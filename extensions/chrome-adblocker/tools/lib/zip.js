// Writes and reads zip archives with nothing but Node's zlib. The same
// files always make the same bytes: names in order, one fixed date, no
// extra fields.

import { crc32, deflateRawSync, inflateRawSync } from 'node:zlib';

// 1 January 1980, the first day a zip can name.
const DOS_DATE = (0 << 9) | (1 << 5) | 1;
const DOS_TIME = 0;
const UTF8_NAMES = 0x0800;

/** A zip of `files`: [{ name, data }], `name` with forward slashes. */
export function zip(files) {
  const sorted = [...files].sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  const parts = [];
  const directory = [];
  let offset = 0;
  for (const file of sorted) {
    const name = Buffer.from(file.name, 'utf8');
    const data = Buffer.from(file.data);
    const packed = deflateRawSync(data, { level: 9 });
    const sum = crc32(data) >>> 0;

    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4); // version needed: 2.0, for deflate
    local.writeUInt16LE(UTF8_NAMES, 6);
    local.writeUInt16LE(8, 8); // deflate
    local.writeUInt16LE(DOS_TIME, 10);
    local.writeUInt16LE(DOS_DATE, 12);
    local.writeUInt32LE(sum, 14);
    local.writeUInt32LE(packed.length, 18);
    local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(name.length, 26);
    parts.push(local, name, packed);

    const entry = Buffer.alloc(46);
    entry.writeUInt32LE(0x02014b50, 0);
    entry.writeUInt16LE((3 << 8) | 20, 4); // made on Unix, version 2.0
    entry.writeUInt16LE(20, 6);
    entry.writeUInt16LE(UTF8_NAMES, 8);
    entry.writeUInt16LE(8, 10);
    entry.writeUInt16LE(DOS_TIME, 12);
    entry.writeUInt16LE(DOS_DATE, 14);
    entry.writeUInt32LE(sum, 16);
    entry.writeUInt32LE(packed.length, 20);
    entry.writeUInt32LE(data.length, 24);
    entry.writeUInt16LE(name.length, 28);
    entry.writeUInt32LE((0o100644 << 16) >>> 0, 38); // a plain file anyone may read
    entry.writeUInt32LE(offset, 42);
    directory.push(entry, name);

    offset += local.length + name.length + packed.length;
  }
  const directorySize = directory.reduce((sum, part) => sum + part.length, 0);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(sorted.length, 8);
  end.writeUInt16LE(sorted.length, 10);
  end.writeUInt32LE(directorySize, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...parts, ...directory, end]);
}

/** The files of a zip this module wrote (or any plain one): [{ name, data }]. */
export function unzip(archive) {
  let end = archive.length - 22;
  while (end >= 0 && archive.readUInt32LE(end) !== 0x06054b50) end--;
  if (end < 0) throw new Error('Not a zip: no end record');
  const count = archive.readUInt16LE(end + 10);
  let at = archive.readUInt32LE(end + 16);
  const files = [];
  for (let i = 0; i < count; i++) {
    if (archive.readUInt32LE(at) !== 0x02014b50) throw new Error('Not a zip: bad directory entry');
    const method = archive.readUInt16LE(at + 10);
    const sum = archive.readUInt32LE(at + 16);
    const packedSize = archive.readUInt32LE(at + 20);
    const nameLength = archive.readUInt16LE(at + 28);
    const extraLength = archive.readUInt16LE(at + 30);
    const commentLength = archive.readUInt16LE(at + 32);
    const local = archive.readUInt32LE(at + 42);
    const name = archive.toString('utf8', at + 46, at + 46 + nameLength);
    const dataAt = local + 30 + archive.readUInt16LE(local + 26) + archive.readUInt16LE(local + 28);
    const packed = archive.subarray(dataAt, dataAt + packedSize);
    const data = method === 0 ? Buffer.from(packed) : inflateRawSync(packed);
    if (crc32(data) >>> 0 !== sum) throw new Error(`${name}: checksum does not match`);
    files.push({ name, data });
    at += 46 + nameLength + extraLength + commentLength;
  }
  return files;
}
