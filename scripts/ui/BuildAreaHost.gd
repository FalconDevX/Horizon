class_name BuildAreaHost
extends Control
## Expands to at least the ScrollContainer viewport and centers the build grid inside.
## Enables true centering when the grid is smaller than the view, and proper scroll
## centering when it is larger.

@export var grid_path: NodePath = ^"ShipGridUI"

var _grid: Control


func _ready() -> void:
	if has_node(grid_path):
		_grid = get_node(grid_path) as Control
	resized.connect(_recenter)
	call_deferred("refresh")


func refresh() -> void:
	_fit_to_viewport_and_grid()
	_recenter()


func _fit_to_viewport_and_grid() -> void:
	var scroll := get_parent() as ScrollContainer
	var view := scroll.size if scroll != null else size
	var grid_size := Vector2.ZERO
	if _grid != null:
		grid_size = _grid.custom_minimum_size
		if grid_size == Vector2.ZERO:
			grid_size = _grid.size

	var host := Vector2(
		maxi(ceili(view.x), ceili(grid_size.x)),
		maxi(ceili(view.y), ceili(grid_size.y))
	)
	custom_minimum_size = host
	size = host


func _recenter() -> void:
	if _grid == null:
		return
	var grid_size := _grid.custom_minimum_size
	if grid_size == Vector2.ZERO:
		grid_size = _grid.size
	_grid.position = ((size - grid_size) * 0.5).floor()
	_grid.size = grid_size
