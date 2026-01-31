extends CharacterBody2D

@export var speed = 60
@export var vision_range = 200

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
	# On cherche le joueur
	player = get_tree().get_first_node_in_group("player")
	
	# Réglage du pathfindingqs
	nav_agent.path_desired_distance = 4.0
	nav_agent.target_desired_distance = 4.0
	
	# Configuration du Timer
	timer_memoire.timeout.connect(_on_memory_timeout)
	raycast.add_exception(self)

func _physics_process(delta):
	if !player: return
	
	#GESTION DE LA VUE (Raycast)
	var distance = global_position.distance_to(player.global_position)
	var can_see_player = false
	var cible_visuelle = player.global_position + Vector2(0, -15)
	# On pointe le laser vers le joueur
	raycast.target_position = to_local(cible_visuelle)
	raycast.force_raycast_update()
	
	# SI le joueur est assez près ET que le laser ne touche PAS de mur
	if distance < vision_range and not raycast.is_colliding():
		can_see_player = true
	
	#Changement d'état
	if can_see_player:
		current_state = State.CHASE
		timer_memoire.stop()
		last_known_position = player.global_position
	elif current_state == State.CHASE and !can_see_player:
		# On pert le joueur de vue !
		current_state = State.SEARCH
		timer_memoire.start() # On lance le chrono de 5 secondes
		print("Je t'ai perdu ! Je cherche encore 5s...")

	#MOUVEMENT
	match current_state:
		State.IDLE:
			velocity = Vector2.ZERO
			sprite.play("idle")
			
		State.CHASE, State.SEARCH:
			# Si on chasse ou cherche, on va vers la cible
			nav_agent.target_position = last_known_position
			
			if nav_agent.is_navigation_finished():
				velocity = Vector2.ZERO
				sprite.play("idle")
			else:
				# C'est ici que le pathfinding opère
				var next_path_pos = nav_agent.get_next_path_position()
				var direction = global_position.direction_to(next_path_pos)
				velocity = direction * speed
				sprite.play("walk")
				
				# Gestion Flip
				if velocity.x < 0: sprite.flip_h = true
				elif velocity.x > 0: sprite.flip_h = false

	move_and_slide()

# Quand les 5 secondes sont finies
func _on_memory_timeout():
	print("Bon, il est parti. J'arrête.")
	current_state = State.IDLE
