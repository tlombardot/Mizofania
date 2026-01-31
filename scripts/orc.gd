extends CharacterBody2D

@export var speed = 60
@export var vision_range = 250
@export var espece = "orc" # <--- AJOUT : L'espèce de cet ennemi

# États de l'ennemi
enum State { IDLE, CHASE, SEARCH }
var current_state = State.IDLE

var player = null
var last_known_position = Vector2.ZERO

@onready var sprite = $AnimatedSprite2D
@onready var nav_agent = $NavigationAgent2D
@onready var raycast = $RayCast2D
@onready var timer_memoire = $Timer

func _ready():
	# 1. On récupère le joueur
	player = get_tree().get_first_node_in_group("player")
	
	# 2. On configure l'Agent de Navigation
	nav_agent.path_desired_distance = 20.0
	nav_agent.target_desired_distance = 20.0
	
	# IMPORTANT POUR L'ÉVITEMENT
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	
	# 3. Réglages divers
	timer_memoire.timeout.connect(_on_memory_timeout)
	
	call_deferred("actor_setup")

func actor_setup():
	await get_tree().physics_frame

func _physics_process(delta):
	if !player: return
	
	# --- A. VISION (SNIPER & FACTION) ---
	var distance = global_position.distance_to(player.global_position)
	var can_see_player = false
	var is_enemy = true # Par défaut, on considère que c'est un ennemi
	
	# 0. VÉRIFICATION DE L'ESPÈCE (Le joueur est-il un allié ?)
	# On vérifie si le joueur a la variable 'espece_actuelle' et si c'est la même que nous
	if "espece_actuelle" in player:
		if player.espece_actuelle == self.espece:
			is_enemy = false # C'est un copain !
	
	# Si c'est un copain, on arrête la vision ici (pas besoin de calculer le reste)
	if not is_enemy:
		current_state = State.IDLE # On force le repos
		# (Note : Si tu veux qu'il patrouille, mets ta logique de patrouille ici)
	
	# SINON (Si c'est un ennemi), on lance la détection visuelle
	else:
		var cible_coeur = player.global_position + Vector2(0, -10)
		raycast.target_position = raycast.to_local(cible_coeur)
		raycast.force_raycast_update()
		
		if distance < vision_range:
			# Si le Raycast tape le joueur
			if raycast.is_colliding():
				if raycast.get_collider() == player:
					can_see_player = true
			# Si le Raycast ne touche rien (donc pas de mur)
			else:
				can_see_player = true
	
	# --- B. CERVEAU (Changement d'état) ---
	if can_see_player:
		current_state = State.CHASE
		timer_memoire.stop()
		last_known_position = player.global_position
	elif current_state == State.CHASE and !can_see_player:
		current_state = State.SEARCH
		timer_memoire.start()
		print("Je t'ai perdu ! Je cherche...")

	# --- C. CALCUL DU MOUVEMENT ---
	var velocity_desiree = Vector2.ZERO
	
	match current_state:
		State.IDLE:
			velocity_desiree = Vector2.ZERO
			sprite.play("idle")
			
		State.CHASE, State.SEARCH:
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

	# --- D. APPLICATION DE L'ÉVITEMENT ---
	if nav_agent.avoidance_enabled:
		nav_agent.set_velocity(velocity_desiree)
	else:
		velocity = velocity_desiree
		move_and_slide()

# --- E. LE RÉSULTAT DE L'ÉVITEMENT ---
func _on_velocity_computed(safe_velocity):
	velocity = safe_velocity
	move_and_slide()

func _on_memory_timeout():
	print("Abandon.")
	current_state = State.IDLE
