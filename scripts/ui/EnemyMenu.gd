class_name EnemyMenu
extends Control
## Sandbox panel (E key) for picking a hostile ship to test-fly.
## Populated once enemy art/stats exist in EnemyCatalog.

signal enemy_selected(enemy_id: String)

@onready var _panel: PanelContainer = %Panel
@onready var _title: Label = %Title
@onready var _list: VBoxContainer = %EnemyList
@onready var _empty_label: Label = %EmptyLabel


func _ready() -> void:
	_style()
	refresh()


func _style() -> void:
	if _panel != null:
		var flat := StyleBoxFlat.new()
		flat.bg_color = HudPanelStyle.COLOR_BG_SURFACE
		flat.border_color = HudPanelStyle.COLOR_BORDER_DEFAULT
		flat.set_border_width_all(1)
		flat.set_corner_radius_all(6)
		flat.content_margin_left = 12.0
		flat.content_margin_right = 12.0
		flat.content_margin_top = 10.0
		flat.content_margin_bottom = 10.0
		_panel.add_theme_stylebox_override("panel", flat)
	if _title != null:
		_title.add_theme_font_override("font", HudPanelStyle.get_font())
		_title.add_theme_color_override("font_color", HudPanelStyle.COLOR_CYAN)
	if _empty_label != null:
		_empty_label.add_theme_font_override("font", HudPanelStyle.get_font())
		_empty_label.add_theme_color_override("font_color", HudPanelStyle.COLOR_TEXT_MUTED)


func refresh() -> void:
	for child in _list.get_children():
		child.queue_free()

	var enemies := EnemyCatalog.all_enemies()
	if _empty_label != null:
		_empty_label.visible = enemies.is_empty()

	for enemy: Dictionary in enemies:
		var enemy_id: String = str(enemy.get("id", ""))
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 36)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_enemy_button_pressed.bind(enemy_id))

		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 10)
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 8.0
		row.offset_right = -8.0
		btn.add_child(row)

		var glyph := _GlyphIcon.new()
		glyph.kind_id = enemy_id
		glyph.custom_minimum_size = Vector2(26, 26)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(glyph)

		var label := Label.new()
		label.text = str(enemy.get("title", "Enemy"))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", HudPanelStyle.get_font())
		label.add_theme_color_override("font_color", EnemyCatalog.marker_color(enemy_id))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(label)

		_list.add_child(btn)


func _on_enemy_button_pressed(enemy_id: String) -> void:
	enemy_selected.emit(enemy_id)


class _GlyphIcon:
	extends Control

	var kind_id: String = "basic"

	func _draw() -> void:
		EnemyCatalog.draw_glyph(self, size * 0.5, minf(size.x, size.y) * 0.42, kind_id, false)
