class_name ShipBuilderController
extends Control
## Wires inventory, shipyard grid UI, stats panel, and resize handles.

@onready var _ship_hull: ShipHull = %ShipHull
@onready var _grid_ui: ShipGridUI = %ShipGridUI
@onready var _stats_panel: StatsPanel = %StatsPanel
@onready var _inventory: GridContainer = %InventoryGrid
@onready var _hint: Label = %Hint
@onready var _module_bay: CollapsibleSection = %ModuleBaySection
@onready var _bay_handle: DragResizeHandle = %BayResizeHandle
@onready var _stats_handle: DragResizeHandle = %StatsResizeHandle
@onready var _right_column: Control = %RightColumn
@onready var _grid_scroll: PannableScrollContainer = %GridScroll
@onready var _center_view_btn: Button = %CenterViewButton


func _ready() -> void:
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


func _populate_inventory() -> void:
	for child in _inventory.get_children():
		child.queue_free()

	for module: ModuleData in ModuleCatalog.all_buildable_modules():
		var slot := ModuleInventorySlot.new()
		_inventory.add_child(slot)
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
