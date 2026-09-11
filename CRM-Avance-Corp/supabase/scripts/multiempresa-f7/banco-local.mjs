// Destino cerrado: copia sintética aislada; nunca acepta una URL productiva.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';

export const directorio='/private/tmp/avancecorp-f7-20260911';
export const contenedor='supabase_db_avancecorp-f5-bank';
export const db='multiempresa_f7_20260911';
export const fixture=JSON.parse(readFileSync('/private/tmp/avancecorp-f5-bank/fixtures.json','utf8'));
export const literal=v=>v===null?'null':`'${String(v).replaceAll("'","''")}'`;
export function sql(texto,{admin=false}={}) {
  const r=spawnSync('docker',['exec','-i',contenedor,'psql','-X','-qAt','-U',
    admin?'supabase_admin':'postgres','-d',db,'-v','ON_ERROR_STOP=1','-f','-'],
  {input:`set timezone='America/Lima';\n${texto}\n`,encoding:'utf8',maxBuffer:32*1024*1024});
  assert.equal(r.status,0,r.stderr||r.error?.message||'Falló el banco aislado F7');
  return r.stdout.trim();
}
export const como=(rol,consulta)=>`set local role authenticated;
  set local request.jwt.claim.sub=${literal(fixture.usuarios[rol].id)};
  ${consulta}`;
export const informe=(mes='2026-09-01',preparar='')=>JSON.parse(sql(`begin;
  update crm.multiempresa_flags set activo=true where nombre='metricas_multiempresa_sombra';
  ${preparar}
  ${como('gerencia',`select crm.metricas_multiempresa_fn(${literal(mes)})`)};
  rollback;`));

export function aplicar() {
  assert.equal(sql('select current_database()'),db);
  const candidata=readFileSync(new URL('../../migrations/20260911163243_crm_multiempresa_f7_metricas_sombra.sql',import.meta.url),'utf8');
  // Solo objetos NUEVOS de esta tarea, en su copia descartable. No usar fuera.
  sql(`begin;
    drop function if exists crm.metricas_multiempresa_fn(date);
    drop function if exists crm.metricas_multiempresa_estado_fn();
    drop function if exists private.metricas_f7_fuentes();
    drop function if exists private.metricas_f7_autorizada();
    delete from crm.multiempresa_flags where nombre='metricas_multiempresa_sombra';
    ${candidata}
    commit;`);
}
