extends CharacterBody2D
class_name Monster

# --- CONFIG ---
@export_group("Species Stats")
@export var species = "orc"
@export var max_health = 50.0
@export var speed = 50.0
@export var damage = 15.0
@export var attack_cooldown = 1.0
@export var attack_range = 20.0
@export var max_vitality_duration = 20.0
@export var ejection_range = 5 * 16.0

@export_group("RPG & XP")
@export var required_level = 1
@export var xp_min = 10
@export var xp_max = 20

@export_group("Animations")
@export var attack_animations_list: Array[String] = ["attack1", "attack2"]

enum State { IDLE, CHASE, ATTACK, WANDER, DEAD }
var current_state = State.WANDER

var health = 0.0
var current_vitality_time = 0.0
var target: Node2D = null
var can_attack = true
var last_position = Vector2.ZERO
var stuck_timer = 0.0

@onready var sprite = $AnimatedSprite2D
@onready var nav_agent = $NavigationAgent2D
@onready var raycast = $RayCast2D
@onready var timer_wander = Timer.new()
@onready var indicator = get_node_or_null("LevelIndicator")

func _ready():
	if "death" in attack_animations_list: attack_animations_list.erase("death")
	if "idle" in attack_animations_list: attack_animations_list.erase("idle")
	
	if health <= 0: health = max_health
	if current_vitality_time <= 0: current_vitality_time = max_vitality_duration
	if indicator: indicator.visible = false
	
	nav_agent.path_desired_distance = 10.0
	nav_agent.target_desired_distance = 10.0
	nav_agent.avoidance_enabled = false

	raycast.add_exception(self)
	
	add_child(timer_wander)
	timer_wander.wait_time = 2.0
	timer_wander.one_shot = true
	timer_wander.timeout.connect(_on_wander_timeout)
	
	if not sprite.animation_finished.is_connected(_on_animation_finished):
		sprite.animation_finished.connect(_on_animation_finished)
	
	add_to_group("enemy")
	last_position = global_position
	await get_tree().physics_frame
	enter_wander_state()

func _physics_process(delta):
	if current_state == State.DEAD: return
	
	stuck_timer += delta
	if stuck_timer >= 3.0:
		stuck_timer = 0.0
		if global_position.distance_to(last_position) < 10.0: enter_wander_state()
		last_position = global_position

	if current_state != State.ATTACK:
		scan_for_enemies()
		_check_attack_range()

	if current_state == State.ATTACK: velocity = Vector2.ZERO
	elif current_state == State.CHASE or current_state == State.WANDER: _process_movement_logic()
	move_and_slide()

func update_visual_indicator(player_level):
	var show_indicator = (player_level < required_level)
	if indicator: indicator.visible = show_indicator

func _process_movement_logic():
	if nav_agent.is_navigation_finished():
		velocity = Vector2.ZERO
		if current_state == State.WANDER and timer_wander.is_stopped():
			sprite.play("idle"); timer_wander.start(randf_range(1.0, 3.0))
	else:
		var next = nav_agent.get_next_path_position()
		var dir = global_position.direction_to(next)
		velocity = dir * speed
		sprite.play("walk"); sprite.speed_scale = speed / 60.0
		if velocity.x < -0.1: sprite.flip_h = true
		elif velocity.x > 0.1: sprite.flip_h = false

func scan_for_enemies():
	if is_instance_valid(target):
		if "current_state" in target and target.current_state == State.DEAD: 
			target = null; enter_wander_state(); return
		
		if target.is_in_group("player") and target.get("current_species") == "mask":
			target = null; enter_wander_state(); return

		if target is Node2D:
			nav_agent.target_position = target.global_position
			if global_position.distance_to(target.global_position) > 300: 
				target = null; enter_wander_state()
		else:
			target = null
			
		if current_state == State.IDLE: current_state = State.CHASE
		return

	var candidates = []
	candidates.append_array(get_tree().get_nodes_in_group("player"))
	candidates.append_array(get_tree().get_nodes_in_group("enemy"))
	var closer = null
	var min_distance = 250
	
	for c in candidates:
		if c == self or not is_instance_valid(c): continue
		
		if not c is Node2D: continue 

		if "current_state" in c and c.current_state == State.DEAD: continue
		
		var c_species = "unknown"
		if c.is_in_group("player"):
			if "current_species" in c:
				c_species = c.current_species
				if c_species == "mask": continue
		elif "species" in c:
			c_species = c.species
		
		if c_species != "" and c_species != self.species:
			var d = global_position.distance_to(c.global_position)
			if d < min_distance:
				raycast.target_position = to_local(c.global_position)
				raycast.force_raycast_update()
				if not raycast.is_colliding() or raycast.get_collider() == c:
					min_distance = d; closer = c

	if closer: target = closer; current_state = State.CHASE
	elif current_state == State.IDLE or current_state == State.CHASE: enter_wander_state()

func _check_attack_range():
	if is_instance_valid(target) and can_attack:
		if target.is_in_group("player") and target.get("current_species") == "mask":
			target = null
			enter_wander_state()
			return
			
		if global_position.distance_to(target.global_position) <= attack_range: launch_an_attack()

func enter_wander_state():
	current_state = State.WANDER
	target = null
	sprite.speed_scale = 1.0
	_pick_random_point()

func _pick_random_point():
	var rot = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(50, 150)
	var map = get_world_2d().navigation_map
	nav_agent.target_position = NavigationServer2D.map_get_closest_point(map, global_position + rot)

func _on_wander_timeout():
	if current_state == State.WANDER: _pick_random_point()

func launch_an_attack():
	current_state = State.ATTACK
	can_attack = false
	velocity = Vector2.ZERO
	sprite.speed_scale = 1.0
	if attack_animations_list.size() > 0: sprite.play(attack_animations_list.pick_random())
	if is_instance_valid(target): sprite.flip_h = (target.global_position.x < global_position.x)

func _on_animation_finished():
	if not is_inside_tree(): return # Check 1
	
	if current_state == State.DEAD: 
		if get_tree(): await get_tree().create_timer(3.0).timeout
		queue_free()
		return

	if sprite.animation in attack_animations_list:
		if is_instance_valid(target) and global_position.distance_to(target.global_position) < attack_range + 20:
			if target.is_in_group("player") and target.get("current_species") == "mask":
				pass
			elif target.has_method("take_damage"):
				target.take_damage(damage, self)
		
		current_state = State.IDLE
		
		# --- CORRECTION DU CRASH ---
		if get_tree(): # Check 2 : On vérifie que l'arbre existe avant de créer le timer
			await get_tree().create_timer(attack_cooldown).timeout
			can_attack = true

func take_damage(amount, attacker = null):
	if current_state == State.DEAD: return
	health -= amount
	
	if is_instance_valid(attacker) and attacker != self:
		target = attacker
		current_state = State.CHASE

	sprite.modulate = Color.RED
	var t = create_tween()
	t.tween_property(sprite, "modulate", Color.WHITE, 0.2)
	
	if health <= 0:
		if is_instance_valid(attacker) and attacker.is_in_group("player"):
			attacker.gain_xp(randi_range(xp_min, xp_max))
		death()

func death():
	current_state = State.DEAD
	velocity = Vector2.ZERO
	$CollisionShape2D.set_deferred("disabled", true)
	nav_agent.set_velocity(Vector2.ZERO)
	if indicator: indicator.visible = false
	if sprite.sprite_frames.has_animation("death"): sprite.play("death")
	else: _on_animation_finished()
