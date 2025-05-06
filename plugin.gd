@tool
extends EditorPlugin


const ScenePostImportPlugin := preload("./scene_post_import_plugin.gd")


var _scene_post_import_plugin : ScenePostImportPlugin = null

var _fs : EditorFileSystem = null


func _enter_tree() -> void:
	_scene_post_import_plugin = ScenePostImportPlugin.new()
	add_scene_post_import_plugin(_scene_post_import_plugin)

	_fs = EditorInterface.get_resource_filesystem()
	_fs.script_classes_updated.connect(_on_script_classes_updated)
	_on_script_classes_updated()


func _exit_tree() -> void:
	_scene_post_import_plugin.sub_scene_import_extensions.clear()

	_fs.script_classes_updated.disconnect(_on_script_classes_updated)
	_fs = null

	remove_scene_post_import_plugin(_scene_post_import_plugin)
	_scene_post_import_plugin = null


func _on_script_classes_updated() -> void:
	_scene_post_import_plugin.sub_scene_import_extensions.clear()

	for global_class in ProjectSettings.get_global_class_list():
		var script := ResourceLoader.load(global_class.path) as GDScript
		var base := script.get_base_script()
		while base != null:
			if base == SubSceneImportExtension:
				var instance := script.new()
				_scene_post_import_plugin.sub_scene_import_extensions.push_back(instance)
				break
			base = base.get_base_script()
