extends Node
class_name SongUploader

# allows the player to upload a zip song file into the game songs folder, good for quest or web users

var server := TCPServer.new()
@export var PORT := 45800
const UPLOAD_DIR := Constants.APPDATA_PATH+"temp/"
const CRLF := "\r\n"

var active := false

# reference to the main main node (used for playing downloadable song previews)
@export var main_menu_ref: MainMenu

func _enter_tree() -> void:
	if not DirAccess.dir_exists_absolute(UPLOAD_DIR):
		DirAccess.make_dir_recursive_absolute(UPLOAD_DIR)
	
	var err := server.listen(PORT)
	if err == OK:
		print("Server started on ", get_server_url())
		active = true
	else:
		print("Failed to start server: ", err)

func get_server_url() -> String:
	var ips := IP.get_local_addresses()
	var v4ips := []
	for i in range(ips.size()):
		if ips[i].count(".") == 3 and ips[i] != "127.0.0.1":
			v4ips.append(ips[i])
	if not v4ips.is_empty():
		return "http://%s:%s"%[v4ips[v4ips.size()-1], PORT]
	return "http://localhost:%s"%[ PORT]

func _process(_delta: float) -> void:
	if server.is_connection_available():
		var connection := server.take_connection()
		handle_connection(connection)

func handle_connection(connection: StreamPeerTCP) -> void:
	var request := PackedByteArray()
	
	# Read the headers first (until we find \r\n\r\n)
	var headers_complete := false
	var buffer := PackedByteArray()
	
	var pulls := 0
	while not headers_complete:
		if connection.get_available_bytes() > 0:
			buffer.append_array(connection.get_partial_data(1)[1])
			# Check for end of headers
			if buffer.size() >= 4:
				var last_four = buffer.slice(buffer.size() - 4)
				if last_four == "\r\n\r\n".to_utf8_buffer():
					headers_complete = true
		if pulls%64 == 0:
			await get_tree().process_frame
		pulls += 1
	
	request.append_array(buffer)
	var headers := request.get_string_from_utf8()
	
	if headers.begins_with("GET"):
		connection.put_data(make_get_response(headers))
	elif headers.begins_with("POST"):
		var content_length_match := headers.find("Content-Length: ")
		if content_length_match == -1:
			connection.put_data(make_error_response("400 Bad Request"))
			return
		# Get Content-Length
		var content_length := int(headers.substr(content_length_match + 16).split("\r\n")[0])
		
		# Read the rest of the data
		var post_body := PackedByteArray()
		while post_body.size() < content_length and connection.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			if connection.get_available_bytes() > 0:
				post_body.append_array(connection.get_partial_data(connection.get_available_bytes())[1])
		connection.put_data(handle_post(headers, post_body, content_length))
		if main_menu_ref:
			main_menu_ref._on_LoadPlaylists_Button_pressed()
	else:
		connection.put_data(make_error_response("405 Method Not Allowed"))
	
	connection.disconnect_from_host()

static func make_get_response(headers: String) -> PackedByteArray:
	var path := StringName(headers.substr(4, headers.find(" ", 4) - 4))
	match path:
		&"/Roboto-Medium.ttf":
			return make_response_from_file("res://OQ_Toolkit/OQ_UI2D/theme/Roboto-Medium.ttf", "font/ttf")
		&"/favicon.ico":
			return make_response_from_file("res://game/data/beepsaber_logo.png", "image/png")
		&"/style.css":
			return make_response_from_file("res://game/scripts/SongUploader/style.css", "text/css")
		_:
			return make_response_from_file("res://game/scripts/SongUploader/prompt.html", "text/html")

static func make_response_from_file(path: String, type: String) -> PackedByteArray:
	var file := FileAccess.get_file_as_bytes(path)
	
	var header := ("HTTP/1.1 200 OK" + CRLF +
		"Content-Type: %s" + CRLF +
		"Content-Length: %d" + CRLF +
		"Connection: close" + CRLF + CRLF
	) % [type, file.size()]
	
	var response := header.to_utf8_buffer() + file
	return response

static func find_byte_pattern(data: PackedByteArray, pattern: PackedByteArray, start: int = 0) -> int:
	if pattern.size() > data.size():
		return -1
	
	for i in range(start, data.size() - pattern.size() + 1):
		var found := true
		for j in range(pattern.size()):
			if data[i + j] != pattern[j]:
				found = false
				break
		if found:
			return i
	return -1

static func handle_post(headers: String, post_body: PackedByteArray, content_length: int) -> PackedByteArray:
	# Find the boundary in the Content-Type header
	const BOUNDARY_HEADER := "Content-Type: multipart/form-data; boundary="
	var boundary_match := headers.find(BOUNDARY_HEADER)
	if boundary_match == -1:
		return make_error_response("400 Bad Request")
	
	var boundary_delimiter := headers.substr(boundary_match + BOUNDARY_HEADER.length()).split("\r\n")[0]
	
	# Find the file content boundaries
	var zipfile_start := find_byte_pattern(post_body, (CRLF + CRLF).to_utf8_buffer(), boundary_delimiter.length()) + 4
	if zipfile_start == -1:
		return make_error_response("400 Bad Request")
	
	# Find the end boundary
	var boundary_end := "--" + boundary_delimiter + "--"
	var length_to_look_back := (CRLF + boundary_end + CRLF).length()
	var zipfile_end := find_byte_pattern(post_body, boundary_end.to_utf8_buffer(), content_length - length_to_look_back) - 2
	
	if zipfile_end <= -1:
		return make_error_response("400 Bad Request")
	
	# Extract and save the file content
	var filename := "UploadedSong-%s"%[hash(post_body)]
	var file_content := post_body.slice(zipfile_start, zipfile_end)
	var file := FileAccess.open(UPLOAD_DIR + filename + ".zip", FileAccess.WRITE)
	file.store_buffer(file_content)
	file.close()
	
	var unzipped_dir := unzip_song(filename)
	if unzipped_dir.is_empty() or DirAccess.get_files_at(unzipped_dir).is_empty():
		return make_error_response("400 Unable to unzip file")
	
	# Send success response
	var response_body := """<!DOCTYPE html>
<html>
<head>
	<title>Upload Success</title>
	<link rel="stylesheet" href="/style.css" />
</head>
<body>
	<h2>Song uploaded successfully!</h2>
	<h4>The song should appear on the songs list now</h4>
	<p>Folder Name: %s</p>
	<p>Size: %d bytes</p>
	<p><a href="/">Upload another song</a></p>
</body>
</html>""" % [filename, file_content.size()]

	var response_headers := [
		"HTTP/1.1 200 OK",
		"Content-Type: text/html",
		"Content-Length: " + str(response_body.length()),
		"Connection: close"
	]
	
	var response := CRLF.join(response_headers) + CRLF + CRLF + response_body
	return response.to_utf8_buffer()

static func make_error_response(error: String) -> PackedByteArray:
	var response_body := """
<!DOCTYPE html>
<html>
<head>
	<title>Error</title>
	<link rel="stylesheet" href="/style.css" />
</head>
<body>
	<h2>Error: %s</h2>
	<p><a href="/">Go back</a></p>
</body>
</html>""" % error

	var headers := [
		"HTTP/1.1 " + error,
		"Content-Type: text/html",
		"Content-Length: " + str(response_body.length()),
		"Connection: close"
	]
	
	var response := CRLF.join(headers) + CRLF + CRLF + response_body
	return response.to_utf8_buffer()

func _exit_tree() -> void:
	server.stop()

static func unzip_song(filename := "") -> String:
	var zippath := UPLOAD_DIR + filename + ".zip"
	var song_out_dir := Constants.APPDATA_PATH + ("Songs/%s/"%filename)
	
	if DirAccess.make_dir_recursive_absolute(song_out_dir) != OK: 
		vr.log_error(
			"unzip_song - " +
			"Failed to create song output dir '%s'" % song_out_dir)
		return ""
	
	Utils.unzip(zippath,song_out_dir)
	
	DirAccess.remove_absolute(zippath)
	
	return song_out_dir
