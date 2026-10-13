-- IRS owns these text regions so tooltip population cannot restore GameFonts.
local IRS = IRS
function IRS:CreateMicroTooltip()
    local popup = CreateFrame("Frame", "IncomeRecordsSystemMicroTooltip", UIParent, "BackdropTemplate")
    popup:SetFrameStrata("TOOLTIP")
    popup:SetClampedToScreen(true)
    popup:Hide()
    local rows, count, owner = {}, 0, nil
    local showFrame = popup.Show

    local function Text(row, key, style, justify)
        if not row[key] then
            local text = popup:CreateFontString(nil, "OVERLAY")
            IRS:RegisterFontString("main", style, text, STANDARD_TEXT_FONT, "")
            text:SetJustifyH(justify)
            text:SetJustifyV("TOP")
            text:SetWordWrap(true)
            text:SetSpacing(2)
            row[key] = text
        end
        return row[key]
    end

    local function AddRow(left, right, leftColor, rightColor, style)
        count = count + 1
        rows[count] = rows[count] or {}
        local row = rows[count]
        for _, text in pairs(row) do text:Hide() end
        row.left = nil
        row.right = nil
        local key = "left_" .. (style or "body")
        local l = Text(row, key, style or "body", "LEFT")
        l:SetText(left or "")
        l:SetTextColor(unpack(leftColor))
        l:Show()
        row.left = l
        if right then
            local r = Text(row, "right_body", "body", "RIGHT")
            r:SetText(right)
            r:SetTextColor(unpack(rightColor))
            r:Show()
            row.right = r
        end
    end

    function popup:SetOwner(newOwner)
        owner = newOwner
        self:ClearAllPoints()
        self:SetPoint("BOTTOMLEFT", newOwner, "TOPLEFT", 0, 8)
    end
    function popup:IsOwned(candidate) return owner == candidate and self:IsShown() end
    function popup:SetText(text, r, g, b)
        for _, row in ipairs(rows) do
            for _, region in pairs(row) do region:Hide() end
        end
        count = 0
        AddRow(text, nil, {r or 1, g or 1, b or 1}, nil, "section")
    end
    function popup:AddLine(text, r, g, b, wrap, style)
        AddRow(text, nil, {r or 1, g or 1, b or 1}, nil, style or "body")
    end
    function popup:AddDoubleLine(left, right, lr, lg, lb, rr, rg, rb)
        AddRow(left, right, {lr or 1, lg or 1, lb or 1}, {rr or 1, rg or 1, rb or 1}, "body")
    end
    function popup:Show()
        local maxWidth = math.min(UIParent:GetWidth() * 0.6,
            math.max(360, IRS:GetFontSize("main", "body") * 24))
        local width = 300
        for i = 1, count do
            local row = rows[i]
            local needed = row.left:GetUnboundedStringWidth()
            if row.right then needed = needed + row.right:GetUnboundedStringWidth() + 20 end
            -- Explanatory prose wraps within the data width rather than making
            -- the whole popup as wide as the longest sentence.
            if row.right or i == 1 then
                width = math.max(width, math.min(maxWidth, needed + 24))
            end
        end
        local y = 12
        for i = 1, count do
            local row = rows[i]
            local available = width - 24
            row.left:ClearAllPoints()
            row.left:SetPoint("TOPLEFT", 12, -y)
            row.left:SetWidth(row.right and (available * 0.5 - 10) or available)
            local height = row.left:GetStringHeight()
            if row.right then
                row.right:ClearAllPoints()
                row.right:SetPoint("TOPRIGHT", -12, -y)
                row.right:SetWidth(available * 0.5 - 10)
                height = math.max(height, row.right:GetStringHeight())
            end
            y = y + math.max(4, height) + 4
        end
        self:SetSize(width, y + 8)
        showFrame(self)
    end
    return popup
end
