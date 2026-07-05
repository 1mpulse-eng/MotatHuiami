extends Area2D
class_name ThrownWeapon

## Кто бросил оружие — чтобы не задеть самого себя в момент броска
var thrower: Node = null
var weapon_resource: WeaponResource
var direction: Vector2 = Vector2.RIGHT
var speed: float = 900.0
var max_distance: float = 500.0
var spin_speed: float = 30.0 # рад/сек, чисто визуальное вращение в полёте

var _traveled: float = 0.0
var _stopped: bool = false

func _ready():
	if weapon_resource and has_node("Sprite2D"):
		$Sprite2D.texture = weapon_resource.texture
		$Sprite2D.scale = Vector2.ONE * weapon_resource.pickup_scale
	monitoring = false
	monitorable = false

func _physics_process(delta):
	if _stopped:
		return

	var motion = direction * speed * delta
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(global_position, global_position + motion)
	query.exclude = [self, thrower]
	var result = space_state.intersect_ray(query)

	if result:
		global_position = result.position
		_stopped = true
		if result.collider.has_method("take_damage"):
			result.collider.take_damage(weapon_resource.damage)
		_land.call_deferred()
		return

	global_position += motion
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
