extends Node
## 联机内核探针（**真实拉起内置内核**，不 mock）。
##
## 用法：
##     godot --headless --path <工程> --quit-after 1200 res://tools/probe_eve_tunnel.tscn
##
## ⚠️ 前置：`addons/easytier/bin/` 里要有内核
##    （python tools/pipeline/_fetch_easytier.py）。没内核时本探针只报「不可用」并退出 0
##    —— ⛔ 它是探针，不进验收套件（CI 上没有内核）。
##
## 它验的是**只有真机能验**的三件事：
##   ① `build_args()` 生成的参数**内核真的认**（猜错参数名 = 静默起不来）；
##   ② 就绪判定（连管理 RPC 端口）**真的能判断"起来了"**；
##   ③ 停得干净（⛔ 不残留进程）。

const TUN := preload("res://scripts/net/eve_tunnel.gd")
const RC := preload("res://scripts/net/eve_room_code.gd")
const RELAY := preload("res://scripts/net/eve_relay_list.gd")

const CODE := "PROBE234"
const RELAYS: Array[String] = ["tcp://sh.vomiku.com:7910"]   ## 只连一个，探针别压公共节点

var _fail := 0


func _ready() -> void:
	print("═══ 联机内核探针 ═══")
	print("内核版本（脚本声明）= %s" % TUN.VERSION)
	print("内核路径 = %s" % ("(未找到)" if TUN.core_path() == "" else TUN.core_path()))
	if not TUN.available():
		print("⚠️ 没找到内置内核 ⇒ 跳过实跑（先跑：python tools/pipeline/_fetch_easytier.py）")
		print("════ 探针结束（跳过）════")
		get_tree().quit(0)
		return
	print("wintun.dll = %s" % ("有" if TUN.has_wintun() else "无（房主模式不可用）"))
	print("--- 参数样例（加入者）---")
	print("  " + " ".join(TUN.build_args(CODE, 2, false, RELAYS, "测试加入者")))

	await _run("加入者（--no-tun + 端口转发，应无需管理员）", false, 2)
	await _run("房主（TUN，需管理员 + wintun.dll）", true, 0)

	print("════ 探针结束，失败项 = %d ════" % _fail)
	# ⛔ 探针无判定语义，但自炸要看得出来：统一退 0，结论看打印
	get_tree().quit(0)


func _run(title: String, is_host: bool, seat: int) -> void:
	print("--- %s ---" % title)
	var t := TUN.new()
	var now := Time.get_ticks_msec()
	if not t.start(CODE, seat, is_host, RELAYS, "探针", now):
		print("  ✗ 启动失败：%s" % t.last_error)
		_fail += 1
		return
	print("  · 进程已拉起 pid=%d，等待就绪…" % t.pid)
	var t0 := Time.get_ticks_msec()
	while true:
		await get_tree().process_frame
		var now2 := Time.get_ticks_msec()
		var st: int = t.poll(now2)
		if st == TUN.State.UP:
			print("  ✓ 就绪（耗时 %d ms）：RPC 端口 %d 可连" % [
					now2 - t0, RC.rpc_port(CODE, seat)])
			break
		if st == TUN.State.FAILED:
			print("  ⚠️ 起不来（耗时 %d ms）：%s" % [now2 - t0, t.last_error])
			break
		if now2 - t0 > TUN.READY_TIMEOUT_MS + 3000:
			print("  ✗ 超时未就绪")
			_fail += 1
			break
	var was_up: bool = t.state == TUN.State.UP
	var pid := t.pid
	t.stop()
	await get_tree().create_timer(0.6).timeout
	var still := OS.is_process_running(pid)
	print("  %s 停止后无残留（pid=%d running=%s）" % [
			"✓" if not still else "✗", pid, str(still)])
	if still:
		_fail += 1
	if is_host and not was_up:
		# 房主在本机起不来是**已知的环境问题**（虚拟网卡驱动/防火墙），
		# 这里只把「人话原因」打出来，验证降级路径有话说。
		print("    （房主失败在本环境属已知；重点是上面那句话是否人话可读）")
