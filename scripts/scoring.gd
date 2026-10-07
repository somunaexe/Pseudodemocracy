class_name Scoring

const GameDataScript = preload("res://scripts/game_data.gd")


# Tie-break score. Higher wins.
# Handbook rule: (popularity + shift) x PSD. The shift is 51, not 50, so a CANCELLED
# player (-50 popularity) still scores 1 x PSD and their wealth keeps mattering.
# Debt fix: anyone below 0 PSD scores their (negative) PSD, so they always rank under
# everyone at 0 or above, and a smaller debt beats a bigger one. (Multiplying by a negative
# PSD would have flipped the meaning of popularity.)
static func tie_break_score(popularity: int, net_psd: int) -> int:
	if net_psd < 0:
		return net_psd
	var shift: int = GameDataScript.get_int("tieBreakShift")
	return (popularity + shift) * net_psd


# The full order, compared left to right:
#   1. half-rounds as Leader (a full term = 2, a couped term = 1, so 3 rounds = 6)
#   2. the tie-break score above
#   3. popularity (this settles everyone at exactly 0 PSD, equal debts, and equal products)
# Entries that match on all three are a genuine tie.
static func rank_key(entry: Dictionary) -> Array:
	var popularity: int = entry["popularity"]
	var net_psd: int = entry["net_psd"]
	var half_rounds: int = entry["half_rounds"]
	return [half_rounds, tie_break_score(popularity, net_psd), popularity]


# 1 if key a ranks higher, -1 if b does, 0 if they are tied.
static func compare_keys(a: Array, b: Array) -> int:
	for i in a.size():
		if a[i] > b[i]:
			return 1
		if a[i] < b[i]:
			return -1
	return 0


# Entries look like { "id": 1, "half_rounds": 6, "popularity": 10, "net_psd": 500 }.
# Returns the ids of everyone tied for first place: one id normally, several when the
# game ends in a genuine tie (a shared win). The caller decides who is eligible.
static func winners(entries: Array) -> Array:
	var best: Array = []
	var ids: Array = []
	for entry in entries:
		var key: Array = rank_key(entry)
		var result: int = 1 if best.is_empty() else compare_keys(key, best)
		if result > 0:
			best = key
			ids = [entry["id"]]
		elif result == 0:
			ids.append(entry["id"])
	return ids
