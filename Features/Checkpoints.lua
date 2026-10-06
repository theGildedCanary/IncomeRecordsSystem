--[[
IRS — Savings Project Checkpoints
Editor for named intermediate milestones used by Project trajectory views.
]]

local IRS = IRS
local parent = _G.IncomeRecordsSystemFrame or UIParent

local COLORS = {
    panel = {0.105, 0.086, 0.064, 0.995},
    row = {0.115, 0.094, 0.069, 0.985},
    border = {0.52, 0.39, 0.22, 1},
    gold = {0.86, 0.71, 0.36, 1},
    goldSoft = {0.79, 0.66, 0.39, 1},
    text = {0.88, 0.84, 0.75, 1},
    muted = {0.68, 0.62, 0.51, 1},
    green = {0.43, 0.60, 0.36, 1},
    red = {0.63, 0.29, 0.25, 1},
}

local function SetColor(fs, color)
    fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

local function MakeText(parentFrame, style, color, justify, flags)
    local fs = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local fontFlags = flags or ""

    fs:SetFont(
        STANDARD_TEXT_FONT,
        IRS:GetFontSize("main", style),
        fontFlags
    )
    fs:SetJustifyH(justify or "LEFT")
    fs:SetJustifyV("MIDDLE")

    if color then SetColor(fs, color) end

    IRS:RegisterFontString(
        "main",
        style,
        fs,
        STANDARD_TEXT_FONT,
        fontFlags
    )

    return fs
end

local function MakePanel(parentFrame, bg)
    local panel = CreateFrame("Frame", nil, parentFrame, "BackdropTemplate")
    panel:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })

    local c = bg or COLORS.panel
    panel:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
    panel:SetBackdropBorderColor(unpack(COLORS.border))
    return panel
end

local function ParseGoldInput(text)
    text = strtrim(tostring(text or "")):lower():gsub(",", ""):gsub("%s+", "")
    if text == "" then return nil end

    local multiplier = 1

    if text:sub(-1) == "m" then
        multiplier = 1000000
        text = text:sub(1, -2)
    elseif text:sub(-1) == "k" then
        multiplier = 1000
        text = text:sub(1, -2)
    elseif text:sub(-1) == "g" then
        text = text:sub(1, -2)
    end

    local gold = tonumber(text)
    if not gold or gold <= 0 then return nil end

    return math.floor((gold * multiplier * 10000) + 0.5)
end

local function GoldEditText(copper)
    return tostring(math.floor((tonumber(copper) or 0) / 10000))
end

local manager = MakePanel(parent)
manager:SetSize(600, 470)
manager:SetPoint("CENTER", parent, "CENTER", 0, 0)
manager:SetFrameStrata("DIALOG")
manager:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)
manager:SetClampedToScreen(true)
manager:EnableMouse(true)
manager:SetMovable(true)
manager:RegisterForDrag("LeftButton")
manager:SetScript("OnDragStart", manager.StartMoving)
manager:SetScript("OnDragStop", manager.StopMovingOrSizing)
manager:Hide()

local title = MakeText(manager, "page", COLORS.goldSoft, "LEFT")
title:SetPoint("TOPLEFT", 16, -14)
title:SetText("PROJECT CHECKPOINTS")

local projectName = MakeText(manager, "body", COLORS.text, "LEFT")
projectName:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
projectName:SetPoint("RIGHT", -48, 0)

local close = CreateFrame("Button", nil, manager, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -4, -4)

local intro = MakeText(manager, "helper", COLORS.muted, "LEFT")
intro:SetPoint("TOPLEFT", projectName, "BOTTOMLEFT", 0, -8)
intro:SetPoint("RIGHT", -16, 0)
intro:SetText("Add named intermediate gold goals. Checkpoints are automatically ordered by gold amount.")

local form = MakePanel(manager, {0.035, 0.038, 0.038, 0.98})
form:SetPoint("TOPLEFT", 14, -92)
form:SetPoint("TOPRIGHT", -14, -92)
form:SetHeight(92)

local nameLabel = MakeText(form, "helper", COLORS.muted, "LEFT")
nameLabel:SetPoint("TOPLEFT", 12, -10)
nameLabel:SetText("CHECKPOINT NAME")

local nameBox = CreateFrame("EditBox", nil, form, "InputBoxTemplate")
nameBox:SetPoint("TOPLEFT", 12, -29)
nameBox:SetSize(270, 26)
nameBox:SetAutoFocus(false)
nameBox:SetMaxLetters(40)

local goldLabel = MakeText(form, "helper", COLORS.muted, "LEFT")
goldLabel:SetPoint("TOPLEFT", 298, -10)
goldLabel:SetText("GOLD GOAL")

local goldBox = CreateFrame("EditBox", nil, form, "InputBoxTemplate")
goldBox:SetPoint("TOPLEFT", 298, -29)
goldBox:SetSize(130, 26)
goldBox:SetAutoFocus(false)

local save = CreateFrame("Button", nil, form, "UIPanelButtonTemplate")
save:SetSize(124, 26)
save:SetPoint("TOPRIGHT", -12, -29)
save:SetText("ADD CHECKPOINT")

local cancelEdit = CreateFrame("Button", nil, form, "UIPanelButtonTemplate")
cancelEdit:SetSize(90, 22)
cancelEdit:SetPoint("BOTTOMRIGHT", -12, 7)
cancelEdit:SetText("Cancel Edit")
cancelEdit:Hide()

local status = MakeText(form, "helper", COLORS.muted, "LEFT")
status:SetPoint("BOTTOMLEFT", 12, 9)
status:SetPoint("RIGHT", cancelEdit, "LEFT", -8, 0)

local listPanel = MakePanel(manager, {0.028, 0.030, 0.030, 0.98})
listPanel:SetPoint("TOPLEFT", form, "BOTTOMLEFT", 0, -10)
listPanel:SetPoint("BOTTOMRIGHT", manager, "BOTTOMRIGHT", -14, 14)

local listTitle = MakeText(listPanel, "section", COLORS.goldSoft, "LEFT")
listTitle:SetPoint("TOPLEFT", 12, -10)
listTitle:SetText("SAVED CHECKPOINTS")

local listHint = MakeText(listPanel, "helper", COLORS.muted, "RIGHT")
listHint:SetPoint("TOPRIGHT", -28, -13)
listHint:SetText("Reached milestones are green.")

local scroll = CreateFrame("ScrollFrame", nil, listPanel, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 10, -42)
scroll:SetPoint("BOTTOMRIGHT", -28, 10)

local child = CreateFrame("Frame", nil, scroll)
child:SetSize(530, 1)
scroll:SetScrollChild(child)

local empty = MakeText(child, "body", COLORS.muted, "CENTER")
empty:SetPoint("TOPLEFT", 8, -18)
empty:SetWidth(510)

local rows = {}
local editingId = nil

local function ClearEditor()
    editingId = nil
    nameBox:SetText("")
    goldBox:SetText("")
    save:SetText("ADD CHECKPOINT")
    cancelEdit:Hide()
end

local function EnsureRow(index)
    if rows[index] then return rows[index] end

    local row = MakePanel(child, COLORS.row)
    row:SetHeight(48)
    row:SetBackdropBorderColor(0.13, 0.15, 0.15, 1)

    row.name = MakeText(row, "body", COLORS.goldSoft, "LEFT", "OUTLINE")
    row.name:SetPoint("TOPLEFT", 10, -7)
    row.name:SetWidth(220)

    row.amount = MakeText(row, "body", COLORS.text, "RIGHT")
    row.amount:SetPoint("TOPRIGHT", -154, -7)
    row.amount:SetWidth(120)

    row.state = MakeText(row, "helper", COLORS.muted, "LEFT")
    row.state:SetPoint("BOTTOMLEFT", 10, 7)
    row.state:SetWidth(320)

    row.edit = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.edit:SetSize(60, 24)
    row.edit:SetPoint("RIGHT", -76, 0)
    row.edit:SetText("Edit")

    row.delete = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.delete:SetSize(66, 24)
    row.delete:SetPoint("RIGHT", -7, 0)
    row.delete:SetText("Delete")

    rows[index] = row
    return row
end

local RefreshRows

RefreshRows = function()
    local projectId = IRS.GetSelectedProjectId and IRS:GetSelectedProjectId()
    local project = projectId and IRS:GetProject(projectId) or nil

    if not project then
        projectName:SetText("No saved project selected")
        empty:SetText("Select or save a project before adding checkpoints.")
        empty:Show()

        for _, row in ipairs(rows) do
            row:Hide()
        end

        child:SetHeight(1)
        return
    end

    projectName:SetText(project.name or "Savings Project")

    local checkpoints = IRS:GetProjectCheckpoints(project)
    empty:SetShown(#checkpoints == 0)
    empty:SetText("No custom checkpoints yet.")

    local rowHeight = math.max(
        48,
        IRS:GetFontSize("main", "body")
            + IRS:GetFontSize("main", "helper")
            + 22
    )
    local rowWidth = math.max(500, (scroll:GetWidth() or 530) - 4)

    for i, checkpoint in ipairs(checkpoints) do
        local row = EnsureRow(i)
        local checkpointState = IRS:GetProjectCheckpointStatus(project, checkpoint)

        row.checkpointId = checkpoint.id
        row:SetHeight(rowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -((i - 1) * (rowHeight + 4)))
        row:SetWidth(rowWidth)

        row.name:SetText(checkpoint.name or "Checkpoint")
        row.amount:SetText(IRS:FormatMoney(checkpoint.amountCopper or 0))

        if checkpointState and checkpointState.aboveTarget then
            row.state:SetText("Above current project target — edit or remove.")
            SetColor(row.state, COLORS.red)
        elseif checkpointState and checkpointState.reached then
            row.state:SetText("REACHED")
            SetColor(row.state, COLORS.green)
        else
            row.state:SetText(
                "Remaining: "
                    .. IRS:FormatMoney(
                        checkpointState and checkpointState.remaining or 0
                    )
            )
            SetColor(row.state, COLORS.muted)
        end

        row.edit:SetScript("OnClick", function()
            editingId = checkpoint.id
            nameBox:SetText(checkpoint.name or "")
            goldBox:SetText(GoldEditText(checkpoint.amountCopper))
            save:SetText("SAVE CHANGES")
            cancelEdit:Show()
            status:SetText("Editing " .. (checkpoint.name or "checkpoint") .. ".")
        end)

        row.delete:SetScript("OnClick", function()
            IRS:DeleteProjectCheckpoint(projectId, checkpoint.id)

            if editingId == checkpoint.id then
                ClearEditor()
            end

            status:SetText("Checkpoint deleted.")
            RefreshRows()

            if IRS.RefreshProjectsPage then
                IRS:RefreshProjectsPage(true)
            end
        end)

        row:Show()
    end

    for i = #checkpoints + 1, #rows do
        rows[i]:Hide()
    end

    child:SetHeight(
        math.max(1, #checkpoints * (rowHeight + 4))
    )
end

cancelEdit:SetScript("OnClick", function()
    ClearEditor()
    status:SetText("")
end)

save:SetScript("OnClick", function()
    local projectId = IRS.GetSelectedProjectId and IRS:GetSelectedProjectId()

    if not projectId then
        status:SetText("Select or save a project first.")
        return
    end

    local amount = ParseGoldInput(goldBox:GetText())
    if not amount then
        status:SetText("Enter a valid amount, such as 500000 or 500k.")
        return
    end

    local ok, result

    if editingId then
        ok, result = IRS:UpdateProjectCheckpoint(
            projectId,
            editingId,
            nameBox:GetText(),
            amount
        )
    else
        local id
        id, result = IRS:AddProjectCheckpoint(
            projectId,
            nameBox:GetText(),
            amount
        )
        ok = id ~= nil
    end

    if not ok then
        status:SetText(result or "Could not save checkpoint.")
        return
    end

    local wasEditing = editingId ~= nil
    ClearEditor()
    status:SetText(wasEditing and "Checkpoint updated." or "Checkpoint added.")
    RefreshRows()

    if IRS.RefreshProjectsPage then
        IRS:RefreshProjectsPage(true)
    end
end)

function IRS:RefreshProjectCheckpointsButton(project)
    local button = IRS.projectCheckpointsButton
    if not button then return end

    if not project then
        button:SetEnabled(false)
        if button.label then
            button.label:SetText("CHECKPOINTS")
        end
        return
    end

    local count = #IRS:GetProjectCheckpoints(project)
    button:SetEnabled(true)

    if button.label then
        if count > 0 then
            button.label:SetText("CHECKPOINTS (" .. count .. ")")
        else
            button.label:SetText("CHECKPOINTS")
        end
    end

    if manager:IsShown() then
        RefreshRows()
    end
end

function IRS:ShowProjectCheckpointsManager()
    local projectId = IRS.GetSelectedProjectId and IRS:GetSelectedProjectId()

    if not projectId then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffffc247IRS:|r Save or select a Savings Project before adding checkpoints."
            )
        end
        return
    end

    ClearEditor()
    status:SetText("")
    RefreshRows()
    manager:Show()
end


manager:SetScript("OnShow", RefreshRows)
