extends Camera2D

@export var cursor_influence = 0.25  # насколько сильно камера тянется к курсору (0.0 - 1.0)
@export var smoothing = 5.0         # плавность движения камеры

func _process(delta):
	var player_pos = get_parent().global_position
	var mouse_pos = get_global_mouse_position()
	
	# Точка между игроком и курсором
	var target = player_pos.lerp(mouse_pos, cursor_influence)
	
	# Плавно двигаем камеру к этой точке
	global_position = global_position.lerp(target, smoothing * delta)
