# TransmogKit

Map mounts and hearthstones to your transmog outfits, and find the look you want with a color-aware Finder built into the transmog window.

Auto-updates one mount macro and one hearth macro per character, so a single bar button works on every character.

**Optional companion:** [TransmogKit - Auction Source Finder](https://github.com/EnosDei/TransmogKit_AuctionSource) adds an Expansions tab to the Auction House.

## Install

- **CurseForge app:** search for *TransmogKit* and install.
- **Manual:** download the latest zip from the [Releases page](https://github.com/EnosDei/TransmogKit/releases) and extract the `TransmogKit` folder into `World of Warcraft/_retail_/Interface/AddOns/`. Do a full game restart after updating.

## Features

### Transmog window
- **Reskin:** the transmog station opens as one dark, flat window with gold trim and four columns: outfits and mounts, preview, Blizzard's collection, and the built-in Set Finder. Blizzard's frame art, portrait and help button are hidden. `/tmk skin` switches between this and the Blizzard look. If the window is too wide for your screen, use `/tmk scale 0.85`.
- **Mount strip** (left side, above Purchase Outfit Slot): select an outfit in Blizzard's list, then click Ground, Flying, Swim or Hearth to assign it. Right-click a slot to clear it. Assignments belong to that Blizzard outfit; there are no separate looks.
- **Title dropdown** above the character: pick a title per outfit (or No title / Keep current). It switches automatically when the outfit becomes active.

### Finder tab
Next to Situations, open by default whenever the transmog window opens. `/tmk side` shows it as a side column instead, `/tmk tab` switches back. Only things you own are listed.

- **Items:** a grid of 3D models, like Blizzard's Items tab. Pick a slot (Head through Feet, or cycle through weapon types), then filter by **color**, expansion and collected status (Collected or Favorites).
  - Click a model to put it on your character; it stays pending until you save the outfit. Ctrl-click to preview, Shift-click to link, right-click to favorite or unfavorite (shared with Blizzard's Items tab; favorites show a star and sort first).
  - The color palette has 60 swatches plus **Custom shade...** for Blizzard's full color picker. The match setting (Exact, Close, Similar or Loose) controls how close a shade must be. Each model shows a strip of its main colors.
  - **Shift-Right-click** a model to save its full color palette as a filter that stays active across slot tabs. Each slot's grid narrows to matching appearances, ranked most-similar-first with a match % badge. Click the "Like: ..." button, pick a manual color, or choose "Any color" to clear it.
  - **Multi-select** (or Shift-click swatches) picks up to 8 colors; an item must contain all of them (all but one when you pick 3 or more). **Themes** offers common looks such as Black & Gold, Frost, Fel Green & Black or Fire & Ember.
  - **Match my outfit's colors** builds a palette from the outfit you are viewing (up to 4 dominant colors) and ranks each slot's pieces against it.
  - **Search by name** box, **NEW badge** on freshly collected appearances, a **Hide this slot** cell for hideable slots, **Main / Off** hand buttons, weapon sheathing dropdown, and a left/right shoulder split.
  - **Undo** (bottom right) steps back through changes made from the Finder that you have not saved yet.
- **Sets:** the class-filtered set list with expansion, PvE/PvP, tier and collected filters. The color filter uses real piece colors.
- **Mounts:** Ground / Flying / Swim / Hearth tabs. Hover to preview the mount with you riding it on the transmog character; hearths play their own cast animation. Click to assign to the outfit. Mounts you can't use (class, race, faction) are hidden, and favorite mounts are starred and listed first.
- **Effects:** pick a weapon enchant illusion for the main or off hand. Right-click to favorite. Uses the same calls as Blizzard's own effect box.
- **More:** options, export / import an outfit's mounts, hearth and title as a short `TMK1;...` string, copy picks from another character, and saved looks you can load onto any character.

### Anywhere
- **Outfit button:** left-click shows your outfits and right-click opens the Set Finder. Outfits must be on an action bar; a hidden bar works.
- **Macros** `TMK_Mount` and `TMK_Hearth` are shared account (General) macros. Each character rewrites them with its own outfit's mounts on login and whenever the outfit you're wearing changes.

## Commands

| Command | What it does |
| --- | --- |
| `/tmk` | Show or hide the Set Finder |
| `/tmk macros` | Refresh macros for the current outfit |
| `/tmk button` | Show or hide the outfit button |
| `/tmk dock` | Turn automatic Set Finder opening on or off |
| `/tmk skin` | Switch between the reskin and the Blizzard look |
| `/tmk scale <n>` | Scale the window (for example `/tmk scale 0.85`) |
| `/tmk side` / `/tmk tab` | Show the Finder as a side column / as a tab |
| `/tmk verbose` / `/tmk quiet` | Turn chat confirmation messages on or off |
| `/tmk kits` | Print what is saved for this character (diagnostics) |
| `/tmk probe` | Print outfit function and action bar info (diagnostics) |
| `/tmk frames` | Save the transmog window's frame names (diagnostics) |

## Color data

`TransmogKit_Colors.lua` (about 2 MB) holds the main colors of about 57,000 appearances, taken from each appearance's icon, plus the expansion each one comes from. Icon colors are close to the in-game model but not exact; glowing icon backgrounds can occasionally pull in an extra color.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE) © EnosDei
