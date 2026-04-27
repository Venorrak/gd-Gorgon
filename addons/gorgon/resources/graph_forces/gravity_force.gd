## The physical force that pulls all atoms toward their gravitational targets.
## (Free atoms are pulled toward the global center; node atoms are pulled toward their branches).
##
## The force of attraction increases for nodes and points with multiple connections,
## so that central elements remain in the middle of the graph.
##
## It has a small dead zone so that atoms do not constantly fight 
## for the exact central point, ensuring a stable state of rest.
class_name GravityForce extends GraphForce

@export var gravity_strength: float = 0.002  ## Power of the pull toward the center.
@export var degree_scale:     float = 0.002  ## Extra pulling force for each connection the atom has.
@export var dead_zone:        float = 100.0  ## Atoms within this radius are not subject to gravitational attraction.

func apply_force(registry: Array, forces: Array, context: Dictionary) -> void:
	var global_center: Vector2        = context["global_center"]
	var centers:       Array[Vector2] = context["centers"]
	var scales:        Array[float]   = context["scales"]

	for item_context in registry:
		var atom = item_context.atom
		
		if atom.is_dragging or atom.is_static: continue
		
		var index = item_context.index
		var world_scale = scales[index]
		
		var gravity_target: Vector2
		if item_context.is_in_hub and is_instance_valid(item_context.gravity_target_node):
			gravity_target = item_context.gravity_target_node.get_gravity_center()
		else:
			gravity_target = global_center
		
		var direction_vector = gravity_target - centers[index]
		
		if direction_vector.length() < dead_zone * world_scale: continue
		
		var degree_factor = 1.0 + atom.connected_atoms.size() * degree_scale
		
		forces[index] += (direction_vector / world_scale) * gravity_strength * degree_factor * world_scale

func calculate_mass(registry: Array, masses: Array, context: Dictionary) -> void: pass
