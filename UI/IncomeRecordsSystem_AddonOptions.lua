local IRS = IRS

local panel = CreateFrame("Frame")
panel.name = "IRS  Income Records System"

-- Title Display
local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 24, -24)
title:SetText("IRS – Income Records System")

-- Version Display
local version = C_AddOns.GetAddOnMetadata(
    "IncomeRecordsSystem",
    "Version"
) or "Unknown"

local versionText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
versionText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
versionText:SetTextColor(0.65, 0.65, 0.65)
versionText:SetText("Version: " .. version)

-- Description Display
local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
description:SetPoint("TOPLEFT", versionText, "BOTTOMLEFT", 0, -8)
description:SetWidth(620)
description:SetJustifyH("LEFT")
description:SetWordWrap(true)
description:SetText(
    "Track account-wide gold, Savings Projects, Reserve Funds, reports, WoW Token prices, and other IRS tools."
)

-- Open Dashboard Button
local openButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
openButton:SetSize(220, 32)
openButton:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -20)
openButton:SetText("Open IRS Dashboard")

openButton:SetScript("OnClick", function()
    if SettingsPanel and SettingsPanel:IsShown() then
        HideUIPanel(SettingsPanel)
    end
    
    IRS:ShowUI("dashboard")
end)

-- category registration
local category = Settings.RegisterCanvasLayoutCategory(
    panel,
    panel.name
)

Settings.RegisterAddOnCategory(category)