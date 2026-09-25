class_name InventoryView
extends Control

## The ship's hold as a grid of slots - each item a small live 3D model and a
## count - with the selected item's details beside it. A self-contained
## component: bind() it to an Inventory and give it a rect; it lays itself out
## in whatever size it gets (the details column drops away when narrow), so it
## can sit in the InventoryScreen overlay now or in a bigger interface later.
## Mouse picks a slot; step() moves the selection from the keyboard.

signal item_selected(id: StringName)

## Smallest a slot gets; they stretch to fill the grid's width.
const SLOT := 84.0
const SLOT_GAP := 8.0
## Room kept under the grid for the "hold is empty" note.
const EMPTY_NOTE := 60.0
const DETAIL_WIDTH := 300.0
const DETAIL_GAP := 24.0
## Narrower than this and only the grid is drawn.
const DETAIL_MIN_TOTAL := 520.0
const ICON_PIXELS := 192
const ICON_SPIN := 0.5
var _inventory: Inventory = null
var _selected: StringName = &""
var _hovered: int = -1
## id -> {viewport, model, camera} - one small scene per item held.
var _icons: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	resized.connect(queue_redraw)
	visibility_changed.connect(_update_icon_rendering)


func bind(inventory: Inventory) -> void:
	if _inventory != null and _inventory.changed.is_connected(_refresh):
		_inventory.changed.disconnect(_refresh)
	_inventory = inventory
	_inventory.changed.connect(_refresh)
	_refresh()


func selected() -> StringName:
	return _selected


## Moves the selection by `columns` slots across and `rows` down.
func step(columns: int, rows: int) -> void:
	var ids: Array = _ids()
	if ids.is_empty():
		return
	var index: int = maxi(ids.find(_selected), 0)
	index = clampi(index + columns + rows * _columns(), 0, ids.size() - 1)
	_select(ids[index])


## Name, colour and a line about it, for any item id.
static func item_info(id: StringName) -> Dictionary:
	return {
		"name": ResourceIcons.display_name(id),
		"color": ResourceIcons.color(id),
		"kind": "Resource",
	}


func _ids() -> Array:
	return _inventory.ids() if _inventory != null else []


func _select(id: StringName) -> void:
	if id == _selected:
		return
	_selected = id
	item_selected.emit(id)
	queue_redraw()


func _refresh() -> void:
	var ids: Array = _ids()
	for id: StringName in ids:
		if not _icons.has(id):
			_icons[id] = _make_icon(id)
	for id: StringName in _icons.keys():
		if not ids.has(id):
			_icons[id]["viewport"].queue_free()
			_icons.erase(id)
	if not ids.has(_selected):
		_selected = ids[0] if not ids.is_empty() else &""
	_update_icon_rendering()
	queue_redraw()


# ---- icons ----------------------------------------------------------------

## A tiny scene of its own for the item (ResourceIcons.make_stage), kept
## rendering so the model can spin. Drawn from the viewport's texture.
func _make_icon(id: StringName) -> Dictionary:
	var stage: Dictionary = ResourceIcons.make_stage(id, ICON_PIXELS)
	add_child(stage["viewport"])
	return stage


## The icons render only while the view is on screen.
func _update_icon_rendering() -> void:
	var mode := SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	for id: StringName in _icons:
		_icons[id]["viewport"].render_target_update_mode = mode


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	for id: StringName in _icons:
		var pivot: Node3D = _icons[id]["pivot"]
		pivot.rotate_y(ICON_SPIN * delta * (2.0 if id == _selected else 1.0))
	# No redraw needed: the slots draw the viewports' live textures.


# ---- layout ---------------------------------------------------------------

func _shows_details() -> bool:
	return size.x >= DETAIL_MIN_TOTAL


func _detail_width() -> float:
	return minf(DETAIL_WIDTH, size.x * 0.42)


func _grid_rect() -> Rect2:
	var width: float = size.x - (_detail_width() + DETAIL_GAP if _shows_details() else 0.0)
	return Rect2(Vector2.ZERO, Vector2(width, size.y))


func _detail_rect() -> Rect2:
	var width: float = _detail_width()
	return Rect2(Vector2(size.x - width, 0.0), Vector2(width, size.y))


func _columns() -> int:
	return maxi(1, int((_grid_rect().size.x + SLOT_GAP) / (SLOT + SLOT_GAP)))


## Slots widen so a row spans the grid exactly.
func _slot_size() -> float:
	var columns: int = _columns()
	return (_grid_rect().size.x - SLOT_GAP * (columns - 1)) / columns


func _slot_rect(index: int) -> Rect2:
	var columns: int = _columns()
	var side: float = _slot_size()
	return Rect2(Vector2(index % columns, index / columns) * (side + SLOT_GAP), Vector2(side, side))


## Enough to fill the rows that fit - empty ones faint - or more if the hold
## holds more (the view clips; there is no scrolling yet).
func _slot_count() -> int:
	var columns: int = _columns()
	var height: float = size.y - (EMPTY_NOTE if _ids().is_empty() else 0.0)
	var rows: int = maxi(1, int((height + SLOT_GAP) / (_slot_size() + SLOT_GAP)))
	var needed: int = int(ceil(float(_ids().size()) / columns))
	return maxi(rows, needed) * columns


func _slot_at(point: Vector2) -> int:
	for i in range(_slot_count()):
		if _slot_rect(i).has_point(point):
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hovered: int = _slot_at(event.position)
		if hovered != _hovered:
			_hovered = hovered
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var index: int = _slot_at(event.position)
		if index >= 0 and index < _ids().size():
			_select(_ids()[index])
		accept_event()


# ---- drawing --------------------------------------------------------------

func _draw() -> void:
	var font: Font = HudPanelStyle.get_font()
	var ids: Array = _ids()
	for i in range(_slot_count()):
		_draw_slot(font, i, ids[i] if i < ids.size() else &"")

	if ids.is_empty():
		var grid: Rect2 = _grid_rect()
		var y: float = _slot_rect(_slot_count() - 1).end.y + 34.0
		draw_string(
			font, Vector2(0.0, y), "THE HOLD IS EMPTY", HORIZONTAL_ALIGNMENT_LEFT, grid.size.x, 14,
			HudPanelStyle.COLOR_TEXT_SECONDARY
		)
		draw_string(
			font, Vector2(0.0, y + 20.0), "Land on a planet (ENTER), fly over a resource and press E",
			HORIZONTAL_ALIGNMENT_LEFT, grid.size.x, 11, HudPanelStyle.COLOR_TEXT_MUTED
		)
	if _shows_details():
		_draw_details(font)


func _draw_slot(font: Font, index: int, id: StringName) -> void:
	var slot: Rect2 = _slot_rect(index)
	var filled: bool = id != &""
	draw_rect(slot, Color(HudPanelStyle.COLOR_BG_SURFACE, 0.9 if filled else 0.45))
	var border: Color = HudPanelStyle.COLOR_BORDER_DEFAULT
	if filled and id == _selected:
		draw_rect(slot, HudPanelStyle.COLOR_CYAN_GLOW)
		border = HudPanelStyle.COLOR_CYAN
	elif filled and index == _hovered:
		border = HudPanelStyle.COLOR_BORDER_HOVER
	draw_rect(slot, border if filled else Color(border, 0.25), false, 1.0)
	if not filled:
		return

	draw_texture_rect(_icons[id]["viewport"].get_texture(), slot.grow(-6.0), false)
	var info: Dictionary = item_info(id)
	# A strip of the item's colour along the foot, and its count over it.
	draw_rect(Rect2(slot.position + Vector2(0.0, slot.size.y - 3.0), Vector2(slot.size.x, 3.0)), Color(info["color"], 0.8))
	draw_string(
		font, slot.position + Vector2(0.0, slot.size.y - 8.0), "×%d" % _inventory.count(id),
		HORIZONTAL_ALIGNMENT_RIGHT, slot.size.x - 6.0, 12, HudPanelStyle.COLOR_TEXT_PRIMARY
	)


func _draw_details(font: Font) -> void:
	var rect: Rect2 = _detail_rect()
	draw_line(rect.position - Vector2(DETAIL_GAP * 0.5, 0.0), Vector2(rect.position.x - DETAIL_GAP * 0.5, rect.end.y), Color(HudPanelStyle.COLOR_TEXT_FAINT, 0.8), 1.0)
	if _selected == &"":
		return

	var info: Dictionary = item_info(_selected)
	var icon := Rect2(rect.position, Vector2(rect.size.x, minf(rect.size.x * 0.7, rect.size.y * 0.5)))
	draw_rect(icon, Color(HudPanelStyle.COLOR_BG_SURFACE, 0.6))
	var side: float = minf(icon.size.x, icon.size.y)
	draw_texture_rect(
		_icons[_selected]["viewport"].get_texture(),
		Rect2(icon.get_center() - Vector2.ONE * side * 0.5, Vector2.ONE * side), false
	)

	var x: float = rect.position.x
	var y: float = icon.end.y + 30.0
	draw_string(font, Vector2(x, y), String(info["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, 20, HudPanelStyle.COLOR_CYAN)
	y += 22.0
	draw_string(font, Vector2(x, y), info["kind"], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, 12, HudPanelStyle.COLOR_AMBER)
	y += 30.0
	draw_string(font, Vector2(x, y), "IN THE HOLD", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HudPanelStyle.COLOR_TEXT_MUTED)
	draw_string(font, Vector2(x, y), "%d" % _inventory.count(_selected), HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x, 14, HudPanelStyle.COLOR_TEXT_PRIMARY)
	y += 26.0

	var sources: Dictionary = _inventory.sources(_selected)
	if not sources.is_empty():
		draw_string(font, Vector2(x, y), "COLLECTED ON", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HudPanelStyle.COLOR_EMERALD)
		y += 18.0
		for source: String in sources:
			draw_string(font, Vector2(x + 10.0, y), source, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 60.0, 12, HudPanelStyle.COLOR_TEXT_SECONDARY)
			draw_string(font, Vector2(x, y), "×%d" % sources[source], HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x, 12, HudPanelStyle.COLOR_TEXT_SECONDARY)
			y += 17.0
