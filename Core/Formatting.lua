-- Catch template-provided text as well as explicitly styled IRS FontStrings.
-- Only registered addon roots are visited; Blizzard's UI is never traversed.
local IRS = IRS
local roots = {}
local controlFonts = {}

function IRS:GetControlFont(scope)
    scope = scope == "mini" and "mini" or "main"
    if not controlFonts[scope] then
        local font = CreateFont("IncomeRecordsSystem" .. scope .. "ControlFont")
        font:SetTextColor(0.88, 0.84, 0.75)
        IRS:RegisterFontString(scope, scope == "mini" and "body" or "label", font, STANDARD_TEXT_FONT, "")
        controlFonts[scope] = font
    end
    return controlFonts[scope]
end

local function CoverText(object, scope, style)
    if not object or not object.SetFont then return end
    if IRS._registeredFontObjects and IRS._registeredFontObjects[object] then return end
    local _, size = object:GetFont()
    if size == 1 then return end -- hidden compatibility text
    IRS:RegisterFontString(scope, style, object, STANDARD_TEXT_FONT, "")
end

local function CoverFrame(frame, scope)
    if frame.IsForbidden and frame:IsForbidden() then return end
    local kind = frame:GetObjectType()
    if kind == "EditBox" then
        CoverText(frame, scope, "body")
        frame:SetHeight(math.max(frame:GetHeight(), IRS:GetFontSize(scope, "body") + 12))
    end
    local buttonText = frame.GetFontString and frame:GetFontString()
    if buttonText and frame.SetNormalFontObject then
        -- Private FontObjects keep template hover/disabled states from restoring
        -- Blizzard's font. They never modify the shared GameFont objects.
        local font = IRS:GetControlFont(scope)
        frame:SetNormalFontObject(font)
        frame:SetHighlightFontObject(font)
        frame:SetDisabledFontObject(font)
        CoverText(buttonText, scope, scope == "mini" and "body" or "label")
        buttonText:SetWordWrap(false)
        frame:SetWidth(math.max(frame:GetWidth(), buttonText:GetUnboundedStringWidth() + 24))
        frame:SetHeight(math.max(frame:GetHeight(), buttonText:GetStringHeight() + 12))
    end
    for _, region in ipairs({frame:GetRegions()}) do
        if region:IsObjectType("FontString") then
            CoverText(region, scope, "body")
        end
    end
    for _, child in ipairs({frame:GetChildren()}) do CoverFrame(child, scope) end
end

function IRS:RegisterFormattingRoot(frame, scope)
    if not frame or roots[frame] then return end
    roots[frame] = scope == "mini" and "mini" or "main"
    frame:HookScript("OnShow", function(self) CoverFrame(self, roots[self]) end)
end

function IRS:RefreshFormattingCoverage()
    for frame, scope in pairs(roots) do CoverFrame(frame, scope) end
    if IRS.tooltip and IRS.tooltip:IsShown() then
        IRS:FormatTooltip(IRS.tooltip, IRS.tooltip._irsFontScope)
    end
end

-- All IRS hover information uses a private tooltip, including its line fonts.
-- Scope-specific objects are reapplied before measurement on each population.
IRS.tooltip = CreateFrame("GameTooltip", "IncomeRecordsSystemTooltip", UIParent, "GameTooltipTemplate")
function IRS:FormatTooltip(tooltip, scope)
    tooltip._irsFontScope = scope or "main"
    local path = IRS:GetFontFace()
    local name = tooltip:GetName()
    if not name then return end
    for i = 1, tooltip:NumLines() do
        for _, side in ipairs({"Left", "Right"}) do
            local line = _G[name .. "Text" .. side .. i]
            if line then
                line:SetFont(path, IRS:GetFontSize(scope or "main", i == 1 and "body" or "helper"), "")
            end
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    IRS:ApplySavedFontSizes()
    if IRS.RefreshUI then
        hooksecurefunc(IRS, "RefreshUI", function() IRS:RefreshFormattingCoverage() end)
    end
end)
