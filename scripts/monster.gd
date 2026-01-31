extends CharacterBody2D

@export var speed = 60
@export var vision_range = 70
@export var attack_range = 25
@export var attack_cooldown = 1.0

@export var attack_animations_list: Array[String] = ["attack1", "attack2"]

enum State { IDLE, CHASE, SEARCH, ATTACK, COOLDOWN }
var current_state = State.IDLE

var player = null
var last_known_position = Vector2.ZERO
var can_attack = true

@onready var sprite = $AnimatedSprite2D
@onready var nav_agent = $NavigationAgent2D
@onready var raycast = $RayCast2D
@onready var timer_memoire = $Timer

func _ready():
	player = get_tree().get_first_node_in_group("player")
	
	nav_agent.path_desired_distance = 20.0
	nav_agent.target_desired_distance = 20.0
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	timer_memoire.timeout.connect(_on_memory_timeout)
	sprite.animation_finished.connect(_on_animation_finished)
	
	call_deferred("actor_setup")
	
	# Petit check de sécurité
	if attack_animations_list.is_empty():
		push_error("Attention ! Tu n'as pas mis de noms d'attaque dans la liste 'attack_animations_list' de l'Inspecteur")

func actor_setup():
	await get_tree().physics_frame

func _physics_process(delta):
	if !player: return
	
	# --- A. VISION ---
	# (Code inchangé...)
	var distance = global_position.distance_to(player.global_position)
	var can_see_player = false
	var cible_coeur = player.global_position + Vector2(0, -10)
	raycast.target_position = raycast.to_local(cible_coeur)
	raycast.force_raycast_update()
	
	if distance < vision_range:
		if raycast.is_colliding():
			if raycast.get_collider() == player:
				can_see_player = true
		else:
			can_see_player = true
	
	# --- B. TRANSITIONS ---
	
	if current_state == State.ATTACK:
		pass # On attend que l'animation finisse
		
	elif can_see_player:
		# <--- NOUVEAU : Si on peut attaquer, on appelle la nouvelle fonction
		if distance < attack_range and can_attack:
			lancer_une_attaque()
			
		elif distance >= attack_range:
			current_state = State.CHASE
			
		timer_memoire.stop()
		last_known_position = player.global_position
		
	elif current_state == State.CHASE and !can_see_player:
		current_state = State.SEARCH
		timer_memoire.start()

	# --- C. MOUVEMENT CONTINU ---
	var velocity_desiree = Vector2.ZERO
	
	match current_state:
		State.IDLE:
			velocity_desiree = Vector2.ZERO
			sprite.play("idle")
		
		State.ATTACK:
			# <--- IMPORTANT : On ne lance plus sprite.play() ici ! 
			# C'est déjà fait dans "lancer_une_attaque()"
			velocity_desiree = Vector2.ZERO
			
			# On continue juste de regarder vers le joueur pendant l'attaque
			if player:
				var direction = (player.global_position - global_position).normalized()
				if direction.x < -0.1: sprite.flip_h = true
				elif direction.x > 0.1: sprite.flip_h = false
		
		State.CHASE, State.SEARCH:
			# (Code mouvement inchangé...)
			nav_agent.target_position = last_known_position
			if nav_agent.is_navigation_finished():
				velocity_desiree = Vector2.ZERO
				sprite.play("idle")
			else:
				var next_path_pos = nav_agent.get_next_path_position()
				var direction = global_position.direction_to(next_path_pos)
				velocity_desiree = direction * speed
				sprite.play("walk")
				if velocity.x < -0.1: sprite.flip_h = true
				elif velocity.x > 0.1: sprite.flip_h = false
		
	if nav_agent.avoidance_enabled:
		nav_agent.set_velocity(velocity_desiree)
	else:
		velocity = velocity_desiree
		move_and_slide()

# --- NOUVELLE FONCTION POUR CHOISIR L'ATTAQUE ---
func lancer_une_attaque():
	if attack_animations_list.size() == 0: return

	current_state = State.ATTACK
	can_attack = false # On verrouille tout de suite
	velocity = Vector2.ZERO # Stop net
	
	# 1. Choisir un index au hasard dans la liste
	var random_index = randi() % attack_animations_list.size()
	# 2. Récupérer le nom de l'animation
	var attaque_choisie = attack_animations_list[random_index]
	
	print("Orc choisit l'attaque : ", attaque_choisie)
	
	# 3. Jouer l'animation choisie (UNE SEULE FOIS)
	sprite.play(attaque_choisie)


# --- D. LOGIQUE DE FIN D'ATTAQUE ---

func _on_animation_finished():
	# <--- NOUVEAU : On vérifie si l'animation qui vient de finir est DANS notre liste d'attaques
	# L'opérateur "in" est très pratique pour ça !
	if sprite.animation in attack_animations_list:
		
		# 1. Appliquer les dégâts
		if player:
			var distance = global_position.distance_to(player.global_position)
			if distance < attack_range + 10: 
				print("Dégâts infligés avec ", sprite.animation)
				# player.take_damage(10) 
		
		# 2. Retour au calme et Cooldown
		current_state = State.IDLE
		sprite.play("idle")
		
		await get_tree().create_timer(attack_cooldown).timeout
		
		can_attack = true
		print("Cooldown fini.")

func _on_velocity_computed(safe_velocity):
	velocity = safe_velocity
	move_and_slide()

func _on_memory_timeout():
	current_state = State.IDLE
