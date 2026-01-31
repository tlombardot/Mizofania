extends CharacterBody2D
class_name Monster

# --- PARAMÈTRES ---
@export var speed = 60
@export var vision_range = 200
@export var attack_range = 25
@export var attack_cooldown = 1.0
@export var damage = 15 # <--- NOUVEAU : Dégâts infligés
@export var attack_animations_list: Array[String] = ["attack1", "attack2"]
@export var espece = "orc"

# --- ÉTATS ---
enum State { IDLE, CHASE, SEARCH, ATTACK, WANDER } # <--- Ajout de WANDER
var current_state = State.IDLE

var player = null
var last_known_position = Vector2.ZERO
var can_attack = true
var wander_target = Vector2.ZERO # Pour la promenade

@onready var sprite = $AnimatedSprite2D
@onready var nav_agent = $NavigationAgent2D
@onready var raycast = $RayCast2D
@onready var timer_memoire = $Timer
@onready var timer_wander = Timer.new() # Timer interne pour changer de direction

func _ready():
	player = get_tree().get_first_node_in_group("player")
	
	nav_agent.path_desired_distance = 20.0
	nav_agent.target_desired_distance = 20.0
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	
	timer_memoire.timeout.connect(_on_memory_timeout)
	
	# Configuration du timer de promenade
	add_child(timer_wander)
	timer_wander.wait_time = 3.0
	timer_wander.one_shot = true
	timer_wander.timeout.connect(_on_wander_timeout)
	
	if not sprite.animation_finished.is_connected(_on_animation_finished):
		sprite.animation_finished.connect(_on_animation_finished)
	
	call_deferred("actor_setup")

func actor_setup():
	await get_tree().physics_frame

func _physics_process(delta):
	# Si pas de joueur ou jeu fini
	if !player: return

	# 1. GESTION DE FACTION (Allié ou Ennemi ?)
	if not _check_faction():
		# Si on est ami, on se balade au lieu de rester figé
		if current_state != State.WANDER:
			enter_wander_state()
		
		# Logique de promenade (Wander)
		if current_state == State.WANDER:
			nav_agent.target_position = wander_target
			if not nav_agent.is_navigation_finished():
				var next = nav_agent.get_next_path_position()
				var dir = global_position.direction_to(next)
				
				# Petite vitesse de promenade (50% de la vitesse max)
				var wander_speed = speed * 0.5 
				velocity = dir * wander_speed
				
				sprite.play("walk")
				if velocity.x < -0.1: sprite.flip_h = true
				elif velocity.x > 0.1: sprite.flip_h = false
				
				move_and_slide()
			else:
				sprite.play("idle")
				velocity = Vector2.ZERO
		return

	# 2. LOGIQUE ENNEMIE (Si on est hostile)
	
	# Vision
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
	
	# Transitions Ennemi
	if current_state == State.ATTACK:
		pass # Bloqué par l'anim
		
	elif can_see_player:
		if distance < attack_range and can_attack:
			lancer_une_attaque()
		elif distance >= attack_range:
			current_state = State.CHASE
		
		timer_memoire.stop()
		last_known_position = player.global_position
		
	elif current_state == State.CHASE and !can_see_player:
		current_state = State.SEARCH
		timer_memoire.start()
	
	elif current_state == State.IDLE:
		# Si on était en IDLE hostile, on peut aussi patrouiller un peu (optionnel)
		velocity = Vector2.ZERO

	# Mouvement Ennemi (Chasse)
	var velocity_desiree = Vector2.ZERO
	
	match current_state:
		State.ATTACK:
			velocity_desiree = Vector2.ZERO
			if player:
				var dir = (player.global_position - global_position).normalized()
				if dir.x < -0.1: sprite.flip_h = true
				elif dir.x > 0.1: sprite.flip_h = false

		State.CHASE, State.SEARCH:
			nav_agent.target_position = last_known_position
			if not nav_agent.is_navigation_finished():
				var next = nav_agent.get_next_path_position()
				var dir = global_position.direction_to(next)
				velocity_desiree = dir * speed
				sprite.play("walk")
				if velocity.x < -0.1: sprite.flip_h = true
				elif velocity.x > 0.1: sprite.flip_h = false
			else:
				sprite.play("idle")
	
	# Application Evitement
	if current_state != State.WANDER: # WANDER gère son propre move_and_slide pour être fluide
		if nav_agent.avoidance_enabled:
			nav_agent.set_velocity(velocity_desiree)
		else:
			velocity = velocity_desiree
			move_and_slide()

# --- LOGIQUE PROMENADE ---
func enter_wander_state():
	current_state = State.WANDER
	_pick_random_wander_target()
	timer_wander.start(randf_range(2.0, 5.0)) # Change de direction toutes les 2-5 sec

func _pick_random_wander_target():
	# Choisit un point au hasard autour de lui (rayon de 100px)
	var random_offset = Vector2(randf_range(-100, 100), randf_range(-100, 100))
	wander_target = global_position + random_offset

func _on_wander_timeout():
	if current_state == State.WANDER:
		# On choisit une nouvelle destination ou on fait une pause
		if randf() > 0.5:
			_pick_random_wander_target()
		else:
			# Petite pause sur place
			wander_target = global_position 
		
		timer_wander.start(randf_range(2.0, 5.0))

# --- LOGIQUE COMBAT ---

func _check_faction() -> bool:
	if "espece_actuelle" in player:
		if player.espece_actuelle == self.espece:
			return false
	return true

func lancer_une_attaque():
	if attack_animations_list.size() == 0: return

	current_state = State.ATTACK
	can_attack = false
	velocity = Vector2.ZERO
	
	var idx = randi() % attack_animations_list.size()
	sprite.play(attack_animations_list[idx])

func _on_animation_finished():
	if sprite.animation in attack_animations_list:
		# --- MODIFICATION DÉGÂTS RÉELS ---
		if player and global_position.distance_to(player.global_position) < attack_range + 15:
			# On vérifie si le joueur a la méthode take_damage
			if player.has_method("take_damage"):
				player.take_damage(damage)
			else:
				print("Erreur : Le joueur n'a pas de fonction take_damage()")
		
		current_state = State.IDLE
		sprite.play("idle")
		
		await get_tree().create_timer(attack_cooldown).timeout
		can_attack = true

func _on_velocity_computed(safe_velocity):
	if current_state != State.WANDER: # On laisse le WANDER gérer son mouvement cool
		velocity = safe_velocity
		move_and_slide()

func _on_memory_timeout():
	# Si on perd le joueur, on peut se remettre à errer
	enter_wander_state()
