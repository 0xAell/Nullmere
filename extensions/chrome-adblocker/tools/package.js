#!/usr/bin/env node
// Packs the extension for handing out: builds it afresh and zips the
// build, manifest.json at the top, as Chrome and the Web Store take it.
//
//   node tools/package.js            writes dist/nullmere-stillwater-<version>.zip
//   node tools/package.js --check    fails unless the zip in dist/ holds exactly a fresh build

import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from './build.js';
import { unzip, zip } from './lib/zip.js';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

/** Every file under a directory: [{ name, data }], names with forward slashes. */
export function filesOf(directory) {
  const files = [];
  const walk = (at) => {
    for (const entry of readdirSync(at, { withFileTypes: true })) {
      const path = join(at, entry.name);
      if (entry.isDirectory()) walk(path);
      else files.push({ name: relative(directory, path).split(sep).join('/'), data: readFileSync(path) });
    }
  };
  walk(directory);
  return files.sort((a, b) => (a.name < b.name ? -1 : 1));
}

/** Where the packed extension of the version in src/manifest.json goes. */
export function zipPath() {
  const { version } = JSON.parse(readFileSync(join(root, 'src', 'manifest.json'), 'utf8'));
  return join(root, 'dist', `nullmere-stillwater-${version}.zip`);
}

/** What differs between a zip's files and a directory's, as words; empty if nothing. */
export function differences(archive, directory) {
  const packed = new Map(unzip(archive).map((file) => [file.name, file.data]));
  const fresh = new Map(filesOf(directory).map((file) => [file.name, file.data]));
  const out = [];
  for (const [name, data] of fresh) {
    if (!packed.has(name)) out.push(`${name} is not in the zip`);
    else if (!packed.get(name).equals(data)) out.push(`${name} differs`);
  }
  for (const name of packed.keys()) {
    if (!fresh.has(name)) out.push(`${name} is in the zip but not in the build`);
  }
  return out;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const out = join(root, 'build');
  build({ out, quiet: true });
  const path = zipPath();
  if (process.argv.includes('--check')) {
    if (!existsSync(path)) {
      console.error(`${relative(root, path)} is missing. Run: npm run package`);
      process.exit(1);
    }
    const differs = differences(readFileSync(path), out);
    if (differs.length) {
      console.error(`${relative(root, path)} is not a fresh build:\n  ${differs.slice(0, 20).join('\n  ')}\nRun: npm run package`);
      process.exit(1);
    }
    console.log(`${relative(root, path)} holds exactly a fresh build.`);
  } else {
    const files = filesOf(out);
    const archive = zip(files);
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, archive);
    console.log(`${relative(root, path)}: ${files.length} files, ${(archive.length / 1024).toFixed(0)} KB`);
  }
}
