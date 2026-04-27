## Physical force that creates a rotating vortex effect around a central point.
##
## Causes atoms to move in a circle around an axis (the center of the hub or global center).
## The rotational force decreases with distance to maintain orbital stability.
class_name GraphVortexForce extends GraphForce


@export var rotation_speed: float = 5.0   ## Base intensity of rotational thrust.
@export var clockwise: bool = true        ## Direction of the vortex rotation.


func apply_force(registry: Array, forces: Array, context: Dictionary) -> void:
	var global_center: Vector2 = context["global_center"]
	var centers: Array[Vector2] = context["centers"]
	var scales: Array[float] = context["scales"]
	
	for item_context in registry:
		var index = item_context.index
		var atom = item_context.atom
		
		if atom.is_dragging or atom.is_static or item_context.is_cold: continue
		
		var world_scale = scales[index]
		var atom_center = centers[index]
		
		var pivot_point: Vector2
		if item_context.is_in_hub and is_instance_valid(item_context.gravity_target_node): pivot_point = item_context.gravity_target_node.get_gravity_center()
		else: pivot_point = global_center
		
		var radial_vector = atom_center - pivot_point
		var distance = radial_vector.length()
		
		var logical_distance = distance / world_scale
		
		if logical_distance < 20.0: continue 
		
		var tangent_direction: Vector2
		if clockwise:  tangent_direction = Vector2(-radial_vector.y, radial_vector.x) / distance
		else: tangent_direction = Vector2(radial_vector.y, -radial_vector.x) / distance
		
		var force_magnitude = (rotation_speed * 10.0) / logical_distance
		
		forces[index] += tangent_direction * (force_magnitude * world_scale)

func calculate_mass(registry: Array, masses: Array, context: Dictionary) -> void: pass
