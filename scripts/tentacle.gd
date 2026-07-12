extends Node2D
class_name Tentacle

## Радиус, в пределах которого курсор считается "наведённым" на врага для вырывания оружия.
const HOVER_RADIUS: float = 40.0

## Оружие в слоте щупальца. null = слот пуст (у щупальца нет "кулаков").
var current_weapon: WeaponResource = null

## Оружие на полу, находящееся в зоне досягаемости щупальца (за вычетом зоны игрока — см. player.gd).
var nearby_weapons: Array[WeaponPickup] = []

## Враги, находящиеся в зоне досягаемости щупальца (для вырывания оружия).
var nearby_enemies: Array[Node] = []

const THROWN_WEAPON_SCENE = preload("res://weapon/thrown_weapon.tscn")

@onready var visual: TentacleVisual = $TentacleVisual

## Отложенный возврат щупальца в состояние покоя. Вызывается "и забывается" (без await у
## вызывающей стороны), поэтому функции ниже (pick_up_weapon/throw_weapon/try_rip_weapon)
## остаются полностью синхронными и продолжают возвращать значения сразу, как раньше.
func _schedule_retract(delay: float, duration: float = 0.2):
	await get_tree().create_timer(delay).timeout
	visual.retract(duration)

func _ready():
	$Zone.area_entered.connect(_on_zone_area_entered)
	$Zone.area_exited.connect(_on_zone_area_exited)
	$Zone.body_entered.connect(_on_zone_body_entered)
	$Zone.body_exited.connect(_on_zone_body_exited)

func _on_zone_area_entered(area: Area2D):
	if area is WeaponPickup:
		nearby_weapons.append(area)

func _on_zone_area_exited(area: Area2D):
	if area is WeaponPickup:
		nearby_weapons.erase(area)

func _on_zone_body_entered(body: Node):
	if body.is_in_group("enemy"):
		nearby_enemies.append(body)

func _on_zone_body_exited(body: Node):
	if body.is_in_group("enemy"):
		nearby_enemies.erase(body)

## Возвращает оружие, на которое наведён курсор (в пределах HOVER_RADIUS), за вычетом того,
## что уже "принадлежит" зоне игрока (exclude — nearby_weapons игрока). Требует наведения,
## как и вырывание оружия у врага — иначе щупальце подбирало бы что попало по всей своей зоне.
func get_closest_weapon(exclude: Array, mouse_pos: Vector2) -> WeaponPickup:
	var closest: WeaponPickup = null
	var closest_dist := INF
	for w in nearby_weapons:
		if not is_instance_valid(w):
			continue
		if exclude.has(w):
			continue
		var d = mouse_pos.distance_squared_to(w.global_position)
		if d < closest_dist:
			closest_dist = d
			closest = w
	if closest and closest_dist <= HOVER_RADIUS * HOVER_RADIUS:
		return closest
	return null

func pick_up_weapon(pickup: WeaponPickup):
	current_weapon = pickup.weapon_resource
	nearby_weapons.erase(pickup)
	visual.flash_color(TentacleVisual.COLOR_PICKUP)
	visual.reach_to(pickup.global_position, 0.18, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	visual.set_held_weapon(current_weapon)
	pickup.queue_free()
	_schedule_retract(0.18)

## Бросок оружия щупальцем. thrower передаётся как игрок (владелец), чтобы не задеть самого себя.
func throw_weapon(thrower: Node2D):
	if current_weapon == null:
		return
	var mouse_pos = thrower.get_global_mouse_position()
	visual.flash_color(TentacleVisual.COLOR_THROW)
	visual.reach_to(mouse_pos, 0.15, Tween.TRANS_QUAD, Tween.EASE_OUT)
	var thrown = THROWN_WEAPON_SCENE.instantiate()
	thrown.thrower = thrower
	thrown.weapon_resource = current_weapon
	thrown.direction = (mouse_pos - global_position).normalized()
	thrower.get_parent().add_child(thrown)
	thrown.global_position = global_position
	current_weapon = null
	visual.set_held_weapon(null)
	_schedule_retract(0.1)

## Ищет врага из nearby_enemies, находящегося ближе всего к позиции курсора (в пределах HOVER_RADIUS).
func _get_enemy_under_mouse(mouse_pos: Vector2) -> Node:
	var closest: Node = null
	var closest_dist := INF
	for e in nearby_enemies:
		if not is_instance_valid(e):
			continue
		var d = mouse_pos.distance_squared_to(e.global_position)
		if d < closest_dist:
			closest_dist = d
			closest = e
	if closest and closest_dist <= HOVER_RADIUS * HOVER_RADIUS:
		return closest
	return null

## Проверка без побочных эффектов: наведён ли курсор на вооружённого врага, которого можно
## вырвать прямо сейчас (щупальце должно быть пустым). Используется для подсветки курсора.
func has_rippable_enemy(mouse_pos: Vector2) -> bool:
	if current_weapon != null:
		return false
	var enemy = _get_enemy_under_mouse(mouse_pos)
	if enemy == null or not enemy.has_method("is_armed"):
		return false
	return enemy.is_armed()

## Пытается вырвать оружие у врага, на которого наведён курсор. Возвращает true, если получилось.
func try_rip_weapon(mouse_pos: Vector2) -> bool:
	if current_weapon != null:
		return false
	var enemy = _get_enemy_under_mouse(mouse_pos)
	if enemy == null or not enemy.has_method("disarm"):
		return false
	visual.flash_color(TentacleVisual.COLOR_RIP)
	visual.reach_to(enemy.global_position, 0.1, Tween.TRANS_BACK, Tween.EASE_OUT)
	var weapon = enemy.disarm()
	if weapon == null:
		visual.retract()
		return false
	current_weapon = weapon
	visual.set_held_weapon(current_weapon)
	_schedule_retract(0.1, 0.35)
	return true

## Забирает оружие из слота щупальца (для передачи в руки игрока). Возвращает ресурс или null.
func take_weapon() -> WeaponResource:
	var w = current_weapon
	current_weapon = null
	visual.set_held_weapon(null)
	return w
