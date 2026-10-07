extends Node
## ══════════════════════════════════════════════════════════════════════
##  47 轮 · 定位「**网格几何体到底挂在哪个节点**」
## ══════════════════════════════════════════════════════════════════════
##
## ── 为什么必须先弄清这个才能改 ═══════════════════════════════════════
##  `probe_worldbow47` 的 `_inner_rot()` 把 model 下**所有**子节点旋转连乘，
##  得到一个"内部旋转" —— 但那可能混进了碰撞体 / 挂点 / 相机节点，
##  **不能直接当成几何体的朝向**（那正是"复刻漂移"）。
##
##  唯一安全的做法：**找到真正的 `MeshInstance3D`**，读它的
##  `global_transform.basis`，再乘 `bow_local`。
##  引擎会把「visual.quaternion ∘ hull_root(scale) ∘ model.basis ∘
##  中间层 ∘ mesh 节点自身」整条链算完 —— **我一个乘号都不写**。
##
## 跑法：
##   `--headless --path <工程> --quit-after 200 res://tools/probe_meshnode47.tscn`
const IDS := [
	"abaddon", "algos", "catalyst", "incursus", "kestrel", "myrmidon",
	"slasher", "tristan", "omen", "raven", "rifter", "thorax", "vexor",
]

func _ready() -> void:
	print("═══ 47 轮 · 网格节点层级普查 ═══")
	for id in IDS:
		_print_tree(StringName(id))

func _print_tree(id: StringName) -> void:
	var MODEL := load("res://scripts/visual/eve_ship_model.gd")
	var m: Node3D = MODEL.instantiate(id)
	if m == null:
		print("── %s：加载失败" % id)
		return
	print("── %s ──" % id)
	_dump(m, 0, m)
	m.queue_free()

func _dump(n: Node, depth: int, root: Node3D) -> void:
	var pad := "  ".repeat(depth)
	var kind := n.get_class()
	var extra := ""
	if n is Node3D:
		var b: Basis = (n as Node3D).transform.basis
		extra = " basis=%s" % _fmt(b)
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		extra += " mesh=%s" % (mi.mesh.get_class() if mi.mesh != null else "null")
	print("%s%s [%s]%s" % [pad, n.name, kind, extra])
	if depth >= 4:
		return
	for c in n.get_children():
		_dump(c, depth + 1, root)

func _fmt(b: Basis) -> String:
	var q := Quaternion(b.orthonormalized())
	var ang := rad_to_deg(q.get_angle())
	return "%d°@(%.2f,%.2f,%.2f)" % [roundi(ang), q.get_axis().x, q.get_axis().y, q.get_axis().z]
