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

# Текущее оружие как ресурс
var current_weapon: WeaponResource = null

func _ready():
	add_to_group("player")
	$AttackHitbox/CollisionShape2D.disabled = true
	$AttackHitbox.body_entered.connect(_on_hitbox_body_entered)
	$AnimatedSprite2D.animation_finished.connect(_on_animation_finished)
	# Стартовое оружие
	equip(preload("res://weapon//bat.tres"))

func equip(weapon: WeaponResource):
	current_weapon = weapon
	# Обновляем размер и позицию хитбокса под оружие
	$AttackHitbox/CollisionShape2D.shape.size = weapon.hitbox_size
	$AttackHitbox.position = weapon.hitbox_offset

func _physics_process(delta):
	var direction = Vector2.ZERO
	direction.x = Input.get_axis("ui_left", "ui_right")
	direction.y = Input.get_axis("ui_up", "ui_down")
	direction = direction.normalized()

	if is_rolling:
		var roll_speed = ROLL_DISTANCE / ROLL_DURATION
		velocity = roll_direction * roll_speed
	else:
		velocity = direction * SPEED
		rotation = (get_global_mouse_position() - global_position).angle() + PI / 2

		if Input.is_action_just_pressed("roll") and can_roll and not is_attacking:
			_start_roll(direction)
		if Input.is_action_just_pressed("attack") and can_attack and not is_rolling:
			_play_attack_animation()

	move_and_slide()

func _play_attack_animation():
	if current_weapon == null:
		return

	is_attacking = true
	can_attack = false
	_attack_id += 1
	var this_attack = _attack_id

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
