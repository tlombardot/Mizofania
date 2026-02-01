extends CharacterBody2D

enum State { MASQUE, POSSEDE, MORT }
var current_state = State.MASQUE

# --- PARAMÈTRES ---
@export var rayon_possession_survie = 32.0
@export var temps_survie_masque = 5.0
@export var duree_possession_max = 30.0
@export var cooldown_tir = 5.0
@export var distance_premier_saut = 80.0

@export_group("RPG System")
@export var xp_cost_possession = 15
@export var xp_to_next_level_base = 100
@export var xp_growth_factor = 1.5

# --- Stats ---
var speed = 150.0
var max_health = 100.0
var damage = 10.0
var attack_cooldown = 1.0
var ejection_range_actuelle = 5 * 16.0
var attack_range_actuelle = 40.0

# --- État ---
var health = 100.0
var current_xp = 0
var current_level = 1
var max_xp_current_level = 100

var espece_actuelle = "masque"
var premiere_apparition = true
var masque_actif = null
var is_dying = false
var input_locked = true
var can_attack = true
var is_attacking = false
var host_scene_path = ""

# --- Mode Parasite ---
var is_control_locked = false 
var parasite_nav_agent: NavigationAgent2D = null
var parasite_target: Node2D = null
var parasite_state = 0 
var parasite_wander_timer = 0.0

var visual_target: Node2D = null

@onready var sprite = $AnimatedSprite2D
@onready var collision_shape = $CollisionShape2D
@onready var camera = $Camera2D

# UI
@onready var jauge_sante = $Sante/GroupeSante/JaugeSante
@onready var groupe_vitalite = $Vitalite/GroupeVitalite
@onready var jauge_vitalite = $Vitalite/GroupeVitalite/JaugeVitalite
@onready var jauge_cooldown = $CooldownUI/JaugeCooldown
@onready var timer_cooldown = $TimerCooldown
@onready var timer_vitalite = $TimerPossession
@onready var timer_mort = $DeathTimer
@onready var jauge_xp = $XP/JaugeXP
@onready var label_niveau = $XP/LabelNiveau 

var masque_scene = preload("res://scenes/masque_projectile.tscn")
var death_scene_path = "res://scenes/death.tscn"
var original_frames = null
var original_scale = Vector2.ONE
var original_shape = null

func _ready():
	add_to_group("player")
	
	parasite_nav_agent = NavigationAgent2D.new()
	parasite_nav_agent.path_desired_distance = 20.0
	parasite_nav_agent.target_desired_distance = 20.0
	parasite_nav_agent.avoidance_enabled = true
	add_child(parasite_nav_agent)
	
	health = 100.0; max_health = 100.0; speed = 150.0
	max_xp_current_level = xp_to_next_level_base
	
	original_frames = sprite.sprite_frames
	original_scale = sprite.scale
	if collision_shape.shape: original_shape = collision_shape.shape.duplicate()
	
	timer_vitalite.timeout.connect(_on_vitalite_empty)
	timer_mort.timeout.connect(mourir)
	if not sprite.animation_finished.is_connected(_on_animation_finished):
		sprite.animation_finished.connect(_on_animation_finished)
	
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack"); InputMap.action_add_event("attack", InputEventMouseButton.new())
	if not InputMap.has_action("eject"):
		var k = InputEventKey.new(); k.keycode = KEY_SPACE
		InputMap.add_action("eject"); InputMap.action_add_event("eject", k)

	camera.top_level = true
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 10.0
	
	await get_tree().create_timer(0.5).timeout
	input_locked = false
	devenir_masque(true)

func _physics_process(delta):
	if current_state == State.MASQUE and is_instance_valid(masque_actif):
		camera.global_position = masque_actif.global_position
	else:
		camera.global_position = global_position

	if input_locked or current_state == State.MORT: return
	
	if jauge_sante: jauge_sante.value = health; jauge_sante.max_value = max_health
	if jauge_xp: jauge_xp.value = current_xp; jauge_xp.max_value = max_xp_current_level
	if label_niveau: label_niveau.text = "Niv. " + str(current_level)
	
	if groupe_vitalite:
		groupe_vitalite.visible = (current_state == State.POSSEDE or (current_state == State.MASQUE and not timer_mort.is_stopped()))
		if current_state == State.POSSEDE: jauge_vitalite.value = timer_vitalite.time_left; jauge_vitalite.max_value = timer_vitalite.wait_time
		elif current_state == State.MASQUE: jauge_vitalite.value = timer_mort.time_left; jauge_vitalite.max_value = temps_survie_masque
	
	if jauge_cooldown:
		var ratio = 0.0
		if not timer_cooldown.is_stopped(): ratio = 1.0 - (timer_cooldown.time_left / timer_cooldown.wait_time)
		else: ratio = 1.0
		jauge_cooldown.value = ratio * 100

	if current_state == State.MASQUE: update_visual_target_and_indicators()
	else: reset_all_enemy_tints(); update_enemies_red_dots_only(); visual_target = null; queue_redraw()

	match current_state:
		State.MASQUE:
			velocity = Vector2.ZERO
			move_and_slide()
			if Input.is_action_just_pressed("eject") and timer_cooldown.is_stopped():
				gestion_action_masque()

		State.POSSEDE:
			if is_control_locked:
				_run_parasite_ai(delta)
				move_and_slide()
				if Input.is_action_just_pressed("eject"):
					if not timer_cooldown.is_stopped(): print("Attente...")
					elif timer_vitalite.time_left < (timer_vitalite.wait_time - 0.5): ejecter_masque(false)
				return 

			if is_attacking: velocity = Vector2.ZERO; move_and_slide(); return 
			
			var direction = Input.get_vector("gauche", "droite", "haut", "bas")
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
			if Input.is_action_just_pressed("eject"):
				if not timer_cooldown.is_stopped(): print("Attente...")
				elif timer_vitalite.time_left < (timer_vitalite.wait_time - 0.5): ejecter_masque(false)

func _run_parasite_ai(delta):
	if not is_instance_valid(parasite_target):
		parasite_target = _find_nearest_enemy_for_parasite()
		parasite_state = 0 
	else:
		if "current_state" in parasite_target and parasite_target.current_state == 4:
			parasite_target = null; return

	if is_instance_valid(parasite_target):
		var dist = global_position.distance_to(parasite_target.global_position)
		if dist <= attack_range_actuelle and can_attack: parasite_state = 2
		else: parasite_state = 1
	else: parasite_state = 0

	if parasite_state == 2:
		velocity = Vector2.ZERO
		lancer_attaque_joueur()
	elif parasite_state == 1:
		if is_instance_valid(parasite_target):
			parasite_nav_agent.target_position = parasite_target.global_position
			var next = parasite_nav_agent.get_next_path_position()
			var dir = global_position.direction_to(next)
			velocity = dir * speed
			sprite.play("walk"); sprite.flip_h = dir.x < 0
	elif parasite_state == 0:
		parasite_wander_timer -= delta
		if parasite_wander_timer <= 0:
			parasite_wander_timer = randf_range(1.0, 3.0)
			var random_offset = Vector2.RIGHT.rotated(randf() * TAU) * 100
			parasite_nav_agent.target_position = global_position + random_offset
		if parasite_nav_agent.is_navigation_finished():
			velocity = Vector2.ZERO; sprite.play("idle")
		else:
			var next = parasite_nav_agent.get_next_path_position()
			var dir = global_position.direction_to(next)
			velocity = dir * speed
			sprite.play("walk"); sprite.flip_h = dir.x < 0

func _find_nearest_enemy_for_parasite():
	var mobs = get_tree().get_nodes_in_group("ennemi")
	var nearest = null; var min_dist = 400.0
	for m in mobs:
		if m == self: continue
		if "current_state" in m and m.current_state == 4: continue
		var is_enemy = false
		if "espece" in m and m.espece != self.espece_actuelle: is_enemy = true
		if is_enemy:
			var d = global_position.distance_to(m.global_position)
			if d < min_dist: min_dist = d; nearest = m
	return nearest

func gestion_action_masque():
	if premiere_apparition:
		tirer_projectile_vers(get_global_mouse_position(), distance_premier_saut, null)
	else:
		if is_instance_valid(visual_target):
			tirer_projectile_vers(visual_target.global_position, ejection_range_actuelle, null)
		else:
			print("Pas de cible à portée !")

func tirer_projectile_vers(target_pos, max_dist_override, corps_a_ignorer):
	if current_xp >= xp_cost_possession: current_xp -= xp_cost_possession
	
	var masque = masque_scene.instantiate()
	var dir = (target_pos - global_position).normalized()
	var dist_reelle = global_position.distance_to(target_pos)
	var final_dist = min(dist_reelle + 10, max_dist_override) 
	
	masque.distance_max = final_dist
	masque.vitesse = 450
	masque.global_position = global_position + (dir * 20)
	masque.look_at(global_position + dir * 100)
	masque.player_ref = self
	masque.corps_a_ignorer = corps_a_ignorer
	
	get_parent().add_child(masque)
	
	masque_actif = masque
	visible = false
	collision_shape.set_deferred("disabled", true)
	timer_vitalite.stop()
	current_state = State.MASQUE
	if timer_cooldown: timer_cooldown.start()

func ejecter_masque(corps_est_mort: bool):
	if current_state == State.MORT: return
	
	var mob_lache = null
	
	if not corps_est_mort and host_scene_path != "":
		var scene = load(host_scene_path)
		if scene:
			var mob = scene.instantiate()
			mob.global_position = global_position
			mob.health = health
			var temps_restant = timer_vitalite.time_left
			if is_control_locked: temps_restant = temps_restant / 2.0
			mob.current_vitality_time = temps_restant
			get_parent().add_child(mob)
			mob_lache = mob
	
	if not corps_est_mort:
		tirer_projectile_vers(get_global_mouse_position(), ejection_range_actuelle, mob_lache)
	else:
		rater_possession(global_position)

func reussir_possession(nouvel_hote):
	visible = true
	collision_shape.set_deferred("disabled", false)
	timer_mort.stop()
	current_state = State.POSSEDE
	premiere_apparition = false
	global_position = nouvel_hote.global_position
	
	health = nouvel_hote.health
	max_health = nouvel_hote.max_health
	speed = nouvel_hote.speed
	damage = nouvel_hote.damage
	attack_cooldown = nouvel_hote.attack_cooldown
	ejection_range_actuelle = nouvel_hote.ejection_range
	espece_actuelle = nouvel_hote.espece
	attack_range_actuelle = nouvel_hote.attack_range
	var duree_base = nouvel_hote.max_vitality_duration
	
	if "current_vitality_time" in nouvel_hote and nouvel_hote.current_vitality_time > 0:
		duree_base = nouvel_hote.current_vitality_time
	
	# --- FIX BUG CONTROLE BLOQUÉ ---
	if "niveau_requis" in nouvel_hote and current_level < nouvel_hote.niveau_requis:
		is_control_locked = true
		duree_base = duree_base * 2.0
		sprite.modulate = Color(0.7, 0.7, 0.7, 1.0)
	else:
		is_control_locked = false # ON DÉBLOQUE SI NIVEAU OK
		sprite.modulate = Color.WHITE

	if nouvel_hote.scene_file_path: host_scene_path = nouvel_hote.scene_file_path
	var ennemi_sprite = nouvel_hote.get_node("AnimatedSprite2D")
	sprite.sprite_frames = ennemi_sprite.sprite_frames
	sprite.scale = ennemi_sprite.scale
	if ennemi_sprite.offset: sprite.offset = ennemi_sprite.offset
	
	nouvel_hote.queue_free()
	timer_vitalite.start(duree_base)

func _draw():
	if current_state == State.MASQUE:
		var alpha = 0.2 + (sin(Time.get_ticks_msec() * 0.005) * 0.1)
		draw_circle(Vector2.ZERO, rayon_possession_survie, Color(0.2, 0.6, 1.0, alpha), true)
		draw_circle(Vector2.ZERO, rayon_possession_survie, Color(0.2, 0.6, 1.0, 0.5), false, 1.0)

func update_visual_target_and_indicators():
	var ennemis = get_tree().get_nodes_in_group("ennemi")
	var plus_proche = null
	var d_min = rayon_possession_survie
	for e in ennemis:
		e.modulate = Color.WHITE
		if e.has_method("update_visual_indicator"): e.update_visual_indicator(current_level)
		if "current_state" in e and e.current_state == 4: continue
		var d = global_position.distance_to(e.global_position)
		if d < d_min: d_min = d; plus_proche = e
	visual_target = plus_proche
	if visual_target: visual_target.modulate = Color(0.4, 0.7, 1.0)
	queue_redraw()

func reset_all_enemy_tints():
	var ennemis = get_tree().get_nodes_in_group("ennemi")
	for e in ennemis: e.modulate = Color.WHITE

func update_enemies_red_dots_only():
	var ennemis = get_tree().get_nodes_in_group("ennemi")
	for e in ennemis:
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
	if "attack" in sprite.animation:
		var ennemis = get_tree().get_nodes_in_group("ennemi")
		for e in ennemis:
			var is_enemy = false
			if "espece" in e and e.espece != self.espece_actuelle: is_enemy = true
			
			# TRAHISON POSSIBLE : Si c'est ma propre espèce, je peux quand même taper
			# Pour autoriser le Friendly Fire du joueur : On vérifie juste la distance
			if global_position.distance_to(e.global_position) < 50:
				if e.has_method("take_damage"): e.take_damage(damage, self)
		
		sprite.play("idle")
		is_attacking = false
		await get_tree().create_timer(attack_cooldown).timeout
		can_attack = true

func take_damage(amount, attacker = null):
	if is_dying or health <= 0: return
	health -= amount
	sprite.modulate = Color.RED
	var t = create_tween()
	t.tween_property(sprite, "modulate", Color.WHITE, 0.1)
	if health <= 0:
		if current_state == State.POSSEDE: ejecter_masque(true)
		else: mourir()

func rater_possession(pos):
	masque_actif = null
	global_position = pos
	devenir_masque(false)

func devenir_masque(is_safe):
	current_state = State.MASQUE
	espece_actuelle = "masque"
	visible = true
	collision_shape.set_deferred("disabled", false)
	health = 100.0; speed = 0
	sprite.sprite_frames = original_frames; sprite.scale = original_scale
	sprite.play("idle"); sprite.speed_scale = 1.0
	if original_shape: collision_shape.shape = original_shape
	timer_vitalite.stop()
	if is_safe: premiere_apparition = true; timer_mort.stop()
	else: premiere_apparition = false; timer_mort.start(temps_survie_masque)

func _on_vitalite_empty(): ejecter_masque(true)
func mourir():
	is_dying = true; current_state = State.MORT
	get_tree().change_scene_to_file(death_scene_path)
