// Copia sintética propia: no acepta URLs, credenciales ni destinos externos.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
export const db='cartera_filtros_20260916',contenedor='supabase_db_avancecorp-f5-bank';
export const q=x=>x===null?'null':"'"+String(x).replaceAll("'","''")+"'";
export function ejecutar(s) {
  return spawnSync('docker',['exec','-i',contenedor,'psql','-X','-qAt','-U','supabase_admin','-d',db,'-v','ON_ERROR_STOP=1','-f','-'],
    {input:'\\set VERBOSITY verbose\n'+s,encoding:'utf8',maxBuffer:16*1024*1024});
}
export function sql(s) {const r=ejecutar(s);assert.equal(r.status,0,r.stderr||r.error?.message);return r.stdout.trim();}
export const objeto=s=>JSON.parse(sql(s));
export const gerencia=sql("select perfil_id from crm.equipo where activo and rol_crm='gerencia' order by perfil_id limit 1");
export const preparar="update crm.piloto_f8_control set activo=false where singleton;update crm.multiempresa_flags set activo=(nombre<>'metricas_multiempresa_sombra');";
export const claims=actor=>`set local request.jwt.claim.sub=${q(actor)};set local role authenticated;`;
export function consulta(s,actor=gerencia,antes='') {
  return objeto(`begin;set local statement_timeout='15s';${preparar}${antes}${claims(actor)}select ${s};rollback;`);
}
