extends Marker2D


# "PackedScene", c'est le type de variable pour stocker un fichier .tscn
@export var monstre_scene: PackedScene 

# Options pour personnaliser chaque spawner
@export var temps_spawn = 3.0
@export var rayon_spawn = 0 # Pour le spawn un peu plus aléatoir autour du spawner
@export var max_monstres = 5 # Max monstre spawn
@export var monstre_parent_node_name = "Ennemis"

var monstres_actuels = 0

@onready var timer = $Timer

func _ready():
	# Applique le temps choisi
	timer.wait_time = temps_spawn
	timer.timeout.connect(_on_timer_timeout)
	
	# Check si il y a un monstre
	if monstre_scene == null:
		push_error("Pas de monstre dans le spawner !")
		timer.stop()

func _on_timer_timeout():
	spawn_monstre()

func spawn_monstre():
	# Si max monstre on spawn plus rien
	if monstres_actuels >= max_monstres:
		return
		
	if monstre_scene:
		# On crée le monstre
		var monstre = monstre_scene.instantiate()
		
		# On choisit sa position
		# Si rayon_spawn est > 0, on décale un peu aléatoirement
		var decalage = Vector2.ZERO
		if rayon_spawn > 0:
			decalage = Vector2(randf_range(-rayon_spawn, rayon_spawn), randf_range(-rayon_spawn, rayon_spawn))
		
		monstre.global_position = global_position + decalage
		
		# On l'ajoute au monde
		get_parent().add_child(monstre)
		
		#On connecte le signal de mort pour décrémenter le compteur
		#Le monstre doit émettre un signal "tree_exited" quand il meurt
		monstre.tree_exited.connect(_on_monstre_mort)
		monstres_actuels += 1

func _on_monstre_mort():
	monstres_actuels -= 1
	if monstres_actuels < 0: monstres_actuels = 0
