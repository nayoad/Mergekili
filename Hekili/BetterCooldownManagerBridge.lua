-- BetterCooldownManagerBridge.lua
-- Bridge layer that routes ALL of Hekili's C_Spell queries through
-- BetterCooldownManager's SpellState API when available, and wraps every
-- fallback Blizzard call in pcall so that blocked / restricted APIs in
-- Midnight 12.x never crash the addon.
--
-- Loaded early in the Hekili TOC so that every other file can reference
-- ns.BCDM_* helpers instead of calling C_Spell.* directly.

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
    -- Check restriction / secret state in fallback path
    if C_Secrets and C_Secrets.ShouldSpellCooldownBeSecret then
        local sok, secret = pcall(C_Secrets.ShouldSpellCooldownBeSecret, spellID)
        if sok and secret then return 0, 0, true, 1 end
    end
    local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
    if ok and info then
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
    -- Check restriction / secret state in fallback path
    if C_Secrets and C_Secrets.ShouldCooldownsBeSecret then
        local sok, secret = pcall(C_Secrets.ShouldCooldownsBeSecret)
        if sok and secret then return nil end
    end
    local ok, info = pcall(C_Spell.GetSpellCharges, spellID)
    if ok and info then
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
    local ok, info = pcall(C_Spell.GetSpellLossOfControlCooldown, spellID)
    if ok and info then
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
    local ok, usable, noMana = pcall(C_Spell.IsSpellUsable, spellID)
    if ok then return usable, noMana end
    return false, false
end

-- ---------------------------------------------------------------------------
-- GetSpellBaseCooldown  →  cooldown, gcd, icd
-- ---------------------------------------------------------------------------
ns.BCDM_GetSpellBaseCooldown = function(spellID)
    if IsBCDMAvailable() then
        return BCDMG:GetSpellBaseCooldown(spellID)
    end
    if C_Spell and C_Spell.GetSpellCooldownDuration then
        local ok, duration = pcall(C_Spell.GetSpellCooldownDuration, spellID)
        if ok and duration then return duration, 0, 0 end
    end
    if GetSpellBaseCooldown then
        local ok, cd, gcd, icd = pcall(GetSpellBaseCooldown, spellID)
        if ok then return cd, gcd, icd end
    end
    return 0, 0, 0
end

-- ---------------------------------------------------------------------------
-- GetSpellCooldownRaw  →  returns the raw cooldown info table (for callers
-- that access fields like .startTime / .duration directly on the table)
-- ---------------------------------------------------------------------------
ns.BCDM_GetSpellCooldownRaw = function(spellID)
    if IsBCDMAvailable() then
        local rawInfo = {}
        local ok, result = pcall(C_Spell.GetSpellCooldown, spellID)
        if ok and result then rawInfo = result end
        local startTime, duration, isEnabled, modRate = BCDMG:GetSpellCooldown(spellID)
        rawInfo.startTime = startTime
        rawInfo.duration  = duration
        rawInfo.isEnabled = isEnabled
        rawInfo.modRate   = modRate
        return rawInfo
    end
    -- Check restriction / secret state in fallback path
    if C_Secrets and C_Secrets.ShouldSpellCooldownBeSecret then
        local sok, secret = pcall(C_Secrets.ShouldSpellCooldownBeSecret, spellID)
        if sok and secret then
            return { startTime = 0, duration = 0, isEnabled = true, modRate = 1 }
        end
    end
    local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
    if ok then return info end
    return { startTime = 0, duration = 0, isEnabled = true, modRate = 1 }
end

-- ---------------------------------------------------------------------------
-- GetSpellInfo  →  spellInfo table  (name, iconID, castTime, etc.)
-- ---------------------------------------------------------------------------
ns.BCDM_GetSpellInfo = function(spellID)
    if not spellID then return nil end
    local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
    if ok then return info end
    return nil
end

-- ---------------------------------------------------------------------------
-- GetSpellName  →  string
-- ---------------------------------------------------------------------------
ns.BCDM_GetSpellName = function(spellID)
    if not spellID then return nil end
    local ok, name = pcall(C_Spell.GetSpellName, spellID)
    if ok then return name end
    return nil
end

-- ---------------------------------------------------------------------------
-- GetSpellTexture  →  texture path / ID
-- ---------------------------------------------------------------------------
ns.BCDM_GetSpellTexture = function(spellID)
    if not spellID then return nil end
    local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
    if ok then return tex end
    return nil
end

-- ---------------------------------------------------------------------------
-- GetSpellDescription  →  string
-- ---------------------------------------------------------------------------
ns.BCDM_GetSpellDescription = function(spellID)
    if not spellID then return nil end
    local ok, desc = pcall(C_Spell.GetSpellDescription, spellID)
    if ok then return desc end
    return nil
end

-- ---------------------------------------------------------------------------
-- GetSpellLink  →  hyperlink string
-- ---------------------------------------------------------------------------
ns.BCDM_GetSpellLink = function(spellID)
    if not spellID then return nil end
    local ok, link = pcall(C_Spell.GetSpellLink, spellID)
    if ok then return link end
    return nil
end

-- ---------------------------------------------------------------------------
-- GetSpellSubtext  →  string (e.g. rank)
-- ---------------------------------------------------------------------------
ns.BCDM_GetSpellSubtext = function(spellID)
    if not spellID then return nil end
    local ok, sub = pcall(C_Spell.GetSpellSubtext, spellID)
    if ok then return sub end
    return nil
end

-- ---------------------------------------------------------------------------
-- GetSpellCastCount  →  number
-- ---------------------------------------------------------------------------
ns.BCDM_GetSpellCastCount = function(spellID)
    if not spellID then return 0 end
    local ok, count = pcall(C_Spell.GetSpellCastCount, spellID)
    if ok then return count end
    return 0
end

-- ---------------------------------------------------------------------------
-- GetSpellPowerCost  →  table of cost entries
-- ---------------------------------------------------------------------------
ns.BCDM_GetSpellPowerCost = function(spellID)
    if not spellID then return nil end
    local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
    if ok then return costs end
    return nil
end

-- ---------------------------------------------------------------------------
-- IsCurrentSpell  →  boolean
-- ---------------------------------------------------------------------------
ns.BCDM_IsCurrentSpell = function(spellID)
    if not spellID then return false end
    local ok, val = pcall(C_Spell.IsCurrentSpell, spellID)
    if ok then return val end
    return false
end

-- ---------------------------------------------------------------------------
-- IsSpellInRange  →  boolean
-- ---------------------------------------------------------------------------
ns.BCDM_IsSpellInRange = function(spellID, unit)
    if not spellID then return nil end
    local ok, val = pcall(C_Spell.IsSpellInRange, spellID, unit)
    if ok then return val end
    return nil
end

-- ---------------------------------------------------------------------------
-- SpellHasRange  →  boolean
-- ---------------------------------------------------------------------------
ns.BCDM_SpellHasRange = function(spellID)
    if not spellID then return false end
    local ok, val = pcall(C_Spell.SpellHasRange, spellID)
    if ok then return val end
    return false
end

-- ---------------------------------------------------------------------------
-- IsSpellDataCached  →  boolean
-- ---------------------------------------------------------------------------
ns.BCDM_IsSpellDataCached = function(spellID)
    if not spellID then return false end
    local ok, val = pcall(C_Spell.IsSpellDataCached, spellID)
    if ok then return val end
    return false
end

-- ---------------------------------------------------------------------------
-- RequestLoadSpellData  →  void
-- ---------------------------------------------------------------------------
ns.BCDM_RequestLoadSpellData = function(spellID)
    if not spellID then return end
    pcall(C_Spell.RequestLoadSpellData, spellID)
end

-- ---------------------------------------------------------------------------
-- IsSpellPassive  →  boolean
-- ---------------------------------------------------------------------------
ns.BCDM_IsSpellPassive = function(spellID)
    if not spellID then return false end
    local ok, val = pcall(C_Spell.IsSpellPassive, spellID)
    if ok then return val end
    return false
end

-- ---------------------------------------------------------------------------
-- IsSpellHarmful  →  boolean
-- ---------------------------------------------------------------------------
ns.BCDM_IsSpellHarmful = function(spellID)
    if not spellID then return false end
    local ok, val = pcall(C_Spell.IsSpellHarmful, spellID)
    if ok then return val end
    return false
end

-- ---------------------------------------------------------------------------
-- IsSpellHelpful  →  boolean
-- ---------------------------------------------------------------------------
ns.BCDM_IsSpellHelpful = function(spellID)
    if not spellID then return false end
    local ok, val = pcall(C_Spell.IsSpellHelpful, spellID)
    if ok then return val end
    return false
end

-- ---------------------------------------------------------------------------
-- IsPressHoldReleaseSpell  →  boolean
-- ---------------------------------------------------------------------------
ns.BCDM_IsPressHoldReleaseSpell = function(spellID)
    if not spellID then return false end
    local ok, val = pcall(C_Spell.IsPressHoldReleaseSpell, spellID)
    if ok then return val end
    return false
end

-- ---------------------------------------------------------------------------
-- 12.0.0  Addon Restriction & Secret Values helpers
-- ---------------------------------------------------------------------------

--- Check whether addon restrictions are currently active.
-- @return boolean
ns.BCDM_IsAddonRestricted = function()
    if IsBCDMAvailable() then
        return BCDMG:IsAddonRestricted()
    end
    if C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive then
        local ok, active = pcall(C_RestrictedActions.IsAddOnRestrictionActive)
        if ok then return active end
    end
    return false
end

--- Check whether a spell cooldown is hidden by the Secret Values system.
-- @param spellID number
-- @return boolean
ns.BCDM_IsSpellCooldownSecret = function(spellID)
    if IsBCDMAvailable() then
        return BCDMG:IsSpellCooldownSecret(spellID)
    end
    if C_Secrets and C_Secrets.ShouldSpellCooldownBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldSpellCooldownBeSecret, spellID)
        if ok then return secret end
    end
    return false
end

--- Check whether cooldowns in general are hidden by the Secret Values system.
-- @return boolean
ns.BCDM_AreCooldownsSecret = function()
    if IsBCDMAvailable() then
        return BCDMG:AreCooldownsSecret()
    end
    if C_Secrets and C_Secrets.ShouldCooldownsBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldCooldownsBeSecret)
        if ok then return secret end
    end
    return false
end

--- Returns action bar cooldown info via the new C_ActionBar API (12.0.0+).
-- @param slot number  action bar slot
-- @return startTime, duration, isEnabled, modRate
ns.BCDM_GetActionCooldown = function(slot)
    if IsBCDMAvailable() then
        return BCDMG:GetActionCooldown(slot)
    end
    if C_ActionBar and C_ActionBar.GetActionCooldown then
        local ok, info = pcall(C_ActionBar.GetActionCooldown, slot)
        if ok and info then
            return info.startTime or 0, info.duration or 0, info.isEnabled, info.modRate or 1
        end
    end
    return 0, 0, true, 1
end

--- Returns action bar charge info via the new C_ActionBar API (12.0.0+).
-- @param slot number  action bar slot
-- @return currentCharges, maxCharges, cooldownStartTime, cooldownDuration, chargeModRate
ns.BCDM_GetActionCharges = function(slot)
    if IsBCDMAvailable() then
        return BCDMG:GetActionCharges(slot)
    end
    if C_ActionBar and C_ActionBar.GetActionCharges then
        local ok, info = pcall(C_ActionBar.GetActionCharges, slot)
        if ok and info then
            return info.currentCharges, info.maxCharges, info.cooldownStartTime, info.cooldownDuration, info.chargeModRate
        end
    end
    return nil
end
