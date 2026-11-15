import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');

/** Every script under a directory. */
function scripts(directory) {
  return readdirSync(directory, { withFileTypes: true, recursive: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith('.js'))
    .map((entry) => join(entry.parentPath, entry.name));
}

test('every script of the extension and its tools can be read by Node as it is written', () => {
  // A worker with a mistake in it never starts, and Chromium then says nothing: so they are read here first.
  const files = [...scripts(join(root, 'src')), ...scripts(join(root, 'tools'))];
  assert.ok(files.length > 15, 'the scripts were found');
  for (const file of files) {
    assert.doesNotThrow(() => execFileSync(process.execPath, ['--check', file], { stdio: 'pipe' }), file);
  }
});
