class_name StatsPanel
extends VBoxContainer
## Listens to ShipHull.stats_changed and prints key aggregates.
## Body is collapsible via the header button.

@export var ship_hull: ShipHull
@export var start_expanded: bool = true

var _labels: Dictionary = {}
var _header: Button
var _body: VBoxContainer
var _expanded: bool = true


const DISPLAY_KEYS: Array[String] = [
	"mass",
	"durability",
	"health",
	"thrust",
	"fuel_consumption",
	"fuel_capacity",
	"energy_consumption",
	"energy_generation",
	"energy_capacity",
	"net_energy",
	"shield_strength",
	"damage",
	"repair_rate",
	"max_heat",
	"occupied_cells",
	"capacity",
	"module_count",
	"thrust_to_weight",
	"hulls_linked",
]


func _ready() -> void:
	_build_ui()
	set_expanded(start_expanded)
	if ship_hull != null:
		ship_hull.stats_changed.connect(_on_stats_changed)
		_on_stats_changed(ship_hull.get_stats_dictionary())


func bind_hull(hull: ShipHull) -> void:
	if ship_hull != null and ship_hull.stats_changed.is_connected(_on_stats_changed):
		ship_hull.stats_changed.disconnect(_on_stats_changed)
	ship_hull = hull
	if ship_hull != null:
		ship_hull.stats_changed.connect(_on_stats_changed)
		_on_stats_changed(ship_hull.get_stats_dictionary())


func set_expanded(value: bool) -> void:
	_expanded = value
	if _body != null:
		_body.visible = _expanded
	if _expanded:
		size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		size_flags_vertical = 0
	_refresh_header()


func toggle_expanded() -> void:
	set_expanded(not _expanded)


func _build_ui() -> void:
	for child in get_children():
		child.queue_free()
	_labels.clear()

	_header = Button.new()
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_header.pressed.connect(toggle_expanded)
	_style_header()
	add_child(_header)

	_body = VBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	add_child(_body)

	for key in DISPLAY_KEYS:
		var row := HBoxContainer.new()
		var name_l := Label.new()
		name_l.text = key.replace("_", " ").capitalize()
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.add_theme_font_override("font", HudPanelStyle.get_font())
		name_l.add_theme_font_size_override("font_size", 12)
		name_l.add_theme_color_override("font_color", HudPanelStyle.COLOR_TEXT_MUTED)
		var value_l := Label.new()
		value_l.text = "—"
		value_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_l.add_theme_font_override("font", HudPanelStyle.get_font())
		value_l.add_theme_font_size_override("font_size", 12)
		value_l.add_theme_color_override("font_color", HudPanelStyle.COLOR_CYAN)
		row.add_child(name_l)
		row.add_child(value_l)
		_body.add_child(row)
		_labels[key] = value_l

	_refresh_header()


func _style_header() -> void:
	var flat := StyleBoxFlat.new()
	flat.bg_color = HudPanelStyle.COLOR_BG_SURFACE
	flat.border_color = HudPanelStyle.COLOR_BORDER_DEFAULT
	flat.set_border_width_all(1)
	flat.set_corner_radius_all(4)
	flat.set_content_margin_all(6)
	var flat_hover := flat.duplicate() as StyleBoxFlat
	flat_hover.border_color = HudPanelStyle.COLOR_CYAN
	_header.add_theme_stylebox_override("normal", flat)
	_header.add_theme_stylebox_override("hover", flat_hover)
	_header.add_theme_stylebox_override("pressed", flat_hover)
	_header.add_theme_stylebox_override("focus", flat)
	_header.add_theme_font_override("font", HudPanelStyle.get_font())
	_header.add_theme_font_size_override("font_size", 14)
	_header.add_theme_color_override("font_color", HudPanelStyle.COLOR_CYAN)
	_header.add_theme_color_override("font_hover_color", HudPanelStyle.COLOR_TEXT_PRIMARY)


func _refresh_header() -> void:
	if _header == null:
		return
	var arrow := "▼" if _expanded else "▶"
	_header.text = "%s  Ship Stats" % arrow


func _on_stats_changed(new_stats: Dictionary) -> void:
	for key in DISPLAY_KEYS:
		if not _labels.has(key):
			continue
		var value: Variant = new_stats.get(key, 0)
		if key == "hulls_linked":
			_labels[key].text = "YES" if bool(value) else "NO"
		elif typeof(value) == TYPE_FLOAT:
			_labels[key].text = "%.2f" % value
		else:
			_labels[key].text = str(value)
