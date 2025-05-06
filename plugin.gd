@tool
extends EditorPlugin


const ScenePostImportPlugin := preload("./scene_post_import_plugin.gd")


var _scene_post_import_plugin : EditorScenePostImportPlugin = null


func _enter_tree() -> void:
	_scene_post_import_plugin = ScenePostImportPlugin.new()
	add_scene_post_import_plugin(_scene_post_import_plugin)


func _exit_tree() -> void:
	remove_scene_post_import_plugin(_scene_post_import_plugin)
	_scene_post_import_plugin = null
