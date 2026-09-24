// Primera preparación del candidato: obtener las huellas reales dentro de un
// ROLLBACK. Sólo rellena marcadores de esta migración nueva, nunca el historial.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { sql } from './banco.mjs';

const archivo = new URL('../../migrations/20260923234404_crm_gestion_diaria_pendientes_supervisor.sql', import.meta.url);
const firmas = [
  'private.gestion_diaria_equipo_core(date,uuid)',
  'private.gestion_diaria_equipo_ambito(uuid)',
  'private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)',
  'crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid)',
];
const marcadores = ['MD5_H3_EQUIPO', 'MD5_H3_AMBITO', 'MD5_H3_CORE', 'MD5_H3_PUERTA'];
let fuente = readFileSync(archivo, 'utf8');
if (marcadores.some(m => fuente.includes(m))) {
  const huellas = `select jsonb_build_array(${firmas.map(f => `md5(pg_get_functiondef('${f}'::regprocedure))`).join(',')});`;
  const provisional = fuente.replace(/do \$postflight\$[\s\S]*?end \$postflight\$;/, '')
    .replace("notify pgrst, 'reload schema';", '').replace(/commit;\s*$/, `${huellas}\nrollback;`);
  const sellos = JSON.parse(sql(provisional));
  marcadores.forEach((marcador, i) => {
    assert.match(sellos[i], /^[a-f0-9]{32}$/);
    fuente = fuente.replaceAll(marcador, sellos[i]);
  });
  writeFileSync(archivo, fuente);
  console.log('PASS: huellas obtenidas con rollback en el banco H3');
} else console.log('Migración ya sellada: no se modifica');
