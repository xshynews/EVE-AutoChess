extends Node
## ══════════════════════════════════════════════════════════════════════
##  47 轮 · 全库 52 艘 glb **内部残留旋转**普查
## ══════════════════════════════════════════════════════════════════════
##
## ── 背景 ══════════════════════════════════════════════════════════════
##  `probe_worldbow47` 发现：`model`（glb 根）**下面还有一层节点带着旋转**
##  （slasher/catalyst/kestrel = R_x(90°) · incursus/abaddon = R_z(180°) ·
##   myrmidon = R_y(90°) …）。而游戏把轴重映射全部加在 **model 这一层**上，
##  于是「我们以为的舰艏」和「网格几何体的实际朝向」**差着那一层**。
##
##  实测后果：外层读数 `bow·敌向 = 1.000`（自洽假象），
##            含内层读数 = **0.000**（舰艏与敌向垂直）——
##            正是用户 45 轮/47 轮看到的「垂直」+「每艘都不一样」。
##
## ── 本条要产出什么 ════════════════════════════════════════════════════
##  52 艘逐艘打印：内部旋转的**轴角表示**，并统计分布。
##  「全都一样」⇒ 一个常量就能修；「各不相同」⇒ 必须在 `instantiate` 里
##  把它**烘焙掉**（把内层的旋转提升到 model 自己的 basis 里）。
##
## 跑法：
##   `--headless --path <工程> --quit-after 200 res://tools/probe_innerrot47.tscn`
const MODEL := preload("res://scripts/visual/eve_ship_model.gd")

const IDS := [
	"abaddon", "algos", "apocalypse", "arbitrator", "atlantic", "bantam",
	"bellicose", "burst", "catalyst", "celestis", "condor", "cormorant",
	"corax", "crucifier", "dominix", "executioner", "exequror", "ferox",
	"garmur", "gnosis", "heretic", "heron", "incursus", "inquisitor",
	"kestrel", "maelstrom", "magnate", "maller", "megathron", "merlin",
	"myrmidon", "navitas", "omen", "osprey", "punisher", "raven",
	"rifter", "rook", "scythe", "slasher", "stabber", "talos",
	"thorax", "tristan", "typhoon", "vexor", "vigil", "vindicator",
	"worm", "wreathe", "zealot", "tempest",
]

func _ready() -> void:
	print("═══ 47 轮 · 52 艘 glb 内部残留旋转普查 ═══")
	print("%-12s | %-8s | %-22s | %s" % ["ship", "angle", "axis", "basis"])
	var buckets: Dictionary = {}
	var missing: Array[String] = []
	var n := 0
	for id in IDS:
		var m: Node3D = MODEL.instantiate(StringName(id))
		if m == null:
			missing.append(id)
			continue
		var inner := _inner_rot(m)
		var q := Quaternion(inner)
		var ang := rad_to_deg(q.get_angle())
		var ax := q.get_axis()
		print("%-12s | %7.2f° | (%+.3f,%+.3f,%+.3f) | %s"
				% [id, ang, ax.x, ax.y, ax.z, _fmt(inner)])
		var bucket := _bucket(inner)
		buckets[bucket] = int(buckets.get(bucket, 0)) + 1
		n += 1
		m.queue_free()
	print("── 共 %d 艘 ──" % n)
	print("── 分桶 ──")
	for k in buckets:
		print("   %-28s %d 艘" % [k, buckets[k]])
	if missing.size() > 0:
		print("⚠️ 加载失败：%s" % ", ".join(missing))

func _fmt(b: Basis) -> String:
	# 用一行紧凑表示：三列各自取最接近的 ±轴
	return "X%+d Y%+d Z%+d | %s" % [1, 1, 1, str(b).replace("\n", " ")]

func _bucket(b: Basis) -> String:
	var q := Quaternion(b)
	var ang := roundf(rad_to_deg(q.get_angle()))
	var ax := q.get_axis()
	var a := "%.3f,%.3f,%.3f" % [snappedf(ax.x, 0.001), snappedf(ax.y, 0.001), snappedf(ax.z, 0.001)]
	return "%.0f° @ (%s)" % [ang, a]

## 把 model 之下所有子节点的旋转连乘 —— glb 内部那一层。
func _inner_rot(model: Node3D) -> Basis:
	var acc := Basis.IDENTITY
	for c in model.get_children():
		var n3 := c as Node3D
		if n3 == null:
			continue
		acc = acc * n3.transform.basis.orthonormalized()
	return acc.orthonormalized()
