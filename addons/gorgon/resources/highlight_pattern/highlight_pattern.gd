@tool
@abstract
class_name HighlightPattern extends Resource

@abstract
## highlights the wanted Atom(s). Passed highlight_source can be null when the highlight ends. Returns the highlighted Atom(s)
func apply_highlights(graph: Graph, highlight_source: Atom, dim_opacity: float) -> Array[Atom]
