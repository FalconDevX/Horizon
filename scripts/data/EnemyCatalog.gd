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
		{
			"id": "sniper",
			"title": "Sniper",
			"texture": preload("res://textures/enemies/enemy_sniper.png"),
			"scene": preload("res://scenes/enemies/EnemySniper.tscn"),
		},
		{
			"id": "kamikaze",
			"title": "Kamikaze",
			"texture": preload("res://textures/enemies/enemy_kamikaze.png"),
			"scene": preload("res://scenes/enemies/EnemyKamikaze.tscn"),
		},
		{
			"id": "cruiser",
			"title": "Cruiser",
			"texture": preload("res://textures/enemies/enemy_cruiser.png"),
			"scene": preload("res://scenes/enemies/EnemyCruiser.tscn"),
		},
		{
			"id": "mothership",
			"title": "Mothership",
			"texture": preload("res://textures/enemies/enemy_mothership.png"),
			"scene": preload("res://scenes/enemies/EnemyMothership.tscn"),
		},
		{
			"id": "minelayer",
			"title": "Minelayer",
			"texture": preload("res://textures/enemies/enemy_minelayer.png"),
			"scene": preload("res://scenes/enemies/EnemyMinelayer.tscn"),
		},
		{
			"id": "black_hole",
			"title": "Black hole",
			"texture": preload("res://textures/enemies/enemy_black_hole.png"),
			"scene": preload("res://scenes/enemies/EnemyBlackHole.tscn"),
		},
	]
