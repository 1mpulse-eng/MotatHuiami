extends AnimatedSprite2D
var player: Node = null
# Цвета курсора под конкретное действие. Поправь под свой вкус/арт.
const COLOR_NONE = Color(1, 1, 1, 1)                    # обычный — ничего не произойдёт
const COLOR_PLAYER_PICKUP = Color(0.3, 1.0, 0.35, 1)    # зелёный — игрок подберёт сам
const COLOR_TENTACLE_PICKUP = Color(0.7, 0.2, 0.75, 1)  # фиолетовый (цвет щупальца) — подберёт оно
const COLOR_RIP = Color(1.0, 0.15, 0.15, 1)             # красный — наведены на врага, можно вырвать оружие
const COLOR_THROW = Color(1, 1, 1, 1)            # жёлтый — готовы кинуть оружие

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	centered = true
	top_level = true # чтобы позиция курсора не зависела от родителя

func _process(delta):
	global_position = get_viewport().get_mouse_position()
	_update_color()

func _update_color():
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("get_action_preview"):
		return
	match player.get_action_preview():
		"player_pickup":
			modulate = COLOR_PLAYER_PICKUP
		"tentacle_pickup":
			modulate = COLOR_TENTACLE_PICKUP
		"rip":
			modulate = COLOR_RIP
		"throw":
			modulate = COLOR_THROW
		_:
			modulate = COLOR_NONE
