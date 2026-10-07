extends Node
class_name EveOrbitCamera

## EVE 自走棋 —— 战术轨道相机控制器
##
## 职责：把「俯角/偏角/缩放」三个状态量做成【可被鼠标拖拽驱动】的轨道相机，
##       并复刻参考程序 eve-fit-lab 的手感（原算法出自 EVE V24.01 客户端）。
##
## ══════════════════════════════════════════════════════════════════════
## 算法出处
## ══════════════════════════════════════════════════════════════════════
##   参考程序 app.js 里有一段注释写得很清楚：
##     "EVE V24.01 client camera constants and update rules, recovered from
##      the local code.ccp files: tacticalCameraController.py, baseCamera.py
##      and cameraUtil.py."
##   也就是说这不是它自己拍的参数，是 EVE 客户端原版手感。所以直接照抄。
##
## ── 参数表（COMBAT_OFFICIAL_CAMERA 原样）─────────────────────────────
##     orbitMoveAttached  .012    拖拽灵敏度（相机贴在船上）
##     orbitMoveDetached  .006    拖拽灵敏度（自由观察模式）
##     orbitSpeed         5       环绕收敛速度（每秒）
##     orbitStopAngle     .0001   吸附停止阈值（弧度）
##     zoomInputScale     .3      滚轮输入到「推进量」的系数
##     wheelScale         .0005   滚轮原始 delta 的缩放
##     wheelPower         1.1     滚轮 delta 的非线性指数
##     zoomSpeed          10      缩放收敛速度（每秒）
##     zoomStopDist       .00001  缩放吸附阈值
##     zoomPower          9       距离-推进量的分配指数（9 = 极不均匀）
##     inertiaSetting     0       惯性设置（0 表示标准）
##     sensitivitySetting 0       灵敏度设置（0 表示标准）
##     minPitch           .05     俯仰限位余量 → limit = PI/2 - .05
##
## ── 为什么「丝滑」= target/current 双值 + 指数收敛 ────────────────────
##
##   最朴素的做法是拖拽时直接 yaw += dx * k。这样有两个手感问题：
##     ① 帧率抖动会直接体现为角度抖动（dx 每帧不等）；
##     ② 松手时画面「啪」地停住，没有收尾。
##
##   EVE 的做法是：拖拽【只改 target】，每帧再让 current 追 target：
##       speed = min(1, orbitSpeed * inertia * dt)
##       current += (target - current) * speed
##   dt = 1/60 时 speed ≈ 0.083 → 每帧走 8% 的差额 → 约 0.25 秒收敛。
##   这带来两个手感特性：
##     ① 帧率无关（dt 参与运算）；
##     ② 松手后有一段平滑的「收拢尾巴」—— 这就是「丝滑」的来源。
##
## ⚠️ 注意这不是匀速动画，是指数收敛：一开始快、越接近越慢。
##    用匀速（move_toward）会得到完全不同的手感 —— 结尾生硬。
##
## ── 另一个关键细节：垂直灵敏度只有水平的一半 ──────────────────────────
##   `targetPitch += move * deltaY / 2`
##   那个 `/2` 是 EVE 原版就有的。原因：玩家横向扫视的幅度远大于纵向，
##   若两者等灵敏，上下会「一碰就翻到底」。
##
## ── 死区 4 像素 ──────────────────────────────────────────────────────
##   参考程序：`if (dragMode === "rotate" && dragDistance <= 4) return;`
##   累积位移没超过 4px 就完全不动相机。
##   作用有两点：① 手指/鼠标微抖不会让画面漂移；
##              ② 区分「点击选中」和「拖拽转视角」——
##                 单击选船时画面对得起，玩家才觉得「点得准」。

# ────────────────────────────────────────────────────────────── 常量

## 拖拽灵敏度（相机贴在船上时）
const ORBIT_MOVE_ATTACHED := 0.012
## 拖拽灵敏度（自由观察 / 第三视角）
const ORBIT_MOVE_DETACHED := 0.006
## 环绕收敛速度（每秒）—— 数值越大越「跟手」，越小越「拖沓」
const ORBIT_SPEED := 5.0
## 环绕吸附停止阈值（弧度）
const ORBIT_STOP_ANGLE := 0.0001

## 缩放收敛的吸附阈值（zoom 是无量纲倍率，量级与弧度不同，不能用同一个阈值）
const ZOOM_STOP := 0.0015

## `_step()` 里 delta 的下限兜底 —— 无头模式下 delta 会是 0，
## 导致所有收敛停滞（详见 `_step` 里的说明）。
const MIN_STEP_DELTA := 1.0 / 60.0

## 滚轮缩放 —— 直接乘法，不是推进量曲线
##
## ══════════════════════════════════════════════════════════════════════
## ⚠️⚠️ 这里做过一次纠错，改动前务必读完（很容易又抄错）
## ══════════════════════════════════════════════════════════════════════
##
## 参考程序里【有两条滚轮路径】，手感完全不同：
##
##   ① 主画布 #combatRadar（战斗场景用的就是这个，@1114584）：
##        zoom = clamp(zoom * Math.exp(-deltaY * .002), .55, 360)
##      —— 纯指数乘法，【瞬时生效】，没有收敛过程。
##
##   ② 独立缩放画布 #zoomCanvas（@1094100）：
##        combatOfficialCameraQueueZoom(event.deltaY)
##      —— 走 eveOfficialCameraZoomBounds / ZoomPropFromValue 那套
##         zoomPower = 9 的推进量曲线，有 zoomSpeed = 10 的收敛。
##
##   我第一版误把 ② 当成滚轮手感抄了进来，结果：
##     - 方向反了（推进量 prop 的语义是「拉到多远」，和 zoom 值反相关）
##     - 多了一层 9 次幂的非线性，手感与参考程序完全不同
##
##   战斗场景要的是 ① —— 就是那句 `zoom * exp(-deltaY * .002)`。
##
## ── 方向核对 ────────────────────────────────────────────────────────
##   浏览器：deltaY < 0 = 向上滚。代入 exp(-deltaY * .002)：
##     上滚 → -deltaY > 0 → exp(+) > 1 → zoom 变大
##   zoom 变大 → distance = range * SCALE / zoom 变小 → 镜头【推近】。
##   所以：上滚 = 推近，下滚 = 拉远。这是常规约定，也符合直觉。
##
## ── 为什么 Godot 侧是「瞬时」而不是「收敛」 ──────────────────────────
##   ① 里没有 target/current 双值 —— 它直接改 zoom 并立刻 redraw()。
##   滚轮本身就是离散的「一格一格」，再叠一层收敛会显得拖沓（「黏」）。
##   而【拖拽转视角】才是需要收敛的那一个（②的 orbit 部分），
##   因为它输入连续、且玩家期待「松手后有收尾」。
##   这两个的差异不是我拍的，是参考程序原本就这么分的。
const WHEEL_ZOOM_SCALE := 0.002

## 俯仰限位余量 —— 防止翻到正下方导致 gimbal 奇异
const MIN_PITCH := 0.05

## 垂直灵敏度系数（EVE 原版就是 1/2）
const PITCH_SENSITIVITY := 0.5

## 拖拽死区（像素）—— 累积位移不超过它就不动相机
const DRAG_DEAD_ZONE := 4.0

## 默认机位（无拖拽时的初始状态）
##
## 与参考程序 combatTacticalCamera 的初始值一致：
##   own 模式     yaw=-.58  pitch=.72  zoom=1
##   target 模式  yaw=自动  pitch=.62  zoom=1.4
##   observer     yaw=自动  pitch=.52
##
## ⚠️ 这里 pitch 是【向上为正】的仰角，和 Godot 的 rotation.x 符号相反！
##    参考程序：camera.y = focus.y + sin(pitch) * distance
##      pitch > 0 → 相机在焦点【上方】→ 俯视 → 这就是我们要的战术视角。
##    Godot：camera.rotation.x = -pitch 才会向下看。
##    换算集中在 apply_to_camera() 里，别在别处再翻一次。
const DEFAULT_PITCH := 0.72    # 弧度 ≈ 41.3°
const DEFAULT_YAW := -0.58     # 弧度 ≈ -33.2°

## 默认缩放倍率（2026-09-28 用户裁决：战斗区的船太小，要"再推近两格滚轮"）
##
## ── 为什么是 1.616074 而不是 1.0 ──────────────────────────────────
##  一格滚轮（`dy = ±120`）经 `zoom *= exp(-dy * 0.002)` 后是 `exp(0.24) = 1.271249`，
##  两格即 `exp(0.48) = 1.616074`。
##  本来 `distance = max_range * 1.52 / zoom` ⇒ zoom 越大越近，
##  所以「推近两格滚轮」= 把默认 zoom 直接乘以 1.616074。
##
##  ⚠️ 改了它必须同步改 `EveBattleArena.BOARD_VIEW_ZOOM`（见那边的注释）：
##     布阵棋盘的**投影尺寸 ∝ BOARD_VIEW_ZOOM × zoom**，
##     两处一起动才能「战斗区推近、棋盘一格不变」。
const DEFAULT_ZOOM := 3.320117   # = exp(1.2)。2026-09-28 用户实机手滚定案

## 缩放上下限（对齐参考程序 eveOfficialCameraZoomBounds(.55, ...)）
const ZOOM_MIN := 0.55
const ZOOM_MAX := 360.0

## 相机取景距离系数（COMBAT_TACTICAL_CAMERA_DISTANCE_SCALE）
##
## distance = max_range * DISTANCE_SCALE / max(0.55, zoom)
## 也就是 zoom=1 时视距是战场最大跨度的 1.52 倍 —— 刚好把全场框进来。
const DISTANCE_SCALE := 1.52

# ────────────────────────────────────────────────────────────── 状态

## 当前值（相机实际使用的值 —— 每帧由 _step 逼近 target）
var yaw: float = DEFAULT_YAW
var pitch: float = DEFAULT_PITCH
var zoom: float = DEFAULT_ZOOM

## 目标值（拖拽只改这里）—— NAN 表示「无待收敛目标」
##
## ⚠️ yaw / pitch 走 target/current 双值是因为「转视角」必须平滑（硬跳会吓人）。
##    zoom 同样如此 —— 见 `set_zoom_target()` 的长注释：
##    **阶段 D 的开战镜头改了 zoom 却没人还原，导致下一轮布阵格子投影全错位。**
var _target_yaw: float = NAN
var _target_pitch: float = NAN
var _target_zoom: float = NAN

## 独立缩放画布用的推进量（0~1）—— 战斗场景的滚轮不走这条路
var _zoom_prop: float = 1.0

## 焦点（相机绕它转）
var focus: Vector3 = Vector3.ZERO

## 取景距离基准（战场最大跨度，单位：世界单位）
var max_range: float = 60.0

## 是否贴在船上（决定用哪档灵敏度）
##
## 参考程序：attached = 相机模式 != "observer"
## 我们没有 observer 模式，但可以暴露给外部按需切换。
var attached: bool = true

## 相机节点
var camera: Camera3D = null

## 上一帧视角是否还在收敛（供外部判断「是否还在动」）
var animating: bool = false

## 拖拽状态
var _dragging := false
var _drag_distance := 0.0
var _last_mouse := Vector2.ZERO

# ────────────────────────────────────────────────────────────── 类型化访问器
#
# ⚠️ 为什么要有这一组 getter/setter，而不是让外部直接读字段：
#    外部（eve_battle_arena.gd）把这个节点声明成了 Node 而不是
#    EveOrbitCamera（原因见那边的注释：无头模式下 class_name 可能未就绪）。
#    在 Node 类型的变量上写 `orion_cam.yaw` 是合法的（动态属性），
#    但拿不到静态类型检查，而且写成 `orion_cam.max_range = x` 这种
#    赋值在严格模式下有风险。给一组显式访问器，两边都干净。

func get_yaw() -> float:
	return yaw

func get_pitch() -> float:
	return pitch

func get_zoom() -> float:
	return zoom

func get_focus() -> Vector3:
	return focus

func set_focus_point(p: Vector3) -> void:
	focus = p
	apply_to_camera()

func get_max_range() -> float:
	return max_range

func set_max_range(v: float) -> void:
	max_range = v

## 是否处于拖拽中（供上层判断鼠标状态）
func is_dragging() -> bool:
	return _dragging

## 本帧是否仍在收敛
func is_animating() -> bool:
	return animating

## 当前距离值
func get_distance() -> float:
	return distance()

## 手动推进一帧（无头验证用 —— 无头时 _process 由引擎驱动，
## 但验证脚本需要精确控制步进节奏）
func step(delta: float) -> bool:
	return _step(delta)

## 按输入幅度直接排入（无头验证用，跳过事件层）
func queue_orbit_rad(dx: float, dy: float) -> void:
	queue_orbit(dx, dy)

## 直接设一个 pitch 目标（无头验证用）—— 用于测试半球翻转这类
## 「需要精确落在某个负角度、又不想撞限位」的场景。
## 走的是与拖拽相同的 target/current 收敛路径，不是硬赋值。
func set_pitch_target(rad: float) -> void:
	if is_nan(_target_pitch):
		_target_pitch = pitch
	var limit := PI * 0.5 - MIN_PITCH
	_target_pitch = clampf(rad, -limit, limit)


## 直接设一个 yaw 目标 —— 「把镜头平滑转到某个方位」的入口。
##
## ⚠️ 与 set_pitch_target 同款：走 target/current 收敛（约 0.25 秒收拢），
##    **不是硬赋值**。硬赋值会让画面「啪」地跳过去，而布阵对齐要求的是
##    「玩家拿起船的那一瞬间，镜头自己转正」—— 必须平滑才不吓人。
##
## 用途：EveBattleArena.align_camera_to_board()（棋盘正对）。
func set_yaw_target(rad: float) -> void:
	if is_nan(_target_yaw):
		_target_yaw = yaw
	_target_yaw = rad


## 平滑收敛到某个缩放倍率（zoom 越大 = 相机越近，见 distance()）。
##
## ══════════════════════════════════════════════════════════════════
##  ⚠️ 为什么必须有它（2026-09-20 阶段 D 回归的根因）
## ══════════════════════════════════════════════════════════════════
##  阶段 D 的开战镜头把 zoom 从 1.0 推到 1.55（推近），而**没有任何路径把它还原**。
##  后果不是"镜头有点近"这么轻 —— 是**下一轮布阵的格子投影全错位**：
##    镜头停在开战取景时，格 (8,5) 投影到 y≈1044，
##    而商店窗的出售区在 y 898~1067 ⇒ **格子被商店窗盖住**。
##    玩家的实际体验：拖船到那一格 → 判定成"拖到出售区" → 船被卖掉。
##    而验收脚本的症状是三条看似无关的断言同时挂
##    （提示没写行号 / 商店亮橙 / 拖放后上场数少了 1）——
##    根因只有一个：**相机没回来**。
##
##  ⇒ 结论：任何"临时改 zoom"的行为都必须配一条"改回来"的路径。
##    这里提供入口，由 show_board_for_deploy() 在布阵开始时收回去。
func set_zoom_target(z: float) -> void:
	if is_nan(_target_zoom):
		_target_zoom = zoom
	_target_zoom = maxf(ZOOM_MIN, z)

## 直接排入缩放（无头验证用）
func queue_zoom_delta(dy: float) -> void:
	queue_zoom(dy)

# ────────────────────────────────────────────────────────────── 生命周期

func bind_camera(cam: Camera3D) -> void:
	camera = cam
	if camera == null:
		return
	_sync_zoom_prop_from_value()
	apply_to_camera()


func _process(delta: float) -> void:
	if camera == null:
		return
	var changed := _step(delta)
	if changed:
		apply_to_camera()


# ────────────────────────────────────────────────────────────── 输入

## 处理一个输入事件，返回是否消费了它
##
## ⚠️ 返回 true 表示「这个事件是相机在用」，调用方不应再拿它做别的事
##    （比如点击选船）。这是区分「拖拽转视角」和「点击选船」的关键。
func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				return _begin_drag(mb.position)
			else:
				var was := _dragging
				_end_drag()
				# 松开时若确实拖过（超过死区），这一下算相机的，不算点击
				return was and _drag_distance > DRAG_DEAD_ZONE
		# 滚轮缩放
		#
		# ⚠️ 方向必须与浏览器对齐：参考程序吃掉的是 event.deltaY，
		#    而 deltaY < 0 表示【向上滚】。公式是 exp(-deltaY * .002)，
		#    所以上滚（deltaY 负）→ zoom 变大 → 镜头推近。
		#    Godot 没有 deltaY，只给 WHEEL_UP / WHEEL_DOWN 两个键，
		#    所以这里反过来映射：WHEEL_UP 送一个负的 deltaY。
		#
		#    ⚠️ 这个符号第一版写反过，症状是「上滚滚成了拉远」——
		#       方位类 bug 在无头测试里不会报错，只会静默反着跑，
		#       所以 verify_camera 里专门有一条方向断言（第 7 组）。
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP
				or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			# 一格 ≈ 120 单位（浏览器上的典型 deltaY 量级）
			var dy := -120.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 120.0
			queue_zoom(dy)
			return true

	if event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		# ⚠️ 必须用 relative 而不是「当前 - 上次」：
		#    Godot 的 relative 已经处理了窗口边界/缩放/高 DPI，
		#    自己相减在缩放窗口下会得到错误的位移。
		var rel := mm.relative
		_drag_distance += rel.length()
		if _drag_distance <= DRAG_DEAD_ZONE:
			return true          # 还在死区内，但事件仍归相机（别去选船）
		queue_orbit(rel.x, rel.y)
		return true

	return false


func _begin_drag(pos: Vector2) -> bool:
	_dragging = true
	_drag_distance = 0.0
	_last_mouse = pos
	return true


func _end_drag() -> void:
	_dragging = false


## 公开的「结束拖拽」入口（验证脚本 / 外部强制中断拖拽用）
func end_drag() -> void:
	_end_drag()


## 目标值读取（验证脚本用 —— 检查排入是否正确）
func get_target_yaw() -> float:
	return _target_yaw

func get_target_pitch() -> float:
	return _target_pitch


# ────────────────────────────────────────────────────────────── 轨道

## 排入一次环绕（拖拽只改 target，不动当前值）
##
## 对应 eveOfficialCameraQueueOrbit(camera, deltaX, deltaY, {attached})
func queue_orbit(dx: float, dy: float) -> void:
	if is_nan(_target_yaw):
		_target_yaw = yaw
	if is_nan(_target_pitch):
		_target_pitch = pitch
	var move := ORBIT_MOVE_ATTACHED if attached else ORBIT_MOVE_DETACHED
	var limit := PI * 0.5 - MIN_PITCH
	# ⚠️ 符号：向右拖 → yaw 减小。
	#    参考程序是 `targetYaw -= move * deltaX`，它在视觉上表现为
	#    「画面跟着鼠标走」（右拖 = 场景右移 = 相机左转）。
	_target_yaw -= move * dx
	_target_pitch = clampf(
		_target_pitch + move * dy * PITCH_SENSITIVITY, -limit, limit)


## 排入一次缩放
##
## 对应参考程序主画布的 `zoom = clamp(zoom * exp(-deltaY * .002), .55, 360)`
##
## ⚠️ 直接改 zoom，不设 target —— 滚轮是离散事件，瞬时响应才跟手。
##    详见 WHEEL_ZOOM_SCALE 上面那段纠错说明。
func queue_zoom(delta_y: float) -> void:
	zoom = clampf(zoom * exp(-delta_y * WHEEL_ZOOM_SCALE), ZOOM_MIN, ZOOM_MAX)
	# 拖拽收敛中的话，缩放要能立刻反映出来
	apply_to_camera()


## 每帧收敛 —— 这是「丝滑」的本体
##
## 对应 eveOfficialCameraStepOrbit。只负责【环绕】的收敛；
## 环绕（yaw/pitch）与缩放（zoom）都在这里收敛。
## 返回是否发生了可见变化。
##
## ⚠️ 缩放的 target/current 是**后加的**（阶段 D 回归的修复，见 `set_zoom_target`）：
##    它必须参与这里，否则「推近了没人拉回来」——
##    而症状会伪装成「格子判定错 / 拖放变出售」等完全无关的断言失败。
func _step(delta: float) -> bool:
	var changed := false
	# ⚠️⚠️ `delta` 必须兜底（2026-09-20 阶段 D 验收挖出的坑）
	#   **无头模式下 `_process` 的 `delta` 会是 0**（帧率不限、每帧耗时计为 0），
	#   于是 speed = 5.0 * 0 = 0 ⇒ `yaw += yaw_left * 0` ⇒ **收敛永远推不动**。
	#   症状极具误导性：`_process` 明明跑了 480 次（探针计数器为证），
	#   而 yaw/zoom 一步没动、target 还挂着，看起来像"信号没接上"或"被谁覆盖了"。
	#   后果不止"转不过去"：**棋盘取景的距离也收敛不了**，
	#   于是格 (8,5) 投影到 y≈1044 —— 正好落进商店窗的出售区，
	#   玩家拖船到格子上会被判定成「拖到出售区」而**把船卖掉**。
	#   ⇒ 给 delta 一个最小步长：无头下取 1/60 秒（等价于 60fps），
	#     真实运行时 delta 本来就在这个量级，行为不变。
	var dt := maxf(delta, MIN_STEP_DELTA)
	var speed := minf(1.0, ORBIT_SPEED * dt)

	# ── 缩放收敛（独立于环绕，两者可同时进行）──
	if not is_nan(_target_zoom):
		var z_left := _target_zoom - zoom
		if absf(z_left) < ZOOM_STOP:
			zoom = _target_zoom
			_target_zoom = NAN
			apply_to_camera()
		else:
			zoom += z_left * speed
			changed = true

	# ── 环绕收敛 ──
	if is_nan(_target_yaw) and is_nan(_target_pitch):
		animating = not is_nan(_target_zoom)
		return changed

	var orbit_active := false
	var ty := yaw if is_nan(_target_yaw) else _target_yaw
	var tp := pitch if is_nan(_target_pitch) else _target_pitch
	var yaw_left := ty - yaw
	var pitch_left := tp - pitch

	if absf(yaw_left) < ORBIT_STOP_ANGLE:
		yaw = ty
	else:
		yaw += yaw_left * speed
		orbit_active = true
		changed = true

	if absf(pitch_left) < ORBIT_STOP_ANGLE:
		pitch = tp
	else:
		pitch += pitch_left * speed
		orbit_active = true
		changed = true

	if not orbit_active:
		# 收敛完毕 —— 清掉 target，让拖拽下次从当前值重新起步
		#
		# ⚠️ 残留量说明：吸附阈值是 EVE 原版的 .0001 弧度（≈0.0057°），
		#    也就是说最终会留下最多 0.0001 rad 的残差。
		#    这是【原版行为】，不是 bug —— 换算到 1080p 上不足半个像素，
		#    肉眼完全不可见。不要为了「绝对归零」把阈值调小，
		#    那会让收敛尾巴无限拉长（指数收敛 + 极小阈值 = 卡在半路）。
		_target_yaw = NAN
		_target_pitch = NAN
		#
		# ⚠️ 但上面两个分支里 `yaw = ty` / `pitch = tp` 是【直接吸附】，
		#    它改了 yaw/pitch 却没有走过 apply_to_camera()。
		#    必须在收敛的最后一帧补一次写入，否则：
		#      · 小幅拖拽（target 位移 < 阈值）时，整次旋转都留着没写进相机
		#        —— 表现为「拖了没反应」；
		#      · 大幅拖拽时，相机永远停在倒数第二帧的位置
		#        —— 表现为「松手后画面差一点点才到位」的黏滞感。
		#    实测抓到的现象：把 pitch 收到 -0.5（确实翻到下半球了），
		#    但相机 y 仍比焦点高 63.90 —— 因为 -0.5 那次吸附没落地。
		apply_to_camera()

	animating = orbit_active or not is_nan(_target_zoom)
	return changed


# ────────────────────────────────────────────────────────────── 相机定位

## 把当前 yaw/pitch/zoom/focus 写进 Camera3D
##
## ── 位置公式（照抄参考程序 combatCameraFrame）─────────────────────
##     distance = maxRange * 1.52 / max(0.55, zoom)
##     cam.x = focus.x + sin(yaw) * cos(pitch) * distance
##     cam.y = focus.y + sin(pitch) * distance
##     cam.z = focus.z + cos(yaw) * cos(pitch) * distance
##
## ── 为什么用 look_at 而不是直接设 rotation ─────────────────────────
##     公式给出的是位置，朝向是「看向 focus」。
##     用 look_at 保证任何 pitch（包括穿过 0 翻到另一侧半球）都朝向焦点。
##     ⚠️ 但 look_at 会带入任意 roll —— 所以必须把 up 固定为 Vector3.UP，
##        并且 pitch 的限位 ±(PI/2 - .05) 正是为了避开 look_at 的奇异点
##        （视线与 up 平行时 look_at 结果退化）。
func apply_to_camera() -> void:
	if camera == null:
		return
	var dist := max_range * DISTANCE_SCALE / maxf(0.55, zoom)
	var offset := Vector3(
		sin(yaw) * cos(pitch),
		sin(pitch),
		cos(yaw) * cos(pitch)) * dist
	camera.position = focus + offset
	camera.look_at(focus, Vector3.UP)
	camera.far = maxf(20_000.0, dist * 30.0)


## 相机到焦点的距离（世界单位）
func distance() -> float:
	return max_range * DISTANCE_SCALE / maxf(0.55, zoom)


## 把焦点移到新位置（位置跟随，但不改角度）
##
## ⚠️ 这是「自动取景跟随」和「手动拖拽」的接合点：
##    跟随只改 focus，绝不碰 yaw/pitch/zoom —— 这样玩家转过的角度不会被抢走。
func set_focus(p: Vector3) -> void:
	focus = p
	apply_to_camera()


# ────────────────────────────────────────────────────────────── 复位

## 复位到默认机位
##
## 参考程序是双击画布触发（dblclick），且会清掉所有收敛目标
## （combatOfficialCameraSyncTargets 把 target 全置 null）。
func reset() -> void:
	yaw = DEFAULT_YAW
	pitch = DEFAULT_PITCH
	zoom = DEFAULT_ZOOM
	_target_yaw = NAN
	_target_pitch = NAN
	_zoom_prop = 1.0
	animating = false
	apply_to_camera()


## 复位，但保留当前的 yaw/pitch（只把缩放回到 1）——
## 用于「重新取景但不想丢失玩家转过的角度」
func reset_zoom_only() -> void:
	zoom = DEFAULT_ZOOM
	_zoom_prop = 1.0
	apply_to_camera()


## 按部署带 / 舰船包围盒自适应视距基准
##
## max_range 是 EVE 的「雷达最大量程」概念 —— 它决定视距，
## 而视距决定「多大范围能被框进画面」。
## 传进来的是世界单位的战场半跨度，这里换算成全跨度。
func set_range_from_half_extent(half_x: float, half_z: float) -> void:
	# 用对角线的一半作为「最远须看到的距离」，再乘 2 得到跨度
	var half_diag := sqrt(half_x * half_x + half_z * half_z)
	max_range = maxf(20.0, half_diag * 2.0)


# ────────────────────────────────────────────────────────────── 缩放数学
#
# ⚠️ 这一整段（推进量映射 / 二分反解 / 带符号幂）是给【独立缩放画布】
#    那条路径留的实现，战斗场景暂时用不到 —— 主画布的滚轮是纯指数乘法，
#    见 WHEEL_ZOOM_SCALE 上面那段纠错说明。
#
#    保留的原因：以后如果要做「舰船装配预览」里的那种精细缩放
#    （需要把「近端」的分辨率压掉，让远端好调），这套 zoomPower=9
#    的映射就是现成的。届时直接调 apply_zoom_prop() 即可。
#
# ── zoomPower = 9 意味着什么（留档）────────────────────────────────
#
#   distance = near + prop^9 * (far - near)
#     prop = 0.0  → distance = near         （最近）
#     prop = 0.5  → near + 0.2% 的行程      ← 几乎没动
#     prop = 0.9  → near + 39%  的行程
#     prop = 1.0  → distance = far          （最远）
#
#   滚轮在「中段」几乎不改变距离，只有推到接近 1 时才猛地拉开。
#   这是刻意的：精细观察 90% 的时间待在近距离，所以把「近」这一端
#   的分辨率做得很细，把「远」这一端压缩掉。

## 距离-推进量的分配指数（独立缩放画布用）
const ZOOM_POWER := 9.0

## 推进量 → zoom 值
func _zoom_value_from_prop(prop: float) -> float:
	var b := _zoom_bounds()
	var p := clampf(prop, b["min_prop"], 1.0)
	var dist: float = b["near"] + pow(p, ZOOM_POWER) * (b["far"] - b["near"])
	return clampf(1.0 / maxf(1e-12, dist), ZOOM_MIN, ZOOM_MAX)


## zoom 值 → 推进量
func _zoom_prop_from_value(value: float) -> float:
	var b := _zoom_bounds()
	var z := clampf(value, ZOOM_MIN, ZOOM_MAX)
	var dist := 1.0 / z
	var span: float = maxf(1e-12, b["far"] - b["near"])
	var linear := clampf((dist - b["near"]) / span, 0.0, 1.0)
	return clampf(pow(linear, 1.0 / ZOOM_POWER), b["min_prop"], 1.0)


## 距离边界（对齐 eveOfficialCameraZoomBounds）
##
## 参考程序用 32 步二分反解 near 距离，是为了保证「推进量下界 minProp
## 对应的距离」与推进量曲线自洽。这里照搬同一个二分。
func _zoom_bounds() -> Dictionary:
	var minimum := ZOOM_MIN
	var maximum := maxf(minimum, ZOOM_MAX)
	var closest := 1.0 / maximum
	var far := 1.0 / minimum
	var low := 0.0
	var high := minf(closest, far)
	for _i in 32:
		var near := (low + high) * 0.5
		var prop := minf(0.2 + near / far, 1.0)
		var dist := near + pow(prop, ZOOM_POWER) * (far - near)
		if dist > closest:
			high = near
		else:
			low = near
	var near_dist := (low + high) * 0.5
	var min_prop := minf(0.2 + near_dist / far, 1.0)
	return {
		"minimum": minimum,
		"maximum": maximum,
		"closest": closest,
		"near": near_dist,
		"far": far,
		"min_prop": min_prop,
	}


func _sync_zoom_prop_from_value() -> void:
	_zoom_prop = _zoom_prop_from_value(zoom)


## 应用一个推进量（独立缩放画布路径的入口）
##
## 供以后做「装配预览」那种需要 zoomPower=9 精细映射的场景调用。
## 战斗场景不用 —— 主画布滚轮走纯指数乘法。
func apply_zoom_prop(prop: float) -> void:
	_zoom_prop = clampf(prop, 0.0, 1.0)
	zoom = _zoom_value_from_prop(_zoom_prop)
	apply_to_camera()


## 当前推进量（只读）
func get_zoom_prop() -> float:
	return _zoom_prop
