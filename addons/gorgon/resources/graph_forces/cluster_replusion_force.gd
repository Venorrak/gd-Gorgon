## A physical force that prevents different nodes (branches) from overlapping.
##
## Instead of pushing individual atoms, this force treats each branch of the graph 
## as one large object to keep them apart.
##
## Free atoms repel nodes, and nodes repel each other,
## to maintain a clean and readable layout even with dense clusters.
##
## It has a “hardness” multiplier that increases the repulsion force 
## when two clusters physically collide with each other.
class_name ClusterRepulsionForce extends GraphForce

@export var repulsion_strength: float = 120000.0  ## Force between clusters
@export var max_distance:       float = 1200.0    ## Force distance
@export var overlap_hardness:   float = 8.0       ## How much stronger when overlapping

func apply_force(registry: Array, forces: Array, context: Dictionary) -> void:
	var centers: Array[Vector2] = context["centers"]
	var scales:  Array[float]   = context["scales"]
	var atoms_count = registry.size()
	
	## Сбор данных о кластерах (группах атомов вокруг хабов)
	# Структура clusters: hub_node → { center, radius, indices[] }
	var clusters: Dictionary = {}
	
	for index in range(atoms_count):
		var item_context = registry[index]
		if not item_context.is_in_hub: continue
			
		var hub_node = item_context.gravity_target_node
		if not is_instance_valid(hub_node): continue
			
		if not clusters.has(hub_node):
			clusters[hub_node] = { 
				"center": Vector2.ZERO, 
				"sum_positions": Vector2.ZERO,
				"count": 0, 
				"radius": 0.0, 
				"indices": [] 
			}
		
		clusters[hub_node]["sum_positions"] += centers[index]
		clusters[hub_node]["count"] += 1
		clusters[hub_node]["indices"].append(index)
	
	# Вычисляем геометрический центр масс и радиус охвата для каждого кластера
	for hub_node in clusters:
		var cluster_data = clusters[hub_node]
		cluster_data["center"] = cluster_data["sum_positions"] / float(cluster_data["count"])
		
		# Радиус определяется как среднее расстояние от атомов до их общего центра масс
		var total_distance_to_center = 0.0
		for index in cluster_data["indices"]:
			total_distance_to_center += (centers[index] - cluster_data["center"]).length()
		
		# Устанавливаем минимальный радиус 50.0, чтобы кластер не схлопывался в точку
		cluster_data["radius"] = maxf(total_distance_to_center / float(cluster_data["count"]), 50.0)
	
	var active_hubs = clusters.keys()
	
	## Взаимодействие Кластер ↔ Кластер (расталкивание групп)
	for i in range(active_hubs.size()):
		var cluster_a = clusters[active_hubs[i]]
		var center_a  = cluster_a["center"]
		var radius_a  = cluster_a["radius"]
		
		for j in range(i + 1, active_hubs.size()):
			var cluster_b = clusters[active_hubs[j]]
			var center_b  = cluster_b["center"]
			var radius_b  = cluster_b["radius"]
			
			var difference = center_a - center_b
			var distance = maxf(difference.length(), 1.0)
			
			# Если кластеры слишком далеко друг от друга, расчет пропускаем
			if distance > max_distance: continue
			
			var minimum_separation = radius_a + radius_b
			var overlap_coefficient = 1.0
			
			# Если границы кластеров пересекаются, сила отталкивания резко возрастает
			if distance < minimum_separation:
				var overlap_depth = (minimum_separation - distance) / max(minimum_separation, 1.0)
				overlap_coefficient = 1.0 + overlap_depth * overlap_hardness
			
			# Расчет величины силы (закон обратных квадратов с защитой от сингулярности 200.0)
			var force_magnitude = (repulsion_strength * overlap_coefficient) / (distance * distance + 200.0)
			var direction = difference / distance
			
			# Распределяем силу по всем атомам обоих кластеров
			_push_cluster( direction * force_magnitude, cluster_a, forces, scales)
			_push_cluster(-direction * force_magnitude, cluster_b, forces, scales)
	
	## Взаимодействие Кластер ↔ Свободный атом
	for index in range(atoms_count):
		var item_context = registry[index]
		
		# Работаем только со свободными, активными и динамическими атомами
		if item_context.is_in_hub or item_context.is_cold: continue
		if item_context.atom.is_static or item_context.atom.is_dragging: continue
		
		var atom_center = centers[index]
		var world_scale = scales[index]
		
		for hub_node in active_hubs:
			var cluster_data = clusters[hub_node]
			var cluster_center = cluster_data["center"]
			var cluster_radius = cluster_data["radius"]
			
			var difference = atom_center - cluster_center
			var distance = maxf(difference.length(), 1.0)
			
			if distance > max_distance: continue
			
			var overlap_coefficient = 1.0
			# Если свободный атом залетает внутрь радиуса кластера
			if distance < cluster_radius:
				var inside_depth = (cluster_radius - distance) / max(cluster_radius, 1.0)
				overlap_coefficient = 1.0 + inside_depth * overlap_hardness * 0.5
			
			# Для свободных атомов сила значительно слабее (множитель 0.1)
			var force_magnitude = (repulsion_strength * overlap_coefficient * 0.1) / (distance * distance + 200.0)
			var direction = difference / distance
			
			# Толкаем атом от кластера и слегка подталкиваем сам кластер в обратную сторону
			forces[index] += direction * force_magnitude * world_scale
			_push_cluster(-direction * force_magnitude * 0.1, cluster_data, forces, scales)

func calculate_mass(registry: Array, masses: Array, context: Dictionary) -> void: pass

func _push_cluster(total_force: Vector2, cluster_data: Dictionary, forces: Array, scales: Array[float]) -> void:
	var member_indices: Array = cluster_data["indices"]
	if member_indices.is_empty(): return
	
	var force_per_atom = total_force / float(member_indices.size())
	
	for index in member_indices: 
		forces[index] += force_per_atom * scales[index]
