// Trade evolution tests. As a fake friend plugin (--plugin evolve) it does nothing extra: the
// built-in --trade <file> already offers the file's first Pokemon and accepts any offer.
// As a command it gives a party file's first Pokemon another PID (so a traded-in test Pokemon
// never shares one with ours), keeping everything else:
//   node tools/ff/evolve.mjs setpid <in.bin> <out.bin> <pid hex>
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

const ORDER = [
  'ABCD', 'ABDC', 'ACBD', 'ACDB', 'ADBC', 'ADCB', 'BACD', 'BADC', 'BCAD', 'BCDA', 'BDAC', 'BDCA',
  'CABD', 'CADB', 'CBAD', 'CBDA', 'CDAB', 'CDBA', 'DABC', 'DACB', 'DBAC', 'DBCA', 'DCAB', 'DCBA',
];

// XOR the u16 words of buf[from, to) in place with the Gen 5 LCG seeded with seed
function crypt(buf, from, to, seed) {
  let s = seed >>> 0;
  for (let o = from; o < to; o += 2) {
    s = (Math.imul(s, 0x41c64e6d) + 0x6073) >>> 0;
    buf.writeUInt16LE(buf.readUInt16LE(o) ^ (s >>> 16), o);
  }
}

export function setPid(rec, pid) {
  const r = Buffer.from(rec);
  const oldPid = r.readUInt32LE(0), check = r.readUInt16LE(6);
  crypt(r, 0x08, 0x88, check);
  crypt(r, 0x88, 0xdc, oldPid);
  const blocks = {};
  const oldOrder = ORDER[((oldPid >>> 13) & 31) % 24];
  for (let p = 0; p < 4; p++) blocks[oldOrder[p]] = Buffer.from(r.subarray(8 + p * 32, 8 + p * 32 + 32));
  const newOrder = ORDER[((pid >>> 13) & 31) % 24];
  for (let p = 0; p < 4; p++) blocks[newOrder[p]].copy(r, 8 + p * 32);
  r.writeUInt32LE(pid >>> 0, 0);
  crypt(r, 0x08, 0x88, check);
  crypt(r, 0x88, 0xdc, pid);
  return r;
}

export default function evolvePlugin() {
  return {};
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const [cmd, inFile, outFile, pidHex] = process.argv.slice(2);
  if (cmd !== 'setpid' || !pidHex) {
    console.error('usage: node tools/ff/evolve.mjs setpid <in.bin> <out.bin> <pid hex>');
    process.exit(1);
  }
  const data = fs.readFileSync(inFile);
  const out = Buffer.from(data);
  setPid(data.subarray(0, 0xdc), parseInt(pidHex, 16)).copy(out, 0);
  fs.writeFileSync(outFile, out);
}
