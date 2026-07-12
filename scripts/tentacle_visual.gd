@tool
extends Node2D
class_name TentacleVisual

## ============================================================================
## ШАБЛОН СЕГМЕНТНОГО ЩУПАЛЬЦА — куда положить свои спрайты:
##
## 1) SegmentTemplate/Body   (Sprite2D)        -> текстура сегмента тела
## 2) SegmentTemplate/Hinge  (Sprite2D)        -> текстура шарнира-заглушки
## 3) Tip (AnimatedSprite2D) -> SpriteFrames с анимациями "idle"/"reach" (зациклены)
##    и "grab"/"throw" (без Loop, проигрываются разово). Если анимации ещё нет —
##    код откатывается на цветовую вспышку (см. flash_color).
##
## Больше ничего в коде трогать не нужно — пул сегментов и их scale строятся
## автоматически из SegmentTemplate.
## ============================================================================

## Размер пула сегментов. Должен с запасом покрывать max_reach при текущем
## размере текстуры Body — если щупальце не дотягивается до края зоны захвата,
## увеличь это число.
@export var pool_size: int = 18
## Насколько соседние сегменты перекрывают друг друга (0 = встык по размеру
## текстуры, 0.3 = каждый следующий заходит на 30% предыдущего). Шаг между
## сегментами всегда берётся из реальной высоты текстуры Body (_get_segment_render_length),
## так что рассинхронизация с рисованным размером спрайта невозможна.
@export_range(0.0, 0.6) var segment_overlap: float = 0.0
## Общий масштаб щупальца (сегменты, шарниры, кончик), применяется поверх
## собственного scale, заданного на Body/Hinge в редакторе.
@export var visual_scale: float = 0.4
## Максимальная длина вытяжения. Должна совпадать с радиусом CircleShape2D
## зоны щупальца (Tentacle/Zone/CollisionShape2D в player.tscn).
@export var max_reach: float = 137.5101
## Поворотная поправка спрайта сегмента: 0, если "верх" текстуры = направление
## наружу (от базы к кончику). Подбирается под конкретный арт.
@export var segment_rotation_offset: float = 1.596
## Смещение спрайта Tip вбок от оси щупальца, в пикселях (до visual_scale).
## Положительное значение = вправо по ходу щупальца, отрицательное = влево.
## Чисто косметическая подгонка под конкретный арт кончика — на положение
## остальной цепочки не влияет.
@export var tip_side_offset: float = -1.0
## Разворот всей позы покоя (радианы) — если щупальце огибает не ту сторону
## игрока, крутить это число.
@export var idle_base_direction_offset: float = -1.065
## Из скольки сегментов состоит поза покоя (прямо влияет на общую длину дуги).
## Реальное число видимых сегментов на 1 меньше: второй по счёту сегмент
## дуги намеренно выбрасывается из цепочки в _build_curl_angles, форма дуги
## при этом не меняется.
@export var idle_segment_count: int = 5
## Экранный угол первого сегмента (у тела), градусы. 90° = вниз, 0° = вправо,
## -90° = вверх, 180° = влево.
@export var idle_curl_start_deg: float = 90.0
## Экранный угол последнего сегмента (у кончика), градусы. Держи
## |start - end| заметно меньше 180, иначе дуга визуально замыкается в кольцо.
@export var idle_curl_end_deg: float = -110.0
## Неравномерность кривизны дуги покоя (ease-in по параметру t). 1.0 = дуга
## идеальной окружности. Больше 1.0 = у основания щупальце идёт почти прямо,
## а изгиб концентрируется у кончика (силуэт гибкого хлыста).
@export_range(0.5, 4.0) var idle_curl_curve: float = 2.083
## Насколько последний видимый сегмент доворачивается до idle_curl_end_deg.
## 1.0 = садится ровно на end_deg, 0.0 = садится на start_deg (полностью
## выпрямлен). Форма дуги до последнего сегмента не зависит от этого параметра.
@export_range(0.0, 1.0) var idle_last_segment_curl_t: float = 0.657

## Амплитуда виляния цепочки при вытяжении к цели, угасает по мере приближения
## к 100% вытяжения.
@export var reach_wiggle_amplitude: float = 0.15
## Амплитуда органического (не периодического) шума на позы покоя.
@export var idle_jitter_amplitude: float = 0.05
@export var idle_jitter_speed: float = 0.7
## Через сколько секунд (случайно, в этом диапазоне) щупальце само сменит
## позу покоя (право <-> лево).
@export var idle_pose_change_min: float = 4.0
@export var idle_pose_change_max: float = 9.0
@export var idle_pose_blend_duration: float = 1.6

# Цвета запасной вспышки (см. flash_color), пока на Tip нет анимаций grab/throw.
# Используются извне (tentacle.gd): COLOR_PICKUP в pick_up_weapon, COLOR_RIP в
# try_rip_weapon, COLOR_THROW в throw_weapon.
const COLOR_RIP = Color(0.9, 0.15, 0.15)
const COLOR_PICKUP = Color(0.6, 0.15, 0.55)
const COLOR_THROW = Color(0.85, 0.7, 0.2)

# Поза покоя = пара чисел (_current_start_deg/_current_end_deg). Зеркалирование
# право<->лево — это mirrored = 180 - x, переход твинится напрямую по этим двум
# числам, поэтому вся дуга проходит через общую промежуточную форму синхронно.
var _current_start_deg: float = 0.0
var _current_end_deg: float = 0.0
## Живая версия idle_base_direction_offset — как и start/end, зеркалится и
## твинится при смене стороны покоя (см. _pick_new_idle_pose), иначе базовое
## направление щупальца оставалось бы приклеено к одной стороне, а честно
## отражалась бы только кривизна дуги поверх него.
var _current_base_offset: float = 0.0
var _mirrored: bool = false
var _current_angles: Array = []

## Текущее состояние горизонтального флипа Tip/WeaponSprite. Хранится отдельно
## от _mirrored (который переключается МГНОВЕННО в момент выбора новой idle-позы,
## пока сама поза ещё 1.6 сек едет через твин) — переключается по фактическому
## знаку tip_dir.x в _update_chain(), то есть ровно в момент, когда цепочка
## визуально проходит через вертикаль, синхронно с поворотом. С небольшой
## мёртвой зоной (см. TIP_FLIP_DEADZONE), чтобы не дребезжало возле tip_dir.x≈0.
var _tip_flipped: bool = false
const TIP_FLIP_DEADZONE: float = 0.05

var _time: float = 0.0
var _extension: float = 0.0                # 0..1, степень вытяжения к цели
var _target_local: Vector2 = Vector2.ZERO   # цель в локальных координатах узла

var _pose_timer: float = 0.0
var _next_pose_change: float = 0.0

## Затухающее колебание позы покоя сразу после retract() — имитация инерции.
var _settle_wobble: float = 0.0

var _noise := FastNoiseLite.new()

var _pool_segments: Array = []
var _pool_bodies: Array = []
var _pool_hinges: Array = []

# Исходный scale Body/Hinge из редактора — используется как множитель, чтобы
# visual_scale масштабировал оба разом, сохраняя их пропорцию друг к другу.
# Для Tip такой множитель не нужен (единичный узел без пары), там visual_scale
# применяется напрямую.
var _body_base_scale: Vector2 = Vector2.ONE
var _hinge_base_scale: Vector2 = Vector2.ONE

# Ссылки на твины — чтобы убивать предыдущий перед созданием нового и не
# получать несколько твинов, тянущих одно поле одновременно.
var _extension_tween: Tween
var _pose_tween: Tween
var _wobble_tween: Tween
var _anticipation_tween: Tween
var _flash_tween: Tween

@onready var segment_pool: Node2D = $SegmentPool
@onready var segment_template: Node2D = $SegmentTemplate
@onready var tip: AnimatedSprite2D = $Tip
@onready var weapon_sprite: Sprite2D = $Tip/WeaponSprite


func _ready():
	_noise.seed = randi()
	_noise.frequency = 0.15

	_body_base_scale = segment_template.get_node("Body").scale
	_hinge_base_scale = segment_template.get_node("Hinge").scale

	tip.scale = Vector2.ONE * visual_scale
	_build_segment_pool()
	_current_start_deg = idle_curl_start_deg
	_current_end_deg = idle_curl_end_deg
	_current_base_offset = idle_base_direction_offset
	_current_angles = _build_curl_angles(_current_start_deg, _current_end_deg, idle_segment_count)
	if Engine.is_editor_hint():
		# В редакторе таймеры смены позы/вес оружия не нужны — только сама дуга.
		return
	weapon_sprite.visible = false
	weapon_sprite.z_index = -1
	_schedule_next_pose_change()


## Строит массив углов (радианы, "относительно Vector2.DOWN") для idle-позы:
## первый сегмент смотрит под start_deg, последний — под end_deg, промежуточные —
## по ease-кривой idle_curl_curve. Зеркалирование делается не здесь, а выбором
## других start_deg/end_deg (см. _pick_new_idle_pose).
## Дополнительно: второй по счёту сегмент выбрасывается из готовой дуги (форма
## кривой не пересчитывается, меняется только число видимых звеньев), а
## последняя точка доворачивается не до полного end_deg, а на долю
## idle_last_segment_curl_t.
func _build_curl_angles(start_deg: float, end_deg: float, count: int) -> Array:
	var result: Array = []
	var curve_power: float = _safe_curve_power()
	for i in range(count):
		var t = float(i) / float(max(count - 1, 1))
		var t_eased = pow(t, curve_power)
		var screen_angle_deg = lerp(start_deg, end_deg, t_eased)
		result.append(deg_to_rad(screen_angle_deg - 90.0))

	if result.size() > 2:
		result.remove_at(1)

	if result.size() > 0:
		var outward_screen_deg = lerp(start_deg, end_deg, idle_last_segment_curl_t)
		result[result.size() - 1] = deg_to_rad(outward_screen_deg - 90.0)

	return result


## Защита от Nil-override idle_curl_curve, который иногда остаётся в .tscn
## при добавлении нового @export-поля в уже сохранённую сцену. Если такое
## случится — открой инспектор, впиши значение в "Idle Curl Curve" руками и
## пересохрани сцену (Ctrl+S), после этого override починится сам.
func _safe_curve_power() -> float:
	if typeof(idle_curl_curve) != TYPE_FLOAT and typeof(idle_curl_curve) != TYPE_INT:
		return 1.0
	var v: float = float(idle_curl_curve)
	if not is_finite(v) or v <= 0.0:
		return 1.0
	return v


## Дублирует SegmentTemplate pool_size раз, текстуры Body/Hinge копируются
## автоматически.
func _build_segment_pool():
	for i in range(pool_size):
		var seg = segment_template.duplicate()
		seg.visible = false
		segment_pool.add_child(seg)
		_pool_segments.append(seg)
		var body: Sprite2D = seg.get_node("Body")
		var hinge: Sprite2D = seg.get_node("Hinge")
		body.scale = _body_base_scale * visual_scale
		hinge.scale = _hinge_base_scale * visual_scale
		_pool_bodies.append(body)
		_pool_hinges.append(hinge)


## Реальная высота сегмента на экране (с учётом visual_scale и _body_base_scale,
## без scale Player и без segment_overlap), берётся напрямую из текстуры Body.
func _get_segment_render_length() -> float:
	var body_texture: Texture2D = _pool_bodies[0].texture if _pool_bodies.size() > 0 else segment_template.get_node("Body").texture
	var raw_height = body_texture.get_height() if body_texture else 32.0
	var effective_scale_y = maxf(_body_base_scale.y * visual_scale, 0.001)
	return raw_height * effective_scale_y


## Реальная высота текущего кадра Tip на экране (с учётом visual_scale, без
## scale Player). Текстура Tip обычно отличается по размеру от Body, поэтому
## смещение кончика от шарнира нужно считать по ЕГО собственному размеру, а не
## по размеру Body — иначе центр Tip оказывается не там, где должно быть его
## начало, и спрайт кончика наезжает на предыдущий сегмент.
func _get_tip_render_length() -> float:
	if tip.sprite_frames == null or not tip.sprite_frames.has_animation(tip.animation):
		return _get_segment_render_length()
	var frame_count = tip.sprite_frames.get_frame_count(tip.animation)
	if frame_count == 0:
		return _get_segment_render_length()
	var tip_texture: Texture2D = tip.sprite_frames.get_frame_texture(tip.animation, 0)
	if tip_texture == null:
		return _get_segment_render_length()
	return tip_texture.get_height() * maxf(visual_scale, 0.001)


func _schedule_next_pose_change():
	_next_pose_change = randf_range(idle_pose_change_min, idle_pose_change_max)
	_pose_timer = 0.0


func _process(delta):
	if Engine.is_editor_hint():
		# Живой предпросмотр в редакторе: каждый кадр перечитываем @export-поля
		# и перерисовываем дугу, чтобы ползунки сразу отражались во вьюпорте.
		_ensure_pool_matches_size()
		_current_start_deg = idle_curl_start_deg
		_current_end_deg = idle_curl_end_deg
		_current_base_offset = idle_base_direction_offset
		_current_angles = _build_curl_angles(_current_start_deg, _current_end_deg, idle_segment_count)
		_extension = 0.0
		_update_chain()
		return

	_time += delta
	_current_angles = _build_curl_angles(_current_start_deg, _current_end_deg, idle_segment_count)

	if _extension <= 0.0001:
		_pose_timer += delta
		if _pose_timer >= _next_pose_change:
			_pick_new_idle_pose()

	_update_chain()


## Только для редакторского предпросмотра: пересобирает пул при смене pool_size,
## переприменяет масштаб при смене visual_scale. Дополнительно каждый кадр
## обновляет _body_base_scale/_hinge_base_scale с самого SegmentTemplate — без
## этого правка Scale на Body/Hinge прямо в открытой сцене не подхватывалась бы
## (кэш этих значений раньше читался только один раз в _ready), из-за чего
## визуальный размер сегмента и шаг между ними (spacing, который тоже считается
## через этот кэш в _get_segment_render_length) могли разъехаться и в дуге
## появлялись пустые промежутки.
func _ensure_pool_matches_size():
	_body_base_scale = segment_template.get_node("Body").scale
	_hinge_base_scale = segment_template.get_node("Hinge").scale
	if _pool_segments.size() != pool_size:
		for child in segment_pool.get_children():
			child.free()
		_pool_segments.clear()
		_pool_bodies.clear()
		_pool_hinges.clear()
		_build_segment_pool()
		return
	for body in _pool_bodies:
		body.scale = _body_base_scale * visual_scale
	for hinge in _pool_hinges:
		hinge.scale = _hinge_base_scale * visual_scale
	tip.scale = Vector2.ONE * visual_scale


## Переключает щупальце на зеркальную сторону (право <-> лево) по таймеру.
## Твинятся два числа (start/end градусы) — вся дуга проходит через общую
## промежуточную форму синхронно, без излома посередине.
func _pick_new_idle_pose():
	_mirrored = not _mirrored
	var target_start = idle_curl_start_deg if not _mirrored else (180.0 - idle_curl_start_deg)
	var target_end = idle_curl_end_deg if not _mirrored else (180.0 - idle_curl_end_deg)
	# idle_base_direction_offset — тоже часть позы, а не константа: отражение
	# угла относительно вертикали — это смена знака. Без этого зеркалилась бы
	# только кривизна дуги, а базовое направление щупальца оставалось приклеено
	# к одной стороне.
	var target_base_offset = idle_base_direction_offset if not _mirrored else -idle_base_direction_offset
	_blend_to_pose(target_start, target_end, target_base_offset)
	_schedule_next_pose_change()


func _blend_to_pose(target_start: float, target_end: float, target_base_offset: float, duration: float = -1.0):
	if duration < 0.0:
		duration = idle_pose_blend_duration
	if _pose_tween and _pose_tween.is_valid():
		_pose_tween.kill()
	_pose_tween = create_tween()
	_pose_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pose_tween.tween_property(self, "_current_start_deg", target_start, duration)
	_pose_tween.parallel().tween_property(self, "_current_end_deg", target_end, duration)
	_pose_tween.parallel().tween_property(self, "_current_base_offset", target_base_offset, duration)


## Строит цепочку: направление каждого активного сегмента (в покое — поза +
## шум, при вытяжении — к цели с затухающим виляньем), раскладывает Body/Hinge
## по позициям, прячет неиспользуемые сегменты пула. Первый шарнир всегда в
## (0,0). Hinge показывается на каждом активном сегменте всегда.
func _update_chain():
	var dirs: Array = []

	if _extension <= 0.0001:
		var base_dir = Vector2.DOWN.rotated(_current_base_offset + _settle_wobble)
		for i in range(_current_angles.size()):
			var jitter = _noise.get_noise_2d(float(i) * 5.0, _time * idle_jitter_speed * 10.0) * idle_jitter_amplitude
			dirs.append(base_dir.rotated(_current_angles[i] + jitter))
		_set_tip_animation("idle")
	else:
		var to_target := _target_local
		var dist = min(to_target.length(), max_reach)
		var target_dir = to_target.normalized() if to_target.length() > 0.001 else Vector2.DOWN
		var reach_len = dist * _extension
		var count = clamp(int(ceil(reach_len / _get_segment_render_length() / (1.0 - segment_overlap))), 0, pool_size)
		var falloff = 1.0 - _extension
		var perp = target_dir.orthogonal()
		var idle_base_dir = Vector2.DOWN.rotated(_current_base_offset)
		# Раскрутка: на старте вытяжения цепочка ещё повторяет позу покоя, и по
		# мере роста _extension каждый сегмент разворачивается к прямому
		# направлению на цель — щупальце видимо разматывается.
		var straighten = smoothstep(0.0, 1.0, clamp(_extension * 1.6, 0.0, 1.0))
		for i in range(count):
			var wiggle = sin(float(i) * 0.9 + _time * 3.0) * reach_wiggle_amplitude * falloff
			var reach_dir = (target_dir + perp * wiggle).normalized()
			var idle_index = min(i, _current_angles.size() - 1)
			var idle_dir = idle_base_dir.rotated(_current_angles[idle_index]) if _current_angles.size() > 0 else target_dir
			var dir: Vector2
			if idle_dir.dot(reach_dir) < -0.999:
				dir = reach_dir
			else:
				dir = idle_dir.slerp(reach_dir, straighten).normalized()
			dirs.append(dir)
		_set_tip_animation("reach")

	var pos := Vector2.ZERO
	var render_length = _get_segment_render_length()
	# Сегменты рисуются полным размером текстуры, но сдвигаются друг относительно
	# друга на spacing (меньше при segment_overlap > 0).
	var spacing = render_length * (1.0 - segment_overlap)
	# Последний элемент dirs — это слот кончика: своего Body у него нет (это
	# место занимает Tip), а вот Hinge остаётся и играет роль шва между
	# последним видимым телом и Tip (см. ветку i == body_count ниже).
	var body_count = max(dirs.size() - 1, 0)
	for i in range(pool_size):
		var segment: Node2D = _pool_segments[i]
		var body: Sprite2D = _pool_bodies[i]
		var hinge: Sprite2D = _pool_hinges[i]
		if i < body_count:
			var dir: Vector2 = dirs[i]
			segment.visible = true
			segment.position = pos
			body.visible = true
			body.position = dir * (render_length * 0.5)
			body.rotation = dir.angle() + segment_rotation_offset
			hinge.position = Vector2.ZERO
			hinge.visible = true
			pos += dir * spacing
		elif i == body_count and dirs.size() > 0:
			# Слот кончика: свой Body у этого сегмента не рисуем (его место
			# занимает Tip), а вот Hinge того же сегмента переиспользуем как
			# шов между последним видимым телом и Tip — отдельный узел под то
			# же самое заводить незачем, в пуле он уже есть на каждый сегмент.
			segment.visible = true
			segment.position = pos
			body.visible = false
			hinge.position = Vector2.ZERO
			hinge.visible = true
		else:
			segment.visible = false

	if dirs.size() > 0:
		var tip_dir: Vector2 = dirs[dirs.size() - 1]
		var tip_length = _get_tip_render_length()

		# Флип кончика по фактическому знаку tip_dir.x (а не по _mirrored —
		# та переключается мгновенно, а поза потом ещё едет через твин 1.6 сек;
		# так флип срабатывает ровно в момент, когда цепочка проходит через
		# вертикаль, синхронно с поворотом, а не раньше/позже). Мёртвая зона
		# TIP_FLIP_DEADZONE вокруг нуля — чтобы не дёргалось от idle_jitter,
		# когда цепочка почти строго вертикальна.
		if tip_dir.x > TIP_FLIP_DEADZONE:
			_tip_flipped = true
		elif tip_dir.x < -TIP_FLIP_DEADZONE:
			_tip_flipped = false
		tip.flip_h = _tip_flipped
		weapon_sprite.flip_h = _tip_flipped

		# "Лево" считается относительно направления кончика (dir, повёрнутый на
		# -90°), а не экрана — так смещение остаётся визуально одинаковым и в
		# зеркальной позе покоя, и при вытяжении в любую сторону.
		# ИСПРАВЛЕНО: одного flip_h недостаточно — art Tip несимметричен, и
		# tip_side_offset был подобран под НЕотзеркаленную ориентацию. После
		# flip_h та же сторона в локальных координатах текстуры соответствует
		# противоположной физической стороне, поэтому знак смещения тоже нужно
		# перевернуть — иначе offset продолжает толкать спрайт в старую сторону
		# поверх уже отзеркаленной текстуры, и кончик визуально "съезжает"
		# относительно места стыка с последним сегментом цепочки.
		var side := tip_dir.rotated(-PI / 2.0)
		var side_offset = -tip_side_offset if _tip_flipped else tip_side_offset
		tip.position = pos + tip_dir * (tip_length * 0.5) + side * side_offset
		tip.rotation = tip_dir.angle() + segment_rotation_offset
	else:
		tip.position = pos


func _set_tip_animation(anim_name: String):
	if not tip.sprite_frames or not tip.sprite_frames.has_animation(anim_name):
		return
	# Пока в щупальце что-то зажато, idle не крутим — держим кончик статично
	# на 0 кадре, чтобы схваченный предмет не подрагивал вместе с петлёй.
	if anim_name == "idle" and weapon_sprite.visible:
		if tip.animation != anim_name:
			tip.animation = anim_name
		tip.stop()
		tip.frame = 0
		return
	if tip.animation != anim_name:
		tip.play(anim_name)


## Плавно вытягивается к глобальной позиции цели за duration секунд.
func reach_to(target_global: Vector2, duration: float = 0.25, trans := Tween.TRANS_CUBIC, ease := Tween.EASE_OUT):
	_target_local = to_local(target_global)
	_play_tip_anticipation()
	if _extension_tween and _extension_tween.is_valid():
		_extension_tween.kill()
	_extension_tween = create_tween()
	_extension_tween.set_trans(trans).set_ease(ease)
	_extension_tween.tween_property(self, "_extension", 1.0, duration)


## Плавно возвращается в состояние покоя, затем "дожимает" затухающее
## колебание позы (см. _play_settle_wobble).
func retract(duration: float = 0.2):
	if _extension_tween and _extension_tween.is_valid():
		_extension_tween.kill()
	_extension_tween = create_tween()
	_extension_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_extension_tween.tween_property(self, "_extension", 0.0, duration)
	_extension_tween.tween_callback(_play_settle_wobble)


## Короткое затухающее колебание позы покоя — имитация инерции гибкого материала.
func _play_settle_wobble(kick_deg: float = 12.0, duration: float = 0.45):
	_settle_wobble = deg_to_rad(kick_deg) * (1 if randi() % 2 == 0 else -1)
	if _wobble_tween and _wobble_tween.is_valid():
		_wobble_tween.kill()
	_wobble_tween = create_tween()
	_wobble_tween.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_wobble_tween.tween_property(self, "_settle_wobble", 0.0, duration)


## Короткий "поджим" кончика перед броском (squash-and-stretch) — подготовительное
## движение для более резкого рывка, даже без готовой анимации grab/throw.
func _play_tip_anticipation(strength: float = 0.3, duration: float = 0.08):
	var base_scale = Vector2.ONE * visual_scale
	tip.scale = base_scale * (1.0 - strength)
	if _anticipation_tween and _anticipation_tween.is_valid():
		_anticipation_tween.kill()
	_anticipation_tween = create_tween()
	_anticipation_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_anticipation_tween.tween_property(tip, "scale", base_scale, duration)


## Проигрывает анимацию действия на кончике (grab/throw). Если такой анимации
## ещё нет в SpriteFrames — откатывается на цветовую вспышку.
func flash_color(color: Color, duration: float = 0.15):
	var anim_name = "grab"
	if color == COLOR_THROW:
		anim_name = "throw"

	if tip.sprite_frames and tip.sprite_frames.has_animation(anim_name):
		tip.play(anim_name)
		return

	tip.modulate = color
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(tip, "modulate", Color(1, 1, 1, 1), duration)


func set_held_weapon(weapon: WeaponResource):
	if weapon == null:
		weapon_sprite.visible = false
		return
	weapon_sprite.texture = weapon.texture
	# ИСПРАВЛЕНО: раньше здесь стояло "weapon_sprite.global_scale = Vector2.ONE
	# * weapon.pickup_scale" — а global_scale-сеттер решает нужный ЛОКАЛЬНЫЙ
	# scale через ТЕКУЩИЙ global_scale родителя (Tip) в момент вызова. Проблема
	# в том, что pick_up_weapon()/try_rip_weapon() в tentacle.gd вызывают
	# reach_to() ДО set_held_weapon(), а reach_to() первым делом дёргает
	# _play_tip_anticipation(), которая СИНХРОННО ужимает tip.scale до 70% от
	# нормального (squash перед рывком) и только потом за 0.08 сек твинит его
	# обратно. Если set_held_weapon() срабатывает именно в этом окне, он
	# компенсирует случайно подвернувшийся 70%-й масштаб Tip вместо настоящего
	# — итоговый scale оружия получается примерно в 1/0.7 ≈ 1.43 раза больше
	# нужного и остаётся раздутым навсегда (пока не пересчитается заново на
	# следующем подборе/вырывании с той же ошибкой). Оружие на полу (WeaponPickup)
	# этой цепочки не задевает и потому всегда выглядит нормально — отсюда и
	# разница "в щупальце большое / на земле нормальное".
	# Чиним, беря масштаб предков ВЫШЕ Tip (Player/Tentacle/TentacleVisual —
	# они не анимируются, их global_scale стабилен) и НАМЕРЕННЫЙ масштаб самого
	# Tip в покое (visual_scale), а не его текущее, возможно ужатое значение.
	var ancestors_scale = tip.get_parent().global_scale if tip.get_parent() else Vector2.ONE
	var safe_visual_scale = maxf(visual_scale, 0.001)
	weapon_sprite.scale = (Vector2.ONE * weapon.pickup_scale) / (ancestors_scale * safe_visual_scale)
	weapon_sprite.visible = true
