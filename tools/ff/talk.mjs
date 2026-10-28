// Fake friend plugin for talking (test/t_talk.lua): node tools/fakefriend.mjs --plugin talk --trade party.bin
// The player's chat drives it:
//   "ff offer"  the fake friend offers the first Pokemon of --trade (as a player would from the window
//               or by talking), to whoever said it. When the player then offers theirs, fakefriend's
//               own --trade handling offers again and accepts.
//   "ff leave"  the fake friend leaves (disconnects), to test a conversation with someone who left.
export default function talk(ctx) {
  const { T, frame, send, args, fs } = ctx;
  return {
    onFrame(f, id) {
      if (f[0] !== T.CHAT) return;
      const text = f.subarray(4, 44).toString('latin1').replace(/\0.*$/s, '');
      if (text === 'ff offer' && args.trade) {
        const mon = Buffer.concat([fs.readFileSync(args.trade).subarray(0, 0xdc), Buffer.alloc(20)]);
        for (let c = 0; c < 6; c++) {
          const o = frame(T.TRADE); o[4] = 1; o[5] = id; o[6] = c; o[7] = 6;
          mon.subarray(c * 40, c * 40 + 40).copy(o, 8);
          send(o);
        }
        console.log(`talk: offered first to #${id}`);
      } else if (text === 'ff leave') {
        console.log('talk: leaving');
        setTimeout(() => process.exit(0), 50);
      }
    },
  };
}
