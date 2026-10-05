## **THE WHOLE-WORLD MAP'S SHAPE KEY** (ASSA-206, Maren's ruling).
##
## WHY IT EXISTS, and the evidence is our own QA's record rather than anyone's taste: on 2026-10-04
## Nerite misread this view three times in six minutes -- a player square called a building, a smelter
## called a player, and an olive square neither they nor the director could name without grepping
## (it was the spawn pad). The view carries fifteen draw calls and eleven facts, and the only key on
## screen was the species panel, which maps COLOUR to SPECIES and says nothing about SHAPE. Four
## items (ASSA-187/189/193/199) added meaning to shape and the key never grew with them.
##
## **EVERY ROW COMES OUT OF `AssayHud.MAP_MARKS`, WHICH IS THE TABLE `main.gd::_draw` PAINTS FROM.**
## That is Maren's constraint and the whole of what is fixed here: there is no list of rows in this
## file. A mark added to the map without a row in that table fails `tests/test_map_key.gd`, and a row
## added to the table that nothing paints fails it too.
##
## DRAWN, NOT LAID OUT, and the reason is the thing a panel of Labels cannot do: each row's mark has
## to be painted by the same kind of call the map paints it with -- a filled disc, a hatch cut to a
## chord, a diamond, four corner brackets -- on the map's own ground ink, so the sample is the mark
## and not a picture of it. `AssayHud.hatch_segments` and `AssayHud.diamond` are the map's own
## geometry, called here. The one thing this file owns is the SIZE of a sample.
##
## IT SITS IN A `PanelContainer` THE CALLER OWNS, so the chrome and the ink are the theme's and this
## panel spends no colour literal of its own (Maren's corrected ruling 3, ASSA-116).
class_name AssayMapKey
extends Control

## The box a row's mark is drawn in, and the row pitch. A sample has to be big enough for the two
## marks that are ABOUT their size to still be about it: a 16px body with a 2px keyline, and a ring
## 1.6x that. 28x20 holds both with a pixel to spare.
const SAMPLE := Vector2(28.0, 20.0)
const PITCH := 24.0
const PAD := 8.0
const GAP := 10.0

## The letter on the glyph sample. A species' symbol is generated per world (`sim::debug::
## species_symbol`), so no real one can be hard-coded here; `S` is an example and is deliberately not
## a grade letter (C/B/A), which is the one reading that would be wrong rather than merely arbitrary.
const SAMPLE_GLYPH := "S"


## THE SIZE THIS PANEL WANTS, FROM THE FONT AND THE TABLE. Pure, so a headless test can read it: the
## runner works in `SceneTree._initialize`, where `_ready` never fires and every rect is zero, so a
## minimum size derived inside layout would be untestable and a number written down would drift from
## the rows.
static func wants(font: Font, font_px: int, rows: Array[Dictionary]) -> Vector2:
	var widest := 0.0
	for row in rows:
		widest = maxf(widest, font.get_string_size(String(row["label"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x)
	return Vector2(PAD * 2.0 + SAMPLE.x + GAP + widest,
			PAD * 2.0 + PITCH * float(rows.size()))


func _get_minimum_size() -> Vector2:
	return wants(_font(), _font_px(), AssayHud.map_key_rows())


func _font() -> Font:
	var font := get_theme_font(&"font")
	return ThemeDB.fallback_font if font == null else font


func _font_px() -> int:
	var px := get_theme_font_size(&"font_size")
	return 13 if px <= 0 else px


## ONE ROW PER MARK, IN THE ORDER `_draw` PAINTS THEM. The sample sits on a patch of the map's own
## ground, so a mark whose contrast against that ground is its weak point (the spawn pad, 2.23:1 --
## Maren's number, and she ruled the size rather than the colour) is exactly as quiet here as it is
## on the map. A key that flattered a mark would be worse than none.
func _draw() -> void:
	var font := _font()
	var font_px := _font_px()
	var ink := get_theme_color(&"font_color")
	var rows := AssayHud.map_key_rows()
	var y := PAD
	for row in rows:
		var box := Rect2(Vector2(PAD, y), SAMPLE)
		draw_rect(box, AssayHud.mark_ink(&"ground"), true)
		_paint_sample(row, box, font, font_px)
		draw_string(font, Vector2(PAD + SAMPLE.x + GAP,
				y + SAMPLE.y * 0.5 + float(font_px) * 0.36), String(row["label"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, ink)
		y += PITCH


## A ROW'S MARK, IN THE SHAPE ITS TABLE ENTRY NAMES. The shapes come from the entry and not from the
## id, so two marks that look the same share one branch and a new shape has to be added here to be
## drawable at all -- which is the second half of "a mark cannot be added without appearing in the
## key": an unknown shape draws nothing and `test_map_key.gd` fails on the shape, by name.
func _paint_sample(row: Dictionary, box: Rect2, font: Font, font_px: int) -> void:
	var colour := AssayHud.map_key_sample_ink(row)
	var middle := box.get_center()
	var shape := StringName(row["shape"])
	match shape:
		&"ground", &"rect":
			draw_rect(_body(middle), colour, true)
		&"disc":
			draw_circle(middle, box.size.y * 0.45, colour)
		&"hatch":
			# **THE DISC UNDER IT IS THE ORE'S, NOT THE HATCH'S** -- and the first version of this line
			# took the row's own ink, which for a dead end IS `MAP_BG`: a disc painted in the ground
			# colour with ground-coloured strokes on it, measured 100% `(25,28,33)` in the real-window
			# shot where a clean disc reads `(80,155,230)`. The row that exists to teach the one mark
			# Maren says can disappear (ASSA-209) was a black box on black.
			var radius := box.size.y * 0.45
			draw_circle(middle, radius, AssayHud.species_tint(AssayHud.KEY_SAMPLE_SPECIES))
			var strokes := AssayHud.hatch_segments(middle, radius)
			for i in range(0, strokes.size(), 2):
				draw_line(strokes[i], strokes[i + 1], AssayHud.mark_ink(&"dead_end"),
						float(AssayHud.HATCH_ON))
		&"glyph":
			var radius := box.size.y * 0.45
			draw_circle(middle, radius, AssayHud.species_tint(AssayHud.KEY_SAMPLE_SPECIES))
			var wide := font.get_string_size(SAMPLE_GLYPH, HORIZONTAL_ALIGNMENT_LEFT, -1,
					font_px).x
			draw_string(font, middle + Vector2(-wide * 0.5, float(font_px) * 0.36), SAMPLE_GLYPH,
					HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, colour)
		&"line":
			draw_line(Vector2(box.position.x + 2.0, box.end.y - 4.0),
					Vector2(box.end.x - 2.0, box.position.y + 4.0), colour, 1.0)
		&"ring":
			draw_rect(_body(middle).grow(3.0), colour, false, 2.0)
		&"diamond":
			draw_colored_polygon(AssayHud.diamond(middle, AssayHud.BUILDING_MARK_PX * 0.75), colour)
		&"brackets":
			var tile := Rect2(middle - Vector2(7.0, 7.0), Vector2(14.0, 14.0))
			var reach := 4.0
			for step in [Vector2(1.0, 1.0), Vector2(-1.0, 1.0), Vector2(1.0, -1.0),
					Vector2(-1.0, -1.0)]:
				var from := Vector2(tile.position.x if step.x > 0.0 else tile.end.x,
						tile.position.y if step.y > 0.0 else tile.end.y)
				draw_line(from, from + Vector2(reach * step.x, 0.0), colour, 2.0)
				draw_line(from, from + Vector2(0.0, reach * step.y), colour, 2.0)
		&"outline":
			draw_rect(Rect2(middle - Vector2(7.0, 7.0), Vector2(14.0, 14.0)), colour, false, 1.0)
		_:
			push_error("map key cannot draw shape '%s'" % shape)


## The sample's own body rect: the player mark's size is a fact (`PLAYER_MARK_PX`, ASSA-119 box 6), so
## the sample is drawn at it rather than at a fraction of the box, and the box was sized to fit it.
func _body(middle: Vector2) -> Rect2:
	var span := Vector2(AssayHud.PLAYER_MARK_PX, AssayHud.PLAYER_MARK_PX) * 0.7
	return Rect2(middle - span * 0.5, span)
