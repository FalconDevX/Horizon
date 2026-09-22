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
@onready var _close_btn: Button = %CloseButton
@onready var _title: Label = %Title

const CATEGORY_ORDER: Array[ModuleData.Category] = [
	ModuleData.Category.HULL,
	ModuleData.Category.CONNECTOR,
	ModuleData.Category.ENGINE,
	ModuleData.Category.WEAPON,
	ModuleData.Category.UTILITY,
]

const CATEGORY_LABELS: Dictionary = {
	ModuleData.Category.HULL: "Kadłuby",
	ModuleData.Category.CONNECTOR: "Łączniki",
	ModuleData.Category.ENGINE: "Silniki",
	ModuleData.Category.WEAPON: "Uzbrojenie",
	ModuleData.Category.UTILITY: "Moduły użytkowe",
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

	if _close_btn != null:
		_close_btn.pressed.connect(func() -> void: closed.emit())

	# Center once after first layout.
	call_deferred("_on_center_view_pressed")


func _on_center_view_pressed() -> void:
	if _grid_scroll != null:
		_grid_scroll.center_view()


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
	_style_topbar_button(_close_btn)


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
		link = " ⚠ Kadłuby niepołączone — użyj Łącznika."
	if module == null:
		_hint.text = "Ctrl+kółko = zoom. ŚPM = przesuwanie. Kółko = góra/dół, Shift+kółko = lewo/prawo. Przy module: kółko = obrót.%s" % link
	else:
		var bounds := module.get_bounding_size(rotation)
		var floor_hint := "wolne pole stoczni"
		match module.category:
			ModuleData.Category.HULL:
				floor_hint = "stocznia (bez styku z innym kadłubem)"
			ModuleData.Category.CONNECTOR:
				floor_hint = "pusta kratka między kadłubami"
			ModuleData.Category.WEAPON:
				floor_hint = "obok pokładu (nie na podłodze)"
			ModuleData.Category.ENGINE, ModuleData.Category.UTILITY:
				floor_hint = "pokład"
			_:
				pass
		_hint.text = "W ręku: %s → %s | obrót %d° | %dx%d%s" % [
			module.title,
			floor_hint,
			rotation * 90,
			bounds.x,
			bounds.y,
			link,
		]
