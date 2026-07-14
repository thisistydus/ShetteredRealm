extends Node
## Global signal bus. Keeps board / combat / UI decoupled.

# Board -> combat/UI
signal match_made(kind: int, total: int, unlocked: int, combo: int, world_pos: Vector2)
signal board_settled

# Enemy -> combat/UI
signal enemy_damaged(amount: int, world_pos: Vector2, was_chip: bool)
signal enemy_died
signal enemy_attack(attack: Dictionary)  # {name, time, kind, power}

# Combat -> UI
signal party_hp_changed(hp: int, max_hp: int)
signal party_defeated
signal atb_full(id: int)
signal ability_used(id: int)

# Flow / juice
signal encounter_started(index: int, enemy: Node)
signal float_text(text: String, world_pos: Vector2, color: Color, size: int)
signal shake(amount: float)
signal banner(text: String, color: Color)
