// Fake friend plugin: watching battles (BATTLE frames, type 11).
// --plugin watch: plays a made-up battle with busy set: our Excadrill Lv45 and Zebstrika Lv43
// against a wild Lillipup Lv12, then a wild Patrat; HP goes down every second, Excadrill takes a
// hit, the Lillipup faints, and after each battle 6 s on the field (busy off, count 0 sent).
// --watch listen: don't battle, just print the BATTLE frames received (to check a real game's).
// BATTLE frames received are always printed.
export default function watch(ctx) {
  const { T, frame, send, args, state, names } = ctx;
  const listenOnly = args.watch === 'listen';

  // A scripted battle: [species, hp, maxHp, level]
  const battles = [
    { ours: [[530, 160, 160, 45], [523, 140, 140, 43]], foe: [[506, 34, 34, 12]] },
    { ours: [[530, 120, 160, 45], [523, 140, 140, 43]], foe: [[504, 30, 30, 9]] },
  ];
  let n = 0, cur = null, phase = 'field', phaseAt = Date.now() + 2000, lastSend = 0, lastKey = '', step = 0;

  function sendSide(side, mons) {
    const b = frame(T.BATTLE); b[4] = side; b[5] = mons.length;
    mons.forEach(([sp, hp, max, lv], i) => {
      const o = 6 + i * 7;
      b.writeUInt16LE(sp, o); b.writeUInt16LE(hp, o + 2); b.writeUInt16LE(max, o + 4); b[o + 6] = lv;
    });
    send(b);
  }

  function tick() {
    if (listenOnly || !ctx.myId()) return;
    const now = Date.now();
    if (phase === 'field') {
      if (now < phaseAt) return;
      const b = battles[n++ % battles.length];
      cur = { ours: b.ours.map((m) => [...m]), foe: b.foe.map((m) => [...m]) };
      phase = 'battle'; step = 0; phaseAt = now + 1000;
      state().busy = true; state().hold = true;
      console.log('watch: battle starts');
    }
    if (phase === 'battle' && now >= phaseAt) {
      phaseAt = now + 1000; step++;
      const foe = cur.foe[0];
      foe[1] = Math.max(0, foe[1] - 3);
      if (step === 3) cur.ours[0][1] = Math.max(1, cur.ours[0][1] - 25); // Excadrill takes a hit
      if (foe[1] === 0 && !cur.endAt) { cur.endAt = now + 3000; console.log('watch: the foe fainted'); }
      if (cur.endAt && now >= cur.endAt) {
        send(frame(T.BATTLE)); // count 0: over
        phase = 'field'; phaseAt = now + 6000;
        state().busy = false; state().hold = false;
        console.log('watch: battle over');
        return;
      }
    }
    if (phase !== 'battle') return;
    const key = JSON.stringify(cur);
    if (key !== lastKey || now - lastSend >= 2000) {
      sendSide(0, cur.ours); sendSide(1, cur.foe);
      lastKey = key; lastSend = now;
    }
  }

  function onFrame(f, id) {
    if (f[0] !== T.BATTLE) return;
    const count = f[5];
    const mons = [...Array(Math.min(count, 6))].map((_, i) => {
      const o = 6 + i * 7;
      return `${f.readUInt16LE(o)} ${f.readUInt16LE(o + 2)}/${f.readUInt16LE(o + 4)} L${f[o + 6]}`;
    });
    console.log(`battle from #${id} ${names[id] ?? ''} side=${f[4]} count=${count}${mons.map((m) => ` [${m}]`).join('')}`);
  }

  return { tick, onFrame };
}
