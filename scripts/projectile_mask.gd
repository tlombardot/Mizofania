extends Area2D

var speed = 250
var distance_max = 0
var distance_traveled = 0

var player_ref = null
var body_to_ignore = null

var is_bouncing = false
var velocity = Vector2.ZERO

func _ready():
	if not is_connected("body_entered", _on_body_entered):
		connect("body_entered", _on_body_entered)

func _physics_process(delta):
	if is_bouncing:
		position += velocity * delta
		velocity = velocity.move_toward(Vector2.ZERO, 1000 * delta)
		if velocity.length() < 10:
			fall_to_the_ground()
		return

	var move_amount = speed * delta
	position += transform.x * move_amount
	distance_traveled += move_amount

	if distance_traveled >= distance_max:
		fall_to_the_ground()

func _on_body_entered(body):
	if body == body_to_ignore: return
	
	if body is TileMap or body is TileMapLayer or body is StaticBody2D:
		fall_to_the_ground()
		return

	if body.is_in_group("enemy"):
		var level_ok = true
		
		if "required_level" in body:
			if player_ref.current_level < body.required_level:
				level_ok = false
		
		if level_ok:
			if player_ref.has_method("success_possession"):
				player_ref.success_possession(body)
				queue_free()
		else:
			bounce()

func bounce():
	is_bouncing = true
	$CollisionShape2D.call_deferred("set_disabled", true)
	
	velocity = -transform.x * (speed * 0.5) 
	
	modulate = Color(0.591, 0.0, 0.125, 1.0) 
	var t = create_tween()
	t.tween_property(self, "modulate", Color.WHITE, 0.3)

	await get_tree().create_timer(0.3).timeout
	fall_to_the_ground()

func fall_to_the_ground():
	if player_ref.has_method("miss_possession"):
		player_ref.miss_possession(global_position)
	queue_free()
