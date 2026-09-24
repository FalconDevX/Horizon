class_name AsteroidBeltMap
extends Node2D
## Map marking for the asteroid belts (asteroid_belts.gd): each belt's whole
## band tinted a see-through light red, with thin edges, so it reads from far
## out even when the rocks themselves are specks. Lives on the BehindWorld
## layer, under the orbit lines and the 3D bodies.

const FILL := Color(1.0, 0.45, 0.45, 0.09)
const EDGE := Color(1.0, 0.55, 0.55, 0.3)
## Edge width in screen pixels.
const EDGE_SCREEN_WIDTH := 1.5
const POINTS := 512

var _center := Vector2.ZERO
var _zoom := 1.0


func setup(sun_center: Vector2) -> void:
	_center = sun_center
	queue_redraw()


## Edges keep a constant screen width, so redraw when the zoom moves.
func set_zoom(zoom: float) -> void:
	if is_equal_approx(zoom, _zoom):
		return
	_zoom = zoom
	queue_redraw()


func _draw() -> void:
	var edge_width: float = EDGE_SCREEN_WIDTH / maxf(_zoom, 1e-6)
	for belt: Dictionary in AsteroidBelts.BELTS:
		var inner: float = belt["inner"]
		var outer: float = belt["outer"]
		draw_arc(_center, (inner + outer) * 0.5, 0.0, TAU, POINTS, FILL, outer - inner)
		draw_arc(_center, inner, 0.0, TAU, POINTS, EDGE, edge_width)
		draw_arc(_center, outer, 0.0, TAU, POINTS, EDGE, edge_width)
