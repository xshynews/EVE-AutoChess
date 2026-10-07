extends Node

## 舰船可视节点体检 —— 量每艘船的实际世界尺寸
##
## 跑法：
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" --headless \
##     --path "F:/evezzq/eve自走棋918" --quit-after 400 \
##     res://tools/probe_ship_scale.tscn
##
## 背景：换上真实 GLB 模型后实机画面出现「一层巨大几何体罩住镜头」，
## 天空盒被挡死。仅凭截图分不清是哪艘船被放大了，所以逐个量：
##   ① 索引里记的 max_dim_m（归一化的分母）
##   ② 模型节点自身的 scale
##   ③ hull_root 的**世界包围盒** —— 这才是真正决定它占多大屏的量
## 正常情况下每艘船的世界尺寸都应落在 1.5~3.5 世界单位
## （HULL_REF_LENGTH 2.6 × 吨位档 0.70~1.35）。

const SCENE_PATH := "res://scenes/battle_scene.tscn"

var _battle: Node = null
var _frame := 0


func _ready() -> void:
	var ps: PackedScene = load(SCENE_PATH)
	_battle = ps.instantiate()
	add_child(_battle)


func _process(_dt: float) -> void:
	_frame += 1
	if _frame < 45:
		return
	_dump()
	get_tree().quit()


func _dump() -> void:
	var arena = _battle.get("arena")
	var nodes: Dictionary = arena.get("_ship_nodes")
	print("═══ 舰船可视体检（%d 艘）═══" % nodes.size())
	print("%-13s %-9s %-9s %-11s %-9s %s"
			% ["ship_key", "索引max_m", "模型有?", "模型scale", "档位x夸张", "世界包围盒尺寸"])

	var worst := ""
	var worst_sz := 0.0
	for id in nodes.keys():
		var v = nodes[id]
		if v == null or not is_instance_valid(v):
			continue
		var sk := String(v.get("ship").ship_key)
		var hr = v.get("hull_root")
		var max_m := EveShipModel.max_dim_m(sk)
		var has_model := EveShipModel.has_model(sk)
		var mscale := 0.0
		var info := ""
		if hr != null:
			for c in hr.get_children():
				if String(c.name).begins_with("Model_"):
					mscale = c.scale.x
					break
			var acc := AABB()
			var has := false
			for mi in _meshes(hr):
				var a: AABB = mi.get_aabb()
				var xf: Transform3D = mi.global_transform
				for i in 8:
					var w := xf * a.get_endpoint(i)
					if not has:
						acc = AABB(w, Vector3.ZERO)
						has = true
					else:
						acc = acc.expand(w)
			if has:
				info = "%.2f × %.2f × %.2f" % [acc.size.x, acc.size.y, acc.size.z]
				var mx: float = maxf(acc.size.x, maxf(acc.size.y, acc.size.z))
				if mx > worst_sz:
					worst_sz = mx
					worst = sk
		print("%-13s %-9.1f %-9s %-11.3f %-9.3f %s"
				% [sk, max_m, "有" if has_model else "无", mscale,
				hr.scale.x if hr != null else 0.0, info])

	print("")
	print("最大的一艘：%s  世界尺寸 %.2f" % [worst, worst_sz])
	print("健康区间：1.5 ~ 3.5 世界单位（HULL_REF_LENGTH 2.6 × 档位 0.70~1.35）")
	if worst_sz > 6.0:
		print("!! 有船被放大了 —— 归一化的分母（max_dim_m）不对")
	print("═══ 结束 ═══")


func _meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out
