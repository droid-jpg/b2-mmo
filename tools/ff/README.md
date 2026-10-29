# Fake friend plugins

`node tools/fakefriend.mjs --plugin live,watch ...` loads `tools/ff/live.mjs` and `tools/ff/watch.mjs`.
Each exports a default function `(ctx) => hooks`. `ctx` has `sock`, `frame(type)` (a fresh 48-byte
frame), `send(buf)`, `T` (frame types), `opt` (parsed options), `args` (raw `--key value` options),
`myId()`, `names` (id → name), `state()` (`{ x, z, dir, zone }`, writable: `state().busy = true`),
`fs`. Hooks: `onFrame(f, id)` for every frame received (after the built-in handling), `tick()`
every 66 ms.

`live.mjs` (live battles): `--live-accept` accepts challenges (else declines), `--live-challenge <s>`
challenges whoever joins after s seconds, `--live-ai` lets the game's AI pick for us, `--live-leave
<n>` disconnects after n steps. Needs `--party <file>` (read when a battle is set up). Each step it
answers with its Pokemon's first move aimed at the foe, or a send-in of its next Pokemon when asked.
