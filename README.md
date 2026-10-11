# TransmogKit v0.21.5

Install: replace the `TransmogKit` folder in `World of Warcraft/_retail_/Interface/AddOns/`.

## Inside the transmog window
- **Reskin**: the transmog station opens as one dark, flat window with gold trim. It has four columns: outfits and mounts, preview, Blizzard's collection, and the built-in Set Finder. Blizzard's frame art, portrait and help button are hidden. `/tmk skin` switches between this and the Blizzard look.
- If the window is too wide for your screen, use `/tmk scale 0.85`.
- **Mount strip** (left side, above Purchase Outfit Slot): select an outfit in Blizzard's list, then click Ground, Flying, Swim or Hearth to assign it. Right-click a slot to clear it. Assignments belong to that Blizzard outfit; there are no separate looks.
- **Finder tab** (next to Situations; open by default whenever the transmog window opens; `/tmk side` shows it as a side column instead, `/tmk tab` switches back). It has two modes:
  - **Items**: a grid of 3D models, like Blizzard's Items tab. Pick a slot (Head through Feet, or cycle through weapon types), then filter by **color**, expansion and collected status. The color palette has 60 swatches plus **Custom shade...** for Blizzard's full color picker. The match setting (Exact, Close, Similar or Loose) controls how close a shade must be. Each model shows a strip of its main colors. Click a model to put it on your character exactly like Blizzard's Items tab does. It shows as a pending change until you save the outfit. Ctrl-click to preview an item or Shift-click to link it. Right-click to favorite or unfavorite it. Favorites are shared with Blizzard's Items tab, show a star and sort first. Expansion, weapon type and collected status (Collected or Favorites) are dropdown menus.
  - **Shift-Right-click** a model to save its full color palette (not just its single dominant swatch) as a filter. It works like the color palette but stays active as you click through slot tabs normally — each slot's grid narrows to appearances that match it and ranks them most-similar-first, with a match % badge on each cell. Click the "Like: ..." button, pick a manual color, or choose "Any color" to clear it.
  - **Multiple colors and themes** (Items grid): in the color popup, turn on **Multi-select** (or Shift-click swatches) to pick up to 8 colors; an item must contain all of them (all but one when you pick 3 or more). **Themes** offers common looks such as Black & Gold, Frost, Fel Green & Black or Fire & Ember. Results rank most-similar-first with a match % badge, and the Exact/Close/Similar/Loose setting still applies. "Any color" clears it. Sets view still uses a single color.
  - **Sets**: the class-filtered set list with expansion, PvE/PvP, tier and collected filters. The color filter now uses real piece colors instead of words in set names.

## Anywhere
- **Outfit button**: left-click shows your outfits and right-click opens the Set Finder. Outfits must be on an action bar; a hidden bar works.
- **Macros** `TMK_Mount` and `TMK_Hearth` are shared account (General) macros. Each character rewrites them with its own outfit's mounts on login and whenever the outfit you're wearing changes, so a single bar button works on every character.

## Commands
- `/tmk`: show or hide the Set Finder
- `/tmk macros`: refresh macros for the current outfit
- `/tmk button`: show or hide the outfit button
- `/tmk dock`: turn automatic Set Finder opening on or off
- `/tmk probe`: print outfit function and action bar info
- `/tmk frames`: save the transmog window's frame names so the reskin can be built

## Color data
`TransmogKit_Colors.lua` (about 2 MB) holds the main colors of about 57,000 appearances, taken from each appearance's icon, plus the expansion each one comes from. Icon colors are close to the in-game model but not exact; glowing icon backgrounds can occasionally pull in an extra color.


## v0.12
- Items list newest expansion first (favorites still on top). Filter defaults to Collected; Any removed.
- Hearth list covers 40 hearthstone toys (incl. Preyseeker's) plus a live name scan for newer ones.
- Mount picker shows a Mount Journal-style preview with you riding in your pending look. Hovering a hearth plays its cast effect on the transmog character. Both stop when the picker closes.

## v0.13
- Mount/hearth picker and preview draw above everything and open right above the mount strip.
- Favorite mounts (from the Mount Journal) are starred and listed first.

## v0.14
- Mount preview hides the big character and Finder models while open (3D models ignore layering), restored on close.
- Clicking a slot on the transmog character jumps the Finder to that slot/weapon type and the page with the look you are wearing, highlighted.

## v0.15
- Finder gets a Mounts tab (Ground / Flying / Swim / Hearth). Strip buttons jump to it. Hovering previews the mount with you riding it right on the transmog character; hearths play on the character. Click assigns to the outfit.
- Unusable mounts (class, race, faction) are hidden.
- Fixed empty grid on the first slot click.
- v0.16.1: mounts no longer vanish in no-mount zones (class/race/faction filtering kept).
- v0.16.1: mount/hearth lists are remembered so they still show inside raids; Blizzard Items page no longer pops up under the Finder on slot clicks.

## v0.16
- Title dropdown above the character: pick a title per outfit (or No title / Keep current). It switches automatically when the outfit becomes active.

## v0.17
- Finder Items grid: Shift-Right-click a model to save its full color palette as a sticky filter across slots, ranking each slot's matches most-similar-first with a % badge.
- The "Like: ..." button opens the Exact/Close/Similar/Loose popup instead of clearing the saved palette; only "Any color" (or picking a manual color) clears it.
- When a palette is saved, the "Like: ..." button gets its own full-width row so a long item name doesn't overlap other text; hover it to see the full name if it's still clipped.
- Finder tab is now the tab that's open by default whenever the transmog window opens (position unchanged - still next to Situations).
- Fixed the mount/hearth strip picker showing mounts that are collected account-wide but not actually usable on the current character (e.g. a covenant mount unlocked on a different character) - it now checks the game's own per-character usability flag, not just the account-wide collected flag.

## v0.18
- Color popup: Multi-select (pick several colors) and a Themes menu of common transmog color combinations, in the Items grid.
- Hearth preview now plays each hearth's own character animation (looked up from the game's spell visual data), falling back to the generic casting pose for hearths without one.
- Hearth list now skips toys this character cannot use (e.g. race-locked hearths collected on another character), and adds two hearth toys that were missing (163206, 263489).
- Logging into a character with no mounts/hearths set no longer wipes the shared mount and hearth macros; they stay as the last character left them until that character sets its own. Mount availability now ignores the character's current location.
- Saved mounts/hearths/titles are now matched by outfit name if the game gives an outfit a new ID, and `/tmk kits` prints what is saved for this character (for diagnosing).
- Mount usability is back to the game's own per-character flag (the location-independent check let other classes' mounts through). The macros now follow the worn outfit, and if that outfit has nothing set they keep the last mounts/hearth that were set instead of blanking.
- A character file that holds another character's saved mounts/hearths/titles (e.g. a copied settings file) is detected at login and those settings are set aside instead of being used.
- Picking a mount, hearth or title now prints which outfit it was saved to (`/tmk quiet` turns that off); `/tmk kits` also shows the character and whether the file belongs to it.
- Outfit ID 0 (reported when no outfit is selected) is no longer treated as an outfit, and a line at login says which outfit is worn and whether mounts/hearth were found for it.
- Fixed the mount and hearth pickers coming up empty inside instances: hidden usability data is now treated as unknown instead of blocking the scan.

## v0.19
- Settings are now stored in an account-wide file (one entry per character) instead of relying on each character's own file being writable; existing per-character settings are carried over once. Needs a full game restart after installing. A "storage check" line at login shows whether each file is being kept.

## v0.20
- New **Effects** tab in the Finder: pick a weapon enchant effect (illusion) for the main hand or off hand. Click an effect to apply it to the outfit (pending until you save, like any other change); "Clear effect" removes it; only effects you have collected are listed. Uses the same calls as Blizzard's own effect box.
- Uncollected appearances, sets and effects are no longer listed anywhere in the Finder: only things you own can be shown or applied. The Collected filter now offers Collected or Favorites.
- Effects tab is now a grid of your weapon with each effect applied (like Blizzard's Weapon Enchantment page). Clicking the effect box next to a weapon in the transmog window opens it; clicking a weapon slot goes back to Items. The search box filters effects by name.

## v0.20.2
- Added a pixel-art wardrobe icon (`icon.tga`) shown in the AddOns list.

## v0.21.0
- **Match my outfit's colors**: in the color popup, one button builds a palette from everything on the outfit you are viewing (up to 4 dominant colors) and ranks each slot's pieces against it.
- **Undo** button (bottom right of the Finder): steps back through changes made from the Finder (items and weapon effects) that you have not saved yet. It clears when you save, close the window, or switch outfit.
- **Favorites for weapon effects**: right-click an effect to favorite it; favorites sort first and show a star (shared by all your characters).
- **NEW badge** on appearances you have just collected (the game's own "new" flag). New pieces sort first, and hovering one clears the flag, like Blizzard's tab.
- **More** tab (settings and tools):
  - Options: confirmation messages in chat (off by default, `/tmk verbose` toggles), and whether the Finder opens by default.
  - Export / import an outfit's mounts, hearth and title as a short `TMK1;...` text string.
  - Copy picks from another character: to outfits with the same name, or as your default for outfits with none.
  - Saved looks: save the appearances on the current outfit under a name and load them onto any character. Loaded pieces are pending until you save the outfit, and Undo works on them.

## v0.21.1
- Items grid: slots that can be hidden now show the game's "Hide this slot" option as the first cell (eye icon). Click it to make that slot invisible; Undo works on it. It disappears when a color filter is active, since it has no colors.

## v0.21.2
- Fixed weapon appearances always going on the main hand: for dual-wielders (and anyone with a usable off-hand weapon type) the Finder now applies to the hand selected in the transmog window. New **Main / Off** buttons next to the weapon type menu show and switch which hand a click will change.

## v0.21.3
- Weapon sheathing dropdown (side / back / default) is back, at the bottom left of the Items tab. It appears when the weapon on the selected hand offers more than one option, and uses the same setting as Blizzard's own dropdown.

## v0.21.4
- Fixed many appearances showing as "Appearance ####": the game only knows an item's name once its data has loaded, and the old lookup gave up (and remembered the failure). Names are now requested, kept once found, and the tooltip updates itself when they arrive.
- New **Search by name** box in the Items tab, beside the Expansion / Collected / Color row (on its own row just below it when the window is narrow). It matches any item that shares the look, works together with the color and palette filters, and shows "loading names..." while the game fetches item names.

## v0.21.5
- **Transmog shoulders differently**: on the Shoulders tab, a checkbox at the bottom left turns the split on or off (the same setting as Blizzard's checkbox). While it is on, **Right** and **Left** buttons next to it choose which shoulder a click changes; clicking a shoulder slot on the character does the same. Previously every click went to the right shoulder, so the left one could not be changed on its own.
