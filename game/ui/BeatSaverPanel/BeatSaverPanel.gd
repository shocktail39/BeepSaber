extends Panel
class_name BeatSaverPanel

var song_data := []
var current_list := 0
# reference to the main main node (used for playing downloadable song previews)
@export var main_menu_ref: MainMenu
# the next requestable pages for the current list; null if prev/next page is
# not requestable (ie. reached end of the list)
var prev_page_available = null
var next_page_available = null
# Older API used to support more lists. temporarily limiting to ones that still work
#var list_modes = ["hot","rating","latest","downloads","plays"]
var list_modes = ["plays"]
var search_word := ""
var item_selected := -1
var downloading := []#[["name","version_info"]]
@onready var httpreq := $HTTPReq as HTTPRequest
@onready var httpdownload := $HTTPDownload as HTTPRequest
@onready var httpcoverdownload := $CoverDownload as HTTPRequest
@onready var httppreviewdownload := $PreviewDownload as HTTPRequest
@onready var placeholder_cover := preload("res://game/data/beepsaber_logo.png")
@onready var goto_maps_by := $gotoMapsBy as Button
@onready var v_scroll := ($ItemList as ItemList).get_v_scroll_bar()

const MAX_BACK_STACK_DEPTH := 10
# series of previous requests that you can go back to
var back_stack := []

# structure representing the previous HTTP request we made to beatsaver
var prev_request := {
	# required fields
	"type" : "list",# can be "list","text_search", or "uploader"
	"page" : 0,
	
	# type-specific fields when type is "list"
	"list" : "plays"
	
	# type-specific fields when type is "text_search"
	# "search_text" = ""
	
	# type-specific fields when type is "uploader"
	# "uploader_id" = ""
}

@export var keyboard: OQ_UI2DKeyboard

func _ready() -> void:
	UI_AudioEngine.attach_children(self)
	$back.visible = false
	v_scroll.value_changed.connect(_on_ListV_Scroll_value_changed)
	
	var is_web := OS.get_name() == "Web"
	
	if not is_web:
		httpreq.use_threads = true
		httpdownload.use_threads = true
		httpcoverdownload.use_threads = true
		httppreviewdownload.use_threads = true
	
	if keyboard != null:
		keyboard.text_input_enter.connect(_text_input_enter)
		keyboard.text_input_cancel.connect(_text_input_cancel)
	
	var parent_canvas = self
	while parent_canvas != null:
		if parent_canvas is OQ_UI2DCanvas:
			break
		parent_canvas = parent_canvas.get_parent()
	if parent_canvas != null:
		parent_canvas.visibility_changed.connect(_on_BeatSaverPanel_visibility_changed)
	
# override hide() method to handle case where UI is inside a OQ_UI2DCanvas
func _hide() -> void:
	var parent_canvas = self
	while parent_canvas != null:
		if parent_canvas is OQ_UI2DCanvas:
			break
		parent_canvas = parent_canvas.get_parent()
		
	if parent_canvas == null:
		self.visible = false
	else:
		parent_canvas.hide()

# override show() method to handle case where UI is inside a OQ_UI2DCanvas
func _show() -> void:
	var parent_canvas = self
	while parent_canvas != null:
		if parent_canvas is OQ_UI2DCanvas:
			break
		parent_canvas = parent_canvas.get_parent()
		
	if parent_canvas == null:
		self.visible = true
	else:
		parent_canvas.show()
	_on_BeatSaverPanel_visibility_changed()

func update_list(request) -> void:
	var page = request.page
	$mode.disabled = true
	if page == 0:
		# brand new request, clear list to prep for reload
		$ItemList.clear()
		if goto_maps_by:
			goto_maps_by.visible = false
		song_data = []
		item_selected = -1
	if not httpcoverdownload:
		return
	httpcoverdownload.cancel_request()
	httpreq.cancel_request()
	prev_page_available = page
	next_page_available = null
	
	match request.type:
		"list":
			var list : String = request.list
			$mode.text = list.substr(0,1).capitalize() + list.substr(1)
			httpreq.request("https://beatsaver.com/api/maps/%s/%s" % [list,page])
		"text_search":
			var search_text = request.search_text
			$mode.text = search_text
			httpreq.request("https://beatsaver.com/api/search/text/%s?q=%s&sortOrder=Relevance&automapper=true" % [page,search_text.uri_encode()])
		"uploader":
			var uploader_id = request.uploader_id
			$mode.text = "Uploader"
			httpreq.request("https://beatsaver.com/api/maps/uploader/%s/%s" % [uploader_id,page])
		_:
			vr.log_warning("Unsupported request type '%s'" % request.type)

func _add_to_back_stack(request: Dictionary) -> void:
	back_stack.push_back(request)
	if back_stack.size() > MAX_BACK_STACK_DEPTH:
		back_stack.pop_front()

# return the selected song's data, or null if not song is selected
func _get_selected_song() -> Dictionary:
	if item_selected >= 0 && song_data.size():
		return song_data[item_selected]
	return {}

func _on_HTTPRequest_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == 0:
		var json_data = JSON.parse_string(body.get_string_from_utf8())
		next_page_available = prev_page_available + 1
		
		if json_data.has("docs"):
			json_data = json_data["docs"]
			_current_cover_to_download = song_data.size()
			for song in json_data:
				song_data.insert(song_data.size(),song)
				$ItemList.add_item(song["name"])
				var tooltip = "Map author: %s" % song["metadata"]["levelAuthorName"]
				$ItemList.set_item_tooltip($ItemList.get_item_count()-1,tooltip)
				$ItemList.set_item_icon($ItemList.get_item_count()-1,placeholder_cover)
	else:
		vr.log_error("request error "+str(result))
	$mode.disabled = false
	$back.visible = back_stack.size() > 0
	_scroll_page_request_pending = false
	
	var canvas = get_parent().get_parent()
	if canvas.has_method("_input_update"): canvas._input_update()
	
	_update_all_covers()


func _on_mode_button_up() -> void:
	current_list += 1
	current_list %= list_modes.size()
	$mode.text = list_modes[current_list].capitalize()
	_add_to_back_stack(prev_request)
	prev_request = {
		"type" : "list",
		"page" : 0,
		"list" : list_modes[current_list]
	}
	update_list(prev_request)


func _on_ItemList_item_selected(index: int) -> void:
	item_selected = index
	var selected_data := _get_selected_song()
	var metadata = selected_data["metadata"]
	var dur_s = int(metadata["duration"])
	var version = selected_data["versions"][0]
	goto_maps_by.text = "Maps by %s" % metadata["levelAuthorName"]
	goto_maps_by.visible = true
	var difficulties = ""
	for diff in version['diffs']:
		difficulties += " %s" % diff['difficulty']
	var text = """[center]%s By %s[/center]

Map author: %s
Duration: %dm %ds
Difficulties:%s

[center]Description:[/center]
%s""" % [
		metadata["songName"],
		metadata["songAuthorName"],
		metadata["levelAuthorName"],
		dur_s/60,dur_s%60,
		difficulties,
		selected_data["description"],
	]
	$song_data.text = text
	
	$TextureRect.texture = $ItemList.get_item_icon(index)

	httppreviewdownload.request(selected_data['versions'][0]['previewURL'])

func _on_download_button_up():
	OS.request_permissions()
	if item_selected == -1: return
	var version_info = song_data[item_selected]['versions'][0]
	downloading.insert(downloading.size(),[song_data[item_selected]["name"],version_info])
	download_next()
	
	
func download_next():
	if downloading.size() > 0:
		httpdownload.request(downloading[0][1]['downloadURL'])
		$Label.text = "Downloading: %s - %d left" % [str(downloading[0][0]),downloading.size()-1]
		$Label.visible = true
		

func _on_HTTPRequest_download_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
#	$download.disabled = false
	if result == 0:
		var has_error = false
		var tempdir = main_menu_ref.bspath+"temp"
		var error = DirAccess.make_dir_recursive_absolute(tempdir)
		if error != OK: 
			vr.log_error(
				"_on_HTTPRequest_download_completed - " +
				"Failed to create temp directory '%s'" % tempdir)
			has_error = true
		
		# sanitize path separators from song directory name
		var song_dir_name: String = downloading[0][0].replace('/','')
		
		var zippath := main_menu_ref.bspath+"temp/%s.zip"%song_dir_name
		if not has_error:
			var file = FileAccess.open(zippath,FileAccess.WRITE)
			if file:
				file.store_buffer(body)
				file.close()
			else:
				vr.log_error(
					"_on_HTTPRequest_download_completed - " +
					"Failed to save song zip to '%s'" % zippath)
				has_error = true
		
		var song_out_dir := main_menu_ref.bspath+("Songs/%s/"%song_dir_name)
		if not has_error:
			error = DirAccess.make_dir_recursive_absolute(song_out_dir)
			if error != OK: 
				vr.log_error(
					"_on_HTTPRequest_download_completed - " +
					"Failed to create song output dir '%s'" % song_out_dir)
				has_error = true
		
		if not has_error:
			Unzip.unzip(zippath,song_out_dir)
		
		DirAccess.remove_absolute(zippath)
		
		downloading.remove_at(0)
		
		if not downloading.size() > 0:
			main_menu_ref._on_LoadPlaylists_Button_pressed()
			$Label.text = "All downloaded"
	else:
		$Label.text = "Download error"
		vr.log_info("download error "+str(result))
	
	var canvas = get_parent().get_parent()
	if canvas.has_method("_input_update"): canvas._input_update()
	download_next()

func _on_preview_download_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == 0:
		# request preview to be played by the main menu node
		if main_menu_ref != null:
			main_menu_ref.play_preview(
				body, # song data buffer
				0,    # start previous at time 0
				-1,   # play preview song for entire duration
				'mp3')# bsaver has all it's previews in mp3 format for now

func _on_search_button_up() -> void:
	keyboard._show()
	keyboard._text_edit.grab_focus();

func _text_input_enter(text: String) -> void:
	keyboard._hide()
	search_word = text
	$mode.text = search_word
	current_list = -1
	_add_to_back_stack(prev_request)
	prev_request = {
		"type" : "text_search",
		"page" : 0,
		"search_text" : search_word
	}
	update_list(prev_request)
	
func _text_input_cancel() -> void:
	keyboard._hide()


var _current_cover_to_download := 0

func _update_all_covers() -> void:
	httpcoverdownload.cancel_request()
	update_next_cover()

func update_next_cover() -> void:
	if _current_cover_to_download < song_data.size():
		var cover_url := _get_cover_url_from_song_data(song_data[_current_cover_to_download])
		
		if cover_url == "":
			# song didn't have a cover. skip this cover and move to next one
			_current_cover_to_download += 1
			update_next_cover()
		else:
			httpcoverdownload.request(cover_url)

func _update_cover(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == 0:
		var img = Image.new()
		if not img.load_jpg_from_buffer(body) == 0:
			img.load_png_from_buffer(body)
		var img_tex = ImageTexture.create_from_image(img)
		$ItemList.set_item_icon(_current_cover_to_download,img_tex)
	_current_cover_to_download += 1
	
	var canvas = get_parent().get_parent()
	if canvas.has_method("_input_update"): canvas._input_update()
	
	update_next_cover()

func _on_gotoMapsBy_pressed():
	var selected_song = _get_selected_song()
	if not selected_song.has("uploader"): return
	_add_to_back_stack(prev_request)
	prev_request = {
		"type" : "uploader",
		"page" : 0,
		"uploader_id" : selected_song["uploader"]["id"]
	}
	update_list(prev_request)
	
# SCROLL_TO_FETCH_THRESHOLD
# Range: 0.0 to 1.0
# Description: Used to request the next page of songs from the current list
# once the user scrolls past this threshold
const SCROLL_TO_FETCH_THRESHOLD = 0.9
var _scroll_page_request_pending = false
	
func _on_ListV_Scroll_value_changed(new_value: float) -> void:
	var scroll_range = v_scroll.max_value - v_scroll.min_value
	var scroll_ratio = (new_value + v_scroll.page) / scroll_range
	if scroll_ratio > SCROLL_TO_FETCH_THRESHOLD:
		if next_page_available == null:
			# no next page to load
			return
		
		# prevent back to back requests
		if _scroll_page_request_pending:
			return
		
		# request next page and update list
		prev_request.page += 1
		update_list(prev_request)
		_scroll_page_request_pending = true

func _on_back_pressed():
	if back_stack.is_empty():
		return
		
	# re-request latest entry
	prev_request = back_stack.back()
	prev_request.page = 0
	back_stack.pop_back()
	update_list(prev_request)
	
	$back.visible = back_stack.size() > 0
	
func _get_cover_url_from_song_data(song_data: Dictionary) -> String:
	var song_versions = song_data['versions']
	var version_data := {}
	if len(song_versions) == 1:
		version_data = song_versions[0]# is there always 1 version?!?
	elif len(song_versions) > 1:
		vr.log_warning("The are %d versions for this song, but only getting cover for the first. song_data = %s" % [len(song_versions),song_data])
		version_data = song_versions[0]
	else:
		vr.log_warning("No version info available in song_data: %s" % song_data)
		return ""
		
	return version_data['coverURL']

func _on_CloseButton_pressed():
	self._hide()

var _is_first_show = true
func _on_BeatSaverPanel_visibility_changed():
	if _is_first_show:
		# populate initial list of songs with most played on BeatSaver
		update_list({"type":"list","page":0,"list":"plays"})
		_is_first_show = false
