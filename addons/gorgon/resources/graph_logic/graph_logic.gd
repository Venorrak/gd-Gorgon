@tool
class_name GraphLogic extends Resource

enum Return {
	BLOCK,  ## If at least one rule returns BLOCK, the atom becomes DISABLED or remains LOCKED
	PASS,   ## The rule has no opinion (e.g., the skill doesn't have the tags the rule is configured for)
	ALLOW   ## If a condition is met (e.g., a parent skill is purchased)
}

func get_permission(atom: Atom, graph: Graph) -> Return:
	return Return.PASS

## STATUS CONTROL (Called at startup and each time progress is updated in sync_with_progress)
## Here, the logic can change atom.is_disabled, atom.is_hidden, etc.
## Calls the permission to continue the state change cycle.
func apply_status(atom: Atom, graph: Graph) -> bool:
	return false
