class_name TechTreePanel
extends VBoxContainer
## The whole module tech tree: a tab per branch, the player's resource stock
## and the branch's TechTreeView, scrolling both ways. Lives in
## TechTreeWindow (T).

## CategoryTabBar is keyed by category, so each branch borrows a
## representative one for its key and glyph.
const BRANCH_TAB_CATEGORY: Dictionary = {
	TechTree.Branch.STRUCTURE: ModuleData.Category.HULL,
	TechTree.Branch.WEAPONS: ModuleData.Category.WEAPON,
	TechTree.Branch.PROPULSION: ModuleData.Category.ENGINE,
	TechTree.Branch.POWER: ModuleData.Category.BATTERY,
	TechTree.Branch.SUPPORT: ModuleData.Category.UTILITY,
}

var _modules_by_id: Dictionary = {} ## module id → ModuleData
var _tabs: CategoryTabBar
var _resource_bar: HFlowContainer
var _tree_view: TechTreeView
var _branch: TechTree.Branch = TechTree.Branch.STRUCTURE


func _ready() -> void:
	PlayerProgress.ensure_initialized()
	add_theme_constant_override("separation", 10)
	for module: ModuleData in ModuleCatalog.all_buildable_modules():
		_modules_by_id[module.id] = module

	var categories: Array[ModuleData.Category] = []
	var labels: Dictionary = {}
	for branch: TechTree.Branch in TechTree.BRANCH_ORDER:
		var category: ModuleData.Category = BRANCH_TAB_CATEGORY[branch]
		categories.append(category)
		labels[category] = TechTree.BRANCH_NAMES[branch]
	_tabs = CategoryTabBar.new()
	add_child(_tabs)
	_tabs.setup(categories, labels, categories[0])
	_tabs.category_selected.connect(_on_tab_selected)

	_resource_bar = HFlowContainer.new()
	_resource_bar.add_theme_constant_override("h_separation", 12)
	_resource_bar.add_theme_constant_override("v_separation", 4)
	add_child(_resource_bar)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)
	_tree_view = TechTreeView.new()
	scroll.add_child(_tree_view)
	_tree_view.node_unlocked.connect(_on_node_unlocked)
	refresh()


## Redraws stock and tree, e.g. when the panel opens.
func refresh() -> void:
	_refresh_resource_bar()
	_tree_view.setup(_branch, _modules_by_id)


func _on_tab_selected(category: ModuleData.Category) -> void:
	for branch: TechTree.Branch in BRANCH_TAB_CATEGORY:
		if BRANCH_TAB_CATEGORY[branch] == category:
			_branch = branch
			_tree_view.setup(branch, _modules_by_id)
			return


func _on_node_unlocked(_node_id: StringName) -> void:
	refresh()


## What the hold has of every resource the tree asks for: icon + amount,
## tinted with the resource's own colour.
func _refresh_resource_bar() -> void:
	for child in _resource_bar.get_children():
		child.queue_free()
	for id: StringName in _recipe_resources():
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 4)
		item.tooltip_text = TechTreeView._resource_name(id)
		var icon := TextureRect.new()
		icon.texture = ResourceIcons.icon(id)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(22, 22)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(icon)
		var label := Label.new()
		label.text = str(PlayerProgress.stock(id))
		label.add_theme_font_override("font", HudPanelStyle.get_font())
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", ResourceIcons.color(id))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(label)
		_resource_bar.add_child(item)


## Every resource some cost names, in the order the tree first uses them.
static func _recipe_resources() -> Array[StringName]:
	var ids: Array[StringName] = []
	for node: Dictionary in TechTree.NODES:
		for id: StringName in TechTree.recipe(node):
			if not ids.has(id):
				ids.append(id)
	return ids
