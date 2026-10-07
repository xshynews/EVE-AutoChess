extends RefCounted
class_name EveDestinyMotion

## EVE 自走棋 —— 运动学（Destiny Ballpark 公式的 GDScript 移植）
##
## 公式来源：CCP Games 官方开源运动引擎 Carbon/Destiny（MIT License）
##           https://github.com/carbonengine/destiny
## 移植自 eve-fit-lab 的 destiny-motion.js（同为该开源库的浏览器端适配）
##
## 核心思想：EVE 的船不是"瞬移到目标"，而是用推力对抗惯性阻尼。
##   drag_rate   = friction / (mass * agility)     惯性阻尼率
##   decay       = exp(-drag_rate * dt)
##   速度积分用「终末速度 + 瞬态」两项：
##     position += terminal*dt + transient*(1-decay)/rate
##     velocity  = terminal + transient*decay
##
## 变更清单（初版）：
##   - integrate_body   惯性积分
##   - goto_thrust      直线接近
##   - follow_thrust    保持指定距离
##   - orbit_thrust     环绕（切向接近，用于"角速度"玩法）
##   - velocity_thrust  速度匹配
##   - 五种姿态 command_to_acceleration

const DEFAULT_FRICTION := 1_000_000.0
const DEFAULT_STEP := 1.0 / 30.0
const EPSILON := 1e-9

## 战斗体（船的物理状态）
class Body:
	var id: int = 0
	var position: Vector3 = Vector3.ZERO
	var previous_position: Vector3 = Vector3.ZERO
	var velocity: Vector3 = Vector3.ZERO
	var acceleration: Vector3 = Vector3.ZERO
	var max_speed: float = 0.0
	var speed_fraction: float = 1.0
	var mass: float = 1_000_000.0
	var agility: float = 1.0
	var radius: float = 0.0
	## ★ 45 轮：**指向当前目标的单位向量**（模拟层每 tick 写入，视觉层只读）。
	##
	## 为什么挂在 Body 上、而不是让视觉层自己去选目标：
	##   ① 选目标的逻辑（射程 / 威胁 / 锁定）只在 `eve_battle_simulator` 里有一份
	##      ⇒ 视觉层复刻一份必然漂移（红线 40：不许自己复刻算式）；
	##   ② 「舰艏朝谁」与「炮口朝谁」必须是同一个方向，否则会出现
	##      「船头指着 A、炮打 B」这种看着就不对的画面。
	## 零向量 = 本 tick 没有目标 ⇒ 视觉层退回"舰艏朝速度方向"。
	var aim_dir: Vector3 = Vector3.ZERO

	func _init(p_id: int = 0) -> void:
		id = p_id

	## 当前速度占最大速度的比例（0~1），用于 HUD 显示
	func speed_ratio() -> float:
		if max_speed <= 0.0:
			return 0.0
		return clampf(velocity.length() / max_speed, 0.0, 1.0)

	## 是否在移动（阈值 5%）
	func is_moving() -> bool:
		return velocity.length() > max_speed * 0.05


# ---------------------------------------------------------------- 基础量

## 惯性阻尼率
static func drag_rate(body: Body, friction: float = DEFAULT_FRICTION) -> float:
	return maxf(EPSILON, friction / maxf(EPSILON, body.mass * body.agility))


## 速度衰减因子（dt 秒后保留多少速度）
static func time_factor(body: Body, dt: float, friction: float = DEFAULT_FRICTION) -> float:
	return exp(-drag_rate(body, friction) * maxf(0.0, dt))


## 最大加速度（受质量、敏捷、speed_fraction 限制）
static func maximum_acceleration(body: Body, friction: float = DEFAULT_FRICTION) -> float:
	return drag_rate(body, friction) * body.speed_fraction * body.max_speed


# ---------------------------------------------------------------- 积分

## 惯性积分 —— 这是"船感"的来源
static func integrate_body(body: Body, acceleration: Vector3, dt: float,
		friction: float = DEFAULT_FRICTION) -> void:
	var seconds := maxf(0.0, dt)
	if seconds <= 0.0:
		return
	body.previous_position = body.position

	var rate := drag_rate(body, friction)
	var decay := exp(-rate * seconds)

	# 终末速度：推力的稳态速度
	var terminal_velocity := acceleration / rate
	var transient := body.velocity - terminal_velocity

	# 位置积分：稳态位移 + 瞬态衰减位移
	body.position += terminal_velocity * seconds + transient * ((1.0 - decay) / rate)
	body.velocity = terminal_velocity + transient * decay
	body.acceleration = acceleration

	# 速度上限保护
	var speed := body.velocity.length()
	if body.max_speed > 0.0 and speed > body.max_speed:
		body.velocity = body.velocity * (body.max_speed / speed)


# ---------------------------------------------------------------- 姿态求解

## 直线接近目标点（返回所需加速度方向与大小）
##
## ⚠️ 关键点：这里必须按距离**缩放推力比例**，不能无脑给满推力。
##   原因：本积分器是「速度求解器」—— 加速度 a 会收敛到终末速度 a/rate。
##   若恒定给满加速度 max_accel，船的稳态速度恒为 max_speed，
##   而终端速度与位置误差无关 → 一旦越过目标点就来回过冲，
##   表现为舰队互相「弹开」而不是交战。
##   正确做法（也是 EVE 客户端的做法）：用一个与距离成正比的期望速度，
##   再反解出需要的加速度。这样船才会「先冲、近了减速、到点停住」。
static func goto_thrust(body: Body, target: Vector3, dt: float = DEFAULT_STEP,
		friction: float = DEFAULT_FRICTION) -> Vector3:
	var delta := target - body.position
	var distance := delta.length()
	if distance <= EPSILON:
		return -body.velocity * drag_rate(body, friction)   # 到点了就刹住

	var rate := drag_rate(body, friction)
	var max_accel := maximum_acceleration(body, friction)

	# 期望速度：距离越远越快，进入「制动距离」后线性衰减到 0
	# 制动距离取惯性滑行距离的量级，保证不会冲过头
	var stop_distance := maxf(body.radius * 4.0, body.max_speed / maxf(EPSILON, rate))
	var desired_speed := body.speed_fraction * body.max_speed * clampf(distance / stop_distance, 0.0, 1.0)

	# 反解所需加速度：让稳态速度等于 desired_speed
	var accel_mag := desired_speed * rate
	accel_mag = minf(accel_mag, max_accel)
	return delta.normalized() * accel_mag


## 保持与目标船的指定距离
##
## desired_range 是「相对距离」，orbit/follow 都基于它。
## 注意目标点的取法：若当前距离 > 期望，应向目标**内部**插一个点；
## 若当前距离 < 期望，应向**外侧**插点。这样 follow 既能追也能退。
static func follow_thrust(body: Body, target_body: Body, desired_range: float,
		dt: float = DEFAULT_STEP, friction: float = DEFAULT_FRICTION) -> Vector3:
	var delta := body.position - target_body.position
	var distance := delta.length()
	var range := maxf(0.0, desired_range) + body.radius + target_body.radius

	# 退化保护：几乎重合时给一个确定的外推方向，避免 normalized() 变 NaN
	var away: Vector3
	if distance <= EPSILON:
		away = Vector3(0.0, 0.0, 1.0) if body.id % 2 == 0 else Vector3(0.0, 0.0, -1.0)
	else:
		away = delta / distance

	var target := target_body.position + away * range
	return goto_thrust(body, target, dt, friction)


## 速度匹配推力（用于手动指定相对速度）
static func velocity_thrust(body: Body, desired_velocity: Vector3, dt: float = DEFAULT_STEP,
		friction: float = DEFAULT_FRICTION) -> Vector3:
	var rate := drag_rate(body, friction)
	var decay := exp(-rate * maxf(0.0, dt))
	var denominator := maxf(EPSILON, 1.0 - decay)
	var accel := (desired_velocity - body.velocity * decay) * (rate / denominator)
	var max_accel := maximum_acceleration(body, friction)
	var mag := accel.length()
	if mag > max_accel and mag > EPSILON:
		accel = accel * (max_accel / mag)
	return accel


## 环绕推力 —— 角速度玩法的核心
## 让船沿切向逼近到指定距离，形成绕圈飞行
static func orbit_thrust(body: Body, target_body: Body, desired_range: float,
		elapsed: float = 0.0, dt: float = DEFAULT_STEP,
		friction: float = DEFAULT_FRICTION) -> Vector3:
	var max_thrust := maximum_acceleration(body, friction)
	var range := maxf(0.0, desired_range) + body.radius + target_body.radius
	var to_vector := target_body.position - body.position
	var distance := to_vector.length()
	if max_thrust <= 0.0 or distance <= EPSILON:
		return Vector3.ZERO

	var to_unit := to_vector.normalized()

	# 轨道平面法线：优先用当前速度与视线叉乘，退化则用默认法线
	var radial_vector := default_orbital_normal(body, elapsed).cross(to_unit)
	if radial_vector.length_squared() <= 1e-12:
		var fallback_up := Vector3.UP if absf(to_unit.y) < 0.9 else Vector3.RIGHT
		radial_vector = fallback_up.cross(to_unit)
	radial_vector = radial_vector.normalized()

	# 求切向推力方向（保证能切入目标环）
	var thrust_direction := to_unit
	var tangent_discriminant := distance * distance - range * range
	if tangent_discriminant >= 0.0:
		var radial_component := range * sqrt(tangent_discriminant) / distance
		thrust_direction = (to_unit * (tangent_discriminant / distance) + radial_vector * radial_component).normalized()

	# 距离误差 -> 径向修正权重（高斯衰减，误差越大修正越强）
	var range_error := range - distance
	var radial_factor := exp(-(range_error * range_error) / 40000.0)

	# 解二次方程求切向分量
	var opposing_cosine := -thrust_direction.dot(radial_vector)
	var determinant := 1.0 + radial_factor * radial_factor * (opposing_cosine * opposing_cosine - 1.0)
	var transverse_factor := 0.0
	if determinant > 0.0:
		transverse_factor = radial_factor * opposing_cosine + sqrt(determinant)
	else:
		transverse_factor = radial_factor * opposing_cosine
	transverse_factor *= 1.0 if distance >= range else -1.0

	return (radial_vector * radial_factor + thrust_direction * transverse_factor) * max_thrust


## 默认轨道法线（无速度参考时的兜底，用 id 与时间做伪随机）
static func default_orbital_normal(body: Body, elapsed: float = 0.0) -> Vector3:
	var phi1 := elapsed * 0.001
	var phi2 := float(absi(body.id) % 65536) + elapsed * 0.001
	var normal := Vector3(
		cos(phi1) * cos(phi2),
		sin(phi2),
		sin(phi1) * cos(phi2)
	)
	return normal.normalized()


## 螺旋接近 —— 远距离接敌时用，避免「直线顶牛」导致角速度恒为 0
##
## ⚠️ 为什么必须有这个：
##   实测发现，如果远程接近一律走直线（follow/goto），
##   则整段接敌过程 transversal 恒为 0 → angular 恒为 0，
##   于是炮塔追踪机制完全失效（命中率虚高到 90%+），
##   而且双方会在交错点「擦肩而过」，然后又互相掉头追 → 距离周期性振荡。
##
##   解法：接近时叠一个切向分量，让船走弧线包向目标。
##   这样接敌过程中就有角速度，追踪机制从头就生效，
##   而且天然形成「包夹」而非「对撞」，更容易进入环绕稳态。
static func spiral_thrust(body: Body, target_body: Body, desired_range: float,
		elapsed: float = 0.0, dt: float = DEFAULT_STEP,
		friction: float = DEFAULT_FRICTION) -> Vector3:
	var to_vector := target_body.position - body.position
	var distance := to_vector.length()
	if distance <= EPSILON:
		return Vector3.ZERO

	var to_unit := to_vector.normalized()
	var max_accel := maximum_acceleration(body, friction)

	# 距离越远，越偏向径向（尽快拉近）；越近，越偏向切向（建立环绕）
	var range := maxf(1.0, desired_range)
	var radial_weight := clampf((distance - range) / maxf(range, EPSILON), 0.0, 1.0)
	radial_weight = sqrt(radial_weight)   # 开方：让切向分量更早介入

	# 切向方向：绕目标旋转（用 orbital normal 保证同队船绕向一致，形成编队感）
	var orbit_normal := default_orbital_normal(body, elapsed)
	var tangent := orbit_normal.cross(to_unit)
	if tangent.length_squared() <= 1e-12:
		var fallback_up := Vector3.UP if absf(to_unit.y) < 0.9 else Vector3.RIGHT
		tangent = fallback_up.cross(to_unit)
	tangent = tangent.normalized()

	var direction := (to_unit * radial_weight + tangent * (1.0 - radial_weight)).normalized()

	# 速度目标：距离远时全速，进入期望距离后开始减速
	var stop_distance := maxf(body.radius * 4.0, body.max_speed / maxf(EPSILON, drag_rate(body, friction)))
	var desired_speed := body.speed_fraction * body.max_speed * clampf(distance / stop_distance, 0.0, 1.0)
	var accel_mag := minf(desired_speed * drag_rate(body, friction), max_accel)

	return direction * accel_mag


# ---------------------------------------------------------------- 姿态分发

## 把战斗姿态翻译成加速度 —— 自走棋的"指令层"
## 这是自走棋玩家唯一需要操作的：给每艘船选一个姿态
##
## 关于 KEEP：如果只保持 desired_range，双方都在射程外时会「谁都不动」。
## 自走棋里必须保证战斗一定会打起来，所以 KEEP 在超出射程时退化为接近，
## 进入射程后才切回保持距离。这是自走棋与 EVE 真实战斗的关键差异。
static func command_to_acceleration(body: Body, target_body: Body, stance: int,
		desired_range: float, dt: float = DEFAULT_STEP,
		elapsed: float = 0.0, friction: float = DEFAULT_FRICTION) -> Vector3:
	var distance := body.position.distance_to(target_body.position)

	match stance:
		EveCombatCore.Stance.APPROACH:
			# 全速贴近：牺牲命中换距离压制
			return follow_thrust(body, target_body, 0.0, dt, friction)

		EveCombatCore.Stance.KEEP:
			# 保持射程：超出射程先接近，进入后保持
			if distance > desired_range:
				return follow_thrust(body, target_body, desired_range, dt, friction)
			return follow_thrust(body, target_body, desired_range, dt, friction)

		EveCombatCore.Stance.ORBIT:
			# 环绕：拉高角速度，让对方打不中
			return orbit_thrust(body, target_body, desired_range, elapsed, dt, friction)

		EveCombatCore.Stance.KITE:
			# 风筝：保持在射程外缘游走（不主动拉开到无限远）
			var away := (body.position - target_body.position).normalized()
			# 目标点：射程外缘再留一点余量
			var want := desired_range * 1.05 + body.radius + target_body.radius
			if distance < want:
				return goto_thrust(body, target_body.position + away * want, dt, friction)
			# 已经在理想距离外 → 横向游走而非继续远离
			return orbit_thrust(body, target_body, want, elapsed, dt, friction)

		_:
			# MANUAL：由外部直接给加速度
			return Vector3.ZERO


## 姿态中文名（用于 HUD）
static func stance_label(stance: int) -> String:
	match stance:
		EveCombatCore.Stance.APPROACH: return "接近战"
		EveCombatCore.Stance.KEEP: return "保持距离"
		EveCombatCore.Stance.ORBIT: return "环绕规避"
		EveCombatCore.Stance.KITE: return "拉开风筝"
		_: return "手动"
