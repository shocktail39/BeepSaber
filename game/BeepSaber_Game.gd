# This file contains the main game logic for the BeepSaber demo implementation
extends Node3D
class_name BeepSaber_Game

var gamestate_bootup := GameState.new()
var gamestate_mapcomplete := GameStateMapComplete.new()
var gamestate_mapselection := GameStateMapSelection.new()
var gamestate_newhighscore := GameStateNewHighScore.new()
var gamestate_paused := GameStatePaused.new()
var gamestate_playing := GameStatePlaying.new()
var gamestate_settings := GameStateSettings.new()
var gamestate: GameState = gamestate_bootup

@onready var left_controller := $XROrigin3D/LeftController as BeepSaberController
@onready var right_controller := $XROrigin3D/RightController as BeepSaberController

@onready var left_saber := $XROrigin3D/LeftController/LeftLightSaber as LightSaber
@onready var right_saber := $XROrigin3D/RightController/RightLightSaber as LightSaber

@onready var right_ui_raycast := $XROrigin3D/RightController/UIRaycast as UIRaycast
@onready var left_ui_raycast := $XROrigin3D/LeftController/UIRaycast as UIRaycast

@onready var main_menu := $MainMenu_OQ_UI2DCanvas as OQ_UI2DCanvas
@onready var pause_menu := $PauseMenu_canvas as OQ_UI2DCanvas
@onready var pause_countdown := $Pause_countdown as OQ_UI2DLabel
@onready var settings_canvas := $Settings_canvas as OQ_UI2DCanvas
@onready var settings_panel := settings_canvas.ui_control as SettingsPanel
@onready var highscore_canvas := $Highscores_Canvas as OQ_UI2DCanvas
@onready var highscore_panel := highscore_canvas.ui_control as HighscorePanel
@onready var name_selector_canvas := $NameSelector_Canvas as OQ_UI2DCanvas
@onready var highscore_keyboard := $Keyboard_highscore as OQ_UI2DKeyboard
@onready var endscore := $EndScore as EndScore

@onready var points_label_driver := $Points_label_driver as PointsLabelDriver
@onready var event_driver := $event_driver as EventDriver
@onready var cube_pool := $BeepCubePool as BeepCubePool

@onready var multiplier_label := $Multiplier_Label as MeshInstance3D
@onready var point_label := $Point_Label as MeshInstance3D
@onready var percent_indicator := $Percent_Indicator as PercentIndicator

@onready var map_source_dialogs := $MapSourceDialogs as Node3D
@onready var online_search_keyboard := $Keyboard_online_search as OQ_UI2DKeyboard

@onready var fps_label := $XROrigin3D/XRCamera3D/PlayerHead/FPS_Label as OQ_UI2DLabel

@onready var cube_template := preload("res://game/BeepCube.tscn").instantiate() as BeepCube

@onready var track := $Track as Node3D

@onready var song_player := $SongPlayer as AudioStreamPlayer

@onready var menu := main_menu.ui_control as MainMenu


# There's an interesting issue where the AudioStreamPlayer's playback_position
# doesn't immediately return to 0.0 after restarting the song_player. This
# causes issues with restarting a map because the process_physics routine will
# execute for a times and attempt to process the map up to the playback_position
# prior to the AudioStreamPlayer restart. This bug can presents itself as notes
# persisting between map restarts.
# To remidy this issue, this flag is set to true when the map is restarted. The
# process_physics routine won't begin processing the map until after the
# AudioStreamPlayer has reset it's playback_position to zero. This flag is set
# to false once the AudioStreamPlayer reset is detected.
var _audio_synced_after_restart := false

var _in_wall := false

#prevents the song for starting from the start when pausing and unpausing
var pause_position := 0.0

func start_map(info: Map.Info, map_difficulty: int) -> void:
	var set0 := info.difficulty_beatmaps
	if (set0.is_empty()):
		vr.log_error("No _difficultyBeatmaps in set")
		return
	Map.current_difficulty_index = map_difficulty
	
	var map_data := vr.load_json_file(info.filepath + set0[map_difficulty].beatmap_filename)
	if not map_data.has("_notes"):
		print("Map has no '_notes'")
		return
	Map.current_info = info
	Map.load_beatmap_v2(map_data)
	
	if not Settings.disable_map_color:
		Map.set_colors_from_custom_data(info.custom_data, info.difficulty_beatmaps[map_difficulty].custom_data, Settings.color_left, Settings.color_right)
	update_colors(Map.color_left, Map.color_right)
	if Map.event_stack.is_empty():
		event_driver.set_all_on(Map.color_left, Map.color_right)
	else:
		event_driver.set_all_off()
	
	print("loading: ",info.filepath + info.song_filename)
	var stream := AudioStreamOggVorbis.load_from_file(info.filepath + info.song_filename)
	
	song_player.stream = stream
	_audio_synced_after_restart = false
	song_player.play(0.0)
	song_player.volume_db = 0.0
	_in_wall = false
	Scoreboard.restart()
	
	_display_points()
	percent_indicator.start_map()
	
	_clear_track()
	_transition_game_state(gamestate_playing)

# This function will transitioning the game from it's current state into
# the provided 'next_state'.
func _transition_game_state(next_state: GameState) -> void:
	gamestate = next_state
	gamestate._ready(self)

func show_MapSourceDialogs(showing: bool = true) -> void:
	map_source_dialogs.visible = showing
	for c in map_source_dialogs.get_children():
		if c is OQ_UI2DCanvas:
			(c as OQ_UI2DCanvas)._hide()
	if showing:
		var first_dialog := map_source_dialogs.get_child(0)
		if first_dialog is OQ_UI2DCanvas:
			(first_dialog as OQ_UI2DCanvas)._show()

# call this method to submit a new highscore to the database
func _submit_highscore(player_name: String) -> void:
	if gamestate == gamestate_newhighscore:
		Highscores.add_highscore(
			Map.current_info,
			Map.current_difficulty.difficulty_rank,
			player_name,
			Scoreboard.points)
			
		_transition_game_state(gamestate_mapcomplete)

func _check_and_update_saber(controller: BeepSaberController, saber: LightSaber) -> void:
	# to allow extending/sheething the saber while not playing a song
	if ((not song_player.playing)
		and (controller.ax_just_pressed() or controller.by_just_pressed())
		and (not saber._anim.is_playing())):
		if (saber.is_extended()): saber._hide()
		else: saber._show()
	
	# check for saber rumble (only when extended and not already rumbling)
	# this check is necessary to not overwrite a rumble set from somewhere else
	# (in this case it can come from cutting cubes)
	if not controller.is_simple_rumbling(): 
		if _in_wall:
			# weak rumble on both controllers when player is inside wall
			controller.simple_rumble(0.1, 0.1)
		elif saber.get_overlapping_areas().size() > 0 or saber.get_overlapping_bodies().size() > 0:
			# strong rumble when saber is cutting into wall or other saber
			controller.simple_rumble(0.5, 0.1)
		else:
			controller.simple_rumble(0.0, 0.1)


func _physics_process(_dt: float) -> void:
	if fps_label.visible:
		fps_label.set_label_text("FPS: %d" % Engine.get_frames_per_second())
	
	gamestate._physics_process(self)
	
	_check_and_update_saber(left_controller, left_saber)
	_check_and_update_saber(right_controller, right_saber)

func _ready() -> void:
	vr.vrOrigin = $XROrigin3D as XROrigin3D
	vr.vrCamera = $XROrigin3D/XRCamera3D as XRCamera3D
	vr.leftController = left_controller
	vr.rightController = right_controller
	
	left_saber.set_saber(Settings.SABER_VISUALS[Settings.saber_visual][1])
	right_saber.set_saber(Settings.SABER_VISUALS[Settings.saber_visual][1])
	fps_label.visible = Settings.show_fps
	
	if not vr.inVR:
		$XROrigin3D.add_child(preload("res://OQ_Toolkit/OQ_ARVROrigin/Feature_VRSimulator.tscn").instantiate())
	set_colors_from_settings()
	
	UI_AudioEngine.attach_children(highscore_keyboard)
	UI_AudioEngine.attach_children(online_search_keyboard)
	
	_transition_game_state(gamestate_mapselection)
	
	Scoreboard.score_changed.connect(_display_points)
	Scoreboard.points_awarded.connect(points_label_driver.show_points)
	
	#render common assets for a couple of frames to prevent performance issues when loading them mid game
	($pre_renderer as Node3D).visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	($pre_renderer as Node3D).queue_free()

func set_colors_from_settings() -> void:
	update_colors(Settings.color_left, Settings.color_right)

func update_colors(left: Color, right: Color) -> void:
	Map.color_left = left
	Map.color_right = right
	left_saber.set_color(left)
	right_saber.set_color(right)
	#also updates map colors
	event_driver.update_colors(left, right)
	($StandingGround as Floor).update_colors(left, right)

func disable_events(disabled: bool) -> void:
	event_driver.disabled = disabled
	if disabled:
		event_driver.set_all_off()
	else:
		event_driver.set_all_on(Settings.color_left, Settings.color_right)

func _clear_track() -> void:
	for c in track.get_children():
		if c is BeepCube:
			var b := c as BeepCube
			if b.visible:
				b.release()
		else:
			track.remove_child(c)
			c.queue_free()

func _display_points() -> void:
	var hit_rate: float
	if Scoreboard.right_notes+Scoreboard.wrong_notes > 0:
		hit_rate = Scoreboard.right_notes/(Scoreboard.right_notes+Scoreboard.wrong_notes)
	else:
		hit_rate = 1.0
	
	(point_label.mesh as TextMesh).text = "Score: %6d" % Scoreboard.points
	(multiplier_label.mesh as TextMesh).text = "x %d\nCombo %d" % [Scoreboard.multiplier, Scoreboard.combo]
	percent_indicator.update_percent(hit_rate)

# accessor method for the player name selector UI element
func _name_selector() -> NameSelector:
	return name_selector_canvas.ui_control

func _on_PlayerHead_area_entered(area: Area3D) -> void:
	if area.is_in_group(&"wall"):
		song_player.volume_db = -15.0
		_in_wall = true

func _on_PlayerHead_area_exited(area: Area3D) -> void:
	if area.is_in_group(&"wall"):
		song_player.volume_db = 0.0
		_in_wall = false

# when the song ended we want to display the current score and
# the high score
func _on_song_ended() -> void:
	song_player.stop()
	PlayCount.increment_play_count(Map.current_info,Map.current_difficulty.difficulty_rank)
	
	var new_record := false
	var highscore := Highscores.get_highscore(Map.current_info,Map.current_difficulty.difficulty_rank)
	if highscore == -1:
		# no highscores exist yet
		highscore = Scoreboard.points
	elif Scoreboard.points > highscore:
		# player's score is the new highscore!
		highscore = Scoreboard.points
		new_record = true

	var current_percent := Scoreboard.right_notes/(Scoreboard.right_notes+Scoreboard.wrong_notes)
	endscore.show_score(
		Scoreboard.points,
		highscore,
		current_percent,
		"%s By %s\n%s     Map author: %s" % [
			Map.current_info.song_name,
			Map.current_info.song_author_name,
			menu._map_difficulty_name,
			Map.current_info.level_author_name],
		Scoreboard.full_combo,
		new_record
	)
	
	if Highscores.is_new_highscore(Map.current_info,Map.current_difficulty.difficulty_rank,Scoreboard.points):
		_transition_game_state(gamestate_newhighscore)
	else:
		_transition_game_state(gamestate_mapcomplete)

func _restart_button() -> void:
	start_map(Map.current_info, Map.current_difficulty_index)
	endscore.visible = false
	pause_menu.visible = false

func _main_menu_button() -> void:
	_clear_track()
	_transition_game_state(gamestate_mapselection)

func _unpause_button() -> void:
	pause_menu.visible = false
	pause_countdown.visible = true
	track.visible = true
	pause_countdown.set_label_text("3")
	await get_tree().create_timer(0.5).timeout
	pause_countdown.set_label_text("2")
	await get_tree().create_timer(0.5).timeout
	pause_countdown.set_label_text("1")
	await get_tree().create_timer(0.5).timeout
	pause_countdown.visible = false
	
	# continue game play
	song_player.play(pause_position)
	_transition_game_state(gamestate_playing)

func _on_BeepSaberMainMenu_difficulty_changed(map_info: Map.Info, diff_rank: int) -> void:
	Map.current_difficulty = null
	for diff in map_info.difficulty_beatmaps:
		if diff_rank == diff.difficulty_rank:
			Map.current_difficulty = diff
			break
	
	# menu loads playlist in _ready(), must yield until scene is loaded
	if not highscore_canvas:
		await self.ready
	
	highscore_canvas._show()
	highscore_panel.load_highscores(map_info,diff_rank)

func _settings_button() -> void:
	_transition_game_state(gamestate_settings)

func _on_settings_Panel_apply() -> void:
	set_colors_from_settings()
	_transition_game_state(gamestate_mapselection)

func _on_Keyboard_highscore_text_input_enter(text: String) -> void:
	if gamestate == gamestate_newhighscore:
		_submit_highscore(text)

func _on_NameSelector_name_selected(name: String) -> void:
	if gamestate == gamestate_newhighscore:
		_submit_highscore(name)

func _on_BeepCubePool_scene_instanced(cube: BeepCube) -> void:
	cube.visible = false
	track.add_child(cube)
