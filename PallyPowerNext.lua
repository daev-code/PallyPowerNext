-- PallyPower Next Blessing
--
-- One button that does the NEXT needed blessing action from your PallyPowerTW assignments,
-- one cast per click:
--
--   1. Greater Blessings (classes that have individual overrides first). A Greater Blessing
--      also overwrites your blessing on the override members, so all of these go first.
--   2. Individual overrides (PallyPower's per-player "normal blessing" assignments).
--
-- Every click works on what the button shows (the next step, or the one picked with the wheel).
--
-- Left-click            cast what's missing, or on but with a time left PallyPower doesn't know
--                       (low time left is only shown on the button, not refreshed early)
-- Shift                 "cast anyway": the Greater Blessing shown even if some members are not
--                       here, out of range or out of line of sight, or everyone already has
--                       it, Greater or normal version (refresh / upgrade)
-- Right-click           overrides first, then the normal blessing on a member missing the Greater one
-- Shift+right-click     "cast anyway": also refresh blessings that are still on (lowest time first)
--
-- Greater Blessing: only the members WITHOUT an override count. If one of them is not here
-- (not visible), out of range or out of line of sight (UnitXP), it's skipped unless Shift.
-- Skipped Greater Blessings leave only overrides.
--
-- The button lists who the next click is about, with ">" on the player the click is cast on.
-- When a left-click can't do anything on the page shown, a line says what a right-click would
-- cast instead. A totals line (always shown) counts everyone by state: Applied, Missing, OOR,
-- LOS, Not Here, Dead, Tank, No config.
--
-- Pets: Greater Blessings on the Warrior class also land on pets. If PallyPower assigns pets
-- the same blessing as Warriors they're part of that group; otherwise they're handled like
-- overrides with the normal version of their assigned blessing.

local REFRESH_BELOW = 5 * 60   -- button turns yellow when less than this is left
local RECENT_GUARD = 5         -- seconds: don't recast the same thing before the buff scan catches up

local GREY = "|cff9d9d9d"
local NOTE_R, NOTE_G, NOTE_B = 0.80, 0.75, 0.55   -- muted status colours
local OK_R, OK_G, OK_B = 0.55, 0.80, 0.55

PPNext_Settings = PPNext_Settings or {}

local function feedback(text, r, g, b)
	if PallyPower_ShowFeedback then
		PallyPower_ShowFeedback(text, r, g, b)
	else
		UIErrorsFrame:AddMessage(text, r, g, b)
	end
end

local function blessingName(b) return (PallyPower_BlessingID and PallyPower_BlessingID[b]) or ("blessing " .. tostring(b)) end
local function className(c) return (PallyPower_ClassID and PallyPower_ClassID[c]) or ("class " .. tostring(c)) end

-- Own short-lived guard against double casts (PallyPower's equivalent is a local we can't reach).
-- Keys include the blessing, so a player whose assignment was just changed can be blessed again
-- right away.
local recent = {}
local function recentlyCast(key)
	local t = recent[key]
	return t and (GetTime() - t) < RECENT_GUARD
end
local function markCast(key)
	recent[key] = GetTime()
end


------------------------------------------------------------------------------
-- Reading PallyPower's state
------------------------------------------------------------------------------

local function me() return UnitName("player") end

local function spellsFor(b)
	local mine = AllPallys and AllPallys[me()]
	return mine and mine[b]
end

-- Greater Blessing spell id for blessing b, or nil if not known / regular-blessings mode.
local function greaterSpell(b)
	local s = spellsFor(b)
	if not s or RegularBlessings == true then return nil end
	if s["id"] and s["id"] ~= s["idsmall"] then return s["id"] end
	return nil
end

local function smallSpell(b)
	local s = spellsFor(b)
	return s and s["idsmall"]
end

local function classAssignment(c)
	local a = PallyPower_Assignments and PallyPower_Assignments[me()]
	local b = a and a[c]
	if b == nil or b == -1 then return nil end
	return b
end

local function overrideFor(c, name)
	if not GetNormalBlessings then return nil end
	local b = GetNormalBlessings(me(), c, name)
	if b == nil or b == -1 then return nil end
	return b
end

local function usable(unit, includeDead)
	return UnitExists(unit) and UnitIsConnected(unit) and (includeDead or not UnitIsDeadOrGhost(unit))
end

-- Our own copy of the timers we set (expiry times), per PallyPower table: "cast" = LastCast
-- (class Greater Blessings), "player" = LastCastPlayer (individual blessings).
-- PallyPower wipes a timer when a UI refresh sees nobody with the blessing yet, which happens
-- right after a cast, before its buff scan has caught up. Its own casts are protected from that
-- by a local we can't reach, so we restore the timer from this copy instead.
local ownTimers = { cast = {}, player = {} }

local function ppTimers(kind)
	if kind == "cast" then return LastCast end
	return LastCastPlayer
end

local function setTimer(kind, key, duration)
	local tbl = ppTimers(kind)
	if tbl then tbl[key] = duration end
	ownTimers[kind][key] = GetTime() + duration
end

local function clearTimer(kind, key)
	local tbl = ppTimers(kind)
	if tbl then tbl[key] = nil end
	ownTimers[kind][key] = nil
end

-- Seconds left on a timer, or nil when neither PallyPower nor we know.
local function timeLeft(kind, key)
	local tbl = ppTimers(kind)
	local t = tbl and tbl[key]
	if t and t > 0 then return t end
	local expiry = ownTimers[kind][key]
	if expiry then
		local rest = expiry - GetTime()
		if rest > 0 then
			if tbl then tbl[key] = rest end  -- put it back so PallyPower's buttons show it too
			return rest
		end
		ownTimers[kind][key] = nil
	end
	return nil
end

-- Does a member need blessing b? has = PallyPower's scan says it's on them; left = known time left.
-- Missing -> yes. On, but PallyPower doesn't know how long it has left (cast by hand, after a
-- reload...) -> yes, so its timer is known from then on. Otherwise no: low time left is only
-- shown on the button (yellow + time), not refreshed early.
local function needs(has, left)
	if not has then return true end
	return left == nil
end

-- Real time left per player, from ClassicAPI (C_UnitAuras) when it's loaded and knows the
-- aura's expiration time. Which paladin cast it doesn't matter. Results are cached per unit
-- for half a second (the tooltip and list ask often). nil = not known this way.
local hasAuraAPI = (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) and true or false
local AURA_CACHE_TIME = 0.5
local auraCache = {}  -- unit -> { at = time, left = { [blessing] = seconds } }

-- PallyPower's blessing index (0-5) for an aura icon, Greater or normal version.
local function blessingOfIcon(icon)
	if type(icon) ~= "string" or not PallyPower_GetBuffTextureID then return nil end
	local id = PallyPower_GetBuffTextureID(icon)
	if id and id >= 0 and id <= 5 then return id end
	if id and id >= 6 and id <= 11 then return id - 6 end
	return nil
end

local function auraLeft(unit, b)
	if not hasAuraAPI or not unit or b == nil then return nil end
	local now = GetTime()
	local c = auraCache[unit]
	if not c or now - c.at > AURA_CACHE_TIME then
		c = { at = now, left = {} }
		for i = 1, 32 do
			local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
			if not ok or type(a) ~= "table" then break end
			local bb = blessingOfIcon(a.icon)
			local e = tonumber(a.expirationTime)
			if bb and e and e > now then
				local rest = e - now
				if not c.left[bb] or rest > c.left[bb] then c.left[bb] = rest end
			end
		end
		auraCache[unit] = c
	end
	return c.left[b]
end

-- Timers for the normal blessings right-click casts on group members (PallyPower keeps no
-- timer for those): memberTimers[name] = { blessing = b, expiry = GetTime() + duration }.
-- A Greater Blessing cast on the group clears them.
local memberTimers = {}

-- Time left for one group member: the group's Greater Blessing timer, else the member's
-- own normal-blessing timer (same blessing), else nil (unknown).
local function memberLeft(groupLeftTime, g, name, unit)
	local real = auraLeft(unit, g)
	if real then return real end
	local t = memberTimers[name]
	if t and t.blessing == g then
		local rest = t.expiry - GetTime()
		if rest > 0 then return rest end
		memberTimers[name] = nil
	end
	return groupLeftTime
end

-- Time left shown for a group: its Greater Blessing timer, else the lowest normal-blessing
-- timer among its members, else nil.
local function groupLeft(group)
	local g, c = group.blessing, group.class
	local left = timeLeft("cast", g .. c)
	-- the member whose blessing runs out first
	local low
	for _, m in ipairs(group.plain) do
		if m.stats[g] then
			local t = memberLeft(left, g, m.name, m.unit)
			if t and (not low or t < low) then low = t end
		end
	end
	return low or left
end

-- Time left for an override member: real aura time, else the individual timer.
local function overrideLeft(o)
	return auraLeft(o.unit, o.blessing) or timeLeft("player", o.name)
end


local function ppIconPrefix()
	if PP_PerUser and PP_PerUser.usehdicons == true then return "AddOns\\PallyPowerTW\\HD" end
	return "AddOns\\PallyPowerTW\\"
end

-- PallyPower's icon path -> the texture path UnitBuff returns.
local function buffTexture(path)
	if not path then return nil end
	return (string.gsub(path, ppIconPrefix(), ""))
end

-- PallyPower's scan says "has Might" for both the Greater and the normal version (10 min,
-- shorter than the Greater one). The icons tell them apart, so the list can show members who
-- only have the normal one ("single"). They count as covered: a plain left-click doesn't recast
-- the Greater Blessing for them, Shift + left-click does. Buff textures are cached per unit
-- for half a second.
local buffCache = {}  -- unit -> { at = time, tex = { [texture] = true } }
local function unitBuffTextures(unit)
	local now = GetTime()
	local c = buffCache[unit]
	if not c or now - c.at > AURA_CACHE_TIME then
		c = { at = now, tex = {} }
		for i = 1, 32 do
			local t = UnitBuff(unit, i)
			if not t then break end
			c.tex[t] = true
		end
		buffCache[unit] = c
	end
	return c.tex
end

local function normalOnly(unit, b)
	if RegularBlessings == true or not (BuffIcon and BuffIconSmall) then return false end
	local big, small = buffTexture(BuffIcon[b]), buffTexture(BuffIconSmall[b])
	if not big or not small or big == small then return false end
	local tex = unitBuffTextures(unit)
	return (tex[small] and not tex[big]) and true or false
end

-- Does a Greater Blessing group member need the Greater Blessing on a plain left-click?
-- Missing, or on with an unknown time - but someone with only the normal version is covered.
local function memberNeeds(g, m, left)
	if m.stats[g] and normalOnly(m.unit, g) then return false end
	return needs(m.stats[g], left)
end

------------------------------------------------------------------------------
-- Building the work list
------------------------------------------------------------------------------

-- Returns:
--   groups:    { {class=c, blessing=g, spell=id, members={...}, plain={...}, hasOverrides=bool} }
--   overrides: { {unit=, name=, class=, blessing=b, spell=idsmall} }
--   unassigned: members you have nothing to cast on (no assignment for their class, or a
--               blessing you don't know) - only counted, for the "No config" total
-- members are { unit=, name=, stats=, dead= }.
-- includeDead: also list dead members (flagged dead=true) - only for the status display;
-- casting never includes them.
local function collect(includeDead)
	local groups, overrides, unassigned = {}, {}, {}
	if not CurrentBuffs then return groups, overrides, unassigned end

	local petsMerged = classAssignment(9) ~= nil and classAssignment(9) == classAssignment(0)

	local function addMember(group, unit, stats, c)
		local dead = UnitIsDeadOrGhost(unit) and true or false
		local m = { unit = unit, name = stats.name, stats = stats, class = c, dead = dead }
		table.insert(group.members, m)
		local o = overrideFor(c, stats.name)
		if o and o ~= group.blessing and smallSpell(o) then
			group.hasOverrides = true
			table.insert(overrides, { unit = unit, name = stats.name, class = c, blessing = o, spell = smallSpell(o), stats = stats, dead = dead })
		else
			table.insert(group.plain, m)
		end
	end

	for c = 0, 9 do
		local g = classAssignment(c)
		local bucket = CurrentBuffs[c]
		if bucket and not (c == 9 and petsMerged) then
			local gspell = g and greaterSpell(g)
			if c == 9 and g and not petsMerged then
				gspell = nil  -- pets can't take a Greater Blessing different from the Warriors'
			end

			local group = { class = c, blessing = g, spell = gspell, members = {}, plain = {}, hasOverrides = false }
			local function addBucket(bkt, cls)
				for unit, stats in pairs(bkt) do
					if stats.name and usable(unit, includeDead) then
						addMember(group, unit, stats, cls)
					end
				end
			end
			addBucket(bucket, c)
			if c == 0 and petsMerged and CurrentBuffs[9] then
				addBucket(CurrentBuffs[9], 9)
			end

			if g and gspell then
				table.insert(groups, group)
			elseif g and smallSpell(g) then
				-- No Greater Blessing for this class (not learned, regular-blessings mode, or
				-- pets with their own assignment): everyone without an override gets the
				-- normal version, one by one, like an override.
				for _, m in ipairs(group.plain) do
					table.insert(overrides, { unit = m.unit, name = m.name, class = m.class, blessing = g, spell = smallSpell(g), stats = m.stats, dead = m.dead })
				end
			else
				for _, m in ipairs(group.plain) do table.insert(unassigned, m) end
			end
		end
	end

	-- Classes with overrides first, then the rest (class order otherwise).
	table.sort(groups, function(a, b)
		if a.hasOverrides ~= b.hasOverrides then return a.hasOverrides end
		return a.class < b.class
	end)
	return groups, overrides, unassigned
end


------------------------------------------------------------------------------
-- Casting (PallyPower's pattern: spell on the cursor, test targets, cast or cancel)
------------------------------------------------------------------------------

local restoreSelfCastAt = nil
local hadTarget = false

local function beginCasting()
	if GetCVar("autoSelfCast") == "1" then
		SetCVar("autoSelfCast", "0")
		restoreSelfCastAt = GetTime() + 1
	end
	DoEmote("STAND")
	hadTarget = UnitExists("target")
	ClearTarget()  -- with a friendly target selected, CastSpell would land on it immediately
end

local function endCasting()
	if hadTarget then
		TargetLastTarget()
	end
	hadTarget = false
end

local function onCooldown(spell)
	local start = GetSpellCooldown(spell, BOOKTYPE_SPELL)
	return start and start >= 1
end

-- UnitXP_SP3 (DLL) gives real distance and line of sight. Detected the same way Rinse does.
local hasUnitXP = pcall(UnitXP, "nop", "nop")

local BLESSING_RANGE = 30
local GREATER_RANGE = 40

-- Line of sight: UnitXP when the DLL is there (regardless of PallyPower's UnitXP option,
-- which otherwise makes its check always say yes); fall back to PallyPower's check.
local function inSight(unit)
	if UnitIsUnit(unit, "player") then return true end
	if hasUnitXP then
		local ok, seen = pcall(UnitXP, "inSight", "player", unit)
		if ok then return seen and true or false end
	end
	return not PallyPower_CheckTargetLoS or PallyPower_CheckTargetLoS(unit)
end

-- Click-time check: the spell is on the cursor, so the game tells us the real spell range.
local function inRange(unit)
	return UnitIsVisible(unit)
		and (SpellCanTargetUnit(unit) or UnitIsUnit(unit, "player"))
		and inSight(unit)
end

-- Preview status of one unit (no spell on the cursor): "OK", "OOR", "LOS", "Dead" or "Not Here".
-- Distance from UnitXP, or the ~28 yd follow range without it.
local function unitStatus(unit, dead, yards)
	if dead then return "Dead" end
	if UnitIsUnit(unit, "player") then return "OK" end
	if not UnitIsVisible(unit) then return "Not Here" end
	local near
	if hasUnitXP then
		local ok, d = pcall(UnitXP, "distanceBetween", "player", unit)
		if ok and d then near = d <= yards end
	end
	if near == nil then
		near = CheckInteractDistance(unit, 4) and true or false
	end
	if not near then return "OOR" end
	if not inSight(unit) then return "LOS" end
	return "OK"
end

local function inRangePreview(unit, yards)
	return unitStatus(unit, false, yards) == "OK"
end

local function salvationOnTank(unit, blessing)
	return PallyPower_CastingSalvationOnTank and PallyPower_CastingSalvationOnTank(unit, -1, blessing)
end

-- Try the Greater Blessing for one group. Returns "cast", "gcd", or nil plus a note.
-- dry = preview only: no spell on the cursor, distance-based range, no side effects;
-- returns "cast" with the target it would pick.
-- overExisting (Shift): cast even when nobody needs it (refresh, or over the same blessing).
local function tryGroup(group, force, dry, overExisting)
	local g, c = group.blessing, group.class
	local left = timeLeft("cast", g .. c)

	if recentlyCast("G" .. g .. ":" .. c) then return nil end

	local needing = {}
	for _, m in ipairs(group.plain) do
		if memberNeeds(g, m, memberLeft(left, g, m.name, m.unit)) then
			table.insert(needing, m)
		end
	end
	if table.getn(needing) == 0 and not overExisting then return nil end

	local reach
	if dry then
		reach = function(unit) return inRangePreview(unit, GREATER_RANGE) end
	else
		if onCooldown(group.spell) then return "gcd" end
		CastSpell(group.spell, BOOKTYPE_SPELL)
		if not SpellIsTargeting() then
			-- cast went off without targeting (shouldn't happen with self-cast off and no target)
			return nil
		end
		reach = inRange
	end
	local function stop() if not dry then SpellStopTargeting() end end

	-- Everyone without an override should get it. Anyone not here (not visible), out of range
	-- or out of line of sight blocks it, unless Shift ("cast anyway").
	local notHere, outOfReach = 0, 0
	for _, m in ipairs(group.plain) do
		if not UnitIsVisible(m.unit) then
			notHere = notHere + 1
		elseif not reach(m.unit) then
			outOfReach = outOfReach + 1
		end
	end
	if (notHere > 0 or outOfReach > 0) and not force then
		stop()
		local parts = {}
		if notHere > 0 then table.insert(parts, notHere .. " not here") end
		if outOfReach > 0 then table.insert(parts, outOfReach .. " out of range or sight") end
		return nil, string.format("Greater %s (%s): %s - Shift-click to cast anyway.",
			blessingName(g), className(c), table.concat(parts, ", "))
	end

	-- Target someone who needs it; fall back to anyone without an override in range.
	local target
	for _, m in ipairs(needing) do
		if reach(m.unit) and not salvationOnTank(m.unit, g) then target = m; break end
	end
	if not target then
		for _, m in ipairs(group.plain) do
			if reach(m.unit) and not salvationOnTank(m.unit, g) then target = m; break end
		end
	end
	if not target then
		stop()
		return nil, string.format("Greater %s (%s): nobody in range or sight.", blessingName(g), className(c))
	end

	if dry then
		return "cast", nil, { group = group, class = c, blessing = g, target = target.name,
			text = string.format("Greater %s -> %s", blessingName(g), className(c)) }
	end

	SpellTargetUnit(target.unit)
	markCast("G" .. g .. ":" .. c)

	-- Keep PallyPower's timers in step, the same way its own buttons do.
	setTimer("cast", g .. c, PALLYPOWER_GREATERBLESSINGDURATION)
	if c == 0 and CurrentBuffs[9] and classAssignment(9) == g then
		setTimer("cast", g .. 9, PALLYPOWER_GREATERBLESSINGDURATION)
	end
	if LastCastOn and LastCastOn[c] then
		LastCastOn[c] = {}
		for _, m in ipairs(group.members) do
			if UnitIsVisible(m.unit) then table.insert(LastCastOn[c], m.unit) end
		end
	end
	-- The Greater Blessing replaced any normal blessing you put on members.
	for _, m in ipairs(group.members) do
		memberTimers[m.name] = nil
	end
	-- The Greater Blessing replaced your blessing on override members in range: their
	-- individual timers no longer apply.
	for _, m in ipairs(group.members) do
		if UnitIsVisible(m.unit) and overrideFor(m.class, m.name) and LastCastPlayer then
			clearTimer("player", m.name)
		end
	end

	feedback(string.format("Greater %s -> %s (%s)", blessingName(g), className(c), target.name), OK_R, OK_G, OK_B)
	return "cast"
end

local function tryOverride(o, dry, anyway)
	local key = "O" .. o.name .. ":" .. o.blessing  -- per blessing: a changed assignment isn't held back
	if recentlyCast(key) then return nil end
	if not anyway and not needs(o.stats[o.blessing], overrideLeft(o)) then return nil end
	if anyway and o.dead then return nil end
	if salvationOnTank(o.unit, o.blessing) then return nil end

	if dry then
		if not inRangePreview(o.unit, BLESSING_RANGE) then
			return nil, string.format("%s (%s): out of range or sight.", blessingName(o.blessing), o.name)
		end
		return "cast", nil, { override = o, class = o.class, blessing = o.blessing, target = o.name,
			text = string.format("%s -> %s", blessingName(o.blessing), o.name) }
	end

	if onCooldown(o.spell) then return "gcd" end

	CastSpell(o.spell, BOOKTYPE_SPELL)
	if not SpellIsTargeting() then return nil end
	if not inRange(o.unit) then
		SpellStopTargeting()
		return nil, string.format("%s (%s): out of range or sight.", blessingName(o.blessing), o.name)
	end

	SpellTargetUnit(o.unit)
	markCast(key)
	setTimer("player", o.name, PALLYPOWER_NORMALBLESSINGDURATION)
	feedback(string.format("%s -> %s", blessingName(o.blessing), o.name), OK_R, OK_G, OK_B)
	return "cast"
end

-- Right-click fallback: the normal (single-target) version of a group's blessing on one member
-- who'd otherwise get the Greater Blessing (no override) and is missing it. Only when the
-- blessing is missing - a member who has the Greater one isn't touched.
-- dry = preview only, like tryOverride's.
local function tryNormal(group, m, anyway, dry)
	local g = group.blessing
	local spell = smallSpell(g)
	if not spell then return nil end
	local key = "N" .. m.name .. ":" .. g
	if recentlyCast(key) or recentlyCast("G" .. g .. ":" .. group.class) then return nil end
	if m.dead or (m.stats[g] and not anyway) then return nil end
	local refresh = m.stats[g]
	if salvationOnTank(m.unit, g) then return nil end
	if not UnitIsVisible(m.unit) then return nil end

	if dry then
		if not inRangePreview(m.unit, BLESSING_RANGE) then return nil end
		return "cast", nil, { group = group, class = group.class, blessing = g, target = m.name,
			text = string.format("%s -> %s", blessingName(g), m.name) }
	end

	if onCooldown(spell) then return "gcd" end

	CastSpell(spell, BOOKTYPE_SPELL)
	if not SpellIsTargeting() then return nil end
	if not inRange(m.unit) then
		SpellStopTargeting()
		return nil, string.format("%s (%s): out of range or sight.", blessingName(g), m.name)
	end

	SpellTargetUnit(m.unit)
	markCast(key)
	if refresh then
		memberTimers[m.name] = { blessing = g, expiry = GetTime() + PALLYPOWER_NORMALBLESSINGDURATION }
	end
	feedback(string.format("%s -> %s", blessingName(g), m.name), OK_R, OK_G, OK_B)
	return "cast"
end

-- Right-click order: overrides first (of onlyGroup's class when one is given), then unless
-- overridesOnly the normal blessing on members who'd otherwise get the Greater one (only
-- onlyGroup's). anyway (Shift): also refreshes, so both lists go missing first, then
-- unknown time, then lowest time. Returns { {o=} | {group=, m=} } in the order to try them.
local function rightClickPlan(groups, overrides, onlyGroup, overridesOnly, anyway)
	local function sortKey(has, left)
		if not has then return -2 end
		return left or -1
	end
	local plan = {}
	local cls = onlyGroup and onlyGroup.class
	local olist = {}
	for _, o in ipairs(overrides) do
		if not cls or o.class == cls or (cls == 0 and o.class == 9) then
			table.insert(olist, { o = o, key = sortKey(o.stats[o.blessing], overrideLeft(o)) })
		end
	end
	if anyway then table.sort(olist, function(a, b) return a.key < b.key end) end
	for _, e in ipairs(olist) do table.insert(plan, e) end
	if not overridesOnly then
		local mlist = {}
		for _, group in ipairs(groups) do
			if not onlyGroup or group.class == onlyGroup.class then
				local left = timeLeft("cast", group.blessing .. group.class)
				for _, m in ipairs(group.plain) do
					table.insert(mlist, { group = group, m = m,
						key = sortKey(m.stats[group.blessing], memberLeft(left, group.blessing, m.name, m.unit)) })
				end
			end
		end
		if anyway then table.sort(mlist, function(a, b) return a.key < b.key end) end
		for _, e in ipairs(mlist) do table.insert(plan, e) end
	end
	return plan
end

------------------------------------------------------------------------------
-- Personal passives: your aura (when one is assigned to you in PallyPower) and Righteous Fury
-- (when PallyPower's Righteous Fury button is enabled and you know it). Cast on yourself,
-- always before any blessing when one is missing.
------------------------------------------------------------------------------

local function playerHasBuff(path)
	local want = buffTexture(path)
	if not want then return false end
	for i = 1, 40 do
		local t = UnitBuff("player", i)
		if not t then break end
		if t == want then return true end
	end
	return false
end

-- Time left of one of your own buffs (1.12 knows these for the player), or nil.
local function playerBuffLeft(path)
	local want = buffTexture(path)
	if not want or not GetPlayerBuff then return nil end
	for i = 0, 31 do
		local idx = GetPlayerBuff(i, "HELPFUL")
		if not idx or idx < 0 then break end
		if GetPlayerBuffTexture(idx) == want then
			local left = GetPlayerBuffTimeLeft(idx)
			if left and left > 0 then return left end
			return nil
		end
	end
	return nil
end

-- { kind = "aura" | "rf", name, icon, has, left, spell (aura: spellbook id) }
local function personalList()
	local list = {}
	local name = me()
	local auraId = PallyPower_AuraAssignments and PallyPower_AuraAssignments[name]
	local auras = AllPallysAuras and AllPallysAuras[name]
	if auraId and auraId ~= -1 and auras and auras[auraId] and auras[auraId]["id"] and AuraIcons and AuraIcons[auraId] then
		local auraName = PallyPower_AuraID and PallyPower_AuraID[auraId]
		table.insert(list, { kind = "aura", name = (auraName or "Assigned") .. " Aura", icon = AuraIcons[auraId],
			has = playerHasBuff(AuraIcons[auraId]), spell = auras[auraId]["id"] })
	end
	if PP_PerUser and PP_PerUser.showrfbutton == true and hasRighteousFury == true and nameRighteousFury
		and BuffIcon and BuffIcon[9] then
		local has = playerHasBuff(BuffIcon[9])
		table.insert(list, { kind = "rf", name = nameRighteousFury,
			icon = PallyPower_RighteousFury or BuffIcon[9],
			has = has, left = has and playerBuffLeft(BuffIcon[9]) or nil })
	end
	return list
end

local function tryPersonal(pp, dry)
	if pp.has or recentlyCast("P" .. pp.kind .. ":" .. (pp.spell or "")) then return nil end
	if dry then
		return "cast", nil, { personal = true, text = pp.name }
	end
	if pp.kind == "aura" then
		if onCooldown(pp.spell) then return "gcd" end
		CastSpell(pp.spell, BOOKTYPE_SPELL)
	else
		CastSpellByName(pp.name)
	end
	if SpellIsTargeting() then
		SpellStopTargeting()
		return nil
	end
	markCast("P" .. pp.kind .. ":" .. (pp.spell or ""))
	feedback(pp.name, OK_R, OK_G, OK_B)
	return "cast"
end

-- What would a left-click do right now (with the modifiers currently held)? Same order and
-- rules as doNext, but with distance/LoS instead of a spell on the cursor.
-- Returns info {group or override, class, blessing, text}, or nil plus the first blocking note
-- and what it blocked ({group=} or {override=}).
local function preview(force)
	local groups, overrides = collect()
	local note, subject, result, n, info
	for _, pp in ipairs(personalList()) do
		result, n, info = tryPersonal(pp, true)
		if result then return info end
	end
	for _, group in ipairs(groups) do
		result, n, info = tryGroup(group, force, true)
		if n and not note then note, subject = n, { group = group } end
		if result then return info end
	end
	for _, o in ipairs(overrides) do
		result, n, info = tryOverride(o, true)
		if n and not note then note, subject = n, { override = o } end
		if result then return info end
	end
	return nil, note, subject
end

-- Mouse-wheel selection: instead of the next action, the button can be pointed at one step of
-- the work list - a Greater Blessing group (key = class id) or the individual overrides
-- ("ind"). Clicks then work on that step only. Falls back to "next" when the mouse leaves
-- the button.
local selectedKey = nil

-- Button status (filled in by computeStatus once a second). Declared here so the click
-- handler can see what the button is showing.
local status = { missing = 0, dead = 0, unknown = 0, minLeft = nil }

local function stepKey(subject)
	if not subject then return nil end
	if subject.personal then return "personal" end
	if subject.group then return subject.group.class end
	if subject.override or subject.individual then return "ind" end
	return nil
end

-- Steps in the order the button works through them.
local function steps()
	local list = {}
	if table.getn(personalList()) > 0 then table.insert(list, "personal") end
	local groups, overrides = collect(true)
	for _, group in ipairs(groups) do
		if table.getn(group.plain) > 0 then table.insert(list, group.class) end
	end
	if table.getn(overrides) > 0 then table.insert(list, "ind") end
	return list
end

local function doNext(button)
	local _, cls = UnitClass("player")
	if cls ~= "PALADIN" then return end
	if not (AllPallys and CurrentBuffs and PallyPower_Assignments) then
		feedback("PallyPowerTW isn't loaded.", NOTE_R, NOTE_G, NOTE_B)
		return
	end
	if PallyPower_ScanSpells then PallyPower_ScanSpells() end
	if not AllPallys[me()] then
		feedback("PallyPower hasn't scanned your blessings yet.", NOTE_R, NOTE_G, NOTE_B)
		return
	end

	local force = IsShiftKeyDown()  -- "cast anyway"
	local rightClick = (button == "RightButton")
	local overridesOnly = false
	local groups, overrides = collect()
	local note

	local personal = personalList()
	if table.getn(groups) == 0 and table.getn(overrides) == 0 and table.getn(personal) == 0 then
		feedback("No blessings assigned to you in PallyPower.", NOTE_R, NOTE_G, NOTE_B)
		return
	end

	-- Every click works on what the button shows (the next step, or the one picked with the
	-- wheel): your personal passives, one Greater Blessing group, or the overrides. Only when
	-- it shows nothing does a left-click go through everything in order.
	local subj = status.subject
	local onlyGroup, personalOnly
	if subj and subj.personal then
		personalOnly = true
	elseif subj and subj.group then
		for _, group in ipairs(groups) do
			if group.class == subj.group.class then onlyGroup = group end
		end
		if not onlyGroup then
			feedback(string.format("Greater %s (%s): nobody alive to bless.", blessingName(subj.group.blessing), className(subj.group.class)), NOTE_R, NOTE_G, NOTE_B)
			return
		end
	elseif subj and (subj.override or subj.individual) then
		overridesOnly = true
	end

	if personalOnly or not subj then
		for _, pp in ipairs(personal) do
			local r = tryPersonal(pp)
			if r then return end
		end
		if personalOnly then
			feedback("Your aura and Righteous Fury are up.", NOTE_R, NOTE_G, NOTE_B)
			return
		end
	end

	beginCasting()

	local result, n
	if rightClick then
		-- Right-click: overrides first (of the group shown), then the normal blessing on
		-- members who'd otherwise get the Greater one and are missing it - not when the button
		-- shows the overrides. Shift: "cast anyway" - also refresh blessings that are still
		-- on, starting with the one that runs out first (missing first, then unknown time,
		-- then lowest time).
		local anyway = IsShiftKeyDown()
		for _, e in ipairs(rightClickPlan(groups, overrides, onlyGroup, overridesOnly, anyway)) do
			if e.o then
				result, n = tryOverride(e.o, nil, anyway)
			else
				result, n = tryNormal(e.group, e.m, anyway)
			end
			note = note or n
			if result then break end
		end
	elseif onlyGroup then
		-- Shift: cast anyway - past anyone out of range / sight / not here, and even when the
		-- members already have the blessing (refresh, or replace normal versions).
		result, note = tryGroup(onlyGroup, force, nil, force)
	else
		if not overridesOnly then
			for _, group in ipairs(groups) do
				result, n = tryGroup(group, force)
				note = note or n
				if result then break end
			end
		end
		if not result then
			for _, o in ipairs(overrides) do
				result, n = tryOverride(o)
				note = note or n
				if result then break end
			end
		end
	end

	if SpellIsTargeting() then SpellStopTargeting() end
	endCasting()

	if result == "cast" or result == "gcd" then return end
	if note then
		feedback(note, NOTE_R, NOTE_G, NOTE_B)
	elseif onlyGroup and not rightClick then
		feedback(string.format("Greater %s (%s) is up.", blessingName(onlyGroup.blessing), className(onlyGroup.class)), NOTE_R, NOTE_G, NOTE_B)
	elseif rightClick then
		feedback(overridesOnly and "All overrides are up." or "Nobody is missing a blessing.", NOTE_R, NOTE_G, NOTE_B)
	else
		feedback(overridesOnly and "All overrides are up." or "All blessings are up.", NOTE_R, NOTE_G, NOTE_B)
	end
end


------------------------------------------------------------------------------
-- The button
------------------------------------------------------------------------------

-- Built from PallyPower's own buff-bar button template so it looks like the class buttons:
-- backdrop tinted by state, class + blessing icon of the next thing to cast, time top-right,
-- notice under it, count of missing at the bottom. Sits on top of the buff bar (child of it,
-- so it moves, scales and hides with the bar).
local button = CreateFrame("Button", "PPNextButton", UIParent, "PallyPowerBuffButtonTemplate")
button:SetPoint("CENTER", UIParent, "CENTER", 0, -150)  -- fallback until attached
button:SetScript("OnMouseWheel", nil)
button:EnableMouseWheel(false)
button:Hide()

local timeText   = getglobal("PPNextButtonTime")
local noticeText = getglobal("PPNextButtonTime2")
local countText  = getglobal("PPNextButtonText")
local classIcon  = getglobal("PPNextButtonClassIcon")
local buffIcon   = getglobal("PPNextButtonBuffIcon")

local IDLE_CLASS_ICON = "Interface\\AddOns\\PallyPowerTW\\Icons\\Paladin"
local IDLE_BUFF_ICON = "Interface\\Icons\\Spell_Holy_GreaterBlessingofKings"

local function attachToBuffBar()
	local bar = getglobal("PallyPowerBuffBar")
	if not bar then return false end
	button:SetParent(bar)
	button:SetFrameLevel(bar:GetFrameLevel() + 5)
	button:ClearAllPoints()
	local title = getglobal("PallyPowerBuffBarTitle")
	if PPNext_Settings.below and title then
		button:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 5, -2)  -- "below" layout: under the title (grows down/right)
	else
		button:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 5, 2)    -- below layout off: on top of the bar (grows up/right)
	end
	return true
end


-- Status, from PallyPower's buff scan and timers only (no range checks: those need a spell on
-- the cursor). Members out of sight count as fine, like on PallyPower's own buttons.
local function computeStatus()
	local s = { missing = 0, dead = 0, unknown = 0, minLeft = nil }
	local nextC, nextB, nextRank  -- icon preview: first missing, else first unknown/short
	local function consider(c, b, rank)
		if not nextRank or rank < nextRank then nextC, nextB, nextRank = c, b, rank end
	end
	local function track(has, left, c, b, dead)
		if dead then
			-- Like PallyPower: dead members without the blessing are counted separately;
			-- they can't be blessed, so they don't make the button red.
			if not has then s.dead = s.dead + 1 end
		elseif not has then
			s.missing = s.missing + 1
			consider(c, b, 1)
		elseif left == nil then
			s.unknown = s.unknown + 1
			consider(c, b, 2)
		else
			if not s.minLeft or left < s.minLeft then s.minLeft, s.minClass, s.minBlessing = left, c, b end
			if left < REFRESH_BELOW then consider(c, b, 3) end
		end
	end

	if AllPallys and AllPallys[me()] and CurrentBuffs and PallyPower_Assignments then
		local groups, overrides = collect(true)
		for _, group in ipairs(groups) do
			local g, c = group.blessing, group.class
			local left = timeLeft("cast", g .. c)
			for _, m in ipairs(group.plain) do
				if UnitIsVisible(m.unit) and not salvationOnTank(m.unit, g) then
					local before = s.minLeft
					local mleft = memberLeft(left, g, m.name, m.unit)
					-- only the normal version and no known time: covered, not "unknown"
					if not (mleft == nil and m.stats[g] and normalOnly(m.unit, g)) then
						track(m.stats[g], mleft, c, g, m.dead)
					end
					if s.minLeft ~= before then s.minSubject = { group = group } end
				end
			end
		end
		for _, o in ipairs(overrides) do
			if UnitIsVisible(o.unit) and not salvationOnTank(o.unit, o.blessing) then
				local before = s.minLeft
				track(o.stats[o.blessing], overrideLeft(o), o.class, o.blessing, o.dead)
				if s.minLeft ~= before then s.minSubject = { override = o } end
			end
		end
	end

	s.nextClass, s.nextBlessing = nextC, nextB
	-- Nothing needs doing: the icons show what the corner time is about (the blessing that
	-- runs out first), so time and icons belong together.
	if not nextC and s.minClass then
		s.nextClass, s.nextBlessing = s.minClass, s.minBlessing
	end

	-- personal passives that are missing count as missing (red button)
	for _, pp in ipairs(personalList()) do
		if not pp.has then s.missing = s.missing + 1 end
	end

	-- Real reachability of the next click (range + line of sight).
	if AllPallys and AllPallys[me()] and CurrentBuffs and PallyPower_Assignments then
		local blockedSubject
		s.next, s.blocked, blockedSubject = preview(IsShiftKeyDown())
		if s.next then
			s.nextClass, s.nextBlessing = s.next.class, s.next.blessing
		end
		s.subject = s.next or blockedSubject  -- who the target list shows
		-- Nothing to do: the button is on whatever runs out first (the corner time's group /
		-- player), so its list, right-click and wheel start from there.
		if not s.subject and s.minSubject then s.subject = s.minSubject end

		-- Wheel selection overrides what the icons and list show.
		if selectedKey then
			local list = steps()
			for i, k in ipairs(list) do
				if k == selectedKey then s.selIndex, s.selCount = i, table.getn(list) end
			end
			if not s.selIndex then
				selectedKey = nil  -- the step is gone (assignment changed, member left...)
			elseif selectedKey == "personal" then
				s.selected = { personal = true }
			elseif selectedKey == "ind" then
				local _, overrides = collect(true)
				local pick = overrides[1]
				for _, o in ipairs(overrides) do
					if not o.dead and needs(o.stats[o.blessing], overrideLeft(o)) then pick = o; break end
				end
				s.selected = { individual = true }
				s.nextClass, s.nextBlessing = pick.class, pick.blessing
			else
				for _, group in ipairs((collect(true))) do
					if group.class == selectedKey then
						s.selected = { group = group }
						s.nextClass, s.nextBlessing = group.class, group.blessing
					end
				end
			end
			if s.selected then s.subject = s.selected end
		end

		-- Time left and "unknown" for what the button shows (the subject), so the corner
		-- doesn't show another group's or player's timer.
		local subj = s.subject
		if subj and subj.group then
			s.subjectLeft = groupLeft(subj.group)
			local g = subj.group.blessing
			for _, m in ipairs(subj.group.plain) do
				if m.stats[g] then s.subjectHas = true end
			end
		elseif subj and subj.override then
			local o = subj.override
			s.subjectLeft = overrideLeft(o)
			s.subjectHas = o.stats[o.blessing] and true or false
		elseif subj and subj.individual then
			local _, overrides = collect(true)
			for _, o in ipairs(overrides) do
				local t = overrideLeft(o)
				if t and (not s.subjectLeft or t < s.subjectLeft) then s.subjectLeft = t end
				if o.stats[o.blessing] then s.subjectHas = true end
			end
		end

		-- What a click on this page does, with the modifiers held now. Left-click (leftNext):
		-- on a group, the Greater Blessing and the member it's cast on; on the overrides, the
		-- first one in reach. Right-click (rightNext) is worked out when a left-click can't do
		-- anything here, or while Shift is held (both lines are shown then). ">" marks the
		-- left-click target, else the right-click one.
		local shift = IsShiftKeyDown()
		s.shift = shift
		local cgroups, coverrides = collect()  -- living members only, as a click sees them
		local onlyGroup
		if subj and subj.group then
			for _, group in ipairs(cgroups) do
				if group.class == subj.group.class then onlyGroup = group end
			end
		end
		if onlyGroup then
			local r, _, info = tryGroup(onlyGroup, shift, true, shift)
			if r then
				s.leftNext, s.markName = info, info.target
				info.text = info.text .. " (" .. info.target .. ")"
			end
		elseif subj and (subj.override or subj.individual) then
			for _, o in ipairs(coverrides) do
				local r, _, info = tryOverride(o, true)
				if r then s.leftNext, s.markName = info, info.target; break end
			end
		elseif subj and subj.personal then
			for _, pp in ipairs(personalList()) do
				local r, _, info = tryPersonal(pp, true)
				if r then s.leftNext = info; break end
			end
		end
		if subj and not subj.personal and (shift or not s.leftNext) then
			if subj.group and not onlyGroup then
				-- nobody alive in that group: nothing to right-click
			else
				for _, e in ipairs(rightClickPlan(cgroups, coverrides, onlyGroup, not subj.group, shift)) do
					local r, info, _
					if e.o then
						r, _, info = tryOverride(e.o, true, shift)
					else
						r, _, info = tryNormal(e.group, e.m, shift, true)
					end
					if r then
						s.rightNext = info
						if not s.markName then s.markName = info.target end
						break
					end
				end
			end
		end

		-- Totals over everyone in the group or raid: one category per player, for your
		-- blessing on them.
		local t = {}
		local function count(k) t[k] = (t[k] or 0) + 1 end
		local function tally(unit, dead, has, blessing, yards)
			if dead then return count("Dead") end
			if has then return count("Applied") end
			if salvationOnTank(unit, blessing) then return count("Tank") end
			local st = unitStatus(unit, false, yards)
			count(st == "OK" and "Missing" or st)
		end
		local agroups, aoverrides, unassigned = collect(true)
		for _, group in ipairs(agroups) do
			for _, m in ipairs(group.plain) do
				tally(m.unit, m.dead, m.stats[group.blessing], group.blessing, GREATER_RANGE)
			end
		end
		for _, o in ipairs(aoverrides) do
			tally(o.unit, o.dead, o.stats[o.blessing], o.blessing, BLESSING_RANGE)
		end
		for _ in ipairs(unassigned) do count("No config") end
		s.totals = t
	end
	return s
end


------------------------------------------------------------------------------
-- Target list: who the next click is about, with OK / OOR / LOS / Dead / Not Here
------------------------------------------------------------------------------

local LIST_LINE = 12
-- Two markers: STEP_MARK on a tooltip section header = the step the button is on (the group
-- or list it shows, also after a mouse-wheel pick); TARGET_MARK on a player row (button list
-- and tooltip) = who the next click is cast on.
local STEP_MARK = "|cffe6cc80->|r "
local TARGET_MARK = "|cff8ccf8c>|r "
local STATUS_COLOR = {
	["OK"]       = { 0.55, 0.80, 0.55 },
	["OOR"]      = { 0.82, 0.55, 0.55 },
	["LOS"]      = { 0.82, 0.68, 0.45 },
	["Dead"]     = { 0.60, 0.60, 0.60 },
	["Not Here"] = { 0.62, 0.62, 0.75 },
	["Tank"]     = { 0.60, 0.60, 0.60 },  -- Salvation is never cast on PallyPower-marked tanks
}

-- Totals line (top of the button and the tooltip): label order and colours (statuses as above; "missing" as in
-- the time column). Categories with 0 aren't shown.
local TOTALS = {
	{ "Applied",   0.55, 0.80, 0.55 },
	{ "Missing",   0.82, 0.54, 0.54 },
	{ "OOR" },
	{ "LOS" },
	{ "Not Here" },
	{ "Dead" },
	{ "Tank" },
	{ "No config", 0.60, 0.60, 0.60 },
}
local RIGHT_R, RIGHT_G, RIGHT_B = 0.62, 0.72, 0.85   -- right-click line (muted blue)

-- The button shows the same "page" as the tooltip does for the group / player it's on:
--   header:  [class][blessing] G. Might - Paladin               6:22
--   rows:    Kael  6:22                                           OK
--            Velandra -> [Light] 6:03                             OK    (overrides)
-- but only your assigned blessing per player (the tooltip can also list their other blessing
-- types: the "others" setting). The button grows taller with the rows; its width is
-- constant. The list doesn't take the mouse, so clicks, wheel and tooltip all go to the button.
local BUTTON_W = 180                 -- constant width (the template is 100); long names are cut off
local STATUS_W = 44                  -- right-hand status column
local TIME_W = 44                    -- time-left column
local ICON = 12
local HEADER_H = LIST_LINE + 5       -- header line
local COLHEAD_H = LIST_LINE          -- "Can cast" label line above the status column (with rows)

local list = CreateFrame("Frame", "PPNextList", button)
list:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
list:EnableMouse(false)
list:Show()

-- The template's big icons, notice and count aren't used.
classIcon:Hide()
buffIcon:Hide()
noticeText:Hide()
countText:Hide()

-- the template's time text becomes the header's right column
timeText:ClearAllPoints()
timeText:SetPoint("TOPRIGHT", list, "TOPRIGHT", -6, -3)  -- moves down with the list under the totals
timeText:SetWidth(60)
timeText:SetHeight(LIST_LINE)

button:SetWidth(BUTTON_W)

local function setButtonSize(w, h)
	if math.abs(button:GetWidth() - w) > 0.5 then button:SetWidth(w) end
	if math.abs(button:GetHeight() - h) > 0.5 then button:SetHeight(h) end
end

local function newIcon()
	local t = list:CreateTexture(nil, "OVERLAY")
	t:SetWidth(ICON)
	t:SetHeight(ICON)
	t:SetTexCoord(0.07, 0.93, 0.07, 0.93)  -- trim the icon border
	t:Hide()
	return t
end

local headerIcons = { newIcon(), newIcon() }
local listHeader = list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
listHeader:SetJustifyH("LEFT")
listHeader:SetHeight(LIST_LINE)

local listMeasure = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
listMeasure:Hide()

-- the status column says whether a cast would reach the player (range / line of sight)
local colHead = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
colHead:SetPoint("TOPRIGHT", list, "TOPRIGHT", -6, -HEADER_H)
colHead:SetJustifyH("RIGHT")
colHead:SetHeight(LIST_LINE)
colHead:SetTextColor(0.6, 0.6, 0.6)
colHead:SetText("Can cast?")
colHead:Hide()

-- "Shift-click: G. Might -> Warrior (Kael)" under the rows while Shift is held
local leftLine = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
leftLine:SetJustifyH("LEFT")
leftLine:SetWidth(BUTTON_W - 12)
leftLine:SetHeight(LIST_LINE)
leftLine:Hide()

-- "Right-click: Might -> Kael" under the rows, when a left-click can't do anything here (or
-- while Shift is held)
local rightLine = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
rightLine:SetJustifyH("LEFT")
rightLine:SetWidth(BUTTON_W - 12)
rightLine:SetHeight(LIST_LINE)
rightLine:SetTextColor(RIGHT_R, RIGHT_G, RIGHT_B)
rightLine:Hide()

-- Totals: "Applied (6)  OOR (3)  Dead (1) ...", wrapped over as many lines as needed, only
-- between categories. The lines get no width, so the game never wraps one by itself (which
-- could split "Not Here (1)"); totalsLines decides what goes on each line.
-- They sit in their own strip at the top of the button, with a thin line under them; the
-- list (header, rows, right-click line) is moved down below it.
local totalsFrame = CreateFrame("Frame", nil, button)
totalsFrame:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
totalsFrame:SetWidth(BUTTON_W)
totalsFrame:SetHeight(1)
totalsFrame:EnableMouse(false)
local totalsSep = totalsFrame:CreateTexture(nil, "OVERLAY")
totalsSep:SetTexture(0.6, 0.6, 0.6, 0.35)
totalsSep:SetHeight(1)
totalsSep:Hide()

local totalsFS = {}
local function totalsLine(i)
	if not totalsFS[i] then
		local fs = totalsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetJustifyH("LEFT")
		totalsFS[i] = fs
	end
	return totalsFS[i]
end

local function colorCode(r, g, b)
	return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- Texts of the totals lines (colour codes included), each fitting maxW pixels; with no
-- maxW, everything on one line (the tooltip).
local function totalsLines(totals, maxW)
	local lines = {}
	if not totals then return lines end
	-- Nobody you can bless is without it (wherever they are): "All applied (n)" instead.
	local allUp = true
	for _, k in ipairs({ "Missing", "OOR", "LOS", "Not Here" }) do
		if (totals[k] or 0) > 0 then allUp = false end
	end
	local cur, curPlain = nil, nil
	for _, def in ipairs(TOTALS) do
		local label = def[1]
		local n = totals[label]
		if n and n > 0 then
			local r, g, b = def[2], def[3], def[4]
			if not r then
				local col = STATUS_COLOR[label]
				r, g, b = col[1], col[2], col[3]
			end
			if label == "Applied" and allUp then label = "All applied" end
			local plain = label .. " (" .. n .. ")"
			local piece = colorCode(r, g, b) .. plain .. "|r"
			if cur then
				listMeasure:SetText(curPlain .. "  " .. plain)
				if maxW and listMeasure:GetStringWidth() > maxW then
					table.insert(lines, cur)
					cur, curPlain = piece, plain
				else
					cur, curPlain = cur .. "  " .. piece, curPlain .. "  " .. plain
				end
			else
				cur, curPlain = piece, plain
			end
		end
	end
	if cur then table.insert(lines, cur) end
	return lines
end

local listRows = {}
local function listRow(i)
	if not listRows[i] then
		local text = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetPoint("TOPLEFT", list, "TOPLEFT", 6, -HEADER_H - COLHEAD_H - (i - 1) * LIST_LINE)
		text:SetJustifyH("LEFT")
		text:SetHeight(LIST_LINE)
		local st = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		st:SetPoint("TOP", text, "TOP", 0, 0)
		st:SetPoint("RIGHT", list, "RIGHT", -6, 0)
		st:SetWidth(STATUS_W)
		st:SetHeight(LIST_LINE)
		st:SetJustifyH("RIGHT")
		local icon = newIcon()
		icon:SetPoint("RIGHT", list, "RIGHT", -6 - STATUS_W - 4 - TIME_W - 3, 0)
		icon:SetPoint("TOP", text, "TOP", 0, 0)
		local after = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")  -- time column
		after:SetPoint("TOP", text, "TOP", 0, 0)
		after:SetPoint("RIGHT", list, "RIGHT", -6 - STATUS_W - 4, 0)
		after:SetWidth(TIME_W)
		after:SetJustifyH("RIGHT")
		after:SetHeight(LIST_LINE)
		listRows[i] = { text = text, status = st, icon = icon, after = after }
	end
	return listRows[i]
end

local function classColor(unit)
	local _, token = UnitClass(unit)
	local cc = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
	if cc then return cc.r, cc.g, cc.b end
	return 1, 1, 1
end

-- Time left: the timer if known; "no timer" when someone has the blessing but there's no timer
-- (cast by hand, after a reload...); "missing" (muted red) when nobody has it.
local function timeLabel(left, has)
	if not has then return "|cffd08a8amissing|r" end
	if left then return PallyPower_FormatTime(left) end
	return "no timer"
end

-- A player's assigned blessing, as in the tooltip: its time (light), "no timer", or
-- "missing" (muted red). In a Greater Blessing group, a time that matches the group's time
-- (in the header) isn't repeated: it's left blank.
local SAME_TIME = 3  -- seconds
local SINGLE_TEXT = "|cffd8c890single|r"  -- has only the normal version (Shift + left-click upgrades it)
local function assignedText(has, left, headerLeft)
	if not has then return "|cffd08a8amissing|r" end
	if left and headerLeft and math.abs(left - headerLeft) < SAME_TIME then return "" end
	return "|cffd8d8d8" .. (left and PallyPower_FormatTime(left) or "no timer") .. "|r"
end

-- Header and rows for the page the button is on: a Greater Blessing group (its members
-- without an override, dead ones included), or the individual overrides.
local function listEntries(subject)
	local page = { icons = {}, rows = {} }
	if subject.personal then
		page.text = "Personal"
		page.right = ""
		for _, pp in ipairs(personalList()) do
			local t
			if not pp.has then
				t = "|cffd08a8amissing|r"
			elseif pp.left then
				t = "|cffd8d8d8" .. PallyPower_FormatTime(pp.left) .. "|r"
			else
				t = "|cffd8d8d8on|r"
			end
			table.insert(page.rows, { unit = "player", text = pp.name, icon = pp.icon, time = t,
				status = "OK", needed = not pp.has })
		end
	elseif subject.group then
		local g, c = subject.group.blessing, subject.group.class
		local grp = subject.group
		for _, full in ipairs((collect(true))) do  -- same group, with dead members
			if full.class == c then grp = full; break end
		end
		local left = timeLeft("cast", g .. c)
		local anyHas = false
		local headerLeft = groupLeft(grp)
		page.icons = { PallyPower_ClassTexture and PallyPower_ClassTexture[c], BlessingIcon and BlessingIcon[g] }
		page.text = string.format("G. %s - %s", blessingName(g), className(c))  -- "G." = Greater (short, the button is narrow)
		for _, m in ipairs(grp.plain) do
			if m.stats[g] then anyHas = true end
			local mleft = memberLeft(left, g, m.name, m.unit)
			local st = salvationOnTank(m.unit, g) and "Tank" or unitStatus(m.unit, m.dead, GREATER_RANGE)
			local single = m.stats[g] and normalOnly(m.unit, g)
			table.insert(page.rows, { unit = m.unit, sortName = m.name, name = m.name,
				text = m.name, time = single and SINGLE_TEXT or assignedText(m.stats[g], mleft, headerLeft),
				status = st, needed = memberNeeds(g, m, mleft) })
		end
		table.sort(page.rows, function(x, y) return x.sortName < y.sortName end)
		page.right = timeLabel(headerLeft, anyHas)
	else
		page.text = "Individual"
		page.right = ""
		local _, overrides = collect(true)
		for _, o in ipairs(overrides) do
			local oleft = overrideLeft(o)
			local st = salvationOnTank(o.unit, o.blessing) and "Tank" or unitStatus(o.unit, o.dead, BLESSING_RANGE)
			table.insert(page.rows, { unit = o.unit, name = o.name,
				text = o.name, icon = BlessingIcon and BlessingIcon[o.blessing],
				time = assignedText(o.stats[o.blessing], oleft),
				status = st, needed = needs(o.stats[o.blessing], oleft) })
		end
	end
	return page
end

local function refreshList()
	local subject = status.subject
	local page
	if subject then
		page = listEntries(subject)
	else
		page = { icons = {}, rows = {}, text = "Nothing assigned", right = "" }
	end
	if PPNext_Settings.list == false then page.rows = {} end

	-- header: icons, text (+ wheel position), time on the right
	local x = 6
	for i = 1, 2 do
		local tex = headerIcons[i]
		if page.icons[i] then
			tex:SetTexture(page.icons[i])
			tex:ClearAllPoints()
			tex:SetPoint("TOPLEFT", list, "TOPLEFT", x, -3)
			tex:Show()
			x = x + ICON + 2
		else
			tex:Hide()
		end
	end
	if x > 6 then x = x + 1 end
	listHeader:ClearAllPoints()
	listHeader:SetPoint("TOPLEFT", list, "TOPLEFT", x, -3)
	listHeader:SetWidth(BUTTON_W - x - 6 - 50)
	local text = page.text
	if status.selIndex then
		text = text .. " |cff9db8d8" .. status.selIndex .. "/" .. status.selCount .. "|r"
	end
	listHeader:SetText(text)
	timeText:SetText(page.right or "")

	-- rows
	for i, r in ipairs(page.rows) do
		local row = listRow(i)
		-- columns: name | icon (overrides: their blessing) | time | status
		local nameW = BUTTON_W - 12 - STATUS_W - 4 - TIME_W - 4
		if r.icon then
			row.icon:SetTexture(r.icon)
			row.icon:Show()
			nameW = nameW - ICON - 3
		else
			row.icon:Hide()
		end
		row.text:SetWidth(nameW)
		if r.name and r.name == status.markName then
			row.text:SetText(TARGET_MARK .. r.text)
		else
			row.text:SetText(r.text)
		end
		row.after:SetText(r.time or "")
		row.after:Show()
		if r.needed then
			row.text:SetTextColor(classColor(r.unit))
		else
			row.text:SetTextColor(0.5, 0.5, 0.5)  -- already has it
		end
		row.after:SetTextColor(row.text:GetTextColor())
		row.status:SetText(r.status)
		local col = STATUS_COLOR[r.status] or STATUS_COLOR["OK"]
		row.status:SetTextColor(col[1], col[2], col[3])
		row.text:Show()
		row.status:Show()
	end
	for i = table.getn(page.rows) + 1, table.getn(listRows) do
		listRows[i].text:Hide()
		listRows[i].status:Hide()
		listRows[i].icon:Hide()
		listRows[i].after:Hide()
	end

	local nrows = table.getn(page.rows)
	if nrows > 0 then colHead:Show() else colHead:Hide() end
	local y = HEADER_H + (nrows > 0 and (COLHEAD_H + nrows * LIST_LINE + 2) or 0)

	-- click lines: with Shift held, what Shift-click and Shift-right-click do here; without,
	-- the right-click line only when a left-click can't do anything on this page
	if status.shift then
		leftLine:ClearAllPoints()
		leftLine:SetPoint("TOPLEFT", list, "TOPLEFT", 6, -y)
		if status.leftNext then
			leftLine:SetText("Shift-click: " .. (string.gsub(status.leftNext.text, "^Greater ", "G. ")))
			leftLine:SetTextColor(OK_R, OK_G, OK_B)
		else
			leftLine:SetText("Shift-click: nothing to cast here")
			leftLine:SetTextColor(0.6, 0.6, 0.6)
		end
		leftLine:Show()
		y = y + LIST_LINE
	else
		leftLine:Hide()
	end
	if status.rightNext then
		rightLine:ClearAllPoints()
		rightLine:SetPoint("TOPLEFT", list, "TOPLEFT", 6, -y)
		rightLine:SetText((status.shift and "Shift-right: " or "Right-click: ") .. status.rightNext.text)
		rightLine:Show()
		y = y + LIST_LINE
	else
		rightLine:Hide()
	end

	local listH = (y == HEADER_H) and HEADER_H or (y + 3)

	-- totals at the top, wrapped to the button's width, then a thin line; the list goes below
	local tlines = totalsLines(status.totals, BUTTON_W - 12 - 2)  -- a little slack for rounding
	local top = 0
	for i, text in ipairs(tlines) do
		local fs = totalsLine(i)
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", totalsFrame, "TOPLEFT", 6, -3 - (i - 1) * LIST_LINE)
		fs:SetText(text)
		fs:Show()
	end
	for i = table.getn(tlines) + 1, table.getn(totalsFS) do totalsFS[i]:Hide() end
	if table.getn(tlines) > 0 then
		local sepY = 3 + table.getn(tlines) * LIST_LINE + 1
		totalsSep:ClearAllPoints()
		totalsSep:SetPoint("TOPLEFT", totalsFrame, "TOPLEFT", 6, -sepY)
		totalsSep:SetPoint("TOPRIGHT", totalsFrame, "TOPRIGHT", -6, -sepY)
		totalsSep:Show()
		top = sepY + 1
	else
		totalsSep:Hide()
	end
	totalsFrame:SetHeight(math.max(top, 1))

	list:ClearAllPoints()
	list:SetPoint("TOPLEFT", button, "TOPLEFT", 0, -top)
	list:SetWidth(BUTTON_W)
	list:SetHeight(listH)
	setButtonSize(BUTTON_W, top + listH)
end

-- Cast detection: blessings cast some other way (spellbook, macro, keybind...) have no timer
-- anywhere. When someone who was in sight and missing their blessing has it at the next
-- check (once a second), it was just cast: start a timer for it.
--   override member          -> their individual timer (normal blessing duration)
--   2+ members of a group at once -> the group's Greater Blessing timer
--   1 member of a group      -> that member's normal-blessing timer (shorter, so it errs
--                               on the side of refreshing early)
-- Only fills in timers that are missing. Like PallyPower's own scan, it can't tell which
-- paladin cast a blessing.
local lastSeen = {}  -- name -> { b = blessing, has = bool, vis = bool }

-- "appeared" (was in sight and missing it, now has it), "gone" (had it, now doesn't) or nil.
local function blessingChange(name, b, has, vis)
	local prev = lastSeen[name]
	lastSeen[name] = { b = b, has = has, vis = vis }
	if not prev or prev.b ~= b then return nil end
	if prev.vis and not prev.has and has and vis then return "appeared" end
	if prev.has and not has then return "gone" end
	return nil
end

local function observeCasts()
	if not (AllPallys and AllPallys[me()] and CurrentBuffs and PallyPower_Assignments) then return end
	local groups, overrides = collect(true)
	local now = GetTime()
	for _, o in ipairs(overrides) do
		local has = o.stats[o.blessing] and true or false
		local change = blessingChange(o.name, o.blessing, has, UnitIsVisible(o.unit) and true or false)
		if change == "appeared" then
			setTimer("player", o.name, PALLYPOWER_NORMALBLESSINGDURATION)
		elseif change == "gone" then
			clearTimer("player", o.name)
		end
	end
	for _, group in ipairs(groups) do
		local g, c = group.blessing, group.class
		local appeared = {}
		for _, m in ipairs(group.plain) do
			local has = m.stats[g] and true or false
			local change = blessingChange(m.name, g, has, UnitIsVisible(m.unit) and true or false)
			if change == "appeared" then
				table.insert(appeared, m)
			elseif change == "gone" then
				memberTimers[m.name] = nil
			end
		end
		if table.getn(appeared) >= 2 then
			-- several at once: a Greater Blessing
			setTimer("cast", g .. c, PALLYPOWER_GREATERBLESSINGDURATION)
			for _, m in ipairs(appeared) do memberTimers[m.name] = nil end
		else
			for _, m in ipairs(appeared) do
				memberTimers[m.name] = { blessing = g, expiry = now + PALLYPOWER_NORMALBLESSINGDURATION }
			end
		end
	end
end

local function refreshButton()
	observeCasts()
	status = computeStatus()
	local alpha = (PP_PerUser and PP_PerUser.transparency) or 0.5

	-- Same colours as PallyPower's buttons: red = something missing, yellow = needs a refresh
	-- (unknown time, or < 5 min) or someone dead is missing it, green = all good.
	if status.missing > 0 then
		button:SetBackdropColor(1, 0, 0, alpha)
	elseif status.dead > 0 or status.unknown > 0 or (status.minLeft and status.minLeft < REFRESH_BELOW) then
		button:SetBackdropColor(1, 1, 0.5, alpha)
	else
		button:SetBackdropColor(0, 1, 0, alpha)
	end

	refreshList()
end

local HELP = {
	"Every click works on what the button shows.",
	"Left-click: your aura / Righteous Fury first when missing (as set",
	"   up in PallyPower), then the next missing blessing",
	"   (or one whose time left PallyPower doesn't know).",
	"   Greater Blessings first (classes with overrides first),",
	"   then your individual overrides.",
	"   Low time left only shows on the button (yellow + time).",
	"Shift: cast the Greater Blessing shown anyway, even if some of",
	"   the class is not here, out of range or out of line of sight,",
	"   or everyone already has it: refreshes it, and upgrades",
	"   members who only have the normal version (\"single\").",
	"Right-click: overrides first, then the normal (single) blessing",
	"   on one member missing their Greater Blessing per click.",
	"Shift+right-click: cast anyway - also refresh blessings that are",
	"   still on, the one that runs out first first.",
	"Mouse wheel: pick a group (or the overrides); clicks then work",
	"   on that one. Back to next when the mouse leaves the button.",
	"List in the button: who the next click is about -",
	"   OK, OOR (range), LOS (line of sight), Dead, Not Here.",
	"   Grey names already have it.   /ppnext list toggles it.",
	"   > marks who the click is cast on. When a left-click can't",
	"   do anything there, a line shows what a right-click would do.",
	"   Holding Shift shows what Shift-click and Shift-right-click do.",
	"Totals line: everyone you bless - Applied, Missing (in reach),",
	"   OOR, LOS, Not Here, Dead, Tank, No config (nothing assigned).",
	"PallyPower's buttons stay hidden until you mouse over the",
	"   \"Pally Buffs\" title.   /ppnext collapse toggles it.",
	"/ppnext below: this button under the title, bar grows up (default).",
	"/ppnext opacity 10-100: fade the bar out of combat (100 = off, 70 default);",
	"   fully visible in combat and while the mouse is over it.",
	"/ppnext others: other blessing types in the tooltip (off) -",
	"   blessings on a player besides the one you give them.",
	"Settings explain themselves on mouseover (Tooltips setting).",
	"Moves with PallyPower's buff bar.   /ppnext for options.",
}

local HEAD_R, HEAD_G, HEAD_B = 0.90, 0.80, 0.50

------------------------------------------------------------------------------
-- Tooltip icons. 1.12 tooltips can't show textures inside their text, so small textures are
-- laid over the tooltip: the line's text gets spaces where an icon goes, the text before it
-- is measured with the line's own font, and the icon is anchored at that offset.
------------------------------------------------------------------------------

local TIP_ICON = 13
local tipLayer = CreateFrame("Frame", nil, GameTooltip)
tipLayer:SetAllPoints(GameTooltip)
local tipIcons, tipIconsUsed, tipPending = {}, 0, {}
local tipMeasure = tipLayer:CreateFontString(nil, "OVERLAY")
tipMeasure:Hide()

local tipTexts, tipTextsUsed, tipRowsPending = {}, 0, {}

local function hideTipIcons()
	for i = 1, table.getn(tipIcons) do tipIcons[i]:Hide() end
	tipIconsUsed = 0
	for i = 1, table.getn(tipTexts) do tipTexts[i]:Hide() end
	tipTextsUsed = 0
end

-- The tooltip is shared: once another frame owns it, our icons go.
tipLayer:SetScript("OnUpdate", function()
	if (tipIconsUsed > 0 or tipTextsUsed > 0) and not GameTooltip:IsOwned(button) then hideTipIcons() end
end)

local function measureWidth(fs, text)
	local font, size, flags = fs:GetFont()
	if not font then return 0 end
	tipMeasure:SetFont(font, size, flags)
	tipMeasure:SetText(text)
	return tipMeasure:GetStringWidth() or 0
end

-- Spaces wide enough for one icon, in the tooltip's line font.
local tipGap
local function iconGap()
	if not tipGap then
		local fs = getglobal("GameTooltipTextLeft2")
		local w = fs and (measureWidth(fs, ".          .") - measureWidth(fs, "..")) / 10 or 3  -- trailing spaces are not measured
		if w <= 0 then w = 3 end
		tipGap = string.rep(" ", math.ceil((TIP_ICON + 3) / w))
	end
	return tipGap
end

-- Adds a line from segments: strings, or { icon = texturePath }.
local function tipLine(segs, right, lr, lg, lb, rr, rg, rb)
	local text = ""
	local icons = {}
	for _, sg in ipairs(segs) do
		if type(sg) == "table" then
			if sg.icon then
				table.insert(icons, { path = sg.icon, prefix = text })
				text = text .. iconGap()
			end
		else
			text = text .. sg
		end
	end
	if right then
		GameTooltip:AddDoubleLine(text, right, lr, lg, lb, rr, rg, rb)
	else
		GameTooltip:AddLine(text, lr, lg, lb)
	end
	local line = GameTooltip:NumLines()
	for _, ic in ipairs(icons) do
		ic.line = line
		table.insert(tipPending, ic)
	end
end

local function placeTipIcons()
	for _, ic in ipairs(tipPending) do
		local fs = getglobal("GameTooltipTextLeft" .. ic.line)
		if fs then
			tipIconsUsed = tipIconsUsed + 1
			local tex = tipIcons[tipIconsUsed]
			if not tex then
				tex = tipLayer:CreateTexture(nil, "OVERLAY")
				tex:SetWidth(TIP_ICON)
				tex:SetHeight(TIP_ICON)
				tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)  -- trim the icon border
				tipIcons[tipIconsUsed] = tex
			end
			tex:SetTexture(ic.path)
			tex:ClearAllPoints()
			tex:SetPoint("LEFT", fs, "LEFT", measureWidth(fs, ic.prefix) + 1, 0)
			tex:Show()
		end
	end
	tipPending = {}
end

local function blessingIcon(b)
	return BlessingIcon and BlessingIcon[b] or nil
end

local function lineColors(unit, needed, st)
	local r, g, b = 0.5, 0.5, 0.5  -- grey: already has it
	if needed then r, g, b = classColor(unit) end
	local col = STATUS_COLOR[st] or STATUS_COLOR["OK"]
	return r, g, b, col[1], col[2], col[3]
end

------------------------------------------------------------------------------
-- Tooltip rows in columns. A tooltip line only has a left and a right text, so the middle
-- columns are overlays at fixed offsets from the line's left text:
--   name | [blessing icon] (overrides) | time left | other blessings: [icon] time ... | status
-- The left text holds the name, padded with spaces up to where the status goes, so the
-- tooltip is wide enough and the status (the line's right text) stays clear of the columns.
------------------------------------------------------------------------------

local TIP_TIME_W = 46

local function tipTextPiece()
	tipTextsUsed = tipTextsUsed + 1
	local fs = tipTexts[tipTextsUsed]
	if not fs then
		fs = tipLayer:CreateFontString(nil, "OVERLAY")
		tipTexts[tipTextsUsed] = fs
	end
	return fs
end

local function tipIconPiece()
	tipIconsUsed = tipIconsUsed + 1
	local tex = tipIcons[tipIconsUsed]
	if not tex then
		tex = tipLayer:CreateTexture(nil, "OVERLAY")
		tex:SetWidth(TIP_ICON)
		tex:SetHeight(TIP_ICON)
		tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		tipIcons[tipIconsUsed] = tex
	end
	return tex
end

-- Width of a run of spaces (trailing spaces aren't measured, so measure between dots).
local function spaceWidth(fs)
	local w = (measureWidth(fs, "." .. string.rep(" ", 20) .. ".") - measureWidth(fs, "..")) / 20
	if w <= 0 then w = 3 end
	return w
end

-- Text padded with spaces to at least px wide.
local function padTo(fs, text, px, sp)
	local w = measureWidth(fs, text)
	if w >= px then return text end
	return text .. string.rep(" ", math.ceil((px - w) / sp) + 1)
end

-- The assigned blessing's time: light time, "no timer", or "missing" (muted red); blank
-- when it matches the group header's time.
local function assignedTimeText(unit, stats, b, left, headerLeft)
	return assignedText(stats[b], auraLeft(unit, b) or left, headerLeft)
end

-- The player's other blessing types (not the one you're assigned to give them, which has its
-- own column whoever cast it), with time left.
local function otherBlessings(unit, stats, assigned)
	local list = {}
	if PPNext_Settings.others ~= true then return list end  -- setting, off by default
	for b = 0, 5 do
		if b ~= assigned and stats[b] then
			local left = auraLeft(unit, b)
			table.insert(list, { icon = blessingIcon(b),
				time = "|cff9d9d9d" .. (left and PallyPower_FormatTime(left) or "no timer") .. "|r" })
		end
	end
	return list
end

-- Adds the tooltip lines (headers, blanks and rows, in order) with the rows' columns lined up.
local function emitTipLines(lines)
	local fs = getglobal("GameTooltipTextLeft2")
	local sp = spaceWidth(fs)

	-- column positions from the widest name and the longest list of other blessings
	local nameW = 0
	for _, ln in ipairs(lines) do
		if ln.kind == "row" then
			local w = measureWidth(fs, ln.name)
			if w > nameW then nameW = w end
		end
	end
	local xIcon = nameW + 8
	local xTime = xIcon + TIP_ICON + 4
	local xOther = xTime + TIP_TIME_W + 10
	local rowEnd = xTime + TIP_TIME_W
	for _, ln in ipairs(lines) do
		if ln.kind == "row" then
			local x = xOther
			ln.otherX = {}
			for k, o in ipairs(ln.others) do
				ln.otherX[k] = x
				x = x + TIP_ICON + 3 + measureWidth(fs, o.time) + 10
			end
			if table.getn(ln.others) > 0 and x - 10 > rowEnd then rowEnd = x - 10 end
		end
	end

	for _, ln in ipairs(lines) do
		if ln.kind == "blank" then
			GameTooltip:AddLine(" ")
		elseif ln.kind == "text" then
			if ln.right then
				GameTooltip:AddDoubleLine(ln.text, ln.right, ln.r, ln.g, ln.b, ln.rr, ln.rg, ln.rb)
			else
				GameTooltip:AddLine(ln.text, ln.r, ln.g, ln.b)
			end
		elseif ln.kind == "header" then
			tipLine(ln.segs, ln.right, ln.r, ln.g, ln.b, ln.rr, ln.rg, ln.rb)
		elseif ln.kind == "row" then
			GameTooltip:AddDoubleLine(padTo(fs, ln.name, rowEnd + 8, sp), ln.status,
				ln.r, ln.g, ln.b, ln.rr, ln.rg, ln.rb)
			table.insert(tipRowsPending, { line = GameTooltip:NumLines(), row = ln,
				xIcon = xIcon, xTime = xTime })
		end
	end
end

local function placeTipRows()
	for _, pend in ipairs(tipRowsPending) do
		local lineFs = getglobal("GameTooltipTextLeft" .. pend.line)
		if lineFs then
			local font, size, flags = lineFs:GetFont()
			local ln = pend.row
			if ln.icon then
				local tex = tipIconPiece()
				tex:SetTexture(ln.icon)
				tex:ClearAllPoints()
				tex:SetPoint("LEFT", lineFs, "LEFT", pend.xIcon, 0)
				tex:Show()
			end
			local t = tipTextPiece()
			t:SetFont(font, size, flags)
			t:SetJustifyH("RIGHT")
			t:SetWidth(TIP_TIME_W)
			t:ClearAllPoints()
			t:SetPoint("LEFT", lineFs, "LEFT", pend.xTime, 0)
			t:SetText(ln.time)
			t:Show()
			for k, o in ipairs(ln.others) do
				local x = ln.otherX[k]
				local tex = tipIconPiece()
				tex:SetTexture(o.icon)
				tex:ClearAllPoints()
				tex:SetPoint("LEFT", lineFs, "LEFT", x, 0)
				tex:Show()
				local ot = tipTextPiece()
				ot:SetFont(font, size, flags)
				ot:SetJustifyH("LEFT")
				ot:SetWidth(60)
				ot:ClearAllPoints()
				ot:SetPoint("LEFT", lineFs, "LEFT", x + TIP_ICON + 3, 0)
				ot:SetText(o.time)
				ot:Show()
			end
		end
	end
	tipRowsPending = {}
end


-- Everyone, in the order the button works through them: Greater Blessing groups (classes with
-- overrides first), then overrides. "->" on a header marks the step the button is on, ">" on
-- a row the player the next click is cast on (both as on the button).
local function showTooltip()
	hideTipIcons()
	tipPending = {}
	tipRowsPending = {}
	GameTooltip:SetOwner(button, "ANCHOR_TOPLEFT")
	GameTooltip:SetText("PallyPower Next Blessing")
	for _, line in ipairs(totalsLines(status.totals)) do
		GameTooltip:AddLine(line, 1, 1, 1)
	end

	local sel = status.selected
	if sel then
		local what = "Individual overrides"
		if sel.personal then
			what = "Personal"
		elseif sel.group then
			what = string.format("G. %s - %s", blessingName(sel.group.blessing), className(sel.group.class))
		end
		GameTooltip:AddLine(string.format("Selected (%d/%d): %s", status.selIndex, status.selCount, what), 0.62, 0.72, 0.85)
	end
	if status.leftNext then
		GameTooltip:AddLine((status.shift and "Shift-click: " or "Next click: ") .. status.leftNext.text, OK_R, OK_G, OK_B)
	elseif status.shift then
		GameTooltip:AddLine("Shift-click: nothing to cast here", 0.6, 0.6, 0.6)
	elseif not sel and status.blocked then
		GameTooltip:AddLine(status.blocked, 0.82, 0.55, 0.55, 1)
	end  -- all up: the totals line above says "All applied"
	if status.rightNext then
		GameTooltip:AddLine((status.shift and "Shift-right: " or "Right-click: ") .. status.rightNext.text, RIGHT_R, RIGHT_G, RIGHT_B)
	end

	if AllPallys and AllPallys[me()] and CurrentBuffs and PallyPower_Assignments then
		local groups, overrides = collect(true)
		local curStep = stepKey(status.subject)  -- same page the button shows
		local lines = {}
		table.insert(lines, { kind = "blank" })
		table.insert(lines, { kind = "text", text = " ", right = "Can cast?",
			r = 0.6, g = 0.6, b = 0.6, rr = 0.6, rg = 0.6, rb = 0.6 })
		local firstSection = true
		-- Personal passives first: aura and Righteous Fury
		local plist = personalList()
		if table.getn(plist) > 0 then
			firstSection = false
			local pmark = (curStep == "personal") and STEP_MARK or ""
			table.insert(lines, { kind = "text", text = pmark .. "Personal", r = HEAD_R, g = HEAD_G, b = HEAD_B })
			for _, pp in ipairs(plist) do
				local t
				if not pp.has then
					t = "|cffd08a8amissing|r"
				elseif pp.left then
					t = "|cffd8d8d8" .. PallyPower_FormatTime(pp.left) .. "|r"
				else
					t = "|cffd8d8d8on|r"
				end
				local r, gg, b, sr, sg, sb = lineColors("player", not pp.has, "OK")
				table.insert(lines, { kind = "row", name = "   " .. pp.name, icon = pp.icon, time = t,
					others = {}, status = "OK", r = r, g = gg, b = b, rr = sr, rg = sg, rb = sb })
			end
		end
		for _, group in ipairs(groups) do
			local g, c = group.blessing, group.class
			if table.getn(group.plain) > 0 then
				local left = timeLeft("cast", g .. c)
				local mark = (curStep == c) and STEP_MARK or ""
				if not firstSection then table.insert(lines, { kind = "blank" }) end
				firstSection = false
				local anyHas = false
				for _, m in ipairs(group.plain) do
					if m.stats[g] then anyHas = true end
				end
				local headerLeft = groupLeft(group)
				-- header: [class][blessing] G. Might - Paladin
				table.insert(lines, { kind = "header",
					segs = { mark, { icon = PallyPower_ClassTexture and PallyPower_ClassTexture[c] },
						{ icon = blessingIcon(g) }, " " .. string.format("G. %s - %s", blessingName(g), className(c)) },
					right = timeLabel(headerLeft, anyHas),
					r = HEAD_R, g = HEAD_G, b = HEAD_B, rr = 0.8, rg = 0.8, rb = 0.8 })
				table.sort(group.plain, function(x, y) return x.name < y.name end)
				for _, m in ipairs(group.plain) do
					local st = salvationOnTank(m.unit, g) and "Tank" or unitStatus(m.unit, m.dead, GREATER_RANGE)
					local mleft = memberLeft(left, g, m.name, m.unit)
					local r, gg, b, sr, sg, sb = lineColors(m.unit, memberNeeds(g, m, mleft), st)
					local single = m.stats[g] and normalOnly(m.unit, g)
					local tmark = (m.name == status.markName) and TARGET_MARK or ""
					table.insert(lines, { kind = "row", name = "   " .. tmark .. m.name,
						time = single and SINGLE_TEXT or assignedTimeText(m.unit, m.stats, g, mleft, headerLeft),
						others = otherBlessings(m.unit, m.stats, g), status = st,
						r = r, g = gg, b = b, rr = sr, rg = sg, rb = sb })
				end
			end
		end
		if table.getn(overrides) > 0 then
			if not firstSection then table.insert(lines, { kind = "blank" }) end
			table.insert(lines, { kind = "text",
				text = ((curStep == "ind") and STEP_MARK or "") .. "Individual",
				r = HEAD_R, g = HEAD_G, b = HEAD_B })
			for _, o in ipairs(overrides) do
				local left = overrideLeft(o)
				local mark = (o.name == status.markName) and TARGET_MARK or ""
				local st = salvationOnTank(o.unit, o.blessing) and "Tank" or unitStatus(o.unit, o.dead, BLESSING_RANGE)
				local r, gg, b, sr, sg, sb = lineColors(o.unit, needs(o.stats[o.blessing], left), st)
				table.insert(lines, { kind = "row", name = "   " .. mark .. o.name, icon = blessingIcon(o.blessing),
					time = assignedTimeText(o.unit, o.stats, o.blessing, left),
					others = otherBlessings(o.unit, o.stats, o.blessing), status = st,
					r = r, g = gg, b = b, rr = sr, rg = sg, rb = sb })
			end
		end
		emitTipLines(lines)
	end

	if not hasUnitXP then
		GameTooltip:AddLine("(UnitXP not loaded: range is approximate, no line-of-sight check)", 0.6, 0.6, 0.6, 1)
	end
	GameTooltip:Show()
	placeTipIcons()
	placeTipRows()
end

button:SetScript("OnEnter", function()
	if PPNext_Settings.tooltips ~= false then showTooltip() end
end)
button:SetScript("OnLeave", function()
	if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
	if selectedKey then
		selectedKey = nil  -- back to following the next action
		refreshButton()
	end
end)

-- Mouse wheel: step through the groups (down = further along the order, up = back), wrapping.
-- Starts from whatever the button currently shows.
button:EnableMouseWheel(true)
button:SetScript("OnMouseWheel", function()
	if not (AllPallys and AllPallys[me()] and CurrentBuffs and PallyPower_Assignments) then return end
	local list = steps()
	local n = table.getn(list)
	if n == 0 then return end
	local cur = selectedKey or stepKey(status.subject)
	local idx
	for i, k in ipairs(list) do
		if k == cur then idx = i end
	end
	local delta = (arg1 > 0) and -1 or 1
	if not idx then idx = (delta > 0) and 0 or (n + 1) end
	idx = idx + delta
	if idx < 1 then idx = n elseif idx > n then idx = 1 end
	selectedKey = list[idx]
	refreshButton()
	if GameTooltip:IsOwned(button) then showTooltip() end
end)

-- Timers: status refresh (1/s, also refreshing an open tooltip) and restoring autoSelfCast
-- after a cast.
local nextRefresh = 0
local shiftWasDown = false

-- Clicks work on what the button shows, so it's refreshed right after each click (on the next
-- frame, with the tooltip): the step just cast is skipped by its recent-cast guard and the
-- button moves on, so a quick second click doesn't hit the same step again.
button:SetScript("OnClick", function()
	doNext(arg1)
	nextRefresh = 0
end)
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function()
	local now = GetTime()
	-- Shift changes what a click does (cast anyway / refresh): show it at once, not on the
	-- next tick.
	local shift = IsShiftKeyDown() and true or false
	if shift ~= shiftWasDown then
		shiftWasDown = shift
		nextRefresh = 0
	end
	if now >= nextRefresh and button:IsVisible() then
		nextRefresh = now + 1
		refreshButton()
		if GameTooltip:IsOwned(button) and MouseIsOver(button) then showTooltip() end
	end
	if restoreSelfCastAt and now >= restoreSelfCastAt then
		restoreSelfCastAt = nil
		SetCVar("autoSelfCast", "1")
	end
end)


------------------------------------------------------------------------------
-- Collapsed buff bar: PallyPower's own buttons stay invisible until the mouse is over the
-- "Pally Buffs" title, and fold away again once it leaves the bar. Only this button, its
-- list and the title stay visible.
--
-- PallyPower calls Show()/Hide() on its buttons on every layout update, so they're faded
-- (alpha 0) and made click-through instead of hidden - nothing to fight over. Their mouse
-- wheel is never enabled by PallyPower, so invisible buttons can't catch a scroll either.
------------------------------------------------------------------------------

local COLLAPSE_GRACE = 0.3  -- seconds outside the bar before it folds away
local BAR_PARTS = { "RF", "Aura", "Seal", "ResizeButton" }
for i = 1, 10 do table.insert(BAR_PARTS, "Buff" .. i) end

local barOpen = true      -- PallyPower's buttons currently visible
local leftBarAt = nil

local function collapseOn()
	return PPNext_Settings.collapse ~= false
end

local function setBarOpen(open)
	barOpen = open
	for _, part in ipairs(BAR_PARTS) do
		local f = getglobal("PallyPowerBuffBar" .. part)
		if f then
			f:SetAlpha(open and 1 or 0)
			f:EnableMouse(open)
		end
	end
	-- The bar's own area would otherwise block clicks on the world behind it.
	local bar = getglobal("PallyPowerBuffBar")
	if bar then bar:EnableMouse(open) end
end

local function hookTitle()
	local title = getglobal("PallyPowerBuffBarTitle")
	if not title or title.ppNextHooked then return end
	title.ppNextHooked = true
	local orig = title:GetScript("OnEnter")
	title:SetScript("OnEnter", function()
		if orig then orig() end
		if collapseOn() then
			leftBarAt = nil
			setBarOpen(true)
		end
	end)
end

local barWatcher = CreateFrame("Frame")
barWatcher:SetScript("OnUpdate", function()
	if not collapseOn() or not barOpen then return end
	local bar = getglobal("PallyPowerBuffBar")
	if not bar or not bar:IsVisible() then return end
	local title = getglobal("PallyPowerBuffBarTitle")
	if MouseIsOver(bar) or (title and MouseIsOver(title)) then  -- the title sits outside the bar in the "below" layout
		leftBarAt = nil
	elseif not leftBarAt then
		leftBarAt = GetTime()
	elseif GetTime() - leftBarAt >= COLLAPSE_GRACE then
		leftBarAt = nil
		setBarOpen(false)
	end
end)

------------------------------------------------------------------------------
-- "Below" layout: the "Pally Buffs" title goes under PallyPower's buttons and this button
-- under the title, and the bar is anchored by its bottom-left corner so it grows upwards
-- (opening the collapsed bar, or PallyPower adding class buttons, never moves the title or
-- this button). The bar position is saved in PPNext_Settings.barPos and re-saved after
-- PallyPower drags or rescales the bar (both re-anchor it by its top-left).
------------------------------------------------------------------------------

local function anchorBarBottom(x, y)
	local bar = PallyPowerBuffBar
	bar:ClearAllPoints()
	bar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
	PPNext_Settings.barPos = { x, y }
end

local function saveBarPos()
	local bar = getglobal("PallyPowerBuffBar")
	if not bar or not bar:GetLeft() or not bar:GetBottom() then return end
	anchorBarBottom(bar:GetLeft(), bar:GetBottom())
end

-- Puts the title and this button where the current layout wants them. When switching
-- (switching = true) the bar is moved so the title stays where it was on screen.
local function applyLayout(switching)
	local bar = getglobal("PallyPowerBuffBar")
	local title = getglobal("PallyPowerBuffBarTitle")
	if not bar or not title then return end
	title:ClearAllPoints()
	if PPNext_Settings.below then
		title:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
		if switching and bar:GetTop() then
			anchorBarBottom(bar:GetLeft(), bar:GetTop() - 5)  -- title was 5 below the bar's top
		elseif PPNext_Settings.barPos then
			anchorBarBottom(PPNext_Settings.barPos[1], PPNext_Settings.barPos[2])
		else
			saveBarPos()
		end
	else
		title:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -5)
		if switching and bar:GetBottom() then
			local x, y = bar:GetLeft(), bar:GetBottom() + 5
			bar:ClearAllPoints()
			bar:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
		end
	end
	attachToBuffBar()
end

local function hookBarMoves()
	if PPNext_BarMovesHooked then return end
	PPNext_BarMovesHooked = true
	local origUp = PallyPowerBuffBar_MouseUp
	if origUp then
		PallyPowerBuffBar_MouseUp = function(a1)
			origUp(a1)
			if PPNext_Settings.below then saveBarPos() end
		end
	end
	local origScale = PallyPower_ScaleFrame
	if origScale then
		PallyPower_ScaleFrame = function(scale)
			origScale(scale)
			if PPNext_Settings.below then saveBarPos() end
		end
	end
end

------------------------------------------------------------------------------
-- Out-of-combat opacity for the whole buff bar (PallyPower's buttons, its title, this
-- button and its list): PPNext_Settings.oocAlpha (0.1 - 1, 1 = off, default 0.7). In combat,
-- and while the mouse is over any of it, fully opaque. Checked 10 times a second.
------------------------------------------------------------------------------

local DEFAULT_OOC_ALPHA = 0.7
local function oocAlpha()
	local a = tonumber(PPNext_Settings.oocAlpha) or DEFAULT_OOC_ALPHA
	if a < 0.1 then a = 0.1 end
	if a > 1 then a = 1 end
	return a
end

local opacity = CreateFrame("Frame")
local nextOpacityTick = 0
opacity:SetScript("OnUpdate", function()
	local now = GetTime()
	if now < nextOpacityTick then return end
	nextOpacityTick = now + 0.1
	local bar = getglobal("PallyPowerBuffBar")
	if not bar or not bar:IsVisible() then return end
	local a = oocAlpha()
	if a < 1 then
		local title = getglobal("PallyPowerBuffBarTitle")
		if UnitAffectingCombat("player") or MouseIsOver(bar) or MouseIsOver(button)
			or (title and MouseIsOver(title)) or (list:IsVisible() and MouseIsOver(list)) then
			a = 1
		end
	end
	if math.abs(bar:GetAlpha() - a) > 0.001 then bar:SetAlpha(a) end
end)

local function updateVisibility()
	local _, cls = UnitClass("player")
	if cls == "PALADIN" and not PPNext_Settings.hidden then
		button:Show()
	else
		button:Hide()
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function()
	if event == "PLAYER_LOGIN" then
		hookTitle()
		hookBarMoves()
		if collapseOn() then setBarOpen(false) end
		updateVisibility()
		-- Below layout is on by default. First time (never set): switch to it the way the
		-- setting does, so the title stays where it is on screen.
		if PPNext_Settings.below == nil then
			PPNext_Settings.below = true
			applyLayout(true)
		end
	end
	-- Also after loading screens, in case the saved frame layout put the bar back.
	applyLayout()
end)

------------------------------------------------------------------------------
-- Settings: shared by the options section and the slash command
------------------------------------------------------------------------------

local function say(text) DEFAULT_CHAT_FRAME:AddMessage("PallyPower Next: " .. text) end

local setters = {
	shown = function(on)
		PPNext_Settings.hidden = (not on) or nil
		updateVisibility()
	end,
	collapse = function(on)
		PPNext_Settings.collapse = on and true or false
		setBarOpen(not on)
	end,
	below = function(on)
		if (PPNext_Settings.below and true or false) == (on and true or false) then return end
		PPNext_Settings.below = on and true or false  -- false is kept: nil means "default (on)"
		applyLayout(true)
	end,
	list = function(on)
		PPNext_Settings.list = on and true or false
		refreshList()
	end,
	tooltips = function(on)
		PPNext_Settings.tooltips = on and true or false
		if not on and GameTooltip:IsOwned(button) then GameTooltip:Hide() end
	end,
	others = function(on)
		PPNext_Settings.others = on and true or false
		if GameTooltip:IsOwned(button) then showTooltip() end
	end,
}

local getters = {
	shown    = function() return not PPNext_Settings.hidden end,
	collapse = function() return collapseOn() end,
	below    = function() return PPNext_Settings.below and true or false end,
	list     = function() return PPNext_Settings.list ~= false end,
	tooltips = function() return PPNext_Settings.tooltips ~= false end,
	others   = function() return PPNext_Settings.others == true end,
}

local function setOpacity(a)
	a = math.floor(a * 20 + 0.5) / 20  -- 5% steps
	if a < 0.1 then a = 0.1 end
	if a > 1 then a = 1 end
	PPNext_Settings.oocAlpha = a
end


------------------------------------------------------------------------------
-- "PallyPower Next" section at the bottom of PallyPower's options window
-- (PallyPower_OptionsFrame, the one with Global Transparency). Same layout as
-- PallyPower's own rows: label on the left at x 7, control on the right at x -5, 25 px apart.
------------------------------------------------------------------------------

local panelRows = {}
local opacitySlider

-- Explainers on the settings controls: shown after a short delay, and only while tooltips are
-- on (the same setting as the button's tooltip).
local SETTING_TIP_DELAY = 0.5
local settingTipFor, settingTipAt
local settingTipTimer = CreateFrame("Frame")
settingTipTimer:Hide()
settingTipTimer:SetScript("OnUpdate", function()
	if not settingTipFor then this:Hide() return end
	if GetTime() < settingTipAt then return end
	local f = settingTipFor
	settingTipFor = nil
	this:Hide()
	if not MouseIsOver(f) then return end
	GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
	GameTooltip:SetText(f.tipTitle, 1, 1, 1)
	for _, line in ipairs(f.tipLines) do
		GameTooltip:AddLine(line, 0.85, 0.85, 0.85, 1)
	end
	GameTooltip:Show()
end)

local function settingTip(f, title, lines)
	f.tipTitle, f.tipLines = title, lines
	f:SetScript("OnEnter", function()
		if PPNext_Settings.tooltips == false then return end
		settingTipFor, settingTipAt = this, GetTime() + SETTING_TIP_DELAY
		settingTipTimer:Show()
	end)
	f:SetScript("OnLeave", function()
		settingTipFor = nil
		if GameTooltip:IsOwned(this) then GameTooltip:Hide() end
	end)
end

local function refreshPanel()
	for _, row in ipairs(panelRows) do
		row.check:SetChecked(getters[row.key]())
	end
	if opacitySlider then
		opacitySlider.updating = true
		opacitySlider:SetValue(oocAlpha())
		opacitySlider.updating = nil
		getglobal(opacitySlider:GetName() .. "Text"):SetText(math.floor(oocAlpha() * 100 + 0.5) .. "%")
	end
end

local function buildPanel()
	local opts = getglobal("PallyPower_OptionsFrame")
	if not opts or opts.ppNextSection then return end
	opts.ppNextSection = true

	local ROW = 25
	local y = -opts:GetHeight() - 5   -- first free row under PallyPower's last one

	local header = opts:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	header:SetPoint("TOPLEFT", opts, "TOPLEFT", 7, y)
	header:SetText("PallyPower Next")
	y = y - 20

	local function label(text, yy)
		local fs = opts:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		fs:SetPoint("TOPLEFT", opts, "TOPLEFT", 7, yy)
		fs:SetWidth(300)
		fs:SetHeight(16)
		fs:SetJustifyH("LEFT")
		fs:SetText(text)
	end

	local rows = {
		{ "shown",    "Show the Next Blessing button",
			{ "Shows the button that casts your next blessing on PallyPower's buff bar.",
			  "Chat: /ppnext show | hide" } },
		{ "collapse", "Collapse: show buttons on title mouseover",
			{ "PallyPower's own buttons stay hidden until you hover the \"Pally Buffs\" title,",
			  "and fold away 0.3 s after the mouse leaves the bar. On by default.",
			  "Chat: /ppnext collapse" } },
		{ "below",    "Button below the title, bar grows upwards",
			{ "Puts this button under the title and makes the bar grow upwards, so opening it",
			  "never moves the title or the button. On by default.",
			  "Chat: /ppnext below" } },
		{ "list",     "Target list in the button",
			{ "Lists who the next click is about inside the button: time left, and whether a",
			  "cast would reach them (OK, OOR, LOS, Dead, Not Here, Tank).",
			  "Chat: /ppnext list" } },
		{ "tooltips", "Tooltips (button and settings)",
			{ "The button's tooltip (everyone, in the order the button works through them)",
			  "and these explainers.",
			  "Chat: /ppnext tooltips" } },
		{ "others",   "Other blessing types in the tooltip",
			{ "Also lists each player's other blessing types in the button's tooltip, e.g.",
			  "Kings and Wisdom when you give them Might, with time left (known only with",
			  "ClassicAPI). Your own blessing type is always shown, whoever cast it. Off by default.",
			  "Chat: /ppnext others" } },
	}
	for i, r in ipairs(rows) do
		local key = r[1]
		label(r[2], y)
		local check = CreateFrame("CheckButton", "PPNextOption" .. i, opts, "OptionsCheckButtonTemplate")
		check:SetWidth(20)
		check:SetHeight(20)
		check:SetPoint("TOPRIGHT", opts, "TOPRIGHT", -5, y + 2)
		check:SetScript("OnClick", function()
			setters[key](this:GetChecked() and true or false)
		end)
		settingTip(check, r[2], r[3])
		table.insert(panelRows, { key = key, check = check })
		y = y - ROW
	end

	y = y - 10  -- room for the slider's value text above it
	label("Out-of-combat opacity", y)
	opacitySlider = CreateFrame("Slider", "PPNextOpacitySlider", opts, "OptionsSliderTemplate")
	opacitySlider:SetWidth(220)
	opacitySlider:SetHeight(16)
	opacitySlider:SetPoint("TOPRIGHT", opts, "TOPRIGHT", -5, y)
	opacitySlider:SetMinMaxValues(0.1, 1)
	opacitySlider:SetValueStep(0.05)
	getglobal("PPNextOpacitySliderLow"):SetText("10%")
	getglobal("PPNextOpacitySliderHigh"):SetText("100%")
	opacitySlider:SetScript("OnValueChanged", function()
		if this.updating then return end
		setOpacity(this:GetValue())
		getglobal(this:GetName() .. "Text"):SetText(math.floor(oocAlpha() * 100 + 0.5) .. "%")
	end)
	settingTip(opacitySlider, "Out-of-combat opacity", {
		"Fades the whole buff bar out of combat. Fully visible in combat and while the",
		"mouse is over it. 100% = off, 70% by default.",
		"Chat: /ppnext opacity 10-100" })
	y = y - ROW - 5

	-- where else these settings live
	local note = opts:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", opts, "TOPLEFT", 7, y)
	note:SetWidth(386)
	note:SetJustifyH("LEFT")
	note:SetTextColor(0.6, 0.6, 0.6)
	note:SetText("Also as chat commands: type /ppnext for the list (/ppnext options opens this window).")
	y = y - 18

	opts:SetHeight(-y + 5)

	-- PallyPower's OnShow isn't a script we can extend safely in 1.12 (no HookScript), so
	-- refresh the controls on show through a small child frame.
	local watcher = CreateFrame("Frame", nil, opts)
	watcher:SetScript("OnShow", refreshPanel)
	watcher:Show()
	refreshPanel()
end

buildPanel()


-- Slash command: shortcuts for the same settings.
SLASH_PPNEXT1 = "/ppnext"
SlashCmdList["PPNEXT"] = function(msg)
	msg = string.lower(msg or "")
	local function toggle(key, onText, offText)
		local on = not getters[key]()
		setters[key](on)
		say(on and onText or offText)
	end
	if msg == "show" then
		setters.shown(true)
	elseif msg == "hide" then
		setters.shown(false)
	elseif msg == "tooltips" then
		toggle("tooltips", "tooltips on", "tooltips off")
	elseif msg == "list" then
		toggle("list", "target list on", "target list off")
	elseif msg == "others" then
		toggle("others", "other blessing types in the tooltip on", "other blessing types in the tooltip off")
	elseif msg == "collapse" then
		toggle("collapse", "collapsed buff bar on", "collapsed buff bar off")
	elseif msg == "below" then
		toggle("below", "button below the title, bar grows upwards", "button on top of the bar")
	elseif string.find(msg, "^opacity") then
		local _, _, pct = string.find(msg, "^opacity%s*(%d+)")
		pct = tonumber(pct)
		if pct and pct >= 10 and pct <= 100 then
			setOpacity(pct / 100)
			say("out-of-combat opacity " .. math.floor(oocAlpha() * 100 + 0.5) .. "%")
		else
			say("/ppnext opacity 10-100 (now " .. math.floor(oocAlpha() * 100 + 0.5) .. "%)")
		end
	elseif msg == "auras" then
		-- What ClassicAPI reports for your target's buffs (or yours, with no target).
		local u = UnitExists("target") and "target" or "player"
		if not hasAuraAPI then
			say("ClassicAPI (C_UnitAuras) isn't loaded: time left comes from PallyPower Next's own timers.")
		else
			say("buffs on " .. (UnitName(u) or u) .. ":")
			for i = 1, 32 do
				local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, u, i, "HELPFUL")
				if not ok or type(a) ~= "table" then break end
				local e = tonumber(a.expirationTime)
				local left = (e and e > GetTime()) and PallyPower_FormatTime(e - GetTime()) or "no time"
				local b = blessingOfIcon(a.icon)
				DEFAULT_CHAT_FRAME:AddMessage("   " .. tostring(a.name) .. ": " .. left
					.. (b and (" (" .. blessingName(b) .. ")") or ""), 0.8, 0.8, 0.8)
			end
		end
	elseif msg == "options" or msg == "config" then
		if PallyPower_Options then PallyPower_Options() end
	else
		setters.shown(not getters.shown())
		DEFAULT_CHAT_FRAME:AddMessage(GREY .. "/ppnext [show | hide | options | tooltips | others | list | collapse | below | opacity 10-100 | auras]|r")
		DEFAULT_CHAT_FRAME:AddMessage(GREY .. "All of these are also in PallyPower's options window (PallyPower Next section).|r")
		for _, line in ipairs(HELP) do
			DEFAULT_CHAT_FRAME:AddMessage(GREY .. line .. "|r")
		end
	end
	refreshPanel()
end
