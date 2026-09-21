class_name FastScrollContainer
extends ScrollContainer
## Mouse-wheel scroll with a larger step (for Module Bay etc.).

@export var wheel_step: int = 96 ## pixels per wheel tick (default Godot is much smaller)
@export var shift_horizontal: bool = true


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
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if shift_horizontal and mb.shift_pressed:
					scroll_horizontal = scroll_horizontal - wheel_step
				else:
					scroll_vertical = scroll_vertical - wheel_step
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if shift_horizontal and mb.shift_pressed:
					scroll_horizontal = scroll_horizontal + wheel_step
				else:
					scroll_vertical = scroll_vertical + wheel_step
				accept_event()
			MOUSE_BUTTON_WHEEL_LEFT:
				scroll_horizontal = scroll_horizontal - wheel_step
				accept_event()
			MOUSE_BUTTON_WHEEL_RIGHT:
				scroll_horizontal = scroll_horizontal + wheel_step
				accept_event()
