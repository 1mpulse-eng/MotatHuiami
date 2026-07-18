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

# Сглаженный шум вместо чистого randf_range каждый кадр — иначе тряска
# дёргается как "статик" на телевизоре. Раз в shake_noise_interval секунд
# берём новую случайную цель и лерпим текущий вектор к ней, а не дёргаем
# его резко каждый кадр. Интервал побольше и скорость поменьше, чем в первой
# версии — так волна шума мягче, без резких "тиков".
@export var shake_noise_speed: float = 10.0  # скорость сближения с целью шума
@export var shake_noise_interval: float = 0.05  # как часто менять цель шума
var _shake_noise_target: Vector2 = Vector2.ZERO
var _shake_noise_current: Vector2 = Vector2.ZERO
var _shake_noise_timer: float = 0.0

# --- Directional punch (смещение в сторону удара) ---
# _punch_target — "сырое" значение: сюда добавляется импульс и оно же
# затухает к нулю (punch_decay). _punch_rendered — то, что реально идёт в
# offset: оно ПЛАВНО ДОГОНЯЕТ _punch_target (punch_attack), а не наследует
# его скачком. Из-за этого в момент удара камера не дёргается мгновенно,
# а быстро, но плавно, разгоняется в сторону толчка — и так же плавно,
# без излома, спадает обратно вместе с угасанием target.
@export var punch_decay: float = 6.0
@export var punch_attack: float = 45.0  # скорость нарастания к цели; больше = резче начальный рывок
@export var max_punch_offset: float = 64.0  # защита от "улёта" камеры при серии попаданий подряд — увеличен вместе с дальностью отброса
var _punch_target: Vector2 = Vector2.ZERO
var _punch_rendered: Vector2 = Vector2.ZERO

# --- Zoom punch (килл-панч, дэш) ---
# Та же логика "target/rendered", что и у punch выше — сглаживаем не только
# затухание, но и сам момент применения импульса.
@export var zoom_decay: float = 8.0
@export var zoom_attack: float = 10.0
var _zoom_target: float = 0.0
var _zoom_rendered: float = 0.0
var _base_zoom: Vector2 = Vector2.ONE  # тот zoom, что выставлен на ноде в редакторе

# Low-pass ТОЛЬКО для шейка (сглаживает шум, чтобы не было "статика").
# Раньше это же сглаживание накладывалось и на punch, из-за чего резкость
# самого рывка глохла вместе с шумом — вынес их в разные пути ниже.
@export var offset_smoothing: float = 22.0
var _rendered_offset: Vector2 = Vector2.ZERO

func _ready():
	_base_zoom = zoom  # запоминаем ДО того, как _process начнёт его трогать

# --- Hit-stop (freeze-frame на попаданиях) ---
# Engine.time_scale глобальный, так что несколько наложившихся вызовов
# hit_stop() не должны портить друг друга: если пришёл более сильный/длинный
# запрос, пока предыдущий ещё активен — просто продлеваем текущий, а не
# запускаем второй параллельный таймер поверх первого.
var _hit_stop_active: bool = false
var _hit_stop_id: int = 0

func _process(delta):
	var player_pos = get_parent().global_position
	var mouse_pos = get_global_mouse_position()

	# Точка между игроком и курсором
	var target = player_pos.lerp(mouse_pos, cursor_influence)

	# Плавно двигаем камеру к этой точке.
	# 1.0 - exp(-smoothing * delta) вместо smoothing * delta — не зависит от
	# framerate даже при просадках/лаг-спайках (обычный lerp(t, k*delta) при
	# k*delta > 1 может "перелететь" цель или задёргаться).
	global_position = global_position.lerp(target, 1.0 - exp(-smoothing * delta))

	# --- Shake ---
	if _trauma > 0.0:
		_trauma = max(_trauma - shake_decay * delta, 0.0)
	var shake_amount = _trauma * _trauma

	_shake_noise_timer -= delta
	if _shake_noise_timer <= 0.0:
		_shake_noise_timer = shake_noise_interval
		_shake_noise_target = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	_shake_noise_current = _shake_noise_current.lerp(_shake_noise_target, 1.0 - exp(-shake_noise_speed * delta))
	var shake_vec = _shake_noise_current * max_shake_offset * shake_amount

	# --- Punch ---
	# Сначала "сырая" цель угасает сама к нулю...
	_punch_target = _punch_target.lerp(Vector2.ZERO, 1.0 - exp(-punch_decay * delta))
	# ...а рендерящееся значение плавно её догоняет (и вверх, и вниз) —
	# это убирает резкий скачок в момент самого удара.
	_punch_rendered = _punch_rendered.lerp(_punch_target, 1.0 - exp(-punch_attack * delta))

	# Low-pass применяем только к шейку (там он борется с "статиком" от шума),
	# а не к сумме shake+punch — иначе он же гасил и резкость самого панча,
	# что и было проблемой. Punch после punch_attack уже сам по себе достаточно
	# резкий на пике, ему этот фильтр сверху не нужен.
	_rendered_offset = _rendered_offset.lerp(shake_vec, 1.0 - exp(-offset_smoothing * delta))
	offset = _rendered_offset + _punch_rendered

	# --- Zoom punch ---
	_zoom_target = lerp(_zoom_target, 0.0, 1.0 - exp(-zoom_decay * delta))
	_zoom_rendered = lerp(_zoom_rendered, _zoom_target, 1.0 - exp(-zoom_attack * delta))
	zoom = _base_zoom * (1.0 - _zoom_rendered)

## Добавить тряску. amount от 0.0 до 1.0 — например 0.2 за свой удар,
## 0.4-0.5 за попадание по игроку (получение урона обычно чувствуется сильнее,
## чем нанесение). Суммируется с текущим trauma, а не перезаписывает его.
func add_trauma(amount: float):
	_trauma = clamp(_trauma + amount, 0.0, 1.0)

## Импульс камеры в направлении удара. direction — не обязательно нормализован,
## strength — сила толчка в пикселях. Вызывать в момент старта атаки/получения урона.
## Ограничено max_punch_offset — если несколько ударов прилетают быстрее, чем
## успевает отработать decay (толпа врагов, серия атак), офсет не улетает
## бесконечно, а держит потолок. Сам толчок применяется к _punch_target, а не
## напрямую к тому, что видно на экране — рендер плавно догонит его в _process.
func punch(direction: Vector2, strength: float = 12.0):
	if direction == Vector2.ZERO:
		return
	_punch_target += direction.normalized() * strength
	_punch_target = _punch_target.limit_length(max_punch_offset)

## Импульс зума. Положительное amount — резкое приближение (килл-панч),
## отрицательное — отдаление (например, старт рывка/дэша). Затухает сам,
## как и punch/trauma, суммируется с текущим значением.
func punch_zoom(amount: float):
	_zoom_target += amount

## Хит-стоп / freeze-frame. duration — сколько РЕАЛЬНОГО (не игрового) времени
## держим замедление, scale — во сколько раз замедляется время (0.0 = полная
## заморозка, 0.05 = почти стоп но не совсем). Использует Engine.time_scale,
## поэтому влияет на всю игру, а не только на камеру — учитывай это при вызове
## из мест, где инпут/анимации должны идти по unscaled-времени.
## Если новый вызов пришёл, пока предыдущий hit_stop ещё активен, просто
## перезапускаем таймер (продлеваем), а не плодим параллельные корутины,
## которые в итоге начнут спорить друг с другом за Engine.time_scale.
func hit_stop(duration: float = 0.05, scale: float = 0.05):
	_hit_stop_id += 1
	var this_id = _hit_stop_id

	Engine.time_scale = scale
	_hit_stop_active = true

	# create_timer(..., ignore_time_scale = true) — ждём по реальному времени,
	# иначе таймер сам зависнет вместе с time_scale.
	await get_tree().create_timer(duration, true, false, true).timeout

	# Если за время ожидания пришёл более новый hit_stop (например, второй килл
	# почти сразу после первого) — не сбрасываем time_scale, пусть отработает
	# он, это его ответственность вернуть время на место.
	if this_id != _hit_stop_id:
		return

	Engine.time_scale = 1.0
	_hit_stop_active = false
