class_name Starfield
extends CanvasLayer

# A single high-quality image is dramatically cheaper than redrawing hundreds
# of stars, flares and nebula shapes every frame. It remains stable while the
# camera travels through the system.
# Kept under a new resource path so Godot cannot reuse the previous imported
# texture after the user selected a replacement background.
const BACKGROUND := preload("res://assets/space-background-galaxies.png")


func _ready() -> void:
	layer = -20
	add_to_group("starfield")
	var image := TextureRect.new()
	image.texture = BACKGROUND
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(image)


func set_space_visible(enabled: bool) -> void:
	visible = enabled