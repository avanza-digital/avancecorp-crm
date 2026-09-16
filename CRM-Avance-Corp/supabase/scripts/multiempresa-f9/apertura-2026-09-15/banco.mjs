// Acceso exclusivo a una copia sintética F9. No acepta destino por env/argv.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
export const db='f9_apertura_20260915',contenedor='supabase_db_avancecorp-f5-bank';
export const args=(admin=false)=>['exec','-i',contenedor,'psql','-X','-qAt','-U',admin?'supabase_admin':'postgres','-d',db,'-v','ON_ERROR_STOP=1','-f','-'];
export const ejecutar=(s,admin=false)=>spawnSync('docker',args(admin),{input:'\\set VERBOSITY verbose\n'+s,encoding:'utf8',maxBuffer:12*1024*1024});
export function sql(s,admin=false) {const r=ejecutar(s,admin);assert.equal(r.status,0,r.stderr||r.error?.message);return r.stdout.trim();}
export const objeto=(s,admin=false)=>JSON.parse(sql(s,admin));
export const q=x=>x===null?'null':"'"+String(x).replaceAll("'","''")+"'";
export const j=x=>q(JSON.stringify(x))+'::jsonb';
