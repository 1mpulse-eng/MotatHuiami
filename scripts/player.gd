extends CharacterBody2D
const SPEED = 280.0
const ROLL_DISTANCE = 85
const ROLL_DURATION = 0.1
const ROLL_COOLDOWN = 0.35

var is_rolling = false
var can_roll = true
var is_invincible = false
var roll_direction = Vector2.ZERO

var is_attacking = false
var can_attack = true
var _attack_id = 0 # guards against overlapping async attack calls

# Чередование стороны удара (как в Hotline Miami): 0 — слева-направо,
# 1 — справа-налево. Переключается ПОСЛЕ завершения удара (см.
# _on_animation_finished), а не при нажатии кнопки — чтобы кулдаун и
# прерванные атаки не сбивали чередование. idle всегда доигрывает ту же
# сторону, что и последний удар (см. _anim_name).
var attack_side: int = 0

# Процедурное "дыхание" в простое — лёгкое периодическое сжатие/растяжение
# спрайта поверх текущей idle-анимации (см. _process). Работает одинаково для
# любого оружия, без отдельных нарисованных кадров под каждое idle_anim.
@export var breathing_amplitude: float = 0.025
@export var breathing_speed: float = 2.2
var _sprite_base_scale: Vector2 = Vector2.ONE
var _breath_time: float = 0.0

# Текущее оружие как ресурс
var current_weapon: WeaponResource = null
var fists_weapon: WeaponResource = preload("res://weapon/fists.tres")

# Оружие на полу, находящееся в радиусе подбора
var nearby_weapons: Array[WeaponPickup] = []

@onready var tentacle: Tentacle = $Tentacle
@onready var camera: Camera2D = $Camera

func _ready():
	add_to_group("player")
	_sprite_base_scale = $AnimatedSprite2D.scale
	$AttackHitbox/CollisionShape2D.disabled = true
	$AttackHitbox.body_entered.connect(_on_hitbox_body_entered)
	$AnimatedSprite2D.animation_finished.connect(_on_animation_finished)
	$PickupZone.area_entered.connect(_on_pickup_zone_area_entered)
	$PickupZone.area_exited.connect(_on_pickup_zone_area_exited)
	# Стартовое оружие
	equip(preload("res://weapon//bat.tres"))

## Выбирает имя анимации под текущую attack_side. Если у оружия не задан
## alt-вариант (пустая строка в ресурсе), просто отдаёт базовую анимацию —
## оружие без второй стороны продолжает работать как раньше.
func _anim_name(base: String, alt: String) -> String:
	if attack_side == 1 and alt != "":
		return alt
	return base

func equip(weapon: WeaponResource):
	current_weapon = weapon
	# Обновляем размер и позицию хитбокса под оружие
	$AttackHitbox/CollisionShape2D.shape.size = weapon.hitbox_size
	$AttackHitbox.position = weapon.hitbox_offset
	# Сразу переключаем анимацию простоя на новое оружие, а не ждём следующей
	# атаки (раньше спрайт менялся только в _on_animation_finished(), то есть
	# только после удара). is_attacking проверяем на случай, если equip()
	# вызовут прямо посреди своей же атаки — не перебиваем attack_anim.
	if not is_attacking:
		$AnimatedSprite2D.play(_anim_name(weapon.idle_anim, weapon.idle_anim_alt))

func _on_pickup_zone_area_entered(area: Area2D):
	if area is WeaponPickup:
		nearby_weapons.append(area)

func _on_pickup_zone_area_exited(area: Area2D):
	if area is WeaponPickup:
		nearby_weapons.erase(area)

## Ближайшее к курсору оружие среди тех, что уже физически лежат в PickupZone
## (т.е. игрок рядом) — но подбор засчитывается только если курсор наведён
## непосредственно на сам предмет, в пределах Tentacle.HOVER_RADIUS от его
## позиции. Та же логика (и та же константа), что и у щупальца в
## get_closest_weapon() — раньше здесь вместо этого проверялось, попадает ли
## курсор в форму PickupZone (_is_point_in_pickup_zone), из-за чего наведение
## на предмет для себя и для щупальца ощущалось по-разному.
func _get_closest_pickup(mouse_pos: Vector2) -> WeaponPickup:
	var closest: WeaponPickup = null
	var closest_dist := INF
	for w in nearby_weapons:
		if not is_instance_valid(w):
			continue
		var d = w.global_position.distance_squared_to(mouse_pos)
		if d < closest_dist:
			closest_dist = d
			closest = w
	if closest and closest_dist <= Tentacle.HOVER_RADIUS * Tentacle.HOVER_RADIUS:
		return closest
	return null

func pick_up_weapon(pickup: WeaponPickup):
	var picked_weapon = pickup.weapon_resource
	nearby_weapons.erase(pickup)
	pickup.queue_free()
	equip(picked_weapon)

const THROWN_WEAPON_SCENE = preload("res://weapon/thrown_weapon.tscn")

func throw_weapon():
	if current_weapon == null or current_weapon == fists_weapon:
		return
	var thrown = THROWN_WEAPON_SCENE.instantiate()
	thrown.thrower = self
	thrown.weapon_resource = current_weapon
	thrown.direction = (get_global_mouse_position() - global_position).normalized()
	get_parent().add_child(thrown)
	thrown.global_position = global_position
	equip(fists_weapon)
	# Та же лёгкая отдача, что и у броска щупальцем — для консистентности,
	# оба способа бросить оружие должны ощущаться одинаково.
	camera.punch(thrown.direction, 8.0)

## Единый обработчик кнопки "throw" (ПКМ). Порядок для щупальца: бросок (если вооружено) ->
## вырывание оружия у врага под курсором -> подбор оружия с пола в своей зоне.
## Для игрока — как раньше: кулаки -> подбор, оружие -> бросок. Если в этот же нажатие
## бросило щупальце, игрок в этот момент НЕ бросает (сначала разряжается щупальце).
## Единый обработчик кнопки "throw" (ПКМ). За одно нажатие срабатывает РОВНО ОДНО действие
## (либо подбор, либо бросок, либо вырывание) — строгая цепочка приоритетов сверху вниз:
## 1) игрок подбирает оружие в своей зоне (если в руках кулаки) — своё под ногами всегда
##    в приоритете, иначе бросок/подбор щупальца мог бы его перебить. Подбор засчитывается
##    только если курсор наведён на сам предмет (Tentacle.HOVER_RADIUS), иначе игрок будет
##    подбирать оружие "на автомате" просто пробегая мимо, что мешает игре щупальцем.
## 2) щупальце бросает (если вооружено)
## 3) вырывание оружия у врага под курсором (если щупальце пустое)
## 4) щупальце подбирает оружие с пола, на которое наведён курсор (в своей зоне)
## 5) игрок бросает оружие (если вооружен)
## Возвращает строковое название действия, которое произойдёт при нажатии ПКМ прямо сейчас:
## "player_pickup", "tentacle_pickup", "rip", "throw" или "none". Ничего не меняет в состоянии —
## только смотрит, теми же проверками, что и _handle_throw_button(). Используется курсором
## для подсветки (чтобы игрок видел, что сейчас случится по клику).
func get_action_preview() -> String:
	var mouse_pos = get_global_mouse_position()

	if current_weapon == fists_weapon and _get_closest_pickup(mouse_pos) != null:
		return "player_pickup"

	if tentacle.current_weapon != null:
		return "throw"

	if tentacle.has_rippable_enemy(mouse_pos):
		return "rip"

	var exclude_for_tentacle: Array = nearby_weapons if current_weapon == fists_weapon else []
	if tentacle.get_closest_weapon(exclude_for_tentacle, mouse_pos) != null:
		return "tentacle_pickup"

	if current_weapon != fists_weapon:
		return "throw"

	return "none"

func _handle_throw_button():
	var mouse_pos = get_global_mouse_position()

	if current_weapon == fists_weapon:
		var closest = _get_closest_pickup(mouse_pos)
		if closest:
			pick_up_weapon(closest)
			return

	if tentacle.current_weapon != null:
		tentacle.throw_weapon(self)
		# Отдача от броска — слабее, чем ближний удар: это дальнобойное
		# действие, а не столкновение, толчок скорее лёгкий акцент.
		camera.punch((mouse_pos - global_position).normalized(), 8.0)
		return

	if tentacle.try_rip_weapon(mouse_pos):
		# Вырывание оружия у врага — самое "сочное" действие щупальца в игре
		# такого рода, заслуживает реакции заметнее обычного удара кулаком:
		# punch в сторону врага + trauma + небольшой zoom-punch на контрасте.
		var rip_dir = (mouse_pos - global_position).normalized()
		camera.punch(rip_dir, 20.0)
		camera.add_trauma(0.3)
		camera.punch_zoom(0.05)
		return

	# Зону игрока исключаем из кандидатов щупальца только пока игрок реально может
	# там что-то подобрать сам (т.е. держит кулаки). Если в руке уже оружие —
	# своим подбором игрок всё равно не воспользуется, так что щупальце может забрать
	# оружие даже из зоны игрока. На практике до этой строки редко доходит с пустыми
	# руками (пункт 1 уже забрал бы всё из своей зоны), но exclude оставлен как страховка.
	var exclude_for_tentacle: Array = nearby_weapons if current_weapon == fists_weapon else []
	var tw = tentacle.get_closest_weapon(exclude_for_tentacle, mouse_pos)
	if tw:
		tentacle.pick_up_weapon(tw)
		return

	throw_weapon()

## Лёгкое периодическое сжатие/растяжение спрайта поверх idle-анимации —
## имитация дыхания без отдельных нарисованных кадров под каждое оружие.
## Отключается на время атаки/переката, чтобы не мешаться с этими анимациями
## и не оставить спрайт "застрявшим" на не-единичном scale при их старте
## (см. сброс _sprite_base_scale в _play_attack_animation()/_start_roll()).
func _process(delta):
	if is_attacking or is_rolling:
		return
	_breath_time += delta
	var breathe = sin(_breath_time * breathing_speed) * breathing_amplitude
	$AnimatedSprite2D.scale = _sprite_base_scale * (1.0 + breathe)

func _physics_process(delta):
	var direction = Vector2.ZERO
	direction.x = Input.get_axis("ui_left", "ui_right")
	direction.y = Input.get_axis("ui_up", "ui_down")
	direction = direction.normalized()

	if is_rolling:
		var roll_speed = ROLL_DISTANCE / ROLL_DURATION
		velocity = roll_direction * roll_speed
		_update_legs(roll_direction)
	else:
		velocity = direction * SPEED
		rotation = (get_global_mouse_position() - global_position).angle() + PI / 2
		_update_legs(direction)

		if Input.is_action_just_pressed("roll") and can_roll and not is_attacking:
			_start_roll(direction)
		if Input.is_action_just_pressed("attack") and can_attack and not is_rolling:
			if current_weapon == fists_weapon and tentacle.current_weapon != null:
				# Забираем оружие из щупальца в руки и тут же бьём им, одним нажатием
				equip(tentacle.take_weapon())
			_play_attack_animation()
		if Input.is_action_just_pressed("throw") and not is_attacking and not is_rolling:
			_handle_throw_button()

	move_and_slide()

## Ноги (узел Legs) — отдельный AnimatedSprite2D-ребёнок Player. Так как
## Player каждый кадр крутится в сторону курсора (см. rotation = ... выше),
## а Legs — обычный дочерний узел, он наследует это вращение автоматически.
## Чтобы ноги НЕ крутились вслед за телом:
## 1) каждый кадр обнуляем мировой (global) поворот ног — это компенсирует
##    поворот родителя, сам global_rotation-сеттер сам пересчитает нужный
##    локальный rotation с учётом текущего поворота Player;
## 2) вместо поворота спрайта используем 5 отдельных анимаций, переключаемых
##    по направлению WASD, а не по углу до мыши.
func _update_legs(move_direction: Vector2):
	if move_direction == Vector2.ZERO:
		$Legs.global_rotation = 0.0
		if $Legs.animation != "idle":
			$Legs.play("idle")
		return

	var angle = move_direction.angle()

	var base_angles = {
		"walk_right": 0.0,
		"walk_down": PI / 2,
		"walk_left": PI,
		"walk_up": -PI / 2,
	}
	var best_anim = "walk_down"
	var best_diff = INF
	for anim_name in base_angles:
		var diff = wrapf(angle - base_angles[anim_name], -PI, PI)
		if absf(diff) < absf(best_diff):
			best_diff = diff
			best_anim = anim_name

	if $Legs.animation != best_anim:
		$Legs.play(best_anim)

	$Legs.global_rotation = best_diff

func _play_attack_animation():
	if current_weapon == null:
		return

	is_attacking = true
	can_attack = false
	_attack_id += 1
	var this_attack = _attack_id

	$AnimatedSprite2D.scale = _sprite_base_scale
	$AnimatedSprite2D.play(_anim_name(current_weapon.attack_anim, current_weapon.attack_anim_alt))
	# Толчок камеры — в сторону САМОГО УДАРА (лево-право / право-лево),
	# а не туда, куда целится курсор. "Право" и "лево" тут относительно
	# текущего разворота персонажа: берём направление на курсор (forward)
	# и поворачиваем его на 90° в одну или другую сторону в зависимости
	# от attack_side. Если после теста толчок будет визуально в обратную
	# сторону от реального замаха — поменяй местами PI/2 и -PI/2 ниже.
	var facing_dir = (get_global_mouse_position() - global_position).normalized()
	var side_dir = facing_dir.rotated(-PI / 2) if attack_side == 0 else facing_dir.rotated(PI / 2)
	camera.punch(side_dir, 16.0)
	camera.add_trauma(0.15)

	await get_tree().create_timer(current_weapon.damage_delay).timeout

	# If a newer attack started (or we equipped a new weapon) while waiting, bail out.
	if this_attack != _attack_id:
		return

	$AttackHitbox/CollisionShape2D.disabled = false

	# Wait one physics frame so the physics server actually registers the
	# shape as enabled before we ask it who's overlapping. Without this,
	# get_overlapping_bodies() can come back empty when you're already
	# standing right on top of the enemy, and the hit silently misses.
	await get_tree().physics_frame
	if this_attack != _attack_id:
		return
	_check_bodies_already_in_hitbox()

	await get_tree().create_timer(current_weapon.hitbox_active_time).timeout

	if this_attack != _attack_id:
		return

	$AttackHitbox/CollisionShape2D.disabled = true

func _check_bodies_already_in_hitbox():
	# body_entered does NOT fire for bodies already overlapping when the
	# shape is re-enabled, so we manually check once right after enabling.
	for body in $AttackHitbox.get_overlapping_bodies():
		_on_hitbox_body_entered(body)

func _on_animation_finished():
	if current_weapon == null:
		return
	var played_anim = $AnimatedSprite2D.animation
	if played_anim == current_weapon.attack_anim or played_anim == current_weapon.attack_anim_alt:
		is_attacking = false
		# Переключаем сторону ПОСЛЕ удара — следующий замах и текущий idle
		# пойдут уже с другой стороны.
		attack_side = 1 - attack_side
		$AnimatedSprite2D.play(_anim_name(current_weapon.idle_anim, current_weapon.idle_anim_alt))
		# Independent cooldown, decoupled from the hitbox timing above.
		# Comes straight from the equipped weapon — change it in bat.tres.
		await get_tree().create_timer(current_weapon.attack_cooldown).timeout
		can_attack = true

func _on_hitbox_body_entered(body):
	if body == self:
		return
	if body.has_method("take_damage"):
		body.take_damage(current_weapon.damage)
		camera.add_trauma(0.25)
		# Короткий хит-стоп на попадание — 25-35мс почти полной заморозки уже
		# ощутимо добавляет "вес" удару, даже без всяких дополнительных
		# эффектов. Небольшой zoom-punch поверх — ещё немного акцента.
		# Когда появится сигнал "враг убит" — стоит вызывать hit_stop() с
		# бОльшей длительностью (60-100мс) и bigger zoom-punch именно оттуда,
		# а это (0.03/0.05) оставить как базовый "просто попал" отклик.
		camera.hit_stop(0.03, 0.05)
		camera.punch_zoom(0.04)

func _start_roll(input_direction):
	is_rolling = true
	can_roll = false
	is_invincible = true
	$AnimatedSprite2D.scale = _sprite_base_scale

	if input_direction != Vector2.ZERO:
		roll_direction = input_direction
	else:
		var to_mouse = (get_global_mouse_position() - global_position).normalized()
		roll_direction = -to_mouse

	# Лёгкий толчок камеры по направлению рывка + небольшое отдаление (zoom-out),
	# чтобы дэш ощущался быстрее, без физической тряски.
	camera.punch(roll_direction, 12.0)
	camera.punch_zoom(-0.03)

	modulate.a = 0.5
	await get_tree().create_timer(ROLL_DURATION).timeout
	is_rolling = false
	is_invincible = false
	modulate.a = 1.0

	await get_tree().create_timer(ROLL_COOLDOWN).timeout
	can_roll = true

func take_damage(amount):
	if is_invincible:
		return
	print("Получен урон: ", amount)
	camera.add_trauma(0.5)
	# Сознательно НЕ вызываем camera.hit_stop() здесь: Engine.time_scale
	# заморозит игру целиком, в том числе окно на реакцию/roll игрока прямо
	# в момент, когда он и так под угрозой — а именно этого хочется избегать.
	# Trauma (тряска) как отклик на получение урона достаточно и не мешает
	# среагировать.
	#queue_free()
