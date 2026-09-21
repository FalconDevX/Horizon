class_name DragResizeHandle
extends ColorRect
## Thin drag strip that resizes a target Control by changing custom_minimum_size.

enum Axis {
	VERTICAL, ## Drag up/down — changes target height
	HORIZONTAL, ## Drag left/right — changes target width
}

signal size_dragged(new_size: float)

@export var axis: Axis = Axis.VERTICAL
@export var target_path: NodePath
@export var min_size: float = 80.0
@export var max_size: float = 600.0
## If true, dragging the handle "outward" (down for vertical / left for horizontal) grows the target.
@export var invert_drag: bool = false

var _target: Control
var _dragging: bool = false
var _drag_start_mouse: float = 0.0
var _drag_start_size: float = 0.0


func _ready() -> void:
	mouse_default_cursor_shape = (
		Control.CURSOR_VSIZE if axis == Axis.VERTICAL else Control.CURSOR_HSIZE
	)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if color.a < 0.01:
		color = Color(0.45, 0.55, 0.65, 0.35)
	if target_path != NodePath("") and has_node(target_path):
		_target = get_node(target_path) as Control
	_apply_handle_thickness()


func set_target(control: Control) -> void:
	_target = control


func _apply_handle_thickness() -> void:
	if axis == Axis.VERTICAL:
		custom_minimum_size = Vector2(0, 6)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = 0
	else:
		custom_minimum_size = Vector2(6, 0)
		size_flags_horizontal = 0
		size_flags_vertical = Control.SIZE_EXPAND_FILL


func _gui_input(event: InputEvent) -> void:
	if _target == null:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_start_mouse = mb.global_position.y if axis == Axis.VERTICAL else mb.global_position.x
				_drag_start_size = (
					_target.custom_minimum_size.y if axis == Axis.VERTICAL
					else _target.custom_minimum_size.x
				)
				if _drag_start_size <= 0.0:
					_drag_start_size = _target.size.y if axis == Axis.VERTICAL else _target.size.x
				mouse_default_cursor_shape = (
					Control.CURSOR_VSIZE if axis == Axis.VERTICAL else Control.CURSOR_HSIZE
				)
				accept_event()
			else:
				_end_drag()
				accept_event()


func _input(event: InputEvent) -> void:
	if not _dragging or _target == null:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_end_drag()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var mouse_now := motion.global_position.y if axis == Axis.VERTICAL else motion.global_position.x
		var delta := mouse_now - _drag_start_mouse
		if invert_drag:
			delta = -delta
		var new_size := clampf(_drag_start_size + delta, min_size, max_size)
		if axis == Axis.VERTICAL:
			_target.custom_minimum_size.y = new_size
		else:
			_target.custom_minimum_size.x = new_size
		size_dragged.emit(new_size)
		get_viewport().set_input_as_handled()


func _end_drag() -> void:
	_dragging = false
