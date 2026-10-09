## **ONE PROPERTY, AS THREE COLUMNS: label | track | value** (ASSA-288, ASSA-276 move 3).
##
## Maren's rule 2, measured off my own mock and ruled against it: *"Four 87 px tracks at four
## different x, because each is parked beside its own right-aligned number. A position encoding whose
## axes are not aligned cannot be compared down the column, which is the only thing it is for."*
##
## **SO THE TRACK'S x IS NOT ALLOWED TO DEPEND ON THE LABEL'S WORD OR THE VALUE'S DIGITS.** The label
## column is a fixed width and so is the value column; the track sits between two fixed things and
## therefore lands on the same x in every row of every species in the panel. A `GridContainer` would
## have aligned the columns WITHIN one species and moved them between species, because its columns
## size to their own widest child — six grids, six alignments, and the defect looks like success in
## any single screenshot.
##
## **NOTHING HERE IS COMPOSED, WHICH IS THE ONLY REASON THIS SLICE IS CLIENT-ONLY.** The label is the
## sim's own property key, the value is the sim's own reading string (`readings[property]`: "26-50"
## while rough, "38" once exact) kept verbatim, and the mark is `reading_ranges[property]` against
## `AssaySim.reading_scale()`. The close-up my mock drew these in is built from the sim's SENTENCES
## (`AssayHud.tile_lines`), and splitting a sentence into a label and a value in GDScript is the
## thing ASSA-136/146 forbid — so that surface needs a Rust change and is not this item.
##
## **THE VALUE STAYS, AND THAT IS NOT A HEDGE.** A track answers "where on the scale" at a glance and
## cannot answer "what number"; the text answers the number and cannot be compared down a column.
## They are two questions. Dropping the text to make room for the bar would trade a readable number
## for a pretty one, and the sim's own string is the thing every other surface in the game prints.
class_name AssayReadingRow
extends HBoxContainer

## **THE LABEL COLUMN, FIXED, AND THE NUMBER IS NOT TASTE** (see `_init`): it is the width of the
## longest property name the sim publishes, at the theme's `BODY` size, asked of the engine's own
## font metrics in `test_reading_row.gd`. `heat tolerance` is the long one today, and a seventh
## property longer than this one makes that test red rather than clipping a word on screen.
const LABEL_W := 104.0

## **THE VALUE COLUMN, RIGHT-ALIGNED, AND WIDE ENOUGH THAT NO READING CAN EVER EXCEED IT.**
##
## **IT MAY NOT BE CLIPPED AND IT MAY NOT GROW, which is a tighter constraint than the label's.** The
## label is a word and clipping it costs a few letters; this is the NUMBER, and a clipped number is
## worse than no column at all. But a column that grows with its digits pushes the track just as
## surely as a label would -- the slack a row has to share is what is left after this -- so sizing it
## to its text would put every species' axis at its own x again.
##
## So the only way out is a width nothing can exceed: the widest string the sim's own scale permits,
## at the theme's `BODY` size. **48 WAS NOT IT.** `test_track.gd` measured `100-100` at 49.0 px
## against a 48.0 column and went red -- one pixel, and it would have moved every track on the
## sharpest sheet in the game. The number is held by that assertion against the engine's own font
## metrics, not by my reading of a glyph table.
const VALUE_W := 56.0

## The air either side of the track. Small on purpose: the track must read as belonging to the row it
## is on, and `ASSA-276`'s own note on the mock says why — under the value it sat nearer the NEXT
## label than its own, "which is the mistake that makes a table of rows read as a list of pairs".
const GAP := 6

var _label := Label.new()
var _track := AssayTrack.new()
var _value := Label.new()


func _init() -> void:
	add_theme_constant_override("separation", GAP)
	# THE PROPERTY NAME IS SECONDARY AND THE READING IS NOT. `Muted` for the label, default ink for
	# the value: the thing a player came for is the number, and the name of the property is how they
	# find it. This is the same hierarchy `tile_lines`' readouts already read with.
	_label.theme_type_variation = &"Muted"
	_label.custom_minimum_size = Vector2(LABEL_W, 0.0)
	# **CLIPPED, AND THAT IS WHAT MAKES RULE 2 TRUE RATHER THAN LUCKY.** `custom_minimum_size` is a
	# floor, not a ceiling: a Label sizes itself to its text, so a long property name would GROW this
	# column and push the track right -- one row's axis out of line with its neighbours', which is
	# exactly the defect Maren measured in my mock. With `clip_text` Godot reports a minimum width of
	# 1 for the text and the custom minimum is the only thing left, so the label's width cannot depend
	# on its word. `test_track.gd` asserts that by giving two rows wildly different labels and
	# comparing their combined minimum sizes -- which is content-derived, so it survives a headless
	# suite where no position is real.
	#
	# Clipped and not WRAPPED for a second reason: a wrapped name makes one row twice the height of
	# its neighbours and the column stops being a table.
	_label.clip_text = true
	# THE SLACK GOES TO THE LABEL, SO THE TRACK AND THE VALUE SIT AGAINST THE RIGHT EDGE. A row wider
	# than its content has to give the extra pixels to somebody; handing them to the label is what
	# puts every track at one x and every digit under the one above it. Handing them to nobody (no
	# expand flag anywhere) would leave the whole group floating left of the panel edge with the
	# right-aligned value aligned to nothing.
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_label)
	add_child(_track)
	_value.custom_minimum_size = Vector2(VALUE_W, 0.0)
	# RIGHT-ALIGNED, which is what makes the digits line up under each other; the track is already
	# fixed, so nothing moves because of this.
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_value)


## **SHOW ONE READING, EXACTLY AS THE SIM PUBLISHED IT.**
##
## `property` and `text` are the sim's own strings; `low`/`high` are one `reading_ranges` entry and
## `scale` is `AssaySim.reading_scale()`. `assayed` is the sheet's own flag, so the ink follows the
## sim's certainty and not a guess from whether `low == high` — a band can legitimately collapse to a
## point while the sheet is still rough, and reading certainty off the geometry would then promote a
## guess to an answer.
func show_reading(property: String, text: String, low: int, high: int, scale: Vector2i,
		assayed: bool) -> void:
	_label.text = property
	_value.text = text
	_track.show_reading(low, high, scale, assayed)


## **A RATIO FILL, WITH NO NUMBER BESIDE IT** (ASSA-369; Maren's §5.1 and her 00:32 ruling that block
## 5 is *"the relationship, not the figures"*).
##
## `value` and `total` are both the sim's. **THE VALUE COLUMN IS DELIBERATELY EMPTY** and that is the
## item's box 4, not an omission: the design's figures live in the commit bar, and one fact with two
## homes is ASSA-316 ruling 6. The column is still RESERVED -- it keeps the track at the x every
## other row in the game puts it at, which is the whole of move 3's rule 2 and the only reason the
## per-part mass floats of this item's second box can be compared down the column when they land.
##
## **AND `property` MAY BE EMPTY, WHICH IS A SUBJECT THIS ROW DOES NOT HAVE** (Maren's ruling, ASSA-369
## 16:09: *"under a heading that NAMES THE QUANTITY, a row label names its SUBJECT -- never the
## quantity again. With one row and no second subject to tell it from, there is no label at all."*).
## An empty word leaves the label column **reserved and blank**, exactly as the value column already
## is: a `clip_text` Label reports a minimum width of 1 for its text, so the custom minimum is all
## that holds the column open and the track cannot move because a word left it. That the air is
## reserved rather than reclaimed is the half of her ruling she would not spec without seeing the
## rect, and it is measured on the 1x shot rather than decided here.
##
## **THE TRACK DECIDES WHAT AN ABSENT FACT LOOKS LIKE, NOT THIS ROW.** `total <= 0` draws nothing
## (`AssayTrack.show_amount`), which is the state a refused design is in -- and leaving that to the
## track is what makes it uniform rather than a case this screen invented for itself.
func show_amount(property: String, value: int, total: int) -> void:
	_label.text = property
	_value.text = ""
	_track.show_amount(value, total)


## **THE SIM'S WORDS WITH NO AXIS UNDER THEM**, for a property the binding sent a reading for and no
## range. Not a styling choice: the row keeps the number it was given and withholds the position it
## was not. See `main.gd::_readings_table` for the default that made this a function instead of a
## `Vector2i.ZERO`.
func show_unmarked(property: String, text: String) -> void:
	_label.text = property
	_value.text = text
	_track.show_nothing()


## The value as rendered, for the suite. `test_species_panel.gd` tells a band from an exact number by
## the hyphen the sim spells it with, so it needs the sim's string and not the geometry.
func value_text() -> String:
	return _value.text


func label_text() -> String:
	return _label.text


func track() -> AssayTrack:
	return _track
