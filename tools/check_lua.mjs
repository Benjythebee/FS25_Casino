// Parses every Lua file of the mod as Lua 5.1 and checks it is ASCII.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import luaparse from 'luaparse';

const root = join(fileURLToPath(new URL('.', import.meta.url)), '..', 'FS25_Casino');

function* walk(dir) {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) yield* walk(path);
    else if (name.endsWith('.lua')) yield path;
  }
}

let failed = 0;
for (const file of walk(root)) {
  const source = readFileSync(file, 'utf8');
  const name = relative(root, file);
  try {
    luaparse.parse(source, { luaVersion: '5.1' });
    const bad = [...source].findIndex((ch) => ch.charCodeAt(0) > 127);
    if (bad >= 0) throw new Error(`non-ASCII character at offset ${bad}`);
    console.log(`ok   ${name}`);
  } catch (err) {
    failed++;
    console.log(`FAIL ${name}: ${err.message}`);
  }
}
process.exit(failed ? 1 : 0);
