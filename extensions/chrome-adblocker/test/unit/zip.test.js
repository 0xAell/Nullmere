import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { encodePNG } from '../../tools/lib/png.js';
import { unzip, zip } from '../../tools/lib/zip.js';
import { draw, ICONS } from '../../tools/make-icons.js';

const files = [
  { name: 'manifest.json', data: Buffer.from('{"name":"Nullmere Stillwater"}') },
  { name: 'rules/easylist.json', data: Buffer.from('[]\n'.repeat(2000)) },
  { name: 'icons/ünï.bin', data: Buffer.from([0, 1, 2, 255]) },
  { name: 'empty.txt', data: Buffer.alloc(0) },
];

test('a zip is read back as it was written, names in order', () => {
  const read = unzip(zip(files));
  assert.deepEqual(read.map((file) => file.name), ['empty.txt', 'icons/ünï.bin', 'manifest.json', 'rules/easylist.json']);
  for (const file of files) assert.ok(read.find((other) => other.name === file.name).data.equals(file.data), file.name);
});

test('the same files make the same bytes, in whatever order they are given', () => {
  assert.ok(zip(files).equals(zip([...files].reverse())));
});

test('the system\'s own unzip reads it', (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'zip-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  writeFileSync(join(directory, 'a.zip'), zip(files));
  let listing;
  try {
    listing = execFileSync('unzip', ['-t', join(directory, 'a.zip')], { encoding: 'utf8' });
  } catch (error) {
    if (error.code === 'ENOENT') return t.skip('no unzip on this machine');
    throw error;
  }
  assert.match(listing, /No errors detected/);
  execFileSync('unzip', ['-q', join(directory, 'a.zip'), '-d', join(directory, 'out')]);
  assert.equal(readFileSync(join(directory, 'out', 'manifest.json'), 'utf8'), '{"name":"Nullmere Stillwater"}');
});

test('a damaged zip is refused', () => {
  const archive = zip(files);
  archive[40] ^= 0xff;
  assert.throws(() => unzip(archive));
  assert.throws(() => unzip(Buffer.from('not a zip at all')), /no end record/);
});

test('the icons in src/icons are what the generator draws', () => {
  for (const [name, size, off] of ICONS) {
    const drawn = encodePNG(size, size, draw(size, off));
    const kept = readFileSync(new URL(`../../src/icons/${name}`, import.meta.url));
    assert.ok(drawn.equals(kept), `${name}: run node tools/make-icons.js`);
    assert.deepEqual([...kept.subarray(0, 8)], [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    assert.equal(kept.readUInt32BE(16), size);
  }
});
