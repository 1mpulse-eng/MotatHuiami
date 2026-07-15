extends Resource
class_name WeaponResource
 
@export var weapon_name: String = "Бита"
@export var damage: int = 25
@export var texture: Texture2D # Спрайт оружия, лежащего на земле
@export var pickup_scale: float = 1.0 # масштаб спрайта на полу и в полёте
@export var attack_cooldown: float = 0.4
@export var hitbox_size: Vector2 = Vector2(40, 70)   # размер хитбокса
@export var hitbox_offset: Vector2 = Vector2(0, -35) # позиция хитбокса
@export var attack_anim: String = "attack" # название анимации, удар слева-направо
@export var attack_anim_alt: String = "" # удар справа-налево; если пусто — используется attack_anim
@export var idle_anim: String = "idle"
@export var idle_anim_alt: String = "" # idle, соответствующий стороне attack_anim_alt; если пусто — используется idle_anim
#@export var walk_anim: String = "walk_bat"
@export var damage_delay: float = 0.15 # задержка перед уроном
@export var hitbox_active_time: float = 0.15 # сколько хитбокс остаётся включён после damage_delay
