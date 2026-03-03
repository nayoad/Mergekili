local _, BCDM = ...

local hooked = {}
local isEnabled = false
local eventFrame

local COOLDOWN_STYLE = {
    showSwipe = true,
    showEdge = false,
    showBling = true,
    reverse = false,
    swipeRGBA = { 0, 0, 0, 0.8 },
    swipeTexture = "Interface\\Buttons\\WHITE8X8",
}

local VIEWERS = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
}

local function ApplyCooldownStyle(cd)
    if not cd then return end

    local style = COOLDOWN_STYLE
    cd:SetDrawSwipe(style.showSwipe)
    cd:SetDrawEdge(style.showEdge)
    cd:SetDrawBling(style.showBling)
    cd:SetReverse(style.reverse)

    local color = style.swipeRGBA
    if color then
        cd:SetSwipeColor(color[1], color[2], color[3], color[4])
    end

    if cd.SetSwipeTexture and style.swipeTexture then
        cd:SetSwipeTexture(style.swipeTexture)
    end
end

local function GetSpellID(frame)
    local info = frame and frame.cooldownInfo
    return info and (info.overrideSpellID or info.spellID)
end

local function ClearCooldown(cd)
    if cd and cd.Clear then
        cd:Clear()
    end
end

local function TryApplyChargeCooldown(cd, spellID)
    if not (C_Spell and C_Spell.GetSpellCharges) then return false end

    local chargeInfo = C_Spell.GetSpellCharges(spellID)
    if not chargeInfo then return false end

    if type(chargeInfo) ~= "table" and cd.SetCooldownFromDurationObject then
        local success = pcall(function()
            cd:SetCooldownFromDurationObject(chargeInfo, false)
        end)
        if success then
            return true
        end
    end

    if type(chargeInfo) == "table" then
        local chargeStart = chargeInfo.cooldownStartTime or chargeInfo.chargeStartTime or chargeInfo.chargeStart
        local chargeDuration = chargeInfo.cooldownDuration or chargeInfo.chargeDuration

        if chargeStart and chargeDuration then
            cd:SetCooldown(chargeStart, chargeDuration)
        else
            ClearCooldown(cd)
        end

        return true
    end

    return false
end

local function SetCooldownForSpell(cd, spellID)
    if not cd or not spellID or spellID == 0 then
        ClearCooldown(cd)
        return
    end

    if TryApplyChargeCooldown(cd, spellID) then
        return
    end

    if cd.SetCooldownFromDurationObject and C_Spell and C_Spell.GetSpellCooldownDuration then
        local durationObj = C_Spell.GetSpellCooldownDuration(spellID)
        if durationObj then
            cd:SetCooldownFromDurationObject(durationObj, false)
            return
        end
    end

    if C_Spell and C_Spell.GetSpellCooldown then
        local success = pcall(function()
            local info = C_Spell.GetSpellCooldown(spellID)
            if info and info.startTime and info.duration then
                cd:SetCooldown(info.startTime, info.duration)
            end
        end)
        if success then
            return
        end
    end

    ClearCooldown(cd)
end

local function UpdateCooldownFrame(cd)
    if not isEnabled then return end
    if cd.BCDMBypassHook then return end

    local parent = cd.BCDMParentFrame
    if not parent or not parent.cooldownInfo then return end

    local spellID = GetSpellID(parent)
    if not spellID then return end

    cd.BCDMBypassHook = true
    SetCooldownForSpell(cd, spellID)
    ApplyCooldownStyle(cd)
    cd.BCDMBypassHook = false
end

local function HookCooldownFrame(cd, parent)
    if not cd or hooked[cd] then return end
    if not parent or not parent.cooldownInfo then return end

    hooked[cd] = true
    cd.BCDMParentFrame = parent
    cd.BCDMBypassHook = false

    hooksecurefunc(cd, "SetCooldown", UpdateCooldownFrame)

    if cd.SetCooldownFromDurationObject then
        hooksecurefunc(cd, "SetCooldownFromDurationObject", UpdateCooldownFrame)
    end
end

local function ScanCooldownFrames()
    for _, viewerName in ipairs(VIEWERS) do
        local viewer = _G[viewerName]
        if viewer then
            for _, child in ipairs({ viewer:GetChildren() }) do
                if child and child.Cooldown and child.cooldownInfo then
                    HookCooldownFrame(child.Cooldown, child)
                end
            end
        end
    end
end

local function EnsureEventFrame()
    if eventFrame then return end
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, _, addon)
        if addon == "Blizzard_CooldownViewer" then
            C_Timer.After(0.5, ScanCooldownFrames)
        end
    end)
end

function BCDM:EnableAuraOverlayRemoval()
    isEnabled = true
    ScanCooldownFrames()
    EnsureEventFrame()
    eventFrame:UnregisterAllEvents()
    eventFrame:RegisterEvent("ADDON_LOADED")
end

function BCDM:DisableAuraOverlayRemoval()
    isEnabled = false

    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
end

function BCDM:RefreshAuraOverlayRemoval()
    if not BCDM.db or not BCDM.db.profile or not BCDM.db.profile.CooldownManager then
        return
    end

    local general = BCDM.db.profile.CooldownManager.General
    if general and general.DisableAuraOverlay then
        BCDM:EnableAuraOverlayRemoval()
    else
        BCDM:DisableAuraOverlayRemoval()
    end
end
