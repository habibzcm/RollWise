# Rollwise

A loot roll board for **WoW Forever**. Every Need, Greed and Pass shows up as it happens, grouped the way the game decides the winner: main spec Need, off spec Need, transmog, Greed.

Download it from CurseForge, or grab this repo and copy the `Rollwise` folder into `World of Warcraft\_forever_\Interface\AddOns\`.

## What it does

- **Roll board:** one card per item, docked under the game's Need / Greed window. Picks are grouped by strength with a roll bar for each player, the current leader, and the winner. Main spec / off spec comes straight from the game's own roll state.
- **Your odds:** your chance to win from the picks so far, and an item level check against the piece you'd replace
- **Wishlist:** point at any item (AtlasLoot, auction house, chat) and press your wishlist key. When it drops, its card glows and Rollwise makes sure you notice. Tracks how often it dropped and who got it.
- **Journal:** every decided item per dungeon or raid run, grouped by boss, with search and filters
- **Players tab:** who has won what this run, main spec vs off spec, and who is still empty-handed
- **Quiet chat:** hide your own choices, other players' choices, roll numbers and/or results, everywhere or only in dungeons and raids
- **Recent tray:** the last items to leave the board; click one to see its card again
- **Export** a run as text, CSV or a Discord-ready list
- Three looks (Rollwise, Tooltip, Classic), scale, width, and a board you can move anywhere

Rollwise is read-only: it shows rolls, it never makes them.

Type `/rollwise` in game to open it, or `/rollwise preview` to see the board in action.

## Limits

Inside dungeons and raids the game can hide some roll details from addons. Rollwise marks those as hidden instead of guessing. When a roll only shows up in chat, main spec / off spec can't be known and the pick shows as plain Need.

## Found a bug, or have an idea?

Open an [issue](../../issues). For bugs it helps to include your Rollwise version and the output of `/rollwise diag`.

## License

MIT, see [LICENSE](LICENSE).
