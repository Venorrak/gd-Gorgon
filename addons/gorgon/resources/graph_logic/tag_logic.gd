@tool
class_name TagLogic extends GraphLogic

@export var tags: Array[StringName] = [&"root"]
@export var status: Atom.Status = Atom.Status.AVAILABLE

func get_permission(atom: Atom, graph: Graph) -> Return:
	for t in tags: if t in atom.get_all_tags(): return Return.ALLOW
	return Return.PASS

func apply_status(atom: Atom, graph: Graph) -> bool:
	var perm = get_permission(atom, graph)
	if perm == GraphLogic.Return.ALLOW:
		if atom.status != status: atom.status = status
	return true
