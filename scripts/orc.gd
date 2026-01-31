extends CharacterBody2D

@export var speed = 60
@export var vision_range = 250

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
	
	# IMPORTANT POUR L'ÉVITEMENT :
	# On connecte le signal qui nous donnera la "Vitesse Sûre" (calculée pour éviter les autres)
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	
	# 3. Réglages divers
	timer_memoire.timeout.connect(_on_memory_timeout)
	
	# Petite astuce : on attend que la map soit chargée
	call_deferred("actor_setup")

func actor_setup():
	await get_tree().physics_frame

func _physics_process(delta):
	if !player: return
	
	# --- A. VISION (SNIPER) ---
	var distance = global_position.distance_to(player.global_position)
	var can_see_player = false
	
	# On vise le COEUR du joueur (-10px), pas ses pieds
	var cible_coeur = player.global_position + Vector2(0, -10)
	
	# On oriente le laser depuis les yeux de l'orc (to_local)
	raycast.target_position = raycast.to_local(cible_coeur)
	raycast.force_raycast_update()
	
	# Si on est assez près
	if distance < vision_range:
		# Si le Raycast tape le joueur (Option précise)
		if raycast.is_colliding():
			if raycast.get_collider() == player:
				can_see_player = true
		else:
			# Si le Raycast ne touche RIEN (donc pas de mur), on te voit
			# (Seulement si le joueur n'est PAS dans le mask du raycast)
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
	# Note : Ici on ne bouge pas encore ! On calcule juste où on VOUDRAIT aller.
	
	var velocity_desiree = Vector2.ZERO
	
	match current_state:
		State.IDLE:
			velocity_desiree = Vector2.ZERO
			sprite.play("idle")
			
		State.CHASE, State.SEARCH:
			# On met à jour la cible
			nav_agent.target_position = last_known_position
			
			if nav_agent.is_navigation_finished():
				velocity_desiree = Vector2.ZERO
				sprite.play("idle")
			else:
				var next_path_pos = nav_agent.get_next_path_position()
				var direction = global_position.direction_to(next_path_pos)
				
				# C'est ici qu'on définit la vitesse qu'on VEUT avoir
				velocity_desiree = direction * speed
				
				sprite.play("walk")
				
				# Gestion du regard (Flip)
				if velocity.x < -0.1: sprite.flip_h = true
				elif velocity.x > 0.1: sprite.flip_h = false

	# --- D. APPLICATION DE L'ÉVITEMENT ---
	if nav_agent.avoidance_enabled:
		# Si l'évitement est activé, on envoie notre souhait à l'agent
		# Il va réfléchir et nous renvoyer la réponse dans "_on_velocity_computed"
		nav_agent.set_velocity(velocity_desiree)
	else:
		# Si pas d'évitement, on bouge comme un bourrin (ancienne méthode)
		velocity = velocity_desiree
		move_and_slide()

# --- E. LE RÉSULTAT DE L'ÉVITEMENT ---
# Cette fonction est appelée automatiquement par Godot quand il a fini de calculer
func _on_velocity_computed(safe_velocity):
	# "safe_velocity" c'est la vitesse corrigée pour ne pas taper les copains
	velocity = safe_velocity
	move_and_slide()

func _on_memory_timeout():
	print("Abandon.")
	current_state = State.IDLE
