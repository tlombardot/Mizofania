extends CharacterBody2D

@export var speed = 150
@onready var sprite = $AnimatedSprite2D
@onready var timer_possession = $TimerPossession

# --- SAUT & MOUVEMENT ---
var jump_height = 5.0
var jump_speed = 10.0
var time = 0.0
var initial_y = 0.0 

# --- VARIABLES DE TRANSFORMATION ---
var masque_scene = preload("res://scenes/masque_projectile.tscn")
var futur_corps = null 

# --- MÉMOIRE (Pour redevenir normal) ---
var original_frames = null       
var original_shape = null        
var original_scale = Vector2.ONE 
var original_col_pos = Vector2.ZERO

func _ready():
	# 1. On sauvegarde tout du joueur normal
	initial_y = sprite.position.y
	original_frames = sprite.sprite_frames
	original_scale = sprite.scale
	
	# Sauvegarde précise de la collision
	if $CollisionShape2D.shape:
		original_shape = $CollisionShape2D.shape.duplicate()
		original_col_pos = $CollisionShape2D.position

	timer_possession.timeout.connect(_on_timer_timeout)

func _physics_process(delta):
	
	#Transformation
	if futur_corps != null:
		appliquer_transformation()
		return 

	#Mouvement keybind récupèré dans les settings du projet
	var direction = Input.get_vector("gauche", "droite", "haut", "bas")
	
	if direction:
		velocity = direction * speed
		if direction.x > 0: sprite.flip_h = false
		elif direction.x < 0: sprite.flip_h = true
		
		# Animation saut
		time += delta * jump_speed
		sprite.position.y = initial_y - abs(sin(time) * jump_height)
	else:
		velocity = Vector2.ZERO
		sprite.position.y = move_toward(sprite.position.y, initial_y, delta * jump_speed)
		time = 0.0

	move_and_slide()
	
	if Input.is_action_just_pressed("ui_accept") and timer_possession.is_stopped():
		tirer_masque()

# --- FONCTIONS ---

func tirer_masque():
	var masque = masque_scene.instantiate()
	masque.global_position = global_position
	masque.look_at(get_global_mouse_position())
	masque.player_ref = self 
	get_parent().add_child(masque)

func prendre_corps(ennemi_cible):
	futur_corps = ennemi_cible

func appliquer_transformation():
	print("Transformation en cours (5 secondes)")
	
	#Téléportation du corps
	global_position = futur_corps.global_position
	
	#Copie du sprite de l'ennemi
	var ennemi_sprite = futur_corps.get_node("AnimatedSprite2D")
	
	# On copie les animations
	sprite.sprite_frames = ennemi_sprite.sprite_frames
	# On copie la position locale
	sprite.position = ennemi_sprite.position
	sprite.scale = ennemi_sprite.scale
	
	# On copie le point d'ancrage
	sprite.centered = ennemi_sprite.centered 
	sprite.offset = ennemi_sprite.offset
	
	# On copie la direction du regard
	sprite.flip_h = ennemi_sprite.flip_h

	# On cale le saut sur cette nouvelle position
	initial_y = sprite.position.y
	time = 0.0

	#COPIE DE LA COLLISION
	var ennemi_shape_node = futur_corps.get_node("CollisionShape2D")
	if ennemi_shape_node:
		$CollisionShape2D.shape = ennemi_shape_node.shape.duplicate()
		$CollisionShape2D.position = ennemi_shape_node.position
		$CollisionShape2D.scale = ennemi_shape_node.scale
	
	#Nettoyage
	futur_corps.queue_free()
	futur_corps = null
	
	#Fix de la caméra
	var cam = $Camera2D
	if cam:
		var old_smoothing = cam.position_smoothing_enabled
		cam.position_smoothing_enabled = false
		
		# On force la caméra à se mettre sur le joueur
		cam.force_update_scroll()
		
		# On attend une frame pour être sûr que l'écran a bougé
		await get_tree().process_frame
		
		# On remet le réglage d'avant
		cam.position_smoothing_enabled = old_smoothing
	
	timer_possession.start()

# --- RETOUR À LA NORMALE ---
func _on_timer_timeout():
	print("Revient à la normale")
	# On remet l'apparence
	sprite.sprite_frames = original_frames
	sprite.scale = original_scale
	sprite.offset = Vector2.ZERO
	
	#On remet la collision
	if original_shape:
		$CollisionShape2D.shape = original_shape
		$CollisionShape2D.position = original_col_pos 
		$CollisionShape2D.scale = Vector2.ONE
	
	#On remet le saut standard
	initial_y = 0.0
	sprite.position.y = initial_y
	
	velocity.y = -200
