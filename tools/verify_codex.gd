extends Node

## 舰船图鉴自检：入口按钮 + 52 艘全收录 + 筛选计数 + 详情/关闭。
##
## 用法：godot --headless --path . --quit-after 6000 res://tools/verify_codex.tscn

const MENU := "res://scenes/main_menu.tscn"
const SHIP_DB := preload("res://scripts/core/eve_ship_database.gd")

var _pass := 0
var _fail := 0


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  [FAIL] %s" % msg)


func _ready() -> void:
	print("═══ 舰船图鉴自检 ═══")
	var menu = (load(MENU) as PackedScene).instantiate()
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame

	# ① 入口
	var btn = menu.get("_codex_btn")
	_ok(btn != null, "任务关卡下方有图鉴入口按钮")
	_ok(btn != null and bool(btn.visible), "默认选中任务关卡 ⇒ 入口可见")
	_ok(btn != null and String(btn.text).contains("52"), "按钮文案含总数（实际「%s」"
			% (String(btn.text) if btn != null else ""))

	# ② 打开 + 全收录
	menu.call("_open_codex")
	await get_tree().process_frame
	var codex = menu.get("_codex")
	_ok(codex != null, "图鉴浮层已创建")
	_ok(int(codex.call("card_count")) == SHIP_DB.count(), "全部 %d 艘都在网格里（实际 %d）"
			% [SHIP_DB.count(), int(codex.call("card_count"))])
	_ok(int(codex.call("card_count")) == 52, "舰船总数 = 52")
	_ok(String(codex.call("selected_id")) != "", "打开时默认选中一艘")
	_ok(not SHIP_DB.by_id(String(codex.call("selected_id"))).is_empty(), "选中项的详情数据可读")

	# ③ 筛选计数（4 派系各 13；费用档 12/8/12/8/12；单派系单档 = 3）
	#
	# ★★ 2026-10-28：派系这一档原来只验「= 13 艘」——**四族都是 13 艘**，
	#    所以点「艾玛」筛出米玛塔尔也照样绿（用户实测才发现的 bug）。
	#    ⇒ 改成逐档比对**具体 id**：点哪一族，网格里必须全且仅是那一族的船。
	var fac_names: Array = ["艾玛", "加达里", "盖伦特", "米玛塔尔"]
	# ⚠️ 必须**点 chip**（走 `_fac_chips` 的回调），不能直接 `set_filter(fi, -1)`：
	#    set_filter 拿到的是枚举值，而那个 bug 在「chip 下标 → 枚举值」的映射里 ——
	#    直接传 set_filter 等于绕过被 bug 污染的那一步，断言会一直是绿的
	#    （我第一版就这么写，反向注入旧逻辑后依然 31/0，等于没测）。
	var chips: Array = codex.get("_fac_chips")
	for fi in fac_names.size():
		chips[fi + 1].emit_signal("pressed")
		var got: Array = codex.call("visible_ids")
		var want: Array[String] = []
		for s in SHIP_DB.all_ships():
			if int(s["faction"]) == fi:
				want.append(String(s["ship_key"]))
		want.sort()
		var wrong: Array = []
		for k in got:
			if not want.has(k):
				wrong.append(k)
		var missing: Array = []
		for k in want:
			if not got.has(k):
				missing.append(k)
		_ok(got.size() == want.size() and wrong.is_empty() and missing.is_empty(),
				"★ 派系「%s」⇒ 网格里全且仅是这一族（%d 艘；串族=%s；缺=%s）"
				% [fac_names[fi], got.size(), str(wrong), str(missing)])
	chips[1].emit_signal("pressed")          # 点「艾玛」chip
	_ok(int(codex.call("card_count")) == 13, "派系筛选 = 13（实际 %d）" % int(codex.call("card_count")))
	# 回归锚点：这条 bug 的直接复现条件（点第一档艾玛，里面不许出现米玛塔尔船）
	var mimi: Array = []
	var ids0: Array = codex.call("visible_ids")
	for k in ids0:
		if String(k) in ["slasher", "rifter", "burst", "thrasher", "talwar", "stabber",
				"rupture", "scythe", "cyclone", "maelstrom", "tempest", "typhoon"]:
			mimi.append(k)
	_ok(mimi.is_empty(), "★★ 点「艾玛」不出现任何米玛塔尔船（实际混进 %s）" % str(mimi))
	# 详情栏也要跟着筛选走（否则右栏还挂着别的族的船，看起来像筛选没生效）
	var sel_now := String(codex.call("selected_id"))
	var ids_now: Array = codex.call("visible_ids")
	_ok(ids_now.has(sel_now), "★ 筛选后选中项属于当前筛选结果（选中 %s）" % sel_now)
	codex.call("set_filter", -1, 1)
	_ok(int(codex.call("card_count")) == 12, "护卫 = 12（实际 %d）" % int(codex.call("card_count")))
	codex.call("set_filter", -1, 2)
	_ok(int(codex.call("card_count")) == 8, "驱逐 = 8（实际 %d）" % int(codex.call("card_count")))
	codex.call("set_filter", -1, 3)
	_ok(int(codex.call("card_count")) == 12, "巡洋 = 12（实际 %d）" % int(codex.call("card_count")))
	codex.call("set_filter", -1, 4)
	_ok(int(codex.call("card_count")) == 8, "战巡 = 8（实际 %d）" % int(codex.call("card_count")))
	codex.call("set_filter", -1, 5)
	_ok(int(codex.call("card_count")) == 12, "战列 = 12（实际 %d）" % int(codex.call("card_count")))
	codex.call("set_filter", 0, 1)
	_ok(int(codex.call("card_count")) == 3, "艾玛 + 护卫 = 3（实际 %d）" % int(codex.call("card_count")))
	codex.call("set_filter", -1, -1)
	_ok(int(codex.call("card_count")) == 52, "清空筛选回到 52（实际 %d）" % int(codex.call("card_count")))

	# ③.5 定位五档（2026-10-28 新增）
	#
	# ⚠️ 这五个数是**互斥**口径下的（电子战船不算进攻击/防御）：
	#    攻击 17 = 表里 20 - 电子战里的 3 艘；防御 15 = 24 - 电子战里的 5 艘。
	#    ⇒ 谁要是把 role_tag 的优先级改回「role 优先」，这组断言立刻红，
	#      而那正是会让图鉴五档合计变成 60 的错法。
	var tags: Array[StringName] = [&"attack", &"defense", &"logistics", &"ew", &"command"]
	var expect: Array[int] = [17, 15, 8, 8, 4]
	var sum := 0
	for i in tags.size():
		codex.call("set_filter", -1, -1, tags[i])
		var n := int(codex.call("card_count"))
		sum += n
		_ok(n == expect[i], "定位「%s」= %d（实际 %d）"
				% [SHIP_DB.role_label(tags[i]), expect[i], n])
	_ok(sum == 52, "定位五档互斥、合计 = 52（实际 %d）" % sum)
	codex.call("set_filter", -1, -1, &"")
	_ok(int(codex.call("card_count")) == 52, "清空定位筛选回到 52（实际 %d）"
			% int(codex.call("card_count")))

	# ④ 数据完整性：每艘都能被 by_id 取到、名字非空
	var bad_name := 0
	var bad_id := 0
	for s in SHIP_DB.all_ships():
		if String(s.get("name", "")) == "":
			bad_name += 1
		if SHIP_DB.by_id(String(s.get("ship_key", ""))).is_empty():
			bad_id += 1
	_ok(bad_name == 0, "所有舰船都有名字")
	_ok(bad_id == 0, "所有舰船都能按 id 取回")

	# ⑤ 关闭
	codex.call("close")
	_ok(not bool(codex.call("is_open")), "能正常关闭")

	print("═══ RESULT passed=%d failed=%d ═══" % [_pass, _fail])
	if _fail > 0:
		print("⚠️ 有失败项")
	get_tree().quit(1 if _fail > 0 else 0)
