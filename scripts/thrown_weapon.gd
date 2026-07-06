extends Area2D
class_name ThrownWeapon

## Кто бросил оружие — чтобы не задеть самого себя в момент броска
var thrower: Node = null
var weapon_resource: WeaponResource
var direction: Vector2 = Vector2.RIGHT
var speed: float = 900.0
var max_distance: float = 500.0
var spin_speed: float = 30.0 # рад/сек, чисто визуальное вращение в полёте

## Радиус попадания по врагу/телам — ГЛАВНАЯ ручка, если снова покажется хардкорно/легко.
## Это НЕ размер спрайта, а именно зона, в которую засчитывается попадание.
var hit_radius: float = 22.0

var _traveled: float = 0.0
var _stopped: bool = false
var _hit_shape: CircleShape2D

func _ready():
	if weapon_resource and has_node("Sprite2D"):
		$Sprite2D.texture = weapon_resource.texture
		$Sprite2D.scale = Vector2.ONE * weapon_resource.pickup_scale
	monitoring = false
	monitorable = false
	_hit_shape = CircleShape2D.new()
	_hit_shape.radius = hit_radius

func _physics_process(delta):
	if _stopped:
		return

	var motion = direction * speed * delta
	var new_pos = global_position + motion
	var space_state = get_world_2d().direct_space_state

	# 1) "Толстая" проверка попадания по телам (враг/игрок) — кругом радиуса hit_radius,
	#    а не точечным рейкастом, поэтому попасть заметно проще.
	var shape_query = PhysicsShapeQueryParameters2D.new()
	shape_query.shape = _hit_shape
	shape_query.transform = Transform2D(0, new_pos)
	shape_query.exclude = [self, thrower]
	shape_query.collide_with_bodies = true
	shape_query.collide_with_areas = false
	var hits = space_state.intersect_shape(shape_query, 4)
	for hit in hits:
		var body = hit.collider
		if body == thrower:
			continue
		if body.has_method("take_damage"):
			global_position = new_pos
			_stopped = true
			body.take_damage(weapon_resource.damage)
			_land.call_deferred()
			return

	# 2) Тонкий рейкаст только для стен — тут точность важна, чтобы не пролетать сквозь них.
	var wall_query = PhysicsRayQueryParameters2D.create(global_position, new_pos)
	wall_query.exclude = [self, thrower]
	var wall_result = space_state.intersect_ray(wall_query)
	if wall_result and wall_result.collider is StaticBody2D:
		global_position = wall_result.position
		_stopped = true
		_land.call_deferred()
		return

	global_position = new_pos
	rotation += spin_speed * delta
	_traveled += motion.length()

	if _traveled >= max_distance:
		_stopped = true
		_land.call_deferred()

func _land():
	var pickup = preload("res://weapon/weapon_pickup.tscn").instantiate()
	pickup.weapon_resource = weapon_resource
	get_parent().add_child(pickup)
	pickup.global_position = global_position
	queue_free()
