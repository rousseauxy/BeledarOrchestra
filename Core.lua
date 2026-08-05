local ADDON_NAME, ns = ...

-- Saved variables (initialized in ADDON_LOADED)
BeledarOrchestraDB = BeledarOrchestraDB or {}

-- Constants
ns.PREFIX = "BeledarOrch"
ns.TARGET_NPC_ID = 255888
ns.UPDATE_INTERVAL = 0.2
ns.MAX_MEASURES = 25
ns.RAID_SLOTS = 40
ns.ZONE_ID = 2215

ns.VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "Unknown"
ns.ADDON_NAME = ADDON_NAME

-- Shared state
ns.state = {
    currentMeasure = nil,
    status = "YELLOW",
    mismatchText = "No measure selected",
    lastUpdate = 0,
    activePlayers = {},
    lastPingTime = 0,
    performedEmotes = {},
    danceMoving = {},
    danceComplete = {},
    measureLocked = false,
    measureStarted = false,
    countdownEndTime = nil,
    countdownDuration = 10,
    lastCompletedMeasure = nil,
}

-- Shared UI table
ns.ui = {}

-- Main event frame
ns.frame = CreateFrame("Frame")

-- Utility functions
function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff99ccffBeledar Orchestra:|r " .. tostring(msg))
end

function ns.GetNpcID(unit)
    local id = UnitCreatureID(unit)
    if id then return tonumber(id) end
    return nil
end

function ns.IsTargetNpc(unit)
    return ns.GetNpcID(unit) == ns.TARGET_NPC_ID
end

function ns.IsLeaderOrAssist()
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

function ns.GetAuraData(unit, spellId, filter)
    if not unit or not spellId then return nil end
    filter = filter or "HELPFUL"
    for i = 1, 255 do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
        if not aura then break end

        local auraSpellId = aura.spellId
        if auraSpellId then
            -- Use HasAnySecretValues if available (WoW 11.0.5+) to avoid crashes when 
            -- comparing "secret number values" (private auras) to a regular number.
            local isSecret = HasAnySecretValues and HasAnySecretValues(auraSpellId)
            if not isSecret then
                -- Still use pcall for absolute safety against comparison errors 
                -- in all client versions.
                local success, match = pcall(function() return auraSpellId == spellId end)
                if success and match then
                    return aura
                end
            end
        end
    end
    return nil
end

function ns.HasAura(unit, spellId)
    return ns.GetAuraData(unit, spellId) ~= nil
end

function ns.MakeMovable(f)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
end

-- Every frame CreateBackdropFrame has produced, so a skin change can repaint
-- them. Bounded: this addon creates two.
local backdropFrames = {}

-- Paints one frame in the current look.
--
-- ns.euiSkin is set only when EllesmereUI is installed, its skinning module is
-- on, and the user has not disabled third-party skinning for this addon. When
-- it is absent -- which is the common case -- the original tooltip backdrop is
-- used unchanged.
function ns.ApplyBackdrop(f)
    local S = ns.euiSkin
    if not S then
        f:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
        f:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
        return
    end

    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    local r, g, b, a = S.GetPanelColor()
    -- These float over the world, so stay readable even when the user's panel
    -- fill is semi-transparent.
    f:SetBackdropColor(r, g, b, math.max(a or 1, 0.92))
    local ar, ag, ab = S.GetAccentColor()
    f:SetBackdropBorderColor(ar * 0.55, ag * 0.55, ab * 0.55, 1)
end

function ns.RefreshSkin()
    for i = 1, #backdropFrames do
        ns.ApplyBackdrop(backdropFrames[i])
    end

    -- The player panel's header strip is coloured by hand, so it does not
    -- follow the backdrop automatically.
    local S = ns.euiSkin
    if S and ns.ui.playerHeaderBg then
        local ar, ag, ab = S.GetAccentColor()
        ns.ui.playerHeaderBg:SetColorTexture(ar * 0.30, ag * 0.30, ab * 0.30, 0.9)
        if ns.ui.playerHeaderLine then
            ns.ui.playerHeaderLine:SetColorTexture(ar * 0.65, ag * 0.65, ab * 0.65, 1)
        end
    end
end

function ns.CreateBackdropFrame(name, parent, width, height)
    local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
    f:SetSize(width, height)
    backdropFrames[#backdropFrames + 1] = f
    ns.ApplyBackdrop(f)
    return f
end

function ns.GetSpellNameSafe(spellId)
    if C_Spell and C_Spell.GetSpellName then
        local n = C_Spell.GetSpellName(spellId)
        if n then return n end
    end
    return tostring(spellId)
end

function ns.GetSpellTextureSafe(spellId)
    if C_Spell and C_Spell.GetSpellTexture then
        local t = C_Spell.GetSpellTexture(spellId)
        if t then return t end
    end
    return 134400
end
