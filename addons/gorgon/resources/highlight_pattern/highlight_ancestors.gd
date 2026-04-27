class_name HighlightAncestors extends HighlightPattern

func apply_highlights(graph: Graph, highlight_source: Atom, dim_opacity: float) -> Array[Atom]:
	if highlight_source:
		var atoms = graph.get_all_atoms()
		var ancestors : Array[Atom] = []
		var parents : Array[Atom] = graph.get_atom_parents(highlight_source)
		while not parents.is_empty():
			ancestors.append_array(parents)
			var parent_temp : Array[Atom] = parents.duplicate()
			parents.clear()
			for p in parent_temp:
				parents.append_array(graph.get_atom_parents(p))
		ancestors.append(highlight_source)

		for a in atoms:
			a.fade_to_opacity(dim_opacity) if not a in ancestors else a.fade_to_opacity(1.0)
		return ancestors
	else:
		var atoms = graph.get_all_atoms()
		for a in atoms:
			a.fade_to_opacity(1.0)
		return []
