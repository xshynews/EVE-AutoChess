extends RefCounted
class_name EveShipModel

## EVE 自走棋 —— 3D 舰船模型取用
##
## ══════════════════════════════════════════════════════════════
## 主键 = **ship id**，与立绘 EveShipArt 完全同一个键
## ══════════════════════════════════════════════════════════════
##
## 用户的要求：「别最后我点的惩罚者级的立绘，上去的是其他船就糟糕了」。
## 所以本类**只提供按 id 取模型**这一种入口，没有任何"按名字/按顺序/按类型"
## 的取法可供误用：
##
##     立绘   res://assets/ships/<id>.png      ← EveShipArt.portrait(id)
##     模型   res://assets/ships3d/<id>.glb    ← EveShipModel.scene(id)
##
## 两条路径的 `<id>` 是同一个字符串（= EveShip.ship_key
## = EveShipTable 的 id 列 = EveShipAssetIndex.by_id 的键）。
## 只要调用方两个地方都传 `ship.ship_key`，**结构上不可能取到别的船**。
##
## 想要更硬的保证就跑 `tools/verify_ship_assets.tscn`：
## 它会把 52 个 .glb 真载进引擎量包围盒，与索引里记的尺寸比对 ——
## 文件名正确但内容装错船的情况只有这一步能抓出来。
##
## 变更清单：
##   - scene() / has_model() / instantiate() / max_dim_m() 四个静态入口
##   - 命中/未命中都进缓存（未命中别每帧去探磁盘）
##   - instantiate() 不设 scale（由调用方决定挂哪、多大），
##     但**默认顺带做材质还原**（EveShipMaterial）—— glb 的金属度/粗糙度是退化的
##   - 另见 EveShipMaterial（材质）与 EveShipArt（2D 立绘），三者同一个主键

## 模型所在目录（文件名 = <id>.glb，见 _install_ship_models.py 的强制改名）
const DIR := "res://assets/ships3d/"
const EXT := ".glb"


## Key = ship id，Value = PackedScene 或 null。
## ⚠️ 未命中也要缓存：否则每帧对同一个不存在的路径做 ResourceLoader.exists
##    会变成持续的磁盘探测（52 艘轮着画一遍就是一帧 52 次 stat）。
static var _cache: Dictionary = {}


## 取一艘船的 3D 场景。没有资源时返回 null（调用方负责退回占位体）。
static func scene(ship_id: StringName) -> PackedScene:
	var k := String(ship_id)
	if k.is_empty():
		return null
	if _cache.has(k):
		return _cache[k]
	var path := DIR + k + EXT
	var ps: PackedScene = null
	if ResourceLoader.exists(path):
		var r: Resource = load(path)
		if r is PackedScene:
			ps = r
	_cache[k] = ps
	return ps


static func has_model(ship_id: StringName) -> bool:
	return scene(ship_id) != null


## 实例化一艘船。返回 Node3D（调用方自己 add_child），没有模型时返回 null。
##
## 做两件事：
##   ① 把场景实例化出来
##   ② `upgrade_material`（默认开）= 把退化掉的 glb 材质换成
##      `ship_hull.gdshader`（ramp 复现 Blender 的 metallic / roughness）。
##      详见 EveShipMaterial 的类注释 —— 不换的话白甲板会发银灰、金饰发哑。
##      缺 `_s` 图时它会自动放弃并保留原材质（不会把船变成一面镜子）。
##
## **不**设 scale：因为"多大"取决于挂在哪个场景里（棋盘 / 备战席 / 档案窗差
## 很多），归一化尺度由调用方用 `max_dim_m()` 自己算。
static func instantiate(ship_id: StringName, upgrade_material := true) -> Node3D:
	var ps := scene(ship_id)
	if ps == null:
		return null
	var n: Node = ps.instantiate()
	if n == null:
		return null
	var out: Node3D = null
	if n is Node3D:
		out = n as Node3D
	else:
		# glb 的根不是 Node3D 的极端情况：套一层，保证调用方拿到 Node3D
		var wrap := Node3D.new()
		wrap.name = "ShipModel_%s" % String(ship_id)
		wrap.add_child(n)
		out = wrap
	if upgrade_material:
		EveShipMaterial.apply(out, ship_id)
	return out


## 这艘船模型的**最大外廓尺寸（米）**，数据来自 EveShipAssetIndex。
##
## 用途：把模型归一化到统一的视觉长度 ——
##   `scale = 目标长度(世界单位) / max_dim_m(id)`
##   ⚠️ **分母不乘任何米制换算**：glb 的米在 Godot 里就是 1:1 的世界单位，
##      模型的 mesh 尺寸本身已经是「世界单位」数。
##      乘以 METERS_PER_UNIT(1000) 会把船放大一千倍（踩过，见 eve_ship_visual.gd）。
## ⚠️ 不要用固定缩放去乘所有船：EVE 的模型横跨 17 m（护卫）~ 1529 m（战列），
##    差 90 倍。固定缩放会让战列舰把整个战场糊满。这与 2D 立绘踩过的坑是同一条
##    （见 MEMORY：立绘按 alpha 包围盒归一化，否则同级两艘护卫舰差一倍）。
static func max_dim_m(ship_id: StringName) -> float:
	var a := EveShipAssetIndex.by_id(ship_id)
	if a == null:
		return 0.0
	var m := 0.0
	for v in a.dims:
		m = maxf(m, v)
	return m
