@tool
extends EditorScenePostImportPlugin


const EXTRACT_MESHES_OPTION := &"extract_resources/extract_meshes"

const EXTRACT_MATERIALS_OPTION := &"extract_resources/extract_materials"

const MESHES_DIR_OPTION := &"extract_resources/meshes_directory"

const MATERIALS_DIR_OPTION := &"extract_resources/materials_directory"

const SCENES_DIR_OPTION := &"extract_resources/scenes_directory"

const SAVE_AS_SCENE_OPTION := &"save_as_scene/enabled"


var _source_scene_path : String

var _scene_root_paths : Array[NodePath]

var _file_system_changed : bool

var _file_system_update_queued := false


func _get_import_options(path : String) -> void:
	add_import_option(EXTRACT_MESHES_OPTION, false)
	add_import_option(EXTRACT_MATERIALS_OPTION, false)
	add_import_option(MESHES_DIR_OPTION, "meshes")
	add_import_option(MATERIALS_DIR_OPTION, "materials")
	add_import_option(SCENES_DIR_OPTION, "scenes")

	_source_scene_path = path


func _get_internal_import_options(category : int) -> void:
	match category:
		INTERNAL_IMPORT_CATEGORY_NODE, INTERNAL_IMPORT_CATEGORY_MESH_3D_NODE:
			add_import_option_advanced(TYPE_BOOL, SAVE_AS_SCENE_OPTION, false)


func _pre_process(scene : Node) -> void:
	_file_system_changed = false
	_scene_root_paths.clear()

	var extract_meshes := get_option_value(EXTRACT_MESHES_OPTION)
	var extract_materials := get_option_value(EXTRACT_MATERIALS_OPTION)

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

	if get_option_value(SAVE_AS_SCENE_OPTION):
		_scene_root_paths.push_back(base_node.get_path_to(node))


func _post_process(scene : Node) -> void:
	var source_dir := _source_scene_path.get_base_dir()
	var scenes_dir := _get_dir(get_option_value(SCENES_DIR_OPTION), source_dir)

	for path in _scene_root_paths:
		var node := scene.get_node(path)
		_extract_node_as_scene(node, scenes_dir)

	_scene_root_paths.clear()

	if _file_system_changed:
		_queue_file_system_update()


func _extract_node_as_scene(node : Node, scenes_path : String) -> void:
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

	var scene := PackedScene.new()
	scene.pack(node)
	_ensure_dir_exists(scenes_path)
	# TODO: handle potential conflicts
	var save_path := scenes_path.path_join(node.name.validate_filename() + ".tscn")
	ResourceSaver.save(scene, save_path)
	_file_system_changed = true
	scene.take_over_path(save_path)

	var scene_instance := scene.instantiate()
	if node_3d != null:
		scene_instance.transform = transform

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


func _assign_owner_to_subtree(root : Node, owner := root) -> void:
	for child in root.get_children():
		child.owner = owner
		if child.scene_file_path.is_empty():
			_assign_owner_to_subtree(child, owner)


func _ensure_dir_exists(path : String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)
		_file_system_changed = true


func _print_tree(node : Node, depth := 0) -> void:
	if node.owner != null:
		prints("%s%s (owner: %s)" % ["\t".repeat(depth), node.name, node.owner.name])
	else:
		prints("\t".repeat(depth) + node.name)

	for child in node.get_children():
		_print_tree(child, depth + 1)


func _queue_file_system_update() -> void:
	if not _file_system_update_queued:
		_file_system_update_queued = true
		await EditorInterface.get_resource_filesystem().resources_reimported
		EditorInterface.get_resource_filesystem().scan()
		_file_system_update_queued = false


func _get_dir(path : String, base_dir : String) -> String:
	return path if path.is_absolute_path() else base_dir.path_join(path)
