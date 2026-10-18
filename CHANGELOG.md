# Changelog

All notable changes to **Auction Tracker** are recorded in this file.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [5.0.3] - 2026-10-18

### Fixed
- **Mail figures now reset when you open an empty mailbox.** The mailbox was
  only read when the game sent `MAIL_INBOX_UPDATE`, and that event may never
  fire for an empty inbox (or can fire before the addon is ready). The old
  "Sales waiting in mail" and Sold figures then stayed on the character.
  Opening the mailbox now also queues a scan, 0.5 and 2 seconds after
  `MAIL_SHOW`, so the inbox has time to load. The existing scan on
  `MAIL_INBOX_UPDATE` is unchanged.
- **Collected expired auctions no longer stay in the Expired column.** The
  red Expired count only cleared at the next Auction House scan, even after you
  had taken the returned items from the mailbox. Now, at each mailbox scan, the
  inbox's "Auction expired" mails are counted. If the whole inbox was read and
  holds fewer of them than the list has expired auctions, the extra expired
  auctions (earliest first) are removed. This happens when the mailbox is
  opened, with no Auction House visit needed. Nothing is removed if the inbox
  was only partly shown.
- A scan queued just before the mailbox closes no longer blocks the next
  scan from being queued.

### Notes
- Scans still only run while the mailbox is open, and are still held back
  while a gold take is in progress.
- `.toc` version updated to 5.0.3.

## [5.0.2] - 2026-10-16

### Removed
- **Dated mail income history.** The hourly record that 5.0.1 started saving
  again is gone, because nothing in the window used it. Collecting mail gold no
  longer writes to it, and "Clear mail income" and `/at mailreset` no longer
  touch it.
- **Saved history is deleted once.** On the first login with this version,
  `mailHist` and `histSince` are removed from the saved data (`dataVersion` 3),
  which frees the space they used. This covers history saved by 4.1.0, 5.0.1
  and any build in between.

### Notes
- Nothing visible changes. Mail income totals, the Sold fixes from 5.0.1 and
  everything else are unchanged.
- A saved `mailRange` value from 4.1.0 is not deleted. It is still unused.

## [5.0.1] - 2026-10-16

Fixes to the Sold figures, which could stay too high after sales were collected.

### Fixed
- **Collecting a sale mail now updates Sold straight away.** Before, Sold was
  only corrected at the next mailbox scan, which might never run if the mailbox
  was closed or the game exited first. Now, when a sale mail's gold is taken:
  - its waiting-mail record is removed, and the waiting count, gold and soonest
    expiry are recalculated
  - the matching auction is removed from the list. If the sale arrived after the
    last Auction House scan, that is the entry most likely to be it. If not, an
    estimated sale is used up first, then an auction the Auction House listed as
    sold.
- **Estimated sales no longer linger.** They now expire after 30 days, the same
  life as a sale mail. They are also reset when the mailbox is scanned.
- **Waiting sales past 30 days are ignored.** A sale mail that has passed its
  30 days is no longer counted as waiting, in the Sold column or in the tooltip.
- **Mailbox scan waits for a take to finish.** If gold is still being taken
  from the inbox, the scan retries a second later instead of reading a
  half-updated inbox.
- **One-time cleanup of stale estimates.** On the first login with this
  version, leftover estimated-sales figures from earlier builds are cleared
  (`dataVersion` 2). The next mailbox visit restores the real numbers.
- The comparison of "collected mails" at each mailbox scan was removed, since
  collection is now handled when the gold is taken.

### Changed
- **Hourly income history is recorded again.** It is filed under the hour the
  mail arrived (from its days-left value) instead of when it was collected, and
  old data is trimmed on login (about 400 days kept). Nothing in the window
  shows it yet; the code says it is kept so period views can be added later.
  "Clear mail income" and `/at mailreset` clear it again too.

## [5.0.0] - 2026-10-16

### Added
- **Estimated sales from the auction list.** If an auction disappears from your
  owned-auction list before its earliest possible expiry, it can't have expired,
  and cancellations are already removed by the cancel event, so it is counted as
  a sale.
  - This is only trusted when the game says it sent the complete list.
  - Sale mails that arrived since the previous scan and are still waiting are
    already counted, so they are subtracted to avoid double counting.
  - The estimate is stored per character (`soldInf`) and added to the Sold
    column. It is also used for characters with no mailbox data yet.
  - The estimate resets to 0 the next time that character's mailbox is scanned,
    since the mailbox then shows the real number.
- **Estimate line in the row tooltip.** Hovering a character row now also shows
  "Estimated sales not yet in mailbox check", with a note that these are
  auctions that left the list before they could have expired. The tooltip now
  appears even if the mailbox has never been checked.

### Removed
- **Period selector on the Mail income tab** (1D to All), added in 4.1.0, along
  with the saved `mailRange` choice.
- **Hourly income history**, the "Period data starts <date>" note and the
  "No mailbox income in this period." message.
- The Mail income stat card goes back to showing only the realm total, with no
  period description under it. Realms with no income are listed again.
- "Clear mail income" and `/at mailreset` no longer touch history. Any
  `mailHist`, `histSince` and `mailRange` data already saved stays in the saved
  variables, is no longer read, and is no longer trimmed.

### Notes
- The pinned "All Realms" row from 4.1.0 stays.
- An unused constant (`PIN_H`) was removed.

## [4.1.0] - 2026-10-16

### Added
- **Period selector on the Mail income tab.** A "Period" dropdown at the top
  right of the tab filters mail income by time range: 1D, 1W, 1M, 3M, 6M, 1Y or
  All. The choice is saved in `AuctionTrackerDB.mailRange`, and the default is
  All.
  - The Mail income stat card shows the total for the chosen period, with a
    short description under it (for example "Last 7 days").
  - Realms with no income in the period are hidden, and an empty period shows
    "No mailbox income in this period."
  - The dropdown closes when you click anywhere else or when the window closes.
- **Hourly income history.** Each time mail gold is collected, it is also added
  to an hourly record per realm (AH sales, number of sales, other mail). This is
  what the periods other than All are built from. History older than about 400
  days is dropped on login.
  - All still uses the running totals, so it includes everything from before
    the history existed.
  - History starts on the date this version was first loaded
    (`AuctionTrackerDB.histSince`). If a period reaches back before that date, a
    note appears beside the dropdown, "Period data starts <date>".
- **Pinned "All Realms" row.** When more than one realm is shown, the combined
  total sits above the list and stays in place while you scroll and sort. It
  replaces the "All realms" row that used to sit at the bottom.

### Changed
- The list area starts lower and the scrollbar is adjusted to match while the
  pinned row is shown.
- "Clear mail income" in Settings and `/at mailreset` now also clear the hourly
  history and reset the history start date.

## [4.0.0] - 2026-10-16

### Removed
- **"Other mail" column** on the Mail income tab. The columns are now Realm,
  AH sales and Total. The total still includes other mail, so the Total
  amounts are the same as before.
  - A saved sort on the removed column is repaired automatically on load.
- **"AH sales" line** under the Mail income stat card. The card now shows only
  the total for the current realm.

### Reverted
- The 3.4.1 popup changes. The Auction House popup is back to:
  - the `HIGH` frame strata, with no raised frame level or top-level setting,
    so the Auction House window can cover it again
  - a default position just above the top-right corner of the Auction House
    window, falling back to near the top of the screen
- The 3.4.1 `.toc` author and Notes changes. The author is "You" again, and the
  Notes line is back to the longer description that mentions the popup, mail
  income and the minimap button.

## [3.4.1] - 2026-10-15

### Changed
- **Auction House popup now draws on top.** It uses the `FULLSCREEN_DIALOG`
  strata at frame level 100 and is set as a top-level frame, so it sits above
  the Auction House window and above the addon's own main window. Before it used
  the `HIGH` strata.
- **New default popup position:** top centre of the screen. Before, it sat just
  above the top-right corner of the Auction House window (with a fallback near
  the top of the screen). A position you saved by dragging is still used, and
  `/at popup reset` returns to the new default.
- **`.toc` details:**
  - the author is now `ix_archaix` (was `You`)
  - the Notes line is shortened to "Tracks your active auctions across all
    realms."

## [3.4.0] - 2026-10-15

### Added
- **Mailbox scanning for sold auctions.** When you open a mailbox, the addon
  reads the inbox and counts auction-sale mails that still hold gold. This feeds
  the Sold column, so sales show up even if you never reopened the Auction House
  after they sold.
  - It uses the mail's days-left value to work out when each sale mail arrived.
    Mail lasts 30 days.
  - It records the count, the gold waiting, the soonest mail expiry and when the
    mailbox was last checked. This is saved per character in the `mail` field of
    the character's data.
  - A character is not added to the list just for opening a mailbox, unless it
    has sale mails waiting.
  - If the inbox holds more mail than is shown, only the visible mails are
    counted, and the tooltip says so.
- **Collected sales are removed.** If fewer sale mails are waiting than at the
  previous mailbox check (and the Auction House wasn't scanned in between), the
  matching auctions are dropped from the list. Auctions already expired are
  removed first, then the earliest-ending ones.
- **Mail tooltip on character rows.** Hover a character row on the Auctions tab
  to see:
  - sales waiting in mail
  - gold waiting
  - how soon the first of those mails expires
  - how long ago the mailbox was checked
  Nothing shows if no sales are waiting.
- New events registered: `MAIL_SHOW`, `MAIL_CLOSED` and `MAIL_INBOX_UPDATE`.

### Changed
- **Counts are now corrected using the mailbox.** Live, Unsure, Sold and Expired
  numbers use a new `Counts()` function instead of `Stats()` directly. A sale
  mail that arrived after the last Auction House scan belongs to an auction the
  saved list still counts as expired, unsure or live. That auction is moved out
  of those counts and into Sold. Sold is the larger of the sold-auction count
  from the list and the number of sale mails waiting.
- The corrected counts are used everywhere they appear:
  - the Auctions tab and its sorting
  - the stat cards
  - the Auction House popup
  - the minimap tooltip
  - the login chat summary and `/at summary`

## [3.3.0] - 2026-10-15

### Added
- **Separate Sold and Expired columns** on the Auctions tab. The columns are now
  Character, Live, Sold, Expired, Next expiry and Scanned.
  - Sold shows in green and Expired in red. A dash is shown when the count is 0.
  - Both columns are sortable and start in descending order.

### Changed
- **Live column** now always shows the live count, with "+N?" for unsure
  auctions. The 3.2.1 behaviour of showing the red expired count there when
  nothing was live is replaced by the new Expired column.
- The main window is wider, 700px instead of 620px, to fit the extra columns.
- The list layout code now handles up to five right-hand columns instead of
  three. The Mail income tab is unchanged.

## [3.2.2] - 2026-10-15

### Changed
- **Next expiry column.** When a character has no running auctions but had
  auctions logged that have since expired, the column now shows a red
  "Expired" instead of a dash. This goes with the red expired count added to
  the Live column in 3.2.1.
- **Sorting by Next expiry.** Characters with only expired auctions now sort as
  the soonest expiry, so they appear first in ascending order. Before, they
  were grouped with characters that have no data and sank to the bottom.

## [3.2.1] - 2026-10-15

This build is the 3.1.1 code plus the fixes below. It does not
contain the 3.2.0 gold retheme, so compared with 3.2.0 that retheme is undone.

### Fixed
- **Saved auctions could be wiped by an empty scan.** The owned-auctions update
  event can fire at other times, such as on login, with an empty list, and that
  list would replace the auctions saved earlier. Two guards were added:
  - scans are ignored unless the Auction House is open
  - an empty list is ignored until the full owned-auction results have arrived
    (`HasFullOwnedAuctionResults`)

### Changed
- **Auctions tab count.** When a character has no running auctions but had
  auctions logged that have since expired, the Live column now shows the expired
  count in red. Before, it showed a 0.

### Reverted
- The 3.2.0 gold and leather look, back to the blue-grey look:
  - colour scheme, row shading, scrollbar and hover colours
  - the flipping title-bar coin, the Morpheus title font and the random tagline
  - the icons on the stat cards, the coin in the AH popup (the popup is back to
    270px wide) and the coin-shaped checkmarks
  - gold amount text, the gold chat prefix and minimap tooltip, and the gold
    addon title in the AddOns list
  - the friendlier empty-state messages ("The ledger is empty!" and "No gold in
    the ledger yet!")

## [3.2.0] - 2026-10-14

A visual retheme: the blue-grey look is replaced by a gold and leather
"goblin trader" style.

### Added
- **Animated gold coin** in the title bar that flips every couple of seconds. It
  plays while the window is open and stops when it closes.
- **Random tagline** next to the title, picked each time the window opens
  (for example "Every coin counts." and "Mind the undercutters.").
- **Icons on the stat cards:** a note for Live auctions, a pocket watch for Next
  expiry and a coin for Mail income. The card text is narrower to make room.
- **Coin icon in the AH popup.** The popup is wider, 310px instead of 270px.
- **Coin-shaped checkmarks** in the Settings tab, in place of the plain tick.
- Thin gold line along the bottom of the title bar.

### Changed
- **Colour scheme.** The window now uses:
  - dark leather backgrounds and cards
  - a gold accent and a faint gold border
  - parchment-coloured text
  - orange for warnings and goblin green for good values
- Title is drawn in gold using the Morpheus font, with a fallback to the
  standard font if that font is not available.
- Gold amounts are shown in gold text.
- Gold-tinted row shading, scrollbar, and button and checkbox hover colours,
  replacing the white tints.
- Chat messages and the minimap tooltip use gold in place of blue.
- The addon name in the AddOns list is gold (`.toc` title).
- Friendlier empty-state messages: "The ledger is empty!" on the Auctions tab
  and "No gold in the ledger yet!" on the Mail income tab.

## [3.1.1] - 2026-10-14

### Fixed
- The hover x on character rows (the "forget this character" button) now checks
  the mouse position with the frame's own `IsMouseOver()` method instead of the
  global `MouseIsOver()` function. This is a small compatibility fix for newer
  game clients, which no longer provide the old global. It affects the three
  places that show or hide the x as the mouse enters and leaves a row.

## [3.1.0] - 2026-10-14

### Added
- **Sortable columns.** Click any column header on the Auctions or Mail income
  tab to sort by it. Clicking the active column again flips the direction.
  - The active column is highlighted and shows an up or down arrow.
  - Auctions tab columns: Character, Live, Next expiry, Scanned. Mail income
    tab columns: Realm, AH sales, Other mail, Total.
  - Each column has a sensible first direction. Name, next expiry and scanned
    start ascending. Live, AH sales, other mail and total start descending.
  - Characters with no expiry or no scan time always sink to the bottom.
  - The choice is saved per tab in `AuctionTrackerDB.sort`. Default is
    Character A-Z for Auctions and Total high-to-low for Mail income, and bad
    saved values are repaired.
- **Settings tab** in the main window, with:
  - checkboxes for the Auction House popup, the minimap button, and a new
    "Chat summary at login" option (saved as `AuctionTrackerDB.noLoginSummary`)
  - buttons for Reset popup position, Clear mail income and Clear auction data;
    the two clear buttons ask for confirmation first
  - a hint about forgetting a single character
- **Forget a character from the list.** Hover a character row on the Auctions
  tab to reveal an x after the name. Clicking it asks for confirmation, then
  removes that character. Its auctions return the next time the Auction House
  is opened on that character.
- **Blizzard options entry.** Auction Tracker now appears under
  Options > AddOns, with a button that opens the Settings tab.
- `/at settings` (also `/at options` and `/at config`) opens the Settings tab.

### Changed
- `/at minimap` and `/at popup` now refresh the window, so the Settings
  checkboxes stay in sync.
- The login chat summary can now be switched off.
- The scrollbar and column header bar are hidden while the Settings tab is open.

## [3.0.0] - 2026-10-14

### Removed
- **Window artwork.** The images on the left and right edges of the main window
  (added in 2.1.0, mirrored in 2.2.0) are gone, along with the `/at art` command
  and the draggable art frames.
- `bruto.tga` is no longer shipped. `icon.tga` is unchanged.

### Notes
- `AuctionTrackerDB.hideArt` may still be present in saved data. It is no longer
  read.
- Everything else, including the custom minimap and addon icon, is unchanged.

## [2.2.0] - 2026-10-14

### Added
- **Mirrored artwork on both sides of the window.** The same image now also
  appears on the left edge, flipped horizontally, so the window is framed on
  both sides. Dragging either image moves the window, and `/at art` shows or
  hides both.

### Changed
- `bruto.tga` was replaced with an updated image. It is the same file size, and
  the artwork is now drawn to account for the border, shadow and transparent
  padding built into the texture. The artwork frame grew from 254×320 to 299×366.
- Auctions tab: the "N sold" and "N expired" labels next to each character name
  were removed. Rows now show only the character and realm, plus the live count,
  next expiry and last-scan columns.
- Mailbox tab: the "since <date>" label next to each realm name was removed.

## [2.1.0] - 2026-10-14

### Added
- **Instant count updates while posting and cancelling.** The addon now updates
  its own saved list straight from the post and cancel events, so the displayed
  active-auction count changes immediately instead of waiting for the next
  Auction House query.
  - Hooks `C_AuctionHouse.PostItem` and `PostCommodity` to remember the chosen
    duration (12h / 24h / 48h) for each post.
  - On `AUCTION_HOUSE_AUCTION_CREATED`, a pending entry is added with an exact
    expiry when the duration is known. If it is not known, the expiry is
    estimated as between 12h and 48h until the next real scan.
  - On `AUCTION_CANCELED`, the cancelled auction is removed right away.
- **Window artwork.** An image is attached to the right edge of the main window.
  Drag it to move the window.
  - `/at art` shows or hides it. The choice is saved in `AuctionTrackerDB.hideArt`.
  - New files: `bruto.tga` (the artwork, about 1 MB) and `icon.tga`.

### Changed
- **Custom addon icon.** The minimap button and the TOC `IconTexture` now use
  `icon.tga` instead of the stock coin icon. The minimap icon is slightly larger
  (20px, was 17px) and drawn with a circular mask.
- **Lower Auction House query rate.** The reconcile query is now sent at most
  once every 5 seconds (was a 1.5s debounce). If a refresh is already scheduled,
  new events no longer push it back. The existing skip-if-someone-else-refreshed
  and busy-retry checks stay.
- Scans keep auctions posted in the last 20 seconds that the server list does not
  include yet, so the count no longer dips right after posting.
- The event handler now passes event arguments through, so created and cancelled
  events can use the auction ID.

## [2.0.1] - 2026-10-14

Reduces how often the addon queries the Auction House, so it does not compete
with other addons (e.g. TSM mass-posting).

### Changed
- Opening the Auction House no longer requests owned auctions immediately. The
  request is scheduled and sent after 1.5 seconds.
- After an auction is created or cancelled, the refresh is now debounced.
  Further events restart a 1.5s timer, so the query waits for a quiet moment.
  This replaces 2.0.0's immediate request plus 1-second follow-up.
- Before querying, the addon checks whether another addon or Blizzard's UI
  already refreshed the owned-auction list since the event. If so, it skips its
  own query.
- If the Auction House is busy (`IsThrottledMessageSystemReady` is false), the
  refresh is rescheduled instead of sent.
- A pending refresh is dropped if the Auction House has closed.

### Added
- `ScheduleOwnedRefresh()` plus `AT.ahOpen` and `lastOwnedUpdate` state to
  support the above.

## [2.0.0] - 2026-10-14

### Added
- **Auction House popup.** A small movable panel appears when the Auction House
  opens and hides when it closes. It shows:
  - the current character's active auction count (with "+N unsure" when only a
    time band is known)
  - the next expiry across all characters, colour-coded, with the character name
- Clicking the popup toggles the main window. Drag it to move it; the position
  is saved.
- `/at popup` toggles the popup on or off.
- `/at popup reset` clears the saved popup position.
- New saved variable table `AuctionTrackerDB.popup` (`pos`, `disabled`).
- Expiry colour helper: green above 2h, amber under 2h, red under 30m. Used in
  the popup, the main window rows and the "Next expiry" stat card.
- Shared `CloseButton` helper, used by the main window and the popup.
- Registered the `AUCTION_HOUSE_CLOSED` event.
- Auctions tab now has a one-line-per-character layout with columns
  **CHARACTER / LIVE / NEXT EXPIRY / SCANNED**. Sold and expired counts show
  next to the character name, and rows alternate shading.
- TOC `## Notes` now mentions the Auction House popup.

### Changed
- Main window is smaller: 680×540 → 620×460.
- The post-create / post-cancel refresh now re-queries immediately, then once
  more after 1 second (previously only after 1 second).
- Owned-auction scan debounce reduced from 0.5s to 0.2s.
- Empty-state text rows use a default height of 60 (was 44), so the explicit
  height arguments were dropped.
- Mailbox total row now uses the card background colour in place of the removed
  header colour.
- Window layout code simplified:
  - rows are plain frames rather than buttons
  - `ApplyLayout` resets text and colours in a loop
  - the scrollbar drag calculation was tidied
  - a section comment was renamed from "Frame construction" to "Main window"
- `db.collapsed` is cleared on load, since characters can no longer be collapsed.

### Removed
These 1.0.0 features are gone in 2.0.0:
- Per-auction rows under each character, including item name, quantity, buyout
  price, and the "Sold / Collect from mail" and "Expired" states.
- Item icons and item tooltips on hover.
- The time-left progress bar under each auction.
- Exact vs. estimated time-left display per auction (e.g. `<2h (est.)` and
  `1h - 3h` ranges).
- Collapse/expand of characters in the Auctions tab (the arrow toggle).
- The TOC note "time remaining to the minute".
- Unused code: `ROW_H`, the `header` colour, `ItemDisplay`, `ItemIcon`,
  `SetBar`, `SetAuctionRow` and the `auction` column set.
- Scans no longer store `link`, `itemID`, `qty` or `buyout` for each auction.
  Only `id`, `sold` and the expiry data are kept.

### Notes
- Existing 1.0.0 SavedVariables load fine. Old per-auction fields stay in the
  saved data but are no longer read or refreshed.

## [1.0.0] - 2026-10-14

Baseline version. No earlier history was provided, so this entry only describes
the state compared against.

- Tracks active auctions across all characters, with time remaining to the
  minute.
- Auctions tab lists every auction per character: item with icon and tooltip,
  quantity, price, and time left with a progress bar. Characters can be
  collapsed.
- Per-realm mailbox income tracking.
- Minimap button.
- Slash commands: `/at` (toggle window), `/at summary`, and minimap toggle.
