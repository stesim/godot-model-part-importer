@tool
extends EditorScenePostImportPlugin


enum SubSceneExtractionMode {
	EXCLUDE_FROM_PARENT,
	INCLUDE_IN_PARENT,
	INCLUDE_IN_PARENT_AS_PLACEHOLDER,
}


const EXTRACT_MESHES_OPTION := &"extract_resources/extract_meshes"

const EXTRACT_MATERIALS_OPTION := &"extract_resources/extract_materials"

const SUB_SCENE_MODE_OPTION := &"extract_resources/sub_scene_mode"

const MESHES_DIR_OPTION := &"extract_resources/meshes_directory"

const MATERIALS_DIR_OPTION := &"extract_resources/materials_directory"

const SCENES_DIR_OPTION := &"extract_resources/scenes_directory"

const SAVE_AS_SCENE_OPTION := &"save_as_scene/enabled"


var sub_scene_import_extensions : Array[SubSceneImportExtension] = []


var _source_scene_path : String

var _import_script_option_values : Dictionary = {}

var _import_script_internal_options : Array[Dictionary] = []

var _import_script_internal_option_values : Dictionary[NodePath, Dictionary] = {}

var _scene_root_paths : Array[NodePath]

var _file_system_changed : bool

var _file_system_update_queued := false


func _get_import_options(path : String) -> void:
	_source_scene_path = path

	add_import_option(EXTRACT_MESHES_OPTION, false)
	add_import_option(EXTRACT_MATERIALS_OPTION, false)
	add_import_option_advanced(TYPE_INT, SUB_SCENE_MODE_OPTION, SubSceneExtractionMode.EXCLUDE_FROM_PARENT, PROPERTY_HINT_ENUM, "Exclude From Parent,Instantiate in Parent,Include As Placeholder")
	add_import_option_advanced(TYPE_STRING, MESHES_DIR_OPTION, "meshes", PROPERTY_HINT_DIR)
	add_import_option_advanced(TYPE_STRING, MATERIALS_DIR_OPTION, "materials", PROPERTY_HINT_DIR)
	add_import_option_advanced(TYPE_STRING, SCENES_DIR_OPTION, "scenes", PROPERTY_HINT_DIR)

	_import_script_option_values.clear()
	_import_script_internal_options.clear()
	_import_script_internal_option_values.clear()

	for import_script in sub_scene_import_extensions:
		import_script.import_path = _source_scene_path

		var options := import_script._get_import_options()
		_add_import_options(options)
		for option in options:
			_import_script_option_values[option.name] = option.default_value

		var internal_options := import_script._get_node_import_options()
		_import_script_internal_options.append_array(internal_options)


func _get_internal_import_options(category : int) -> void:
	match category:
		INTERNAL_IMPORT_CATEGORY_NODE, INTERNAL_IMPORT_CATEGORY_MESH_3D_NODE:
			add_import_option_advanced(TYPE_BOOL, SAVE_AS_SCENE_OPTION, false)

	_add_import_options(_import_script_internal_options)


# TODO: figure out why _get_internal_option_visibility() is not being called (as of v4.4.1)

#func _get_internal_option_visibility(category : int, for_animation : bool, option : String) -> Variant:
#	for node_option in _import_script_internal_options:
#		if node_option.name == option:
#			return get_option_value(SAVE_AS_SCENE_OPTION)
#
#	return null


func _pre_process(scene : Node) -> void:
	_file_system_changed = false
	_scene_root_paths.clear()

	var extract_meshes := get_option_value(EXTRACT_MESHES_OPTION)
	var extract_materials := get_option_value(EXTRACT_MATERIALS_OPTION)

	for option in _import_script_option_values:
		_import_script_option_values[option] = get_option_value(option)

	if not extract_meshes and not extract_materials:
		return

	var mesh_instances := scene.find_children("", "ImporterMeshInstance3D")

	var subresources := get_option_value("_subresources")
	if extract_meshes and not "meshes" in subresources:
		subresources["meshes"] = {}
	if extract_materials and not "materials" in subresources:
		subresources["materials"] = {}

	var source_dir := _source_scene_path.get_base_dir()
	var meshes_dir := _get_dir(get_option_value(MESHES_DIR_OPTION), source_dir)
	var materials_dir := _get_dir(get_option_value(MATERIALS_DIR_OPTION), source_dir)

	for instance : ImporterMeshInstance3D in mesh_instances:
		if extract_meshes:
			_configure_mesh(instance.mesh, subresources, meshes_dir)

		if extract_materials:
			for i in instance.mesh.get_surface_count():
				var material := instance.mesh.get_surface_material(i)
				if material != null:
					_configure_material(material, subresources, materials_dir)


func _internal_process(category : int, base_node : Node, node : Node, _resource : Resource) -> void:
	if category != INTERNAL_IMPORT_CATEGORY_NODE:
		return

	if not get_option_value(SAVE_AS_SCENE_OPTION):
		return

	var node_path := base_node.get_path_to(node)

	var option_values := {}
	for option in _import_script_internal_options:
		option_values[option.name] = get_option_value(option.name)

	_import_script_internal_option_values[node_path] = option_values

	_scene_root_paths.push_back(node_path)


func _post_process(scene : Node) -> void:
	var source_dir := _source_scene_path.get_base_dir()
	var scenes_dir := _get_dir(get_option_value(SCENES_DIR_OPTION), source_dir)

	for path in _scene_root_paths:
		var node := scene.get_node(path)
		_extract_node_as_scene(node, path, scenes_dir)

	_scene_root_paths.clear()

	if _file_system_changed:
		_queue_file_system_update()


func _extract_node_as_scene(node : Node, node_path : NodePath, scenes_path : String) -> void:
	var owner := node.owner
	var parent := node.get_parent()
	var index := node.get_index()

	var node_3d := node as Node3D
	var transform : Transform3D
	if node_3d != null:
		transform = node_3d.transform
		node_3d.set_identity()

	parent.remove_child(node)

	node.owner = null
	_assign_owner_to_subtree(node)

	var node_option_values := _import_script_internal_option_values[node_path]
	_import_scripts_pre_process_scene(node, parent, index, owner, node_option_values)

	var scene := _save_node_as_packed_scene(node, scenes_path)

	var mode := get_option_value(SUB_SCENE_MODE_OPTION) as SubSceneExtractionMode

	match mode:
		SubSceneExtractionMode.INCLUDE_IN_PARENT, SubSceneExtractionMode.INCLUDE_IN_PARENT_AS_PLACEHOLDER:
			var scene_instance := scene.instantiate()
			if node_3d != null:
				scene_instance.transform = transform
			if mode == SubSceneExtractionMode.INCLUDE_IN_PARENT_AS_PLACEHOLDER:
				scene_instance.set_scene_instance_load_placeholder(true)
			parent.add_child(scene_instance)
			scene_instance.owner = owner
			parent.move_child(scene_instance, index)

	node.free()


func _configure_mesh(mesh : ImporterMesh, subresource_options : Dictionary, meshes_dir : String) -> void:
	var subresource_meshes : Dictionary = subresource_options.meshes

	var mesh_name := mesh.resource_name
	if not mesh_name in subresource_meshes:
		subresource_meshes[mesh_name] = {}

	var mesh_options : Dictionary = subresource_meshes[mesh_name]
	if not mesh_options.get("save_to_file/enabled", false):
		_ensure_dir_exists(meshes_dir)
		mesh_options["save_to_file/enabled"] = true
		# TODO: handle potential conflicts
		mesh_options["save_to_file/path"] = meshes_dir.path_join(mesh_name + ".res")


func _configure_material(material : Material, subresource_options : Dictionary, materials_dir : String) -> void:
	var subresource_materials : Dictionary = subresource_options.materials

	var material_name := material.resource_name
	if not material_name in subresource_materials:
		subresource_materials[material_name] = {}

	var material_options : Dictionary = subresource_options.materials[material_name]
	if not material_options.get("use_external/enabled", false):
		_ensure_dir_exists(materials_dir)
		# TODO: handle potential conflicts
		var save_path := materials_dir.path_join(material_name + ".tres")
		ResourceSaver.save(material, save_path)
		_file_system_changed = true
		material.take_over_path(save_path)
		material_options["use_external/enabled"] = true
		material_options["use_external/path"] = save_path


func _import_scripts_pre_process_scene(scene : Node, parent : Node, index : int, main_scene : Node, node_option_values : Dictionary) -> void:
	var option_values := _import_script_option_values.merged(node_option_values, true)
	for import_script in sub_scene_import_extensions:
		import_script._pre_process_scene(scene, option_values, parent, index, main_scene)


func _save_node_as_packed_scene(node : Node, save_dir : String) -> PackedScene:
	var save_path := save_dir.path_join(node.name.validate_filename() + ".tscn")
	var scene_exists := ResourceLoader.exists(save_path)
	var scene := ResourceLoader.load(save_path) if scene_exists else PackedScene.new()
	scene.pack(node)
	if not scene_exists:
		_ensure_dir_exists(save_dir)
	# TODO: handle potential conflicts
	ResourceSaver.save(scene, save_path)
	if not scene_exists:
		scene.take_over_path(save_path)
	elif save_path in EditorInterface.get_open_scenes():
		# HACK: update open scenes manually, otherwise they will not update until
		#       the editor loses and regains focus (valid as of v4.4.1)
		EditorInterface.reload_scene_from_path(save_path)
	_file_system_changed = true
	return scene


func _assign_owner_to_subtree(root : Node, owner := root) -> void:
	for child in root.get_children():
		child.owner = owner
		if child.scene_file_path.is_empty():
			_assign_owner_to_subtree(child, owner)


func _ensure_dir_exists(path : String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)
		_file_system_changed = true


func _queue_file_system_update() -> void:
	if not _file_system_update_queued:
		_file_system_update_queued = true
		var fs := EditorInterface.get_resource_filesystem()
		await fs.resources_reimported
		fs.scan()
		_file_system_update_queued = false


func _get_dir(path : String, base_dir : String) -> String:
	return path if path.is_absolute_path() else base_dir.path_join(path)


func _add_import_options(options : Array[Dictionary]) -> void:
	for option in options:
		add_import_option_advanced(
			option.get(&"type", typeof(option.default_value)),
			option.name,
			option.default_value,
			option.get(&"hint", PROPERTY_HINT_NONE),
			option.get(&"hint_string", ""),
			option.get(&"usage", PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_EDITOR),
		)
