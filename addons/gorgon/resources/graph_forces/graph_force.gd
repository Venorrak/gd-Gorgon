## Base resource class for implementing graph physics forces.
##
## Base class for creating custom physical forces in graphics.
##
## All physical behaviors (gravity, springs, repulsion) inherit from this resource.
## It provides a common interface for calculating movement and weight.
@abstract
class_name GraphForce extends Resource


## Step 1: Pre-calculation. Adjusts how "heavy" each atom feels.
## (Called BEFORE applying forces to set up inertia and resistance).
@abstract
func calculate_mass(registry: Array, masses: Array, context: Dictionary) -> void

## Step 2: Movement. Calculates and adds physical push/pull to each atom.
## (Main calculation loop where the actual movement logic happens).
@abstract
func apply_force(registry: Array, forces: Array, context: Dictionary) -> void

## Helper: Returns the world zoom level to keep physics stable at any scale.
func get_physics_scale(atom: Atom) -> float:
	var parent = atom.get_parent()
	if parent is Control:
		var s = parent.get_global_transform().get_scale() 
		return (s.x + s.y) * 0.5 
	return 1.0

## Helper: Returns the exact world center of an atom for distance calculations.
func get_atom_center(atom: Atom) -> Vector2:
	var s = atom.get_global_transform().get_scale()
	return atom.global_position + (atom.pivot_offset * s)
