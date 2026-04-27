@tool
## The central controller for the node-based graph system.
##
## Manages physics simulation, atom registration, input handling, 
## selection/navigation, and line rendering between atoms.
class_name Graph extends Control

class AtomContext:
	var atom: Atom
	var gravity_target_node: Control ## Current gravity pivot (Hub or Graph)
	var is_in_hub: bool = false      ## Flag indicating whether the atom is in a subgroup
	var index: int = -1              ## Position in the flat arrays for fast access (0, 1, 2...).
	var temperature: float = 0.0     ## How long the atom has been sitting still (used for sleep logic).
	var is_cold: bool = false        ## If true, the atom is "sleeping" and physics calculations are skipped.
	
	func _init(atom: Atom, gravity_target_node: Control, is_in_hub: bool):
		self.atom = atom
		self.gravity_target_node = gravity_target_node
		self.is_in_hub = is_in_hub

## Modes
enum SelectionMode { OFF, SOLO, MULTIPLE }
enum FocusSystem { MEDUSA, GODOT}
enum HighlightMode { OFF, HOVER_ONLY, FOCUS_ONLY, HOVER_AND_FOCUS }
enum ConnectionDir { ANY, INBOUND, OUTBOUND }

## Selection
var _selected_atoms: Array[Atom] = []      ## Collection of all selected atoms.
var _focused_atom: Atom = null             ## The primary active atom (the last one clicked).
var _hovered_atom: Atom = null             ## The atom currently under the mouse cursor.
var _current_highlight_source: Atom = null ## Atom triggering the current highlight
var _highlight_update_queued: bool = false ## Thread-safe/performance flag for UI updates

var _drag_leader: Atom = null              ## The atom that we are now dragging
var _drag_group_offsets: Dictionary = {}   ## [Atom: Vector2] of selected atoms relative to the drag leader.

## Registry
# Physics
var _atom_contexts: Array[AtomContext] = []    ## List of all managed atoms      
var _atom_to_index: Dictionary = {}            ## Fast index search: [Atom : Atom_index_in_Arrays]  
var _physics_context: Dictionary = {}          ## General data for Force objects (delta, center, atoms index mao)
var _forces: Array[Vector2] = []               ## Power accumulator (force-battery before use)
var _masses: Array[float] = []                 ## Atomic masses for inertia calculations

# Physics geometry cache
var _ctx_centers: Array[Vector2] = []  ## [Physics Cache] Pre-calculated world positions of all atoms.
var _ctx_scales: Array[float] = []     ## [Physics Cache] World scale factors to adjust forces.
var _ctx_radii: Array[float] = []      ## [Physics Cache] Current collision radii of atoms.
var _spatial_grid: Dictionary = {}     ## [Optimization] A grid map used to quickly find the nearest atoms

# Connections and search
var _id_registry: Dictionary = {}    ## [StringName : Array[Atom]] - Search for all instances of the ref
var _tag_registry: Dictionary = {}   ## [StringName : Array[Atom]] - Search atoms by tag
var _children_map: Dictionary = {}   ## [Atom : Array[Atom]] - To whom does the atom give connection?
var _parents_map: Dictionary = {}    ## [Atom : Array[Atom]] - From whom did this atom get connection?

# Draw Cache for rendering optimization
var _line_render_params: Dictionary = {}   ## Reusable param container for GraphLine in draw
var _draw_positions: Array[Vector2] = []   ## [Render Cache] Center points of atoms in local graph coordinates.
var _draw_radii: Array[float] = []         ## [Render Cache] Visual radii for line starting and ending points.
var _draw_alphas: Array[float] = []        ## [Render Cache] Transparency values for fading lines.
var _draw_is_highlighted: Array[bool] = [] ## [Render Cache] Flags to identify which lines should be glowing/bright.

## Const
const CURSOR_Z_INDEX = 100

@export var physics_enabled: bool = true         ## Turns graph physics on or off.
@export var graph_lines: GraphLine               ## Visual style for the lines connecting atoms.
@export var graph_logics: Array[GraphLogic] = [] ## List of custom rules for atom behavior.

@export_group("Input Control")
@export var drag_input: bool = true             ## Allows players to drag atoms with the mouse.
@export var atom_click_input: bool = true       ## Allows players to click on atoms to select them.
@export var background_click_input: bool = true ## Clicking empty space clears the selection.
@export var multi_drag_enabled: bool = true     ## Allows dragging multiple selected atoms at the same time.

@export_group("Boundary & Grid")
enum BoundaryShape { NONE, RECTANGLE, ELLIPSE }
@export var boundary_shape: BoundaryShape = BoundaryShape.NONE
@export var boundary_margin: float = 10.0        ## Distance from the boundary edge where atoms stop.
@export var use_grid_snap: bool = false          ## Makes atoms snap to a grid when dragged manually.
@export var grid_size: Vector2 = Vector2(64, 64)

@export_category("Selection & Navigation")
@export var focus_system: FocusSystem = FocusSystem.MEDUSA        ## Chooses between Godot's built-in UI focus or custom Medusa focus.
@export var initial_focus_atom: Atom                              ## The atom selected by default when the game starts.
@export var selection_mode: SelectionMode = SelectionMode.SOLO
@export var multi_select_action: String = "graph_multi_selection" ## Input action button (like "Shift") used to select multiple atoms.

@export_category("Physics")
@export var physics_forces: Array[GraphForce] = [] ## List of forces (like gravity or repulsion) that push atoms around.
@export var max_speed: float = 25.0
@export var friction: float = 0.90            ## Resistance to movement. (0 = no friction, 1 = instant stop).
@export var sleep_treshhold: float = 0.33     ## Speed limit. If an atom moves slower than this, it starts to fall asleep.
@export var sleep_delay: float = 0.5          ## Time in seconds. How long an atom must be slow before it completely stops.
@export var spatial_grid_size: float = 400.0  ## Optimization grid size. Should be close to the maximum distance of your forces.
@export var heat_wake_radius: float = 350.0   ## "Heat" radius. Moving atoms will wake up sleeping neighbors within this distance.
@export var draw_sleep_system_enable: bool = false ## Optimization tool. If enabled, the draw function will not run continuously, but only in response to explicit internal calls (try it with animated lines to see the effect). When disabled, draw will be called at a fixed runtime interval, which can be critical for performance with particularly complex lines.

@export_category("Highlight")
@export var highlight_mode: HighlightMode = HighlightMode.HOVER_AND_FOCUS
@export var dim_opacity: float = 0.25         ## How transparent unselected atoms become when highlighting is active.
@export var highlight_line_color: Color = Color(0.8, 1.0, 0.4, 1.0)
@export var colorize_highlighted_lines: bool = true
@export var highlight_pattern: HighlightPattern = HighlightAncestors.new()


## Activates the atom's physics and resets its sleep timer.
func wake_up_atom(atom: Atom):
	var idx = _atom_to_index.get(atom, -1)
	if idx != -1:
		_atom_contexts[idx].is_cold = false
		_atom_contexts[idx].temperature = 0.0

## Creates a one-way physical and logical connection between atoms.
## The function works “surgically.” It does not rebuild the graph registry from scratch or clear the old atom cache, but adds new entries pointwise in O(1) time. 
## This is critically important to ensure that when new connections are added at runtime, the target atom does not accidentally “forget” its old parents.
func connect_atoms(source: Atom, target: Atom):
	if not is_instance_valid(source) or not is_instance_valid(target): return
	source.connect_to(target)
	
	if not _children_map.has(source): _children_map[source] = []
	if not target in _children_map[source]: _children_map[source].append(target)
	if not _parents_map.has(target): _parents_map[target] = []
	if not source in _parents_map[target]: _parents_map[target].append(source)

## Breaks the existing one-way connection between atoms
## Like connect_atoms, it works selectively, safely removing only a specific line.
func disconnect_atoms(source: Atom, target: Atom) -> void:
	if not is_instance_valid(source) or not is_instance_valid(target): return
	source.disconnect_from(target)
	
	if _children_map.has(source): _children_map[source].erase(target)
	if _parents_map.has(target): _parents_map[target].erase(source)

## Returns all atoms on the scene with the specified resource ID
func get_atoms_by_id(id: StringName) -> Array[Atom]:
	var result: Array[Atom] = []; result.assign(_id_registry.get(id, [])); return result

## Returns all atoms with the specified tag
func get_atoms_by_tag(tag: StringName) -> Array[Atom]:
	var result: Array[Atom] = []; result.assign(_tag_registry.get(tag, [])); return result

## Returns all neighbors of an atom (instantly, without calculations)
func get_atom_neighbors(atom: Atom, dir: ConnectionDir = ConnectionDir.ANY) -> Array[Atom]:
	var result: Array[Atom] = []
	
	if dir == ConnectionDir.ANY or dir == ConnectionDir.OUTBOUND:
		result.append_array(_children_map.get(atom, []))
	
	if dir == ConnectionDir.ANY or dir == ConnectionDir.INBOUND:
		for parent in _parents_map.get(atom, []):
			if not parent in result: result.append(parent)
	return result

func get_all_atoms() -> Array[Atom]:
	var result: Array[Atom] = []
	for ctx in _atom_contexts:
		if is_instance_valid(ctx.atom): result.append(ctx.atom)
	return result

func get_atom_parents(atom: Atom) -> Array[Atom]:
	var result: Array[Atom] = []
	for parent in _parents_map.get(atom, []):
		if not parent in result: result.append(parent)
	return result

func get_atom_children(atom: Atom) -> Array[Atom]:
	var result: Array[Atom] = []
	for child in _children_map.get(atom, []):
		if not child in result: result.append(child)
	return result

signal atom_selected(atom: Atom)
signal atom_deselected(atom: Atom)
signal atom_unlocked(atom: Atom)
signal atom_hovered(atom: Atom)
signal atom_unhovered(atom: Atom)

## Forces a position to stay strictly inside the graph's borders.
func constrain_to_boundaries(atom: Atom, target_global_pos: Vector2) -> Vector2:
	if boundary_shape == BoundaryShape.NONE: return target_global_pos
	
	var atom_scale = atom.get_global_transform().get_scale().x
	var atom_radius = atom.get_effective_radius() * atom_scale
	var total_margin = boundary_margin + atom_radius
	
	var atom_center_global = target_global_pos + (atom.pivot_offset * atom_scale)
	
	var graph_transform = get_global_transform()
	var local_pos = graph_transform.affine_inverse() * atom_center_global
	var clamped_local = local_pos
	
	if boundary_shape == BoundaryShape.RECTANGLE:
		var max_x = max(0.1, size.x - total_margin)
		var max_y = max(0.1, size.y - total_margin)
		clamped_local.x = clamp(local_pos.x, total_margin, max_x)
		clamped_local.y = clamp(local_pos.y, total_margin, max_y)
	elif boundary_shape == BoundaryShape.ELLIPSE:
		var center = size / 2.0
		var offset = local_pos - center
		
		var a = max(0.1, (size.x / 2.0) - total_margin)
		var b = max(0.1, (size.y / 2.0) - total_margin)
		
		var normalized_x = offset.x / a
		var normalized_y = offset.y / b
		var dist_squared = (normalized_x * normalized_x) + (normalized_y * normalized_y)
		
		if dist_squared > 1.0:
			var scale_vec = Vector2(a, b)
			var dir = (offset / scale_vec).normalized()
			clamped_local = center + (dir * scale_vec)
	var clamped_global_center = graph_transform * clamped_local
	return clamped_global_center - (atom.pivot_offset * atom_scale)

## Aligns a position to the nearest grid point.
func snap_node_to_grid(node: Control, target_global_pos: Vector2) -> Vector2:
	if not use_grid_snap or grid_size == Vector2.ZERO: return target_global_pos
	
	var global_scale = node.get_global_transform().get_scale()
	var center = target_global_pos + (node.pivot_offset * global_scale)
	var snapped_center = (center / grid_size).round() * grid_size
	return snapped_center - (node.pivot_offset * global_scale)

## Adds an atom as a child to the hub/graph.
func add_atom(atom: Atom, parent: Node = null) -> void:
	assert(atom != null, "Atom cannot be null")
	if not parent: parent = self as Graph
	parent.add_child(atom)
	_register_atom(atom, find_parent_hub(atom))

## Deletes the atom and safely removes all its connections and registry data.
func remove_atom(atom: Atom) -> void:
	if not is_instance_valid(atom): return
	
	if _focused_atom == atom: _focused_atom = null
	if _hovered_atom == atom: _hovered_atom = null
	if _current_highlight_source == atom: _current_highlight_source = null
	if _drag_leader == atom: _drag_leader = null
	
	if atom in _selected_atoms: _remove_from_selection(atom)
	
	_unregister_atom(atom)
	_update_highlights()
	atom.queue_free()

func add_branch(branch: GraphBranch, parent: Node = null) -> void:
	if not parent: parent = self
	parent.add_child(branch)
	_scan_branch(branch, branch)

func remove_branch(branch: GraphBranch) -> void:
	if not is_instance_valid(branch): return
	var atoms_to_remove = []
	for ctx in _atom_contexts:
		if ctx.gravity_target_node == branch or branch.is_ancestor_of(ctx.atom): atoms_to_remove.append(ctx.atom)
	for atom in atoms_to_remove: 
		_unregister_atom(atom)
	branch.queue_free()

func find_parent_hub(node: Node) -> GraphBranch:
	var parent = node.get_parent()
	while parent and parent != self:
		if parent is GraphBranch and parent.physics_enabled: return parent
		parent = parent.get_parent()
	return null


## Instantly updates the entire graph's visuals based on the graph logics
func sync_with_logic() -> void:
	for ctx in _atom_contexts:
		var atom = ctx.atom
		if not is_instance_valid(atom): continue
		for logic in graph_logics:
			if logic:
				var next = logic.apply_status(atom, self)
				if not next: break

## selects the first atom
func select_initial_atom():
	if not _atom_contexts.is_empty(): select_atom(_atom_contexts[0].atom)

## The main method for selecting an atom. If null is passed, the selection will be reset. Can force the 'multiple' selection method 
func select_atom(atom: Atom, force_append: bool = false):
	if selection_mode == SelectionMode.OFF: return
	var is_multi_action = force_append or (Input.is_action_pressed(multi_select_action) and multi_select_action != "")
	
	if atom == null:
		_clear_selection()
		if focus_system == FocusSystem.GODOT: get_viewport().gui_release_focus()
		return
	
	if selection_mode == SelectionMode.SOLO or (selection_mode == SelectionMode.MULTIPLE and not is_multi_action):
		if _selected_atoms.size() == 1 and _selected_atoms[0] == atom: return 
		_clear_selection()
		_add_to_selection(atom)
	
	elif (selection_mode == SelectionMode.MULTIPLE) and is_multi_action:
		if atom in _selected_atoms: _remove_from_selection(atom)
		else: _add_to_selection(atom)

## Moves focus to the adjacent atom (used for keyboard navigation)
func select_neighbor(next_atom: Atom) -> void:
	if next_atom.block_focus: return
	var is_multi = Input.is_action_pressed(multi_select_action) and multi_select_action != ""
	if not is_multi: _clear_selection()
	_add_to_selection(next_atom)

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not Engine.is_editor_hint(): 
		if initial_focus_atom: select_atom(initial_focus_atom)
	_update_graph_registry()
	_physics_context["atoms_index_map"] = _atom_to_index


## Fully rebuilds the internal lists and connections of all atoms from scratch.
func _update_graph_registry():
	_atom_contexts.clear()
	_atom_to_index.clear()
	_forces.clear()
	_masses.clear()
	
	_id_registry.clear()
	_tag_registry.clear()
	_children_map.clear()
	_parents_map.clear()
	
	_ctx_centers.clear()
	_ctx_scales.clear()
	_ctx_radii.clear()
	
	_draw_positions.clear()
	_draw_radii.clear()
	_draw_alphas.clear()
	_draw_is_highlighted.clear()
	_scan_branch(self, null)

## 	Recursively searches through the node tree to find and register atoms and hubs.
func _scan_branch(node: Node, active_hub: GraphBranch):
	for child: Node in node.get_children():
		if child is GraphBranch: _scan_branch(child, child if child.physics_enabled else active_hub)
		elif child is Atom: _register_atom(child, active_hub)

## 	Adds an atom to the physics engine, saves its data, and connects its input signals.
func _register_atom(atom: Atom, hub: GraphBranch):
	var context = AtomContext.new(atom, hub if hub else self, hub != null)
	context.index = _atom_contexts.size()
	context.is_cold = false
	_atom_contexts.append(context)
	_atom_to_index[atom] = context.index 
	_forces.append(Vector2.ZERO)
	_masses.append(1.0)
	
	_ctx_centers.append(Vector2.ZERO)
	_ctx_scales.append(1.0)
	_ctx_radii.append(atom.get_effective_radius())
	
	_draw_positions.append(Vector2.ZERO)
	_draw_radii.append(0.0)
	_draw_alphas.append(1.0)
	_draw_is_highlighted.append(false)
	
	_add_atom_to_indexes(atom)
	
	if not Engine.is_editor_hint():
		atom.setup_focus_system(focus_system)
		if not atom.clicked.is_connected(_on_atom_clicked): atom.clicked.connect(_on_atom_clicked)
		if not atom.unlocked.is_connected(_on_atom_unlocked): atom.unlocked.connect(_on_atom_unlocked)
		if not atom.godot_focus_gained.is_connected(_on_atom_godot_focus_gained): atom.godot_focus_gained.connect(_on_atom_godot_focus_gained)
		if not atom.mouse_entered.is_connected(_on_atom_hovered.bind(atom)): atom.mouse_entered.connect(_on_atom_hovered.bind(atom))
		if not atom.mouse_exited.is_connected(_on_atom_unhovered.bind(atom)): atom.mouse_exited.connect(_on_atom_unhovered.bind(atom))
		if not atom.drag_started.is_connected(_on_atom_drag_started): atom.drag_started.connect(_on_atom_drag_started)
		if not atom.drag_ended.is_connected(_on_atom_drag_ended): atom.drag_ended.connect(_on_atom_drag_ended)

## Safely removes an atom, disconnects its signals, and cleans up broken links in other atoms.
func _unregister_atom(atom: Atom):
	if atom.clicked.is_connected(_on_atom_clicked): atom.clicked.disconnect(_on_atom_clicked)
	if atom.unlocked.is_connected(_on_atom_unlocked): atom.unlocked.disconnect(_on_atom_unlocked)
	if atom.godot_focus_gained.is_connected(_on_atom_godot_focus_gained): atom.godot_focus_gained.disconnect(_on_atom_godot_focus_gained)
	if atom.mouse_entered.is_connected(_on_atom_hovered): atom.mouse_entered.disconnect(_on_atom_hovered)
	if atom.mouse_exited.is_connected(_on_atom_unhovered): atom.mouse_exited.disconnect(_on_atom_unhovered)
	if atom.drag_started.is_connected(_on_atom_drag_started): atom.drag_started.disconnect(_on_atom_drag_started)
	if atom.drag_ended.is_connected(_on_atom_drag_ended): atom.drag_ended.disconnect(_on_atom_drag_ended)
	
	for ctx in _atom_contexts:
		var other_atom = ctx.atom
		if other_atom == atom or not is_instance_valid(other_atom): continue
		if atom in other_atom.connected_atoms: other_atom.connected_atoms.erase(atom)
		for action in other_atom.navigation_map.keys(): if other_atom.navigation_map[action] == atom: other_atom.navigation_map.erase(action)
	
	for i in range(_atom_contexts.size() - 1, -1, -1):
		if _atom_contexts[i].atom == atom:
			_atom_contexts.remove_at(i)
			_atom_to_index.erase(atom)
			_forces.remove_at(i)
			_masses.remove_at(i)
			
			_ctx_centers.remove_at(i)
			_ctx_scales.remove_at(i)
			_ctx_radii.remove_at(i)
			
			_draw_positions.remove_at(i)
			_draw_radii.remove_at(i)
			_draw_alphas.remove_at(i)
			_draw_is_highlighted.remove_at(i)
			
			for j in range(i, _atom_contexts.size()): 
				_atom_contexts[j].index = j
				_atom_to_index[_atom_contexts[j].atom] = j
			break
	_remove_atom_from_indexes(atom)

## Sorts the atom into search dictionaries (by ID, tags, and connections) for instant lookup.
func _add_atom_to_indexes(atom: Atom) -> void:
	if not is_instance_valid(atom): return
	
	var id = atom.id
	if id != &"":
		if not _id_registry.has(id): _id_registry[id] = []
		if not atom in _id_registry[id]: _id_registry[id].append(atom)
	for tag in atom.tags:
		if not _tag_registry.has(tag): _tag_registry[tag] = []
		if not atom in _tag_registry[tag]: _tag_registry[tag].append(atom)
	
	if not _children_map.has(atom): _children_map[atom] = []
	if not _parents_map.has(atom): _parents_map[atom] = []
	
	for child in atom.connected_atoms:
		if is_instance_valid(child): 
			if not child in _children_map[atom]: _children_map[atom].append(child)
			if not _parents_map.has(child): _parents_map[child] = []
			if not atom in _parents_map[child]: _parents_map[child].append(atom)

## Removes the atom from all search dictionaries and clears its relationship maps.
func _remove_atom_from_indexes(atom: Atom) -> void:
	var id = atom.id
	if id != &"" and _id_registry.has(id):
		_id_registry[id].erase(atom)
		if _id_registry[id].is_empty(): _id_registry.erase(id)
	for tag in atom.data.tags:
		if _tag_registry.has(tag):
			_tag_registry[tag].erase(atom)
			if _tag_registry[tag].is_empty(): _tag_registry.erase(tag)
	
	if _children_map.has(atom):
		for child in _children_map[atom]:
			if _parents_map.has(child): _parents_map[child].erase(atom)
		_children_map.erase(atom)
	
	if _parents_map.has(atom):
		for parent in _parents_map[atom]:
			if _children_map.has(parent): _children_map[parent].erase(atom)
		_parents_map.erase(atom)


func _process(delta):
	if draw_sleep_system_enable:
		var any_awake = false
		for ctx in _atom_contexts:
			if not ctx.is_cold or ctx.atom.is_dragging: any_awake = true; break
		if any_awake: queue_redraw()
	else:
		queue_redraw()
	
	if not Engine.is_editor_hint():
		if is_instance_valid(_drag_leader):
			for follower in _drag_group_offsets:
				if not is_instance_valid(follower): continue
				var offset = _drag_group_offsets[follower]
				var target_pos = _drag_leader.global_position + offset
				target_pos = snap_node_to_grid(follower, target_pos)
				follower.global_position = constrain_to_boundaries(follower, target_pos)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not physics_enabled: return
	
	var count = _atom_contexts.size()
	for i in range(count):
		var ctx = _atom_contexts[i]
		var atom = ctx.atom
		var parent_transform = atom.get_parent().get_global_transform()
		var ps = parent_transform.get_scale()
		var target_r = atom.get_effective_radius()
		
		if abs(_ctx_radii[i] - target_r) < 0.05: _ctx_radii[i] = target_r
		else: _ctx_radii[i] = lerpf(_ctx_radii[i], target_r, 0.1)
			
		_ctx_scales[i] = (ps.x + ps.y) * 0.5
		_ctx_centers[i] = parent_transform * (atom.position + atom.pivot_offset)
	
	for key in _spatial_grid.keys(): _spatial_grid[key].clear()
	for i in range(count):
		var cell = Vector2i((_ctx_centers[i] / spatial_grid_size).floor())
		
		if not _spatial_grid.has(cell): _spatial_grid[cell] = []
		_spatial_grid[cell].append(i)
	
	_forces.fill(Vector2.ZERO)
	_masses.fill(1.0)
	
	_physics_context["global_center"] = get_global_rect().get_center()
	_physics_context["delta"] = delta
	_physics_context["spatial_grid"] = _spatial_grid
	_physics_context["centers"] = _ctx_centers
	_physics_context["scales"] = _ctx_scales
	_physics_context["radii"] = _ctx_radii
	
	_apply_spatial_heat(_spatial_grid)
	
	for force in physics_forces: if force: force.calculate_mass(_atom_contexts, _masses, _physics_context)
	for force in physics_forces: if force: force.apply_force(_atom_contexts, _forces, _physics_context)
	
	for ctx in _atom_contexts:
		var atom = ctx.atom
		if atom.is_static or atom.is_dragging or ctx.is_cold: continue
		
		var i = ctx.index
		var parent_transform = atom.get_parent().get_global_transform()
		var local_force = parent_transform.affine_inverse().basis_xform(_forces[i])
		
		atom.velocity += local_force / _masses[i]
		atom.velocity *= friction
		if max_speed > 0: atom.velocity = atom.velocity.limit_length(max_speed)
		
		if atom.velocity.length_squared() < sleep_treshhold * sleep_treshhold:
			atom.velocity = Vector2.ZERO
			ctx.temperature += delta
			if ctx.temperature >= sleep_delay: ctx.is_cold = true
		else:
			ctx.temperature = 0.0
			atom.position += atom.velocity
			
			if boundary_shape != BoundaryShape.NONE:
				var constrained = constrain_to_boundaries(atom, atom.global_position)
				if not atom.global_position.is_equal_approx(constrained):
					var old_pos = atom.global_position
					atom.global_position = constrained
					atom.velocity = parent_transform.affine_inverse().basis_xform(atom.global_position - old_pos)

## Wakes up atoms that are next to heated or dragged atoms
func _apply_spatial_heat(grid: Dictionary) -> void:
	var wake_sq = heat_wake_radius * heat_wake_radius
	var wake_speed_sq = (sleep_treshhold * 2.0) * (sleep_treshhold * 2.0)
	
	for i in range(_atom_contexts.size()):
		var ctx = _atom_contexts[i]
		var atom = ctx.atom
		
		var is_hot = atom.is_dragging or atom.velocity.length_squared() > wake_speed_sq
		
		if is_hot:
			ctx.is_cold = false
			ctx.temperature = 0.0
			
			var cell = Vector2i((_ctx_centers[i] / spatial_grid_size).floor())
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					var ncell = cell + Vector2i(dx, dy)
					if not grid.has(ncell): continue
					
					for j in grid[ncell]:
						if i == j or not _atom_contexts[j].is_cold: continue
						
						var dist_sq = _ctx_centers[i].distance_squared_to(_ctx_centers[j])
						if dist_sq < wake_sq * _ctx_scales[j]:
							_atom_contexts[j].is_cold = false
							_atom_contexts[j].temperature = 0.0
		
		if not ctx.is_cold:
			for connected in atom.connected_atoms:
				var c_idx = _atom_to_index.get(connected, -1)
				if c_idx != -1 and _atom_contexts[c_idx].is_cold:
					_atom_contexts[c_idx].is_cold = false
					_atom_contexts[c_idx].temperature = 0.0

func _draw():
	if Engine.is_editor_hint() and boundary_shape != BoundaryShape.NONE: _draw_boundaries()
	if _atom_contexts.is_empty(): return
	
	var inverse_transform = get_global_transform().affine_inverse()
	var hl_source = _current_highlight_source if highlight_mode != HighlightMode.OFF else null
	
	if _draw_positions.size() != _atom_contexts.size(): return
	for ctx in _atom_contexts:
		var atom = ctx.atom
		if not is_instance_valid(atom): continue
		var i = ctx.index
		var atom_global_scale = atom.get_global_transform().get_scale().x
		var graph_global_scale = get_global_transform().get_scale().x
		_draw_positions[i] = inverse_transform * (atom.global_position + atom.pivot_offset * atom_global_scale)
		_draw_radii[i] = _ctx_radii[i] * atom_global_scale / graph_global_scale
		_draw_alphas[i] = atom.modulate.a
		#_draw_is_highlighted[i] = (atom == hl_source)
	
	for ctx in _atom_contexts:
		var node_a = ctx.atom
		if not is_instance_valid(node_a): continue
		var i = ctx.index
		var pos_a = _draw_positions[i]
		var id_a = node_a.get_instance_id()
		var style: GraphLine = graph_lines
		if not style: continue
		
		for node_b in node_a.connected_atoms:
			if not is_instance_valid(node_b): continue
			var idx_b = _atom_to_index.get(node_b, -1)
			if idx_b == -1: continue
			
			var is_primary = id_a < node_b.get_instance_id()
			var is_conn_mutual = node_a in node_b.connected_atoms

			var nav_fw = false
			for act in node_a.navigation_map:
				if node_a.navigation_map[act] == node_b: nav_fw = true; break
			var nav_bw = false
			for act in node_b.navigation_map:
				if node_b.navigation_map[act] == node_a: nav_bw = true; break
			
			var pair_has_nav = nav_fw or nav_bw
			var pair_has_conn = true
			
			_draw_line_between(style, i, idx_b, pos_a, true, nav_fw, is_conn_mutual, (nav_fw and nav_bw), is_primary, pair_has_conn, pair_has_nav)
		
		for action in node_a.navigation_map:
			var node_b = node_a.navigation_map[action]
			if not is_instance_valid(node_b): continue
			if node_b in node_a.connected_atoms: continue 
			
			var idx_b = _atom_to_index.get(node_b, -1)
			if idx_b == -1: continue
			
			var is_primary = id_a < node_b.get_instance_id()
			var nav_mutual = false
			for act in node_b.navigation_map:
				if node_b.navigation_map[act] == node_a: nav_mutual = true; break
			
			var conn_fw = node_b in node_a.connected_atoms
			var conn_bw = node_a in node_b.connected_atoms
			var pair_has_conn = conn_fw or conn_bw
			var pair_has_nav = true
			
			_draw_line_between(style, i, idx_b, pos_a, false, true, false, nav_mutual, is_primary, pair_has_conn, pair_has_nav)

func _draw_line_between(style: GraphLine, i: int, j: int, pos_a: Vector2, has_conn: bool, has_nav: bool, conn_mutual: bool, nav_mutual: bool, is_primary: bool, pair_has_conn: bool, pair_has_nav: bool):
	var pos_b = _draw_positions[j]
	var direction = (pos_b - pos_a).normalized()
	var line_start = pos_a + direction * _draw_radii[i]
	var line_end    = pos_b - direction * _draw_radii[j]

	var alpha = minf(_draw_alphas[i], _draw_alphas[j])
	var is_hl = _draw_is_highlighted[i] and _draw_is_highlighted[j]

	_line_render_params.connection = has_conn
	_line_render_params.navigation = has_nav
	_line_render_params.conn_mutual = conn_mutual
	_line_render_params.nav_mutual = nav_mutual
	_line_render_params.is_primary = is_primary
	_line_render_params.alpha = alpha
	_line_render_params.highlighted = is_hl
	_line_render_params.colorize_highlighted_lines = colorize_highlighted_lines
	_line_render_params.highlight_color = highlight_line_color
	
	_line_render_params.pair_has_conn = pair_has_conn
	_line_render_params.pair_has_nav = pair_has_nav

	style.draw(self, line_start, line_end, _line_render_params)

func _draw_boundaries():
	var color = Color(0.2, 0.9, 0.4, 0.8)
	var center_color = Color(0.8, 1.0, 0.4)
	var center = size / 2.0

	if boundary_shape == BoundaryShape.RECTANGLE:
		var margin_vector = Vector2(boundary_margin, boundary_margin)
		var rect = Rect2(margin_vector, size - margin_vector * 2)
		draw_rect(rect, color, false, 2.0)
		
	elif boundary_shape == BoundaryShape.ELLIPSE:
		var radius_x = (size.x / 2.0) - boundary_margin
		var radius_y = (size.y / 2.0) - boundary_margin
		
		var points = PackedVector2Array()
		var steps = 64
		for i in range(steps + 1):
			var angle = (float(i) / steps) * TAU
			var px = center.x + cos(angle) * radius_x
			var py = center.y + sin(angle) * radius_y
			points.append(Vector2(px, py))
		draw_polyline(points, color, 2.0)
	var size_px = 12.0 
	draw_line(center - Vector2(size_px, 0), center + Vector2(size_px, 0), center_color, 2.0)
	draw_line(center - Vector2(0, size_px), center + Vector2(0, size_px), center_color, 2.0)
	draw_circle(center, 2.0, center_color)


func _gui_input(event: InputEvent) -> void:
	if Engine.is_editor_hint(): return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if background_click_input: select_atom(null);  accept_event()

func _unhandled_input(event: InputEvent) -> void:
	## CHECK
	if Engine.is_editor_hint() or selection_mode == SelectionMode.OFF: return
	if not is_instance_valid(_focused_atom): return
	if focus_system == FocusSystem.GODOT: return
	
	## MEDUSA
	if not event.is_pressed() or event.is_echo(): return
	for action: StringName in _focused_atom.navigation_map:
		if event.is_action_pressed(action):
			var target: Atom = _focused_atom.navigation_map[action]
			if is_instance_valid(target) and not target.block_focus:
				select_neighbor(target)
				get_viewport().set_input_as_handled()
				break


func _add_to_selection(atom: Atom):
	if atom in _selected_atoms: _focused_atom = atom; return
	_selected_atoms.append(atom)
	atom.is_selected = true
	_focused_atom = atom
	atom_selected.emit(atom)
	_update_highlights()

func _remove_from_selection(atom: Atom):
	_selected_atoms.erase(atom)
	atom.is_selected = false
	if _focused_atom == atom:
		_focused_atom = _selected_atoms.back() if not _selected_atoms.is_empty() else null
	atom_deselected.emit(atom)

func _clear_selection():
	for atom in _selected_atoms:
		if is_instance_valid(atom):
			atom.is_selected = false
			atom_deselected.emit(atom)
	_selected_atoms.clear()
	_focused_atom = null
	_update_highlights()


func _update_highlights():
	if highlight_mode == HighlightMode.OFF or Engine.is_editor_hint(): return
	if _highlight_update_queued: return
	_highlight_update_queued = true
	call_deferred("_apply_highlights")

func _apply_highlights():
	_highlight_update_queued = false
	_current_highlight_source = null
	
	match highlight_mode:
		HighlightMode.HOVER_ONLY:
			_current_highlight_source = _hovered_atom
		HighlightMode.FOCUS_ONLY:
			if is_instance_valid(_focused_atom): _current_highlight_source = _focused_atom
		HighlightMode.HOVER_AND_FOCUS:
			if _hovered_atom: _current_highlight_source = _hovered_atom
			else: _current_highlight_source = _focused_atom
		
	if highlight_pattern:
		var highlightedAtoms : Array[Atom] = highlight_pattern.apply_highlights(self, _current_highlight_source, dim_opacity)
		for ctx in _atom_contexts:
			_draw_is_highlighted[ctx.index] = true if ctx.atom in highlightedAtoms else false

## Smart connection verification (takes into account both physics and navigation)
func _is_atom_connected(node_a: Atom, node_b: Atom) -> bool:
	if node_a == node_b: return true
	if node_a in node_b.connected_atoms or node_b in node_a.connected_atoms: return true # Связи/Наивгация
	
	for action in node_a.navigation_map: if node_a.navigation_map[action] == node_b: return true
	for action in node_b.navigation_map: if node_b.navigation_map[action] == node_a: return true
	return false

## Selects the atom when the player clicks on it.
func _on_atom_clicked(atom: Atom):
	if not atom_click_input: return
	if atom.block_focus: return
	select_atom(atom)
	if focus_system == FocusSystem.GODOT: atom.grab_focus()

## Notifies the entire graph that this specific atom was just unlocked.
func _on_atom_unlocked(atom: Atom):
	atom_unlocked.emit(atom)

## Selects the atom if it was focused using a keyboard or gamepad (ignores mouse clicks).
func _on_atom_godot_focus_gained(atom: Atom):
	var is_mouse_click = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)  or \
						 Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or \
						 Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
	if is_mouse_click: return
	select_atom(atom)

## Triggers visual highlighting and dims other atoms when the mouse enters.
func _on_atom_hovered(atom: Atom):
	_hovered_atom = atom
	atom_hovered.emit(atom)
	_update_highlights()

## Restores normal visuals when the mouse leaves the atom.
func _on_atom_unhovered(atom: Atom):
	if atom.is_dragging: return # Страховка перетаскивания
	if _hovered_atom == atom: _hovered_atom = null
	atom_unhovered.emit(atom)
	_update_highlights()

## Locks selected atoms together to move them as a group when dragging starts.
func _on_atom_drag_started(atom: Atom):
	var idx = _atom_to_index.get(atom, -1)
	if idx != -1:
		_atom_contexts[idx].is_cold = false
		_atom_contexts[idx].temperature = 0.0
	
	if not multi_drag_enabled: return
	if atom in _selected_atoms and _selected_atoms.size() > 1:
		_drag_leader = atom
		_drag_group_offsets.clear()
		
		for follower in _selected_atoms:
			if follower == _drag_leader: continue
			_drag_group_offsets[follower] = follower.global_position - _drag_leader.global_position
			
			follower.is_dragging = true
			
			var fidx = _atom_to_index.get(follower, -1)
			if fidx != -1:
				_atom_contexts[fidx].is_cold = false
				_atom_contexts[fidx].temperature = 0.0

## Drops the dragged group and restores their normal physics state.
func _on_atom_drag_ended(atom: Atom):
	if atom == _drag_leader:
		for follower in _drag_group_offsets:
			if is_instance_valid(follower):
				follower.is_dragging = false
				if not follower.is_hovered: _on_atom_unhovered(follower)
		_drag_leader = null
		_drag_group_offsets.clear()
	
	if not atom.is_hovered: _on_atom_unhovered(atom)
	else: _on_atom_hovered(atom)
