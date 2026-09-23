class_name ShipBuilderController
extends Control
## Wires inventory, shipyard grid UI, stats panel, and resize handles.

signal closed

@onready var _ship_hull: ShipHull = %ShipHull
@onready var _grid_ui: ShipGridUI = %ShipGridUI
@onready var _stats_panel: StatsPanel = %StatsPanel
@onready var _inventory: VBoxContainer = %InventoryGrid
@onready var _hint: Label = %Hint
@onready var _module_bay: CollapsibleSection = %ModuleBaySection
@onready var _bay_handle: DragResizeHandle = %BayResizeHandle
@onready var _stats_handle: DragResizeHandle = %StatsResizeHandle
@onready var _right_column: Control = %RightColumn
@onready var _grid_scroll: PannableScrollContainer = %GridScroll
@onready var _center_view_btn: Button = %CenterViewButton
@onready var _rotate_view_btn: Button = %RotateViewButton
@onready var _info_btn: Button = %InfoButton
@onready var _close_btn: Button = %CloseButton
@onready var _title: Label = %Title
@onready var _exit_confirm: Control = %ExitConfirm
@onready var _exit_scrim: Control = %Scrim
@onready var _exit_dialog_panel: PanelContainer = %DialogPanel
@onready var _save_exit_btn: Button = %SaveExitButton
@onready var _discard_exit_btn: Button = %DiscardExitButton
@onready var _info_popup: Control = %InfoPopup
@onready var _info_scrim: Control = %InfoScrim
@onready var _info_dialog_panel: PanelContainer = %InfoDialogPanel
@onready var _info_close_btn: Button = %InfoCloseButton

const CATEGORY_ORDER: Array[ModuleData.Category] = [
	ModuleData.Category.HULL,
	ModuleData.Category.CONNECTOR,
	ModuleData.Category.ENGINE,
	ModuleData.Category.FUEL_TANK,
	ModuleData.Category.BATTERY,
	ModuleData.Category.SHIELD,
	ModuleData.Category.WEAPON,
	ModuleData.Category.RADAR,
	ModuleData.Category.UTILITY,
]

const CATEGORY_LABELS: Dictionary = {
	ModuleData.Category.HULL: "Hulls",
	ModuleData.Category.CONNECTOR: "Connectors",
	ModuleData.Category.ENGINE: "Engines",
	ModuleData.Category.FUEL_TANK: "Fuel Tanks",
	ModuleData.Category.BATTERY: "Batteries",
	ModuleData.Category.SHIELD: "Shields",
	ModuleData.Category.WEAPON: "Weapons",
	ModuleData.Category.RADAR: "Radars",
	ModuleData.Category.UTILITY: "Utilities",
}

var _modules_by_category: Dictionary = {} ## ModuleData.Category → Array[ModuleData]
var _category_tabs: CategoryTabBar
var _module_grid: GridContainer

const GRID_H_SEPARATION := 8
const SLOT_TARGET_WIDTH := 140.0


func get_hull() -> ShipHull:
	return _ship_hull


func get_stats_dictionary() -> Dictionary:
	if _ship_hull == null:
		return {}
	return _ship_hull.get_stats_dictionary()


func get_fov_devices() -> Array[Dictionary]:
	if _ship_hull == null:
		return []
	return _ship_hull.get_fov_devices()


func _ready() -> void:
	_style_chrome()
	_populate_inventory()
	_grid_ui.bind_hull(_ship_hull)
	_stats_panel.bind_hull(_ship_hull)
	_grid_ui.hold_changed.connect(_on_hold_changed)
	_ship_hull.stats_changed.connect(_on_stats_changed)
	_update_hint(null, 0)

	if _bay_handle != null:
		_bay_handle.set_target(_module_bay)
		_bay_handle.size_dragged.connect(_on_bay_resized)
	if _stats_handle != null:
		_stats_handle.set_target(_right_column)

	if _module_bay != null:
		_module_bay.toggled.connect(_on_bay_toggled)

	if _center_view_btn != null:
		_center_view_btn.pressed.connect(_on_center_view_pressed)
	if _rotate_view_btn != null:
		_rotate_view_btn.pressed.connect(_on_rotate_view_pressed)

	if _close_btn != null:
		_close_btn.pressed.connect(_show_exit_confirm)
	if _exit_scrim != null:
		_exit_scrim.gui_input.connect(_on_scrim_gui_input)
	if _save_exit_btn != null:
		_save_exit_btn.pressed.connect(_on_save_exit_pressed)
	if _discard_exit_btn != null:
		_discard_exit_btn.pressed.connect(_on_discard_exit_pressed)

	if _info_btn != null:
		_info_btn.pressed.connect(_show_info_popup)
	if _info_scrim != null:
		_info_scrim.gui_input.connect(_on_info_scrim_gui_input)
	if _info_close_btn != null:
		_info_close_btn.pressed.connect(_hide_info_popup)

	# Center once after first layout.
	call_deferred("_on_center_view_pressed")


func _on_center_view_pressed() -> void:
	if _grid_scroll != null:
		_grid_scroll.center_view()


func _on_rotate_view_pressed() -> void:
	if _grid_ui != null:
		_grid_ui.rotate_view(1)


func _show_exit_confirm() -> void:
	if _exit_confirm != null:
		_exit_confirm.visible = true


func _hide_exit_confirm() -> void:
	if _exit_confirm != null:
		_exit_confirm.visible = false


func _on_scrim_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_hide_exit_confirm()


func _on_save_exit_pressed() -> void:
	# Placeholder: no persistence layer yet, so this currently behaves like a
	# normal exit. Wire real blueprint saving here once it exists.
	_hide_exit_confirm()
	closed.emit()


func _on_discard_exit_pressed() -> void:
	_hide_exit_confirm()
	closed.emit()


func _show_info_popup() -> void:
	if _info_popup != null:
		_info_popup.visible = true


func _hide_info_popup() -> void:
	if _info_popup != null:
		_info_popup.visible = false


func _on_info_scrim_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_hide_info_popup()


static func _load_icon(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			return res
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null:
			return ImageTexture.create_from_image(img)
	return null


func _on_bay_resized(new_height: float) -> void:
	if _module_bay != null:
		_module_bay.remember_height(new_height)


func _on_bay_toggled(expanded: bool) -> void:
	if _bay_handle != null:
		_bay_handle.visible = expanded


func _style_chrome() -> void:
	if _title != null:
		_title.add_theme_font_override("font", HudPanelStyle.get_font())
	if _hint != null:
		_hint.add_theme_font_override("font", HudPanelStyle.get_font())
		_hint.add_theme_font_size_override("font_size", 11)
		_hint.add_theme_color_override("font_color", HudPanelStyle.COLOR_TEXT_MUTED)
	_style_topbar_button(_center_view_btn)
	_style_topbar_button(_rotate_view_btn)
	_style_topbar_button(_info_btn)
	_style_topbar_button(_close_btn)
	_style_exit_confirm()
	_style_info_popup()

	if _info_btn != null:
		var info_icon: Texture2D = _load_icon("res://textures/icons/info.svg")
		if info_icon != null:
			_info_btn.icon = info_icon
			_info_btn.text = ""
			_info_btn.add_theme_color_override("icon_normal_color", HudPanelStyle.COLOR_TEXT_SECONDARY)
			_info_btn.add_theme_color_override("icon_hover_color", HudPanelStyle.COLOR_CYAN)
			_info_btn.add_theme_color_override("icon_pressed_color", HudPanelStyle.COLOR_CYAN)


func _style_topbar_button(btn: Button) -> void:
	if btn == null:
		return
	var flat := StyleBoxFlat.new()
	flat.bg_color = HudPanelStyle.COLOR_BG_SURFACE
	flat.border_color = HudPanelStyle.COLOR_BORDER_DEFAULT
	flat.set_border_width_all(1)
	flat.set_corner_radius_all(4)
	flat.content_margin_left = 10.0
	flat.content_margin_right = 10.0
	flat.content_margin_top = 5.0
	flat.content_margin_bottom = 5.0
	var flat_hover := flat.duplicate() as StyleBoxFlat
	flat_hover.border_color = HudPanelStyle.COLOR_CYAN
	btn.add_theme_stylebox_override("normal", flat)
	btn.add_theme_stylebox_override("hover", flat_hover)
	btn.add_theme_stylebox_override("pressed", flat_hover)
	btn.add_theme_stylebox_override("focus", flat)
	btn.add_theme_font_override("font", HudPanelStyle.get_font())
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", HudPanelStyle.COLOR_TEXT_SECONDARY)
	btn.add_theme_color_override("font_hover_color", HudPanelStyle.COLOR_CYAN)


func _style_exit_confirm() -> void:
	if _exit_dialog_panel != null:
		var flat := StyleBoxFlat.new()
		flat.bg_color = HudPanelStyle.COLOR_BG_SURFACE
		flat.border_color = HudPanelStyle.COLOR_BORDER_DEFAULT
		flat.set_border_width_all(1)
		flat.set_corner_radius_all(6)
		_exit_dialog_panel.add_theme_stylebox_override("panel", flat)

	_style_topbar_button(_discard_exit_btn)
	_style_topbar_button(_save_exit_btn)
	if _save_exit_btn != null:
		_save_exit_btn.add_theme_color_override("font_color", HudPanelStyle.COLOR_CYAN)


func _style_info_popup() -> void:
	if _info_dialog_panel != null:
		var flat := StyleBoxFlat.new()
		flat.bg_color = HudPanelStyle.COLOR_BG_SURFACE
		flat.border_color = HudPanelStyle.COLOR_BORDER_DEFAULT
		flat.set_border_width_all(1)
		flat.set_corner_radius_all(6)
		_info_dialog_panel.add_theme_stylebox_override("panel", flat)

	if _info_dialog_panel != null:
		for label: Label in _info_dialog_panel.find_children("*", "Label", true, false):
			label.add_theme_font_override("font", HudPanelStyle.get_font())

	_style_topbar_button(_info_close_btn)


func _populate_inventory() -> void:
	for child in _inventory.get_children():
		child.queue_free()

	_modules_by_category.clear()
	for module: ModuleData in ModuleCatalog.all_buildable_modules():
		if not _modules_by_category.has(module.category):
			_modules_by_category[module.category] = []
		(_modules_by_category[module.category] as Array).append(module)

	var available: Array[ModuleData.Category] = []
	for category: ModuleData.Category in CATEGORY_ORDER:
		if _modules_by_category.has(category):
			available.append(category)

	_inventory.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not _inventory.resized.is_connected(_on_inventory_resized):
		_inventory.resized.connect(_on_inventory_resized)

	_category_tabs = CategoryTabBar.new()
	_category_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory.add_child(_category_tabs)
	_category_tabs.setup(available, CATEGORY_LABELS, available[0] if not available.is_empty() else ModuleData.Category.HULL)
	_category_tabs.category_selected.connect(_on_category_selected)

	_module_grid = GridContainer.new()
	_module_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_module_grid.add_theme_constant_override("h_separation", GRID_H_SEPARATION)
	_module_grid.add_theme_constant_override("v_separation", 8)
	_inventory.add_child(_module_grid)

	if not available.is_empty():
		_show_category(available[0])
	call_deferred("_update_grid_columns")


func _on_inventory_resized() -> void:
	_update_grid_columns()


func _update_grid_columns() -> void:
	if _module_grid == null:
		return
	var width: float = _inventory.size.x
	if width < 1.0:
		var scroll := _inventory.get_parent() as Control
		if scroll != null:
			width = scroll.size.x
	if width < 1.0:
		return
	var cols: int = maxi(1, int(floor((width + GRID_H_SEPARATION) / (SLOT_TARGET_WIDTH + GRID_H_SEPARATION))))
	if _module_grid.columns != cols:
		_module_grid.columns = cols


func _on_category_selected(category: ModuleData.Category) -> void:
	_show_category(category)


func _show_category(category: ModuleData.Category) -> void:
	if _module_grid == null:
		return
	for child in _module_grid.get_children():
		child.queue_free()

	_update_grid_columns()

	var modules: Array = _modules_by_category.get(category, [])
	for module: ModuleData in modules:
		var slot := ModuleInventorySlot.new()
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_module_grid.add_child(slot)
		slot.setup(module)
		slot.module_selected.connect(_on_inventory_module_selected)
		slot.drag_started.connect(_on_inventory_drag_started)


func _on_inventory_module_selected(module: ModuleData) -> void:
	_grid_ui.hold_module(module, 0)


func _on_inventory_drag_started(module: ModuleData) -> void:
	_grid_ui.hold_module(module, 0)


func _on_hold_changed(module: ModuleData, rotation: int) -> void:
	_update_hint(module, rotation)


func _on_stats_changed(_stats: Dictionary) -> void:
	if _held_is_null_hint():
		_update_hint(null, 0)


func _held_is_null_hint() -> bool:
	return not _grid_ui.has_held_module()


func _update_hint(module: ModuleData, rotation: int) -> void:
	if _hint == null:
		return
	var link := ""
	if not _ship_hull.are_hulls_connected():
		link += " ⚠ Hulls not connected - use a Connector."
	if not _ship_hull.are_ship_rcs_sides_covered():
		link += " ⚠ Ship needs 1 RCS on each side except the main-engine side."
	if module == null:
		_hint.text = link.strip_edges()
	else:
		var bounds := module.get_bounding_size(rotation)
		var floor_hint := "free shipyard cell"
		match module.category:
			ModuleData.Category.HULL:
				floor_hint = "shipyard (no contact with another hull)"
			ModuleData.Category.CONNECTOR:
				floor_hint = "empty cell between hulls"
			ModuleData.Category.WEAPON:
				floor_hint = "truss next to normal deck (not orange mount)"
			ModuleData.Category.RADAR:
				floor_hint = "deck"
			ModuleData.Category.ENGINE:
				if module.is_corrective_engine:
					floor_hint = "truss next to normal deck (not orange mount)"
				else:
					floor_hint = "orange mount only (≥1 cell) + optional truss overhang"
			_:
				if module.is_deck_equipment():
					floor_hint = "deck"
		var fov_hint := ""
		if module.has_fov():
			fov_hint = " | FOV %.0f° / %.0f SU" % [module.fov_angle_deg, module.fov_range]
		_hint.text = "Holding: %s -> %s | rotation %d deg | %dx%d%s%s" % [
			module.title,
			floor_hint,
			rotation * 90,
			bounds.x,
			bounds.y,
			fov_hint,
			link,
		]
