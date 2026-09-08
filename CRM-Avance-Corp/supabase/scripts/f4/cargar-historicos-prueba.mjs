import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { funcionesDelSql } from './leer-funciones-sql.mjs';
import { literal as q } from './banco-local.mjs';

export const definicionesHistoricas = ['07-historicos.sql','08-historicos-lote.sql'].map(nombre => ({
  nombre, contenido: readFileSync(new URL(nombre,import.meta.url),'utf8'),
}));
const funciones=funcionesDelSql(definicionesHistoricas.map(d=>d.contenido).join('\n'));
export const objetosHistoricosSql=`select jsonb_build_object('tabla',to_regclass('crm.inversion_backfill_lotes') is not null,
  'funciones',(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname||'.'||p.proname=any(array[${funciones.map(f=>q(f.nombre)).join(',')}])) )`;

// El oráculo sirve antes y después de integrar la candidata. Una instalación
// parcial o distinta se rechaza; nunca se sustituye silenciosamente para pasar.
export function cargarHistoricosPrueba(sql) {
  const estado=JSON.parse(sql(objetosHistoricosSql));
  if (!estado.tabla && estado.funciones===0) {
    return { instalado:false, preparacion:definicionesHistoricas.map(d=>d.contenido).join('\n') };
  }
  assert.deepEqual(estado,{tabla:true,funciones:funciones.length},'Instalación histórica parcial');
  for (const f of funciones) {
    assert.equal(sql(`select prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname||'.'||p.proname=${q(f.nombre)}`),f.body.trim(),`Cuerpo histórico diferente: ${f.nombre}`);
  }
  assert.equal(sql(`select count(*) from pg_trigger where tgrelid='crm.inversion_backfill_lotes'::regclass
    and not tgisinternal and tgenabled='O' and tgname in ('trg_audit_inversion_backfill_lotes',
      'trg_inversion_backfill_inmutable','trg_inversion_backfill_completo')`),'3');
  return { instalado:true, preparacion:'' };
}
