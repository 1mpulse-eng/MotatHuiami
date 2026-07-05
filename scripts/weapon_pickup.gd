extends Area2D
class_name WeaponPickup

## Ресурс оружия (bat.tres, fists.tres и т.д.), которое лежит на полу
@export var weapon_resource: WeaponResource:
	set(value):
		weapon_resource = value
		_update_visual()

func _ready():
	add_to_group("weapon_pickup")
	_update_visual()

func _update_visual():
	if weapon_resource and has_node("Sprite2D"):
		$Sprite2D.texture = weapon_resource.texture
		$Sprite2D.scale = Vector2.ONE * weapon_resource.pickup_scale
