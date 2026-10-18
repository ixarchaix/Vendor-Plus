--------------------------------------------------------------------------
-- VendorPlus
-- Replaces the default merchant window with a searchable / sortable list and
-- shows TSM region data next to each item:
--   * Region avg sale price  (DBRegionSaleAvg)
--   * Region sold per day    (DBRegionSoldPerDay)
--   * Min buyout             (DBMinBuyout)
--------------------------------------------------------------------------
local ADDON_NAME = ...
local VP = {}
_G.VendorPlus = VP

local DEFAULTS = {
    enabled     = true,
    sort        = "default",  -- default | name | price | buyout | avg | sold
    sortDesc    = true,
    pos         = nil,        -- saved window position {left, top}
    soldDivisor = 1,          -- adjust with /vp divisor <n> if Sold/Day looks scaled (e.g. 100)
    confirmGold = 1000,       -- confirm purchases costing more than this many gold
    view        = "vp",       -- default | vp | tsm
}

--------------------------------------------------------------------------
-- Theme: matched to Regional Edge (dark navy, blue accent, lime row bars,
-- green sort arrow, stat card, underline tabs)
--------------------------------------------------------------------------
local FLAT = "Interface\\Buttons\\WHITE8X8"
local K = {
    window   = { 0.047, 0.055, 0.075, 0.98 },
    card     = { 0.075, 0.087, 0.118, 1 },
    cardHi   = { 0.105, 0.120, 0.158, 1 },
    input    = { 0.035, 0.040, 0.055, 1 },
    border   = { 0.140, 0.160, 0.210, 1 },
    accent   = { 0.31, 0.64, 1.00, 1 },
    accentBg = { 0.16, 0.38, 0.72, 1 },
    accentHi = { 0.21, 0.47, 0.86, 1 },
    text     = { 0.92, 0.93, 0.95, 1 },
    dim      = { 0.52, 0.56, 0.63, 1 },
    faint    = { 0.36, 0.40, 0.47, 1 },
    lime     = { 0.67, 0.85, 0.32, 1 },
    green    = { 0.30, 0.88, 0.48, 1 },
    amber    = { 1.00, 0.72, 0.26, 1 },
    gold     = { 1.00, 0.80, 0.25, 1 },
    red      = { 1.00, 0.36, 0.36, 1 },
}

-- Layout
local FRAME_W, ROW_H, ROWS = 556, 38, 10
local PAD = 14
local ROW_W = FRAME_W - 2 * PAD - 10                 -- leaves room for the slim scrollbar
local TOP = 188                                      -- y offset where rows begin
local FRAME_H = TOP + ROWS * ROW_H + 64
local COL = { sold = 58, avg = 104, buyout = 104 }   -- right-hand columns, widths
local COL_GAP, COL_PAD = 8, 6
local NAME_W = ROW_W - 50 - (COL.sold + COL.avg + COL.buyout + 2 * COL_GAP + COL_PAD) - 8
local ARROW_W = 12

local DB
VP.list = {}
VP.rows = {}
VP.mode = "merchant"
VP.search = ""
VP.offset = 0
VP.limitedItems = {}

--------------------------------------------------------------------------
-- Fonts: game default font (as Regional Edge), light text, muted grey labels.
-- Change the typeface in-game with:  /vp font <path to .ttf>   (/vp font reset)
--------------------------------------------------------------------------
local DEFAULT_FONT = STANDARD_TEXT_FONT   -- same font Regional Edge uses
local FONT_SPECS = {
    --                      size, flags,     r,    g,    b
    VendorPlusTitle     = { 20, "",        0.92, 0.93, 0.95 },
    VendorPlusName      = { 13, "",        0.92, 0.93, 0.95 },
    VendorPlusText      = { 12, "",        0.92, 0.93, 0.95 },
    VendorPlusSmall     = { 11, "",        0.52, 0.56, 0.63 },
    VendorPlusHeader    = { 12, "",        0.52, 0.56, 0.63 },
    VendorPlusLabel     = { 10, "",        0.52, 0.56, 0.63 },
    VendorPlusValue     = { 22, "",        0.92, 0.93, 0.95 },
    VendorPlusCount     = { 11, "OUTLINE", 1.00, 1.00, 1.00 },
    VendorPlusButton    = { 12, "",        0.92, 0.93, 0.95 },
    VendorPlusButtonOff = { 12, "",        0.52, 0.56, 0.63 },
}
local fonts = {}
for name, spec in pairs(FONT_SPECS) do
    local f = CreateFont(name)
    f:SetFont(DEFAULT_FONT, spec[1], spec[2])
    f:SetTextColor(spec[3], spec[4], spec[5])
    fonts[name] = f
end

-- Returns false (and falls back to the default) if the path can't be loaded.
function VP:ApplyFonts(path)
    path = (path and path ~= "") and path or DEFAULT_FONT
    local ok = true
    for name, spec in pairs(FONT_SPECS) do
        if not fonts[name]:SetFont(path, spec[1], spec[2]) then ok = false break end
    end
    if not ok then
        for name, spec in pairs(FONT_SPECS) do fonts[name]:SetFont(DEFAULT_FONT, spec[1], spec[2]) end
    end
    return ok
end

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------
local function CoinString(copper)
    local fn = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    return fn(copper, 12)
end

local function Money(c)
    if not c then return "|cff858fa1--|r" end
    c = math.floor(c + 0.5)
    if c >= 10000 then c = math.floor(c / 100) * 100 end -- drop copper on big values
    return CoinString(c)
end

local function TSMAvailable()
    return TSM_API and TSM_API.GetCustomPriceValue and TSM_API.ToItemString
end

local function ItemStringFor(link)
    if not link or not TSMAvailable() then return end
    local ok, s = pcall(TSM_API.ToItemString, link)
    if ok then return s end
end

local function TSMValue(source, itemString)
    local ok, v = pcall(TSM_API.GetCustomPriceValue, source, itemString)
    if ok and type(v) == "number" then return v end
end

-- TSM custom prices are rounded to whole numbers and tiny results (e.g. 0.05
-- sold/day) collapse to 0 and come back nil. Ask for value*1000 and scale
-- back down so fractional values survive.
local function TSMFractional(source, itemString)
    local v = TSMValue(source .. " * 1000", itemString)
    if v then return v / 1000 end
    return TSMValue(source, itemString)
end

local function GetTSMData(link)
    local s = ItemStringFor(link)
    if not s then return end
    return TSMValue("DBRegionSaleAvg", s),
           TSMFractional("DBRegionSoldPerDay", s),
           TSMValue("DBMinBuyout", s)
end

local function ColorName(name, link)
    name = name or "Loading..."
    if not link then return name end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, _, quality = getInfo(link)
    local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if c and c.color then return c.color:WrapTextInColorCode(name) end
    return name
end

local function QualityRGB(link)
    if not link then return end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, _, quality = getInfo(link)
    local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if c then return c.r, c.g, c.b end
end

local function SoldText(sold)
    if not sold then return "|cff858fa1--|r" end
    if sold >= 10 then return string.format("%.0f/d", sold) end
    if sold >= 1 then return string.format("%.1f/d", sold) end
    return string.format("%.3f/d", sold)
end

--------------------------------------------------------------------------
-- Reading vendor data (works with both the old global API and the newer
-- C_MerchantFrame table API)
--------------------------------------------------------------------------
local function MerchantInfo(index)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local t = C_MerchantFrame.GetItemInfo(index)
        if t then
            return t.name, t.texture, t.price, t.stackCount, t.numAvailable,
                   t.isPurchasable, t.isUsable, t.hasExtendedCost
        end
        return
    end
    local name, tex, price, qty, avail, purchasable, usable, ext = GetMerchantItemInfo(index)
    return name, tex, price, qty, avail, purchasable, usable, ext
end

local function ReadMerchant(i)
    local name, tex, price, qty, avail, purchasable, usable, ext = MerchantInfo(i)
    if not name and not tex then return end
    local e = {
        index = i, mode = "merchant", name = name, texture = tex,
        price = price or 0, qty = (qty and qty > 0) and qty or 1,
        avail = avail or -1, usable = usable ~= false,
        link = GetMerchantItemLink(i),
        purchasable = purchasable ~= false,
    }
    if ext then
        e.costs = {}
        for j = 1, (GetMerchantItemCostInfo(i) or 0) do
            local ctex, cval = GetMerchantItemCostItem(i, j)
            if ctex then e.costs[#e.costs + 1] = { tex = ctex, val = cval } end
        end
    end
    return e
end

local function ReadBuyback(i)
    local name, tex, price, qty, avail, usable = GetBuybackItemInfo(i)
    if not name then return end
    return {
        index = i, mode = "buyback", name = name, texture = tex,
        price = price or 0, qty = qty or 1, avail = -1,
        usable = usable ~= false, link = GetBuybackItemLink(i),
    }
end

--------------------------------------------------------------------------
-- Build / sort the list
--------------------------------------------------------------------------
function VP:BuildList()
    wipe(self.list)
    local isBuyback = self.mode == "buyback"
    local n = isBuyback and GetNumBuybackItems() or GetMerchantNumItems()
    local filter = (self.search or ""):lower()
    self.limitedItems = {}

    for i = 1, n do
        local e = isBuyback and ReadBuyback(i) or ReadMerchant(i)
        -- gold-priced items with stock left count towards "Buy Limited"
        if e and not isBuyback and e.avail and e.avail > 0 and not e.costs and e.purchasable then
            self.limitedItems[#self.limitedItems + 1] = e
        end
        if e and (filter == "" or (e.name or ""):lower():find(filter, 1, true)) then
            e.avg, e.sold, e.buyout = GetTSMData(e.link)
            if e.sold then e.sold = e.sold / (DB.soldDivisor or 1) end
            self.list[#self.list + 1] = e
        end
    end

    self:ComputeBuyAll()

    local key = DB.sort
    if key and key ~= "default" then
        local desc = DB.sortDesc
        table.sort(self.list, function(a, b)
            local av, bv
            if key == "name" then
                av, bv = (a.name or ""):lower(), (b.name or ""):lower()
            elseif key == "price" then
                av, bv = a.price / a.qty, b.price / b.qty
            else
                av, bv = a[key], b[key]
            end
            -- items with no value always sort last
            if av == nil and bv == nil then return a.index < b.index end
            if av == nil then return false end
            if bv == nil then return true end
            if av ~= bv then
                if desc then return av > bv else return av < bv end
            end
            return a.index < b.index
        end)
    end
end

--------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------
local function CostText(e)
    local parts = {}
    if e.price > 0 then
        local s = CoinString(e.price)
        if e.mode == "merchant" and not e.costs and e.price > GetMoney() then
            s = "|cffff5c5c" .. s .. "|r"
        end
        parts[#parts + 1] = s
    end
    if e.costs then
        for _, c in ipairs(e.costs) do
            parts[#parts + 1] = string.format("|T%s:12|t %d", c.tex, c.val)
        end
    end
    local text = #parts > 0 and table.concat(parts, "  ") or "|cff858fa1Free|r"
    if e.avail and e.avail >= 0 then
        text = text .. string.format("  |cffffb842(%d left)|r", e.avail)
    end
    return text
end

function VP:UpdateScrollbar(maxOff)
    local sb = self.sb
    if not sb then return end
    sb:SetMinMaxValues(0, maxOff)
    if math.floor(sb:GetValue() + 0.5) ~= self.offset then sb:SetValue(self.offset) end
    sb:SetShown(maxOff > 0)
end

function VP:Render()
    if not self.frame or not self.frame:IsShown() then return end
    local count = #self.list
    local maxOff = math.max(0, count - ROWS)
    if self.offset > maxOff then self.offset = maxOff end
    self:UpdateScrollbar(maxOff)
    local offset = self.offset

    for i = 1, ROWS do
        local row, e = self.rows[i], self.list[offset + i]
        if e then
            row.entry = e
            row.icon:SetTexture(e.texture)
            row.icon:SetDesaturated(not e.usable)
            row.count:SetText(e.qty > 1 and e.qty or "")
            local qr, qg, qb = QualityRGB(e.link)
            if qr then row.iconBox:SetBackdropBorderColor(qr, qg, qb, 1)
            else row.iconBox:SetBackdropBorderColor(unpack(K.border)) end
            row.name:SetText(ColorName(e.name, e.link))
            row.cost:SetText(CostText(e))

            -- Avg sale price: green when it beats the vendor's per-item cost
            local avgText = Money(e.avg)
            local profit = e.avg and e.price > 0 and not e.costs and e.avg > (e.price / e.qty)
            if profit then
                avgText = "|cff4de07a" .. avgText .. "|r"
                row.bar:SetColorTexture(K.lime[1], K.lime[2], K.lime[3], 0.7)
                row.bar:Show()
            else
                row.bar:Hide()
            end
            row.avg:SetText(avgText)
            row.buyout:SetText(Money(e.buyout))
            row.sold:SetText(SoldText(e.sold))
            VP.SetSparkle(row, e.avail ~= nil and e.avail > 0) -- limited stock only; no glow once it hits 0
            row:Show()
        else
            row.entry = nil
            row.bar:Hide()
            VP.SetSparkle(row, false)
            row:Hide()
        end
    end

    self.money:SetText(CoinString(GetMoney()))
    for key, h in pairs(self.headers) do
        local active = (DB.sort == key)
        h.label:SetText(h.baseText)
        h.label:SetTextColor(unpack(active and K.text or K.dim))
        h.label:ClearAllPoints()
        h.arrow:ClearAllPoints()
        if h.leftAligned then
            -- arrow sits at the left edge, text shifts right of it
            if active then
                h.label:SetPoint("TOPLEFT", h, "TOPLEFT", ARROW_W, 0)
                h.label:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 0)
                h.arrow:SetPoint("LEFT", h, "LEFT", 0, 0)
            else
                h.label:SetAllPoints()
            end
        else
            -- arrow sits just left of the label text
            h.label:SetAllPoints()
            h.arrow:SetPoint("RIGHT", h, "RIGHT", -(h.label:GetStringWidth() + 4), 0)
        end
        if active then
            h.arrow:SetDirection(not DB.sortDesc)
            h.arrow:Show()
        else
            h.arrow:Hide()
        end
    end

    -- stat card
    local stat = self.stat
    if stat then
        stat.label:SetText(self.mode == "buyback" and "BUYBACK ITEMS" or "ITEMS FOR SALE")
        stat.value:SetText(count)
        if (self.search or "") ~= "" then
            stat.sub:SetText("matching your search")
        elseif self.mode == "merchant" and #self.limitedItems > 0 then
            stat.sub:SetText(#self.limitedItems .. " limited supply")
        elseif self.mode == "buyback" then
            stat.sub:SetText("recently sold to this vendor")
        else
            stat.sub:SetText("in stock")
        end
    end
    self.tabMerchant:SetActiveTab(self.mode == "merchant")
    self.tabBuyback:SetActiveTab(self.mode == "buyback")

    -- Buy Limited
    if self.mode == "merchant" and #self.limitedItems > 0 then
        local label = CoinString(self.buyAllFull and self.buyAllTotal or self.buyAllCost)
        if not self.buyAllFull then label = "|cffff5c5c" .. label .. "|r" end
        self.buyAll:SetText("Buy Limited: " .. label)
        self.buyAll:SetEnabled(self.buyAllItems > 0)
        self.buyAll:Show()
    else
        self.buyAll:Hide()
    end

    -- Repair
    if CanMerchantRepair() then
        local cost, can = GetRepairAllCost()
        self.repair:SetText("Repair: " .. Money(cost or 0))
        self.repair:SetEnabled(can and cost and cost > 0 and GetMoney() >= cost)
        self.repair:Show()
    else
        self.repair:Hide()
    end

    -- Sell junk
    if C_MerchantFrame and C_MerchantFrame.IsSellAllJunkEnabled
       and C_MerchantFrame.IsSellAllJunkEnabled() then
        self.junk:Show()
    else
        self.junk:Hide()
    end

    self.noTSM:SetShown(not TSMAvailable())
end

function VP:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    self:BuildList()
    self:Render()
end

local pending
function VP:RefreshSoon()
    if pending then return end
    pending = true
    C_Timer.After(0.1, function()
        pending = false
        VP:Refresh()
    end)
end

--------------------------------------------------------------------------
-- Buying
--------------------------------------------------------------------------
StaticPopupDialogs["VENDORPLUS_CONFIRM"] = {
    text = "Buy %s?\n%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data)
        if data then BuyMerchantItem(data.index, data.qty) end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function MaxPurchasable(e)
    local n = GetMerchantItemMaxStack(e.index) or 1
    if e.avail and e.avail >= 0 then n = math.min(n, e.avail * e.qty) end
    if e.price > 0 then
        n = math.min(n, math.floor(GetMoney() / e.price) * e.qty)
    end
    return math.max(n, 0)
end

local function TotalCostText(e, qty)
    local units = qty / e.qty
    local parts = {}
    if e.price > 0 then
        parts[#parts + 1] = CoinString(math.floor(e.price * units + 0.5))
    end
    if e.costs then
        for _, c in ipairs(e.costs) do
            parts[#parts + 1] = string.format("|T%s:12|t %d", c.tex, math.floor(c.val * units + 0.5))
        end
    end
    return #parts > 0 and table.concat(parts, "  ") or "Free"
end

-- qty is a number of ITEMS (a vendor selling stacks of 5 takes 5, 10, 15...)
function VP:BuyQuantity(e, qty)
    if not e or not qty or qty < 1 then return end
    if e.mode == "buyback" then
        BuybackItem(e.index)
        return
    end
    local total = e.price * (qty / e.qty)
    if e.costs or total > (DB.confirmGold or 0) * 10000 then
        StaticPopup_Show("VENDORPLUS_CONFIRM",
            string.format("%s x%d", e.name or "item", qty),
            TotalCostText(e, qty),
            { index = e.index, qty = qty })
    else
        BuyMerchantItem(e.index, qty)
    end
end

-- "Buy Limited": every gold-priced item that still has stock, bought in vendor
-- order for as long as you can afford it.
function VP:ComputeBuyAll()
    local money = GetMoney()
    local totalAll, cost, items = 0, 0, 0
    local plan = {}
    for _, e in ipairs(self.limitedItems) do
        totalAll = totalAll + e.price * e.avail
        local units = e.avail
        if e.price > 0 then units = math.min(units, math.floor(money / e.price)) end
        if units > 0 then
            money = money - units * e.price
            cost = cost + units * e.price
            items = items + units * e.qty
            plan[#plan + 1] = { e = e, units = units }
        end
    end
    self.buyPlan = plan
    self.buyAllTotal, self.buyAllCost, self.buyAllItems = totalAll, cost, items
    self.buyAllFull = (cost == totalAll)
end

function VP:ExecuteBuyAll(plan)
    -- Highest index first: if a row sells out and disappears, rows still to buy keep their index.
    table.sort(plan, function(a, b) return a.e.index > b.e.index end)
    local delay = 0
    for _, step in ipairs(plan) do
        local e, units = step.e, step.units
        C_Timer.After(delay, function()
            if not MerchantFrame:IsShown() then return end
            if GetMerchantItemLink(e.index) ~= e.link then return end -- stock shifted; don't buy the wrong thing
            local maxStack = math.max(GetMerchantItemMaxStack(e.index) or e.qty, e.qty)
            local remaining = units * e.qty
            while remaining > 0 do
                local n = math.min(remaining, maxStack)
                BuyMerchantItem(e.index, n)
                remaining = remaining - n
            end
        end)
        delay = delay + 0.15
    end
end

StaticPopupDialogs["VENDORPLUS_BUYALL"] = {
    text = "Buy all limited-supply items?\n%s\n%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data)
        if data then VP:ExecuteBuyAll(data) end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function VP:ClickBuyAll()
    if not self.buyPlan or #self.buyPlan == 0 then return end
    local plan = {}
    for i, step in ipairs(self.buyPlan) do plan[i] = { e = step.e, units = step.units } end
    local summary = string.format("%d item%s", self.buyAllItems, self.buyAllItems == 1 and "" or "s")
    if not self.buyAllFull then summary = summary .. " (all you can afford)" end
    StaticPopup_Show("VENDORPLUS_BUYALL", summary, CoinString(self.buyAllCost), plan)
end

StaticPopupDialogs["VENDORPLUS_QTY"] = {
    text = "Buy how many %s?\n(max %s)",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 5,
    OnShow = function(self)
        local box = self.editBox or self.EditBox
        box:SetText("1")
        box:HighlightText()
        box:SetFocus()
    end,
    OnAccept = function(self, data)
        local box = self.editBox or self.EditBox
        local n = tonumber(box:GetText())
        if n and data then
            n = math.min(math.floor(n), data.max)
            VP:BuyQuantity(data.entry, n)
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local n = tonumber(self:GetText())
        local data = parent.data
        if n and data then
            n = math.min(math.floor(n), data.max)
            VP:BuyQuantity(data.entry, n)
        end
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

-- Shift-click: open VendorPlus's own quantity picker (see VP:ShowQty)
function VP:PromptQuantity(row)
    local e = row.entry
    if not e or e.mode ~= "merchant" then return end
    local maxN = MaxPurchasable(e)
    maxN = math.floor(maxN / e.qty) * e.qty -- whole purchase units only
    if maxN <= e.qty then
        self:BuyQuantity(e, e.qty)
        return
    end
    self:ShowQty(row, e, maxN)
end

--------------------------------------------------------------------------
-- UI construction
--------------------------------------------------------------------------
local function Flat(f, bg, border)
    f:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    f:SetBackdropColor(unpack(bg))
    f:SetBackdropBorderColor(unpack(border))
end

local function Box(parent, bg, border, frameType)
    local f = CreateFrame(frameType or "Frame", nil, parent, "BackdropTemplate")
    Flat(f, bg, border)
    return f
end

local function SkinUpdate(b)
    local enabled = b:IsEnabled()
    local lit = b.primary or b.selected
    local bg = lit and K.accentBg or K.card
    local border = lit and K.accent or K.border
    if enabled then
        if b.isDown then
            bg = lit and K.accentBg or K.input
        elseif b:IsMouseOver() then
            bg = lit and K.accentHi or K.cardHi
        end
    end
    b:SetBackdropColor(unpack(bg))
    b:SetBackdropBorderColor(unpack(border))
    b:SetAlpha(enabled and 1 or 0.4)
    b.text:SetTextColor(unpack((b.segmented and not b.selected) and K.dim or K.text))
end

-- kind: nil = plain card button, "primary" = accent button, "seg" = segmented-control button
local function MakeButton(parent, text, w, h, kind)
    local b = Box(parent, K.card, K.border, "Button")
    b:SetSize(w, h or 26)
    b.primary = (kind == "primary")
    b.segmented = (kind == "seg")

    b.text = b:CreateFontString(nil, "OVERLAY", "VendorPlusButton")
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetWordWrap(false)
    b.SetText = function(self, t) self.text:SetText(t or "") end
    b.GetText = function(self) return self.text:GetText() end
    b.SetText(b, text)

    b:SetScript("OnEnter", SkinUpdate)
    b:SetScript("OnLeave", function(self) self.isDown = false SkinUpdate(self) end)
    b:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self.isDown = true SkinUpdate(self) end end)
    b:SetScript("OnMouseUp", function(self) self.isDown = false SkinUpdate(self) end)
    b:SetScript("OnEnable", SkinUpdate)
    b:SetScript("OnDisable", SkinUpdate)

    -- keep the disabled look in sync however enabled-state is changed
    b.SetEnabled = function(self, enabled)
        if enabled then self:Enable() else self:Disable() end
        SkinUpdate(self)
    end
    b.SetSelected = function(self, on)
        self.selected = on and true or false
        SkinUpdate(self)
    end

    SkinUpdate(b)
    return b
end

-- Dark input box with an accent border while focused. Returns box, editbox.
local function MakeInput(parent, w, h)
    local box = Box(parent, K.input, K.border)
    box:SetSize(w, h)
    local eb = CreateFrame("EditBox", nil, box)
    eb:SetFontObject(fonts.VendorPlusText)
    eb:SetPoint("TOPLEFT", 8, -1)
    eb:SetPoint("BOTTOMRIGHT", -8, 1)
    eb:SetAutoFocus(false)
    eb:HookScript("OnEditFocusGained", function() box:SetBackdropBorderColor(unpack(K.accent)) end)
    eb:HookScript("OnEditFocusLost", function() box:SetBackdropBorderColor(unpack(K.border)) end)
    eb.box = box
    return box, eb
end

-- "x" close button, dim until hovered
local function CloseButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(34, 34)
    b.text = b:CreateFontString(nil, "OVERLAY", "VendorPlusTitle")
    b.text:SetPoint("CENTER", 0, 1)
    b.text:SetText("×")
    b.text:SetTextColor(unpack(K.dim))
    b:SetScript("OnEnter", function(self) self.text:SetTextColor(unpack(K.text)) end)
    b:SetScript("OnLeave", function(self) self.text:SetTextColor(unpack(K.dim)) end)
    b:SetScript("OnClick", onClick)
    return b
end

-- Text tab with an accent underline on the active one
local function TabButton(parent, label, w)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, 26)
    b.text = b:CreateFontString(nil, "OVERLAY", "VendorPlusButton")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b.text:SetTextColor(unpack(K.dim))
    b.underline = b:CreateTexture(nil, "OVERLAY")
    b.underline:SetColorTexture(unpack(K.accent))
    b.underline:SetHeight(2)
    b.underline:SetPoint("BOTTOMLEFT")
    b.underline:SetPoint("BOTTOMRIGHT")
    b.underline:Hide()
    b:SetScript("OnEnter", function(self) self.text:SetTextColor(unpack(K.text)) end)
    b:SetScript("OnLeave", function(self) self.text:SetTextColor(unpack(self.active and K.text or K.dim)) end)
    function b:SetActiveTab(on)
        self.active = on and true or false
        self.underline:SetShown(self.active)
        self.text:SetTextColor(unpack(self.active and K.text or K.dim))
    end
    return b
end

-- Sort arrow drawn from textures (font-independent), in the green Regional Edge uses
local function PixelArrow(parent)
    local a = CreateFrame("Frame", nil, parent)
    a:SetSize(9, 10)
    a.px = {}
    for i = 1, 6 do
        local t = a:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(unpack(K.green))
        a.px[i] = t
    end
    function a:SetDirection(up)
        local stem = self.px[1]
        stem:ClearAllPoints()
        stem:SetSize(3, 5)
        stem:SetPoint(up and "BOTTOM" or "TOP", self, up and "BOTTOM" or "TOP", 0, 0)
        for r = 1, 5 do
            local t = self.px[r + 1]
            t:ClearAllPoints()
            t:SetSize(2 * r - 1, 1)
            if up then
                t:SetPoint("TOP", self, "TOP", 0, -(r - 1))
            else
                t:SetPoint("BOTTOM", self, "BOTTOM", 0, r - 1)
            end
        end
    end
    a:SetDirection(false)
    a:Hide()
    return a
end

--------------------------------------------------------------------------
-- Quantity picker (skinned to match the main window)
--------------------------------------------------------------------------
local function QtyClamp(q, n)
    local e = q.entry
    n = tonumber(n) or e.qty
    n = math.floor(n / e.qty + 0.5) * e.qty
    return math.max(e.qty, math.min(n, q.max))
end

local function QtySet(q, n, rewriteText)
    q.qty = QtyClamp(q, n)
    if rewriteText and q.edit:GetText() ~= tostring(q.qty) then
        q.edit:SetText(tostring(q.qty))
    end
    q.total:SetText("Total: " .. TotalCostText(q.entry, q.qty))
    q.minus:SetEnabled(q.qty > q.entry.qty)
    q.plus:SetEnabled(q.qty < q.max)
end

local function QtyAccept(q)
    QtySet(q, q.edit:GetText(), true)
    local e = q.entry
    if GetMerchantItemLink(e.index) ~= e.link then
        print("|cff4fa3ffVendorPlus|r the vendor's stock changed - try again.")
    else
        VP:BuyQuantity(e, q.qty)
    end
    q:Hide()
end

function VP:CreateQtyFrame()
    local q = CreateFrame("Frame", "VendorPlusQtyFrame", UIParent, "BackdropTemplate")
    q:SetSize(240, 148)
    q:SetFrameStrata("DIALOG")
    q:SetClampedToScreen(true)
    q:EnableMouse(true)
    q:EnableMouseWheel(true)
    Flat(q, K.window, K.accent)
    q:Hide()
    tinsert(UISpecialFrames, "VendorPlusQtyFrame") -- Escape closes it

    q.title = q:CreateFontString(nil, "OVERLAY", "VendorPlusName")
    q.title:SetPoint("TOP", 0, -10)
    q.title:SetWidth(216)
    q.title:SetWordWrap(false)

    q.limit = q:CreateFontString(nil, "OVERLAY", "VendorPlusSmall")
    q.limit:SetPoint("TOP", q.title, "BOTTOM", 0, -3)

    q.minus = MakeButton(q, "-", 28, 28)
    q.minus:SetPoint("TOPLEFT", 16, -46)
    q.minus:SetScript("OnClick", function() QtySet(q, q.qty - q.entry.qty, true) end)

    local ebox, eb = MakeInput(q, 80, 28)
    ebox:SetPoint("LEFT", q.minus, "RIGHT", 8, 0)
    q.edit = eb
    q.edit:SetNumeric(true)
    q.edit:SetMaxLetters(5)
    q.edit:SetJustifyH("CENTER")
    q.edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput then QtySet(q, self:GetText(), false) end -- live total; don't rewrite while typing
    end)
    q.edit:SetScript("OnEditFocusLost", function(self) if q:IsShown() then QtySet(q, self:GetText(), true) end end)
    q.edit:SetScript("OnEnterPressed", function() QtyAccept(q) end)
    q.edit:SetScript("OnEscapePressed", function() q:Hide() end)

    q.plus = MakeButton(q, "+", 28, 28)
    q.plus:SetPoint("LEFT", ebox, "RIGHT", 8, 0)
    q.plus:SetScript("OnClick", function() QtySet(q, q.qty + q.entry.qty, true) end)

    q.maxBtn = MakeButton(q, "Max", 44, 28)
    q.maxBtn:SetPoint("LEFT", q.plus, "RIGHT", 8, 0)
    q.maxBtn:SetScript("OnClick", function() QtySet(q, q.max, true) end)

    q.total = q:CreateFontString(nil, "OVERLAY", "VendorPlusText")
    q.total:SetPoint("TOP", 0, -84)

    local buy = MakeButton(q, "Buy", 104, 28, "primary")
    buy:SetPoint("BOTTOMLEFT", 12, 10)
    buy:SetScript("OnClick", function() QtyAccept(q) end)

    local cancel = MakeButton(q, "Cancel", 104, 28)
    cancel:SetPoint("BOTTOMRIGHT", -12, 10)
    cancel:SetScript("OnClick", function() q:Hide() end)

    q:SetScript("OnMouseWheel", function(_, delta)
        QtySet(q, q.qty + delta * q.entry.qty, true)
    end)
    q:SetScript("OnHide", function() q.edit:ClearFocus() end)

    self.qtyFrame = q
    return q
end

function VP:ShowQty(row, e, maxN)
    local q = self.qtyFrame or self:CreateQtyFrame()
    q.entry, q.max = e, maxN
    q.title:SetText(ColorName(e.name, e.link))
    q.limit:SetText("Max " .. maxN)
    q:ClearAllPoints()
    q:SetPoint("BOTTOMLEFT", row, "TOPLEFT", 40, 2)
    q:Show()
    q.edit:SetText(tostring(e.qty))
    QtySet(q, e.qty, true)
    q.edit:SetFocus()
    q.edit:HighlightText()
end

-- Sparkly gold border for limited-stock ("N left") rows
local SPARKLE_SPOTS = {
    -- top edge
    { 18, 0 }, { 75, 0 }, { 133, 0 }, { 192, 0 }, { 250, 0 }, { 308, 0 }, { 366, 0 }, { 432, 0 },
    -- bottom edge
    { 46, -38 }, { 104, -38 }, { 162, -38 }, { 221, -38 }, { 279, -38 }, { 337, -38 }, { 395, -38 },
    -- sides
    { 3, -12 }, { 3, -27 }, { 453, -12 }, { 453, -27 },
}

function VP.AttachSparkle(row)
    -- pulsing gold edge
    local edge = CreateFrame("Frame", nil, row)
    edge:SetAllPoints(row)
    edge:SetFrameLevel(row:GetFrameLevel() + 2)
    local function Edge(p1, p2, horizontal)
        local t = edge:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(K.gold[1], K.gold[2], K.gold[3], 0.95)
        t:SetPoint(p1)
        t:SetPoint(p2)
        if horizontal then t:SetHeight(1) else t:SetWidth(1) end
    end
    Edge("TOPLEFT", "TOPRIGHT", true)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    Edge("TOPLEFT", "BOTTOMLEFT", false)
    Edge("TOPRIGHT", "BOTTOMRIGHT", false)

    local pulse = edge:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local pa = pulse:CreateAnimation("Alpha")
    pa:SetFromAlpha(1)
    pa:SetToAlpha(0.4)
    pa:SetDuration(0.9)
    pa:SetSmoothing("IN_OUT")

    -- twinkling stars along the border
    local stars = {}
    for i, spot in ipairs(SPARKLE_SPOTS) do
        local star = edge:CreateTexture(nil, "OVERLAY", nil, 2)
        star:SetTexture("Interface\\Cooldown\\star4")
        star:SetBlendMode("ADD")
        star:SetSize(14, 14)
        star:SetPoint("CENTER", row, "TOPLEFT", spot[1] * ROW_W / 456, spot[2])
        star:SetVertexColor(1, 0.95, 0.6)
        star:SetAlpha(0)

        local ag = star:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        local fadeIn = ag:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1); fadeIn:SetDuration(0.3); fadeIn:SetOrder(1)
        local fadeOut = ag:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0); fadeOut:SetDuration(0.4); fadeOut:SetOrder(2)
        local spin = ag:CreateAnimation("Rotation")
        spin:SetDegrees(90); spin:SetDuration(0.7); spin:SetOrder(1)
        local pause = ag:CreateAnimation("Alpha") -- staggers the stars so they twinkle out of sync
        pause:SetFromAlpha(0); pause:SetToAlpha(0); pause:SetDuration(0.3 + (i * 0.37) % 1.3); pause:SetOrder(3)
        stars[i] = ag
    end

    edge:Hide()
    row.sparkle = { frame = edge, pulse = pulse, stars = stars }
end

function VP.SetSparkle(row, on)
    local sp = row.sparkle
    if not sp then return end
    if on then
        if not sp.frame:IsShown() then
            sp.frame:Show()
            sp.pulse:Play()
            for _, ag in ipairs(sp.stars) do ag:Play() end
        end
    elseif sp.frame:IsShown() then
        sp.pulse:Stop()
        for _, ag in ipairs(sp.stars) do ag:Stop() end
        sp.frame:Hide()
    end
end

local function CreateRow(parent, i)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(ROW_W, ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, -TOP - (i - 1) * ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.SplitStack = function(self, split) VP:BuyQuantity(self.entry, split) end
    VP.AttachSparkle(row)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.035 or 0)

    -- lime bar on the left edge when the vendor price beats the region average
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetWidth(2)
    row.bar:SetPoint("TOPLEFT")
    row.bar:SetPoint("BOTTOMLEFT")
    row.bar:Hide()

    row:SetHighlightTexture(FLAT)
    row:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.05)

    -- icon in a thin box, border coloured by item quality
    row.iconBox = Box(row, { 0, 0, 0, 1 }, K.border)
    row.iconBox:SetSize(32, 32)
    row.iconBox:SetPoint("LEFT", 10, 0)
    row.icon = row.iconBox:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("TOPLEFT", 1, -1)
    row.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.count = row.iconBox:CreateFontString(nil, "OVERLAY", "VendorPlusCount")
    row.count:SetPoint("BOTTOMRIGHT", row.iconBox, "BOTTOMRIGHT", -2, 2)

    row.name = row:CreateFontString(nil, "OVERLAY", "VendorPlusName")
    row.name:SetPoint("TOPLEFT", row.iconBox, "TOPRIGHT", 8, -2)
    row.name:SetWidth(NAME_W)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.cost = row:CreateFontString(nil, "OVERLAY", "VendorPlusSmall")
    row.cost:SetPoint("BOTTOMLEFT", row.iconBox, "BOTTOMRIGHT", 8, 2)
    row.cost:SetWidth(NAME_W)
    row.cost:SetJustifyH("LEFT")
    row.cost:SetWordWrap(false)

    -- right-hand columns, anchored right to left
    row.sold = row:CreateFontString(nil, "OVERLAY", "VendorPlusText")
    row.sold:SetWidth(COL.sold)
    row.sold:SetJustifyH("RIGHT")
    row.sold:SetPoint("RIGHT", row, "RIGHT", -COL_PAD, 0)

    row.avg = row:CreateFontString(nil, "OVERLAY", "VendorPlusText")
    row.avg:SetWidth(COL.avg)
    row.avg:SetJustifyH("RIGHT")
    row.avg:SetPoint("RIGHT", row.sold, "LEFT", -COL_GAP, 0)

    row.buyout = row:CreateFontString(nil, "OVERLAY", "VendorPlusText")
    row.buyout:SetWidth(COL.buyout)
    row.buyout:SetJustifyH("RIGHT")
    row.buyout:SetPoint("RIGHT", row.avg, "LEFT", -COL_GAP, 0)

    row:SetScript("OnEnter", function(self)
        local e = self.entry
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if e.mode == "buyback" then
            GameTooltip:SetBuybackItem(e.index)
        else
            GameTooltip:SetMerchantItem(e.index)
        end
        GameTooltip:AddLine(" ")
        if e.mode == "buyback" then
            GameTooltip:AddLine("Click: buy back", 0.6, 0.8, 1)
        else
            GameTooltip:AddLine("Click: buy  |  Shift-click: choose quantity", 0.6, 0.8, 1)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row:SetScript("OnClick", function(self)
        local e = self.entry
        if not e then return end
        if e.link and HandleModifiedItemClick and HandleModifiedItemClick(e.link) then
            return -- chat link / dressing room handled it
        end
        if IsShiftKeyDown() and e.mode == "merchant" then
            VP:PromptQuantity(self)
        else
            VP:BuyQuantity(e, e.qty)
        end
    end)

    return row
end

function VP:ClickHeader(key)
    local firstDesc = not (key == "name" or key == "price") -- text/price sort ascending first, data columns descending
    if DB.sort ~= key then
        DB.sort, DB.sortDesc = key, firstDesc
    elseif DB.sortDesc == firstDesc then
        DB.sortDesc = not firstDesc
    else
        DB.sort = "default"
    end
    self:Refresh()
end

function VP:CreateUI()
    local f = CreateFrame("Frame", "VendorPlusFrame", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W, FRAME_H)
    f:SetFrameStrata("HIGH")
    Flat(f, K.window, K.border)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:Hide()
    self.frame = f

    -- Draggable: grab any empty part of the window (title area, gaps, footer)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        DB.pos = { left = self:GetLeft(), top = self:GetTop() }
    end)

    -- Title bar
    local title = f:CreateFontString(nil, "OVERLAY", "VendorPlusTitle")
    title:SetPoint("TOPLEFT", PAD, -8)
    title:SetPoint("TOPRIGHT", -40, -8)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    f.title = title

    local close = CloseButton(f, function() CloseMerchant() end)
    close:SetPoint("TOPRIGHT", -2, -1)

    local tline = f:CreateTexture(nil, "ARTWORK")
    tline:SetColorTexture(unpack(K.border))
    tline:SetHeight(1)
    tline:SetPoint("TOPLEFT", 1, -37)
    tline:SetPoint("TOPRIGHT", -1, -37)

    -- Stat card (item count on the left, search on the right)
    local card = Box(f, K.card, K.border)
    card:SetPoint("TOPLEFT", PAD, -50)
    card:SetPoint("TOPRIGHT", -PAD, -50)
    card:SetHeight(70)
    card.label = card:CreateFontString(nil, "OVERLAY", "VendorPlusLabel")
    card.label:SetPoint("TOPLEFT", 12, -10)
    card.label:SetText("ITEMS FOR SALE")
    card.value = card:CreateFontString(nil, "OVERLAY", "VendorPlusValue")
    card.value:SetPoint("TOPLEFT", 12, -24)
    card.sub = card:CreateFontString(nil, "OVERLAY", "VendorPlusSmall")
    card.sub:SetPoint("TOPLEFT", 12, -51)
    card.sub:SetWidth(260)
    card.sub:SetJustifyH("LEFT")
    card.sub:SetWordWrap(false)
    self.stat = card

    local sbox, search = MakeInput(card, 190, 28)
    sbox:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -14, 14)
    search:SetScript("OnTextChanged", function(self)
        VP.search = self:GetText()
        VP:Refresh()
    end)
    search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    self.searchBox = search
    local sl = card:CreateFontString(nil, "OVERLAY", "VendorPlusLabel")
    sl:SetPoint("BOTTOMLEFT", sbox, "TOPLEFT", 0, 8)
    sl:SetText("SEARCH")

    -- Tabs
    self.tabMerchant = TabButton(f, "Merchant", 96)
    self.tabMerchant:SetPoint("TOPLEFT", PAD, -130)
    self.tabMerchant:SetScript("OnClick", function() VP:SetMode("merchant") end)

    self.tabBuyback = TabButton(f, "Buyback", 90)
    self.tabBuyback:SetPoint("LEFT", self.tabMerchant, "RIGHT", 0, 0)
    self.tabBuyback:SetScript("OnClick", function() VP:SetMode("buyback") end)

    local tabLine = f:CreateTexture(nil, "ARTWORK")
    tabLine:SetColorTexture(unpack(K.border))
    tabLine:SetHeight(1)
    tabLine:SetPoint("TOPLEFT", PAD, -156)
    tabLine:SetPoint("TOPRIGHT", -PAD, -156)

    -- Column headers (click to sort; click again to reverse; third click = vendor order)
    local hdr = CreateFrame("Frame", nil, f)
    hdr:SetPoint("TOPLEFT", PAD, -164)
    hdr:SetSize(ROW_W, 20)

    self.headers = {}
    local function Header(key, text, leftAligned, anchorTo, x, w)
        local btn = CreateFrame("Button", nil, hdr)
        btn:SetSize(w, 20)
        if leftAligned then
            btn:SetPoint("LEFT", hdr, "LEFT", x, 0)
        else
            btn:SetPoint("RIGHT", anchorTo, anchorTo == hdr and "RIGHT" or "LEFT", x, 0)
        end
        local fs = btn:CreateFontString(nil, "OVERLAY", "VendorPlusHeader")
        fs:SetAllPoints()
        fs:SetJustifyH(leftAligned and "LEFT" or "RIGHT")
        btn.label, btn.baseText, btn.leftAligned = fs, string.upper(text), leftAligned
        btn.arrow = PixelArrow(btn)
        fs:SetText(btn.baseText)
        btn:SetScript("OnEnter", function() fs:SetTextColor(unpack(K.text)) end)
        btn:SetScript("OnLeave", function()
            fs:SetTextColor(unpack(DB.sort == key and K.text or K.dim))
        end)
        btn:SetScript("OnClick", function() VP:ClickHeader(key) end)
        self.headers[key] = btn
        return btn
    end
    Header("name",  "Item", true, nil, 50, 60)
    Header("price", "Cost", true, nil, 114, 60)
    local hSold   = Header("sold",   "Sold/Day",   false, hdr,    -COL_PAD, COL.sold)
    local hAvg    = Header("avg",    "Region Avg", false, hSold,  -COL_GAP, COL.avg)
    Header("buyout", "Min Buyout", false, hAvg, -COL_GAP, COL.buyout)

    local hline = f:CreateTexture(nil, "ARTWORK")
    hline:SetColorTexture(unpack(K.border))
    hline:SetHeight(1)
    hline:SetPoint("TOPLEFT", PAD, -(TOP - 2))
    hline:SetPoint("TOPRIGHT", -PAD, -(TOP - 2))

    -- Slim scrollbar (drives the row offset)
    local sb = CreateFrame("Slider", nil, f)
    sb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -TOP)
    sb:SetSize(6, ROWS * ROW_H)
    sb:SetOrientation("VERTICAL")
    sb:SetMinMaxValues(0, 0)
    sb:SetValueStep(1)
    sb:SetObeyStepOnDrag(true)
    local sbBg = sb:CreateTexture(nil, "BACKGROUND")
    sbBg:SetAllPoints()
    sbBg:SetColorTexture(1, 1, 1, 0.04)
    sb:SetThumbTexture(FLAT)
    local th = sb:GetThumbTexture()
    th:SetSize(6, 30)
    th:SetVertexColor(0.40, 0.45, 0.54, 1)
    sb:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v + 0.5)
        if v ~= VP.offset then
            VP.offset = v
            VP:Render()
        end
    end)
    sb:Hide()
    self.sb = sb

    f:SetScript("OnMouseWheel", function(_, delta)
        sb:SetValue(sb:GetValue() - delta * 2)
    end)

    for i = 1, ROWS do
        self.rows[i] = CreateRow(f, i)
    end

    -- Footer
    self.money = f:CreateFontString(nil, "OVERLAY", "VendorPlusText")
    self.money:SetPoint("BOTTOMLEFT", PAD, 22)

    self.buyAll = MakeButton(f, "", 196, 30, "primary")
    self.buyAll:SetPoint("LEFT", self.money, "RIGHT", 12, 0)
    self.buyAll:SetScript("OnClick", function() VP:ClickBuyAll() end)
    self.buyAll:HookScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:AddLine("Buy all limited-supply items", 1, 0.82, 0)
        GameTooltip:AddLine(string.format("%d limited item type%s with stock left",
            #VP.limitedItems, #VP.limitedItems == 1 and "" or "s"), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(" ")
        for _, step in ipairs(VP.buyPlan or {}) do
            local qty = step.units * step.e.qty
            GameTooltip:AddDoubleLine(
                string.format("%s x%d", ColorName(step.e.name, step.e.link), qty),
                CoinString(step.e.price * step.units), 1, 1, 1, 1, 1, 1)
        end
        if not VP.buyAllFull then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Not enough gold for everything - buys what you can afford.", 1, 0.4, 0.4, true)
            GameTooltip:AddDoubleLine("Full cost", CoinString(VP.buyAllTotal), 0.8, 0.8, 0.8, 1, 1, 1)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Items bought with currency or other items are not included.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    self.buyAll:HookScript("OnLeave", function() GameTooltip:Hide() end)

    self.junk = MakeButton(f, "Sell Junk", 76, 30)
    self.junk:SetPoint("BOTTOMRIGHT", -PAD, 14)
    self.junk:SetScript("OnClick", function()
        if C_MerchantFrame and C_MerchantFrame.SellAllJunkItems then
            C_MerchantFrame.SellAllJunkItems()
        end
    end)

    self.repair = MakeButton(f, "Repair", 124, 30)
    self.repair:SetPoint("RIGHT", self.junk, "LEFT", -6, 0)
    self.repair:SetScript("OnClick", function() RepairAllItems() end)

    self.noTSM = f:CreateFontString(nil, "OVERLAY", "VendorPlusSmall")
    self.noTSM:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 52)
    self.noTSM:SetTextColor(unpack(K.red))
    self.noTSM:SetText("TradeSkillMaster not detected - no price data available")
    self.noTSM:Hide()
end

--------------------------------------------------------------------------
-- Show / hide / mode
--------------------------------------------------------------------------
function VP:SetMode(mode)
    self.mode = mode
    self.offset = 0
    self:Refresh()
end

function VP:CreateBar()
    local bar = CreateFrame("Frame", "VendorPlusBar", UIParent)
    bar:SetSize(228, 24)
    bar:SetFrameStrata("HIGH")
    bar:SetClampedToScreen(true)
    bar:Hide()
    bar.buttons = {}
    local prev
    for _, d in ipairs({
        { "default", "Default UI", 80 },
        { "vp",      "Vendor Plus", 90 },
        { "tsm",     "TSM", 60 },
    }) do
        local b = MakeButton(bar, d[2], d[3], 24, "seg")
        if prev then b:SetPoint("LEFT", prev, "RIGHT", -1, 0) else b:SetPoint("LEFT", bar, "LEFT", 0, 0) end
        b:SetScript("OnClick", function() if VP.effectiveView ~= d[1] then VP:SetView(d[1]) end end)
        bar.buttons[d[1]] = b
        prev = b
    end
    self.bar = bar

    -- If the user closes TSM's window with TSM's own "WOW UI" button, fall back to the default UI.
    -- Needs two consecutive checks so a vendor closing (which also hides TSM's window) isn't mistaken for it.
    local acc, misses = 0, 0
    bar:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.2 then return end
        acc = 0
        local w = VP.tsmWin
        if VP.effectiveView == "tsm" and w and not VP.applying and MerchantFrame:IsShown() and not w:IsVisible() then
            misses = misses + 1
            if misses >= 2 then
                misses = 0
                VP.tsmWin = nil
                VP:SetView("default")
            end
        else
            misses = 0
        end
    end)

    -- Invisible click-blocker over the (hidden) Blizzard merchant frame while TSM's window is up.
    -- MEDIUM strata keeps it underneath TSM's HIGH-strata window.
    local blk = CreateFrame("Frame", nil, UIParent)
    blk:SetFrameStrata("MEDIUM")
    blk:EnableMouse(true)
    blk:Hide()
    self.blocker = blk
end

--------------------------------------------------------------------------
-- TSM integration: TSM's vendor window is opened with the "TSM4" button TSM
-- adds to the merchant frame, and closed with the "WOW UI" button in its own
-- header. We find those buttons by their text and click them.
--------------------------------------------------------------------------
local function TextOf(obj)
    local ok, t = pcall(function() return obj:GetText() end)
    if ok and type(t) == "string" then return t end
end

-- Returns the frame that owns a label (a Button's own text, or a FontString
-- region) matching `text`, searching children up to `depth` levels deep.
local function FindByText(root, text, depth)
    if not root or depth < 0 then return end
    text = string.lower(text)

    local own = TextOf(root)
    if own and string.lower(own) == text then return root end

    local ok, regions = pcall(function() return { root:GetRegions() } end)
    if ok then
        for _, r in ipairs(regions) do
            local rt = TextOf(r)
            if rt and string.lower(rt) == text then return root end
        end
    end

    local ok2, kids = pcall(function() return { root:GetChildren() } end)
    if ok2 then
        for _, k in ipairs(kids) do
            local found = FindByText(k, text, depth - 1)
            if found then return found end
        end
    end
end

local function ClickFrame(f)
    if not f then return end
    if f.Click then
        f:Click()
        return
    end
    for _, script in ipairs({ "OnClick", "OnMouseUp" }) do
        local fn = f:GetScript(script)
        if fn then fn(f, "LeftButton") return end
    end
end

-- TSM's vendor window: a visible TSM_FRAME:LargeApplicationFrame containing a
-- "WOW UI" button (the main /tsm window doesn't have one).
function VP:FindTSMWindow()
    local f = EnumerateFrames()
    while f do
        local win, btn
        pcall(function()
            local n = f:GetName()
            if type(n) == "string"
               and string.find(n, "TSM_FRAME", 1, true)
               and string.find(n, "LargeApplicationFrame", 1, true)
               and f:IsVisible() then
                btn = FindByText(f, "WOW UI", 6)
                if btn then win = f end
            end
        end)
        if win then return win, btn end
        f = EnumerateFrames(f)
    end
end

function VP:FindTSMButton()
    return FindByText(MerchantFrame, "TSM4", 4)
end

function VP:PositionBar()
    local bar = self.bar
    local view = self.effectiveView
    bar:ClearAllPoints()
    if view == "vp" then
        bar:SetPoint("BOTTOMLEFT", self.frame, "TOPLEFT", 0, 2)
    else
        bar:SetPoint("BOTTOMLEFT", MerchantFrame, "TOPLEFT", 0, 2) -- same spot for Default and TSM
    end
    bar:Show()
    local hasTSM = TSMAvailable() and true or false
    bar.buttons.tsm:SetShown(hasTSM) -- no TSM, no TSM button
    bar:SetWidth(hasTSM and 228 or 169)
    for key, btn in pairs(bar.buttons) do btn:SetSelected(key == view) end
end

-- Hides/shows the Blizzard merchant frame. While hidden for TSM, an invisible
-- blocker stops clicks reaching its (invisible) item buttons.
function VP:SetDefaultHidden(hidden, block)
    MerchantFrame:SetAlpha(hidden and 0 or 1)
    if hidden and block then
        self.blocker:SetAllPoints(MerchantFrame)
        self.blocker:SetFrameLevel(MerchantFrame:GetFrameLevel() + 60)
        self.blocker:Show()
    else
        self.blocker:Hide()
    end
end

function VP:DoApplyView()
    local view = DB.view or "vp"
    -- Saved view is TSM but TSM isn't loaded: quietly use the default UI (the saved choice is kept)
    if view == "tsm" and not TSMAvailable() then view = "default" end
    local tsmWin, wowUI = self:FindTSMWindow()
    if view == "tsm" and tsmWin then self.tsmWin = tsmWin end

    if view == "tsm" then
        self.frame:Hide()
        StaticPopup_Hide("VENDORPLUS_CONFIRM")
        StaticPopup_Hide("VENDORPLUS_QTY")
        if not tsmWin then
            local btn = self:FindTSMButton()
            if btn then
                self:SetDefaultHidden(false)
                ClickFrame(btn)
                tsmWin = self:FindTSMWindow()
                self.tsmWin = tsmWin
            else
                view = "default"
                if not self.warnedTSM then
                    self.warnedTSM = true
                    print("|cff4fa3ffVendorPlus|r couldn't find TSM's \"TSM4\" button on the merchant frame (is TSM enabled?). Run /vp tsmscan for details.")
                end
            end
        end
        if view == "tsm" then
            self:SetDefaultHidden(tsmWin ~= nil, true) -- if TSM's window isn't up yet, the timer in ApplyView retries
        else
            self:SetDefaultHidden(false)
        end
    else
        if tsmWin and wowUI then ClickFrame(wowUI) end -- close TSM's window first
        if view == "vp" then
            self:SetDefaultHidden(true, false) -- our frame covers it, no blocker needed
            self.frame:Show()
            self:Refresh()
        else
            self.frame:Hide()
            StaticPopup_Hide("VENDORPLUS_CONFIRM")
            StaticPopup_Hide("VENDORPLUS_QTY")
            self:SetDefaultHidden(false)
        end
    end

    self.effectiveView = view
    self:PositionBar()
end

function VP:ApplyView()
    if self.applying then return end -- TSM's buttons can re-trigger our hooks
    if self.qtyFrame then self.qtyFrame:Hide() end
    StaticPopup_Hide("VENDORPLUS_BUYALL")
    self.applying = true
    local ok, err = pcall(self.DoApplyView, self)
    self.applying = false
    if not ok then error(err, 0) end
    if self.effectiveView == "tsm" then
        C_Timer.After(0.2, function()
            if MerchantFrame:IsShown() and VP.effectiveView == "tsm" then
                local w = VP:FindTSMWindow()
                if w then
                    VP.tsmWin = w
                    VP:SetDefaultHidden(true, true)
                end
            end
        end)
    end
end

function VP:SetView(view)
    DB.view = view
    if MerchantFrame:IsShown() then self:ApplyView() end
end

function VP:PlaceFrame()
    self.frame:ClearAllPoints()
    if DB.pos then
        self.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", DB.pos.left, DB.pos.top)
    else
        self.frame:SetPoint("TOPLEFT", MerchantFrame, "TOPLEFT", 0, 0)
    end
end

function VP:Open()
    if not DB.enabled then
        MerchantFrame:SetAlpha(1)
        self.frame:Hide()
        self.bar:Hide()
        self.blocker:Hide()
        return
    end
    self:PlaceFrame()
    self.frame.title:SetText(UnitName("npc") or MERCHANT)
    self.mode = "merchant"
    self:ApplyView()
    -- TSM can open its own window a moment after the merchant opens; re-check once.
    C_Timer.After(0.3, function()
        if MerchantFrame:IsShown() and DB.enabled then VP:ApplyView() end
    end)
end

function VP:Close()
    if self.frame then self.frame:Hide() end
    if self.bar then self.bar:Hide() end
    StaticPopup_Hide("VENDORPLUS_CONFIRM")
    StaticPopup_Hide("VENDORPLUS_QTY")
    if self.qtyFrame then self.qtyFrame:Hide() end
    StaticPopup_Hide("VENDORPLUS_BUYALL")
    if MerchantFrame then MerchantFrame:SetAlpha(1) end
    if self.blocker then self.blocker:Hide() end
end

--------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------
SLASH_VENDORPLUS1 = "/vp"
SLASH_VENDORPLUS2 = "/vendorplus"
SlashCmdList.VENDORPLUS = function(msg)
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "toggle" then
        DB.enabled = not DB.enabled
        print("|cff4fa3ffVendorPlus|r " .. (DB.enabled and "enabled" or "disabled") .. " (reopen the vendor)")
    elseif cmd == "divisor" and tonumber(arg) and tonumber(arg) > 0 then
        DB.soldDivisor = tonumber(arg)
        print("|cff4fa3ffVendorPlus|r Sold/Day divisor set to " .. DB.soldDivisor)
        VP:Refresh()
    elseif cmd == "view" and (arg == "default" or arg == "vp" or arg == "tsm") then
        VP:SetView(arg)
    elseif cmd == "font" then
        if arg == "" or arg:lower() == "reset" then
            DB.font = nil
            VP:ApplyFonts(nil)
            print("|cff4fa3ffVendorPlus|r font reset to default")
        elseif VP:ApplyFonts(arg) then
            DB.font = arg
            print("|cff4fa3ffVendorPlus|r font set to " .. arg)
        else
            DB.font = nil
            print("|cff4fa3ffVendorPlus|r couldn't load that font; using the default. Use the full path, e.g. Interface\\AddOns\\MyAddon\\Font.ttf")
        end
        VP:Refresh()
    elseif cmd == "reset" then
        DB.pos = nil
        if VP.frame then VP:PlaceFrame() end
        print("|cff4fa3ffVendorPlus|r window position reset")
    elseif cmd == "tsmscan" then
        local win, wow = VP:FindTSMWindow()
        local btn = VP:FindTSMButton()
        print("|cff4fa3ffVendorPlus|r TSM4 button on merchant frame: " .. (btn and "|cff4de07afound|r" or "|cffff5c5cnot found|r"))
        print("|cff4fa3ffVendorPlus|r TSM vendor window open: " .. (win and ("|cff4de07ayes|r (" .. tostring(win:GetName()) .. ")") or "no")
              .. ", WOW UI button: " .. (wow and "|cff4de07afound|r" or "not found"))
    elseif cmd == "confirm" and tonumber(arg) then
        DB.confirmGold = tonumber(arg)
        print("|cff4fa3ffVendorPlus|r confirming purchases over " .. DB.confirmGold .. "g")
    else
        print("|cff4fa3ffVendorPlus|r commands:")
        print("  /vp toggle           - enable/disable the overhaul")
        print("  /vp divisor <n>      - divide TSM sold-per-day by n (default 1)")
        print("  /vp confirm <gold>   - confirm purchases above this gold amount")
        print("  /vp view <default|vp|tsm> - switch vendor window")
        print("  /vp reset            - reset the window position")
        print("  /vp font <path>      - use a custom .ttf (/vp font reset to undo)")
        print("  /vp tsmscan          - check whether TSM's vendor window/buttons are detected")
    end
end

--------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        VendorPlusDB = VendorPlusDB or {}
        DB = VendorPlusDB
        for k, v in pairs(DEFAULTS) do
            if DB[k] == nil then DB[k] = v end
        end

        if DB.sort == "rate" then DB.sort = "default" end
        DB.npcSparkle, DB.limitedNPCs = nil, nil -- removed feature: drop its saved data
        VP:ApplyFonts(DB.font)
        VP:CreateUI()
        VP:CreateBar()

        MerchantFrame:HookScript("OnShow", function() VP:Open() end)
        MerchantFrame:HookScript("OnHide", function() VP:Close() end)

        for _, e in ipairs({
            "MERCHANT_UPDATE", "MERCHANT_FILTER_ITEM_UPDATE", "PLAYER_MONEY",
            "UPDATE_INVENTORY_DURABILITY", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED",
        }) do
            self:RegisterEvent(e)
        end
    else
        if VP.frame and VP.frame:IsShown() then VP:RefreshSoon() end
    end
end)
