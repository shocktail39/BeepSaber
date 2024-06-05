# The lightsaber logic is mostly contained in the BeepSaber_Game.gd
# here I only track the extended/sheethed state and provide helper functions to
# trigger the necessary animations
extends Area3D
class_name LightSaber

# the type of note this saber can cut (0 -> left, 1 -> right)
@export var type := 0 # (int, 0, 1)

# store the saber material in a variable so the main game can set the color on initialize
@onready var _anim := $AnimationPlayer as AnimationPlayer
@onready var _ray_cast := $RayCast3D as RayCast3D
@onready var _swing_cast := $SwingableRayCast as SwingableRayCast
@onready var _main_game: BeepSaber_Game
@onready var saber_visual := $saber_holder.get_child(0) as DefaultSaber
@onready var controller := get_parent() as BeepSaberController

@export var offset_pos := Vector3.ZERO
@export var offset_rot := Vector3.ZERO
var extra_offset_pos := Vector3.ZERO
var extra_offset_rot := Vector3.ZERO

var saber_end := Vector3.ZERO
var saber_end_past := Vector3.ZERO
var last_dt := 0.0

func _show() -> void:
	if not is_extended():
		_anim.play(&"Show")
		saber_visual._show()

func is_extended() -> bool:
	return saber_visual.is_extended

func _hide() -> void:
	# This check makes sure that we are not already in the hidden state
	# (where we translated the light saber to the hilt) to avoid playing it back
	# again from the fully extended light saber position
	if (is_extended() and _anim.current_animation != "QuickHide"):
		_anim.play(&"Hide")
		saber_visual._hide()

func set_thickness(value: float) -> void:
	saber_visual.set_thickness(value)

func set_color(color: Color) -> void:
	saber_visual.set_color(color)
	
func set_trail(enabled: bool = true) -> void:
	saber_visual.set_trail(enabled)

func _ready() -> void:
#	set_saber("res://game/sabers/particles/particles_saber.tscn")
	if get_tree().get_nodes_in_group(&"main_game"):
		_main_game = get_tree().get_nodes_in_group(&"main_game")[0] as BeepSaber_Game
	_anim.play(&"QuickHide")
	saber_visual.quickhide()
	
	if type == 0:
		_swing_cast._set_collision_mask_value(CollisionLayerConstants.LeftNote_bit, true)
	else:
		_swing_cast._set_collision_mask_value(CollisionLayerConstants.RightNote_bit, true)
	_swing_cast._set_collision_mask_value(CollisionLayerConstants.Bombs_bit, true)
	
func _physics_process(delta: float) -> void:
	position = offset_pos + extra_offset_pos
	rotation_degrees = offset_rot + extra_offset_rot
	saber_end_past = saber_end
	#saber_end = (get_parent() as Node3D).global_transform.origin + global_transform.basis.y
	saber_end = saber_visual.tip.global_position
	last_dt = delta
	if is_extended():
		#check floor collision for burn mark
		_ray_cast.force_raycast_update()
		var raycoli := _ray_cast.get_collider()
		if raycoli is Floor:
			var floor_body := raycoli as Floor
			var colipoint := _ray_cast.get_collision_point()
			floor_body.burn_mark(colipoint,type)

func set_saber(saber_path: String) -> void:
	var newsaber := (load(saber_path) as PackedScene).instantiate()
	if newsaber is DefaultSaber:
		for i in $saber_holder.get_children():
			i.queue_free()
		saber_visual = newsaber as DefaultSaber
		$saber_holder.add_child(newsaber)

func set_swingcast_enabled(value: bool) -> void:
	_swing_cast.set_raycasts_enabled(value)

func _handle_area_collided(area: Area3D) -> void:
	if Scoreboard.paused: return
	var cut_object := area.get_parent()
	if not cut_object is Cuttable: return
	var note := cut_object as Cuttable
	
	var time_offset: float = (
		(note.beat/Map.current_info.beats_per_minute * 60.0)-
		_main_game.song_player.get_playback_position()
	)
	saber_visual.hit(time_offset)
	controller.simple_rumble(0.75, 0.1)
	
	var o := controller.global_transform.origin
	var controller_speed: Vector3 = (saber_end - saber_end_past) / last_dt
	const BEAT_DISTANCE := 4.0
	var cutplane := Plane(o, saber_end, saber_end_past + Vector3(0, 0, BEAT_DISTANCE * Map.current_info.beats_per_minute * last_dt / 30)) # Account for relative position to track speed
	note.cut(type, controller_speed, cutplane, controller)

func _on_AnimationPlayer_animation_started(anim_name: StringName) -> void:
	_swing_cast.adjust_segments = true

func _on_AnimationPlayer_animation_finished(anim_name: StringName) -> void:
	_swing_cast.adjust_segments = false
