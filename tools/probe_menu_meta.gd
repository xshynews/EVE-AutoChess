extends SceneTree
## 探针（诊断用，不进验收套件）：实例化主菜单，**把所有 Label 的真实文本 dump 出来**。
## 目的：看「任务关卡」那张卡下面的副标题到底渲染成什么（有没有裸 %d / 数字对不对）。

var _menu: Variant = null
var _frames := 0

func _initialize() -> void:
	_menu = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(_menu)   # ⚠️ 此刻 root 可能还没进树 ⇒ `_ready` 要等几帧才跑


func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	var menu: Variant = _menu
	print("=== META DUMP BEGIN ===")
	# ① 界面上那两行 Label 的真实文本（这是玩家看到的）
	var names: Array = menu.get("_mode_names") if menu.get("_mode_names") != null else []
	var metas: Array = menu.get("_mode_metas") if menu.get("_mode_metas") != null else []
	for i in metas.size():
		var nm := String((names[i] as Label).text) if i < names.size() else ""
		print("[row%d] name=%s | meta=%s" % [i, nm, String((metas[i] as Label).text)])
	if menu.has_method("_build_mode_table"):
		var tbl: Array = menu._build_mode_table()
		for m in tbl:
			var d: Dictionary = m as Dictionary
			print("[mode] id=%s name=%s meta=%s" % [
					String(d.get("id", "")), String(d.get("name", "")), String(d.get("meta", ""))])
	# 「任务关卡」下面那三条难度卡（渲染时取词的文本）
	for i in menu.get("_modes").size() if menu.get("_modes") != null else 0:
		pass
	var modes: Array = menu.get("_modes") if menu.get("_modes") != null else []
	if modes.size() > 0:
		var cards: Array = modes[0].get("cards") if modes.size() > 0 else []
		for c in cards:
			var cd: Dictionary = c as Dictionary
			print("[card] id=%s code=%s rounds=%s" % [
					String(cd.get("id", "")), String(cd.get("code", "")), str(cd.get("rounds", ""))])
	print("=== META DUMP END ===")
	quit()
	return false


func _walk(n: Node, depth: int) -> void:
	var txt := ""
	if n is Label:
		txt = String((n as Label).text)
	elif n is Button:
		txt = String((n as Button).text)
	elif n is RichTextLabel:
		txt = String((n as RichTextLabel).text)
	if txt != "" and (txt.contains("回合") or txt.contains("%") or txt.contains("难度")):
		print("[%s] %s" % [n.get_class(), txt.replace("\n", " / ")])
	for c in n.get_children():
		_walk(c, depth + 1)
