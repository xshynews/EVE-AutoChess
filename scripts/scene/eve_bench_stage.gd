extends Node3D
class_name EveBenchStage

## EVE 自走棋 —— 备战席 3D 舰船层
##
## ╔══════════════════════════════════════════════════════════════════╗
## ║  ⚠️⚠️ 2026-09-23 起【已停用】—— 本文件保留仅为便于回退。        ║
## ╚══════════════════════════════════════════════════════════════════╝
##
## 停用原因（用户口径）：「把备战席的船也改为 2D 立绘卡牌吧，现在这样特别
## 别扭，尤其是放上去的模型朝向还不一样」。
##
## 备战席上的船现在由 EveBenchRail 在自己的 _draw() 里画**官方立绘**，
## 一次性解决了两件事：
##   ① **压暗** —— 本层是 3D，画在 HUD **之下**，所以格底每加一分不透明度
##      就是给站在格子里的船蒙一层黑（实测格底 0.40 时船暗到读不出来，
##      症状是「点购买后像是船没上备战席」）。2D 立绘与格底同在一次 _draw、
##      且后画 —— 这个坑从结构上消失。
##   ② **清晰度** —— 立绘是抠像 + 面积归一化过的图，比缩放的 3D 模型更易辨认。
##
## ⚠️ 但它**没有**解决朝向：3D 模型自身的建模朝向逐船不同，
##    而这正是本层当年「有的船横躺、有的船竖着」的根因。
##    换官方立绘后同一个根因**依然存在**（立绘视角也跟着模型朝向走，
##    实测 52 艘里横构图与竖构图约各占一半）——
##    要看全貌跑 tools/probe_ship_art.tscn。真正的修法是**统一朝向的立绘**
##    （自渲染管线）或**逐船朝向标定表**，两者都还没做。
##
## ── 恢复本层的步骤 ────────────────────────────────────────────────
##   ① EveBattleArena._ready() 里取消那三行的注释（含 BENCH_STAGE_SCRIPT 的 preload）
##   ② EveBattleArena.bench_stage 的类型标注从 Node 改回 EveBenchStage
##   ③ battle_scene 里 `hud.set_bench_fleet(...)` 换回
##      `arena.bench_stage.update_fleet(run.bench_entries())`（外加 != null 守卫）
##   ④ 先解决朝向（否则回到停用前的观感）
##
## ══════════════════════════════════════════════════════════════════
##  停用前的能力（保留原文，供回退时判断是否仍适用）
## ══════════════════════════════════════════════════════════════════
##  2026-09-22 改版后：「8 个看得见的方格，3D 建模脚底踩在格面上」
##                    （见 EveBenchRail 的头注释）
##
## 所以备战席上的船是**真的 3D 模型**，踩在格子上 ——
## 而立绘只出现在商店卡片里，两者不混。
##
## ── 怎么把 3D 钉在一排 2D 的格子上 ──────────────────────────────
##    用 `Camera3D.project_position(屏幕点, 深度)` 反投影：
##    给一个屏幕坐标 + 一个「离相机多远」，就得到该处的世界坐标。
##
##    于是每个槽位的位置 = 格带上该格中心点的【屏幕坐标】+ 固定深度。
##    这样做的三个好处，比「把船摆在世界空间某个 z」都强：
##      ① 船脚**恒定踩在格面上** —— 因为屏幕坐标是直接给格带的；
##      ② 屏幕尺寸恒定 —— 深度固定 ⇒ 距离固定 ⇒ 不会因为镜头缩放变大变小；
##      ③ 永远不被战场遮挡 —— 它比整个战场都近。
##
## ── 为什么是「相机对齐」而不是「世界对齐」──────────────────────
##    节点基向量直接抄相机的基向量（列 0 = 相机右、列 1 = 相机上），
##    所以船头永远指向屏幕右侧、不会被转视角转歪。
##    然后在相机空间里补一个小 yaw + 小 pitch，得到和立绘一样的 3/4 侧视。
##
## ⚠️ 它挂在一个 Node3D 下、不由 CanvasLayer 管，所以「HUD 隐藏」时
##    它不会跟着藏 —— 需要一起藏时调 `set_hud_visible(false)`。
##
## 变更清单：
##   - configure(camera, rail_rect)：把相机与轨道的屏幕矩形接进来
##   - update_fleet(entries)：entries = [{"ship_key": StringName, "star": int}]
##   - 每帧重算位置/朝向/缩放（相机在动，所以必须每帧算）

const SLOTS := 8

## 格带几何的唯一真相源在 EveBenchRail（`cell_area()`）——
## 这里只借它的常量与静态函数，**不另存一份**格子边距。
const BENCH_RAIL_SCRIPT := preload("res://scripts/ui/panels/eve_bench.gd")

## 设计分辨率 —— 轨道矩形是按 1920×1080 给的，这里换算成实际视口比例
const DESIGN := Vector2(1920.0, 1080.0)

## 舰船离相机的距离（世界单位）。
## 取 12：比战场（30~60 单位）近得多，所以永远画在最前面；
## 又远大于 near(0.5)，不会被裁掉。
const BENCH_DEPTH := 12.0

## 归一化后的目标【屏幕长度】（设计像素）。
##
## ⚠️ 2026-09-22 二次改版：130 → 168。
##    首版取 130 只比旧版（118）大 10%，船在 140px 高的格子里几乎看不出变化。
##    168 让船体真正「占住」这一格（船翼略压过格线，与「飞船停在格上」的读法一致）。
const TARGET_LEN_PX := 168.0

## 3/4 侧视：先在相机空间绕上轴偏一点（船头朝右前方），再压低一点看得到甲板
const BENCH_YAW_DEG := -24.0
const BENCH_PITCH_DEG := 11.0

## 船脚落在格子内的纵向比例（0 = 格顶，1 = 格底）。
##
## ⚠️ 为什么不是「贴着格底」（首版 `FOOT_LIFT_PX = 6` 的语义）：
##    船是**横躺的飞船**，屏幕高宽比约 1:2.6，而格子约 1.18:1 ——
##    船在纵向上**永远填不满**格子。把脚钉在格底时整艘船只占格子的下半截，
##    读作「趴在格沿上」而不是「停在这一格里」。
##
## ⚠️ 这条是**实测踩过坑**才改的，症状极隐蔽：
##    首版 base_y = 「控件底边往上 6px」——格带从 52 长到 140 时它是**向下**长高的
##    （顶 838→760，底只从 890→900），所以船脚只从 888 挪到 894，**几乎没动**。
##    玩家报「点购买后船还停在改版前的地方」——说的就是这个 6px 的位移。
##    现在改为按**格子几何**落点，格带再长高船也会跟着进格子。
const FOOT_IN_CELL := 0.72

var camera: Camera3D = null
var rail_rect := Rect2(360, 760, 1200, 140)

## 玩家正拿起的那一格（-1 = 没有）。
##
## 该格的 3D 舰船临时隐藏 —— 视觉上就是「从轨道上被拿起来了」。
## 拖动期间鼠标处只有 HUD 层那个小幽灵标签（名称★n ◆c），
## 不再放第二艘 3D 船：投影到世界里的第二艘船会跟着相机变大小，
## 而玩家此刻盯着的是屏幕上的落格，两种尺寸语言混在一起反而乱。
var hidden_index: int = -1

var _slots: Array[Node3D] = []
var _keys: Array[String] = []
var _hud_visible := true


func configure(p_camera: Camera3D, p_rail_rect: Rect2) -> void:
	camera = p_camera
	rail_rect = p_rail_rect


## 喂一份备战席名单。entries 元素 = {"ship_key": StringName, "star": int}
##
## 只在「名单变了」时重建节点；位置与朝向由 _process 每帧算。
func update_fleet(entries: Array) -> void:
	var want: Array[String] = []
	for e in entries:
		var k := ""
		if e is Dictionary:
			k = String((e as Dictionary).get("ship_key", ""))
		want.append(k)
	if want == _keys:
		return

	for n in _slots:
		if is_instance_valid(n):
			# ⚠️ 必须显式 remove_child：queue_free 是**延迟到本帧末**执行的，
			#    只调它的话，紧接着的 get_child_count() 会把「待删的旧槽位」
			#    和「刚建的新槽位」加在一起（实测 2 个槽位报成 3 个）。
			remove_child(n)
			n.queue_free()
	_slots.clear()
	_keys = want

	for i in want.size():
		if i >= SLOTS:
			break
		var k := want[i]
		var holder := Node3D.new()
		holder.name = "Bench_%d_%s" % [i, k]
		add_child(holder)
		_slots.append(holder)
		if k.is_empty():
			continue
		var model := EveShipModel.instantiate(StringName(k))
		if model == null:
			# 没有 3D 资产的船（理论上 52/52 都有）—— 留一个空节点，
			# 不画占位方块：备战席上出现一个陌生几何体比什么都不放更糟。
			continue
		holder.add_child(model)
		holder.set_meta(&"ship_key", StringName(k))
		holder.set_meta(&"dim_m", EveShipModel.max_dim_m(StringName(k)))

	_apply_visibility()
	_apply_hidden()


## 设置「正被拿起」的槽位（-1 = 没有）
##
## 该槽的 3D 舰船临时隐藏 —— 视觉上就是「从轨道上被拿起来了」。
func set_hidden_index(i: int) -> void:
	if hidden_index == i:
		return
	hidden_index = i
	_apply_hidden()


func _apply_hidden() -> void:
	for i in _slots.size():
		var h := _slots[i]
		if is_instance_valid(h):
			h.visible = (i != hidden_index)


func _process(_dt: float) -> void:
	if camera == null or _slots.is_empty():
		return
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 1.0 or vp.y <= 1.0:
		return

	var sx := vp.x / DESIGN.x
	var sy := vp.y / DESIGN.y
	var slot_w := rail_rect.size.x * sx / float(SLOTS)
	var x0 := rail_rect.position.x * sx
	# 船脚所在的 y：**格区**内部按比例取（不是「控件底边往上固定量」）。
	# ⚠️ 用 EveBenchRail.cell_area() 而不是自己再算一遍 CELL_TOP / CELL_BOTTOM：
	#    两个文件各算一份必然漂移（首版就是这么踩的，见 FOOT_IN_CELL 注释）。
	var area: Rect2 = BENCH_RAIL_SCRIPT.cell_area(rail_rect.size)
	var base_y := (rail_rect.position.y + area.position.y
			+ area.size.y * FOOT_IN_CELL) * sy

	# 固定深度下「1 像素等于多少世界单位」：竖直 FOV 固定（keep_aspect 默认 KEEP_HEIGHT）
	var world_per_px := 2.0 * BENCH_DEPTH * tan(deg_to_rad(camera.fov) * 0.5) / vp.y
	var target_len_world := TARGET_LEN_PX * sx * world_per_px
	var basis := _bench_basis()

	for i in _slots.size():
		var holder := _slots[i]
		if not is_instance_valid(holder) or holder.get_child_count() == 0:
			continue
		var cx := x0 + (float(i) + 0.5) * slot_w
		var p := camera.project_position(Vector2(cx, base_y), BENCH_DEPTH)
		var dim: float = holder.get_meta(&"dim_m", 0.0)
		var s := 1.0
		if dim > 0.001:
			s = target_len_world / dim
		holder.global_transform = Transform3D(basis.scaled(Vector3.ONE * s), p)


## 相机对齐 + 3/4 侧视的基向量
func _bench_basis() -> Basis:
	var b := camera.global_transform.basis.orthonormalized()
	b = b.rotated(b.y, deg_to_rad(BENCH_YAW_DEG))
	b = b.rotated(b.x, deg_to_rad(BENCH_PITCH_DEG))
	return b.orthonormalized()


func set_hud_visible(on: bool) -> void:
	_hud_visible = on
	_apply_visibility()


func _apply_visibility() -> void:
	visible = _hud_visible
