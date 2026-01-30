extends CharacterBody2D

@export var speed = 150
@export var ping_interval = 1.2 # Temps (en secondes) entre chaque ping.
@onready var sonar = $Sonar

var ping_timer = 0.0 # Compteur interne

func _ready():
	sonar.energy = 0
	ping_timer = ping_interval

func _physics_process(delta):
	var direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	if direction:
		velocity = direction * speed
		
		ping_timer += delta
		
		if ping_timer >= ping_interval:
			trigger_ping()
			ping_timer = 0.0
			

	move_and_slide()

# Fonction pour gérer l'animation du flash
func trigger_ping():
	var tween = create_tween()
	
	tween.set_parallel(true)
	tween.tween_property(sonar, "energy", 2.0, 0.1) # Monte à 2.0 en 0.1 seconde
	tween.tween_property(sonar, "texture_scale", 1.5, 0.1) # Grandit à 1.5x
	
	tween.chain().tween_property(sonar, "energy", 0.0, 0.6) # Redescend à 0 en 0.6 seconde
