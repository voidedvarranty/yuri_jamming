@tool
extends EditorScenePostImport

const GENERATE_COLLISION := true


func _post_import(scene: Node) -> Object:
	for found in scene.find_children("*", "MeshInstance3D", true, false):
		_apply_transform(found as MeshInstance3D, scene)
	return scene


func _apply_transform(mesh_instance: MeshInstance3D, root: Node) -> void:
	var source := mesh_instance.mesh as ArrayMesh
	if source == null:
		return

	var xf := _relative_transform(mesh_instance, root)
	var normal_basis := xf.basis.inverse().transposed()

	var baked := ArrayMesh.new()
	baked.resource_name = source.resource_name
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)

		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in vertices.size():
			vertices[i] = xf * vertices[i]
		arrays[Mesh.ARRAY_VERTEX] = vertices

		if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in normals.size():
				normals[i] = (normal_basis * normals[i]).normalized()
			arrays[Mesh.ARRAY_NORMAL] = normals

		if arrays[Mesh.ARRAY_TANGENT] is PackedFloat32Array:
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
			for i in range(0, tangents.size(), 4):
				var t := (xf.basis * Vector3(tangents[i], tangents[i + 1], tangents[i + 2])).normalized()
				tangents[i] = t.x
				tangents[i + 1] = t.y
				tangents[i + 2] = t.z
			arrays[Mesh.ARRAY_TANGENT] = tangents

		baked.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays)
		baked.surface_set_material(surface, source.surface_get_material(surface))
		baked.surface_set_name(surface, source.surface_get_name(surface))

	mesh_instance.mesh = baked

	var parent := mesh_instance.get_parent() as Node3D
	var parent_xf := _relative_transform(parent, root) if parent != null else Transform3D.IDENTITY
	mesh_instance.transform = parent_xf.affine_inverse()

	if GENERATE_COLLISION:
		var body := StaticBody3D.new()
		body.name = "%s_Collision" % mesh_instance.name
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		collision.shape = baked.create_trimesh_shape()
		mesh_instance.add_child(body)
		body.add_child(collision)
		body.owner = root
		collision.owner = root


func _relative_transform(node: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	while node != null and node != root:
		if node is Node3D:
			xf = (node as Node3D).transform * xf
		node = node.get_parent()
	return xf
