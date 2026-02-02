extends Marker2D

@export var monster_scene: PackedScene 

@export var spawn_time = 3.0
@export var spawn_radius = 0
@export var max_monsters = 5
@export var monster_parent_node_name = "Enemis"

var current_monster = 0

@onready var timer = $Timer

func _ready():
	timer.wait_time = spawn_time
	timer.timeout.connect(_on_timer_timeout)
	
	if monster_scene == null:
		push_error("No monster set in the spawner !")
		timer.stop()

func _on_timer_timeout():
	spawn_monster()

func spawn_monster():
	if current_monster >= max_monsters:
		return
		
	if monster_scene:
		var monster = monster_scene.instantiate()
		
		if "parent_spawner" in monster:
			monster.parent_spawner = self
		
		var gap = Vector2.ZERO
		if spawn_radius > 0:
			gap = Vector2(randf_range(-spawn_radius, spawn_radius), randf_range(-spawn_radius, spawn_radius))
		
		monster.global_position = global_position + gap
		
		get_parent().add_child(monster)
		
		monster.tree_exited.connect(_on_monster_death)
		current_monster += 1

func _on_monster_death():
	current_monster -= 1
	if current_monster < 0: current_monster = 0
	
func notify_possession_start(monster_node):
	if monster_node.tree_exited.is_connected(_on_monster_death):
		monster_node.tree_exited.disconnect(_on_monster_death)

func notify_possession_end(new_monster_node):
	new_monster_node.parent_spawner = self
	new_monster_node.tree_exited.connect(_on_monster_death)

func notify_possession_death():
	_on_monster_death()
