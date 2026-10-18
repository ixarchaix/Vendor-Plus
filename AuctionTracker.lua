local ADDON_NAME, AT = ...

------------------------------------------------------------
-- Constants
------------------------------------------------------------
-- Enum.AuctionHouseTimeLeftBand: 0 Short, 1 Medium, 2 Long, 3 VeryLong
-- Used only when the API doesn't give an exact timeLeftSeconds.
local BAND_MIN = { [0] = 0,    [1] = 1800, [2] = 7200,  [3] = 43200 }
local BAND_MAX = { [0] = 1800, [1] = 7200, [2] = 43200, [3] = 172800 }

local PREFIX = "|cff33ccffAuction Tracker:|r "
local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:0|t"

------------------------------------------------------------
-- Helpers
------------------------------------------------------------
local function RealmKey()
    return GetNormalizedRealmName() or GetRealmName():gsub("%s", "")
end

local function CharKey()
    return UnitName("player") .. "-" .. RealmKey()
end

-- Formats seconds as "1d 3h 42m", rounding UP to the next whole minute
local function FormatDuration(sec)
    sec = math.max(0, math.ceil(sec / 60) * 60)
    local d = math.floor(sec / 86400)
    local h = math.floor((sec % 86400) / 3600)
    local m = math.floor((sec % 3600) / 60)
    if d > 0 then
        return string.format("%dd %dh %dm", d, h, m)
    elseif h > 0 then
        return string.format("%dh %dm", h, m)
    else
        return string.format("%dm", m)
    end
end

local function FormatGold(copper)
    copper = copper or 0
    if copper >= 10000 then
        return BreakUpLargeNumbers(math.floor(copper / 10000)) .. GOLD_ICON
    end
    return C_CurrencyInfo.GetCoinTextureString(copper)
end

local function ClassColored(text, classFile)
    local c = classFile and RAID_CLASS_COLORS[classFile]
    if c then
        return string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, text)
    end
    return text
end

local function SortedCharKeys()
    local keys = {}
    for k in pairs(AuctionTrackerDB.chars) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

-- Counts for one character's saved auctions.
--   live    : definitely still running
--   unsure  : only a time band is known and the expiry window includes "now"
--   sold    : sold, proceeds waiting in the mail
--   expired : definitely past expiry
--   soonest : earliest possible expiry timestamp among live/unsure auctions
local function Stats(c, now)
    local live, unsure, sold, expired, soonest = 0, 0, 0, 0, nil
    for _, a in ipairs(c.auctions or {}) do
        if a.sold then
            sold = sold + 1
        elseif a.maxExp <= now then
            expired = expired + 1
        else
            if a.minExp <= now then unsure = unsure + 1 else live = live + 1 end
            local e = math.max(a.minExp, now)
            if not soonest or e < soonest then soonest = e end
        end
    end
    return live, unsure, sold, expired, soonest
end

local MAIL_LIFETIME = 30 * 86400   -- how long the game keeps a mail

-- Stats() adjusted for the last mailbox scan (see ScanMailbox):
--   sold    : sale mails waiting in the mailbox (or auctions the list flags as sold)
--   a sale mail that arrived after the last Auction House scan belongs to an auction
--   the list still counts as expired/live, so take it out of those counts
local function Counts(c, now)
    local live, unsure, sold, expired, soonest = Stats(c, now)
    local m = c.mail

    -- Estimated sales are only good for as long as a sale mail would last
    local inf = c.soldInf or 0
    if inf > 0 and (now - (c.soldInfAt or 0)) > MAIL_LIFETIME then inf = 0 end

    if not m then return live, unsure, math.max(sold, inf), expired, soonest end

    local lastScan = c.lastScan or 0
    local pend = 0
    for _, t in ipairs(m.arrivals or {}) do
        if t > lastScan + 60 then pend = pend + 1 end
    end
    pend = math.max(0, pend - sold)      -- auctions the list already flags as sold are accounted for

    local take = math.min(pend, expired)
    expired, pend = expired - take, pend - take
    take = math.min(pend, unsure)
    unsure, pend = unsure - take, pend - take
    live = math.max(0, live - pend)

    -- Sale mails still waiting (ones past their 30 days are gone)
    local waiting = 0
    for _, t in ipairs(m.arrivals or {}) do
        if t + MAIL_LIFETIME > now then waiting = waiting + 1 end
    end
    sold = math.max(sold, waiting + inf)
    return live, unsure, sold, expired, soonest
end

local function LiveText(live, unsure)
    local t = live .. " live"
    if unsure > 0 then t = t .. " (+" .. unsure .. " unsure)" end
    return t
end

------------------------------------------------------------
-- Scanning (only possible while the Auction House is open)
------------------------------------------------------------
local function ScanOwned()
    -- Your auctions are only sent while the Auction House is open. The update event can
    -- also fire at other times (e.g. on login) with an empty list, and that must never
    -- overwrite the auctions we saved earlier.
    if not AT.ahOpen then return end

    local owned = C_AuctionHouse.GetOwnedAuctions()
    if not owned then return end

    -- An empty list is only believable once the full list has actually arrived
    local hasFull = C_AuctionHouse.HasFullOwnedAuctionResults
    if #owned == 0 and hasFull and not hasFull() then return end

    local key = CharKey()
    local db = AuctionTrackerDB
    local char = db.chars[key] or {}
    db.chars[key] = char

    -- Index previous scan so estimated ranges can be narrowed over time
    local prev = {}
    for _, a in ipairs(char.auctions or {}) do prev[a.id] = a end

    local now = GetServerTime()
    local list = {}

    for _, a in ipairs(owned) do
        local entry = {
            id   = a.auctionID,
            sold = (a.status == (Enum.AuctionStatus and Enum.AuctionStatus.Sold or 1)),
        }

        if a.timeLeftSeconds then
            entry.exact  = true
            entry.minExp = now + a.timeLeftSeconds
            entry.maxExp = entry.minExp
        else
            -- Only a time band is available: store a range, and intersect it
            -- with the range from earlier scans of the same auction.
            local band = a.timeLeft or 3
            local lo = now + (BAND_MIN[band] or 0)
            local hi = now + (BAND_MAX[band] or 172800)
            local p = prev[a.auctionID]
            if p and not p.exact then
                lo = math.max(lo, p.minExp)
                hi = math.min(hi, p.maxExp)
                if lo > hi then lo = hi end
            end
            entry.exact  = false
            entry.minExp = lo
            entry.maxExp = hi
        end

        list[#list + 1] = entry
    end

    -- Keep just-posted auctions the server list doesn't include yet (avoids the count flickering down)
    local seen = {}
    for _, e in ipairs(list) do seen[e.id] = true end
    for _, p in ipairs(char.auctions or {}) do
        if p.pending and p.id and not seen[p.id] and (now - (p.created or 0)) < 20 then
            list[#list + 1] = p
        end
    end

    -- Auctions that left the list before their earliest possible expiry can't have expired.
    -- Cancellations were already removed by the cancel event, so these were sales.
    -- (Only trusted when the game says it sent the complete list.)
    local hasFullList = C_AuctionHouse.HasFullOwnedAuctionResults
    if hasFullList and hasFullList() and char.lastScan then
        local inList = {}
        for _, e in ipairs(list) do inList[e.id] = true end
        local gone = 0
        for _, a in ipairs(char.auctions or {}) do
            if not a.sold and type(a.id) == "number" and not inList[a.id] and a.minExp > now then
                gone = gone + 1
            end
        end
        if gone > 0 then
            -- Sale mails that arrived since the previous scan and are still waiting already
            -- count towards the Sold column, so only add the sales they don't explain.
            local explained = 0
            for _, t in ipairs(char.mail and char.mail.arrivals or {}) do
                if t > char.lastScan - 60 then explained = explained + 1 end
            end
            local extra = math.max(0, gone - explained)
            if extra > 0 then
                char.soldInf = (char.soldInf or 0) + extra
                char.soldInfAt = now
            end
        end
    end

    char.auctions = list
    char.lastScan = now
    char.name     = UnitName("player")
    char.realm    = GetRealmName()
    char.class    = select(2, UnitClass("player"))

    AT:Refresh()
end

local scanQueued = false
local function QueueScan()
    if scanQueued then return end
    scanQueued = true
    C_Timer.After(0.2, function()
        scanQueued = false
        ScanOwned()
    end)
end

local function RequestOwned()
    C_AuctionHouse.QueryOwnedAuctions({
        { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false },
    })
end

-- Keep our footprint on the Auction House small so we never compete with other
-- addons (e.g. TSM mass-posting). The on-screen count updates instantly from the
-- post/cancel events themselves (see below); this timer only reconciles with the
-- real list at most once every 5 seconds, and skips the query if anyone else
-- (Blizzard's UI, TSM) already refreshed the owned-auction list in the meantime.
local lastOwnedUpdate = 0
local ScheduleOwnedRefresh
ScheduleOwnedRefresh = function()
    if AT.refreshTimer then return end   -- already scheduled: don't push it back
    local stamp = GetTime()
    AT.refreshTimer = C_Timer.NewTimer(5, function()
        AT.refreshTimer = nil
        if not AT.ahOpen then return end
        if lastOwnedUpdate >= stamp then return end   -- someone else already refreshed
        local ready = C_AuctionHouse.IsThrottledMessageSystemReady
        if ready and not ready() then
            ScheduleOwnedRefresh()                    -- AH is busy: try again later
            return
        end
        RequestOwned()
    end)
end

------------------------------------------------------------
-- Instant updates while posting / cancelling
------------------------------------------------------------
local DURATION_SECONDS = { [1] = 12 * 3600, [2] = 24 * 3600, [3] = 48 * 3600 }
local postQueue = {}   -- durations of posts we saw being sent, oldest first

local function CurrentChar()
    local db = AuctionTrackerDB
    local key = CharKey()
    local c = db.chars[key]
    if not c then
        c = {
            name = UnitName("player"), realm = GetRealmName(),
            class = select(2, UnitClass("player")), auctions = {},
        }
        db.chars[key] = c
    end
    c.auctions = c.auctions or {}
    return c
end

-- Called (post-hook) whenever anything posts an auction: remembers the chosen duration
local function NotePost(_, duration)
    postQueue[#postQueue + 1] = { secs = DURATION_SECONDS[duration], t = GetTime() }
end

local function OnAuctionCreated(auctionID)
    local c = CurrentChar()
    local t, now = GetTime(), GetServerTime()
    auctionID = auctionID or ("pending" .. t)
    for _, e in ipairs(c.auctions) do
        if e.id == auctionID then return end
    end

    while postQueue[1] and t - postQueue[1].t > 60 do table.remove(postQueue, 1) end
    local q = table.remove(postQueue, 1)

    local entry = { id = auctionID, sold = false, pending = true, created = now }
    if q and q.secs then
        entry.exact, entry.minExp, entry.maxExp = true, now + q.secs, now + q.secs
    else
        -- Duration unknown: anywhere between 12h and 48h until the next real scan
        entry.exact, entry.minExp, entry.maxExp = false, now + 12 * 3600, now + 48 * 3600
    end
    c.auctions[#c.auctions + 1] = entry
    AT:Refresh()
end

local function OnAuctionCanceled(auctionID)
    local c = AuctionTrackerDB.chars[CharKey()]
    if not c or not c.auctions or not auctionID then return end
    for i, e in ipairs(c.auctions) do
        if e.id == auctionID then
            table.remove(c.auctions, i)
            break
        end
    end
    AT:Refresh()
end

local function SetupPostHooks()
    for _, name in ipairs({ "PostItem", "PostCommodity" }) do
        if C_AuctionHouse and C_AuctionHouse[name] then
            hooksecurefunc(C_AuctionHouse, name, NotePost)
        end
    end
end

------------------------------------------------------------
-- Mailbox income tracking (per realm)
------------------------------------------------------------
-- Turn a localized format string like "Auction successful: %s" into a Lua pattern.
local function FormatToPattern(fmt)
    if not fmt then return nil end
    local p = fmt:gsub("%%%d?%$?s", "\001")
    p = p:gsub("([%(%)%.%+%-%*%?%[%^%$%%])", "%%%1")
    p = p:gsub("\001", "(.+)")
    return "^" .. p
end

local soldPattern, outbidPattern, expiredPattern

local pending = {}   -- mail money we saw being taken, awaiting confirmation
local lastMoney

local function MailInfo(index)
    local f = GetInboxHeaderInfo or (C_Mail and C_Mail.GetInboxHeaderInfo)
    if not f then return end
    local a, _, _, d, e, _, g = f(index)
    if type(a) == "table" then return a.subject, a.money, a.daysLeft end
    return d, e, g   -- subject, money, daysLeft
end

local function QueueMail(index)
    local subject, money, daysLeft = MailInfo(index)
    if not money or money <= 0 then return end

    local isAH = false
    if subject then
        if soldPattern and subject:find(soldPattern) then
            isAH = true
        elseif outbidPattern and subject:find(outbidPattern) then
            return  -- returned bid money is not income
        end
    end
    -- When did the sale mail arrive? Mail lasts 30 days, so daysLeft gives its arrival time.
    -- (Only for sale mail; anything that doesn't look sensible falls back to "now".)
    local arrived
    if isAH and daysLeft then
        local now = GetServerTime()
        local t = now + daysLeft * 86400 - MAIL_LIFETIME
        if t <= now and t >= now - MAIL_LIFETIME - 86400 then arrived = t end
    end
    pending[#pending + 1] = { amount = money, ah = isAH, t = GetTime(), arrived = arrived }
end

-- A sale mail that was collected means one auction in our list was really a sale.
-- Drop the entry most likely to be it: already-expired first, then the earliest-ending.
local function ConsumeEntries(c, n, now)
    while n > 0 do
        local bestIdx, bestRank, bestExp
        for i, a in ipairs(c.auctions or {}) do
            if not a.sold then
                local rank = (a.maxExp <= now) and 1 or ((a.minExp <= now) and 2 or 3)
                if not bestRank or rank < bestRank or (rank == bestRank and a.maxExp < bestExp) then
                    bestIdx, bestRank, bestExp = i, rank, a.maxExp
                end
            end
        end
        if not bestIdx then return end
        table.remove(c.auctions, bestIdx)
        n = n - 1
    end
end

local function Credit(p)
    local db = AuctionTrackerDB
    local key = RealmKey()
    local r = db.mail[key]
    if not r then
        r = { name = GetRealmName(), ah = 0, ahCount = 0, other = 0, since = GetServerTime() }
        db.mail[key] = r
    end
    if p.ah then
        r.ah = r.ah + p.amount
        r.ahCount = r.ahCount + 1
    else
        r.other = r.other + p.amount
    end

    -- A sale mail was just collected. Settle the Sold figures now rather than at the next
    -- mailbox scan: the mailbox can be closed (or the game exited) before that scan runs.
    if p.ah then
        local c = db.chars[CharKey()]
        if c then
            local now = GetServerTime()
            local lastScan = c.lastScan or 0

            -- remove the waiting-mail record for this sale (the one that arrived closest to it)
            local m = c.mail
            if m and m.arrivals and #m.arrivals > 0 then
                local idx = 1
                if p.arrived then
                    local best
                    for i, t in ipairs(m.arrivals) do
                        local d = math.abs(t - p.arrived)
                        if not best or d < best then best, idx = d, i end
                    end
                end
                table.remove(m.arrivals, idx)
                m.sold = #m.arrivals
                m.gold = math.max(0, (m.gold or 0) - p.amount)
                local soonest
                for _, t in ipairs(m.arrivals) do
                    local e = t + MAIL_LIFETIME
                    if not soonest or e < soonest then soonest = e end
                end
                m.expiry = soonest
            end

            -- ... and the auction it belonged to
            if p.arrived and p.arrived > lastScan + 60 then
                -- sold after our last Auction House scan: still in the list as live/expired
                ConsumeEntries(c, 1, now)
            elseif (c.soldInf or 0) > 0 then
                c.soldInf = c.soldInf - 1       -- an estimated sale that has now been collected
            else
                for i, a in ipairs(c.auctions or {}) do
                    if a.sold then
                        table.remove(c.auctions, i)   -- listed as sold by the Auction House
                        break
                    end
                end
            end
        end
    end
end

-- Only credit mail money once our gold actually went up by that much.
local function OnMoneyChanged()
    local now = GetMoney()
    local delta = lastMoney and (now - lastMoney) or 0
    lastMoney = now
    if delta <= 0 or #pending == 0 then return end

    local t = GetTime()
    local keep = {}
    for _, p in ipairs(pending) do
        if t - p.t > 15 then
            -- stale: the take never went through
        elseif delta >= p.amount then
            delta = delta - p.amount
            Credit(p)
        else
            keep[#keep + 1] = p
        end
    end
    pending = keep
    AT:Refresh()
end

local function HookFn(name, fn)
    if _G[name] then
        hooksecurefunc(name, fn)
        return true
    elseif C_Mail and C_Mail[name] then
        hooksecurefunc(C_Mail, name, fn)
        return true
    end
    return false
end

------------------------------------------------------------
-- Mailbox scan: sales waiting in the mail (feeds the Sold column)
------------------------------------------------------------
local function MailHeader(index)
    local f = GetInboxHeaderInfo or (C_Mail and C_Mail.GetInboxHeaderInfo)
    if not f then return end
    local a, _, _, d, e, _, g = f(index)
    if type(a) == "table" then return a.subject, a.money, a.daysLeft end
    return d, e, g   -- subject, money, daysLeft
end

local function ScanMailbox()
    if not AT.mailOpen or not soldPattern then return end

    -- A take that hasn't gone through yet leaves the inbox in a half-updated state
    -- (the gold is still listed on the mail). Look again a moment later instead.
    local t = GetTime()
    for _, p in ipairs(pending) do
        if t - p.t <= 15 then
            C_Timer.After(1, ScanMailbox)
            return
        end
    end

    local getNum = GetInboxNumItems or (C_Mail and C_Mail.GetInboxNumItems)
    if not getNum then return end
    local numItems, total = getNum()
    if not numItems then return end
    local now = GetServerTime()

    -- Sale mails that still hold gold. Mail lasts 30 days, so daysLeft also tells us
    -- when each one arrived.
    local arrivals, gold, soonest = {}, 0, nil
    local expiredMails = 0   -- returned-item mails from auctions that ran out
    for i = 1, numItems do
        local subject, money, daysLeft = MailHeader(i)
        if subject and expiredPattern and subject:find(expiredPattern) then
            expiredMails = expiredMails + 1
        end
        if subject and money and money > 0 and subject:find(soldPattern) then
            gold = gold + money
            local expiry = daysLeft and (now + daysLeft * 86400) or nil
            arrivals[#arrivals + 1] = expiry and (expiry - MAIL_LIFETIME) or now
            if expiry and (not soonest or expiry < soonest) then soonest = expiry end
        end
    end

    -- Don't add characters to the list just for opening a mailbox
    local c = AuctionTrackerDB.chars[CharKey()]
    if not c then
        if #arrivals == 0 then return end
        c = CurrentChar()
    end

    local lastScan = c.lastScan or 0
    local post = 0   -- sales that arrived after the last Auction House scan
    for _, t in ipairs(arrivals) do
        if t > lastScan + 60 then post = post + 1 end
    end

    c.mail = {
        sold = #arrivals, gold = gold, expiry = soonest, arrivals = arrivals,
        post = post, stamp = lastScan, scanned = now,
        partial = ((total or numItems) > numItems) or nil,
    }
    -- An auction that expired comes back as a mail. If the whole inbox was read and holds
    -- fewer of those mails than the list has expired auctions, the rest were already
    -- collected, so drop them. The mailbox is the source of truth for expiries.
    if expiredPattern and not c.mail.partial and c.auctions then
        local stale = {}
        for idx, a in ipairs(c.auctions) do
            if not a.sold and a.maxExp <= now then
                stale[#stale + 1] = idx
            end
        end
        local drop = #stale - expiredMails
        if drop > 0 then
            table.sort(stale, function(x, y) return c.auctions[x].maxExp < c.auctions[y].maxExp end)
            local kill = {}
            for k = 1, drop do kill[stale[k]] = true end
            local keep = {}
            for idx, a in ipairs(c.auctions) do
                if not kill[idx] then keep[#keep + 1] = a end
            end
            c.auctions = keep
        end
    end
    c.soldInf = 0   -- the mailbox now shows the real number of sales
    c.soldInfAt = nil
    AT:Refresh()
end

local mailScanQueued = false
local function QueueMailScan()
    if mailScanQueued then return end
    mailScanQueued = true
    C_Timer.After(0.3, function()
        mailScanQueued = false
        ScanMailbox()
    end)
end

local function SetupMailHooks()
    soldPattern   = FormatToPattern(AUCTION_SOLD_MAIL_SUBJECT)
    outbidPattern = FormatToPattern(AUCTION_OUTBID_MAIL_SUBJECT)
    expiredPattern = FormatToPattern(AUCTION_EXPIRED_MAIL_SUBJECT)
    lastMoney = GetMoney()

    local a = HookFn("TakeInboxMoney", QueueMail)
    local b = HookFn("AutoLootMailItem", QueueMail)
    if not (a or b) then
        print(PREFIX .. "Couldn't hook the mailbox functions; mail income tracking is disabled.")
    end
end

------------------------------------------------------------
-- Window UI (flat, custom-drawn: no Blizzard frame art)
------------------------------------------------------------
local W, H, M = 700, 460, 16
local SB_W = 6                          -- scrollbar width
local TOP_LIST = 180                    -- y offset where the list begins
local VIEW_H = H - TOP_LIST - M         -- visible list height
local FONT = STANDARD_TEXT_FONT

local C = {
    bg     = { 0.075, 0.080, 0.100, 0.97 },
    title  = { 0.100, 0.105, 0.130, 1 },
    card   = { 0.115, 0.120, 0.150, 1 },
    border = { 1, 1, 1, 0.08 },
    accent = { 0.35, 0.65, 1.00 },
    text   = { 0.92, 0.93, 0.95 },
    dim    = { 0.55, 0.58, 0.65 },
    warn   = { 1.00, 0.80, 0.20 },
    bad    = { 1.00, 0.30, 0.30 },
    good   = { 0.35, 0.85, 0.50 },
}

-- Right-hand column widths per row type, left to right
-- char: live, sold, expired, next expiry, scanned
local COL = {
    char = { 72, 52, 62, 104, 104 },
    mail = { 150, 120 },
    text = { 0, 0, 0 },
}

-- Sortable columns, in on-screen order, for each list tab
local COLKEYS = {
    auctions = { "name", "live", "sold", "expired", "expiry", "scanned" },
    mail     = { "name", "ah", "total" },
}
-- Direction used the first time a column is clicked (true = ascending)
local SORT_DEFAULT = {
    auctions = { name = true, live = false, sold = false, expired = false, expiry = true, scanned = true },
    mail     = { name = true, ah = false, total = false },
}
-- Sort used before the player has chosen one
local SORT_START = {
    auctions = { key = "name", asc = true },
    mail     = { key = "total", asc = false },
}
local HUGE = math.huge

-- Saved sort for a tab (repaired if the saved data is missing or invalid)
local function SortSettings(tab)
    local db = AuctionTrackerDB
    db.sort = db.sort or {}
    local s = db.sort[tab]
    if type(s) ~= "table" or SORT_DEFAULT[tab][s.key] == nil then
        s = { key = SORT_START[tab].key, asc = SORT_START[tab].asc }
        db.sort[tab] = s
    end
    return s
end

-- Rows with an empty value (HUGE) always sink to the bottom, either direction
local function MakeComparator(s)
    local key, asc = s.key, s.asc
    return function(a, b)
        local x, y = a[key], b[key]
        if x ~= y then
            if x == HUGE then return false end
            if y == HUGE then return true end
            if asc then return x < y end
            return x > y
        end
        return a.tie < b.tie
    end
end

local function Hex(c)
    return string.format("|cff%02x%02x%02x",
        math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

local function Tex(parent, layer, c)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    if c then t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
    return t
end

local function FS(parent, size, c, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size, "")
    c = c or C.text
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function AddBorder(f, c)
    local function edge(p1, p2, w, h)
        local t = Tex(f, "BORDER", c)
        t:SetPoint(p1)
        t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
    end
    edge("TOPLEFT", "TOPRIGHT", nil, 1)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
end

local function ClassRGB(classFile)
    local col = classFile and RAID_CLASS_COLORS[classFile]
    if col then return col.r, col.g, col.b end
    return C.accent[1], C.accent[2], C.accent[3]
end

-- Green when stable (>2h), amber under 2h, red under 30m
local function ExpiryColor(left)
    if left < 1800 then return C.bad end
    if left < 7200 then return C.warn end
    return C.good
end

local function CloseButton(parent, size, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    local bg = Tex(b, "BACKGROUND", { 1, 0.3, 0.3, 0 })
    bg:SetAllPoints()
    local txt = FS(b, size >= 30 and 20 or 16, C.dim, "CENTER")
    txt:SetPoint("CENTER", 0, 1)
    txt:SetText("×")
    b:SetScript("OnEnter", function()
        bg:SetColorTexture(1, 0.3, 0.3, 0.85)
        txt:SetTextColor(1, 1, 1)
    end)
    b:SetScript("OnLeave", function()
        bg:SetColorTexture(1, 0.3, 0.3, 0)
        txt:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
    end)
    b:SetScript("OnClick", onClick)
    return b
end

------------------------------------------------------------
-- Scrolling (thin custom scrollbar)
------------------------------------------------------------
local PIN_EXTRA = 36   -- space the pinned "All Realms" row takes above the list

local function ViewH()
    return VIEW_H - (AT.pinExtra or 0)
end

local function ScrollRange()
    return math.max(0, AT.child:GetHeight() - ViewH())
end

local function UpdateThumb()
    local thumb = AT.thumb
    local range = ScrollRange()
    if range <= 0 or AT.tab == "settings" then
        thumb:Hide()
        return
    end
    local contentH = AT.child:GetHeight()
    local thumbH = math.max(28, ViewH() * ViewH() / contentH)
    local pos = (AT.scroll:GetVerticalScroll() / range) * (ViewH() - thumbH)
    thumb:SetHeight(thumbH)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", AT.track, "TOPRIGHT", 0, -pos)
    thumb:Show()
end

local function SetScroll(v)
    v = math.max(0, math.min(v, ScrollRange()))
    AT.scroll:SetVerticalScroll(v)
    UpdateThumb()
end

------------------------------------------------------------
-- Row pool
------------------------------------------------------------
local rows = {}

-- Shows the little x just after a character's name (only meaningful on character rows)
local function ShowForget(r)
    if not r.charKey then return end
    local w = math.min(r.name:GetStringWidth(), r.name:GetWidth())
    r.forget:ClearAllPoints()
    r.forget:SetPoint("LEFT", r.name, "LEFT", w + 6, 0)
    r.forget:Show()
end

-- Hovering a character row shows what is waiting in their mailbox (from the last mailbox visit)
local function ShowRowTooltip(r)
    local c = r.charKey and AuctionTrackerDB.chars[r.charKey]
    if not c then return end
    local m = c.mail
    local now = GetServerTime()
    local waiting = 0
    for _, t in ipairs(m and m.arrivals or {}) do
        if t + MAIL_LIFETIME > now then waiting = waiting + 1 end
    end
    local est = c.soldInf or 0
    if est > 0 and (now - (c.soldInfAt or 0)) > MAIL_LIFETIME then est = 0 end
    if waiting == 0 and est == 0 then return end

    GameTooltip:SetOwner(r, "ANCHOR_CURSOR_RIGHT")
    GameTooltip:AddLine(c.name or r.charKey, 1, 1, 1)
    if waiting > 0 then
        GameTooltip:AddDoubleLine("Sales waiting in mail", tostring(waiting), 0.8, 0.8, 0.8, C.good[1], C.good[2], C.good[3])
        GameTooltip:AddDoubleLine("Gold waiting", FormatGold(m.gold), 0.8, 0.8, 0.8, 1, 1, 1)
        if m.expiry then
            local left = m.expiry - now
            local col = ExpiryColor(left)
            GameTooltip:AddDoubleLine("Soonest mail expires in", FormatDuration(left), 0.8, 0.8, 0.8, col[1], col[2], col[3])
        end
        GameTooltip:AddLine("Mailbox checked " .. FormatDuration(now - m.scanned) .. " ago", C.dim[1], C.dim[2], C.dim[3])
        if m.partial then
            GameTooltip:AddLine("Only the mails shown in the inbox were counted.", C.dim[1], C.dim[2], C.dim[3])
        end
    end
    if est > 0 then
        GameTooltip:AddDoubleLine("Estimated sales not yet in mailbox check", tostring(est), 0.8, 0.8, 0.8, C.good[1], C.good[2], C.good[3])
        GameTooltip:AddLine("Auctions that left your list before they could have expired.", C.dim[1], C.dim[2], C.dim[3])
    end
    GameTooltip:Show()
end

local function NewRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r.bg = Tex(r, "BACKGROUND")
    r.bg:SetAllPoints()
    r.accent = Tex(r, "ARTWORK", C.accent)
    r.accent:SetPoint("TOPLEFT")
    r.accent:SetPoint("BOTTOMLEFT")
    r.accent:SetWidth(3)

    r.name = FS(r, 12)
    r.c1 = FS(r, 12, C.text, "RIGHT")
    r.c2 = FS(r, 12, C.text, "RIGHT")
    r.c3 = FS(r, 12, C.text, "RIGHT")
    r.c4 = FS(r, 12, C.text, "RIGHT")
    r.c5 = FS(r, 12, C.text, "RIGHT")

    -- Hover a character row to reveal an x that forgets that character
    r:EnableMouse(true)
    r.forget = CloseButton(r, 16, function()
        if r.charKey then AT:ForgetPrompt(r.charKey) end
    end)
    r.forget:Hide()
    r.forget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Forget this character", 1, 1, 1)
        GameTooltip:Show()
    end)
    r.forget:HookScript("OnLeave", function()
        GameTooltip:Hide()
        if not r:IsMouseOver() then r.forget:Hide() end
    end)
    r:SetScript("OnEnter", function()
        ShowForget(r)
        ShowRowTooltip(r)
    end)
    r:SetScript("OnLeave", function()
        GameTooltip:Hide()
        if not r:IsMouseOver() then r.forget:Hide() end
    end)

    return r
end

local function GetRow(i)
    local r = rows[i]
    if r then return r end
    r = NewRow(AT.child)
    rows[i] = r
    return r
end

-- Positions a row and clears everything a previous use may have left behind
local function ApplyLayout(r, mode, y, h)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", AT.child, "TOPLEFT", 0, -y)
    r:SetPoint("TOPRIGHT", AT.child, "TOPRIGHT", 0, -y)
    r:SetHeight(h)

    local w = COL[mode]
    local cols = { r.c1, r.c2, r.c3, r.c4, r.c5 }
    local n = #w
    for i = 1, 5 do cols[i]:ClearAllPoints() end
    cols[n]:SetPoint("RIGHT", r, "RIGHT", -12, 0)
    cols[n]:SetWidth(w[n])
    for i = n - 1, 1, -1 do
        cols[i]:SetPoint("RIGHT", cols[i + 1], "LEFT", -8, 0)
        cols[i]:SetWidth(w[i])
    end

    r.name:ClearAllPoints()
    r.name:SetPoint("LEFT", r, "LEFT", mode == "char" and 16 or 12, 0)
    if mode == "text" then
        r.name:SetPoint("RIGHT", r, "RIGHT", -12, 0)
    else
        r.name:SetPoint("RIGHT", r.c1, "LEFT", -8, 0)
    end
    r.name:SetFont(FONT, mode == "char" and 13 or 12, "")
    r.name:SetJustifyH(mode == "text" and "CENTER" or "LEFT")
    for i = 1, 3 do cols[i]:SetFont(FONT, 12, "") end

    for _, fs in ipairs({ r.name, r.c1, r.c2, r.c3, r.c4, r.c5 }) do
        fs:SetTextColor(C.text[1], C.text[2], C.text[3])
        fs:SetText("")
    end
    r.bg:SetColorTexture(0, 0, 0, 0)
    r.accent:Hide()
    r.forget:Hide()
    r.charKey = nil
    r:Show()
end

local function SetTextRow(r, y, text, h)
    h = h or 60
    ApplyLayout(r, "text", y, h)
    r.name:SetText(text)
    r.name:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
    return h
end

local function SetCharRow(r, y, k, c, now, zebra)
    ApplyLayout(r, "char", y, 34)
    r.charKey = k
    local live, unsure, sold, expired, soon = Counts(c, now)

    if zebra then r.bg:SetColorTexture(1, 1, 1, 0.025) end
    local cr, cg, cb = ClassRGB(c.class)
    r.accent:SetColorTexture(cr, cg, cb, 1)
    r.accent:Show()

    local name = ClassColored(c.name or k, c.class) .. "  " .. Hex(C.dim) .. (c.realm or "?") .. "|r"
    r.name:SetText(name)

    -- Live, sold and expired are kept as three separate numbers
    r.c1:SetFont(FONT, 16, "")
    r.c1:SetText(Hex(C.text) .. live .. "|r" .. (unsure > 0 and (Hex(C.dim) .. " +" .. unsure .. "?|r") or ""))

    if sold > 0 then
        r.c2:SetFont(FONT, 16, "")
        r.c2:SetText(Hex(C.good) .. sold .. "|r")
    else
        r.c2:SetText(Hex(C.dim) .. "-|r")
    end

    if expired > 0 then
        r.c3:SetFont(FONT, 16, "")
        r.c3:SetText(Hex(C.bad) .. expired .. "|r")
    else
        r.c3:SetText(Hex(C.dim) .. "-|r")
    end

    -- Next expiry always follows the live auctions; "Expired" only when nothing is live
    if soon then
        local left = soon - now
        r.c4:SetText(Hex(ExpiryColor(left)) .. FormatDuration(left) .. "|r")
    elseif expired > 0 then
        r.c4:SetText(Hex(C.bad) .. "Expired|r")
    else
        r.c4:SetText(Hex(C.dim) .. "-|r")
    end

    r.c5:SetText(Hex(C.dim) .. (c.lastScan and (FormatDuration(now - c.lastScan) .. " ago") or "never") .. "|r")

    if r:IsMouseOver() then ShowForget(r) end
    return 34
end

local function SetMailRow(r, y, name, ah, ahCount, other, since, zebra, isTotal)
    ApplyLayout(r, "mail", y, 30)
    if isTotal then
        r.bg:SetColorTexture(C.card[1], C.card[2], C.card[3], 1)
        r.accent:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        r.accent:Show()
    elseif zebra then
        r.bg:SetColorTexture(1, 1, 1, 0.025)
    end
    r.name:SetText(name)
    r.c1:SetText(FormatGold(ah) .. (ahCount and ahCount > 0 and ("  " .. Hex(C.dim) .. "(" .. ahCount .. ")|r") or ""))
    r.c2:SetText(Hex(C.accent) .. FormatGold(ah + other) .. "|r")
    return 30
end

------------------------------------------------------------
-- Main window
------------------------------------------------------------
-- Highlights the active sort column and points its arrow up or down
local function UpdateHeaders(tab)
    local bar = AT.colBar
    local s = SortSettings(tab)
    local keys = COLKEYS[tab]
    for i, fs in ipairs({ bar.name, bar.c1, bar.c2, bar.c3, bar.c4, bar.c5 }) do
        local active = (keys[i] == s.key)
        local col = active and C.text or C.dim
        fs:SetTextColor(col[1], col[2], col[3])
        local arrow = bar.arrows[i]
        if active then
            arrow:ClearAllPoints()
            if i == 1 then
                arrow:SetPoint("LEFT", fs, "LEFT", fs:GetStringWidth() + 4, 0)
            else
                arrow:SetPoint("RIGHT", fs, "RIGHT", -(fs:GetStringWidth() + 4), 0)
            end
            if s.asc then
                arrow:SetTexCoord(0, 0.5625, 1, 0)
            else
                arrow:SetTexCoord(0, 0.5625, 0, 1)
            end
            arrow:Show()
        else
            arrow:Hide()
        end
    end
end

local function ApplyColumns(tab)
    local bar = AT.colBar
    local w, labels, left
    if tab == "mail" then
        w, left = COL.mail, 12
        labels = { "REALM", "AH SALES", "TOTAL" }
    else
        w, left = COL.char, 16
        labels = { "CHARACTER", "LIVE", "SOLD", "EXPIRED", "NEXT EXPIRY", "SCANNED" }
    end
    bar.name:ClearAllPoints()
    bar.name:SetPoint("LEFT", bar, "LEFT", left, 0)
    bar.name:SetText(labels[1])

    -- Right-anchored chain: the last used column sits at the right edge
    local cols = { bar.c1, bar.c2, bar.c3, bar.c4, bar.c5 }
    local n = #w
    for i = 1, 5 do cols[i]:ClearAllPoints() end
    cols[n]:SetPoint("RIGHT", bar, "RIGHT", -12, 0)
    for i = n - 1, 1, -1 do
        cols[i]:SetPoint("RIGHT", cols[i + 1], "LEFT", -8, 0)
    end
    for i = 1, 5 do
        local fs, hb = cols[i], bar.btns[i + 1]
        if i <= n then
            fs:SetWidth(w[i])
            fs:SetText(labels[i + 1])
            fs:Show()
            hb:Show()
        else
            fs:SetText("")
            fs:Hide()
            hb:Hide()
            bar.arrows[i + 1]:Hide()
        end
    end
    UpdateHeaders(tab)
end

local function MakeCard(parent, label)
    local card = CreateFrame("Frame", nil, parent)
    card:SetSize((W - 2 * M - 20) / 3, 64)
    local bg = Tex(card, "BACKGROUND", C.card)
    bg:SetAllPoints()
    AddBorder(card, C.border)

    card.label = FS(card, 10, C.dim)
    card.label:SetPoint("TOPLEFT", 12, -10)
    card.label:SetPoint("RIGHT", -12, 0)
    card.label:SetText(label)

    card.value = FS(card, 20, C.text)
    card.value:SetPoint("TOPLEFT", 12, -24)
    card.value:SetPoint("RIGHT", -12, 0)

    card.sub = FS(card, 11, C.dim)
    card.sub:SetPoint("BOTTOMLEFT", 12, 8)
    card.sub:SetPoint("RIGHT", -12, 0)
    return card
end

------------------------------------------------------------
-- Settings tab
------------------------------------------------------------
StaticPopupDialogs["AUCTIONTRACKER_CONFIRM"] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data)
        if data and data.fn then data.fn() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function Confirm(msg, fn)
    StaticPopup_Show("AUCTIONTRACKER_CONFIRM", msg, nil, { fn = fn })
end

local function DoResetAuctions()
    AuctionTrackerDB.chars = {}
    print(PREFIX .. "All auction data cleared.")
    AT:Refresh()
end

local function DoResetMail()
    AuctionTrackerDB.mail = {}
    print(PREFIX .. "Mailbox income totals cleared.")
    AT:Refresh()
end

local function DoResetPopup()
    AuctionTrackerDB.popup.pos = nil
    print(PREFIX .. "Popup position reset.")
    if AT.ahOpen then AT:ShowPopup() end
end

-- Called by the x on a character row
function AT:ForgetPrompt(key)
    local c = AuctionTrackerDB.chars[key]
    local label = (c and c.name) and (c.name .. "-" .. (c.realm or "?")) or key
    Confirm("Forget " .. label .. "?\nTheir saved auctions are removed here, and come back the next time you open the Auction House on that character.", function()
        AuctionTrackerDB.chars[key] = nil
        print(PREFIX .. "Removed " .. key)
        AT:Refresh()
    end)
end

local function MakeCheck(parent, label, desc, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(36)

    local box = CreateFrame("Frame", nil, b)
    box:SetSize(18, 18)
    box:SetPoint("TOPLEFT", 0, -2)
    local boxBg = Tex(box, "BACKGROUND", C.card)
    boxBg:SetAllPoints()
    AddBorder(box, { 1, 1, 1, 0.25 })
    local tick = Tex(box, "ARTWORK", C.accent)
    tick:SetPoint("TOPLEFT", 4, -4)
    tick:SetPoint("BOTTOMRIGHT", -4, 4)

    local text = FS(b, 13)
    text:SetPoint("TOPLEFT", 28, -1)
    text:SetText(label)
    local sub = FS(b, 11, C.dim)
    sub:SetPoint("TOPLEFT", 28, -19)
    sub:SetText(desc)

    function b:Update() tick:SetShown(get() and true or false) end
    b:SetScript("OnClick", function()
        set(not get())
        b:Update()
    end)
    b:SetScript("OnEnter", function() boxBg:SetColorTexture(1, 1, 1, 0.10) end)
    b:SetScript("OnLeave", function() boxBg:SetColorTexture(C.card[1], C.card[2], C.card[3], 1) end)
    return b
end

local function MakeButton(parent, label, width, onClick, danger)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 28)
    local bg = Tex(b, "BACKGROUND", C.card)
    bg:SetAllPoints()
    AddBorder(b, C.border)
    local txt = FS(b, 12, C.text, "CENTER")
    txt:SetPoint("CENTER")
    txt:SetText(label)
    b:SetScript("OnEnter", function()
        bg:SetColorTexture(1, 1, 1, 0.08)
        if danger then txt:SetTextColor(C.bad[1], C.bad[2], C.bad[3]) end
    end)
    b:SetScript("OnLeave", function()
        bg:SetColorTexture(C.card[1], C.card[2], C.card[3], 1)
        txt:SetTextColor(C.text[1], C.text[2], C.text[3])
    end)
    b:SetScript("OnClick", onClick)
    return b
end

local function BuildSettings(f)
    local p = CreateFrame("Frame", nil, f)
    p:SetPoint("TOPLEFT", f, "TOPLEFT", M, -176)
    p:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -M, M)
    p:Hide()

    local function Section(text, y)
        local fs = FS(p, 10, C.dim)
        fs:SetPoint("TOPLEFT", 0, -y)
        fs:SetText(text)
        local line = Tex(p, "BORDER", C.border)
        line:SetPoint("TOPLEFT", 0, -(y + 16))
        line:SetPoint("TOPRIGHT", 0, -(y + 16))
        line:SetHeight(1)
    end

    Section("GENERAL", 0)

    local specs = {
        {
            label = "Show popup at the Auction House",
            desc  = "A small box with your active auction count and next expiry when the Auction House opens.",
            get   = function() return not AuctionTrackerDB.popup.disabled end,
            set   = function(v)
                AuctionTrackerDB.popup.disabled = not v
                if not v then
                    AT:HidePopup()
                elseif AT.ahOpen then
                    AT:ShowPopup()
                end
            end,
        },
        {
            label = "Show minimap button",
            desc  = "Left-click opens this window, right-click prints a summary in chat.",
            get   = function() return not AuctionTrackerDB.minimap.hide end,
            set   = function(v)
                AuctionTrackerDB.minimap.hide = not v
                if AT.mmButton then AT.mmButton:SetShown(v) end
            end,
        },
        {
            label = "Chat summary at login",
            desc  = "Print your live auction count and next expiry a few seconds after logging in.",
            get   = function() return not AuctionTrackerDB.noLoginSummary end,
            set   = function(v) AuctionTrackerDB.noLoginSummary = not v end,
        },
    }

    p.checks = {}
    for i, sp in ipairs(specs) do
        local cb = MakeCheck(p, sp.label, sp.desc, sp.get, sp.set)
        local y = 28 + (i - 1) * 46
        cb:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -y)
        cb:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, -y)
        p.checks[i] = cb
    end

    Section("DATA", 176)

    local b1 = MakeButton(p, "Reset popup position", 170, DoResetPopup)
    b1:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -204)
    local b2 = MakeButton(p, "Clear mail income", 170, function()
        Confirm("Clear all tracked mailbox income totals?", DoResetMail)
    end, true)
    b2:SetPoint("TOPLEFT", b1, "TOPRIGHT", 10, 0)
    local b3 = MakeButton(p, "Clear auction data", 170, function()
        Confirm("Clear the saved auction data for all characters?", DoResetAuctions)
    end, true)
    b3:SetPoint("TOPLEFT", b2, "TOPRIGHT", 10, 0)

    local hint = FS(p, 11, C.dim)
    hint:SetPoint("TOPLEFT", 0, -246)
    hint:SetText("To forget one character, hover their name on the Auctions tab and click the x (or type |cffffffff/at forget Name-Realm|r).")

    function p:RefreshChecks()
        for _, cb in ipairs(self.checks) do cb:Update() end
    end

    f.settings = p
end

local function BuildFrame()
    local db = AuctionTrackerDB
    local f = CreateFrame("Frame", "AuctionTrackerFrame", UIParent)
    f:SetSize(W, H)
    local pos = db.window
    if pos then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        f:SetPoint("CENTER")
    end
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetToplevel(true)
    f:SetFrameStrata("HIGH")
    f:Hide()
    tinsert(UISpecialFrames, "AuctionTrackerFrame")

    local bg = Tex(f, "BACKGROUND", C.bg)
    bg:SetAllPoints()
    AddBorder(f, C.border)

    -- Title bar (also the drag handle)
    local tb = CreateFrame("Frame", nil, f)
    tb:SetPoint("TOPLEFT")
    tb:SetPoint("TOPRIGHT")
    tb:SetHeight(40)
    tb:EnableMouse(true)
    tb:RegisterForDrag("LeftButton")
    tb:SetScript("OnDragStart", function() f:StartMoving() end)
    tb:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local p, _, rp, x, y = f:GetPoint()
        AuctionTrackerDB.window = { p, rp, x, y }
    end)
    local tbBg = Tex(tb, "BACKGROUND", C.title)
    tbBg:SetAllPoints()
    local topLine = Tex(tb, "ARTWORK", C.accent)
    topLine:SetPoint("TOPLEFT")
    topLine:SetPoint("TOPRIGHT")
    topLine:SetHeight(2)

    local title = FS(tb, 14, C.text)
    title:SetPoint("LEFT", 16, -1)
    title:SetText("Auction Tracker")

    local close = CloseButton(tb, 40, function() f:Hide() end)
    close:SetPoint("TOPRIGHT")

    -- Stat cards
    f.cards = {
        MakeCard(f, "LIVE AUCTIONS"),
        MakeCard(f, "NEXT EXPIRY"),
        MakeCard(f, "MAIL INCOME"),
    }
    f.cards[1]:SetPoint("TOPLEFT", M, -54)
    f.cards[2]:SetPoint("TOPLEFT", f.cards[1], "TOPRIGHT", 10, 0)
    f.cards[3]:SetPoint("TOPLEFT", f.cards[2], "TOPRIGHT", 10, 0)

    -- Tabs
    f.tabs = {}
    local function MakeTab(key, label, x)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(120, 28)
        b:SetPoint("TOPLEFT", M + x, -130)
        b.text = FS(b, 12, C.dim, "CENTER")
        b.text:SetPoint("CENTER")
        b.text:SetText(label)
        b.line = Tex(b, "ARTWORK", C.accent)
        b.line:SetPoint("BOTTOMLEFT")
        b.line:SetPoint("BOTTOMRIGHT")
        b.line:SetHeight(2)
        b.line:Hide()
        b:SetScript("OnClick", function() AT:SetTab(key) end)
        b:SetScript("OnEnter", function(self) self.text:SetTextColor(C.text[1], C.text[2], C.text[3]) end)
        b:SetScript("OnLeave", function() AT:SetTab(AT.tab, true) end)
        f.tabs[key] = b
    end
    MakeTab("auctions", "Auctions", 0)
    MakeTab("mail", "Mail income", 124)
    MakeTab("settings", "Settings", 248)

    local tabLine = Tex(f, "BORDER", C.border)
    tabLine:SetPoint("TOPLEFT", M, -158)
    tabLine:SetPoint("TOPRIGHT", -M, -158)
    tabLine:SetHeight(1)

    -- Column headers
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", M, -159)
    bar:SetPoint("TOPRIGHT", -(M + SB_W + 6), -159)
    bar:SetHeight(21)
    bar.name = FS(bar, 10, C.dim)
    bar.name:SetPoint("LEFT", bar, "LEFT", 16, 0)
    bar.c3 = FS(bar, 10, C.dim, "RIGHT")
    bar.c3:SetPoint("RIGHT", bar, "RIGHT", -12, 0)
    bar.c2 = FS(bar, 10, C.dim, "RIGHT")
    bar.c2:SetPoint("RIGHT", bar.c3, "LEFT", -8, 0)
    bar.c1 = FS(bar, 10, C.dim, "RIGHT")
    bar.c1:SetPoint("RIGHT", bar.c2, "LEFT", -8, 0)
    bar.c4 = FS(bar, 10, C.dim, "RIGHT")
    bar.c5 = FS(bar, 10, C.dim, "RIGHT")
    AT.colBar = bar

    -- Each header is a button that sorts the list by that column
    bar.arrows = {}
    bar.btns = {}
    for i, fs in ipairs({ bar.name, bar.c1, bar.c2, bar.c3, bar.c4, bar.c5 }) do
        local arrow = bar:CreateTexture(nil, "OVERLAY")
        arrow:SetSize(9, 8)
        arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
        arrow:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
        arrow:Hide()
        bar.arrows[i] = arrow

        local hb = CreateFrame("Button", nil, bar)
        hb:SetPoint("TOPLEFT", fs, "TOPLEFT", -4, 4)
        hb:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 4, -4)
        bar.btns[i] = hb
        hb:SetScript("OnClick", function() AT:SortBy(i) end)
        hb:SetScript("OnEnter", function() fs:SetTextColor(C.text[1], C.text[2], C.text[3]) end)
        hb:SetScript("OnLeave", function()
            if COLKEYS[AT.tab] then UpdateHeaders(AT.tab) end
        end)
    end

    -- Scrolling list
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", M, -TOP_LIST)
    scroll:SetPoint("BOTTOMRIGHT", -(M + SB_W + 6), M)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(W - 2 * M - SB_W - 6, 1)
    scroll:SetScrollChild(child)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        SetScroll(scroll:GetVerticalScroll() - delta * 48)
    end)
    AT.scroll, AT.child = scroll, child

    -- Scrollbar
    local track = Tex(f, "ARTWORK", { 1, 1, 1, 0.04 })
    track:SetPoint("TOPRIGHT", f, "TOPRIGHT", -M, -TOP_LIST)
    track:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -M, M)
    track:SetWidth(SB_W)
    AT.track = track

    local thumb = CreateFrame("Button", nil, f)
    thumb:SetWidth(SB_W)
    local thumbTex = Tex(thumb, "OVERLAY", { 1, 1, 1, 0.18 })
    thumbTex:SetAllPoints()
    thumb:SetScript("OnEnter", function() thumbTex:SetColorTexture(1, 1, 1, 0.35) end)
    thumb:SetScript("OnLeave", function(self)
        if not self.dragging then thumbTex:SetColorTexture(1, 1, 1, 0.18) end
    end)
    thumb:SetScript("OnMouseDown", function(self)
        self.dragging = true
        local _, cy = GetCursorPosition()
        self.startY = cy
        self.startScroll = scroll:GetVerticalScroll()
        self:SetScript("OnUpdate", function(s)
            local _, y = GetCursorPosition()
            local dy = (s.startY - y) / UIParent:GetEffectiveScale()
            local usable = ViewH() - s:GetHeight()
            if usable > 0 then
                SetScroll(s.startScroll + dy * (ScrollRange() / usable))
            end
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self)
        self.dragging = false
        self:SetScript("OnUpdate", nil)
        thumbTex:SetColorTexture(1, 1, 1, 0.18)
    end)
    AT.thumb = thumb

    AT.frame = f
    BuildSettings(f)
    f:SetScript("OnShow", function() AT:Refresh() end)
    C_Timer.NewTicker(15, function() AT:Refresh() end)

    AT:SetTab("auctions")
end

------------------------------------------------------------
-- Auction House popup (shown whenever the AH opens)
------------------------------------------------------------
local function BuildPopup()
    local p = CreateFrame("Frame", "AuctionTrackerPopup", UIParent)
    p:SetSize(270, 66)
    p:SetFrameStrata("HIGH")
    p:SetClampedToScreen(true)
    p:SetMovable(true)
    p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:Hide()

    local bg = Tex(p, "BACKGROUND", C.bg)
    bg:SetAllPoints()
    AddBorder(p, C.border)
    local line = Tex(p, "ARTWORK", C.accent)
    line:SetPoint("TOPLEFT")
    line:SetPoint("TOPRIGHT")
    line:SetHeight(2)

    p.line1 = FS(p, 14)
    p.line1:SetPoint("TOPLEFT", 12, -15)
    p.line1:SetPoint("RIGHT", -32, 0)
    p.line2 = FS(p, 12)
    p.line2:SetPoint("TOPLEFT", 12, -39)
    p.line2:SetPoint("RIGHT", -12, 0)

    local close = CloseButton(p, 24, function() p:Hide() end)
    close:SetPoint("TOPRIGHT", 0, -2)

    p:SetScript("OnMouseDown", function(self) self.moved = false end)
    p:SetScript("OnDragStart", function(self)
        self.moved = true
        self:StartMoving()
    end)
    p:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local pt, _, rp, x, y = self:GetPoint()
        AuctionTrackerDB.popup.pos = { pt, rp, x, y }
    end)
    p:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and not self.moved then
            if AT.frame:IsShown() then AT.frame:Hide() else AT.frame:Show() end
        end
    end)
    p:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Click to open the full window", 1, 1, 1)
        GameTooltip:AddLine("Drag to move", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)

    AT.popup = p
end

function AT:ShowPopup()
    local p = self.popup
    if not p or AuctionTrackerDB.popup.disabled then return end
    p:ClearAllPoints()
    local pos = AuctionTrackerDB.popup.pos
    if pos then
        p:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    elseif AuctionHouseFrame then
        p:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "TOPRIGHT", 0, 4)
    else
        p:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
    p:Show()
    self:RefreshPopup()
end

function AT:HidePopup()
    if self.popup then self.popup:Hide() end
end

function AT:RefreshPopup()
    local p = self.popup
    if not p or not p:IsShown() then return end

    local db = AuctionTrackerDB
    local now = GetServerTime()

    -- Current character
    local live, unsure = 0, 0
    local me = db.chars[CharKey()]
    if me then live, unsure = Counts(me, now) end
    local count = tostring(live)
    if unsure > 0 then count = count .. " (+" .. unsure .. " unsure)" end
    p.line1:SetText(Hex(C.dim) .. "Active Auctions: |r" .. Hex(C.text) .. count .. "|r")

    -- Next expiry across the whole account
    local soonest, who
    for k, c in pairs(db.chars) do
        local _, _, _, _, soon = Counts(c, now)
        if soon and (not soonest or soon < soonest) then
            soonest, who = soon, c.name or k
        end
    end
    if soonest then
        local left = soonest - now
        p.line2:SetText(Hex(C.dim) .. "Next expiry: |r" .. Hex(ExpiryColor(left)) .. FormatDuration(left) .. "|r"
            .. Hex(C.dim) .. " (" .. who .. ")|r")
    else
        p.line2:SetText(Hex(C.dim) .. "Next expiry: none|r")
    end
end

------------------------------------------------------------
-- Refresh
------------------------------------------------------------
-- The list starts lower when the pinned "All Realms" row is shown
function AT:LayoutList(extra)
    if (self.pinExtra or 0) == extra then return end
    self.pinExtra = extra
    local f = self.frame
    self.scroll:ClearAllPoints()
    self.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", M, -(TOP_LIST + extra))
    self.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(M + SB_W + 6), M)
    self.track:ClearAllPoints()
    self.track:SetPoint("TOPRIGHT", f, "TOPRIGHT", -M, -(TOP_LIST + extra))
    self.track:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -M, M)
end

-- "All Realms" stays above the scrolling list, outside the sort
function AT:UpdatePin(show, ah, count, other)
    local pin = self.pinRow
    if not show then
        if pin then pin:Hide() end
        self:LayoutList(0)
        return
    end
    if not pin then
        pin = NewRow(self.frame)
        self.pinRow = pin
    end
    SetMailRow(pin, 0, "All Realms", ah, count, other, nil, false, true)
    pin:ClearAllPoints()
    pin:SetPoint("TOPLEFT", self.frame, "TOPLEFT", M, -TOP_LIST)
    pin:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -(M + SB_W + 6), -TOP_LIST)
    self:LayoutList(PIN_EXTRA)
end

function AT:Refresh()
    self:RefreshPopup()

    local f = self.frame
    if not f or not f:IsShown() then return end

    local db = AuctionTrackerDB
    local now = GetServerTime()
    local keys = SortedCharKeys()

    -- Stat cards
    local totalLive, soonest, soonestWho = 0, nil, nil
    for _, k in ipairs(keys) do
        local c = db.chars[k]
        local live, unsure, _, _, soon = Counts(c, now)
        totalLive = totalLive + live + unsure
        if soon and (not soonest or soon < soonest) then
            soonest, soonestWho = soon, c.name or k
        end
    end

    local cards = f.cards
    cards[1].value:SetText(tostring(totalLive))
    cards[1].sub:SetText(string.format("across %d character%s", #keys, #keys == 1 and "" or "s"))

    if soonest then
        local left = soonest - now
        local col = ExpiryColor(left)
        cards[2].value:SetText(FormatDuration(left))
        cards[2].value:SetTextColor(col[1], col[2], col[3])
        cards[2].sub:SetText(soonestWho)
    else
        cards[2].value:SetText("-")
        cards[2].value:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
        cards[2].sub:SetText("no live auctions")
    end

    local realm = db.mail[RealmKey()]
    cards[3].label:SetText("MAIL INCOME · " .. string.upper(GetRealmName()))
    cards[3].value:SetText(FormatGold(realm and (realm.ah + realm.other) or 0))
    cards[3].sub:SetText("")

    if self.tab == "settings" then
        self:UpdatePin(false)
        f.settings:RefreshChecks()
        return
    end

    -- List
    local y, i = 0, 0
    local function nextRow()
        i = i + 1
        return GetRow(i)
    end

    if self.tab == "mail" then
        local realms = {}
        local tAH, tOther, tCount = 0, 0, 0
        for rk, r in pairs(db.mail) do
            local nm = (r.name or rk):lower()
            realms[#realms + 1] = {
                key = rk, r = r, tie = nm .. rk,
                name = nm, ah = r.ah, other = r.other, total = r.ah + r.other,
            }
            tAH, tOther, tCount = tAH + r.ah, tOther + r.other, tCount + (r.ahCount or 0)
        end
        table.sort(realms, MakeComparator(SortSettings("mail")))

        self:UpdatePin(#realms > 1, tAH, tCount, tOther)

        if #realms == 0 then
            y = y + SetTextRow(nextRow(), y, "No mailbox income tracked yet.\nCollect gold from your mailbox and it will show up here.")
        else
            for n, e in ipairs(realms) do
                local r = e.r
                y = y + SetMailRow(nextRow(), y, r.name or e.key, r.ah, r.ahCount, r.other, r.since, n % 2 == 0)
            end
        end
    else
        self:UpdatePin(false)
        if #keys == 0 then
            y = y + SetTextRow(nextRow(), y, "No data yet.\nOpen the Auction House on each character once.")
        end
        local entries = {}
        for _, k in ipairs(keys) do
            local c = db.chars[k]
            local live, unsure, sold, expired, soon = Counts(c, now)
            entries[#entries + 1] = {
                k = k, c = c, tie = k:lower(),
                name = (c.name or k):lower(),
                live = live + unsure,
                sold = sold,
                expired = expired,
                expiry = soon and (soon - now) or (expired > 0 and -1 or HUGE),
                scanned = c.lastScan and (now - c.lastScan) or HUGE,
            }
        end
        table.sort(entries, MakeComparator(SortSettings("auctions")))
        for n, e in ipairs(entries) do
            y = y + SetCharRow(nextRow(), y, e.k, e.c, now, n % 2 == 0)
        end
    end

    for j = i + 1, #rows do rows[j]:Hide() end
    self.child:SetHeight(math.max(1, y))
    SetScroll(self.scroll:GetVerticalScroll())
end

function AT:SetTab(name, onlyVisuals)
    self.tab = name
    for key, b in pairs(self.frame.tabs) do
        local active = (key == name)
        local c = active and C.text or C.dim
        b.text:SetTextColor(c[1], c[2], c[3])
        b.line:SetShown(active)
    end
    if onlyVisuals then return end

    local isSettings = (name == "settings")
    self.colBar:SetShown(not isSettings)
    self.scroll:SetShown(not isSettings)
    self.track:SetShown(not isSettings)
    self.frame.settings:SetShown(isSettings)
    if isSettings then
        self.thumb:Hide()
    else
        ApplyColumns(name)
        SetScroll(0)
    end
    self:Refresh()
end

-- Header click: sort by that column, or flip direction if it is already active
function AT:SortBy(index)
    local tab = self.tab
    local keys = COLKEYS[tab]
    if not keys then return end
    local key = keys[index]
    local s = SortSettings(tab)
    if s.key == key then
        s.asc = not s.asc
    else
        s.key = key
        s.asc = SORT_DEFAULT[tab][key]
    end
    UpdateHeaders(tab)
    self:Refresh()
    SetScroll(0)
end

function AT:OpenSettings()
    self.frame:Show()
    self:SetTab("settings")
end

------------------------------------------------------------
-- Minimap button
------------------------------------------------------------
local function UpdateMinimapPos()
    local btn = AT.mmButton
    if not btn then return end
    local angle = math.rad(AuctionTrackerDB.minimap.angle or 215)
    local radius = (Minimap:GetWidth() / 2) + 5
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function ShowMinimapTooltip(self)
    local db = AuctionTrackerDB
    local now = GetServerTime()

    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Auction Tracker", 0.2, 0.8, 1)

    local keys = SortedCharKeys()
    if #keys == 0 then
        GameTooltip:AddLine("No data yet - visit the Auction House.", 0.7, 0.7, 0.7)
    end
    for _, k in ipairs(keys) do
        local c = db.chars[k]
        local live, unsure, _, _, soon = Counts(c, now)
        local right = LiveText(live, unsure)
        if soon then right = right .. "  |cff888888next " .. FormatDuration(soon - now) .. "|r" end
        GameTooltip:AddDoubleLine(
            ClassColored(c.name or k, c.class) .. " |cff888888(" .. (c.realm or "?") .. ")|r",
            right, 1, 1, 1, 1, 1, 1)
    end

    local any = false
    for rk, r in pairs(db.mail) do
        if not any then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Mailbox income", 1, 0.82, 0)
            any = true
        end
        GameTooltip:AddDoubleLine(r.name or rk, FormatGold(r.ah + r.other), 1, 1, 1, 1, 1, 1)
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: open window", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Right-click: chat summary", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Drag: move button", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function PrintSummary()
    local db = AuctionTrackerDB
    local now = GetServerTime()
    local keys = SortedCharKeys()
    if #keys == 0 then
        print(PREFIX .. "No data yet.")
        return
    end
    for _, k in ipairs(keys) do
        local c = db.chars[k]
        local live, unsure, sold, _, soon = Counts(c, now)
        local line = string.format("%s (%s): %s", c.name or k, c.realm or "?", LiveText(live, unsure))
        if sold > 0 then line = line .. ", " .. sold .. " sold" end
        if soon then line = line .. ", next expiry in " .. FormatDuration(soon - now) end
        print(PREFIX .. line)
    end
end

local function BuildMinimapButton()
    local b = CreateFrame("Button", "AuctionTrackerMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetTexture("Interface\\AddOns\\AuctionTracker\\icon")
    icon:SetPoint("TOPLEFT", 6, -5)
    local mask = b:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            PrintSummary()
        else
            if AT.frame:IsShown() then AT.frame:Hide() else AT.frame:Show() end
        end
    end)

    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            AuctionTrackerDB.minimap.angle = math.deg(math.atan2(py - my, px - mx))
            UpdateMinimapPos()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    b:SetScript("OnEnter", ShowMinimapTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    AT.mmButton = b
    UpdateMinimapPos()
    if AuctionTrackerDB.minimap.hide then b:Hide() end
end

------------------------------------------------------------
-- Entry in Blizzard's Options > AddOns list (opens our Settings tab)
------------------------------------------------------------
local function RegisterBlizzardOptions()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        return
    end
    local panel = CreateFrame("Frame")
    panel.name = "Auction Tracker"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Auction Tracker")

    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btn:SetSize(200, 26)
    btn:SetPoint("TOPLEFT", 16, -50)
    btn:SetText("Open Auction Tracker settings")
    btn:SetScript("OnClick", function()
        if SettingsPanel then pcall(HideUIPanel, SettingsPanel) end
        AT:OpenSettings()
    end)

    local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, panel.name)
    if ok and category then pcall(Settings.RegisterAddOnCategory, category) end
end

------------------------------------------------------------
-- Events
------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_MONEY")
ev:RegisterEvent("AUCTION_HOUSE_SHOW")
ev:RegisterEvent("AUCTION_HOUSE_CLOSED")
ev:RegisterEvent("OWNED_AUCTIONS_UPDATED")
ev:RegisterEvent("AUCTION_HOUSE_AUCTION_CREATED")
ev:RegisterEvent("AUCTION_CANCELED")
ev:RegisterEvent("MAIL_SHOW")
ev:RegisterEvent("MAIL_CLOSED")
ev:RegisterEvent("MAIL_INBOX_UPDATE")

ev:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        AuctionTrackerDB = AuctionTrackerDB or {}
        local db = AuctionTrackerDB
        db.chars   = db.chars or {}
        db.mail    = db.mail or {}
        -- One-time cleanup: versions 1.2.0 to 1.2.2 could leave an "estimated sales" figure
        -- behind for sales whose mail had already been collected. Those never cleared on
        -- their own, so drop them once; the next mailbox visit restores the real numbers.
        if (db.dataVersion or 0) < 2 then
            for _, c in pairs(db.chars) do
                c.soldInf = nil
                c.soldInfAt = nil
            end
            db.dataVersion = 2
        end

        -- The dated mail income history was removed; delete what earlier versions saved.
        if (db.dataVersion or 0) < 3 then
            db.mailHist = nil
            db.histSince = nil
            db.dataVersion = 3
        end

        db.minimap = db.minimap or { angle = 215 }
        db.collapsed = nil
        db.popup = db.popup or {}

        BuildFrame()
        BuildPopup()
        BuildMinimapButton()
        SetupMailHooks()
        SetupPostHooks()
        RegisterBlizzardOptions()

        C_Timer.After(3, function()
            local now, n, soonest, who = GetServerTime(), 0, nil, nil
            for k, c in pairs(db.chars) do
                local live, unsure, _, _, soon = Counts(c, now)
                n = n + live + unsure
                if soon and (not soonest or soon < soonest) then
                    soonest, who = soon, c.name or k
                end
            end
            if n > 0 and not db.noLoginSummary then
                print(PREFIX .. string.format("%d live auctions across your characters. Next expiry: %s (%s). /at to view.",
                    n, FormatDuration(soonest - now), who))
            end
        end)

    elseif event == "PLAYER_MONEY" then
        OnMoneyChanged()

    elseif event == "AUCTION_HOUSE_SHOW" then
        AT.ahOpen = true
        AT:ShowPopup()
        ScheduleOwnedRefresh()

    elseif event == "AUCTION_HOUSE_CLOSED" then
        AT.ahOpen = false
        AT:HidePopup()

    elseif event == "OWNED_AUCTIONS_UPDATED" then
        lastOwnedUpdate = GetTime()
        QueueScan()

    elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
        OnAuctionCreated(...)
        ScheduleOwnedRefresh()

    elseif event == "MAIL_SHOW" then
        AT.mailOpen = true
        -- An empty mailbox may never fire MAIL_INBOX_UPDATE, which left old sale-mail
        -- figures in place. Scan on open too, once the inbox has had time to load.
        C_Timer.After(0.5, QueueMailScan)
        C_Timer.After(2, QueueMailScan)

    elseif event == "MAIL_CLOSED" then
        AT.mailOpen = false
        mailScanQueued = false

    elseif event == "MAIL_INBOX_UPDATE" then
        QueueMailScan()

    else -- AUCTION_CANCELED
        OnAuctionCanceled(...)
        ScheduleOwnedRefresh()
    end
end)

------------------------------------------------------------
-- Slash commands
------------------------------------------------------------
SLASH_AUCTIONTRACKER1 = "/at"
SLASH_AUCTIONTRACKER2 = "/auctiontracker"
SlashCmdList["AUCTIONTRACKER"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    local cmd, arg = msg:match("^(%S*)%s*(.*)$")

    if cmd == "forget" and arg ~= "" then
        for k in pairs(AuctionTrackerDB.chars) do
            if k:lower() == arg then
                AuctionTrackerDB.chars[k] = nil
                print(PREFIX .. "Removed " .. k)
                AT:Refresh()
                return
            end
        end
        print(PREFIX .. "No character named '" .. arg .. "' (use Name-Realm).")
    elseif cmd == "reset" then
        AuctionTrackerDB.chars = {}
        print(PREFIX .. "All auction data cleared.")
        AT:Refresh()
    elseif cmd == "mailreset" then
        AuctionTrackerDB.mail = {}
        print(PREFIX .. "Mailbox income totals cleared.")
        AT:Refresh()
    elseif cmd == "minimap" then
        local mm = AuctionTrackerDB.minimap
        mm.hide = not mm.hide
        if mm.hide then AT.mmButton:Hide() else AT.mmButton:Show() end
        print(PREFIX .. "Minimap button " .. (mm.hide and "hidden." or "shown."))
        AT:Refresh()
    elseif cmd == "popup" then
        local pp = AuctionTrackerDB.popup
        if arg == "reset" then
            pp.pos = nil
            print(PREFIX .. "Popup position reset.")
        else
            pp.disabled = not pp.disabled
            print(PREFIX .. "Auction House popup " .. (pp.disabled and "disabled." or "enabled."))
            AT:Refresh()
        end
    elseif cmd == "summary" then
        PrintSummary()
    elseif cmd == "settings" or cmd == "options" or cmd == "config" then
        AT:OpenSettings()
    else
        if AT.frame:IsShown() then AT.frame:Hide() else AT.frame:Show() end
    end
end
