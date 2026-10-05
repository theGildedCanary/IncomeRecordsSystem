--[[
IRS — Main Page Scrolling
Adds outer scrolling to main tabs while leaving nested scrollable widgets independent.
]]

local IRS = IRS
local pageFrames = IRS.pageFrames or {}

IRS.pageScrollFrames = IRS.pageScrollFrames or {}

local PAGE_ORDER = {
    "dashboard",
    "projects",
    "reserves",
    "tools",
    "characters",
    "reports",
    "settings",
    "help",
}

local function CapitalizeKey(key)
    return (tostring(key or ""):gsub("^%l", string.upper))
end

local function GetScrollBar(scroll)
    if scroll.ScrollBar then return scroll.ScrollBar end
    if scroll.GetName then
        local name = scroll:GetName()
        if name then return _G[name .. "ScrollBar"] end
    end
    return nil
end

local function IsVisibleObject(object)
    if not object then return false end
    if object.IsShown and not object:IsShown() then return false end
    return true
end

-- Measures the lowest visible descendant relative to the page top.
--
-- We intentionally do NOT recurse into nested ScrollFrames. Character lists,
-- report histories, the project daily table, and Settings project lists already
-- own their internal scrolling and should count only as one bounded widget here.
local function MeasureFrameExtent(frame, pageTop, deepest)
    if not frame or not pageTop then return deepest end

    if frame.GetRegions then
        for _, region in ipairs({frame:GetRegions()}) do
            if IsVisibleObject(region) and region.GetBottom then
                local bottom = region:GetBottom()
                if bottom then
                    deepest = math.max(deepest, pageTop - bottom)
                end
            end
        end
    end

    if frame.GetChildren then
        for _, child in ipairs({frame:GetChildren()}) do
            if IsVisibleObject(child) then
                if child.GetBottom then
                    local bottom = child:GetBottom()
                    if bottom then
                        deepest = math.max(deepest, pageTop - bottom)
                    end
                end

                local objectType = child.GetObjectType and child:GetObjectType()
                if objectType ~= "ScrollFrame" then
                    deepest = MeasureFrameExtent(child, pageTop, deepest)
                end
            end
        end
    end

    return deepest
end

local function PositionScrollBarOutsideContent(scroll)
    local bar = GetScrollBar(scroll)
    if not bar then return end

    -- The main content frame ends 16px before the IRS window edge. Put the
    -- scrollbar in that spare gutter so it doesn't cover Account Overview or
    -- other right-aligned content.
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 2, -16)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 2, 16)
end

local function BuildPageScroll(key, page)
    if not page or IRS.pageScrollFrames[key] then return end

    local viewport = page:GetParent()
    if not viewport then return end

    local name = "IncomeRecordsSystem" .. CapitalizeKey(key) .. "PageScroll"
    local scroll = CreateFrame("ScrollFrame", name, viewport, "UIPanelScrollFrameTemplate")
    scroll:SetAllPoints(viewport)
    scroll:EnableMouseWheel(true)

    page:ClearAllPoints()
    page:SetParent(scroll)
    page:SetSize(
        math.max(1, viewport:GetWidth() or 1),
        math.max(1, viewport:GetHeight() or 1)
    )
    scroll:SetScrollChild(page)

    scroll._irsPage = page
    scroll._irsKey = key
    scroll._irsHasOverflow = false

    scroll:SetScript("OnMouseWheel", function(self, delta)
        if not self._irsHasOverflow then return end

        local child = self._irsPage
        local viewportHeight = self:GetHeight() or 0
        local childHeight = child and child:GetHeight() or viewportHeight
        local maxScroll = math.max(0, childHeight - viewportHeight)
        local current = self:GetVerticalScroll() or 0
        local step = IsShiftKeyDown and IsShiftKeyDown() and 120 or 48

        self:SetVerticalScroll(
            math.max(0, math.min(maxScroll, current - (delta * step)))
        )
    end)

    PositionScrollBarOutsideContent(scroll)
    IRS.pageScrollFrames[key] = scroll
end

for _, key in ipairs(PAGE_ORDER) do
    BuildPageScroll(key, pageFrames[key])
end

-- Show only the active tab's viewport. UI.lua still owns the child page's
-- visibility, while this function owns the new outer ScrollFrame.
function IRS:UpdatePageScrollVisibility(activeKey)
    activeKey = activeKey or IRS.activeTab or "dashboard"

    for key, scroll in pairs(IRS.pageScrollFrames) do
        scroll:SetShown(key == activeKey)
    end
end

-- Restores page children to viewport height before a fresh responsive-layout
-- pass. This prevents a previously-expanded page from influencing bottom
-- anchors during the next font/layout recalculation.
function IRS:PreparePageScroll(key)
    for pageKey, scroll in pairs(IRS.pageScrollFrames) do
        if not key or key == pageKey then
            local page = scroll._irsPage
            local width = math.max(1, scroll:GetWidth() or 1)
            local height = math.max(1, scroll:GetHeight() or 1)

            if page then
                page:SetWidth(width)
                page:SetHeight(height)
            end

            local current = scroll:GetVerticalScroll() or 0
            if current > 0 then
                scroll:SetVerticalScroll(0)
            end
        end
    end
end

-- Measures one tab after all of its adaptive layout work has completed. The
-- child grows only when something actually extends below the visible viewport.
function IRS:RefreshPageScroll(key)
    key = key or IRS.activeTab or "dashboard"

    local scroll = IRS.pageScrollFrames[key]
    if not scroll then return end

    local page = scroll._irsPage
    if not page then return end

    local viewportHeight = math.max(1, scroll:GetHeight() or 1)
    local viewportWidth = math.max(1, scroll:GetWidth() or 1)

    page:SetWidth(viewportWidth)

    local pageTop = page:GetTop()
    if not pageTop then
        -- Geometry can be unresolved for one frame while the parent window is
        -- first appearing. The OnShow retry below will measure again.
        return
    end

    local extent = MeasureFrameExtent(page, pageTop, 0)
    local neededHeight = math.max(viewportHeight, math.ceil(extent + 12))
    local overflow = neededHeight > (viewportHeight + 1)

    page:SetHeight(neededHeight)
    scroll._irsHasOverflow = overflow

    if scroll.UpdateScrollChildRect then
        scroll:UpdateScrollChildRect()
    end

    local bar = GetScrollBar(scroll)
    if bar then
        bar:SetShown(overflow)
        PositionScrollBarOutsideContent(scroll)
    end

    if not overflow then
        scroll:SetVerticalScroll(0)
    else
        local maxScroll = math.max(0, neededHeight - viewportHeight)
        local current = scroll:GetVerticalScroll() or 0
        if current > maxScroll then
            scroll:SetVerticalScroll(maxScroll)
        end
    end
end

function IRS:RefreshAllPageScrolls()
    for _, key in ipairs(PAGE_ORDER) do
        local scroll = IRS.pageScrollFrames[key]
        if scroll and scroll:IsShown() then
            IRS:RefreshPageScroll(key)
        end
    end
end

IRS:UpdatePageScrollVisibility(IRS.activeTab or "dashboard")

-- Re-measure once the main IRS frame is actually visible. This handles the
-- first open cleanly because hidden frame geometry may not be fully resolved.
local firstPage = pageFrames.dashboard
local content = firstPage and firstPage:GetParent()
local mainFrame = content and content:GetParent()

if mainFrame and mainFrame.HookScript then
    mainFrame:HookScript("OnShow", function()
        C_Timer.After(0, function()
            IRS:RefreshPageScroll(IRS.activeTab or "dashboard")
        end)
    end)
end
