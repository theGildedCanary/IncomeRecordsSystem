--[[
IRS — Window Resizing
Persistent resize controls for the main window and Mini Dashboard.
]]

local IRS = IRS

local MAIN_DEFAULT_W = 1020
local MAIN_DEFAULT_H = 760
local MAIN_MIN_W = 1020
local MAIN_MIN_H = 560
local MINI_DEFAULT_W = 350
local MINI_DEFAULT_H = 260
local MINI_MIN_W = 300
local MINI_MIN_H = 164

local runtime = {
    mainManualResize = false,
    miniManualResize = false,
}

local function Clamp(value, low, high)
    value = tonumber(value) or low
    if value < low then return low end
    if value > high then return high end
    return value
end

local function EnsureResizeDB()
    if not IRS.db then IRS:EnsureDB() end

    IRS.db.ui = IRS.db.ui or {}
    IRS.db.ui.mainWindow = IRS.db.ui.mainWindow or {}
    IRS.db.ui.miniDashboard = IRS.db.ui.miniDashboard or {}

    local main = IRS.db.ui.mainWindow
    local mini = IRS.db.ui.miniDashboard

    if main.sizeLocked == nil then main.sizeLocked = true end
    if mini.sizeLocked == nil then mini.sizeLocked = true end

    return main, mini
end

local function GetMaximumSize(minW, minH)
    local screenW = UIParent and UIParent:GetWidth() or 1920
    local screenH = UIParent and UIParent:GetHeight() or 1080

    return math.max(minW, math.floor(screenW - 30)),
        math.max(minH, math.floor(screenH - 30))
end

local function ApplyResizeBounds(frame, minW, minH)
    if not frame then return end

    local maxW, maxH = GetMaximumSize(minW, minH)

    if frame.SetResizeBounds then
        frame:SetResizeBounds(minW, minH, maxW, maxH)
    else
        if frame.SetMinResize then frame:SetMinResize(minW, minH) end
        if frame.SetMaxResize then frame:SetMaxResize(maxW, maxH) end
    end
end

local function MakeGrip(parent)
    local grip = CreateFrame("Button", nil, parent)
    grip:SetSize(24, 24)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(parent:GetFrameLevel() + 20)
    grip:EnableMouse(true)
    grip:Hide()

    -- Three generated stair-step lines: no image asset required.
    for i = 1, 3 do
        local h = grip:CreateTexture(nil, "OVERLAY")
        h:SetTexture("Interface/Buttons/WHITE8X8")
        h:SetVertexColor(0.79, 0.66, 0.39, 0.95)
        h:SetSize(4 + ((i - 1) * 4), 1)
        h:SetPoint("BOTTOMRIGHT", -4, 3 + ((i - 1) * 4))

        local v = grip:CreateTexture(nil, "OVERLAY")
        v:SetTexture("Interface/Buttons/WHITE8X8")
        v:SetVertexColor(0.79, 0.66, 0.39, 0.95)
        v:SetSize(1, 4 + ((i - 1) * 4))
        v:SetPoint("BOTTOMRIGHT", -(3 + ((i - 1) * 4)), 4)
    end

    return grip
end

local function MakeLockButton(parent, width, x, y)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 20)
    button:SetPoint("TOPRIGHT", x, y)
    button:SetFrameLevel(parent:GetFrameLevel() + 21)
    return button
end

local function SaveMainSize()
    if not IRS.mainFrame then return end
    local main = EnsureResizeDB()

    main.width = math.floor((IRS.mainFrame:GetWidth() or MAIN_DEFAULT_W) + 0.5)
    main.height = math.floor((IRS.mainFrame:GetHeight() or MAIN_DEFAULT_H) + 0.5)
    main.userSized = true
end

local function SaveMiniSize()
    if not IRS.miniDashboardFrame then return end
    local _, mini = EnsureResizeDB()

    mini.width = math.floor((IRS.miniDashboardFrame:GetWidth() or MINI_DEFAULT_W) + 0.5)
    mini.height = math.floor((IRS.miniDashboardFrame:GetHeight() or MINI_DEFAULT_H) + 0.5)
    mini.userSized = true

    if IRS.SaveMiniDashboardAnchor then
        IRS:SaveMiniDashboardAnchor()
    end
end

local mainButton, miniButton
local mainGrip, miniGrip

local function ApplyMainLockState()
    if not IRS.mainFrame or not mainButton or not mainGrip then return end
    local main = EnsureResizeDB()
    local unlocked = main.sizeLocked == false

    if IRS.mainFrame.SetResizable then
        IRS.mainFrame:SetResizable(unlocked)
    end

    mainButton:SetText(unlocked and "Lock" or "Unlock")
    mainGrip:SetShown(unlocked)
end

local function ApplyMiniLockState()
    if not IRS.miniDashboardFrame or not miniButton or not miniGrip then return end
    local _, mini = EnsureResizeDB()
    local unlocked = mini.sizeLocked == false

    if IRS.miniDashboardFrame.SetResizable then
        IRS.miniDashboardFrame:SetResizable(unlocked)
    end

    miniButton:SetText(unlocked and "Lock" or "Unlock")
    miniGrip:SetShown(unlocked)
end

local function RestoreSizes()
    local mainSaved, miniSaved = EnsureResizeDB()
    local main = IRS.mainFrame
    local mini = IRS.miniDashboardFrame

    if main then
        ApplyResizeBounds(main, MAIN_MIN_W, MAIN_MIN_H)
        local maxW, maxH = GetMaximumSize(MAIN_MIN_W, MAIN_MIN_H)
        main:SetSize(
            Clamp(mainSaved.width or MAIN_DEFAULT_W, MAIN_MIN_W, maxW),
            Clamp(mainSaved.height or MAIN_DEFAULT_H, MAIN_MIN_H, maxH)
        )
    end

    if mini then
        ApplyResizeBounds(mini, MINI_MIN_W, MINI_MIN_H)
        local maxW, maxH = GetMaximumSize(MINI_MIN_W, MINI_MIN_H)
        mini:SetWidth(Clamp(miniSaved.width or MINI_DEFAULT_W, MINI_MIN_W, maxW))

        if miniSaved.userSized and miniSaved.height then
            mini:SetHeight(Clamp(miniSaved.height, MINI_MIN_H, maxH))
        end
    end

    if IRS.RefreshMainWindowSizeLayout then
        IRS:RefreshMainWindowSizeLayout()
    end

    if IRS.RefreshMiniDashboard and mini and mini:IsShown() then
        IRS:RefreshMiniDashboard()
    end
end

local function BuildControls()
    if IRS.mainFrame and not mainButton then
        local main = IRS.mainFrame
        mainButton = MakeLockButton(main, 64, -42, -10)
        mainGrip = MakeGrip(main)

        mainButton:SetScript("OnClick", function()
            local saved = EnsureResizeDB()
            saved.sizeLocked = not (saved.sizeLocked ~= false)
            ApplyMainLockState()
        end)

        mainGrip:SetScript("OnMouseDown", function(_, button)
            if button ~= "LeftButton" then return end
            local saved = EnsureResizeDB()
            if saved.sizeLocked ~= false then return end

            runtime.mainManualResize = true
            main:StartSizing("BOTTOMRIGHT")
        end)

        mainGrip:SetScript("OnMouseUp", function()
            if not runtime.mainManualResize then return end
            main:StopMovingOrSizing()
            runtime.mainManualResize = false
            SaveMainSize()

            if IRS.RefreshMainWindowSizeLayout then
                IRS:RefreshMainWindowSizeLayout()
            end
            if IRS.RefreshUI then IRS:RefreshUI() end
            if IRS.RefreshAllPageScrolls then IRS:RefreshAllPageScrolls() end
        end)

        main:SetScript("OnSizeChanged", function()
            if IRS.RefreshMainWindowSizeLayout then
                IRS:RefreshMainWindowSizeLayout()
            end
        end)
    end

    if IRS.miniDashboardFrame and not miniButton then
        local mini = IRS.miniDashboardFrame
        miniButton = MakeLockButton(mini, 54, -34, -5)
        miniGrip = MakeGrip(mini)

        miniButton:SetScript("OnClick", function()
            local _, saved = EnsureResizeDB()
            saved.sizeLocked = not (saved.sizeLocked ~= false)
            ApplyMiniLockState()
        end)

        miniGrip:SetScript("OnMouseDown", function(_, button)
            if button ~= "LeftButton" then return end
            local _, saved = EnsureResizeDB()
            if saved.sizeLocked ~= false then return end

            runtime.miniManualResize = true
            mini:StartSizing("BOTTOMRIGHT")
        end)

        miniGrip:SetScript("OnMouseUp", function()
            if not runtime.miniManualResize then return end
            mini:StopMovingOrSizing()
            runtime.miniManualResize = false
            SaveMiniSize()

            -- Refresh applies the saved width and respects the content minimum
            -- height while keeping any extra user-requested height.
            if IRS.RefreshMiniDashboard then IRS:RefreshMiniDashboard() end
        end)
    end

    ApplyMainLockState()
    ApplyMiniLockState()
end


local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
eventFrame:RegisterEvent("UI_SCALE_CHANGED")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 ~= "IncomeRecordsSystem" then
        return
    end

    if not IRS.db then IRS:EnsureDB() end

    BuildControls()
    RestoreSizes()
end)
