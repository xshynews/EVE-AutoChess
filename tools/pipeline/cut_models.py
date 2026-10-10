# -*- coding: utf-8 -*-
"""多模型抠图库：u2net(320) / isnet-general-use(1024) / silueta(320)。
统一接口 get_mask(pil)->np.float32[0..1]，与原图同尺寸。
"""
import os
import numpy as np
import onnxruntime as ort
from PIL import Image

MDIR = r"C:\godot\_export\_models"
# (文件名, 输入边长, 预处理)
#   rembg = (x/mean - 1)/std     —— u2net 系
#   raw   = 直接 [0,1]           —— isnet 系（归一化已烤进计算图）
MODELS = {
    "u2net": ("u2net.onnx", 320, "rembg"),
    "isnet": ("isnet-general-use.onnx", 1024, "raw"),
    "silueta": ("silueta.onnx", 320, "rembg"),
}
_SESS = {}
MEAN = (0.485, 0.456, 0.406)
STD = (0.229, 0.224, 0.225)


def _session(key):
    if key not in _SESS:
        fn, _, _ = MODELS[key]
        so = ort.SessionOptions()
        so.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        _SESS[key] = ort.InferenceSession(os.path.join(MDIR, fn), sess_options=so,
                                          providers=["CPUExecutionProvider"])
    return _SESS[key]


def get_mask(pil, model="isnet", size=None):
    fn, dsize, prep = MODELS[model]
    size = size or dsize
    im = pil.convert("RGB").resize((size, size), Image.LANCZOS)
    a = np.array(im).astype(np.float32) / 255.0
    if prep == "raw":
        x = a.transpose(2, 0, 1)[None].astype(np.float32)
    else:
        a = a / max(float(a.max()), 1e-6)
        tmp = np.zeros_like(a)
        for c in range(3):
            # rembg 的归一化约定：(x/mean - 1)/std（不是标准的 (x-mean)/std）
            tmp[:, :, c] = (a[:, :, c] / MEAN[c] - 1.0) / STD[c]
        x = tmp.transpose(2, 0, 1)[None].astype(np.float32)
    sess = _session(model)
    outs = sess.run(None, {sess.get_inputs()[0].name: x})
    # 取空间维度与输入一致的输出
    d = None
    for o in outs:
        arr = np.array(o)
        if arr.ndim == 4 and arr.shape[1] == 1:
            d = arr[0, 0]
            break
    if d is None:
        d = np.array(outs[0])[0, 0]
    d = d.astype(np.float32)
    d = (d - d.min()) / (d.max() - d.min() + 1e-8)
    m = Image.fromarray((d * 255).astype(np.uint8)).resize(pil.size, Image.LANCZOS)
    return np.array(m).astype(np.float32) / 255.0
