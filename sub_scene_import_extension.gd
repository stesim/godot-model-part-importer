class_name SubSceneImportExtension
extends RefCounted


var import_path : String


func _get_import_options() -> Array[Dictionary]:
	return []


func _get_node_import_options() -> Array[Dictionary]:
	return []


@warning_ignore("unused_parameter")
func _pre_process_scene(original_scene_root : Node, options : Dictionary, parent : Node, index_in_parent : int, main_scene : Node) -> void:
	pass
