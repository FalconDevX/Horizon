class_name CategoryTabBar
extends HBoxContainer
## Horizontal category picker: square glyphs that expand to the full label when selected.

signal category_selected(category: ModuleData.Category)

const TAB_SIZE := 36.0
const EXPAND_DURATION := 0.18
const ICON_PX := 28

var _tabs: Dictionary = {} ## ModuleData.Category → _CategoryTab
var _selected: ModuleData.Category = ModuleData.Category.HULL
var _order: Array[ModuleData.Category] = []


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	alignment = BoxContainer.ALIGNMENT_BEGIN
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func setup(
	categories: Array[ModuleData.Category],
	labels: Dictionary,
	initial: ModuleData.Category = ModuleData.Category.HULL
) -> void:
	for child in get_children():
		child.queue_free()
	_tabs.clear()
	_order = categories.duplicate()

	for category: ModuleData.Category in categories:
		var tab := _CategoryTab.new()
		tab.setup(
			category,
			str(labels.get(category, "?")),
			ModuleCatalog.make_shape_texture(
				[Vector2i.ZERO],
				category,
				0,
				ICON_PX
			)
		)
		tab.pressed.connect(_on_tab_pressed.bind(category))
		add_child(tab)
		_tabs[category] = tab

	if categories.is_empty():
		return
	if not _tabs.has(initial):
		initial = categories[0]
	_set_selected(initial, false)


func get_selected() -> ModuleData.Category:
	return _selected


func select(category: ModuleData.Category, animate: bool = true) -> void:
	if not _tabs.has(category):
		return
	_set_selected(category, animate)
	category_selected.emit(_selected)


func _on_tab_pressed(category: ModuleData.Category) -> void:
	if category == _selected:
		return
	_set_selected(category, true)
	category_selected.emit(_selected)


func _set_selected(category: ModuleData.Category, animate: bool) -> void:
	_selected = category
	for cat: ModuleData.Category in _tabs:
		var tab: _CategoryTab = _tabs[cat]
		tab.set_expanded(cat == _selected, animate)


class _CategoryTab:
	extends Button

	var category: ModuleData.Category
	var _label_text: String = ""
	var _icon: TextureRect
	var _name_label: Label
	var _row: HBoxContainer
	var _tween: Tween
	var _expanded: bool = false
	var _style_normal: StyleBoxFlat
	var _style_hover: StyleBoxFlat
	var _style_selected: StyleBoxFlat

	func setup(
		p_category: ModuleData.Category,
		p_label: String,
		icon_tex: Texture2D
	) -> void:
		category = p_category
		_label_text = p_label
		flat = true
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		clip_contents = true
		custom_minimum_size = Vector2(CategoryTabBar.TAB_SIZE, CategoryTabBar.TAB_SIZE)

		_build_styles()
		_apply_style(false)

		_row = HBoxContainer.new()
		_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_row.alignment = BoxContainer.ALIGNMENT_CENTER
		_row.add_theme_constant_override("separation", 8)
		_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_row.offset_left = 4.0
		_row.offset_right = -4.0
		_row.offset_top = 4.0
		_row.offset_bottom = -4.0
		add_child(_row)

		_icon = TextureRect.new()
		_icon.texture = icon_tex
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.custom_minimum_size = Vector2(22, 22)
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_row.add_child(_icon)

		_name_label = Label.new()
		_name_label.text = p_label
		_name_label.visible = false
		_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_name_label.add_theme_font_override("font", HudPanelStyle.get_font())
		_name_label.add_theme_font_size_override("font_size", 12)
		_name_label.add_theme_color_override("font_color", HudPanelStyle.COLOR_TEXT_PRIMARY)
		_row.add_child(_name_label)

		tooltip_text = p_label

	func set_expanded(expanded: bool, animate: bool) -> void:
		_expanded = expanded
		_name_label.visible = expanded
		_apply_style(expanded)
		tooltip_text = "" if expanded else _label_text

		var target_w: float = CategoryTabBar.TAB_SIZE
		if expanded:
			var font: Font = HudPanelStyle.get_font()
			var text_w: float = font.get_string_size(
				_label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12
			).x
			target_w = CategoryTabBar.TAB_SIZE + text_w + 18.0

		if _tween != null and _tween.is_valid():
			_tween.kill()

		if animate and is_inside_tree():
			_tween = create_tween()
			_tween.set_ease(Tween.EASE_OUT)
			_tween.set_trans(Tween.TRANS_CUBIC)
			_tween.tween_property(
				self, "custom_minimum_size:x", target_w, CategoryTabBar.EXPAND_DURATION
			)
		else:
			custom_minimum_size.x = target_w

	func _build_styles() -> void:
		_style_normal = StyleBoxFlat.new()
		_style_normal.bg_color = HudPanelStyle.COLOR_BG_SURFACE
		_style_normal.border_color = HudPanelStyle.COLOR_BORDER_DEFAULT
		_style_normal.set_border_width_all(1)
		_style_normal.set_corner_radius_all(4)

		_style_hover = _style_normal.duplicate() as StyleBoxFlat
		_style_hover.border_color = HudPanelStyle.COLOR_CYAN
		_style_hover.bg_color = HudPanelStyle.COLOR_BG_SURFACE.lightened(0.06)

		_style_selected = _style_normal.duplicate() as StyleBoxFlat
		_style_selected.border_color = HudPanelStyle.COLOR_CYAN
		_style_selected.bg_color = Color(HudPanelStyle.COLOR_CYAN, 0.14)

	func _apply_style(selected: bool) -> void:
		var base: StyleBoxFlat = _style_selected if selected else _style_normal
		add_theme_stylebox_override("normal", base)
		add_theme_stylebox_override("hover", _style_hover if not selected else _style_selected)
		add_theme_stylebox_override("pressed", _style_selected)
		add_theme_stylebox_override("focus", base)
