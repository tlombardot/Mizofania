extends CharacterBody2D

@export var speed = 150

func _physics_process(delta):
	var direction = Input.get_vector("gauche", "droite", "haut", "bas")
	
	if direction:
		velocity = direction * speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()
