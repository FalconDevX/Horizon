class_name PannableScrollContainer
extends ScrollContainer
## ScrollContainer with middle-mouse pan and center-view helper.

var _panning: bool = false
var _last_mouse: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_hide_scrollbars()


func _hide_scrollbars() -> void:
	var empty := StyleBoxEmpty.new()
	for bar in [get_h_scroll_bar(), get_v_scroll_bar()]:
		if bar == null:
			continue
		bar.add_theme_stylebox_override("scroll", empty)
		bar.add_theme_stylebox_override("scroll_focus", empty)
		bar.add_theme_stylebox_override("grabber", empty)
		bar.add_theme_stylebox_override("grabber_highlight", empty)
		bar.add_theme_stylebox_override("grabber_pressed", empty)
		bar.custom_minimum_size = Vector2.ZERO


func _gui_input(event: InputEvent) -> void:
	_handle_pan_event(event)


func _input(event: InputEvent) -> void:
	if not _panning:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE and not mb.pressed:
			_panning = false
			mouse_default_cursor_shape = Control.CURSOR_ARROW
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_apply_pan((event as InputEventMouseMotion).global_position)
		get_viewport().set_input_as_handled()


func begin_pan(global_pos: Vector2) -> void:
	_panning = true
	_last_mouse = global_pos
	mouse_default_cursor_shape = Control.CURSOR_DRAG


func end_pan() -> void:
	_panning = false
	mouse_default_cursor_shape = Control.CURSOR_ARROW


func is_panning() -> bool:
	return _panning


func pan_to(global_pos: Vector2) -> void:
	if _panning:
		_apply_pan(global_pos)


const WHEEL_STEP := 48


func scroll_vertical_by(pixels: int) -> void:
	scroll_vertical = scroll_vertical + pixels


func scroll_horizontal_by(pixels: int) -> void:
	scroll_horizontal = scroll_horizontal + pixels


func center_view() -> void:
	# Wait one frame so layout sizes are current.
	await get_tree().process_frame
	var host := get_child(0) as BuildAreaHost
	if host != null:
		host.refresh()
		await get_tree().process_frame
	var content := _content_size()
	var view := size
	scroll_horizontal = maxi(0, int((content.x - view.x) * 0.5))
	scroll_vertical = maxi(0, int((content.y - view.y) * 0.5))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		var host := get_child(0) as BuildAreaHost
		if host != null:
			host.refresh()


func _handle_pan_event(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				begin_pan(mb.global_position)
			else:
				end_pan()
			accept_event()
	elif event is InputEventMouseMotion and _panning:
		_apply_pan((event as InputEventMouseMotion).global_position)
		accept_event()


func _apply_pan(global_pos: Vector2) -> void:
	var delta := global_pos - _last_mouse
	_last_mouse = global_pos
	scroll_horizontal = scroll_horizontal - int(delta.x)
	scroll_vertical = scroll_vertical - int(delta.y)


func _content_size() -> Vector2:
	if get_child_count() == 0:
		return size
	var child := get_child(0) as Control
	if child == null:
		return size
	return child.get_combined_minimum_size().max(child.size)
