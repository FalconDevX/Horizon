class_name EnemyCatalog
extends RefCounted
## Roster for the sandbox (E) enemy menu.

static func all_enemies() -> Array[Dictionary]:
	return [
		{
			"id": "basic",
			"title": "Basic",
			"texture": preload("res://textures/enemies/enemy_basic.png"),
			"scene": preload("res://scenes/enemies/Enemy.tscn"),
		},
		{
			"id": "tank",
			"title": "Tank",
			"texture": preload("res://textures/enemies/enemy_tank.png"),
			"scene": preload("res://scenes/enemies/EnemyTank.tscn"),
		},
	]
