local _, ns = ...

-- =============================================================
-- Optional EllesmereUI integration.
--
-- EllesmereUI 8.6+ exposes a public skinning API: RegisterSkin hands us a
-- facade whose getters report the user's live panel colour, accent colour and
-- font, and OnLooksChanged fires when they change them.
--
-- Registering costs nothing when EllesmereUI is absent -- the whole block is
-- skipped -- and nothing when its skinning module is off or the user has
-- disabled third-party skinning for this addon, because the callback then
-- simply never runs. So ns.euiSkin arriving is the only reliable signal that
-- this addon may paint itself in EUI's style; until then ApplyBackdrop uses the
-- original tooltip look unchanged.
--
-- Only the two backdrop frames and the player panel's header strip are
-- affected. No layout, no fonts, no behaviour.
-- =============================================================

if not (EllesmereUI and EllesmereUI.RegisterSkin) then return end

EllesmereUI.RegisterSkin("BeledarOrchestra", function(S)
    ns.euiSkin = S
    ns.RefreshSkin()

    -- Repaint when the user changes accent or theme, so the addon tracks their
    -- settings instead of freezing whatever was current at login.
    if S.OnLooksChanged then
        S.OnLooksChanged(function()
            ns.RefreshSkin()
        end)
    end
end)
