extends Area2D

var vitesse = 400
var distance_max = 5 * 16 
var distance_parcourue = 0.0
var player_ref = null

func _physics_process(delta):
	var deplacement = vitesse * delta
	position += transform.x * deplacement
	distance_parcourue += deplacement
	
	if distance_parcourue >= distance_max:
		print("Trop loin, raté !")
		rater_cible()

func _on_body_entered(body):
	# On ignore si le projectile touche le joueur qui l'a lancé
	if body == player_ref:
		return

	print("J'ai touché : ", body.name) # <--- Regarde ce qui s'affiche ici !

	# Cas 1 : On touche un ennemi
	if body.is_in_group("ennemi"):
		print("-> C'est un ENNEMI ! Tentative de possession.")
		if player_ref:
			player_ref.reussir_possession(body)
		queue_free()
	
	# Cas 2 : On touche un mur ou autre chose
	else:
		print("-> Ce n'est pas un ennemi (Mur ou Décor).")
		rater_cible()

func rater_cible():
	if player_ref:
		player_ref.rater_possession(global_position)
	queue_free()
