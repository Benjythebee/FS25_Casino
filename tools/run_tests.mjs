// Runs tests.lua in a Lua VM (fengari) with the mod's RouletteRules.lua and RouletteTable.lua loaded.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import fengari from 'fengari';

const { lua, lauxlib, lualib, to_luastring } = fengari;
const here = fileURLToPath(new URL('.', import.meta.url));
const scripts = join(here, '..', 'FS25_Casino', 'scripts');

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

function run(file) {
  const code = readFileSync(file, 'utf8');
  if (lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring('@' + file)) !== lua.LUA_OK ||
      lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    console.error(lua.lua_tojsstring(L, -1));
    process.exit(1);
  }
}

run(join(here, 'test_stubs.lua'));
run(join(scripts, 'RouletteRules.lua'));
run(join(scripts, 'RouletteTable.lua'));
run(join(scripts, 'gui', 'CasinoFrame.lua'));
run(join(here, 'tests.lua'));
