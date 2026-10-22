extends RefCounted

## 原版战斗数值的可复现实现。
## 攻击/防御/伤害/技能效果来自 DLZ.exe 反汇编与 dlz_research 的公式表；
## 经验 100 点一级、击杀经验与战后经验来自 0x429e92 / 0x42ab23 的汇编复核。

const EXP_PER_LEVEL := 100
const LEVEL_CAP := 99
const SKILL_THRESHOLDS := [1, 10, 25, 45, 70, 100, 135, 175, 225, 300]


static func skill_level(use_count: int) -> int:
	var lv := 0
	for i in range(SKILL_THRESHOLDS.size()):
		if use_count >= int(SKILL_THRESHOLDS[i]):
			lv = i + 1
	return mini(10, lv)


static func attack_power(member: Dictionary, unit_type: Dictionary,
		morale: int = 100, integrity: int = 100,
		skill_count: int = 0, item_attack: int = 0) -> int:
	var wuli := int(member.get("wuli", 0))
	var level: int = maxi(1, int(member.get("level", 1)))
	var base := int(unit_type.get("gongji", 0))
	var growth := int(unit_type.get("gongji_plus", 0))
	var raw: int = base * 3 * wuli / 100 + (growth - 1) * (level - 1)
	var atk: int = (skill_level(skill_count) + 59) * (raw * (wuli + 500) / 580) / 60
	atk = atk * clampi(integrity, 0, 100) / 100
	atk = atk * (morale + 100) / 200
	return maxi(1, atk + item_attack)


static func defense_power(member: Dictionary, unit_type: Dictionary,
		morale: int = 100, terrain_bonus: int = 0,
		item_defense: int = 0) -> int:
	var level: int = maxi(1, int(member.get("level", 1)))
	var base := int(unit_type.get("fangyu", 0))
	var growth := int(unit_type.get("fangyu_plus", 0))
	var df: int = base + (level - 1) * growth
	df = df * (morale + 100) / 200
	df = df * (100 + terrain_bonus) / 100
	return maxi(0, df + item_defense)


static func damage(attack: int, defense: int, apply_pct: int = 100) -> int:
	return maxi(1, (attack - defense) * apply_pct / 100)


static func skill_effect(intelligence: int, para: int, count: int) -> int:
	var factor := (skill_level(count) + 7) >> 3
	return (para * intelligence / 100) * factor


static func kill_experience(killer_level: int, victim_level: int) -> int:
	# 0x42ab23: diff = 死者等级 - 击杀者等级；分档 1/2/4/8/12，正差每级 16，封顶 80。
	var diff := victim_level - killer_level
	if diff < -5:
		return 1
	if diff < -3:
		return 2
	if diff < -1:
		return 4
	if diff < 0:
		return 8
	if diff == 0:
		return 12
	return mini(80, diff * 16)


static func battle_experience(level: int, average_level: int) -> int:
	# 0x42b380: 12 + (等级-基准)*8，下限 4；平均分给参战者后再 +8，封顶 12。
	var base := 12 + (level - average_level) * 8
	base = max(4, base)
	return clampi(base + 8, 0, 12)


static func level_over(xp: int) -> Dictionary:
	var gained := int(xp / EXP_PER_LEVEL)
	return {"levels": gained, "xp": xp % EXP_PER_LEVEL}
