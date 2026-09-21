class_name CollapsibleSection
extends VBoxContainer
## Header button that shows/hides [member content].

signal toggled(expanded: bool)

@export var title: String = "Section":
	set(value):
		title = value
		_refresh_header()

@export var expanded: bool = true:
	set(value):
		expanded = value
		_apply_expanded()

@export var content_path: NodePath

## When set, collapse restores to this height on expand (drag-resize target).
var resized_height: float = 200.0

var _header: Button
var _content: Control


func _ready() -> void:
	_ensure_header()
	if content_path != NodePath("") and has_node(content_path):
		_content = get_node(content_path) as Control
	if custom_minimum_size.y > 0.0:
		resized_height = custom_minimum_size.y
	_apply_expanded()


func setup(p_title: String, p_content: Control, start_expanded: bool = true) -> void:
	title = p_title
	_content = p_content
	_ensure_header()
	if _content.get_parent() == self:
		move_child(_header, 0)
		move_child(_content, 1)
	expanded = start_expanded


func set_expanded(value: bool) -> void:
	expanded = value


func toggle() -> void:
	expanded = not expanded


func remember_height(height: float) -> void:
	resized_height = height


func _ensure_header() -> void:
	if _header != null:
		_refresh_header()
		return
	_header = Button.new()
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_header.pressed.connect(toggle)
	add_child(_header)
	move_child(_header, 0)
	_refresh_header()


func _refresh_header() -> void:
	if _header == null:
		return
	var arrow := "▼" if expanded else "▶"
	_header.text = "%s  %s" % [arrow, title]


func _apply_expanded() -> void:
	_refresh_header()
	if _content != null:
		_content.visible = expanded
		_content.size_flags_vertical = Control.SIZE_EXPAND_FILL if expanded else 0
	size_flags_vertical = 0
	if expanded:
		custom_minimum_size.y = resized_height
	else:
		# Keep only header height when collapsed.
		custom_minimum_size.y = 0
	toggled.emit(expanded)
