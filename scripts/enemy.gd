extends CharacterBody2D
const SPEED = 250.0
const MAX_HP = 1
const REACTION_TIME = 0.3
const PROXIMITY_REACTION_TIME = 0.8
const ATTACK_DAMAGE = 1
const ATTACK_COOLDOWN = 1.0
const ATTACK_RANGE = 45.0    # дистанция при которой враг останавливается и бьёт (соответствует реальному радиусу AttackArea)

var hp = MAX_HP
var player = null
var can_see_player = false
var noticed_player = false
var player_nearby = false
var noticed_nearby = false
var can_attack = true
var is_attacking = false
var is_dead = false

func _ready():
	player = get_tree().get_first_node_in_group("player")
	$AttackArea/CollisionShape2D.disabled = true
	$AttackArea/ColorRect.visible = false  # прячем прямоугольник по умолчанию

func _physics_process(delta):
	if is_dead:
		return

	if can_see_player and player != null:
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

func _start_attack():
	is_attacking = true
	can_attack = false

	await get_tree().create_timer(0.4).timeout
	if is_dead:
		return

	# Показываем зону атаки
	$AttackArea/CollisionShape2D.disabled = false
	$AttackArea/ColorRect.visible = true
	await get_tree().physics_frame
	if is_dead:
		return
	_check_bodies_already_in_attack_area()

	await get_tree().create_timer(0.2).timeout
	if is_dead:
		return

	# Прячем зону атаки
	$AttackArea/CollisionShape2D.disabled = true
	$AttackArea/ColorRect.visible = false
	is_attacking = false

	await get_tree().create_timer(ATTACK_COOLDOWN).timeout
	if is_dead:
		return
	can_attack = true

func _check_bodies_already_in_attack_area():
	# body_entered does NOT fire for a body already overlapping the area
	# at the moment the shape is enabled, so check manually right after.
	for body in $AttackArea.get_overlapping_bodies():
		_on_attack_area_body_entered(body)

func _on_attack_area_body_entered(body):
	if is_dead:
		return
	if body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.take_damage(ATTACK_DAMAGE)

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
