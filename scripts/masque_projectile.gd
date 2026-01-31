extends Area2D

var vitesse = 500  # Vitesse du projectile
var player_ref = null # Pour savoir qui a tiré (le joueur)

func _physics_process(delta):
	# Fait avancer le masque tout droit dans la direction où il regarde
	position += transform.x * vitesse * delta

func _on_body_entered(body):
	if body.is_in_group("ennemi"):
		print("J'ai touché l'ennemi : ", body.name)
		if player_ref:
			player_ref.prendre_corps(body)
		queue_free()
		
	# SI C'EST LE JOUEUR (On ignore, pour pas se tirer dessus soi-même)
	elif body == player_ref:
		pass # On ne fait rien
		
	# SI C'EST N'IMPORTE QUOI D'AUTRE (Donc un mur, un sol, une table...)
	else:
		# On détruit le masque car il a tapé un obstacle
		queue_free()
