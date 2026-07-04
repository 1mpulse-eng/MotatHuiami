extends TextureRect

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch_mode = TextureRect.STRETCH_KEEP_CENTERED

func _process(delta):
	global_position = get_viewport().get_mouse_position() - size / 2
