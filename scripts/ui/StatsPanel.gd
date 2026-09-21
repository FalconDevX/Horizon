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
	"energy_consumption",
	"energy_generation",
	"energy_capacity",
	"net_energy",
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
	add_child(_header)

	_body = VBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 2)
	add_child(_body)

	for key in DISPLAY_KEYS:
		var row := HBoxContainer.new()
		var name_l := Label.new()
		name_l.text = key.replace("_", " ").capitalize()
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value_l := Label.new()
		value_l.text = "—"
		value_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(name_l)
		row.add_child(value_l)
		_body.add_child(row)
		_labels[key] = value_l

	_refresh_header()


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
			_labels[key].text = "Tak" if bool(value) else "NIE"
		elif typeof(value) == TYPE_FLOAT:
			_labels[key].text = "%.2f" % value
		else:
			_labels[key].text = str(value)
