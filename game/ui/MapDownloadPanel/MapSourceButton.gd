@tool
extends Button

@export var texture : Texture2D
@export var image_bg_color = Color(0,0,0)
@export var image_margin = 25: set = _set_image_margin
@export var description = 'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.': set = _set_rich_text

@onready var color_rect := $MarginContainer/VBox/ColorRect
@onready var image_margin_container = $MarginContainer/VBox/ColorRect/ImageMargin
@onready var texture_rect := $MarginContainer/VBox/ColorRect/ImageMargin/TextureRect
@onready var rich_text := $MarginContainer/VBox/RichTextLabel

var is_ready = false

func _ready():
	color_rect.color = image_bg_color
	texture_rect.texture = texture
	_set_mouse_passthrough(self)
	is_ready = true
	
func _set_mouse_passthrough(c: Control):
	if c != self:
		c.mouse_filter = Control.MOUSE_FILTER_PASS
	
	for cc in c.get_children():
		_set_mouse_passthrough(cc)

func _set_rich_text(val):
	description = val
	
	if ! is_ready:
		await self.ready
	rich_text.text = val
	
func _set_image_margin(val):
	image_margin = val
	
	if ! is_ready:
		await self.ready
	image_margin_container.set('theme_override_constants/margin_bottom', image_margin)
	image_margin_container.set('theme_override_constants/margin_top', image_margin)
	image_margin_container.set('theme_override_constants/margin_left', image_margin)
	image_margin_container.set('theme_override_constants/margin_right', image_margin)
