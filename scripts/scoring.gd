class_name Scoring

const GameDataScript = preload("res://scripts/game_data.gd")


# Tie-break score when players are level on rounds as Leader. Higher wins.
# Handbook rule: (popularity + shift) x PSD. The shift is 51, not 50, so a CANCELLED
# player (-50 popularity) still scores 1 x PSD and their wealth keeps mattering.
# Fix for debt: anyone below 0 PSD always ranks under everyone at 0 or above, and a
# smaller debt beats a bigger one. (Multiplying by a negative PSD would have flipped
# the meaning of popularity and ranked a more popular debtor lower.)
static func tie_break_score(popularity: int, net_psd: int) -> int:
	if net_psd < 0:
		return net_psd
	var shift: int = GameDataScript.get_int("tieBreakShift")
	return (popularity + shift) * net_psd
