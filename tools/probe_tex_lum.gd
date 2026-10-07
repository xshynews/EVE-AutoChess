extends Node

## 直接量「Godot 实际加载到的立绘纹理」的平均亮度。
##
## 存在的理由：改了 assets/*.png 之后，截图可能看不出变化 ——
## 到底是 ①文件没换成功、②import 缓存没刷新、还是 ③画面上看不出来，
## 这三种在截图上完全一样。本探针绕过绘制链路，只读纹理像素，
## 所以它给出的是**唯一可信的判据**。
##
## 跑法：--headless（不需要截图）

const IDS := ["rifter", "slasher", "tempest", "maelstrom", "hurricane", "drake"]


func _ready() -> void:
	print("[TEX] 基准：原图 rifter mean≈19.1/255(0.075)  B档目标≈43/255(0.169)")
	print("[TEX] %-13s %-11s %8s %10s %8s" % ["id", "size", "body", "mean/255", "hi%"])
	for id in IDS:
		var path := "res://assets/ships/%s.png" % id
		var t: Texture2D = load(path)
		if t == null:
			print("[TEX] %-13s NULL（资源加载失败）" % id)
			continue
		var img: Image = t.get_image()
		if img == null:
			print("[TEX] %-13s image 为空" % id)
			continue
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)
		var w := img.get_width()
		var h := img.get_height()
		var data: PackedByteArray = img.get_data()
		var total := data.size()
		var sum := 0.0
		var n := 0
		var hi := 0
		var i := 0
		while i + 3 < total:
			if data[i + 3] >= 128:
				var l := 0.2126 * float(data[i]) + 0.7152 * float(data[i + 1]) \
						+ 0.0722 * float(data[i + 2])
				sum += l
				n += 1
				if l > 204.0:
					hi += 1
			i += 4
		if n == 0:
			print("[TEX] %-13s %dx%d  无主体像素" % [id, w, h])
			continue
		print("[TEX] %-13s %4dx%-6d %8d %10.1f %7.2f%%" % [
			id, w, h, n, sum / float(n), 100.0 * float(hi) / float(n)])
	print("[TEX] ==== DONE ====")
