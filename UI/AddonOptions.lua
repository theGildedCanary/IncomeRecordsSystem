local IRS = IRS

local panel = CreateFrame("Frame")
IRS:RegisterFormattingRoot(panel, "main")
panel.name = "IRS  Income Records System"

-- Title Display
local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
IRS:RegisterFontString("main", "page", title, STANDARD_TEXT_FONT, "")
title:SetPoint("TOPLEFT", 24, -24)
title:SetText("IRS – Income Records System")

-- Version Display
local version = C_AddOns.GetAddOnMetadata(
    "IncomeRecordsSystem",
    "Version"
) or "Unknown"

local versionText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
IRS:RegisterFontString("main", "helper", versionText, STANDARD_TEXT_FONT, "")
versionText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
IRS:SetLayoutColor(versionText, "SetTextColor", 0.65, 0.65, 0.65)
versionText:SetText("Version: " .. version)

-- Description Display
local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
IRS:RegisterFontString("main", "body", description, STANDARD_TEXT_FONT, "")
description:SetPoint("TOPLEFT", versionText, "BOTTOMLEFT", 0, -8)
description:SetWidth(620)
description:SetJustifyH("LEFT")
description:SetWordWrap(true)
description:SetText(
    "Track account-wide gold, Savings Projects, Reserve Funds, reports, WoW Token prices, and other IRS tools."
)

-- Open Dashboard Button
local openButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
IRS:StyleButtonFeedback(openButton)
openButton:SetSize(220, 32)
openButton:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -20)
openButton:SetText("Open IRS Dashboard")

openButton:SetScript("OnClick", function()
    if SettingsPanel and SettingsPanel:IsShown() then
        HideUIPanel(SettingsPanel)
    end
    
    IRS:ShowUI("dashboard")
end)

-- Contributor credits share their content with the dashboard page.
local contributorsHeading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
IRS:RegisterFontString("main", "section", contributorsHeading, STANDARD_TEXT_FONT, "")
contributorsHeading:SetPoint("TOPLEFT", openButton, "BOTTOMLEFT", 0, -28)
contributorsHeading:SetPoint("RIGHT", panel, "RIGHT", -24, 0)
contributorsHeading:SetJustifyH("LEFT")
contributorsHeading:SetWordWrap(true)
contributorsHeading:SetText("Thank you to our Contributors")

local contributorsThanks = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
IRS:RegisterFontString("main", "body", contributorsThanks, STANDARD_TEXT_FONT, "")
contributorsThanks:SetPoint("TOPLEFT", contributorsHeading, "BOTTOMLEFT", 0, -12)
contributorsThanks:SetPoint("RIGHT", panel, "RIGHT", -24, 0)
contributorsThanks:SetJustifyH("LEFT")
contributorsThanks:SetWordWrap(true)
contributorsThanks:SetSpacing(2)
contributorsThanks:SetText(IRS.contributorThanks)

local contributorNames = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
IRS:RegisterFontString("main", "body", contributorNames, STANDARD_TEXT_FONT, "")
contributorNames:SetPoint("TOPLEFT", contributorsThanks, "BOTTOMLEFT", 0, -16)
contributorNames:SetPoint("RIGHT", panel, "RIGHT", -24, 0)
contributorNames:SetJustifyH("LEFT")
contributorNames:SetWordWrap(true)
contributorNames:SetSpacing(8)
contributorNames:SetText(table.concat(IRS.contributors, "\n"))

-- category registration
local category = Settings.RegisterCanvasLayoutCategory(
    panel,
    panel.name
)

Settings.RegisterAddOnCategory(category)
