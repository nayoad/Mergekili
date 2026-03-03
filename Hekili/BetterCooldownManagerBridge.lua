-- BetterCooldownManagerBridge.lua
-- Bridge layer that routes Hekili's cooldown / charge / GCD queries through
-- BetterCooldownManager's SpellState API when available, falling back to
-- direct Blizzard C_Spell calls otherwise.
--
-- Loaded early in the Hekili TOC so that every other file can reference
-- ns.BCDM_* helpers.

local addon, ns = ...

-- ---------------------------------------------------------------------------
-- Detect whether BCDMG SpellState API is present
-- ---------------------------------------------------------------------------
local function IsBCDMAvailable()
    return type(BCDMG) == "table"
        and type(BCDMG.IsSpellStateAPIAvailable) == "function"
        and BCDMG:IsSpellStateAPIAvailable()
end

-- ---------------------------------------------------------------------------
-- GetSpellCooldown  →  startTime, duration, isEnabled, modRate
-- ---------------------------------------------------------------------------
ns.BCDM_GetSpellCooldown = function(spellID)
    if IsBCDMAvailable() then
        return BCDMG:GetSpellCooldown(spellID)
    end
    local info = C_Spell.GetSpellCooldown(spellID)
    if info then
        return info.startTime, info.duration, info.isEnabled, info.modRate
    end
    return 0, 0, true, 1
end

-- ---------------------------------------------------------------------------
-- GetSpellCharges  →  currentCharges, maxCharges, startTime, duration, modRate
-- ---------------------------------------------------------------------------
ns.BCDM_GetSpellCharges = function(spellID)
    if IsBCDMAvailable() then
        return BCDMG:GetSpellCharges(spellID)
    end
    local info = C_Spell.GetSpellCharges(spellID)
    if info then
        return info.currentCharges, info.maxCharges, info.cooldownStartTime, info.cooldownDuration, info.chargeModRate
    end
end

-- ---------------------------------------------------------------------------
-- GetSpellLossOfControlCooldown  →  startTime, duration
-- ---------------------------------------------------------------------------
ns.BCDM_GetSpellLossOfControlCooldown = function(spellID)
    if IsBCDMAvailable() then
        return BCDMG:GetSpellLossOfControlCooldown(spellID)
    end
    local info = C_Spell.GetSpellLossOfControlCooldown(spellID)
    if info then
        return info.startTime, info.duration
    end
    return 0, 0
end

-- ---------------------------------------------------------------------------
-- IsSpellUsable  →  usable, noMana
-- ---------------------------------------------------------------------------
ns.BCDM_IsSpellUsable = function(spellID)
    if IsBCDMAvailable() then
        return BCDMG:IsSpellUsable(spellID)
    end
    return C_Spell.IsSpellUsable(spellID)
end

-- ---------------------------------------------------------------------------
-- GetSpellBaseCooldown  →  cooldown, gcd, icd
-- ---------------------------------------------------------------------------
ns.BCDM_GetSpellBaseCooldown = function(spellID)
    if IsBCDMAvailable() then
        return BCDMG:GetSpellBaseCooldown(spellID)
    end
    return GetSpellBaseCooldown(spellID)
end

-- ---------------------------------------------------------------------------
-- GetSpellCooldownRaw  →  returns the raw cooldown info table (for callers
-- that access fields like .startTime / .duration directly on the table)
-- ---------------------------------------------------------------------------
ns.BCDM_GetSpellCooldownRaw = function(spellID)
    if IsBCDMAvailable() then
        -- Start with the raw API table to preserve any extra fields (e.g. activeCategory)
        local rawInfo = C_Spell.GetSpellCooldown(spellID) or {}
        local startTime, duration, isEnabled, modRate = BCDMG:GetSpellCooldown(spellID)
        rawInfo.startTime = startTime
        rawInfo.duration  = duration
        rawInfo.isEnabled = isEnabled
        rawInfo.modRate   = modRate
        return rawInfo
    end
    return C_Spell.GetSpellCooldown(spellID)
end
