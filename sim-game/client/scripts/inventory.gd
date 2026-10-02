class_name AssayInventory
extends RefCounted
## READING AN INVENTORY THE SIM HANDED OVER. No rules, no commands, no presentation: these are
## questions about a list of stacks that `AssaySimHost.inventory_of` already decided.
##
## **WHY IT IS HERE AND NOT IN `tools/` (ASSA-51).** `held` used to live on `AssayDemoPlan`, in
## `tools/demo_plan.gd`, and `main.gd` called it. Both export presets carry
## `exclude_filter="tests/*, tools/*"`, so the shipped pack had no such class: the exported client
## failed to parse `main.gd`, never reached `_ready`, never wrote the selfcheck marker and never
## exited. Six main commits' bundles hung for an hour each on a step with no timeout. Anything
## `scripts/` calls has to live in `scripts/`, and `tools/check_shipped_scripts.py` now fails the
## build if that stops being true.


## How many of one kind, species and grade a player is carrying, summed over their stacks.
##
## **GRADE IS PART OF THE QUESTION.** Two grades of one ore are two stacks and two rows in the HUD,
## so a caller that ignored grade would answer with a number from a different row. An empty `grade`
## means "any", which is what a caller asking "how much of this ore at all" wants.
static func held(stacks: Array, kind: String, species: int, grade: String = "") -> int:
	var total := 0
	for entry in stacks:
		var stack: Dictionary = entry
		if String(stack.get("kind", "")) != kind:
			continue
		if int(stack.get("species", -1)) != species:
			continue
		if grade != "" and String(stack.get("grade", "")).to_upper() != grade.to_upper():
			continue
		total += int(stack.get("count", 0))
	return total
