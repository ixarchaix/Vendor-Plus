# VendorPlus Changelog

All notable changes to this addon are recorded here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [1.0.1] - 2026-10-18

Removes the nameplate sparkle feature, which never worked. Only `VendorPlus.lua` changed.

### Removed
- **Nameplate sparkles** around vendors with limited stock, including the `/vp npcsparkle` command and its help line.
- The code that tracked which vendors had limited stock, and the registration for nameplate events.
- The saved settings `npcSparkle` and `limitedNPCs` are deleted from your saved data on login.

The sparkle border on limited-stock rows inside the vendor window is unaffected.

---

## [1.0.0] - 2026-10-18

A full visual redesign of the window, plus support for a newer game client. Both `VendorPlus.lua` and the `.toc` changed.

### Changed
- **New dark navy theme** with a blue accent, flat panels and thin borders throughout the window, replacing the earlier button restyle. This also covers the quantity picker, the switcher bar and the search box.
- **Stat card** at the top of the window showing the item count, with a sub-line ("in stock", "N limited supply", "matching your search", or "recently sold to this vendor" in Buyback). The search box moved into the card and gained a `SEARCH` label.
- **Underline-style Merchant / Buyback tabs** replace the button tabs.
- **Column layout**: the column headers are now `Item`, `Cost`, `Min Buyout`, `Region Avg` and `Sold/Day` (`Region Avg Sale` is shortened to `Region Avg`), with the data columns right-aligned to the edge of the row.
- **Sort arrow** is now a small green arrow drawn next to the active header, replacing the arrow icon.
- **Slim custom scrollbar** replaces Blizzard's scroll frame. The mouse wheel scrolls two rows per notch.
- **Switcher bar** is now a segmented control. Clicking the view you're already in does nothing.
- **Fonts**: the default is now the game's own font (previously Arial Narrow), with light text and muted grey labels. The title is bigger (20 pt) and column headers are 12 pt. `/vp font` still works the same way.
- Window is taller to fit the stat card and tab row.
- Colours for prices, stock counts and placeholders were refined, and VendorPlus's chat messages use a slightly different blue.
- The sparkle stars on limited-stock rows are placed by row width, so they spread evenly across it.
- Game client interface `120105` added to the `.toc` (now `120000, 120001, 120105`).

### Added
- **Quality-coloured icon borders**: each item's icon sits in a thin box coloured by its quality.
- **Lime bar** on the left edge of a row when the region average sale price beats the vendor price, in addition to the green price text.
- The `Buy Limited` button now has a taller, blue accent style.

---

## [0.12.0] - 2026-10-17

A dedicated font set with a `/vp font` command. Only `VendorPlus.lua` changed.

### Added
- **Custom fonts**: VendorPlus now uses its own set of fonts (Arial Narrow by default) instead of Blizzard's stock ones, with white values and small grey labels. This covers the title, item names, costs, prices, buttons, search box, quantity picker and footer.
- `/vp font <path>` switches to a custom `.ttf` file, using the full path (e.g. `Interface\AddOns\MyAddon\Font.ttf`). `/vp font reset` returns to the default. If the font can't be loaded, VendorPlus falls back to the default and says so.
- The chosen font is saved and applied on login.

### Changed
- Column headers are now small upper-case grey labels. The column you're sorting by turns white.
- The window title is smaller (15 pt) and white.

---

## [0.11.0] - 2026-10-17

Buttons get a flat navy look to match the window. Only `VendorPlus.lua` changed.

### Changed
- **Button restyle**: all of VendorPlus's buttons (tabs, Buy Limited, Repair, Sell Junk, and the quantity picker's buttons) are now flat navy with a blue border instead of Blizzard's red button style. They have hover, pressed and disabled looks.
- The close button is now a small matching `X` button, sitting slightly further in from the corner, instead of Blizzard's close button.

---

## [0.10.0] - 2026-10-17

Adds a Buy Limited button. Only `VendorPlus.lua` changed.

### Added
- **Buy Limited** button in the footer, next to your gold. It buys every gold-priced item that still has limited stock, working through them in vendor order for as long as you can afford it.
  - The button shows the total cost, in red when you can't afford everything (in which case it shows what it can buy rather than the full price).
  - A tooltip lists each item and quantity it will buy, the full cost if you're short, and a note that items bought with currency or other items aren't included.
  - It asks for confirmation before buying.
  - Purchases are spaced out slightly, highest vendor slot first so rows that sell out and disappear don't shift the rest.
  - Each purchase is skipped if the item in that vendor slot has changed since the plan was made.
- The button only appears on the Merchant tab when the vendor has at least one such item. It's hidden in Buyback.
- Any open Buy Limited confirmation closes when you switch views or close the vendor.

---

## [0.9.0] - 2026-10-15

Adds a Min Buyout column. Only `VendorPlus.lua` changed.

### Added
- **Min Buyout column** (`DBMinBuyout`), shown between `Cost` and `Region Avg Sale`. Click its header to sort by it like the other columns.

### Changed
- The window is wider (500 to 556 px) to fit the new column, and the `Region Avg Sale` and `Sold/Day` columns have moved right.
- The sparkle stars on limited-stock rows now spread out across the wider row.

---

## [0.8.0] - 2026-10-15

Vendors with limited stock now sparkle in the world too. Only `VendorPlus.lua` changed.

### Added
- **Nameplate sparkles**: a ring of twinkling stars is drawn around the nameplate of any vendor that has at least one item with stock left.
- Vendors are remembered when you open their window. The flag is updated every time the vendor's stock changes, and cleared once the vendor sells out or is no longer limited.
- `/vp npcsparkle` toggles the effect on and off.
- Saved settings `npcSparkle` (on by default) and `limitedNPCs`.

---

## [0.7.1] - 2026-10-15

Cosmetic tweak. Only `VendorPlus.lua` changed.

### Changed
- The sparkle effect on limited-stock rows now has many more stars: 19 spread along the top, bottom and side edges of the row, up from 6. This makes the border look fuller.

---

## [0.7.0] - 2026-10-15

VendorPlus now has its own quantity picker instead of borrowing Blizzard's. Only `VendorPlus.lua` changed.

### Added
- **Custom quantity picker** for Shift-click: a small gold-bordered dialog that opens next to the row, with:
  - `-` and `+` buttons that step by one vendor purchase unit,
  - a typed amount (numeric, up to 5 digits),
  - a `Max` button,
  - mouse-wheel adjustment,
  - a live **Total** cost line, and
  - `Buy` and `Cancel` buttons.
  Enter buys and Escape closes it.
- Stock-shift check: if the item at that vendor slot has changed since the picker opened, nothing is bought and a message tells you to try again.

### Changed
- Shift-click no longer uses Blizzard's stack-split dialog. The old built-in text prompt is no longer used as a fallback.
- The maximum offered is now rounded down to whole purchase units (a vendor selling stacks of 5 offers 5, 10, 15 and so on).
- The picker closes when you switch views or close the vendor.

---

## [0.6.0] - 2026-10-15

Sortable column headers, a draggable window, sparkling limited-stock rows, and more reliable TSM view handling. The Sale Rate column is gone. Only `VendorPlus.lua` changed.

### Added
- **Click-to-sort column headers**: `Item`, `Cost`, `Region Avg Sale` and `Sold/Day`. Click once to sort, again to reverse, and a third time to return to vendor order. An arrow icon next to the header text shows the active column and direction. `Item` and `Cost` sort ascending first, and the data columns sort descending first. Items with no value always sort last.
- **Cost sort** orders by per-item price (price divided by the vendor's stack size).
- **Draggable window**: grab any empty part of the window to move it. The position is saved and kept between sessions, and the window can't be dragged off screen.
- `/vp reset` resets the window position.
- **Sparkle border** on rows with limited stock left: a pulsing gold edge with twinkling stars. It switches off once the stock reaches 0.
- **Auto-fallback from the TSM view**: if you close TSM's window with TSM's own "WOW UI" button, VendorPlus switches to the default UI. It checks twice in a row so that closing the vendor isn't mistaken for this.
- Saved settings `sortDesc` and `pos`.

### Changed
- The **TSM** button in the switcher bar is hidden when TradeSkillMaster isn't loaded, and the bar shrinks to fit.
- If TSM isn't loaded but the TSM view was your saved choice, VendorPlus quietly uses the default UI and keeps your saved choice.
- Column layout adjusted: the `Region Avg Sale` and `Sold/Day` columns are wider, and the Sale Rate space is gone.
- The sort options are now `default`, `name`, `price`, `avg` and `sold`.

### Removed
- **Sale Rate column** and its colour coding, along with the `DBRegionSaleRate` lookup. Existing saves that sorted by rate are reset to vendor order on login.
- The single cycling **Sort:** button. Sorting is now done from the column headers.

---

## [0.5.0] - 2026-10-15

In the TSM view, Blizzard's merchant frame is now hidden properly and the switcher bar stays in one place. Only `VendorPlus.lua` changed.

### Added
- **Click-blocker** over the hidden Blizzard merchant frame while TSM's window is up. Blizzard's frame is invisible in that view, so its item buttons could previously still be clicked by accident. The blocker sits underneath TSM's own window and is removed whenever you leave the TSM view or close the vendor.

### Changed
- In the TSM view, Blizzard's merchant frame is now hidden once TSM's window is actually open (the delayed re-check does this if TSM is slow). It was previously left visible so TSM could use it.
- The switcher bar now sits above the Blizzard merchant frame in both the Default and TSM views, instead of below TSM's window.
- Showing and hiding Blizzard's frame is handled in one place (`SetDefaultHidden`) instead of being repeated across the view code.

---

## [0.4.0] - 2026-10-15

The TSM view now works by driving TSM's own buttons instead of guessing at frame names. Only `VendorPlus.lua` changed.

### Changed
- **TSM view reworked.** VendorPlus now finds the "TSM4" button TSM adds to the merchant frame and clicks it to open TSM's vendor window. To leave the TSM view it clicks the "WOW UI" button in TSM's own header. Buttons are found by their text, so no frame name needs to be known or configured.
- Blizzard's merchant frame is shown untouched while TSM opens its window, since TSM expects it.
- The view switcher bar sits below TSM's window when the TSM view is active, because that window sits at the top of the screen.
- Opening a vendor re-checks the view once after 0.3 seconds, because TSM can open its own window slightly after the merchant opens.
- Switching views is guarded against re-entry, since TSM's buttons can trigger VendorPlus's own hooks.
- If the "TSM4" button can't be found (for example TSM is disabled), VendorPlus falls back to the default UI and prints a one-time hint pointing to `/vp tsmscan`.
- `/vp tsmscan` now reports whether the "TSM4" button on the merchant frame was found, whether TSM's vendor window is open (and its name), and whether its "WOW UI" button was found. It previously listed every top-level frame with `TSM` in its name.

### Removed
- The `/vp tsmframe <name>` command and the `tsmFrame` setting, since they're no longer needed. A previously saved `tsmFrame` value is simply ignored.
- The frame-name scanning from 0.3.0 and 0.3.1.

---

## [0.3.1] - 2026-10-15

Small robustness fix to TSM frame detection. Only `VendorPlus.lua` changed.

### Fixed
- Scanning for TSM's vendor window (used by the TSM view and `/vp tsmscan`) no longer errors on frames that can't be safely inspected, such as protected or restricted ones. Those frames are now skipped.
- Frame-name matching now uses plain-text searches, so special characters in a frame's name can't break the match.

---

## [0.3.0] - 2026-10-15

Adds a vendor-window switcher with TSM support and a proper quantity picker. Only `VendorPlus.lua` changed.

### Added
- **View switcher bar** above the vendor window with three buttons: `Default UI`, `Vendor Plus` and `TSM`. The active view's button is greyed out, and the choice is saved (default: `Vendor Plus`).
- **TSM view**: shows TSM's own vendor window in place of VendorPlus. VendorPlus looks for a top-level frame with `TSM` and `VENDOR` or `MERCHANT` in its name, or uses one you set by hand. If nothing is found it falls back to the default UI and prints a one-time hint.
- **Quantity picker** on Shift-click. It opens Blizzard's stack-split dialog, with a built-in prompt as a fallback if that isn't available. The maximum is capped by the vendor's stock, the stack size and the gold you have, and the amount snaps to whole purchase units.
- Slash commands:
  - `/vp view <default|vp|tsm>` switches the vendor window.
  - `/vp tsmscan` lists top-level frames with `TSM` in the name (run it while TSM's vendor window is open).
  - `/vp tsmframe <name>` sets which frame the TSM view opens (run with no name to clear it).
- Saved settings `view` and `tsmFrame`.

### Changed
- Shift-click no longer buys a full max stack straight away; it opens the quantity picker instead.
- A plain click now buys one vendor purchase unit (the vendor's stack size) rather than a quantity of 1.
- Purchase confirmation now shows the quantity and the total cost (e.g. `Item x20`) instead of just the unit price.
- Tooltip hint now reads "Click: buy | Shift-click: choose quantity".
- Opening a vendor now goes through the view system rather than always showing the VendorPlus window.
- Closing the vendor also closes the quantity prompt and hides the switcher bar.
- `VP:Buy(e, maxStack)` is replaced by `VP:BuyQuantity(e, qty)`.

---

## [0.2.0] - 2026-10-14

Small fix so slow-selling items still show TSM data. Only `VendorPlus.lua` changed.

### Fixed
- **Sold/Day and Sale Rate showed `--` for slow-selling items.** TSM custom prices are rounded to whole numbers, so tiny values (e.g. 0.05 sold/day) collapsed to 0 and came back empty. Both are now requested as `value * 1000` and scaled back down, falling back to the plain value if that fails (new `TSMFractional` helper).

### Changed
- Sold/Day below 1 per day is now shown with 3 decimals (e.g. `0.050/d`). Values of 1 or more keep their previous formatting.
- Sale Rate below 1% is now shown with 2 decimals (e.g. `0.35%`) instead of 1.

---

## [0.1.0] - 2026-10-14

Initial release.

### Added
- Replaces the default merchant window with a searchable list, layered over Blizzard's merchant frame (kept alive but invisible).
- **Merchant** and **Buyback** tabs.
- **Search** box filtering items by name.
- TSM region data next to every item:
  - Region average sale price (`DBRegionSaleAvg`), shown green when it beats the vendor's per-item cost.
  - Region sale rate (`DBRegionSaleRate`), colour-coded green at 30% or more, yellow at 8% or more, red below.
  - Region sold per day (`DBRegionSoldPerDay`).
- Sort button cycling through Vendor order / Avg sale / Sale rate / Sold per day.
- Click to buy, Shift-click to buy a max stack. Purchases above a gold threshold (default 1000g) ask for confirmation, and items with extended costs always confirm.
- Click to buy back in Buyback mode.
- Item tooltips, chat linking and dressing-room support via `HandleModifiedItemClick`.
- Extended cost display (currency / item icons), "N left" stock counts, and a red price when you can't afford it.
- Repair All button (with cost) and Sell Junk button.
- Current gold display.
- Support for both the old global merchant API and the newer `C_MerchantFrame` API.
- Warning when TradeSkillMaster isn't detected.
- Slash commands (`/vp`, `/vendorplus`): `toggle`, `divisor <n>` (scales Sold/Day), `confirm <gold>`.
- Saved variable `VendorPlusDB`, with TradeSkillMaster as an optional dependency.
