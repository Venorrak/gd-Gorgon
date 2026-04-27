@tool
class_name BlockLogic extends GraphLogic

@export var blocked_tags: Array[StringName] = [&"blocked"]
@export var blocked_statuses: Array[Atom.Status] = [Atom.Status.DISABLED]

@export_group("Atom Properties")
@export var require_data: bool = true
@export var block_if_static: bool = false
@export var block_if_no_focus: bool = false
@export var block_if_no_drag: bool = false

func get_permission(atom: Atom, graph: Graph) -> Return:
	if require_data and not atom.data: return Return.BLOCK
	
	if block_if_static and atom.is_static: return Return.BLOCK
	if block_if_no_focus and atom.block_focus: return Return.BLOCK
	if block_if_no_drag and not atom.drag_input: return Return.BLOCK
	
	for t in blocked_tags: if t in atom.get_all_tags(): return Return.BLOCK
	for s in blocked_statuses: if atom.status == s: return Return.BLOCK
	
	return Return.PASS

func apply_status(atom: Atom, graph: Graph) -> bool:
	var perm = get_permission(atom, graph)
	if perm == GraphLogic.Return.BLOCK:
		if atom.status != Atom.Status.DISABLED: atom.status = Atom.Status.DISABLED
		return false
	return true
