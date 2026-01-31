extends CharacterBody2D

@export var speed = 60 
@export var detection_range = 200 

var player = null
@onready var sprite = $AnimatedSprite2D 

func _ready():
	#Au démarrage on essaye de trouver le joueur
	player = get_tree().get_first_node_in_group("player")

func _physics_process(delta):
	#Si le joueur existe
	if player:
		var distance = global_position.distance_to(player.global_position)
		# Si le joueur est trop proche
		if distance < detection_range:
			var direction = (player.global_position - global_position).normalized()
			velocity = direction * speed
			if direction.x < 0:
				sprite.flip_h = true
			else:
				sprite.flip_h = false
		else:
			velocity = Vector2.ZERO
		#Changement d'animation
		if velocity.length() > 0:
			sprite.play("walk")
		else:
			sprite.play("idle")

		move_and_slide()
