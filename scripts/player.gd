extends CharacterBody2D

enum State { MASQUE, POSSEDE }
var current_state = State.MASQUE

@export var speed = 150
@export var rayon_possession_proche = 3 * 16 
@export var temps_survie_masque = 10.0 
@export var duree_possession_max = 30.0 
@export var max_health = 100.0

var health = 100.0
var espece_actuelle = "masque"
var premiere_apparition = true
var masque_actif = null

@onready var sprite = $AnimatedSprite2D
@onready var jauge_vitalite = $Vitalite/JaugeVitalite
@onready var jauge_sante = $Sante/JaugeSante
@onready var timer_vitalite = $TimerPossession
@onready var timer_mort = $DeathTimer
@onready var collision_shape = $CollisionShape2D
@onready var camera = $Camera2D

var masque_scene = preload("res://scenes/masque_projectile.tscn")

var original_frames = null
var original_scale = Vector2.ONE
var original_offset = Vector2.ZERO
var original_centered = false
var original_sprite_pos = Vector2.ZERO
var original_shape = null        
var original_col_pos = Vector2.ZERO
var original_col_scale = Vector2.ONE

func _ready():
	health = max_health
	jauge_sante.max_value = max_health
	jauge_sante.value = health

	original_frames = sprite.sprite_frames
	original_scale = sprite.scale
	original_offset = sprite.offset
	original_centered = sprite.centered
	original_sprite_pos = sprite.position
	
	if collision_shape.shape:
		original_shape = collision_shape.shape.duplicate()
		original_col_pos = collision_shape.position
		original_col_scale = collision_shape.scale
	
	timer_vitalite.one_shot = true
	timer_mort.one_shot = true
	
	if not timer_vitalite.timeout.is_connected(mourir):
		timer_vitalite.timeout.connect(mourir)
	if not timer_mort.timeout.is_connected(mourir):
		timer_mort.timeout.connect(mourir)
	
	devenir_masque(true)

func _physics_process(delta):
	jauge_sante.value = health
	
	if current_state == State.POSSEDE:
		jauge_vitalite.visible = true
		jauge_vitalite.max_value = timer_vitalite.wait_time
		jauge_vitalite.value = timer_vitalite.time_left
	else:
		jauge_vitalite.visible = false

	if current_state == State.MASQUE and is_instance_valid(masque_actif):
		camera.global_position = masque_actif.global_position

	match current_state:
		State.MASQUE:
			velocity = Vector2.ZERO
			move_and_slide()
			if Input.is_action_just_pressed("ui_accept"):
				tenter_possession_proximite()

		State.POSSEDE:
			var direction = Input.get_vector("gauche", "droite", "haut", "bas")
			if direction:
				velocity = direction * speed
				sprite.flip_h = direction.x < 0
				sprite.play("walk")
			else:
				velocity = Vector2.ZERO
				sprite.play("idle")
			move_and_slide()
			
			if Input.is_action_just_pressed("ui_accept") and timer_vitalite.time_left < (duree_possession_max - 0.5):
				ejecter_masque()

func take_damage(amount):
	health -= amount
	sprite.modulate = Color.RED
	await get_tree().create_timer(0.1).timeout
	sprite.modulate = Color.WHITE
	if health <= 0:
		mourir()

func tenter_possession_proximite():
	var ennemis = get_tree().get_nodes_in_group("ennemi")
	var plus_proche = null
	var distance_min = rayon_possession_proche
	for ennemi in ennemis:
		var dist = global_position.distance_to(ennemi.global_position)
		if dist < distance_min:
			distance_min = dist
			plus_proche = ennemi
	if plus_proche:
		reussir_possession(plus_proche)

func reussir_possession(nouvel_hote):
	visible = true
	collision_shape.set_deferred("disabled", false)
	timer_mort.stop()
	current_state = State.POSSEDE
	premiere_apparition = false
	global_position = nouvel_hote.global_position
	
	var ennemi_sprite = nouvel_hote.get_node("AnimatedSprite2D")
	sprite.sprite_frames = ennemi_sprite.sprite_frames
	sprite.position = ennemi_sprite.position
	sprite.scale = ennemi_sprite.scale
	sprite.centered = ennemi_sprite.centered
	sprite.offset = ennemi_sprite.offset
	
	var ennemi_shape_node = nouvel_hote.get_node("CollisionShape2D")
	if ennemi_shape_node:
		collision_shape.shape = ennemi_shape_node.shape.duplicate()
		collision_shape.position = ennemi_shape_node.position
		collision_shape.scale = ennemi_shape_node.scale

	if "espece" in nouvel_hote:
		espece_actuelle = nouvel_hote.espece
	
	masque_actif = null
	camera.top_level = false
	camera.position = Vector2.ZERO
	
	nouvel_hote.queue_free()
	timer_vitalite.start(duree_possession_max)

func ejecter_masque():
	var masque = masque_scene.instantiate()
	masque.global_position = global_position + sprite.position + Vector2(0, -10)
	masque.look_at(get_global_mouse_position())
	masque.player_ref = self 
	get_parent().add_child(masque)
	
	masque_actif = masque
	camera.top_level = true
	visible = false
	collision_shape.set_deferred("disabled", true)
	timer_vitalite.stop()
	current_state = State.MASQUE

func rater_possession(position_crash):
	masque_actif = null
	camera.top_level = false
	camera.position = Vector2.ZERO
	global_position = position_crash
	devenir_masque(false)

func devenir_masque(is_safe_start):
	current_state = State.MASQUE
	espece_actuelle = "masque"
	visible = true
	collision_shape.set_deferred("disabled", false)
	sprite.sprite_frames = original_frames
	sprite.scale = original_scale
	sprite.position = original_sprite_pos
	sprite.play("default")
	
	if original_shape:
		collision_shape.shape = original_shape
		collision_shape.position = original_col_pos
	
	timer_vitalite.stop()
	if is_safe_start:
		timer_mort.stop()
	else:
		timer_mort.start(temps_survie_masque)

func mourir():
	print("💀 MORT !")
	
	# On récupère l'arbre de scène avant de faire quoi que ce soit
	var tree = get_tree()
	
	if tree:
		# On fige le processus pour éviter les erreurs multiples
		set_physics_process(false)
		
		# Petit délai pour laisser le temps de voir la mort
		# On utilise l'arbre de scène pour créer le timer
		await tree.create_timer(1.0).timeout
		
		# On recharge proprement
		tree.reload_current_scene()
	else:
		push_error("Erreur : Impossible d'accéder au SceneTree pour recharger.")
