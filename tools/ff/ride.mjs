// Fake friend plugin: rides a bike or surfs, like a real Black 2 player (STATE model + status bits).
//   --ride walk|bike|surf          one form all along
//   --ride "walk:4,bike:6,surf:6"  forms in turn, seconds each, over and over
//   --ride-leave <s>               leave the room after s seconds (e.g. while surfing)
// The models are the player's forms (field_player.c PLAYER_SPRITE_MAP): --model 231 (Nate) walks,
// 232 bikes, 233 surfs; 240 (Rosa) 241, 242. Status bit 1 (2) = on a bike, bit 2 (4) = surfing.
export default function ride(ctx) {
  const base = ctx.opt.model >= 240 ? 240 : 231;
  const FORMS = { walk: [0, 0], bike: [1, 2], surf: [2, 4] };
  const phases = String(ctx.args.ride ?? 'walk').split(',').map((p) => {
    const [form, secs] = p.split(':');
    return { form: FORMS[form] ? form : 'walk', ms: Number(secs ?? 0) * 1000 };
  });
  const start = Date.now();
  let shown = '';
  const set = (form) => {
    const [off, status] = FORMS[form];
    ctx.opt.model = base + off;
    ctx.state().status = status;
    if (form !== shown) { console.log(`ride: ${form} (model ${ctx.opt.model}, status ${status})`); shown = form; }
  };
  // (ctx.state() only works once the fake friend is running: the first tick sets the form)
  if (ctx.args['ride-leave']) {
    setTimeout(() => { console.log(`ride: leaving as ${shown}`); process.exit(0); }, Number(ctx.args['ride-leave']) * 1000);
  }
  return {
    tick() {
      const total = phases.reduce((a, p) => a + p.ms, 0);
      if (total <= 0) { set(phases[0].form); return; }
      let t = (Date.now() - start) % total;
      for (const p of phases) {
        if (t < p.ms) { set(p.form); return; }
        t -= p.ms;
      }
    },
  };
}
