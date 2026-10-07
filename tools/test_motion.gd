extends Node

## 运动学单元测试 —— 不做完整战斗，只验证「船能不能正确趋近/保持距离」
## 这是定位漂移问题的显微镜。

var _bodies: Array = []
var _t := 0.0
var _done := false


func _ready() -> void:
	print("=".repeat(76))
	print("[运动学单元测试] 两艘船：A 在 z=+45km  B 在 z=-45km，各给不同姿态")
	print("=".repeat(76))
	print("%6s | %-9s | %10s %10s | %10s %10s %10s | %10s" % [
		"t", "姿态", "A_z", "B_z", "A_speed", "B_speed", "距离", "接近率"])
	print("-".repeat(76))

	# A: 保持 9000m   B: 也保持 9000m（同向靠拢）
	var a := EveDestinyMotion.Body.new(1)
	a.position = Vector3(0, 0, 45000)
	a.max_speed = 420.0
	a.mass = 1_150_000.0
	a.agility = 3.2
	a.radius = 34.0

	var b := EveDestinyMotion.Body.new(2)
	b.position = Vector3(0, 0, -45000)
	b.max_speed = 520.0
	b.mass = 1_050_000.0
	b.agility = 2.8
	b.radius = 32.0

	_bodies = [[a, b], [b, a]]
	_run()


func _run() -> void:
	for i in 900:
		_t += EveDestinyMotion.DEFAULT_STEP
		_tick()
		if int(_t / 5.0) != int((_t - EveDestinyMotion.DEFAULT_STEP) / 5.0):
			_dump()
	print("-".repeat(76))
	print("[最终] 距离 %.0f m   A速度 %.1f   B速度 %.1f" % [
		_bodies[0][0].position.distance_to(_bodies[1][0].position),
		_bodies[0][0].velocity.length(), _bodies[1][0].velocity.length()])
	get_tree().quit(0)


func _tick() -> void:
	for pair in _bodies:
		var body: EveDestinyMotion.Body = pair[0]
		var target: EveDestinyMotion.Body = pair[1]
		var accel := EveDestinyMotion.command_to_acceleration(
			body, target, EveCombatCore.Stance.KEEP, 9000.0,
			EveDestinyMotion.DEFAULT_STEP, _t)
		EveDestinyMotion.integrate_body(body, accel, EveDestinyMotion.DEFAULT_STEP)


func _dump() -> void:
	var a: EveDestinyMotion.Body = _bodies[0][0]
	var b: EveDestinyMotion.Body = _bodies[1][0]
	var d := a.position.distance_to(b.position)
	print("%6.1f | %-9s | %10.0f %10.0f | %10.1f %10.1f %10.0f | %10s" % [
		_t, "KEEP 9km", a.position.z, b.position.z,
		a.velocity.length(), b.velocity.length(), d, ""])
