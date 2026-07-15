extends Camera2D

@export var cursor_influence = 0.25  # насколько сильно камера тянется к курсору (0.0 - 1.0)
@export var smoothing = 5.0         # плавность движения камеры

# --- Screen shake ---
# trauma затухает сам со временем (add_trauma только добавляет, никогда не
# ставит напрямую) — так несколько попаданий подряд не обрывают друг друга,
# а честно суммируются. offset = trauma^2, чтобы шейк не выглядел как ровное
# дрожание, а резко "толкал" в начале и мягко угасал.
@export var max_shake_offset: float = 16.0
@export var shake_decay: float = 5.0
var _trauma: float = 0.0

# --- Directional punch (смещение в сторону удара) ---
@export var punch_decay: float = 6.0
var _punch_offset: Vector2 = Vector2.ZERO

func _process(delta):
	var player_pos = get_parent().global_position
	var mouse_pos = get_global_mouse_position()

	# Точка между игроком и курсором
	var target = player_pos.lerp(mouse_pos, cursor_influence)

	# Плавно двигаем камеру к этой точке
	global_position = global_position.lerp(target, smoothing * delta)

	# Shake
	if _trauma > 0.0:
		_trauma = max(_trauma - shake_decay * delta, 0.0)
	var shake_amount = _trauma * _trauma
	var shake_vec = Vector2.ZERO
	if shake_amount > 0.0:
		shake_vec = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * max_shake_offset * shake_amount

	# Punch затухает к нулю
	_punch_offset = _punch_offset.lerp(Vector2.ZERO, punch_decay * delta)

	offset = shake_vec + _punch_offset

## Добавить тряску. amount от 0.0 до 1.0 — например 0.2 за свой удар,
## 0.4-0.5 за попадание по игроку (получение урона обычно чувствуется сильнее,
## чем нанесение). Суммируется с текущим trauma, а не перезаписывает его.
func add_trauma(amount: float):
	_trauma = clamp(_trauma + amount, 0.0, 1.0)

## Импульс камеры в направлении удара. direction — не обязательно нормализован,
## strength — сила толчка в пикселях. Вызывать в момент старта атаки/получения урона.
func punch(direction: Vector2, strength: float = 12.0):
	if direction == Vector2.ZERO:
		return
	_punch_offset += direction.normalized() * strength
