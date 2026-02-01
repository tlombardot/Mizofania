extends Area2D

var vitesse = 450
var distance_max = 300.0 
var distance_parcourue = 0.0
var player_ref = null
var corps_a_ignorer = null # Le mob qu'on vient de spawn

func _physics_process(delta):
	var deplacement = vitesse * delta
	position += transform.x * deplacement
	distance_parcourue += deplacement
	
	if distance_parcourue >= distance_max:
		rater_cible()

func _on_body_entered(body):
	if body == player_ref: return
	if body == corps_a_ignorer: return # <--- FIX BUG RE-POSSESSION

	if body.is_in_group("ennemi"):
		if "current_state" in body and body.current_state == 4: return
		
		if player_ref: player_ref.call_deferred("reussir_possession", body)
		queue_free()
	
	elif body is TileMap or body is StaticBody2D or body is TileMapLayer:
		rater_cible()

func rater_cible():
	if player_ref: player_ref.call_deferred("rater_possession", global_position)
	queue_free()
