extends Node

## 诊断探针 —— 量化「舰船抖动」的来源（不改任何生产代码，只读）。
##
## 用法：
##   godot_console.exe --headless --path <工程> res://tools/probe_jitter.tscn
##
## ══════════════════════════════════════════════════════════════════
##  它测什么，为什么这么测
## ══════════════════════════════════════════════════════════════════
## 玩家报的现象：「对战时候舰船有不明的、小幅高频抖动，看不清、发糊」。
##
## 渲染层的事实（已读代码确认）：
##   · 仿真跑 **30 Hz**（`EveBattleSimulator.TICK_RATE = 30`，固定步长 + 时间累加器）；
##   · 视觉层 `EveShipVisual.sync_from_body()` **直接把 position 写成上一 tick 的位置**
##     （`position = body.position / METERS_PER_UNIT`）；
##   · `EveDestinyMotion.Body.previous_position` **有写、全工程无人读**。
## ⇒ 也就是「固定步长仿真 + **没有渲染插值**」，这是逐帧跳变的经典配方。
##
## 本探针把这条链量化成三个数：
##   ① 每 tick 位移（米 / 像素）—— 抖动的**振幅**
##   ② 60 / 144 / 240 fps 下，**多少比例的渲染帧画面完全没动**（stutter 比例）
##      以及「动的那一帧跳多少像素」—— 抖动的**频率与可见度**
##   ③ 速度方向反转率 —— 排除「仿真本身在振荡」这一种可能
##
## ⚠️ 像素换算用 `PX_PER_UNIT`（见典型取值注释），只求量级，不当权威。

var _sim: EveBattleSimulator
var _tick := 0

## ship_id -> Array[Vector3]，逐 tick 位置（只记 team 0）
var _pos: Dictionary = {}
var _prev_dir: Dictionary = {}
var _reversal: Dictionary = {}
var _moved: Dictionary = {}

## 米 → 世界单位 → 像素。世界单位 1 = 1000 米（`EveBattleArena.world_unit_in_meters`）。
## 典型战斗视距下：2.6 世界单位的船身 ≈ 121 px。
const METERS_PER_UNIT := 1000.0
const PX_PER_UNIT := 46.5

const TICKS_TO_RUN := 450      ## 15 秒战斗时间
const WARMUP_TICKS := 60       ## 前 2 秒是接敌冲刺，不计入抖动统计


func _ready() -> void:
	var own := _gen(4, 0, 100)
	var enemy := _gen(4, 1, 500)
	_place(own, enemy, 0)
	_place(enemy, own, 1)

	_sim = EveBattleSimulator.new()
	_sim.setup(own, enemy)

	print("=".repeat(72))
	print("[探针] 舰船抖动来源量化 · TICK_RATE=%.0f · 无渲染插值" % EveBattleSimulator.TICK_RATE)
	print("=".repeat(72))
	for s in own:
		print("  我方 %-12s 速度上限 %6.0f m/s  射程 %7.0f m" % [
			s.ship_name, s.body.max_speed, s.optimal_range])
	print("")

	while _tick < TICKS_TO_RUN and not _sim.finished:
		_sim.step(EveBattleSimulator.FIXED_STEP)
		_tick += 1
		_sample()

	print("  仿真跑完 %d tick（%.1f 秒），结束=%s" % [_tick, _sim.elapsed, str(_sim.finished)])
	print("")
	_report_per_tick()
	_report_render("60 fps", 60.0)
	_report_render("144 fps", 144.0)
	_report_render("240 fps", 240.0)
	_report_oscillation()

	print("")
	print("[换算口径] 1 世界单位 = %.0f 米；1 世界单位 ≈ %.1f px（战斗视距典型值）"
			% [METERS_PER_UNIT, PX_PER_UNIT])
	print("[目标切换] sim._target_switches = %d（%d tick）"
			% [int(_sim.get("_target_switches")), _tick])
	get_tree().quit()


func _gen(count: int, team: int, base_id: int) -> Array[EveShip]:
	var out: Array[EveShip] = []
	var n := EveShipDatabase.all_ships().size()
	for i in count:
		out.append(EveShipDatabase.instantiate(i % n, team, base_id + i))
	return out


## 与 verify_battle / 实机同口径的部署（射程中位数 × 1.15 的接敌线）。
func _place(fleet: Array[EveShip], other: Array[EveShip], team: int) -> void:
	var ranges: Array[float] = []
	for s in fleet + other:
		if s != null:
			ranges.append(s.optimal_range)
	if ranges.is_empty():
		ranges.append(20_000.0)
	ranges.sort()
	var mid := ranges.size() / 2
	var median := ranges[mid] if ranges.size() % 2 == 1 \
			else (ranges[mid - 1] + ranges[mid]) * 0.5
	var basis := clampf(median, 12_000.0, ranges[ranges.size() - 1])
	var standoff_m := basis * 1.15
	var z := standoff_m * 0.5 if team == 0 else -standoff_m * 0.5
	var col_step := 8_000.0
	for i in fleet.size():
		var col := i % 4
		var row := i / 4
		var x := (float(col) - 1.5) * col_step
		var zz := z + (float(row) * 6_000.0) * (-1.0 if team == 0 else 1.0)
		fleet[i].body.position = Vector3(x, 0.0, zz)
		fleet[i].body.previous_position = fleet[i].body.position
		fleet[i].body.velocity = Vector3.ZERO


## 每 tick 抄一份位置（只抄我方存活船）。
func _sample() -> void:
	for s in _sim.ships:
		if s.team != 0 or not s.alive:
			continue
		if not _pos.has(s.id):
			_pos[s.id] = []
			_prev_dir[s.id] = Vector3.ZERO
			_reversal[s.id] = 0
			_moved[s.id] = 0
		(_pos[s.id] as Array).append(s.body.position)
		# 速度方向反转：相邻两 tick 的位移矢量夹角 > 90°
		var arr: Array = _pos[s.id]
		if arr.size() >= 2:
			var d: Vector3 = arr[arr.size() - 1] - arr[arr.size() - 2]
			var pd: Vector3 = _prev_dir[s.id]
			if pd.length_squared() > 1e-12 and d.length_squared() > 1e-12:
				if d.dot(pd) < 0.0:
					_reversal[s.id] = int(_reversal[s.id]) + 1
			if d.length_squared() > 1e-12:
				_prev_dir[s.id] = d
			_moved[s.id] = int(_moved[s.id]) + 1


## ① 每 tick 位移（去掉接敌冲刺段的温启动）
func _report_per_tick() -> void:
	print("── ① 每 tick 位移（振幅）─────────────────────────────────")
	var worst := 0.0
	var worst_name := ""
	for id in _pos:
		var arr: Array = _pos[id]
		if arr.size() <= WARMUP_TICKS:
			continue
		var tot := 0.0
		var mx := 0.0
		var n := 0
		for i in range(WARMUP_TICKS, arr.size()):
			var d: float = (arr[i] as Vector3).distance_to(arr[i - 1] as Vector3)
			tot += d
			mx = maxf(mx, d)
			n += 1
		if n == 0:
			continue
		var avg := tot / float(n)
		var nm := _name_of(id)
		print("  %-12s 均 %7.0f m/tick (%.2f px)   峰 %7.0f m (%.2f px)"
				% [nm, avg, avg / METERS_PER_UNIT * PX_PER_UNIT,
				mx, mx / METERS_PER_UNIT * PX_PER_UNIT])
		if mx > worst:
			worst = mx
			worst_name = nm
	print("  ⇒ 峰值 %.0f m/tick（%.2f px）= %s" % [
			worst, worst / METERS_PER_UNIT * PX_PER_UNIT, worst_name])


## ② 渲染帧分析：给定刷新率，逐帧看「画面动没动」
##
## ⚠️ 这是本探针的核心。仿真是 30 Hz 离散的，渲染帧在两次 tick 之间拿到的
##    是**同一个** position ⇒ 那几帧画面**完全静止**，然后一帧跳过去。
##    「静止若干帧 + 一次跳变」被眼睛读成抖动/卡顿，跳得越大越明显。
##
## ★ 2026-10-27 起同时打印**插值前 / 插值后**两组数：
##    插值后 = `previous_position.lerp(position, alpha)`，alpha 取累加器余量占比 ——
##    即生产代码现在的行为（`EveBattleSimulator.interp_alpha()` + `sync_ships`）。
func _report_render(label: String, fps: float) -> void:
	print("")
	print("── ② %s 下的逐帧位移 ─────────────────────────────────" % label)
	var t_old := _render_stats(fps, false)
	var t_new := _render_stats(fps, true)
	print("  插值前（旧行为）：总帧 %d · **完全没动**的帧 %d（%.0f%%）· 跳变帧 均 %.2f / 中位 %.2f / 99分位 %.2f px"
			% [int(t_old["frames"]), int(t_old["zero"]),
			100.0 * float(t_old["zero"]) / maxf(1.0, float(t_old["frames"])),
			float(t_old["avg"]), float(t_old["p50"]), float(t_old["p99"])])
	print("  插值后（现行为）：总帧 %d · **完全没动**的帧 %d（%.0f%%）· 跳变帧 均 %.2f / 中位 %.2f / 99分位 %.2f px"
			% [int(t_new["frames"]), int(t_new["zero"]),
			100.0 * float(t_new["zero"]) / maxf(1.0, float(t_new["frames"])),
			float(t_new["avg"]), float(t_new["p50"]), float(t_new["p99"])])


## 按给定刷新率重采样「渲染帧看到的像素位移」，`interp` 选插值前/后。
func _render_stats(fps: float, interp: bool) -> Dictionary:
	var frame_dt := 1.0 / fps
	var total := 0
	var zero := 0
	var jumps: Array[float] = []
	var prev := Vector3.ZERO
	var have_prev := false
	for id in _pos:
		var arr: Array = _pos[id]
		if arr.size() <= WARMUP_TICKS + 2:
			continue
		# 从温启动那一段之后开始，避免把最初那段零位移算进来
		var t0 := float(WARMUP_TICKS) * EveBattleSimulator.FIXED_STEP
		var k := 0.0
		prev = Vector3.ZERO
		have_prev = false
		while true:
			var now := t0 + k * frame_dt
			var ticks := now / EveBattleSimulator.FIXED_STEP
			var n := int(floor(ticks))
			if n >= arr.size():
				break
			var p: Vector3 = arr[n]
			if interp and n >= 1:
				p = (arr[n - 1] as Vector3).lerp(arr[n] as Vector3, ticks - float(n))
			if have_prev:
				var d: float = absf(p.x - prev.x) + absf(p.y - prev.y) + absf(p.z - prev.z)
				total += 1
				if d <= 1e-9:
					zero += 1
				else:
					jumps.append(d)
			prev = p
			have_prev = true
			k += 1.0
	jumps.sort()
	var avg := 0.0
	for j in jumps:
		avg += j
	avg /= maxf(1.0, float(jumps.size()))
	var p50 := jumps[jumps.size() / 2] if not jumps.is_empty() else 0.0
	var p99 := jumps[mini(jumps.size() - 1, int(float(jumps.size()) * 0.99))] if not jumps.is_empty() else 0.0
	var px := 1.0 / METERS_PER_UNIT * PX_PER_UNIT
	return {
		"frames": total, "zero": zero,
		"avg": avg * px, "p50": p50 * px, "p99": p99 * px,
	}


## ③ 仿真本身是否在振荡（速度方向反转率）
func _report_oscillation() -> void:
	print("")
	print("── ③ 仿真自身是否振荡（速度方向反转率）─────────────────")
	for id in _pos:
		var moved := int(_moved.get(id, 0))
		if moved < 10:
			continue
		var rev := int(_reversal.get(id, 0))
		print("  %-12s 反转 %3d / %3d tick = %4.1f%%" % [
				_name_of(id), rev, moved, 100.0 * float(rev) / float(moved)])
	print("  （>30%% 说明仿真层在来回振荡；≈0~10%% 说明仿真平滑，抖动来自呈现层）")


func _name_of(id: int) -> String:
	var s: EveShip = _sim._ship_by_id.get(id)
	return s.ship_name if s != null else "?"