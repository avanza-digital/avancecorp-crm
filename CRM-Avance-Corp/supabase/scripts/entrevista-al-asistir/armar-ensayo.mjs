#!/usr/bin/env node
// Arma el ENSAYO de `crm.cerrar_reunion_v3` contra producción, sin escribir.
//
// Pega la migración REAL (menos su `begin;`/`commit;`) y el oráculo de
// `pruebas.sql` dentro de UNA transacción que termina en `rollback`. Así se
// prueba el cuerpo que se va a publicar —preflight, gates y comentarios
// incluidos— en vez de una copia que se desactualiza sola en cuanto alguien
// toca la migración.
//
// Uso:
//   node supabase/scripts/entrevista-al-asistir/armar-ensayo.mjs > /tmp/ensayo.sql
//
// El resultado se ejecuta con el MCP de Supabase (o `db query`) contra el
// proyecto vivo. Termina SIEMPRE en excepción: eso es el veredicto, no un fallo.
import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const aqui = dirname(fileURLToPath(import.meta.url))
const migracion = resolve(aqui, '../../migrations/20260918213000_crm_entrevista_al_asistir.sql')
const pruebas = resolve(aqui, 'pruebas.sql')

const sql = readFileSync(migracion, 'utf8')

// El control de transacción se quita porque lo pone este guion: si se colara el
// `commit;` de la migración, el ensayo dejaría la función CREADA en producción
// —exactamente lo que este archivo existe para evitar—.
const lineas = sql.split('\n')
const cuerpo = lineas.filter((l) => !/^\s*(begin|commit)\s*;\s*$/i.test(l))
if (cuerpo.length === lineas.length) {
  throw new Error('La migración no trae begin;/commit;: revisar antes de ensayar')
}
if (/^\s*commit\s*;/im.test(cuerpo.join('\n'))) {
  throw new Error('Queda un commit suelto en la migración: el ensayo escribiría en producción')
}

process.stdout.write(
  [
    '-- GENERADO por armar-ensayo.mjs — no editar a mano.',
    '-- Termina en rollback: nada de esto queda en producción.',
    'begin;',
    cuerpo.join('\n'),
    readFileSync(pruebas, 'utf8'),
    'rollback;',
    '',
  ].join('\n'),
)
