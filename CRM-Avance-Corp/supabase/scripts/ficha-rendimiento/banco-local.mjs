import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';

export const contenedor = 'supabase_db_avancecorp-f5-bank';
export const base = 'ficha_rapida_20260915';
export const ajustes = `set local statement_timeout='90s';
set local jit=off; set local work_mem='3500kB'; set local random_page_cost=1.1;`;
// Destino cerrado a la copia sintética propia. No acepta URL, clave ni nombre por entorno.
export function sql(consulta) {
  const r=spawnSync('docker',['exec','-i',contenedor,'psql','-X','-qAt','-U','postgres','-d',base,
    '-v','ON_ERROR_STOP=1','-f','-'],{input:consulta,encoding:'utf8',maxBuffer:32*1024*1024});
  assert.equal(r.status,0,r.stderr||r.error?.message);
  return r.stdout.trim();
}
