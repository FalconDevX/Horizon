class_name TechTreeView
extends Control
## One branch of the module tech tree (TechTree), shown by TechTreePanel: a
## column per tier, a card per node, lines from each node to the ones it
## unlocks. Cards list the node's modules (dimmed while locked); locked ones
## show what they need and an Unlock button (PlayerProgress spends the cost).

signal module_selected(module: ModuleData)
signal node_unlocked(node_id: StringName)

const CARD_WIDTH := 400.0
const COLUMN_GAP := 72.0
const ICON := 18.0
const SLOT_ICON_MAX := 72.0
const LINE_COLOR := Color(0.55, 0.62, 0.85, 0.55)
const LINE_LOCKED_COLOR := Color(0.45, 0.5, 0.6, 0.35)
const MISSING_COLOR := Color(1.0, 0.45, 0.4)

var _branch: TechTree.Branch = TechTree.Branch.STRUCTURE
var _modules_by_id: Dictionary = {}
var _columns: HBoxContainer
var _cards: Dictionary = {} ## node id → card PanelContainer


func setup(branch: TechTree.Branch, modules_by_id: Dictionary) -> void:
	_branch = branch
	_modules_by_id = modules_by_id
	_build()


func _get_minimum_size() -> Vector2:
	return _columns.get_combined_minimum_size() if _columns != null else Vector2.ZERO


func _build() -> void:
	for child in get_children():
		child.queue_free()
	_cards.clear()

	_columns = HBoxContainer.new()
	_columns.add_theme_constant_override("separation", int(COLUMN_GAP))
	add_child(_columns)
	_columns.sort_children.connect(_on_layout_changed)
	_columns.minimum_size_changed.connect(update_minimum_size)

	var nodes: Array[Dictionary] = TechTree.nodes_in(_branch)
	for tier in [1, 2, 3]:
		var in_tier: Array[Dictionary] = []
		for node: Dictionary in nodes:
			if int(node["tier"]) == tier:
				in_tier.append(node)
		if in_tier.is_empty():
			continue
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 14)
		column.custom_minimum_size.x = CARD_WIDTH
		_columns.add_child(column)
		column.add_child(_label(
			"TIER %d  %s" % [tier, TechTree.TIER_NAMES.get(tier, "")],
			12, TechTree.TIER_COLORS.get(tier, Color.WHITE)
		))
		for node: Dictionary in in_tier:
			_cards[node["id"]] = _make_card(node, column)
	update_minimum_size()


func _on_layout_changed() -> void:
	queue_redraw()


## Lines from every prerequisite to the node it opens (same branch only; a
## cross-branch requirement is named on the card instead).
func _draw() -> void:
	var origin: Vector2 = get_global_rect().position
	for node: Dictionary in TechTree.nodes_in(_branch):
		var card: Control = _cards.get(node["id"])
		if card == null:
			continue
		var to_rect: Rect2 = card.get_global_rect()
		for req: StringName in node["requires"]:
			var from_card: Control = _cards.get(req)
			if from_card == null:
				continue
			var from_rect: Rect2 = from_card.get_global_rect()
			var a := Vector2(from_rect.end.x, from_rect.get_center().y) - origin
			var b := Vector2(to_rect.position.x, to_rect.get_center().y) - origin
			var mid_x: float = (a.x + b.x) * 0.5
			var color: Color = LINE_COLOR if PlayerProgress.is_unlocked(node["id"]) else LINE_LOCKED_COLOR
			draw_polyline(PackedVector2Array([a, Vector2(mid_x, a.y), Vector2(mid_x, b.y), b]), color, 2.0, true)
			draw_circle(b, 3.5, color)


## Built inside `parent` so children run _ready before their flags are set.
func _make_card(node: Dictionary, parent: Control) -> PanelContainer:
	var unlocked: bool = PlayerProgress.is_unlocked(node["id"])
	var tier: int = node["tier"]

	var card := PanelContainer.new()
	card.custom_minimum_size.x = CARD_WIDTH
	var style := StyleBoxFlat.new()
	style.bg_color = HudPanelStyle.COLOR_BG_SURFACE if unlocked else HudPanelStyle.COLOR_BG_SURFACE.darkened(0.25)
	style.border_color = TechTree.TIER_COLORS.get(tier, Color.WHITE) if unlocked else HudPanelStyle.COLOR_BORDER_DEFAULT
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", style)
	parent.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	var title := _label(node["title"], 14, HudPanelStyle.COLOR_TEXT_PRIMARY if unlocked else HudPanelStyle.COLOR_TEXT_SECONDARY)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_label(
		("T%d" % tier) if unlocked else ("T%d  LOCKED" % tier), 11,
		TechTree.TIER_COLORS.get(tier, Color.WHITE) if unlocked else HudPanelStyle.COLOR_TEXT_MUTED
	))

	if node.has("note"):
		var note := _label(node["note"], 10, HudPanelStyle.COLOR_TEXT_MUTED)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(note)

	if unlocked and not TechTree.recipe(node).is_empty():
		box.add_child(_resource_row("Recipe", TechTree.recipe(node), TechTree.unlock_cost(node), false))

	if not unlocked:
		var missing: Array[String] = PlayerProgress.missing_requirements(node)
		var requires: Array[String] = []
		for req: StringName in node["requires"]:
			var req_node: Dictionary = TechTree.get_node(req)
			var text: String = String(req_node.get("title", req))
			if int(req_node.get("branch", _branch)) != _branch:
				text += " (%s)" % TechTree.BRANCH_NAMES.get(int(req_node["branch"]), "")
			requires.append(text)
		if not requires.is_empty():
			box.add_child(_label(
				"Requires: " + ", ".join(requires), 11,
				MISSING_COLOR if not missing.is_empty() else HudPanelStyle.COLOR_TEXT_SECONDARY
			))
		box.add_child(_resource_row("Cost", TechTree.recipe(node), TechTree.unlock_cost(node), true))
		var button := Button.new()
		button.text = "Unlock"
		button.add_theme_font_override("font", HudPanelStyle.get_font())
		button.add_theme_font_size_override("font_size", 12)
		button.disabled = not PlayerProgress.can_unlock(node)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_unlock_pressed.bind(node["id"]))
		box.add_child(button)

	var slots := HFlowContainer.new()
	slots.add_theme_constant_override("h_separation", 6)
	slots.add_theme_constant_override("v_separation", 6)
	box.add_child(slots)
	for module_id: StringName in node["modules"]:
		var module: ModuleData = _modules_by_id.get(module_id)
		if module == null:
			continue
		var slot := ModuleInventorySlot.new()
		slots.add_child(slot)
		slot.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		# Keep big footprints (5x5 hulls) card-sized.
		var bounds: Vector2i = module.get_bounding_size(0)
		slot.preview_cell_size = minf(24.0, SLOT_ICON_MAX / maxf(bounds.x, bounds.y))
		slot.setup(module)
		if unlocked:
			slot.module_selected.connect(func(m: ModuleData) -> void: module_selected.emit(m))
		else:
			# Shown so the player sees what the node gives, but not usable yet.
			slot.modulate = Color(1, 1, 1, 0.35)
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return card


## "Label" then an icon and amount per resource; with `stock`, "have/need"
## instead, red where the player is short (moonbloom counts frozen too).
func _resource_row(caption: String, ids: Array, amounts: Dictionary, stock: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var cap := _label(caption + ":", 11, HudPanelStyle.COLOR_TEXT_MUTED)
	cap.custom_minimum_size.x = 48.0
	row.add_child(cap)
	for id: StringName in ids:
		var icon := TextureRect.new()
		icon.texture = ResourceIcons.icon(id)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(ICON, ICON)
		icon.tooltip_text = _resource_name(id)
		row.add_child(icon)
		var need: int = amounts.get(id, 0)
		if stock:
			var have: int = PlayerProgress.stock(id)
			row.add_child(_label("%d/%d" % [have, need], 11, ResourceIcons.color(id) if have >= need else MISSING_COLOR))
		else:
			row.add_child(_label("%d" % need, 11, ResourceIcons.color(id)))
	return row


## "Moonbloom", or "Moonbloom (or Frozen moonbloom)" where equivalents pay too.
static func _resource_name(id: StringName) -> String:
	var others: Array[String] = []
	for other: StringName in TechTree.payable_with(id):
		if other != id:
			others.append(ResourceIcons.display_name(other))
	var name: String = ResourceIcons.display_name(id)
	return name if others.is_empty() else "%s (or %s)" % [name, ", ".join(others)]


func _on_unlock_pressed(node_id: StringName) -> void:
	if PlayerProgress.unlock(TechTree.get_node(node_id)):
		node_unlocked.emit(node_id)


static func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", HudPanelStyle.get_font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
