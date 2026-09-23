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
		var btn := Button.new()
		btn.text = str(enemy.get("title", "Enemy"))
		btn.add_theme_font_override("font", HudPanelStyle.get_font())
		btn.pressed.connect(_on_enemy_button_pressed.bind(str(enemy.get("id", ""))))
		_list.add_child(btn)


func _on_enemy_button_pressed(enemy_id: String) -> void:
	enemy_selected.emit(enemy_id)
