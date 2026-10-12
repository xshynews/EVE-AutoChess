extends SceneTree
## 实机探针：房主与加入者都以 no-TUN 运行时，ENet 能否经 EasyTier 隧道连通。
##
## 需要本机有内核（`python tools/pipeline/_fetch_easytier.py`），不进验收套件。
##
## 用法（--lan 填本机局域网 IP；同机测试时两个内核要经它互连，经 127.0.0.1 互连会失败）：
##   "$GODOT_BIN" --headless --path . -s res://tools/probe_tunnel_notun.gd -- --lan=192.168.1.34
##
## 验证「不需要管理员」时，用普通权限启动 Godot，例如：
##   runas /trustlevel:0x20000 "cmd /c <godot> --headless --path <工程> -s ... > out.txt 2>&1"
##
## 流程：
## 1. 房主用 `eve_tunnel.start()` 启动内核（真实参数：no-TUN、-i 虚拟IP/24、密钥走环境变量）。
## 2. 加入者用 `eve_tunnel.build_args()` 生成真实参数（no-TUN、DHCP、端口转发），只做两处替换：
##    会合节点改为房主的局域网地址；端口转发的本机端口改为 27016，避免与同机房主的 27015 冲突。
## 3. 房主用 `eve_ddz_transport.host_start(27015, "127.0.0.1")` 只在本机监听；
##    加入者连 127.0.0.1:27016，收发 10 条消息。
## 4. 输出 `RESULT ...`，结束时只结束本探针启动的两个内核进程。

const TUN := preload("res://scripts/net/eve_tunnel.gd")
const RC := preload("res://scripts/net/eve_room_code.gd")
const TP := preload("res://scripts/net/eve_ddz_transport.gd")

const CODE := "PRBNTN23"
const GUEST_SLOT := 5
const GUEST_LOCAL_PORT := 27016
const TIMEOUT_MS := 60000
const MSG_COUNT := 10

var _lan := ""
var _host_tun = null
var _guest_pid := -1
var _server = null
var _client = null
var _phase := "tunnel"
var _t0 := 0
var _joined_at := 0
var _sent := 0
var _echoed := 0
var _server_saw := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lan="):
			_lan = a.substr(6)
	if _lan == "":
		print("缺少 --lan=<本机局域网 IP>")
		quit(2)
		return
	if not TUN.available():
		print("本机没有内核，先运行 python tools/pipeline/_fetch_easytier.py")
		quit(2)
		return
	_t0 = Time.get_ticks_msec()
	_host_tun = TUN.new()
	if not _host_tun.start(CODE, 0, true, [], "probe-host", _t0):
		print("房主内核启动失败：%s" % _host_tun.last_error)
		quit(1)
		return
	_guest_pid = _start_guest()
	print("房主 PID %d，加入者 PID %d" % [_host_tun.pid, _guest_pid])


func _start_guest() -> int:
	var host_lp := RC.listen_port(CODE, 0)
	var args := TUN.build_args(CODE, GUEST_SLOT, false, ["tcp://%s:%d" % [_lan, host_lp]], "probe-guest")
	for i in args.size():
		if args[i] == "--port-forward":
			args[i + 1] = args[i + 1].replace("127.0.0.1:%d/" % RC.DEFAULT_PORT,
					"127.0.0.1:%d/" % GUEST_LOCAL_PORT)
	print("加入者参数：%s" % " ".join(args))
	var env := TUN.build_env(CODE)
	for k in env:
		OS.set_environment(String(k), String(env[k]))
	var pid := OS.create_process(TUN.core_path(), args, false)
	for k in env:
		OS.unset_environment(String(k))
	return pid


## 用 easytier-cli 读出房主内核实际生效的配置，确认网络密钥来自环境变量且与房间码派生值一致。
## 只靠「两边能连上」证明不了：若环境变量没传进去，两边都会是空密钥，照样能连。
func _check_secret() -> String:
	var cli := TUN.core_path().get_base_dir().path_join("easytier-cli.exe")
	if not FileAccess.file_exists(cli):
		return "未检查（缺 easytier-cli.exe）"
	var out: Array = []
	OS.execute(cli, ["-p", "127.0.0.1:%d" % RC.rpc_port(CODE, 0), "node", "config"], out, true)
	var text := "".join(out)
	var want := RC.network_secret(CODE)
	if text.find(want) >= 0:
		return "是"
	return "否（配置中未找到预期密钥）"


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_msec()
	if now - _t0 > TIMEOUT_MS:
		_finish("超时（阶段 %s）" % _phase)
		return true
	match _phase:
		"tunnel":
			var st: int = _host_tun.poll(now)
			if st == TUN.State.FAILED:
				_finish("房主内核失败：%s" % _host_tun.last_error)
				return true
			if st == TUN.State.UP:
				print("房主内核就绪 %d ms（no-TUN，未申请管理员权限）" % (now - _t0))
				var secret_check := _check_secret()
				print("密钥经环境变量生效：%s" % secret_check)
				if secret_check != "是":
					_finish("内核实际使用的网络密钥与房间码派生值不一致")
					return true
				_server = TP.new()
				root.add_child(_server)
				if not _server.host_start(RC.DEFAULT_PORT, "127.0.0.1"):
					_finish("房主 ENet 监听失败：%s" % _server.last_error)
					return true
				_server.peer_joined.connect(func(id: int):
					_server_saw = "peer %d" % id)
				_server.packet.connect(func(from: int, d: Dictionary):
					_server.send_to(from, {"echo": d.get("n", -1)}))
				_phase = "join"
		"join":
			# 加入者经 DHCP 取址、与房主建链需要几秒；连不上就重试。
			if _client == null or (now - _joined_at > 3000 and _sent == 0 and _echoed == 0):
				if _client != null:
					_client.stop()
					_client.queue_free()
				_client = TP.new()
				root.add_child(_client)
				_client.connected_ok.connect(func():
					print("ENet 连上房主 %d ms" % (Time.get_ticks_msec() - _t0))
					_phase = "talk")
				_client.packet.connect(func(_from: int, d: Dictionary):
					if int(d.get("echo", -1)) == _echoed:
						_echoed += 1)
				_client.join("127.0.0.1", GUEST_LOCAL_PORT, now)
				_joined_at = now
		"talk":
			if _sent < MSG_COUNT and _sent == _echoed:
				_client.send_to(TP.SERVER_ID, {"n": _sent})
				_sent += 1
			if _echoed >= MSG_COUNT:
				_finish("")
				return true
	return false


func _finish(err: String) -> void:
	if err != "":
		print("失败：%s" % err)
	print("房主看到的连接：%s" % _server_saw)
	print("RESULT notun_host=%s enet_echo=%d/%d" % [err == "", _echoed, MSG_COUNT])
	if _client != null:
		_client.stop()
	if _server != null:
		_server.stop()
	if _host_tun != null:
		_host_tun.stop()
	if _guest_pid > 0 and OS.is_process_running(_guest_pid):
		OS.kill(_guest_pid)
	quit(0 if err == "" else 1)
