extends Node
## 联机面板截图探针（三态：选择 / 权限说明 / 房主等待）。
##
## 跑法（⛔ 非 headless，headless 截不出图）：
##     godot --path . --quit-after 900 --script res://tools/probe_online_shot.gd
##
## 产物写到 `user://`（工程外，不污染仓库）。
## ⚠️ 不碰内核：建房走 `skip_tunnel`（局域网模式），纯粹为了把「等待好友」那一版画出来。
## ⚠️ 跑它会在 `user://settings.cfg` 里写一个 `ddz_name`（默认「舰长」）—— 这是正经功能键。

const DDZ := "res://scenes/doudizhu.tscn"

var _ddz: Control = null
var _n := 0
var _step := 0


func _ready() -> void:
	_ddz = load(DDZ).instantiate()
	add_child(_ddz)


func _process(_d: float) -> void:
	_n += 1
	match _step:
		0:                                  # 等牌桌建完（面板 `_ready` 里还要等两帧量高度）
			if _n < 14:
				return
			_ddz._online.open_panel()
			_next(1)
		1:                                  # ① 选择：创建 / 加入
			if _n < 8:
				return
			_shot("online_1_choose")
			_ddz._online._on_create(true)
			_next(2)
		2:                                  # ② 权限说明卡（点「创建房间」之后才出现）
			if _n < 8:
				return
			_shot("online_2_permission")
			_ddz._online._begin_host(true)   # 局域网模式建房（不碰内核）
			_next(3)
		3:                                  # ③ 房主等待：房间码 + 玩家列表 + 等好友加入
			if _n < 70:
				return
			_shot("online_3_hosting")
			if _ddz._online.room != null:
				_ddz._online._close_room()
			get_tree().quit(0)
			return
	return


func _next(step: int) -> void:
	_step = step
	_n = 0


func _shot(name: String) -> void:
	var path := "user://%s.png" % name
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("SHOT %s err=%d size=%s → %s" % [name, err, img.get_size(),
			ProjectSettings.globalize_path(path)])
