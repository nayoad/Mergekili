-- SpellStateAPI.lua
-- Provides a stable, event-driven SpellState API for addon-to-addon communication.
-- Designed for WoW 12.0.x (Midnight) where direct C_Spell cooldown queries may be
-- inconsistent for SimC-based rotation engines.

local _, BCDM = ...

-- ---------------------------------------------------------------------------
-- Internal spell-state cache
-- ---------------------------------------------------------------------------
local spellStateCache = {}
local gcdState = { startTime = 0, duration = 0, isEnabled = true, modRate = 1 }
local GCD_SPELL_ID = 61304
local addonRestricted = false

-- ---------------------------------------------------------------------------
-- 12.0.0 Secret Values & Restriction helpers
-- ---------------------------------------------------------------------------
local function IsSpellCooldownSecret(spellID)
    if C_Secrets and C_Secrets.ShouldSpellCooldownBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldSpellCooldownBeSecret, spellID)
        if ok then return secret end
    end
    return false
end

local function AreCooldownsSecret()
    if C_Secrets and C_Secrets.ShouldCooldownsBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldCooldownsBeSecret)
        if ok then return secret end
    end
    return false
end

local function IsValueSecret(value)
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, value)
        if ok then return secret end
    end
    return false
end

local function UpdateRestrictionState()
    if C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive then
        local ok, active = pcall(C_RestrictedActions.IsAddOnRestrictionActive)
        if ok then
            addonRestricted = active
            return
        end
    end
    addonRestricted = false
end

-- ---------------------------------------------------------------------------
-- Helpers: safely call the underlying Blizzard APIs
-- ---------------------------------------------------------------------------
local function SafeGetSpellCooldown(spellID)
    if addonRestricted or AreCooldownsSecret() or IsSpellCooldownSecret(spellID) then
        return 0, 0, true, 1
    end
    local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
    if ok and info then
        return info.startTime or 0, info.duration or 0, info.isEnabled, info.modRate or 1
    end
    return 0, 0, true, 1
end

local function SafeGetSpellCharges(spellID)
    if addonRestricted or AreCooldownsSecret() then
        return nil
    end
    local ok, info = pcall(C_Spell.GetSpellCharges, spellID)
    if ok and info then
        return info.currentCharges, info.maxCharges, info.cooldownStartTime, info.cooldownDuration, info.chargeModRate
    end
    return nil
end

local function SafeGetSpellLossOfControlCooldown(spellID)
    local ok, info = pcall(C_Spell.GetSpellLossOfControlCooldown, spellID)
    if ok and info then
        return info.startTime or 0, info.duration or 0
    end
    return 0, 0
end

local function SafeIsSpellUsable(spellID)
    if addonRestricted then
        return false, false
    end
    local ok, usable, noMana = pcall(C_Spell.IsSpellUsable, spellID)
    if ok then
        return usable, noMana
    end
    return false, false
end

local function SafeGetSpellBaseCooldown(spellID)
    if C_Spell.GetSpellCooldownDuration then
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
-- Cache maintenance
-- ---------------------------------------------------------------------------
local function GetOrCreateEntry(spellID)
    if not spellStateCache[spellID] then
        spellStateCache[spellID] = {
            startTime  = 0,
            duration   = 0,
            isEnabled  = true,
            modRate    = 1,
            lastUpdate = 0,
        }
    end
    return spellStateCache[spellID]
end

local CACHE_STALE_THRESHOLD = 0.05  -- 50 ms

local function RefreshCooldownEntry(spellID)
    local entry = GetOrCreateEntry(spellID)
    local now = GetTime()

    if (now - entry.lastUpdate) < CACHE_STALE_THRESHOLD then
        return entry
    end

    local start, dur, enabled, modRate = SafeGetSpellCooldown(spellID)
    entry.startTime  = start   or 0
    entry.duration   = dur     or 0
    entry.isEnabled  = enabled
    entry.modRate    = modRate  or 1
    entry.lastUpdate = now
    return entry
end

local function RefreshGCD()
    local start, dur, enabled, modRate = SafeGetSpellCooldown(GCD_SPELL_ID)
    gcdState.startTime = start   or 0
    gcdState.duration  = dur     or 0
    gcdState.isEnabled = enabled
    gcdState.modRate   = modRate or 1
end

-- ---------------------------------------------------------------------------
-- Event frame: keep cache fresh on relevant game events
-- ---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame", "BCDMSpellStateEventFrame")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        UpdateRestrictionState()
        -- Invalidate all cached entries when restriction state changes
        for _, entry in pairs(spellStateCache) do
            entry.lastUpdate = 0
        end
        return
    end

    RefreshGCD()

    if event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" then
        -- Invalidate all cached entries so the next query re-fetches from the API
        for _, entry in pairs(spellStateCache) do
            entry.lastUpdate = 0
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateRestrictionState()
    end
end)

-- ---------------------------------------------------------------------------
-- Public API  (exposed via the global BCDMG table)
-- ---------------------------------------------------------------------------

--- Returns unpacked cooldown info for a spell.
-- @param spellID number
-- @return startTime, duration, isEnabled, modRate
function BCDMG:GetSpellCooldown(spellID)
    if not spellID then return 0, 0, true, 1 end
    local entry = RefreshCooldownEntry(spellID)
    return entry.startTime, entry.duration, entry.isEnabled, entry.modRate
end

--- Returns unpacked charge info for a spell.
-- @param spellID number
-- @return currentCharges, maxCharges, cooldownStartTime, cooldownDuration, chargeModRate  (or nil)
function BCDMG:GetSpellCharges(spellID)
    if not spellID then return nil end
    return SafeGetSpellCharges(spellID)
end

--- Returns loss-of-control cooldown for a spell.
-- @param spellID number
-- @return startTime, duration
function BCDMG:GetSpellLossOfControlCooldown(spellID)
    if not spellID then return 0, 0 end
    return SafeGetSpellLossOfControlCooldown(spellID)
end

--- Returns whether a spell is currently usable.
-- @param spellID number
-- @return usable, noMana
function BCDMG:IsSpellUsable(spellID)
    if not spellID then return false, false end
    return SafeIsSpellUsable(spellID)
end

--- Returns GCD start / duration.
-- @return startTime, duration, isEnabled, modRate
function BCDMG:GetGCDInfo()
    RefreshGCD()
    return gcdState.startTime, gcdState.duration, gcdState.isEnabled, gcdState.modRate
end

--- Returns base cooldown, gcd category and internal cooldown for a spell.
-- @param spellID number
-- @return cooldown, gcd, icd
function BCDMG:GetSpellBaseCooldown(spellID)
    if not spellID then return 0, 0, 0 end
    return SafeGetSpellBaseCooldown(spellID)
end

--- Invalidate/clear the cache for a single spell (or all spells when nil).
-- @param spellID number|nil
function BCDMG:InvalidateSpellState(spellID)
    if spellID then
        if spellStateCache[spellID] then
            spellStateCache[spellID].lastUpdate = 0
        end
    else
        for _, entry in pairs(spellStateCache) do
            entry.lastUpdate = 0
        end
    end
end

--- Check whether the SpellState API is available. Other addons can call this
--- to verify that BCDM provides the extended state layer.
-- @return boolean
function BCDMG:IsSpellStateAPIAvailable()
    return true
end

--- Check whether addon restrictions are currently active (12.0.0+).
-- @return boolean
function BCDMG:IsAddonRestricted()
    return addonRestricted
end

--- Check whether a specific spell's cooldown is hidden by the Secret Values system.
-- @param spellID number
-- @return boolean
function BCDMG:IsSpellCooldownSecret(spellID)
    return IsSpellCooldownSecret(spellID)
end

--- Check whether cooldowns in general are hidden by the Secret Values system.
-- @return boolean
function BCDMG:AreCooldownsSecret()
    return AreCooldownsSecret()
end

--- Returns action bar cooldown info via the new C_ActionBar API (12.0.0+).
-- @param slot number  action bar slot
-- @return startTime, duration, isEnabled, modRate
function BCDMG:GetActionCooldown(slot)
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
function BCDMG:GetActionCharges(slot)
    if C_ActionBar and C_ActionBar.GetActionCharges then
        local ok, info = pcall(C_ActionBar.GetActionCharges, slot)
        if ok and info then
            return info.currentCharges, info.maxCharges, info.cooldownStartTime, info.cooldownDuration, info.chargeModRate
        end
    end
    return nil
end
