// Fake friend plugin "doors": walks through doors like a Black 2 player, so the other side learns
// them. node tools/fakefriend.mjs --plugin doors --path stand --x 568 --z 200 [options]
//   --route "632,184>585,379,232,32,728;..."  hops, in order: walk (on the current map) to x,z,
//            then change to zone,matrix arriving at x,y,z. Default: Nimbasa City (zone 64) into
//            the house at x 632 (zone 585). Coordinates in units (16 a tile).
//   --wait N   seconds after someone joins before setting off (default 3)
//   --stay N   seconds to stay at the end before walking back the same way (default 8; -1 = stay)
//   --nowarp   flag every hop as "no warp" (STATE status bit 3, like Fly): nothing should be learned
//   --loop     go again after coming back
export default function doors(ctx) {
  const { opt, args } = ctx;
  const route = String(args.route ?? '632,184>585,379,232,32,728').split(';').filter(Boolean).map((h) => {
    const [from, to] = h.split('>');
    const [sx, sz] = from.split(',').map(Number);
    const [zone, matrix, x, y, z] = to.split(',').map(Number);
    return { sx, sz, zone, matrix, x, y, z };
  });
  const waitMs = Number(args.wait ?? 3) * 1000;
  const stayMs = Number(args.stay ?? 8) * 1000;
  const nowarp = !!args.nowarp;
  const step = opt.speed * 4; // units per 66 ms tick
  let me = null; // ctx.state(), once the fake friend has started

  // The plan: a list of moves { walk: [x, z] } and { hop: { zone, matrix, x, y, z } }
  const start = { zone: opt.zone, matrix: opt.matrix, x: opt.x, y: opt.y, z: opt.z };
  const plan = [];
  const build = () => {
    plan.length = 0;
    plan.push({ pause: waitMs });
    let at = start;
    const stops = [];
    for (const h of route) {
      plan.push({ walk: [h.sx, h.sz] }, { pause: 500 }, { hop: h, leaveFrom: [h.sx, h.sz] });
      stops.push({ from: at, hop: h });
      at = h;
    }
    if (stayMs < 0) { plan.push({ pause: Infinity }); return; }
    plan.push({ pause: stayMs });
    for (const s of stops.reverse()) {
      // Back out: to the arrival spot, then to the previous map where we left it
      plan.push({ walk: [s.hop.x, s.hop.z] }, { pause: 500 },
        { hop: { zone: s.from.zone, matrix: s.from.matrix, x: s.hop.sx, y: s.from.y, z: s.hop.sz } });
    }
    plan.push({ pause: 3000 });
  };
  build();

  let i = 0, until = 0, x = opt.x, z = opt.z, flagUntil = 0, started = false;
  return {
    tick() {
      if (!ctx.myId() || Object.keys(ctx.names).length === 0) return; // set off once someone is watching
      if (!me) { me = ctx.state(); me.hold = true; }
      const now = Date.now();
      if (!started) { started = true; until = now + (plan[0].pause ?? 0); }
      me.status = now < flagUntil ? 8 : 0;
      const p = plan[i];
      if (!p) { if (args.loop) { build(); i = 0; started = false; } return; }
      if (p.pause !== undefined) {
        if (now >= until) next(now);
      } else if (p.walk) {
        const [tx, tz] = p.walk;
        let dir;
        if (x !== tx) { const d = Math.sign(tx - x) * Math.min(step, Math.abs(tx - x)); x += d; dir = d > 0 ? 3 : 2; }
        else if (z !== tz) { const d = Math.sign(tz - z) * Math.min(step, Math.abs(tz - z)); z += d; dir = d > 0 ? 1 : 0; }
        me.goto = { x, z, dir };
        if (x === tx && z === tz) next(now);
      } else if (p.hop) {
        const h = p.hop;
        if (nowarp) { flagUntil = now + 5000; me.status = 8; }
        opt.zone = h.zone; opt.matrix = h.matrix; opt.y = h.y;
        x = h.x; z = h.z;
        me.goto = { x, z, dir: 1 };
        console.log(`doors: now in zone ${h.zone} at ${x},${z}${nowarp ? ' (no warp)' : ''}`);
        next(now);
      }
      function next(t) {
        i++;
        const q = plan[i];
        if (q && q.pause !== undefined) until = t + q.pause;
      }
    },
  };
}
