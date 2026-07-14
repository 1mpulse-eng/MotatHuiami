extends CharacterBody2D
const SPEED = 250.0
const MAX_HP = 1
const REACTION_TIME = 0.3
const PROXIMITY_REACTION_TIME = 0.8
const ATTACK_RANGE = 45.0
const WEAPON_PICKUP_RANGE = 30.0

@export var weapon_resource: WeaponResource = null
## Сцена пикапа оружия — назначь в инспекторе (нужна для дропа оружия после смерти)
@export var weapon_pickup_scene: PackedScene = null

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

var nearby_pickups: Array[WeaponPickup] = []

func _ready():
	add_to_group("enemy")
	player = get_tree().get_first_node_in_group("player")
	$AttackArea/CollisionShape2D.disabled = true
	$AttackArea/ColorRect.visible = false
	$WeaponSearchZone.area_entered.connect(_on_weapon_search_zone_area_entered)
	$WeaponSearchZone.area_exited.connect(_on_weapon_search_zone_area_exited)
	equip(weapon_resource if weapon_resource != null else fists_weapon)

func equip(weapon: WeaponResource):
	current_weapon = weapon

func is_armed() -> bool:
	return current_weapon != null and current_weapon != fists_weapon

func disarm() -> WeaponResource:
	if not is_armed():
		return null
	var weapon = current_weapon
	current_weapon = fists_weapon
	_start_stagger()
	can_see_player = true
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
		var distance_to_player = global_position.distance_to(player.global_position)
		var direction_to_player = (player.global_position - global_position).normalized()

		# Игрок в радиусе атаки — деремся (кулаками, если безоружны),
		# не отвлекаясь на оружие на полу. Это чинит "зависание" у пикапа.
		if distance_to_player <= ATTACK_RANGE:
			rotation = direction_to_player.angle() + PI / 2
			velocity = Vector2.ZERO
			if can_attack:
				_start_attack()
			move_and_slide()
			return

		# Безоружны и рядом лежит оружие, которое не дальше игрока — бежим за ним
		if not is_armed():
			var pickup = _get_closest_pickup()
			if pickup:
				var distance_to_pickup = global_position.distance_to(pickup.global_position)
				if distance_to_pickup <= distance_to_player:
					_chase_weapon(pickup)
					move_and_slide()
					return

		rotation = direction_to_player.angle() + PI / 2
		if not is_attacking:
			velocity = direction_to_player * SPEED
	else:
		velocity = Vector2.ZERO

	move_and_slide()

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
	var attack_weapon = current_weapon if current_weapon != null else fists_weapon

	await get_tree().create_timer(0.4).timeout
	if is_dead:
		return

	$AttackArea/CollisionShape2D.disabled = false
	$AttackArea/ColorRect.visible = true
	await get_tree().physics_frame
	if is_dead:
		return
	_check_bodies_already_in_attack_area(attack_weapon)

	await get_tree().create_timer(0.2).timeout
	if is_dead:
		return

	$AttackArea/CollisionShape2D.disabled = true
	$AttackArea/ColorRect.visible = false
	is_attacking = false

	await get_tree().create_timer(attack_weapon.attack_cooldown).timeout
	if is_dead:
		return
	can_attack = true

func _check_bodies_already_in_attack_area(weapon: WeaponResource):
	for body in $AttackArea.get_overlapping_bodies():
		_on_attack_area_body_entered(body, weapon)

func _on_attack_area_body_entered(body, weapon: WeaponResource = null):
	if is_dead:
		return
	if body.is_in_group("player"):
		if body.has_method("take_damage"):
			var used_weapon = weapon if weapon != null else (current_weapon if current_weapon != null else fists_weapon)
			body.take_damage(used_weapon.damage)

func _on_vision_area_body_entered(body):
	if body.is_in_group("player"):
		if not noticed_player and not can_see_player:
			noticed_player = true
			_start_reaction()

func _on_vision_area_body_exited(body):
	if body.is_in_group("player"):
		can_see_player = false
		noticed_player = false
		if player_nearby and not noticed_nearby:
			noticed_nearby = true
			_start_proximity_reaction()

func _start_reaction():
	await get_tree().create_timer(REACTION_TIME).timeout
	if is_dead:
		return
	if noticed_player:
		can_see_player = true

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
	_drop_weapon()
	FlowManager.register_kill()
	queue_free()

func _drop_weapon():
	if not is_armed():
		return
	if weapon_pickup_scene == null:
		push_warning("weapon_pickup_scene не назначен в инспекторе — оружие не будет заспавнено")
		return
	var pickup = weapon_pickup_scene.instantiate()
	pickup.weapon_resource = current_weapon
	pickup.global_position = global_position
	# ВАЖНО: add_child откладывается через call_deferred, потому что die()
	# вызывается из физического колбэка (player.gd _on_hitbox_body_entered),
	# а в этот момент физический сервер ещё "flushing queries" — то есть
	# синхронно менять monitoring/disabled у Area2D/CollisionShape2D нельзя.
	# Если пикап сам включает что-то подобное в своём _ready(), синхронный
	# add_child в этот момент и приводит к ошибке
	# "Can't change this state while flushing queries".
	get_parent().call_deferred("add_child", pickup)
