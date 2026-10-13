-- Account-wide appearance for IRS-owned regions. Keep original colors so
-- switching back restores the default exactly, including hover/selected states.
local IRS = IRS
IRS.LAYOUT_STYLE_OPTIONS = {
    { key = "default", label = "IRS Default" },
    { key = "elvui", label = "ElvUI Inspired" },
}

local function ColorKey(r, g, b)
    return string.format("%.3f/%.3f/%.3f", r, g, b)
end

local replacements = {}
local function Map(r, g, b, nr, ng, nb)
    replacements[ColorKey(r, g, b)] = {nr, ng, nb}
end
-- Panel fills, borders, selected rows, and dividers used by IRS modules.
Map(0.165, 0.125, 0.085, 0.025, 0.030, 0.035)
Map(0.190, 0.145, 0.098, 0.035, 0.040, 0.045)
Map(0.225, 0.170, 0.112, 0.055, 0.060, 0.065)
Map(0.105, 0.086, 0.064, 0.025, 0.030, 0.035)
Map(0.115, 0.094, 0.069, 0.035, 0.040, 0.045)
Map(0.25, 0.19, 0.12, 0.09, 0.10, 0.11)
Map(0.285, 0.215, 0.135, 0.10, 0.11, 0.12)
Map(0.32, 0.24, 0.145, 0.12, 0.13, 0.14)
Map(0.52, 0.39, 0.22, 0.10, 0.11, 0.12)
Map(0.36, 0.28, 0.18, 0.14, 0.15, 0.16)
Map(0.46, 0.36, 0.22, 0.14, 0.15, 0.16)
Map(0.15, 0.115, 0.070, 0.08, 0.09, 0.10)
Map(0.18, 0.13, 0.05, 0.08, 0.09, 0.10)
Map(0.21, 0.16, 0.10, 0.06, 0.07, 0.08)
Map(0.27, 0.23, 0.17, 0.16, 0.17, 0.18)
Map(0.88, 0.84, 0.75, 0.90, 0.90, 0.90)
Map(0.68, 0.62, 0.51, 0.65, 0.67, 0.69)

local regions = setmetatable({}, {__mode = "k"})

function IRS:GetLayoutStyle()
    local key = self.db and self.db.settings and self.db.settings.layoutStyle
    return key == "elvui" and "elvui" or "default"
end

function IRS:GetLayoutStyleLabel()
    local selected = self:GetLayoutStyle()
    for _, option in ipairs(self.LAYOUT_STYLE_OPTIONS) do
        if option.key == selected then return option.label end
    end
end

local function Apply(region, method, color)
    local replacement = IRS:GetLayoutStyle() == "elvui"
        and replacements[ColorKey(color[1], color[2], color[3])]
    local alpha = color[4]
    if replacement then
        -- Layered panels remain readable while letting the world show through.
        if method == "SetBackdropColor" and alpha > 0.80 then alpha = 0.72 end
        region[method](region, replacement[1], replacement[2], replacement[3], alpha)
    else
        region[method](region, unpack(color))
    end
end

function IRS:SetLayoutColor(region, method, r, g, b, a)
    local color = {r, g, b, a or 1}
    if replacements[ColorKey(r, g, b)] then
        regions[region] = regions[region] or {}
        regions[region][method] = color
    elseif regions[region] then
        -- A reused row may change from a themed color to an alert color.
        regions[region][method] = nil
    end
    Apply(region, method, color)
end

function IRS:ApplySavedLayoutStyle()
    for region, methods in pairs(regions) do
        for method, color in pairs(methods) do Apply(region, method, color) end
    end
end

function IRS:SetLayoutStyle(key)
    if key ~= "default" and key ~= "elvui" then return end
    self:EnsureDB()
    self.db.settings.layoutStyle = key
    self:ApplySavedLayoutStyle()
    if self.RefreshSettingsPage then self:RefreshSettingsPage() end
end
