@tool
## A specialized container for [Atom] nodes that acts as a local gravity hub.
##
## Manages a group of atoms.
class_name GraphBranch extends Control

@export var physics_enabled: bool = true: ## If false, all child atoms will be set to static mode.
	set(value):
		if physics_enabled == value: return
		physics_enabled = value

# Boundary Cash
var _content_min_offset: Vector2 = Vector2.ZERO
var _content_max_offset: Vector2 = Vector2.ZERO

## Returns the global center of the branch used as the gravity pivot.
func get_gravity_center() -> Vector2:
	var global_scale = get_global_transform().get_scale()
	return global_position + (size / 2.0 * global_scale)

## Returns all direct children that are of type [Atom].
func get_local_atoms() -> Array[Atom]:
	var result: Array[Atom] = []
	for child in get_children():
		if child is Atom: result.append(child)
	return result

## Calculates the combined bounding box of the branch and its atoms.
func _calculate_content_bounds() -> void:
	var origin = global_position
	
	# Начальные границы (сама ветка)
	var min_pos = Vector2.ZERO
	var max_pos = size * get_global_transform().get_scale()
	
	for atom in get_local_atoms():
		if not is_instance_valid(atom): continue
		
		var atom_scale = atom.get_global_transform().get_scale()
		var atom_radius = atom.get_effective_radius() * atom_scale.x
		var atom_center = atom.global_position + (atom.pivot_offset * atom_scale)
		
		# Относительное смещение центра атома от верхнего левого угла ветки
		var relative_center = atom_center - origin
		
		var atom_min = relative_center - Vector2(atom_radius, atom_radius)
		var atom_max = relative_center + Vector2(atom_radius, atom_radius)
		
		if atom_min.x < min_pos.x: min_pos.x = atom_min.x
		if atom_min.y < min_pos.y: min_pos.y = atom_min.y
		if atom_max.x > max_pos.x: max_pos.x = atom_max.x
		if atom_max.y > max_pos.y: max_pos.y = atom_max.y
	
	_content_min_offset = min_pos
	_content_max_offset = max_pos

func _find_parent_graph() -> Control:
	var parent = get_parent()
	while parent:
		if parent is Graph: return parent
		parent = parent.get_parent()
	return null
