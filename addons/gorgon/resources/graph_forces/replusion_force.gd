## Physical force that repels ALL atoms from each other,
## regardless of whether they belong to a hub (hubs only affect gravity, not repulsion).
##
## neighbor_force is recorded ONLY when there is physical overlap, so that atoms in
## equilibrium (balanced repulsion, no movement) remain at rest and do not vibrate.
## Dragged atoms naturally awaken their neighbors through overlap when they enter the radius.
class_name GraphRepulsionForce extends GraphForce

@export var repulsion_strength: float = 8000.0 ## Power of the "magnetic" push between atoms.
@export var min_distance: float = 1.0          ## Protection against zero distance.
@export var calm_distance: float = 180.0       ## The distance at which the repulsive force begins to weaken.
@export var max_distance: float = 400.0        ## Atoms located beyond this range ignore each other.
@export var overlap_hardness: float = 10.0     ## The intensity of the collision when atoms physically overlap.

func apply_force(registry: Array, forces: Array, context: Dictionary) -> void:
	var centers: Array[Vector2] = context["centers"]
	var scales: Array[float] = context["scales"]
	var radii: Array[float] = context["radii"]
	var spatial_grid: Dictionary = context["spatial_grid"]

	
	for cell_coords in spatial_grid: 
		for index_a in spatial_grid[cell_coords]:
			
			for offset_x in range(-1, 2):
				for offset_y in range(-1, 2):
					
					var neighbor_cell = cell_coords + Vector2i(offset_x, offset_y)
					if not spatial_grid.has(neighbor_cell): continue
					
					for index_b in spatial_grid[neighbor_cell]:
						
						if index_a <= index_b: continue
						
						if registry[index_a].is_cold and registry[index_b].is_cold: continue
						
						var average_scale = (scales[index_a] + scales[index_b]) * 0.5
						var difference_vector = centers[index_a] - centers[index_b]
						var distance_squared = difference_vector.length_squared()
						
						var max_effective_distance = max_distance * average_scale
						if distance_squared > (max_effective_distance * max_effective_distance): continue
						
						var distance = maxf(sqrt(distance_squared), min_distance)
						var logical_distance = distance / average_scale
						var combined_radii = radii[index_a] + radii[index_b]
						
						var overlap_coefficient = 1.0
						if logical_distance < combined_radii:
							var overlap_depth = (combined_radii - logical_distance) / maxf(combined_radii, 1.0)
							overlap_coefficient = 1.0 + overlap_depth * overlap_hardness
						
						var calm_coefficient = 1.0
						if overlap_coefficient <= 1.0 and logical_distance > calm_distance:
							calm_coefficient = 1.0 - smoothstep(calm_distance, max_distance, logical_distance)
						
						var force_magnitude = (repulsion_strength * overlap_coefficient * calm_coefficient) / (logical_distance * logical_distance + 10.0)
						
						var force_vector = (difference_vector / distance) * (force_magnitude * average_scale)
						
						forces[index_a] += force_vector
						forces[index_b] -= force_vector

func calculate_mass(registry: Array, masses: Array, context: Dictionary) -> void: pass
