import assert from 'node:assert/strict';
import {sql,objeto} from './banco.mjs';

// Solo se usa en banco-f7. El trigger touch sustituye toda fecha escrita por
// now(): al devolver el fixture se suspende únicamente ese trigger, dentro de
// la misma transacción, y se vuelve a habilitar antes de confirmar.
export function restaurarBandera(flag){
 assert.equal(flag.nombre,'potencial_lead');
 assert.equal(typeof flag.activo,'boolean');
 assert.equal(sql("select count(*) from pg_trigger where tgrelid='crm.multiempresa_flags'::regclass and tgname='trg_multiempresa_flags_touch' and tgenabled='O'"),'1');
 const literal="'"+JSON.stringify(flag).replaceAll("'","''")+"'::jsonb";
 sql(`begin;
 alter table crm.multiempresa_flags disable trigger trg_multiempresa_flags_touch;
 update crm.multiempresa_flags f set activo=r.activo,actualizado_en=r.actualizado_en
 from jsonb_populate_record(null::crm.multiempresa_flags,${literal}) r where f.nombre=r.nombre;
 alter table crm.multiempresa_flags enable trigger trg_multiempresa_flags_touch;
 commit;`);
 assert.deepEqual(objeto("select to_jsonb(f) from crm.multiempresa_flags f where nombre='potencial_lead'"),flag);
 assert.equal(sql('select count(*) from crm.lead_potencial'),'0','El gate dejó marcas sintéticas');
}
