@tool
class_name ConnectionsLogic extends GraphLogic

enum Mode {
	ANY_PARENT,  ## Allows if there is AT LEAST ONE open parent
	ALL_PARENTS, ## Allows only if ALL parents are open (Strict mode)
	SOLO         ## Allows only if the atom has NO parents and NO children (Islands)
	}

@export var mode: Mode = Mode.ANY_PARENT

func get_permission(atom: Atom, graph: Graph) -> Return:
	var parents = graph.get_atom_neighbors(atom, Graph.ConnectionDir.INBOUND)
	
	match mode:
		Mode.ANY_PARENT:
			if parents.is_empty(): return Return.PASS
			for p in parents: if _is_open(p): return Return.ALLOW
			return Return.PASS
			
		Mode.ALL_PARENTS:
			if parents.is_empty(): return Return.PASS
			for p in parents: if not _is_open(p): return Return.PASS
			return Return.ALLOW
			
		Mode.SOLO:
			var children = graph.get_atom_neighbors(atom, Graph.ConnectionDir.OUTBOUND)
			if parents.is_empty() and children.is_empty(): return Return.ALLOW
	
	return Return.PASS

func apply_status(atom: Atom, graph: Graph) -> bool:
	var perm = get_permission(atom, graph)
	if perm == GraphLogic.Return.ALLOW:
		if atom.status != Atom.Status.AVAILABLE: atom.status = Atom.Status.AVAILABLE
	return true

func _is_open(atom: Atom) -> bool:
	return is_instance_valid(atom) and atom.status == atom.Status.UNLOCKED
