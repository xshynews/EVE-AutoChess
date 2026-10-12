extends Node
## 探针：房间码拉伸哈希的**真实耗时**。
##
## 为什么留这个探针：`eve_room_code` 对所有派生值都走「拉伸哈希」（26 万轮 SHA-256，防离线穷举），
## 而它跑在「点创建房间 / 点加入房间」这条**玩家能感知**的路径上。PR 声称约 0.1 秒 ——
## 该数字看起来像 C/Rust 的量级，在 GDScript 里很可能是几秒（那就等于界面卡死）。
##
## ★ 2026-10-12 实测（本机）：**冷调用 133 ms / 132 ms，缓存后 0 ms**。
##   ⇒ 数字是准的，一次性的 133 ms 可接受（且恰好被「正在启动联机内核…」那段盖住）。
##   ⛔ 若将来把轮数调大（比如 2^20），必须重跑这个探针再决定。
##
## 跑法：godot --headless --path . --quit-after 600 res://tools/probe_roomcode_cost.tscn
const RC := preload("res://scripts/net/eve_room_code.gd")

func _ready() -> void:
	var code := "K7QM3X9D"
	var t0 := Time.get_ticks_msec()
	var nm := RC.network_name(code)          # 冷调用，包含拉伸
	var t1 := Time.get_ticks_msec()
	var st := RC.network_secret(code)        # 热调用（应命中缓存）
	var t2 := Time.get_ticks_msec()
	var lp := RC.listen_port(code, 0)
	var t3 := Time.get_ticks_msec()
	print("冷调用 network_name = %d ms   结果=%s" % [t1 - t0, nm])
	print("热调用 network_secret = %d ms  结果=%s" % [t2 - t1, st])
	print("热调用 listen_port = %d ms    结果=%d" % [t3 - t2, lp])
	print("轮数 STRETCH_ROUNDS = %d" % RC.STRETCH_ROUNDS)
	# 换一个码再冷调一次，确认不是一次性开销
	var t4 := Time.get_ticks_msec()
	var _x := RC.network_name("ABCDEFGH")
	print("第二个码冷调用 = %d ms" % [Time.get_ticks_msec() - t4])
	print("════ 探针结束 ════")
	get_tree().quit(0)
