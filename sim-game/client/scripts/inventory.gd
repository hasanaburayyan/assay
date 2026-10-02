class_name AssayInventory
## READING THE PACK THE SIM HANDED OVER. Counting, never deciding.
##
## Everything here takes the `Array` of stacks `AssaySimHost.inventory_of` returned and answers a
## question about it. No rule lives here: a stack's kind, species, grade and count are the sim's
## words, and this file only adds them up.
##
## WHY IT IS NOT IN `actions.gd`, WHICH IS WHERE IT GREW UP (Marlow's call, and they are right). That
## file's charter is COMMANDS -- the shapes serde reads, the one place a `PlayerCommand` is spelled.
## A count is an argument you pass to one, not a command, and the two things rot differently: the
## command shapes must track the wire protocol, and this must track what `inventory_of` returns.
## I had put it in `actions.gd` because `insert`, `craft` and `make_part` all take a count, which is an
## argument about the CALLER rather than about the function.
##
## IT USED TO LIVE IN `tools/demo_plan.gd`, AND THAT IS WHAT BROKE MAIN (ASSA-51). `main.gd` called
## `AssayDemoPlan.held`; the export preset excludes `tools/*`, so the shipped `main.gd` named a class
## that was not in the pack. It failed to PARSE, `_ready` never ran, the self-check never fired,
## nothing called `quit()`, and the exported client sat in the platform event loop until CI's timeout.
## That is why a count a shipped script needs lives in `scripts/`, and `tools/demo_plan.gd` forwards
## here so there is still exactly one definition.


## HOW MANY OF ONE ITEM A PLAYER IS CARRYING, summed over the stacks `inventory_of` handed back.
##
## GRADE IS PART OF THE QUESTION on purpose: two grades of one ore are two stacks and two rows on
## screen, so counting without it would send the other row's number into a command. An empty `grade`
## means "any", which is the only way to ask about a species as a whole.
##
## ASKED AT THE PRESS, NEVER CAPTURED. The pack's rows only rebuild when its SHAPE changes, so a count
## read when a button was BUILT is stale the moment the next mining cycle lands -- a `Fuel` button on
## a row reading 12 once inserted 2 and the fire went out mid-stack (ASSA-37). `tests/test_buttons.gd`
## has the guard that the submitted command carries the number from the press (ASSA-55).
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
