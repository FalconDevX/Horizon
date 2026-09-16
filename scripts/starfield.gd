class_name Starfield
extends CanvasLayer

func _ready() -> void:
	layer = -20
	add_to_group("starfield")
	var image := TextureRect.new()
	
	var img = Image.load_from_file("res://bg_space.jpg")
	if img != null:
		var tex = ImageTexture.create_from_image(img)
		image.texture = tex
	
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(image)

func set_space_visible(enabled: bool) -> void:
	visible = enabled