class_name ModuleInventorySlot
extends PanelContainer
## Inventory tile that starts a drag / click-to-hold with ModuleData payload.
## Icon size matches the module footprint (2×2 modules show a 2×2 icon).

signal drag_started(module: ModuleData)
signal module_selected(module: ModuleData)

@export var preview_cell_size: float = 28.0

@export var module_data: ModuleData:
	set(value):
		module_data = value
		_refresh()

var _icon: TextureRect
var _label: Label
var _shape_host: Control
var _panel_style: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_ensure_children()
	_apply_style()
	_refresh()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _apply_style() -> void:
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = HudPanelStyle.COLOR_BG_SURFACE
	_panel_style.border_color = HudPanelStyle.COLOR_BORDER_DEFAULT
	_panel_style.set_border_width_all(1)
	_panel_style.set_corner_radius_all(5)
	_panel_style.set_content_margin_all(6)
	add_theme_stylebox_override("panel", _panel_style)


func _on_mouse_entered() -> void:
	if _panel_style != null:
		_panel_style.border_color = HudPanelStyle.COLOR_CYAN
		_panel_style.bg_color = HudPanelStyle.COLOR_BG_SURFACE.lightened(0.06)


func _on_mouse_exited() -> void:
	if _panel_style != null:
		_panel_style.border_color = HudPanelStyle.COLOR_BORDER_DEFAULT
		_panel_style.bg_color = HudPanelStyle.COLOR_BG_SURFACE


func setup(module: ModuleData) -> void:
	_ensure_children()
	module_data = module


func _ensure_children() -> void:
	if _icon != null and _label != null and _shape_host != null:
		return

	for child in get_children():
		child.queue_free()

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	_shape_host = Control.new()
	_shape_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shape_host.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_shape_host)

	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_SCALE
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shape_host.add_child(_icon)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_override("font", HudPanelStyle.get_font())
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_color", HudPanelStyle.COLOR_TEXT_SECONDARY)
	vbox.add_child(_label)


func _refresh() -> void:
	if not is_inside_tree():
		return
	_ensure_children()
	if module_data == null:
		_icon.texture = null
		_label.text = ""
		tooltip_text = ""
		_shape_host.custom_minimum_size = Vector2.ZERO
		return

	var bounds := module_data.get_bounding_size(0)
	var icon_size := Vector2(bounds) * preview_cell_size
	_shape_host.custom_minimum_size = icon_size
	_icon.position = Vector2.ZERO
	_icon.size = icon_size
	_icon.texture = module_data.texture

	_label.text = module_data.title
	tooltip_text = "%s\n[%s]\nShape: %dx%d (%d cells)\nMass: %.1f\nClick or drag to install. R rotates." % [
		module_data.title,
		module_data.category_name(),
		bounds.x,
		bounds.y,
		module_data.get_cell_count(),
		module_data.mass,
	]

	# Grow slot with footprint so 2x2 icons aren't crushed.
	custom_minimum_size = Vector2(
		maxi(120, int(icon_size.x) + 24),
		maxi(96, int(icon_size.y) + 40)
	)


func _gui_input(event: InputEvent) -> void:
	if module_data == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			module_selected.emit(module_data)
			# Don't accept — allow drag to still start on motion.


func _get_drag_data(_at_position: Vector2) -> Variant:
	if module_data == null:
		return null

	set_drag_preview(_build_preview(0))
	drag_started.emit(module_data)
	return {
		"type": "ship_module",
		"module": module_data,
		"rotation": 0,
	}


func _build_preview(rotation: int) -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var cell := preview_cell_size
	var shape := module_data.get_shape(rotation)
	var bounds := ModuleData.bounding_size_of(shape)
	var tex := module_data.texture
	if rotation != 0:
		tex = ModuleCatalog.make_shape_texture(
			module_data.grid_shape,
			module_data.category,
			rotation,
			int(cell)
		)

	if tex != null:
		var icon := TextureRect.new()
		icon.texture = tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.size = Vector2(bounds) * cell
		icon.modulate = Color(1, 1, 1, 0.85)
		root.add_child(icon)
	else:
		for offset: Vector2i in shape:
			var panel := Panel.new()
			panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			panel.position = Vector2(offset) * cell
			panel.size = Vector2(cell, cell)
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.2, 0.55, 0.85, 0.55)
			style.border_color = Color(0.55, 0.85, 1.0, 0.9)
			style.set_border_width_all(1)
			panel.add_theme_stylebox_override("panel", style)
			root.add_child(panel)

	root.position = -Vector2(cell, cell) * 0.5
	return root
