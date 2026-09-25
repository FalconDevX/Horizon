class_name HelpPopup
extends Control
## Box of "how to use this" lines opened by an (i) button next to a window's
## X, so the controls are not spelled out in the window's header. Add it as
## the window's last child (it draws over everything else in the window);
## the window draws the button with draw_button() and calls toggle_at() when
## it is clicked, and close() on any other click.

const PADDING := Vector2(14.0, 12.0)
const LINE_HEIGHT := 18.0
const FONT_SIZE := 11

var lines: PackedStringArray = PackedStringArray()


func _init(help_lines: PackedStringArray = PackedStringArray()) -> void:
	lines = help_lines
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## The button's square, just left of the window's X square.
static func button_rect(close_rect: Rect2) -> Rect2:
	return Rect2(close_rect.position - Vector2(32.0, 0.0), close_rect.size)


static func draw_button(canvas: CanvasItem, rect: Rect2, hovered: bool, open: bool) -> void:
	var center: Vector2 = rect.get_center()
	var radius: float = rect.size.x * 0.5 - 1.0
	var color: Color = HudPanelStyle.COLOR_CYAN if open or hovered else HudPanelStyle.COLOR_TEXT_MUTED
	if open:
		canvas.draw_circle(center, radius, Color(HudPanelStyle.COLOR_CYAN, 0.18))
	canvas.draw_arc(center, radius, 0.0, TAU, 32, color, 1.5, true)
	canvas.draw_string(
		HudPanelStyle.get_font(), Vector2(rect.position.x, center.y + 5.0), "i",
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 14, color
	)


## Opens the box with its top-right corner at `top_right`, or closes it.
func toggle_at(top_right: Vector2) -> void:
	if visible:
		close()
		return
	var font: Font = HudPanelStyle.get_font()
	var width: float = 0.0
	for line in lines:
		width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
	size = Vector2(width, LINE_HEIGHT * lines.size()) + PADDING * 2.0
	position = top_right - Vector2(size.x, 0.0)
	visible = true
	move_to_front()
	queue_redraw()


func close() -> void:
	visible = false


func _draw() -> void:
	var box := Rect2(Vector2.ZERO, size)
	draw_rect(box, Color(HudPanelStyle.COLOR_BG_SURFACE, 0.97))
	draw_rect(box, HudPanelStyle.COLOR_BORDER_HOVER, false, 1.0)
	draw_rect(Rect2(Vector2.ZERO, Vector2(3.0, size.y)), HudPanelStyle.COLOR_CYAN)
	var font: Font = HudPanelStyle.get_font()
	for i in lines.size():
		draw_string(
			font, PADDING + Vector2(0.0, LINE_HEIGHT * i + 12.0), lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, HudPanelStyle.COLOR_TEXT_SECONDARY
		)
