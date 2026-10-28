extends Node

## 中继地址解析自检（`scripts/net/eve_net_config.gd`）。
##
## 用法：godot --headless --path . --quit-after 600 res://tools/verify_net_config.tscn
##
## ⚠️ 只测**纯函数** parse()：不读写 net.cfg、不改 user://，
##    ⇒ 不会碰掉作者本机已经配好的服务器地址。

const NETCFG := preload("res://scripts/net/eve_net_config.gd")

var _pass := 0
var _fail := 0


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  [FAIL] %s" % msg)


func _ready() -> void:
	print("═══ 中继地址解析自检 ═══")

	var a := NETCFG.parse("abc.natfrp.cloud:41234")
	_ok(String(a.get("host", "")) == "abc.natfrp.cloud", "域名：host 正确")
	_ok(int(a.get("port", 0)) == 41234, "域名：port 正确")

	var b := NETCFG.parse("  127.0.0.1:27100  ")
	_ok(String(b.get("host", "")) == "127.0.0.1" and int(b.get("port", 0)) == 27100,
			"IPv4：自动去首尾空格")

	var c := NETCFG.parse("[::1]:27100")
	_ok(String(c.get("host", "")) == "::1", "IPv6 方括号：host 去掉方括号")
	_ok(int(c.get("port", 0)) == 27100, "IPv6 方括号：port 正确")

	_ok(NETCFG.parse("").is_empty(), "空串 ⇒ 空")
	_ok(NETCFG.parse("nohost").is_empty(), "没有端口 ⇒ 空")
	_ok(NETCFG.parse(":27100").is_empty(), "没有主机 ⇒ 空")
	_ok(NETCFG.parse("a.b:0").is_empty(), "端口 0 ⇒ 空")
	_ok(NETCFG.parse("a.b:99999").is_empty(), "端口越界 ⇒ 空")
	_ok(NETCFG.parse("a.b:abc").is_empty(), "端口非数字 ⇒ 空")

	print("═══ RESULT passed=%d failed=%d ═══" % [_pass, _fail])
	if _fail > 0:
		print("⚠️ 有失败项")
	get_tree().quit(1 if _fail > 0 else 0)
