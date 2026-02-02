extends CharacterBody2D

enum State { MASK, POSSESSED, DEAD }
var current_state = State.MASK

# --- CONFIG ---
@export var radius_possession_survival = 32.0
@export var time_survival_mask = 5.0

@export_group("RPG System")
@export var xp_cost_possession = 15
@export var xp_to_next_level_base = 100
@export var xp_growth_factor = 1.5

# --- Stats ---
var speed = 0
var max_health = 100.0
var damage = 10.0
var attack_cooldown = 1.0
var current_ejection_range = 5 * 16.0
var current_attack_range = 20.0

# --- State ---
var health = 100.0
var current_xp = 0
var current_level = 1
var max_xp_current_level = 100

var current_species = "mask"
# "first_appearance" SUPPRIMÉ
var active_mask = null
var is_dying = false
var input_locked = true
var can_attack = true
var is_attacking = false
var host_scene_path = ""

var visual_target: Node2D = null

@onready var sprite = $AnimatedSprite2D
@onready var collision_shape = $CollisionShape2D
@onready var camera = $Camera2D

@onready var health_gauge = $Health/HealthGroup/HealthGauge
@onready var health_group = $Health/HealthGroup
@onready var vitality_group = $Vitality/VitalityGroup
@onready var vitality_gauge = $Vitality/VitalityGroup/VitalityGauge
@onready var cooldown_gauge = $CooldownUI/CooldownGauge
@onready var cooldown_timer = $CooldownTimer
@onready var vitality_timer = $PossessionTimer
@onready var death_timer = $DeathTimer

@onready var xp_gauge = $XP/XPGroup/XPGauge
@onready var level_label = $XP/XPGroup/LevelLabel

@onready var possession_sound = $PossessionSound

var mask_scene = preload("res://scenes/projectile_mask.tscn")
var death_scene_path = "res://scenes/death.tscn"
var original_frames = null
var original_scale = Vector2.ONE
var original_shape = null
var current_host_spawner = null

func _ready():
	add_to_group("player")
	
	health = 100.0; max_health = 100.0; speed = 150.0
	max_xp_current_level = xp_to_next_level_base
	
	original_frames = sprite.sprite_frames
	original_scale = sprite.scale
	if collision_shape.shape: original_shape = collision_shape.shape.duplicate()
	
	if not vitality_timer.timeout.is_connected(_on_vitality_empty): vitality_timer.timeout.connect(_on_vitality_empty)
	if not death_timer.timeout.is_connected(death): death_timer.timeout.connect(death)
	if not sprite.animation_finished.is_connected(_on_animation_finished): sprite.animation_finished.connect(_on_animation_finished)
	
	if not InputMap.has_action("attack"): InputMap.add_action("attack"); InputMap.action_add_event("attack", InputEventMouseButton.new())
	if not InputMap.has_action("eject_or_possess"): var k = InputEventKey.new(); k.keycode = KEY_SPACE; InputMap.add_action("eject_or_possess"); InputMap.action_add_event("eject_or_possess", k)

	camera.top_level = true
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 10.0
	
	await get_tree().create_timer(0.5).timeout
	input_locked = false
	devenir_masque()

func _physics_process(_delta):
	if current_state == State.MASK and is_instance_valid(active_mask) and active_mask is Node2D:
		camera.global_position = active_mask.global_position
	else:
		camera.global_position = global_position

	if input_locked or current_state == State.DEAD: return
	
	# UI
	if health_gauge: 
		health_gauge.value = health;
		health_gauge.max_value = max_health
		health_group.visible = (current_state != State.MASK)
	if xp_gauge: xp_gauge.value = current_xp; xp_gauge.max_value = max_xp_current_level
	if level_label: level_label.text = str(current_level)
	
	if vitality_group:
		vitality_group.visible = (current_state == State.POSSESSED or (current_state == State.MASK and not death_timer.is_stopped()))
		if current_state == State.POSSESSED: 
			vitality_gauge.value = vitality_timer.time_left
			vitality_gauge.max_value = vitality_timer.wait_time
		elif current_state == State.MASK: 
			vitality_gauge.value = death_timer.time_left 
			vitality_gauge.max_value = time_survival_mask
	
	if cooldown_gauge:
		var ratio = 0.0
		if not cooldown_timer.is_stopped(): ratio = 1.0 - (cooldown_timer.time_left / cooldown_timer.wait_time)
		else: ratio = 1.0
		cooldown_gauge.value = ratio * 100

	# États
	if current_state == State.MASK: update_visual_target_and_indicators()
	else: reset_all_enemy_tints(); update_enemies_red_dots_only(); visual_target = null; queue_redraw()

	match current_state:
		State.MASK:
			velocity = Vector2.ZERO
			move_and_slide()
			if Input.is_action_just_pressed("eject_or_possess") and cooldown_timer.is_stopped():
				mask_action_management()

		State.POSSESSED:
			if is_attacking: velocity = Vector2.ZERO; move_and_slide(); return 
			
			var direction = Input.get_vector("left", "right", "up", "down")
			if direction:
				velocity = direction * speed
				sprite.play("walk")
				sprite.speed_scale = speed / 60.0
				sprite.flip_h = direction.x < 0
			else:
				velocity = Vector2.ZERO
				if "attack" not in sprite.animation: sprite.play("idle"); sprite.speed_scale = 1.0
			move_and_slide()
			
			if Input.is_action_just_pressed("attack") and can_attack: lancer_attaque_joueur()
			if Input.is_action_just_pressed("eject_or_possess"):
				if cooldown_timer.is_stopped():
					if vitality_timer.time_left < (vitality_timer.wait_time - 0.5): eject_mask(false)

func mask_action_management():
	
	var enemies = get_tree().get_nodes_in_group("enemy")
	var nearest_mob = null
	
	var min_dist = radius_possession_survival 

	for e in enemies:
		if not is_instance_valid(e): continue
		if e.get("health") <= 0: continue
		if "current_state" in e and e.current_state == 4: continue # Mort

		var d = global_position.distance_to(e.global_position)
		
		if d <= min_dist:
			min_dist = d
			nearest_mob = e
	
	if nearest_mob:
		fire_projectile_towards(nearest_mob.global_position, radius_possession_survival * 1.5, null)

func fire_projectile_towards(target_pos, max_dist_override, body_to_ignore):
	if health > 0 and current_xp >= xp_cost_possession:
		current_xp -= xp_cost_possession
	
	var mask = mask_scene.instantiate()
	var dir = (target_pos - global_position).normalized()
	var real_distance = global_position.distance_to(target_pos)
	var final_distance = min(real_distance + 10, max_dist_override)
	
	mask.distance_max = final_distance
	mask.speed = 450
	mask.global_position = global_position + (dir * 20)
	mask.look_at(global_position + dir * 100)
	mask.player_ref = self
	mask.body_to_ignore = body_to_ignore
	
	get_parent().add_child(mask)
	
	active_mask = mask
	visible = false
	collision_shape.set_deferred("disabled", true)
	vitality_timer.stop()
	current_state = State.MASK
	if cooldown_timer: cooldown_timer.start()

func eject_mask(body_is_dead: bool):
	if current_state == State.DEAD: return
	
	var dropped_mob = null
	
	if not body_is_dead and host_scene_path != "":
		var scene = load(host_scene_path)
		if scene:
			var mob = scene.instantiate()
			mob.global_position = global_position
			mob.health = health
			mob.current_vitality_time = vitality_timer.time_left
			get_parent().add_child(mob)
			dropped_mob = mob

			if current_host_spawner != null and current_host_spawner.has_method("notify_possession_end"):
				current_host_spawner.notify_possession_end(mob)
	
	if (body_is_dead or dropped_mob == null) and current_host_spawner != null:
		if current_host_spawner.has_method("notify_possession_death"):
			current_host_spawner.notify_possession_death()

	current_host_spawner = null

	if not body_is_dead:
		fire_projectile_towards(get_global_mouse_position(), current_ejection_range, dropped_mob)
	else:
		miss_possession(global_position)

func success_possession(new_host):
	if possession_sound:
		possession_sound.pitch_scale = randf_range(0.9, 1.1)
		possession_sound.play()
		
	current_host_spawner = null
	if "parent_spawner" in new_host and new_host.parent_spawner != null:
		current_host_spawner = new_host.parent_spawner
		if current_host_spawner.has_method("notify_possession_start"):
			current_host_spawner.notify_possession_start(new_host)

	is_attacking = false
	can_attack = true
	sprite.modulate = Color.WHITE

	visible = true
	collision_shape.set_deferred("disabled", false)
	death_timer.stop()
	current_state = State.POSSESSED
	global_position = new_host.global_position
	
	health = new_host.health
	max_health = new_host.max_health
	speed = new_host.speed
	damage = new_host.damage
	attack_cooldown = new_host.attack_cooldown
	current_ejection_range = new_host.ejection_range
	current_species = new_host.species
	current_attack_range = new_host.attack_range
	var base_duration = new_host.max_vitality_duration
	
	if "current_vitality_time" in new_host and new_host.current_vitality_time > 0:
		base_duration = new_host.current_vitality_time

	if new_host.scene_file_path: host_scene_path = new_host.scene_file_path
	var enemy_sprite = new_host.get_node("AnimatedSprite2D")
	sprite.sprite_frames = enemy_sprite.sprite_frames
	sprite.scale = enemy_sprite.scale
	if enemy_sprite.offset: sprite.offset = enemy_sprite.offset
	
	new_host.queue_free()
	vitality_timer.start(base_duration)

func _draw():
	if current_state == State.MASK:
		var alpha = 0.2 + (sin(Time.get_ticks_msec() * 0.005) * 0.1)
		draw_circle(Vector2.ZERO, radius_possession_survival, Color(0.2, 0.6, 1.0, alpha), true)
		draw_circle(Vector2.ZERO, radius_possession_survival, Color(0.2, 0.6, 1.0, 0.5), false, 1.0)

func update_visual_target_and_indicators():
	var enemies = get_tree().get_nodes_in_group("enemy")
	var closer = null
	var d_min = radius_possession_survival
	for e in enemies:
		e.modulate = Color.WHITE
		if e.has_method("update_visual_indicator"): e.update_visual_indicator(current_level)
		if "current_state" in e and e.current_state == 4: continue
		var d = global_position.distance_to(e.global_position)
		if d < d_min: d_min = d; closer = e
	visual_target = closer
	if visual_target: visual_target.modulate = Color(0.4, 0.7, 1.0)
	queue_redraw()

func reset_all_enemy_tints():
	var enemies = get_tree().get_nodes_in_group("enemy")
	for e in enemies: e.modulate = Color.WHITE

func update_enemies_red_dots_only():
	var enemies = get_tree().get_nodes_in_group("enemy")
	for e in enemies:
		if e.has_method("update_visual_indicator"): e.update_visual_indicator(current_level)

func gain_xp(amount):
	current_xp += amount
	while current_xp >= max_xp_current_level:
		current_xp -= max_xp_current_level
		current_level += 1
		max_xp_current_level = int(max_xp_current_level * xp_growth_factor)
		sprite.modulate = Color(1.5, 1.5, 2.0)
		var t = create_tween()
		t.tween_property(sprite, "modulate", Color.WHITE, 0.5)

func lancer_attaque_joueur():
	can_attack = false
	is_attacking = true
	velocity = Vector2.ZERO
	sprite.speed_scale = 1.0
	if sprite.sprite_frames.has_animation("attack1"): sprite.play("attack1")
	elif sprite.sprite_frames.has_animation("attack2"): sprite.play("attack2")
	elif sprite.sprite_frames.has_animation("attack"): sprite.play("attack")
	else: can_attack = true; is_attacking = false

func _on_animation_finished():
	if not is_instance_valid(sprite): return
	
	if "attack" in sprite.animation:
		var enemies = get_tree().get_nodes_in_group("enemy")
		for e in enemies:
			if not is_instance_valid(e): continue
			if global_position.distance_to(e.global_position) < 50:
				if e.has_method("take_damage"): e.take_damage(damage, self)
		sprite.play("idle")
		is_attacking = false
		await get_tree().create_timer(attack_cooldown).timeout
		can_attack = true

func take_damage(amount, _attacker = null):
	if is_dying or health <= 0: return
	health -= amount
	sprite.modulate = Color.RED
	var t = create_tween()
	t.tween_property(sprite, "modulate", Color.WHITE, 0.1)
	if health <= 0:
		if current_state == State.POSSESSED: eject_mask(true)
		else: death()

func miss_possession(pos):
	active_mask = null
	global_position = pos
	devenir_masque()

func devenir_masque():
	is_attacking = false
	can_attack = true
	
	current_state = State.MASK
	current_species = "mask"
	visible = true
	collision_shape.set_deferred("disabled", false)
	health = 100.0; speed = 0
	sprite.sprite_frames = original_frames; sprite.scale = original_scale
	sprite.play("idle"); sprite.speed_scale = 1.0
	if original_shape: collision_shape.shape = original_shape
	vitality_timer.stop()
	
	death_timer.start(time_survival_mask)

func _on_vitality_empty():
	eject_mask(true)

func death():
	is_dying = true; current_state = State.DEAD
	get_tree().change_scene_to_file(death_scene_path)
