// Fake friend plugin: live battles (see lua/features/live.lua, PROTOCOL.md LIVE).
//   --live-accept           accept live battle challenges (else decline them)
//   --live-challenge <s>    challenge the first player who joins, <s> seconds after they join
//   --live-ai               answer every step with "your AI picks for me" (count 0xFF)
//   --live-leave <n>        disconnect after answering n steps (the game's AI takes over)
// Needs --party <file> (the party we battle with, 0xDC bytes a Pokemon). Each step the game sends
// (its own answer) is answered for our side: an action with our current Pokemon's first move, aimed
// at the foe; a send-in with the next Pokemon still standing when the step says we must; else nothing.
const OP = { CHALLENGE: 1, ACCEPT: 2, CANCEL: 3, ACTION: 4 };

// Gen 5 party Pokemon: blocks @8 encrypted with the checksum and shuffled by the PID; moves @B+0
const ORDER = ['ABCD', 'ABDC', 'ACBD', 'ACDB', 'ADBC', 'ADCB', 'BACD', 'BADC', 'BCAD', 'BCDA', 'BDAC', 'BDCA',
  'CABD', 'CADB', 'CBAD', 'CBDA', 'CDAB', 'CDBA', 'DABC', 'DACB', 'DBAC', 'DBCA', 'DCAB', 'DCBA'];
function firstMove(raw) {
  const pid = raw.readUInt32LE(0);
  let seed = raw.readUInt16LE(6);
  const dec = Buffer.alloc(128);
  for (let o = 0; o < 128; o += 2) {
    seed = (Math.imul(seed, 0x41c64e6d) + 0x6073) >>> 0;
    dec.writeUInt16LE(raw.readUInt16LE(8 + o) ^ (seed >>> 16), o);
  }
  const b = ORDER[((pid >>> 13) & 31) % 24].indexOf('B');
  return dec.readUInt16LE(b * 32);
}

export default function live(ctx) {
  const { frame, send, T, args, fs, myId, names } = ctx;
  const party = args.party ? fs.readFileSync(args.party) : Buffer.alloc(0);
  const count = Math.min(6, Math.floor(party.length / 0xdc));
  const mons = [...Array(count).keys()].map((i) => party.subarray(i * 0xdc, i * 0xdc + 0xdc));
  let foe = null;       // who we battle
  let order = [];       // our battle party order (the battle swaps the one sent in to the front)
  let fainted = new Set();
  let answered = 0;
  let challenged = false;

  const liveFrame = (op, to) => { const f = frame(T.LIVE); f[4] = op; f[5] = to; return f; };
  function sendParty(to) {
    for (let i = 0; i < count; i++) {
      const mon = Buffer.concat([mons[i], Buffer.alloc(20)]);
      for (let c = 0; c < 6; c++) {
        const p = frame(T.PARTY); p[4] = 3; p[5] = to; p[6] = i * 6 + c; p[7] = count;
        mon.subarray(c * 40, c * 40 + 40).copy(p, 8);
        send(p);
      }
    }
  }
  function begin(to) { foe = to; order = [...Array(count).keys()]; fainted = new Set(); answered = 0; }

  function answer(f) {
    const step = f.readUInt16LE(6), cmd = f[8], ask = f[10];
    const a = liveFrame(OP.ACTION, foe);
    a.writeUInt16LE(step, 6); a[8] = cmd; a[10] = ((ask & 1) << 1) | ((ask >> 1) & 1); a.writeUInt32LE(f.readUInt32LE(12), 12);
    let what;
    if (args['live-ai']) { a[9] = 0xff; what = 'AI picks'; }
    else if (cmd === 3) {
      const move = firstMove(mons[order[0]]);
      a[9] = 1; a.writeUInt32LE((1 | (1 << 4) | (move << 7)) >>> 0, 16); what = `move ${move}`;
    } else if ((cmd === 5 || cmd === 6) && (ask & 2)) {
      if (cmd === 5) fainted.add(order[0]);
      const j = order.findIndex((m, k) => k > 0 && !fainted.has(m));
      if (j < 0) { a[9] = 1; what = 'nobody left'; }
      else {
        [order[0], order[j]] = [order[j], order[0]];
        a[9] = 1; a.writeUInt32LE(3 | (0 << 4) | (j << 7), 16); what = `send in slot ${j}`;
      }
    } else { a[9] = 1; what = 'nothing'; }
    send(a);
    answered++;
    console.log(`live step ${step} cmd ${cmd} ask ${ask} check ${f.readUInt32LE(12).toString(16)}: ${what}`);
    if (args['live-leave'] && answered >= Number(args['live-leave'])) {
      console.log('live: leaving mid-battle');
      setTimeout(() => process.exit(0), 300);
    }
  }

  return {
    onFrame(f, id) {
      if (f[0] === T.JOIN && args['live-challenge'] && !challenged) {
        challenged = true;
        setTimeout(() => {
          sendParty(id);
          const c = liveFrame(OP.CHALLENGE, id); c.writeUInt32LE(0x1234567, 8); send(c);
          foe = id;
          console.log(`live: challenged #${id}`);
        }, Number(args['live-challenge']) * 1000);
      }
      if (f[0] !== T.LIVE || f[5] !== myId()) return;
      const op = f[4];
      if (op === OP.CHALLENGE) {
        console.log(`live: challenge from #${id} ${names[id] ?? ''} seed ${f.readUInt32LE(8).toString(16)}`);
        if (args['live-accept']) { sendParty(id); send(liveFrame(OP.ACCEPT, id)); begin(id); console.log('live: accepted'); }
        else { send(liveFrame(OP.CANCEL, id)); console.log('live: declined'); }
      } else if (op === OP.ACCEPT && id === foe) {
        begin(id); console.log('live: they accepted');
      } else if (op === OP.CANCEL) {
        console.log(`live: cancel from #${id}`);
      } else if (op === OP.ACTION && id === foe) {
        answer(f);
      }
    },
  };
}
