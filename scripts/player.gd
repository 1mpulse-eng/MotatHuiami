extends CharacterBody2D
const SPEED = 270.0
const ROLL_DISTANCE = 85
const ROLL_DURATION = 0.1
const ROLL_COOLDOWN = 0.4

var is_rolling = false
var can_roll = true
var is_invincible = false
var roll_direction = Vector2.ZERO

var is_attacking = false
var can_attack = true
var _attack_id = 0 # guards against overlapping async attack calls

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
		$AnimatedSprite2D.play(weapon.idle_anim)

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
		return

	if tentacle.try_rip_weapon(mouse_pos):
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
	$AnimatedSprite2D.play(current_weapon.attack_anim)

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
	if $AnimatedSprite2D.animation == current_weapon.attack_anim:
		is_attacking = false
		$AnimatedSprite2D.play(current_weapon.idle_anim)
		# Independent cooldown, decoupled from the hitbox timing above.
		# Comes straight from the equipped weapon — change it in bat.tres.
		await get_tree().create_timer(current_weapon.attack_cooldown).timeout
		can_attack = true

func _on_hitbox_body_entered(body):
	if body == self:
		return
	if body.has_method("take_damage"):
		body.take_damage(current_weapon.damage)

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
	#queue_free()
