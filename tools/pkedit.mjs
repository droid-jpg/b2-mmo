// Edit Pokemon Black 2 party Pokemon in a party dump (Gen 5 records, 0xDC bytes each, as in RAM).
// Usage:
//   node tools/pkedit.mjs show <party.bin>
//   node tools/pkedit.mjs edit <in.bin> <out.bin> --slot 1 [--species 93] [--item 233] [--level 30]
//                              [--hp 50] [--nickname NAME] [--clear-nickname]
//   node tools/pkedit.mjs pick <in.bin> <out.bin> 2,1
//   node tools/pkedit.mjs selftest <party.bin>
// Slots are 1-based. Decoding is a port of lua/pkm.lua: the 0x08..0x87 blocks are XORed with the
// LCG seeded by the checksum and shuffled by the PID, the party stats (0x88..0xDB) are XORed with
// the LCG seeded by the PID. edit changes only the chosen record; the others are copied unchanged.
import fs from 'node:fs';

const REC = 0xdc;
// Block order per (PID >> 13 & 31) % 24: position p in the stored data holds block ORDER[i][p].
const ORDER = [
  'ABCD', 'ABDC', 'ACBD', 'ACDB', 'ADBC', 'ADCB', 'BACD', 'BADC', 'BCAD', 'BCDA', 'BDAC', 'BDCA',
  'CABD', 'CADB', 'CBAD', 'CBDA', 'CDAB', 'CDBA', 'DABC', 'DACB', 'DBAC', 'DBCA', 'DCAB', 'DCBA',
];

class PkError extends Error {}

function lcgNext(seed) {
  return (Math.imul(seed >>> 0, 0x41c64e6d) + 0x6073) >>> 0;
}

// XOR the u16 words of buf[from, to) with the LCG seeded with seed. Encrypt and decrypt are the same.
function crypt(buf, from, to, seed) {
  const out = Buffer.alloc(to - from);
  let s = seed >>> 0;
  for (let o = from, k = 0; o < to; o += 2, k += 2) {
    s = lcgNext(s);
    out.writeUInt16LE(buf.readUInt16LE(o) ^ (s >>> 16), k);
  }
  return out;
}

function isEmpty(rec) {
  return rec.readUInt32LE(0) === 0 && rec.readUInt16LE(6) === 0;
}

// Raw record -> plaintext record: header kept, blocks unshuffled to A,B,C,D at 0x08, stats decrypted.
function decodeRecord(rec) {
  const pid = rec.readUInt32LE(0);
  const check = rec.readUInt16LE(6);
  const stored = crypt(rec, 0x08, 0x88, check); // still shuffled
  let sum = 0;
  for (let o = 0; o < 0x80; o += 2) sum = (sum + stored.readUInt16LE(o)) & 0xffff;
  if (sum !== check) {
    throw new PkError(`bad checksum (header 0x${check.toString(16)}, computed 0x${sum.toString(16)})`);
  }
  const p = Buffer.alloc(REC);
  rec.copy(p, 0, 0, 8);
  const order = ORDER[((pid >>> 13) & 31) % 24];
  for (let pos = 0; pos < 4; pos++) {
    const dst = 0x08 + 'ABCD'.indexOf(order[pos]) * 32;
    stored.copy(p, dst, pos * 32, pos * 32 + 32);
  }
  crypt(rec, 0x88, REC, pid).copy(p, 0x88);
  return p;
}

// Plaintext record -> raw record: checksum recomputed, blocks shuffled and encrypted.
function encodeRecord(p) {
  const pid = p.readUInt32LE(0);
  let sum = 0;
  for (let o = 0x08; o < 0x88; o += 2) sum = (sum + p.readUInt16LE(o)) & 0xffff;
  const rec = Buffer.alloc(REC);
  p.copy(rec, 0, 0, 8);
  rec.writeUInt16LE(sum, 6);
  const order = ORDER[((pid >>> 13) & 31) % 24];
  const shuffled = Buffer.alloc(128);
  for (let pos = 0; pos < 4; pos++) {
    const src = 0x08 + 'ABCD'.indexOf(order[pos]) * 32;
    p.copy(shuffled, pos * 32, src, src + 32);
  }
  crypt(shuffled, 0, 128, sum).copy(rec, 0x08);
  crypt(p, 0x88, REC, pid).copy(rec, 0x88);
  return rec;
}

function readMon(p) {
  const ivs = p.readUInt32LE(0x38);
  let nickname = '';
  for (let o = 0x48; o < 0x48 + 22; o += 2) {
    const ch = p.readUInt16LE(o);
    if (ch === 0xffff || ch === 0) break;
    nickname += String.fromCharCode(ch);
  }
  return {
    species: p.readUInt16LE(0x08),
    item: p.readUInt16LE(0x0a),
    level: p.readUInt8(0x8c),
    hp: p.readUInt16LE(0x8e),
    maxHp: p.readUInt16LE(0x90),
    nickname,
    isEgg: ((ivs >>> 30) & 1) === 1,
    nicknamed: ((ivs >>> 31) & 1) === 1,
  };
}

function loadParty(file) {
  if (!fs.existsSync(file)) throw new PkError(`no such file: ${file}`);
  const buf = fs.readFileSync(file);
  if (buf.length === 0 || buf.length % REC !== 0) {
    throw new PkError(`${file} is ${buf.length} bytes, not a multiple of ${REC} (one Pokemon is ${REC} bytes)`);
  }
  const records = [];
  for (let o = 0; o < buf.length; o += REC) records.push(buf.subarray(o, o + REC));
  return records;
}

function parseSlot(text, count) {
  const n = Number(text);
  if (!Number.isInteger(n) || n < 1 || n > count) {
    throw new PkError(`slot must be 1..${count}, got "${text}"`);
  }
  return n - 1;
}

function parseIntOption(name, text, min, max) {
  const n = Number(text);
  if (text === undefined || !Number.isInteger(n) || n < min || n > max) {
    throw new PkError(`--${name} must be an integer ${min}..${max}, got "${text}"`);
  }
  return n;
}

function cmdShow(file) {
  const records = loadParty(file);
  let bad = 0;
  records.forEach((rec, i) => {
    const slot = i + 1;
    if (isEmpty(rec)) {
      console.log(`slot ${slot}: empty`);
      return;
    }
    try {
      const m = readMon(decodeRecord(rec));
      const egg = m.isEgg ? ' EGG' : '';
      console.log(
        `slot ${slot}: species ${m.species} item ${m.item} Lv ${m.level} HP ${m.hp}/${m.maxHp} ` +
          `nickname "${m.nickname}"${m.nicknamed ? '' : ' (not nicknamed)'}${egg}`,
      );
    } catch (e) {
      bad++;
      console.log(`slot ${slot}: ${e.message}`);
    }
  });
  if (bad) process.exitCode = 1;
}

function cmdEdit(args) {
  const [inFile, outFile, ...rest] = args;
  if (!inFile || !outFile) throw new PkError('usage: edit <in.bin> <out.bin> --slot N [options]');
  const opts = {};
  for (let i = 0; i < rest.length; i++) {
    const a = rest[i];
    if (a === '--clear-nickname') {
      opts.clearNickname = true;
    } else if (/^--(slot|species|item|level|hp|nickname)$/.test(a)) {
      if (rest[i + 1] === undefined) throw new PkError(`${a} needs a value`);
      opts[a.slice(2)] = rest[++i];
    } else {
      throw new PkError(`unknown option "${a}"`);
    }
  }
  if (opts.slot === undefined) throw new PkError('edit needs --slot N');
  const changes = ['species', 'item', 'level', 'hp', 'nickname', 'clearNickname'].filter((k) => opts[k] !== undefined);
  if (changes.length === 0) throw new PkError('edit needs at least one of --species --item --level --hp --nickname --clear-nickname');
  if (opts.nickname !== undefined && opts.clearNickname) {
    throw new PkError('--nickname and --clear-nickname cannot be used together');
  }

  const records = loadParty(inFile);
  const idx = parseSlot(opts.slot, records.length);
  if (isEmpty(records[idx])) throw new PkError(`slot ${idx + 1} is empty`);
  const p = decodeRecord(records[idx]);

  if (opts.species !== undefined) p.writeUInt16LE(parseIntOption('species', opts.species, 0, 0xffff), 0x08);
  if (opts.item !== undefined) p.writeUInt16LE(parseIntOption('item', opts.item, 0, 0xffff), 0x0a);
  if (opts.level !== undefined) p.writeUInt8(parseIntOption('level', opts.level, 1, 100), 0x8c);
  if (opts.hp !== undefined) p.writeUInt16LE(parseIntOption('hp', opts.hp, 0, 0xffff), 0x8e);

  let ivs = p.readUInt32LE(0x38);
  if (opts.nickname !== undefined) {
    const name = opts.nickname;
    if (name.length < 1 || name.length > 10) throw new PkError('--nickname must be 1..10 characters');
    for (let i = 0; i < 11; i++) {
      const code = i < name.length ? name.charCodeAt(i) : 0xffff;
      p.writeUInt16LE(code, 0x48 + i * 2);
    }
    ivs = (ivs | 0x80000000) >>> 0; // mark as nicknamed
    p.writeUInt32LE(ivs, 0x38);
  }
  if (opts.clearNickname) {
    ivs = (ivs & 0x7fffffff) >>> 0;
    p.writeUInt32LE(ivs, 0x38);
  }

  records[idx] = encodeRecord(p);
  fs.writeFileSync(outFile, Buffer.concat(records));
  console.log(`wrote ${outFile}: slot ${idx + 1} changed (${changes.join(', ')})`);
}

function cmdPick(args) {
  const [inFile, outFile, list] = args;
  if (!inFile || !outFile || !list) throw new PkError('usage: pick <in.bin> <out.bin> 2,1');
  const records = loadParty(inFile);
  const picked = list.split(',').map((s) => records[parseSlot(s.trim(), records.length)]);
  fs.writeFileSync(outFile, Buffer.concat(picked));
  console.log(`wrote ${outFile}: ${picked.length} Pokemon from slots ${list}`);
}

function cmdSelftest(file) {
  const records = loadParty(file);
  let ok = 0;
  let fail = 0;
  records.forEach((rec, i) => {
    const slot = i + 1;
    if (isEmpty(rec)) {
      console.log(`slot ${slot}: empty, skipped`);
      return;
    }
    try {
      const again = encodeRecord(decodeRecord(rec));
      if (again.equals(rec)) {
        ok++;
        console.log(`slot ${slot}: OK`);
      } else {
        fail++;
        const at = [...rec].findIndex((b, k) => b !== again[k]);
        console.log(`slot ${slot}: FAIL (first difference at 0x${at.toString(16)})`);
      }
    } catch (e) {
      fail++;
      console.log(`slot ${slot}: FAIL (${e.message})`);
    }
  });
  console.log(`selftest: ${ok} OK, ${fail} FAIL`);
  if (fail) process.exitCode = 1;
}

function main(argv) {
  const [cmd, ...args] = argv;
  switch (cmd) {
    case 'show':
      if (args.length !== 1) throw new PkError('usage: show <party.bin>');
      return cmdShow(args[0]);
    case 'edit':
      return cmdEdit(args);
    case 'pick':
      return cmdPick(args);
    case 'selftest':
      if (args.length !== 1) throw new PkError('usage: selftest <party.bin>');
      return cmdSelftest(args[0]);
    default:
      throw new PkError('usage: pkedit.mjs show|edit|pick|selftest ... (see the top of this file)');
  }
}

try {
  main(process.argv.slice(2));
} catch (e) {
  console.error(`pkedit: ${e.message}`);
  process.exitCode = 1;
}
