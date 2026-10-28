// A pretend player for testing: joins a room and walks around a spot, like a real Black 2 player.
// Usage: node tools/fakefriend.mjs [--server 127.0.0.1] [--port 7777] [--room UNOVA] [--name Bot]
//          [--zone 64] [--matrix 0] [--x 568] [--y 16] [--z 200] [--path square|line|stand]
//          [--size 3] [--speed 2] [--model 240] [--busy] [--chat "hi"] [--greet "text"]
//          [--events] [--trade <party.bin>] [--party <party.bin>] [--listen] [--plugin a,b]
// Positions are world units (16 a tile; y is height). --size tiles per side, --speed units per
// frame at 60 fps (1 walk, 2 run). --model the object code: 231 Nate, 240 Rosa.
// --events sends a catch, an evolution and a badge after 3 s. --trade answers a trade offer by
// offering the first Pokemon of a party dump (tools/dumpparty.lua) and accepting.
// --party answers team requests (to battle it) with the Pokemon in a file (0xDC bytes each, as
// the party stores them). --listen prints everything received.
import net from 'node:net';
import fs from 'node:fs';

const args = Object.fromEntries(
  process.argv.slice(2).reduce((acc, a, i, all) => {
    if (a.startsWith('--')) acc.push([a.slice(2), all[i + 1]?.startsWith('--') || all[i + 1] === undefined ? true : all[i + 1]]);
    return acc;
  }, []),
);
const opt = {
  server: args.server ?? '127.0.0.1', port: Number(args.port ?? 7777), room: args.room ?? 'UNOVA',
  name: args.name ?? 'Bot', zone: Number(args.zone ?? 64), matrix: Number(args.matrix ?? 0),
  x: Number(args.x ?? 568), y: Number(args.y ?? 16), z: Number(args.z ?? 200),
  path: args.path ?? 'square', size: Number(args.size ?? 3), speed: Number(args.speed ?? 1),
  model: Number(args.model ?? 240), busy: !!args.busy, listen: !!args.listen,
  greet: args.greet ?? "I'm a bot. Beep boop!",
};

const FRAME = 48;
const T = { HELLO: 1, WELCOME: 2, STATE: 3, CHAT: 4, JOIN: 5, LEAVE: 6, ERROR: 7, PING: 8, GREET: 9, TALK: 10, BATTLE: 11, TRADE: 12, EVENT: 13, PARTY: 14, LIVE: 15 };

function sendParty(to) {
  const data = args.party ? fs.readFileSync(args.party) : Buffer.alloc(0);
  const count = Math.min(6, Math.floor(data.length / 0xdc));
  if (count === 0) { const p = frame(T.PARTY); p[4] = 2; p[5] = to; sock.write(p); return; }
  for (let i = 0; i < count; i++) {
    const mon = Buffer.concat([data.subarray(i * 0xdc, i * 0xdc + 0xdc), Buffer.alloc(20)]);
    for (let c = 0; c < 6; c++) {
      const p = frame(T.PARTY); p[4] = 2; p[5] = to; p[6] = i * 6 + c; p[7] = count;
      mon.subarray(c * 40, c * 40 + 40).copy(p, 8);
      sock.write(p);
    }
  }
  console.log(`sent party (${count}) to #${to}`);
}
const frame = (type) => { const b = Buffer.alloc(FRAME); b[0] = type; b.writeUInt16LE(1, 2); return b; };
const cstr = (b, o, n) => { const s = b.subarray(o, o + n); const z = s.indexOf(0); return s.subarray(0, z < 0 ? n : z).toString('latin1'); };
const names = {};
let myId = 0;
// What plugins can change about us: busy (status bit 0), status (more STATE status bits), hold (stop walking)
const me = { busy: false, hold: false };

const sock = net.connect(opt.port, opt.server, () => {
  const h = frame(T.HELLO);
  h.write(opt.room.toUpperCase().slice(0, 11), 4, 'latin1');
  h.write(opt.name.slice(0, 15), 16, 'latin1');
  sock.write(h);
});
sock.on('error', (e) => { console.error(e.message); process.exit(1); });
sock.on('close', () => { console.log('closed'); process.exit(0); });

function greet() {
  const g = frame(T.GREET);
  g.write(opt.greet.slice(0, 39), 4, 'latin1');
  sock.write(g);
}

// Plugins (--plugin a,b loads tools/ff/a.mjs, tools/ff/b.mjs; see tools/ff/README.md)
const plugins = [];
for (const name of String(args.plugin ?? '').split(',').filter(Boolean)) {
  const mod = await import(new URL(`./ff/${name}.mjs`, import.meta.url));
  plugins.push(mod.default({
    sock, frame, send: (b) => sock.write(b), T, opt, args, myId: () => myId, names, fs,
    state: () => Object.assign(me, { x: px, z: pz, dir, zone: opt.zone }),
  }));
}

// Trade: answer an offer with our own and accept.
const trade = { offer: null, mine: null, chunks: {} };
const fnv = (buf) => { let h = 0x811c9dc5; for (const b of buf) h = Math.imul(h ^ b, 0x01000193) >>> 0; return h; };
function onTrade(f, from) {
  const op = f[4];
  if (op === 1) {
    trade.chunks[f[6]] = Buffer.from(f.subarray(8, 48));
    if (f[6] !== f[7] - 1) return;
    trade.offer = Buffer.concat([...Array(f[7]).keys()].map((i) => trade.chunks[i])).subarray(0, 0xdc);
    trade.chunks = {};
    console.log(`offer from #${from}: ${trade.offer.length} bytes`);
    if (!args.trade) return;
    trade.mine = fs.readFileSync(args.trade).subarray(0, 0xdc);
    for (let c = 0; c < 6; c++) {
      const o = frame(T.TRADE); o[4] = 1; o[5] = from; o[6] = c; o[7] = 6;
      trade.mine.subarray(c * 40, c * 40 + 40).copy(o, 8);
      sock.write(o);
    }
    const [a, b] = myId < from ? [trade.mine, trade.offer] : [trade.offer, trade.mine];
    const acc = frame(T.TRADE); acc[4] = 2; acc[5] = from; acc.writeUInt32LE(fnv(Buffer.concat([a, b])), 8);
    setTimeout(() => sock.write(acc), 500);
    console.log('offered ours and accepted');
  } else if (op === 4) {
    console.log(`COMMIT with #${f[1]} hash ${f.readUInt32LE(8).toString(16)}`);
  } else if (op === 3) {
    console.log(`trade called off by #${from}`);
  }
}

let buf = Buffer.alloc(0);
sock.on('data', (d) => {
  buf = Buffer.concat([buf, d]);
  while (buf.length >= FRAME) {
    const f = buf.subarray(0, FRAME); buf = buf.subarray(FRAME);
    const id = f[1];
    switch (f[0]) {
      case T.WELCOME: myId = id; console.log(`welcome: I am #${id}`); greet(); break;
      case T.JOIN: names[id] = cstr(f, 4, 16); console.log(`join #${id} ${names[id]}`); greet(); break;
      case T.LEAVE: console.log(`leave #${id} ${names[id] ?? ''}`); break;
      case T.STATE:
        if (opt.listen) console.log(`state #${id} zone=${f.readUInt16LE(4)} dir=${f.readUInt16LE(6)} x=${f.readFloatLE(8).toFixed(1)} y=${f.readFloatLE(12).toFixed(1)} z=${f.readFloatLE(16).toFixed(1)} matrix=${f.readUInt32LE(20)} anim=${f[36]} st=${f[37]} model=${f.readUInt16LE(38)}`);
        break;
      case T.CHAT: console.log(`chat #${id} ${names[id] ?? ''}: ${cstr(f, 4, 40)}`); break;
      case T.GREET: console.log(`greet #${id}: ${cstr(f, 4, 40)}`); break;
      case T.TALK: console.log(`talk #${id} -> #${f[4]}`); break;
      case T.TRADE: console.log(`trade #${id} op=${f[4]} to=#${f[5]}`); if (f[5] === myId || f[4] === 4) onTrade(f, id); break;
      case T.PARTY: if (f[4] === 1 && f[5] === myId) sendParty(id); break;
      case T.EVENT: console.log(`event #${id} kind=${f[4]} value=${f[5]} species=${f.readUInt16LE(6)} from=${f.readUInt16LE(8)}`); break;
      case T.ERROR: console.log(`error ${f[4]}`); break;
    }
    for (const p of plugins) p.onFrame?.(f, id);
  }
});

// Walk: a square of --size tiles (or a line, or stand), turning at the corners like a player.
const DIRS = { up: 0, down: 1, left: 2, right: 3 };
let px = opt.x, pz = opt.z, dir = DIRS.down, leg = 0, legLeft = opt.size * 16, seq = 0;
const square = [[1, 0, DIRS.right], [0, 1, DIRS.down], [-1, 0, DIRS.left], [0, -1, DIRS.up]];
const line = [[1, 0, DIRS.right], [-1, 0, DIRS.left]];
let moving = false;
const start = Date.now();
setInterval(() => {
  if (!myId) return;
  const legs = opt.path === 'line' ? line : square;
  moving = opt.path !== 'stand' && !me.hold;
  if (moving) {
    // 66 ms per update = 4 frames
    const step = Math.min(legLeft, opt.speed * 4);
    const [dx, dz, d] = legs[leg % legs.length];
    px += dx * step; pz += dz * step; dir = d; legLeft -= step;
    if (legLeft <= 0) { leg++; legLeft = opt.size * 16; }
  }
  const s = frame(T.STATE);
  s.writeUInt16LE(opt.zone, 4); s.writeUInt16LE(dir, 6);
  s.writeFloatLE(px, 8); s.writeFloatLE(opt.y, 12); s.writeFloatLE(pz, 16);
  s.writeUInt32LE(opt.matrix, 20); s.writeUInt32LE(++seq, 24);
  s[36] = moving ? 0x10 : 0; s[37] = (opt.busy || me.busy ? 1 : 0) | (me.status ?? 0); s.writeUInt16LE(opt.model, 38);
  s.writeUInt32LE((Date.now() - start) >>> 0, 40);
  sock.write(s);
}, 66);

setInterval(() => sock.write(frame(T.PING)), 3000);
setInterval(() => { for (const p of plugins) p.tick?.(); }, 66);

if (args.chat) setTimeout(() => { const c = frame(T.CHAT); c.write(String(args.chat).slice(0, 39), 4, 'latin1'); sock.write(c); }, 3000);
if (args.events) {
  setTimeout(() => {
    const ev = (kind, value, species, from) => { const e = frame(T.EVENT); e[4] = kind; e[5] = value; e.writeUInt16LE(species, 6); e.writeUInt16LE(from, 8); sock.write(e); };
    ev(1, 0, 25, 0); ev(2, 0, 26, 25); ev(3, 5, 0, 0);
  }, 3000);
}
