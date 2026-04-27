class_name HighlightNeighbours extends HighlightPattern

func apply_highlights(graph: Graph, highlight_source: Atom, dim_opacity: float) -> Array[Atom]:
	if highlight_source:
		print(highlight_source)
		var atoms = graph.get_all_atoms()
		var neighbours = graph.get_atom_neighbors(highlight_source, Graph.ConnectionDir.ANY)
		neighbours.append(highlight_source)
		for a in atoms:
			a.fade_to_opacity(dim_opacity) if not a in neighbours else a.fade_to_opacity(1.0)
		return neighbours
	else:
		var atoms = graph.get_all_atoms()
		for a in atoms:
			a.fade_to_opacity(1.0)
		return []
