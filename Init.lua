local _, ns = ...

local frame = ns.frame
local state = ns.state
local ui = ns.ui
local PREFIX = ns.PREFIX
local Print = ns.Print

local function IsInCorrectZone()
    return C_Map.GetBestMapForUnit("player") == ns.ZONE_ID
end

-- Slash commands
SLASH_BELEDARORCHESTRA1 = "/conductor"
SlashCmdList.BELEDARORCHESTRA = function(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd and cmd:lower() or ""

    if cmd == "" then
        if ui.main:IsShown() then
            ui.main:Hide()
            state.leaderUIOpen = false
        else
            ui.main:Show()
            state.leaderUIOpen = true
        end
        return
    elseif cmd == "show" then
        ui.main:Show()
        state.leaderUIOpen = true
        return
    elseif cmd == "hide" then
        ui.main:Hide()
        state.leaderUIOpen = false
        return
    elseif cmd == "player" then
        if ui.playerFrame:IsShown() then
            state.playerUIClosed = true
            ui.playerFrame:Hide()
        else
            state.playerUIClosed = nil
            ui.playerFrame:Show()
        end
        return
    elseif cmd == "playershow" then
        state.playerUIClosed = nil
        ui.playerFrame:Show()
        return
    elseif cmd == "playerhide" then
        state.playerUIClosed = true
        ui.playerFrame:Hide()
        return
    elseif cmd == "measure" then
        local n = tonumber(rest)
        if not n then
            Print("Usage: /conductor measure <1-25>")
            return
        end
        ns.SetMeasure(n)
        ns.UpdatePlayerPanel()
        ns.ValidateTarget()
        return
    elseif cmd == "reset" then
        ns.SetMeasure(nil)
        ns.UpdatePlayerPanel()
        ns.ValidateTarget()
        return
    elseif cmd == "debug" then
        local observed, anyAura = ns.BuildObservedCounts()
        if not anyAura then
            Print("No helpful auras on target")
            return
        end
        for spellId, count in pairs(observed) do
            Print(ns.GetSpellNameSafe(spellId) .. " x" .. tostring(count) .. " (" .. tostring(spellId) .. ")")
        end
        return
    elseif cmd == "slot" then
        local slot = ns.GetRaidSlotForPlayer()
        Print("Computed slot: " .. tostring(slot or "nil"))
        return
    end

    Print("Commands: /conductor, /conductor show, /conductor hide, /conductor player, /conductor playershow, /conductor playerhide, /conductor measure <1-25>, /conductor reset, /conductor debug, /conductor slot")
end

-- Event handler
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
        if IsInCorrectZone() then
            if ui.main and state.leaderUIOpen then ui.main:Show() end
            if ui.playerFrame and ns.IsTargetNpc("target") then ui.playerFrame:Show() end
        else
            if ui.main then ui.main:Hide() end
            if ui.playerFrame then ui.playerFrame:Hide() end
        end
        return
    end

    if event == "ADDON_LOADED" then
        local loadedName = ...
        if loadedName ~= ns.ADDON_NAME then return end

        BeledarOrchestraDB.Overrides = BeledarOrchestraDB.Overrides or {}
        BeledarOrchestraDB.SavedSets = BeledarOrchestraDB.SavedSets or {}
        state.lastCompletedMeasure = BeledarOrchestraDB.LastCompletedMeasure

        -- Migration from flat SavedSets to measure-based SavedSets
        local needsMigration = false
        for k, v in pairs(BeledarOrchestraDB.SavedSets) do
            if type(k) == "string" and type(v) == "table" then
                for mk in pairs(v) do
                    if type(mk) == "number" then
                        needsMigration = true
                        break
                    end
                end
            end
            if needsMigration then break end
        end

        if needsMigration then
            local newSets = {}
            for name, set in pairs(BeledarOrchestraDB.SavedSets) do
                if type(name) == "string" and type(set) == "table" then
                    for m, slots in pairs(set) do
                        if type(m) == "number" then
                            newSets[m] = newSets[m] or {}
                            newSets[m][name] = slots
                        end
                    end
                end
            end
            BeledarOrchestraDB.SavedSets = newSets
            Print("Migrated assignment sets to measure-based format.")
        end

        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        ns.CreateLeaderUI()
        ns.CreatePlayerUI()
        ns.SetMeasure(nil, true)
        ns.UpdatePlayerPanel()
        ns.SetStatus("YELLOW", "No measure selected", {})

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, _, sender = ...
        if prefix ~= PREFIX then return end
        ns.HandleAddonMessage(message, sender)

    elseif InCombatLockdown() then
        return

    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_TARGET_CHANGED" then
        if event == "PLAYER_TARGET_CHANGED" and IsInCorrectZone() and ns.IsLeaderOrAssist() and ns.IsTargetNpc("target") then
            if ui.main and not ui.main:IsShown() then
                ui.main:Show()
                state.leaderUIOpen = true
            end
        end
        ns.UpdatePlayerPanel()
        ns.ValidateTarget()
        if event == "GROUP_ROSTER_UPDATE" and ns.ShowMode and state.currentViewMode then
            ns.ShowMode(state.currentViewMode)
        end

    elseif event == "UNIT_AURA" then
        -- Filtered to "target" at registration, so no unit check is needed here.
        ns.ValidateTarget()

    elseif event == "PLAYER_STARTED_MOVING" then
        local slot = ns.GetRaidSlotForPlayer()
        local measure = state.currentMeasure
        if slot and measure and state.measureLocked then
            local token = ns.GetMeasureEmote(measure, slot)
            if token == "DANCE" and not state.danceMoving[slot] then
                state.danceMoving[slot] = true
                if IsInGroup() then
                    local channel = IsInRaid() and "RAID" or "PARTY"
                    C_ChatInfo.SendAddonMessage(PREFIX, string.format("DANCE_MOVING:%d:%d", measure, slot), channel)
                end
                ns.UpdatePlayerPanel()
            end
        end

    elseif event == "PLAYER_STOPPED_MOVING" then
        local slot = ns.GetRaidSlotForPlayer()
        local measure = state.currentMeasure
        if slot and measure and state.measureLocked then
            local token = ns.GetMeasureEmote(measure, slot)
            if token == "DANCE" and state.danceMoving[slot] and not state.danceComplete[slot] then
                state.danceComplete[slot] = true
                if IsInGroup() then
                    local channel = IsInRaid() and "RAID" or "PARTY"
                    C_ChatInfo.SendAddonMessage(PREFIX, string.format("DANCE_STOPPED:%d:%d", measure, slot), channel)
                end
                frame:UnregisterEvent("PLAYER_STARTED_MOVING")
                frame:UnregisterEvent("PLAYER_STOPPED_MOVING")
                ns.UpdatePlayerPanel()
            end
        end
    end
end)

-- OnUpdate timer
frame:SetScript("OnUpdate", function(_, elapsed)
    if InCombatLockdown() then return end
    if not IsInCorrectZone() then return end

    -- Countdown tick: always check even if no UI is visible, so measureStarted
    -- is set promptly when the countdown expires (player may not be targeting NPC)
    if state.countdownEndTime and not state.measureStarted then
        local remaining = state.countdownEndTime - GetTime()
        if remaining <= 0 then
            state.measureStarted = true
            state.countdownEndTime = nil
            ns.UpdatePlayerPanel()
            ns.UpdateAssignmentGrid()
        end
    end

    if not ((ui.main and ui.main:IsShown()) or (ui.playerFrame and ui.playerFrame:IsShown())) then
        return
    end

    state.lastUpdate = state.lastUpdate + elapsed
    if state.lastUpdate >= ns.UPDATE_INTERVAL then
        state.lastUpdate = 0
        if ui.playerFrame and ui.playerFrame:IsShown() then
            ns.UpdatePlayerPanel()
        end
        if ui.main and ui.main:IsShown() then
            ns.ValidateTarget()
        end
    end
end)

-- Register events
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
-- Registered as a unit event: the emote stacks this addon reads live on the
-- Divine Flame, i.e. the "target" unit. RegisterUnitEvent filters in C before
-- dispatch, where plain RegisterEvent delivered every aura application,
-- refresh, stack change and expiry on every party, raid, boss and nameplate
-- unit -- thousands of dispatches per encounter in a 20-man raid, all of them
-- discarded by the unit check in the handler.
frame:RegisterUnitEvent("UNIT_AURA", "target")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("ZONE_CHANGED")
frame:RegisterEvent("ZONE_CHANGED_INDOORS")
