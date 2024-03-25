extends Node3D


var points_label := [null, null, null, null]
var current_point_label :int = 0


func _ready():
	var points_label_ref := preload("res://game/points_label.tscn")
	for i in range(0,4):
		var instance := points_label_ref.instantiate()
		instance.text_mesh = TextMesh.new()
		instance.text_mesh.material = StandardMaterial3D.new()
		instance.find_child("mesh_instance").mesh = instance.text_mesh
		points_label[i] = instance
		add_child(instance)


func show_points(_position: Vector3, value: String):
	if value == "0":
		value = "x"
	var color := Color(1,0,0) if value == "x" else Color(1,1,1)
	print(value)
	points_label[current_point_label].show_points(_position,value,color)
	current_point_label += 1
	current_point_label %= 4
