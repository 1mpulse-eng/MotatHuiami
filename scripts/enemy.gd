extends CharacterBody2D
const SPEED = 250.0
const MAX_HP = 1
const REACTION_TIME = 0.3
const PROXIMITY_REACTION_TIME = 0.8
const ATTACK_RANGE = 45.0    # дистанция при которой враг останавливается и бьёт (соответствует реальному радиусу AttackArea)
const WEAPON_PICKUP_RANGE = 30.0 # дистанция, на которой безоружный враг подбирает оружие с пола

## Стартовое оружие врага — назначается в инспекторе через .tres (bat.tres и т.д.).
## Если не задано, враг стартует безоружным (дерётся кулаками).
@export var weapon_resource: WeaponResource = null

var fists_weapon: WeaponResource = preload("res://weapon/enemy_fists.tres")
var current_weapon: WeaponResource = null

var hp = MAX_HP
var player = null
var can_see_player = false
var noticed_player = false
var player_nearby = false
var noticed_nearby = false
var can_attack = true
var is_attacking = false
var is_dead = false
var is_staggered = false

# Оружие на полу в радиусе поиска (для безоружного врага)
var nearby_pickups: Array[WeaponPickup] = []

func _ready():
	add_to_group("enemy")
	player = get_tree().get_first_node_in_group("player")
	$AttackArea/CollisionShape2D.disabled = true
	$AttackArea/ColorRect.visible = false  # прячем прямоугольник по умолчанию
	$WeaponSearchZone.area_entered.connect(_on_weapon_search_zone_area_entered)
	$WeaponSearchZone.area_exited.connect(_on_weapon_search_zone_area_exited)
	equip(weapon_resource if weapon_resource != null else fists_weapon)

func equip(weapon: WeaponResource):
	current_weapon = weapon

## Вооружён ли враг (не голыми кулаками)
func is_armed() -> bool:
	return current_weapon != null and current_weapon != fists_weapon

## Вызывается щупальцем игрока, чтобы вырвать оружие. Возвращает вырванное оружие или null.
func disarm() -> WeaponResource:
	if not is_armed():
		return null
	var weapon = current_weapon
	current_weapon = fists_weapon
	_start_stagger()
	return weapon

func _start_stagger():
	is_staggered = true
	can_attack = false
	await get_tree().create_timer(0.5).timeout
	if is_dead:
		return
	is_staggered = false
	can_attack = true

func _on_weapon_search_zone_area_entered(area: Area2D):
	if area is WeaponPickup:
		nearby_pickups.append(area)

func _on_weapon_search_zone_area_exited(area: Area2D):
	if area is WeaponPickup:
		nearby_pickups.erase(area)

func _get_closest_pickup() -> WeaponPickup:
	var closest: WeaponPickup = null
	var closest_dist := INF
	for w in nearby_pickups:
		if not is_instance_valid(w):
			continue
		var d = global_position.distance_squared_to(w.global_position)
		if d < closest_dist:
			closest_dist = d
			closest = w
	return closest

func _pick_up_weapon(pickup: WeaponPickup):
	var picked_weapon = pickup.weapon_resource
	nearby_pickups.erase(pickup)
	pickup.queue_free()
	equip(picked_weapon)

func _physics_process(delta):
	if is_dead:
		return
	if is_staggered:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if can_see_player and player != null:
		# Безоружен и рядом есть оружие на полу — бежим за ним вместо боя
		if not is_armed():
			var pickup = _get_closest_pickup()
			if pickup:
				_chase_weapon(pickup)
				move_and_slide()
				return

		var distance = global_position.distance_to(player.global_position)
		var direction = (player.global_position - global_position).normalized()
		rotation = direction.angle() + PI / 2

		if distance <= ATTACK_RANGE:
			# Игрок близко — стоим, атакуем только если не на кулдауне
			velocity = Vector2.ZERO
			if can_attack:
				_start_attack()
		elif not is_attacking:
			# Идём к игроку
			velocity = direction * SPEED
	else:
		velocity = Vector2.ZERO

	move_and_slide()

## Бежим к оружию на полу; подбираем, когда оказываемся достаточно близко.
func _chase_weapon(pickup: WeaponPickup):
	var direction = (pickup.global_position - global_position).normalized()
	var distance = global_position.distance_to(pickup.global_position)
	rotation = direction.angle() + PI / 2

	if distance <= WEAPON_PICKUP_RANGE:
		velocity = Vector2.ZERO
		_pick_up_weapon(pickup)
	else:
		velocity = direction * SPEED

func _start_attack():
	is_attacking = true
	can_attack = false
	# Фиксируем оружие атаки на момент начала удара, чтобы вырывание/подбор
	# посреди анимации не поменяли параметры уже запущенной атаки.
	var attack_weapon = current_weapon if current_weapon != null else fists_weapon

	await get_tree().create_timer(0.4).timeout
	if is_dead:
		return

	# Показываем зону атаки
	$AttackArea/CollisionShape2D.disabled = false
	$AttackArea/ColorRect.visible = true
	await get_tree().physics_frame
	if is_dead:
		return
	_check_bodies_already_in_attack_area(attack_weapon)

	await get_tree().create_timer(0.2).timeout
	if is_dead:
		return

	# Прячем зону атаки
	$AttackArea/CollisionShape2D.disabled = true
	$AttackArea/ColorRect.visible = false
	is_attacking = false

	await get_tree().create_timer(attack_weapon.attack_cooldown).timeout
	if is_dead:
		return
	can_attack = true

func _check_bodies_already_in_attack_area(weapon: WeaponResource):
	# body_entered does NOT fire for a body already overlapping the area
	# at the moment the shape is enabled, so check manually right after.
	for body in $AttackArea.get_overlapping_bodies():
		_on_attack_area_body_entered(body, weapon)

func _on_attack_area_body_entered(body, weapon: WeaponResource = null):
	if is_dead:
		return
	if body.is_in_group("player"):
		if body.has_method("take_damage"):
			var used_weapon = weapon if weapon != null else (current_weapon if current_weapon != null else fists_weapon)
			body.take_damage(used_weapon.damage)

# --- Конус (дальнее зрение) ---
func _on_vision_area_body_entered(body):
	if body.is_in_group("player"):
		if not noticed_player and not can_see_player:
			noticed_player = true
			_start_reaction()

func _on_vision_area_body_exited(body):
	if body.is_in_group("player"):
		can_see_player = false
		noticed_player = false
		# Player left sight but may still be in the proximity circle;
		# re-arm proximity detection instead of leaving it stuck.
		if player_nearby and not noticed_nearby:
			noticed_nearby = true
			_start_proximity_reaction()

func _start_reaction():
	await get_tree().create_timer(REACTION_TIME).timeout
	if is_dead:
		return
	if noticed_player:
		can_see_player = true

# --- Круг (ближняя зона) ---
func _on_proximity_area_body_entered(body):
	if body.is_in_group("player"):
		player_nearby = true
		if not noticed_nearby and not can_see_player:
			noticed_nearby = true
			_start_proximity_reaction()

func _on_proximity_area_body_exited(body):
	if body.is_in_group("player"):
		player_nearby = false
		noticed_nearby = false

func _start_proximity_reaction():
	await get_tree().create_timer(PROXIMITY_REACTION_TIME).timeout
	if is_dead:
		return
	if player_nearby:
		can_see_player = true

# --- Урон и смерть ---
func take_damage(amount):
	if is_dead:
		return
	hp -= amount
	print("Враг получил урон: ", amount, " | HP: ", hp, "/", MAX_HP)
	if hp <= 0:
		die()

func die():
	if is_dead:
		return
	is_dead = true
	print("Враг умер!")
	set_physics_process(false)
	$AttackArea/CollisionShape2D.set_deferred("disabled", true)
	queue_free()
