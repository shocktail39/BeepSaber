extends Cuttable
class_name Bomb

@export var min_speed := 0.5
@onready var collision_shape := $Area3D/CollisionShape3D as CollisionShape3D

func set_collision_disabled(value: bool) -> void:
	collision_shape.disabled = value

@warning_ignore("unused_parameter")
func cut(saber_type: int, cut_speed: Vector3, cut_plane: Plane, controller: BeepSaberController) -> void:
	Scoreboard.bad_cut(transform.origin)
	queue_free()

func on_miss() -> void:
	queue_free()

func spawn(info: BombInfo, current_beat: float) -> void:
	speed = Constants.BEAT_DISTANCE * Map.current_info.beats_per_minute / 60.0
	beat = info.beat
	
	var distance: float = info.beat - current_beat
	
	transform.origin.x = Constants.LANE_X[info.line_index]
	transform.origin.y = Constants.LAYER_Y[info.line_layer]
	transform.origin.z = -distance * Constants.BEAT_DISTANCE
	
	var anim := $AnimationPlayer as AnimationPlayer
	var anim_speed := Map.current_difficulty.note_jump_movement_speed / 9.0
	anim.speed_scale = maxf(min_speed, anim_speed)
	anim.play(&"Spawn")
