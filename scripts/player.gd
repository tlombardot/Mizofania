extends CharacterBody2D

@export var speed = 150
@onready var sprite = $AnimatedSprite2D

# --- PARAMÈTRES DU SAUT ---
var jump_height = 2.0 
var jump_speed = 7.0  
var time = 0.0

var initial_y = 0.0

func _ready():
	initial_y = sprite.position.y

func _physics_process(delta):
	#Récupèrer les touches préconfigurer dans le projet
	var direction = Input.get_vector("gauche", "droite", "haut", "bas")
	
	#Si les touches récupèrer
	if direction:
		velocity = direction * speed
		
		#Changement de direction Gauche/Droite
		if direction.x > 0:
			sprite.flip_h = false
		elif direction.x < 0:
			sprite.flip_h =true
		
		#On fait sauter le personnage pour une meilleur animation	
		time += delta * jump_speed
		sprite.position.y = initial_y - abs(sin(time) * jump_height)
	else:
		velocity = Vector2.ZERO
		#On reset le saut pour le prochain dès qu'il rebouge
		sprite.position.y = move_toward(sprite.position.y, initial_y, delta * jump_speed)
		time = 0.0

	move_and_slide()
