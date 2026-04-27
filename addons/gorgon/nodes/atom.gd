@tool
class_name Atom extends Control

@export var id : StringName = &""

## Components
var click_mask: BitMap
var _texture_rect: TextureRect
var _animation_player: AnimationPlayer

## Tweens
var _alpha_tween: Tween

## Internal Physics
var _drag_offset: Vector2 = Vector2.ZERO
var _drag_start_mouse_pos: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO

## Signals
signal clicked(atom: Atom)
signal godot_focus_gained(atom: Atom)
signal drag_started(atom: Atom)
signal drag_ended(atom: Atom)
signal unlocked(atom: Atom)
signal status_changed(prevStatus: Atom.Status, newStatus: Atom.Status)

## Status
enum Status {
	LOCKED,
	AVAILABLE,
	UNLOCKED,
	HIDDEN,
	DISABLED
	}

## Internal Maps
var connected_atoms: Array[Atom] = []
var navigation_map: Dictionary[StringName, Atom] = {}

@export var childrens: Array[NodePath] = []:
	set(value): childrens = value; _update_connection_links(); _force_graph_redraw()
@export var navigation_paths: Dictionary[StringName, NodePath] = {
	&"ui_up": NodePath(""),
	&"ui_right": NodePath(""),
	&"ui_left": NodePath(""),
	&"ui_down": NodePath("")}:
	set(value): navigation_paths = value; _update_navigation_links(); _force_graph_redraw()

@export var is_static: bool = false
@export var block_focus: bool = false
@export var drag_input: bool = true
@export var drag_threshold: float = 5.0  ## Distance in pixels the mouse must move before a click turns into a drag.
@export var tags: Array[StringName] = []
@export var information: Dictionary = {}
@export var icon: Texture2D:
	set(value):
		if icon == value: return
		icon = value
		_update_icon()
		_update_size()

## priority: the higher it is on the list, the more important the state is
## check: a function that returns true if the state is active
## animation: the name of the animation for this state
var _state_registry: Array[Dictionary] = [
	{"id": "dragging", "check": func(): return is_dragging, "animation": "PRESSED"},
	{"id": "selected", "check": func(): return is_selected, "animation": "FOCUSED"},
	{"id": "hovered", "check": func(): return is_hovered, "animation": "HOVER"},
	{"id": "normal", "check": func(): return true, "animation": "NORMAL"}]:
	set(value): _state_registry = value; _update_connection_links()
var current_state_id: String

var is_selected: bool = false:
	set(value): if is_selected != value: is_selected = value; _update_state()
var is_dragging: bool = false:
	set(value): if is_dragging != value: is_dragging = value; _update_state()
var is_hovered: bool = false:
	set(value): if is_hovered != value: is_hovered = value; _update_state()

@export_category("Animation Libraries")
@export var status: Status = Status.LOCKED:
	set(value):
		if status == value: return
		status_changed.emit(status, value)
		status = value
		if status == Status.UNLOCKED: unlocked.emit(self)
		_update_visual_style()
@export var locked_animation_library: AnimationLibrary
@export var unlocked_animation_library: AnimationLibrary
@export var available_animation_library: AnimationLibrary
@export var hidden_animation_library: AnimationLibrary
@export var disabled_animation_library: AnimationLibrary



## Method for scripting atom connections (ignores NodePath and does not have access to graph registries)
func connect_to(other_atom: Atom) -> void:
	if other_atom and other_atom != self and not other_atom in connected_atoms: connected_atoms.append(other_atom)

## Method for script-based atom detachment (ignores NodePath and does not have access to graph registries)
func disconnect_from(other_atom: Atom) -> void:
	if other_atom in connected_atoms: connected_atoms.erase(other_atom)

## Returns the actual physical size
func get_effective_radius() -> float:
	return (icon.get_height() + icon.get_width()) / 4 if icon else 30 #janky

## Configures how the atom handles keyboard/gamepad navigation.
func setup_focus_system(system: int) -> void:
	if system == 0:
		focus_mode = Control.FOCUS_NONE
	elif system == 1:
		focus_mode = Control.FOCUS_ALL
		focus_neighbor_top = navigation_paths.get(&"ui_up", NodePath(""))
		focus_neighbor_right = navigation_paths.get(&"ui_right", NodePath(""))
		focus_neighbor_bottom = navigation_paths.get(&"ui_down", NodePath(""))
		focus_neighbor_left = navigation_paths.get(&"ui_left", NodePath(""))

## Updates the target transparency (alpha) for visual fading effects.
func fade_to_opacity(target_alpha: float):
	if _alpha_tween: _alpha_tween.kill()
	_alpha_tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_LINEAR)
	_alpha_tween.tween_property(self, "modulate:a", target_alpha, 0.2)


func _ready() -> void:
	set_process(false)
	_init_components()
	_update_connection_links()
	_update_navigation_links()
	mouse_filter = Control.MOUSE_FILTER_STOP
	pivot_offset = size / 2
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(func(): godot_focus_gained.emit(self))
	_update_visual_style()

func _init_components() -> void:
	if not _texture_rect:
		_texture_rect = TextureRect.new()
		_texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_texture_rect)
	if not _animation_player:
		_animation_player = AnimationPlayer.new()
		add_child(_animation_player)

## LINKS
## [Internal] Resolves NodePaths into real Atom references for physical links.
func _update_connection_links() -> void:
	if not is_node_ready(): return
	if Engine.is_editor_hint(): connected_atoms.clear() 
	for path in childrens:
		if path.is_empty(): continue
		var node = get_node_or_null(path)
		if node is Atom and not node in connected_atoms: connected_atoms.append(node)

## [Internal] Resolves NodePaths into real Atom references for directional navigation.
func _update_navigation_links() -> void:
	if not is_node_ready(): return
	navigation_map.clear()
	for action in navigation_paths:
		var path = navigation_paths[action]
		if path.is_empty(): continue
		var target = get_node_or_null(path)
		if target is Atom: navigation_map[action] = target

## [Editor Only] Forces the parent Graph to update its visuals when something changes.
func _force_graph_redraw() -> void:
	if not Engine.is_editor_hint(): return
	var parent = _find_parent_graph()
	if parent and parent.has_method("queue_redraw"): parent.queue_redraw()

## Signals
func _on_mouse_entered() -> void:
	is_hovered = true
func _on_mouse_exited() -> void:
	is_hovered = false


func _update_visual_style() -> void:
	if not is_node_ready(): return
	_change_library()
	_update_icon()
	_update_size()

func _update_size() -> void:
	if not is_node_ready(): return
	if not icon : return
	var new_size = icon.get_size()
	custom_minimum_size = new_size
	size = new_size
	pivot_offset = size / 2

func _update_icon() -> void:
	if not is_node_ready(): return
	_texture_rect.texture = icon
	_texture_rect.visible = (icon != null)
	
	if icon:
		var img = icon.get_image()
		if img: 
			click_mask = BitMap.new()
			click_mask.create_from_image_alpha(img)
	else:
		click_mask = null

func _draw() -> void:
	if not icon: draw_circle(size / 2.0, get_effective_radius(), Color.WHITE)


func _change_library():
	if not _animation_player: return
	var new_lib = _get_active_library()
	
	if _animation_player.has_animation_library(""):
		if _animation_player.get_animation_library("") == new_lib: return
		_animation_player.remove_animation_library("")
	
	if new_lib:
		_animation_player.add_animation_library("", new_lib)
		if _animation_player.has_animation("RESET"): _animation_player.play("RESET"); _animation_player.advance(0)
	
	current_state_id = ""
	_update_state()

func _update_state() -> void:
	if Engine.is_editor_hint(): return
	if not is_node_ready(): return
	for state in _state_registry:
		if state.check.call():
			_apply_state(state.id, state.animation)
			break
func _apply_state(id: String, anim_name: String) -> void:
	if current_state_id == id: return
	current_state_id = id
	if _animation_player.has_animation(anim_name): _animation_player.play(anim_name)
	elif _animation_player.has_animation("RESET"): _animation_player.play("RESET")

func _get_active_library() -> AnimationLibrary:
	var lib: AnimationLibrary = null
	match status:
		Status.LOCKED:    lib = locked_animation_library
		Status.UNLOCKED:  lib = unlocked_animation_library
		Status.AVAILABLE: lib = available_animation_library
		Status.HIDDEN:    lib = hidden_animation_library
		Status.DISABLED:  lib = disabled_animation_library
	return lib


func _process(_delta: float) -> void:
	if Engine.is_editor_hint(): return
	if is_dragging and drag_input:
		var global_scale = get_global_transform().get_scale()
		var target_center = get_global_mouse_position() + _drag_offset
		var target_pos = target_center - (pivot_offset * global_scale)
		
		var graph: Graph = _find_parent_graph()
		if graph:
			target_pos = graph.snap_node_to_grid(self, target_pos)
			target_pos = graph.constrain_to_boundaries(self, target_pos)
		
		global_position = target_pos

func _gui_input(event: InputEvent) -> void:
	if Engine.is_editor_hint(): return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_start_drag()
				accept_event()
			else:
				if is_dragging:
					var mouse_travel = get_global_mouse_position().distance_to(_drag_start_mouse_pos)
					_end_drag()
					if mouse_travel < drag_threshold: clicked.emit(self)
					accept_event()

func _has_point(point: Vector2) -> bool:
	if not Rect2(Vector2.ZERO, size).has_point(point): return false
	if click_mask: # Если есть маска, проверяем прозрачность конкретного пикселя
		# Масштабируем локальную точку под размер BitMap (текстуры)
		var mask_size = Vector2(click_mask.get_size()) 
		var relative_point = Vector2i(point * (mask_size / size))
		if Rect2i(Vector2i.ZERO, click_mask.get_size()).has_point(relative_point):
			return click_mask.get_bitv(relative_point)
		return false
	if not icon:
		var center = size / 2.0
		return point.distance_to(center) <= get_effective_radius()
	return true


func _start_drag() -> void:
	is_dragging = true
	set_process(true)
	var global_scale = get_global_transform().get_scale()
	_drag_offset = (global_position + pivot_offset * global_scale) - get_global_mouse_position()
	_drag_start_mouse_pos = get_global_mouse_position()
	drag_started.emit(self)

func _end_drag() -> void:
	velocity = Vector2.ZERO
	set_process(false)
	is_dragging = false
	if is_hovered: is_hovered = false; mouse_exited.emit()
	drag_ended.emit(self)


func _find_parent_graph() -> Control:
	var parent = get_parent()
	while parent:
		if parent is Graph: return parent
		parent = parent.get_parent()
	return null
