# Where everyone sits round the oval table, as plain numbers (so it can be tested without drawing anything).
#
# The screen is a phone held sideways, 1280 x 720. You always sit at the bottom middle; the others follow in seat order
# clockwise round the table (bottom, then left, top, right), so everyone sees the same order from their own place.

const SCREEN := Vector2(1280, 720)
const TOP_BAR := 64.0       # round, treasury and the menu buttons live here
const BOTTOM_BAR := 0.0     # (the action panel will come up over the table when it is needed)
const GAP := 8.0            # space kept free between neighbours and from the screen edge


# The area the table may use.
static func table_area() -> Rect2:
	return Rect2(0.0, TOP_BAR, SCREEN.x, SCREEN.y - TOP_BAR - BOTTOM_BAR)


# How big each player's badge is: smaller as the table fills.
static func badge_size(count: int) -> Vector2:
	if count <= 5:
		return Vector2(232, 118)
	if count <= 7:
		return Vector2(206, 108)
	return Vector2(176, 100)


# Centre of each badge, indexed like `seats` (a list of seat numbers in table order starting with you).
static func positions(count: int) -> Array:
	var area: Rect2 = table_area()
	var size: Vector2 = badge_size(count)
	var centre: Vector2 = area.get_center()
	var rx: float = area.size.x / 2.0 - size.x / 2.0 - GAP
	var ry: float = area.size.y / 2.0 - size.y / 2.0 - GAP
	var result: Array = []
	for k in count:
		var angle: float = PI / 2.0 + TAU * float(k) / float(count)   # screen y points down, so this is the bottom, then round to the left
		result.append(centre + Vector2(cos(angle) * rx, sin(angle) * ry))
	return result


# The seats in table order starting with `me`: [me, next clockwise, ...]. Seats are the player ids of the game (1..n).
static func order_from(player_ids: Array, me: int) -> Array:
	var start: int = player_ids.find(me)
	if start == -1:
		start = 0   # a watcher is not at the table: seat 1 is put at the bottom
	var result: Array = []
	for k in player_ids.size():
		result.append(player_ids[(start + k) % player_ids.size()])
	return result
