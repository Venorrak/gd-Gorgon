## The physical force that pulls connected atoms toward their ideal target distance.
## (Springs only exist between atoms with a physical bond).
##
## Rest length is automatically increased for hubs and large nodes 
## to prevent overlap and visual clutter.
##
## Offset is ONLY registered when it exceeds a small dead zone, 
## so that atoms in equilibrium (balanced spring tension) remain at rest.
## This prevents jitter in complex star or mesh topologies.
class_name GraphSpringForce extends GraphForce

@export var target_length: float = 120.0   ## The ideal distance between connected atoms.
@export var stiffness: float = 0.06        ## Higher values make atoms reach their target distance faster.
@export var hub_bonus_length: float = 40.0 ## An additional distance added to atoms with multiple conns to prevent crowding.

func apply_force(registry: Array, forces: Array, context: Dictionary) -> void:
	var index_map: Dictionary = context["atoms_index_map"]
	var centers: Array[Vector2] = context["centers"]
	var scales: Array[float] = context["scales"]
	var radii: Array[float] = context["radii"]

	for item_context in registry:
		var atom_a = item_context.atom
		var index_a = item_context.index
		
		for atom_b in atom_a.connected_atoms:
			if not is_instance_valid(atom_b): continue
			
			if atom_a in atom_b.connected_atoms and atom_a.get_instance_id() > atom_b.get_instance_id(): continue
			
			var index_b: int = index_map.get(atom_b, -1)
			if index_b == -1: continue
			
			if registry[index_a].is_cold and registry[index_b].is_cold: continue
			
			var global_difference = centers[index_b] - centers[index_a]
			var global_distance = global_difference.length()
			
			if global_distance < 0.1: continue
			
			var average_scale = (scales[index_a] + scales[index_b]) * 0.5
			
			var logical_distance = global_distance / average_scale
			
			var connections_count_a = atom_a.connected_atoms.size()
			var connections_count_b = atom_b.connected_atoms.size()
			
			var current_target_length = target_length + radii[index_a] + radii[index_b]
			
			if connections_count_a > 1 and connections_count_b > 1: current_target_length += hub_bonus_length
			
			var force_magnitude = (logical_distance - current_target_length) * stiffness
			
			var force_vector = (global_difference / global_distance) * (force_magnitude * average_scale)
		
			forces[index_a] += force_vector
			forces[index_b] -= force_vector

func calculate_mass(registry: Array, masses: Array, context: Dictionary) -> void: pass
