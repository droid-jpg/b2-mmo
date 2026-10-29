# Black 2 MMO

**Play Pokémon Black 2 online with your friends, all in the same Unova.**

Black 2 MMO is a mod for Pokémon Black 2 on the [BizHawk](https://github.com/TASEmulators/BizHawk)
emulator. Everyone plays their own game, and everyone sees everyone else walking around in it, as
real trainers, in real time. It's the Black 2 version of [ORAS MMO](https://github.com/droid-jpg/oras-mmo)
and speaks the same network protocol.

<p align="center">
  <img src="docs/screenshots/friends.png" width="49%" alt="Two friends, Ann and Cal, walking and running in Nimbasa City with their names above their heads">
  <img src="docs/screenshots/challenge.png" width="49%" alt="You are challenged by PKMN Trainer Ann!">
</p>

## What you can do

- **See each other.** Friends on your map show up as their own trainer (Nate or Rosa), walking, running and turning as they do in their game, with their name above their head.
  They block your way like any trainer.
- **Talk to each other.** Walk up to a friend and press **A**: you see their greeting, and they
  see that you're talking to them.
- **Battle a friend's team.** In the Black 2 MMO window, pick a friend and **Battle their team**:
  a real trainer battle against their party, under their name ("You are challenged by PKMN Trainer
  Ann!"), played by the game's AI. Win or lose, your party, EXP and money are put back afterwards.
- **Trade.** In the window, both of you offer a Pokémon and press **Accept**; the server swaps them
  in both games at once.
- **Chat.** Type in the window. `/who` lists who's online and where.
- **Follow each other.** Hold **Tab** for the list of players and the town or route each one is
  on. You get a notice when a friend joins, arrives on your map, catches a Pokémon, evolves one or
  earns a badge.

## What you need

- [BizHawk](https://github.com/TASEmulators/BizHawk/releases) 2.9 or newer (Windows)
- **Your own** copy of Pokémon Black 2 (USA) as an `.nds` file (nothing from the game is included here)
- One person in the group hosts the server: that needs [Node.js](https://nodejs.org) 18 or newer

## Install

1. Download `b2-mmo-…-windows.zip` from the [latest release](https://github.com/droid-jpg/b2-mmo/releases/latest)
   and unzip it.
2. Double-click **Install Black 2 MMO.bat**. It asks for your name, the server address, a room code,
   where BizHawk is and where your ROM is.
3. Double-click **Play Black 2 MMO.bat**. BizHawk starts the game with the mod and opens the
   Black 2 MMO window next to it.

To change anything later (a wrong ROM or BizHawk path, your name, the server), run
**Install Black 2 MMO.bat** again: it remembers your answers, so press Enter on the ones you keep.

## Hosting a game

One person double-clicks **Start server.bat** (in the zip). It prints the address everyone else
types in when installing.

- **Same Wi-Fi / house:** that's it.
- **Over the internet:** the easiest way is [Tailscale](https://tailscale.com) (free) on everyone's
  computer, then use the host's Tailscale address. Or forward TCP port **7777** on the host's router.

Everyone who types the same room code ends up in the same world.

## Good to know

- It's early. Expect rough edges, and back up your save before playing.
- Pokémon Black 2 (USA) only for now (not White 2 or other languages yet).
- Trades are the mod's own, not the game's link trade: no trade evolutions yet.
- Battles have the game's AI play your friend's team; there are no live player-vs-player battles yet.

Found a bug? [Open an issue](https://github.com/droid-jpg/b2-mmo/issues).

---

## For developers

| Folder | What's in it |
|---|---|
| `arm/` | The code that runs inside the game (C, ARMv5TE Thumb): reports the player, shows friends as the game's own other-player actors, swaps parties for trades and battles |
| `lua/` | The BizHawk script: injects `arm/`, networking, names over heads, notices, the window (chat, trading, battles) |
| `server/` | The relay server, Node with no dependencies: `node server/server.mjs [port]` |
| `tools/` | `fakefriend.mjs`, a test player that joins a room and walks, chats, trades and lends its team |
| `package/` | The Windows installer and launchers that go in the zip |
| `scripts/` | Build, packaging and the generators for the zone and species tables |
| `docs/` | [`NOTES.md`](docs/NOTES.md): how it was reverse-engineered and how it works |

[`PROTOCOL.md`](PROTOCOL.md) describes the wire format and [`STATUS.md`](STATUS.md) what's tested
and what's next.

### Build

```bash
bash scripts/build.sh     # needs devkitARM (WSL or Linux) and python3 -> lua/mmo_code.lua
bash scripts/package.sh   # optional: dist/b2-mmo-<version>-windows.zip
```

Or run straight from the repo: open the ROM in BizHawk, then *Tools → Lua Console → Open Script*
and pick `lua/b2mmo.lua` (settings in `lua/b2mmo.ini`, see `package/install.ps1`).

GitHub Actions builds the zip on every push; pushing a `v*` tag publishes a release.

### Credits

Addresses, names and structures come from the [pokebw2](https://github.com/fuddlesworth/pokebw2)
decompilation of Black 2 / White 2 (and the [swan](https://github.com/ds-pokemon-hacking/swan) names
it uses); `lua/zones.lua` and `lua/species.lua` are generated from its constant lists.
The relay server and protocol are ORAS MMO's.

Pokémon is © Nintendo / Creatures Inc. / GAME FREAK inc. This is an unofficial fan project and
contains no game code or assets.
