# Fake friend plugins

`node tools/fakefriend.mjs --plugin live,watch ...` loads `tools/ff/live.mjs` and `tools/ff/watch.mjs`.
Each plugin exports a default function `(ctx) => hooks`. `ctx` has `sock`, `frame(type)` (a fresh 48-byte
frame), `send(buf)`, `T` (frame types), `opt` (parsed options), `args` (raw `--key value` options),
`myId()`, `names` (id → name), `state()` (`{ x, z, dir, zone }`, writable: `state().busy = true`),
`fs`. Hooks: `onFrame(f, id)` for every frame received (after the built-in handling), `tick()`
every 66 ms.

Each plugin's options are in its header comment. Options for the fake friend itself (`--name`,
`--x`, `--z`, `--path`, `--model`, `--party`, `--trade`, ...) are in `tools/fakefriend.mjs`.

## The plugins

- **`live.mjs`** (live battles, PROTOCOL.md LIVE): `--live-accept` accepts challenges (else declines
  them), `--live-challenge <s>` challenges whoever joins after s seconds, `--live-ai` lets the game's
  AI pick for us, `--live-leave <n>` disconnects after n steps (the game's AI takes over). Needs
  `--party <file>`. Each step it answers with its Pokémon's first move aimed at the foe, or a
  send-in of its next Pokémon when asked.
- **`watch.mjs`** (watching a battle, BATTLE frames): `--plugin watch` plays made-up battles with
  busy set (a wild Lillipup, then a wild Patrat), HP going down every second, and 6 s on the field
  between them. `--watch listen` only prints the BATTLE frames it receives, to check a real game's.
- **`talk.mjs`** (talking): the chat drives it. `ff offer` makes it offer the first Pokémon of
  `--trade <file>` to whoever said it (as a player would from the window or by talking); `ff leave`
  makes it disconnect, to test talking to someone who left.
- **`doors.mjs`** (doors): walks through doors so the other side learns them. `--route
  "x,z>zone,matrix,x,y,z;..."` gives the hops in order (walk on the current map to x,z, then change to
  zone, matrix, arriving at x,y,z); the default walks into a house in Nimbasa City. `--wait N` (seconds
  after someone joins before setting off, default 3), `--stay N` (seconds at the end, default 8, -1 =
  stay), `--nowarp` (flags every hop as "no warp", as Fly does), `--loop`.
- **`evolve.mjs`** (trade evolutions): as a plugin it does nothing extra, the built-in `--trade <file>`
  already offers the file's first Pokémon and accepts any offer. As a command,
  `node tools/ff/evolve.mjs setpid <in.bin> <out.bin> <pid hex>` gives a party file's first Pokémon
  another PID, so a traded-in test Pokémon never shares one with ours.
- **`ride.mjs`** (bikes and surf): `--ride walk|bike|surf` for one form, or `--ride "walk:4,bike:6,surf:6"`
  for forms in turn, in seconds, over and over. The model follows the form: Nate 231 walks, 232 bikes,
  233 surfs (Rosa 240, 241, 242). `--ride-leave <s>` leaves the room after s seconds, e.g. while surfing.
