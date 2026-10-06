// Ensaya el orden de instalación y sus controles SOLO en el banco sintético
// fijo de banco.mjs. Toda la preparación, DDL y fixtures termina en ROLLBACK.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { catalogosUiSql } from './catalogo-ui.mjs'

const ruta = process.argv[2]
assert(ruta?.startsWith('/private/tmp/'), 'Indica el snapshot local de esquema, sin datos')
const esquema = readFileSync(ruta, 'utf8')
const inicio = esquema.indexOf('CREATE OR REPLACE FUNCTION "crm"."postventa_tarea_fn"(')
const fin = esquema.indexOf('\nALTER FUNCTION', inicio)
assert(inicio >= 0 && fin > inicio, 'Falta la definición original del writer')
const leer = nombre => readFileSync(new URL(nombre, import.meta.url), 'utf8')
const sinTransaccion = sql => sql
  .replace(/^begin(?: transaction read only)?;$/gm, '')
  .replace(/^(?:commit|rollback);$/gm, '')
const funciones = [
  'crm.registro_actividad_v2_fn(date,date,uuid[],text[],text,integer,timestamptz,uuid,text,text)',
  'crm.gestiones_resumen_fn(date,date,uuid[])',
  'crm.citas_clientes_fn(date,date,uuid[],integer,timestamptz,uuid)',
  'crm.gestion_diaria_citas_v2_fn(date,text,uuid,integer,timestamptz,uuid)',
  'crm.gestion_diaria_pendientes_v2_fn(uuid,boolean,integer,timestamptz,uuid)',
  'private.gestiones_validar(date,date,uuid[])',
  'private.gestiones_clientes_identidades(jsonb)',
  'private.gestion_cliente_identidad(uuid,uuid)',
  'private.gestiones_clientes_eventos(date,date,uuid[],boolean,integer,text[],timestamptz,uuid,text)',
  'private.gestiones_operativas_eventos(date,date,uuid[],boolean,integer,text[],timestamptz,uuid,text,text,text)',
  'private.citas_clientes_core(date,date,uuid[],integer,timestamptz,uuid)',
  'private.gestiones_identificar_tareas(jsonb)',
]
const posterior = sinTransaccion(leer('comprobar-tras-aplicar.sql'))
const migraciones = ['20261005224214_crm_resultados_cliente_postventa.sql', '20261006012208_crm_gestiones_clientes_supervision.sql']
const sql = [
  'begin;', posterior,
  `drop function ${funciones.join(',')};`,
  'drop index crm.inversionista_gestiones_autor_fecha_idx,crm.inversionista_gestiones_cierre_tarea_idx,crm.actividades_cliente_autor_fecha_idx;',
  esquema.slice(inicio, fin),
  sinTransaccion(leer('preflight.sql')),
  ...migraciones.map(n => sinTransaccion(leer('../../migrations/' + n))),
  posterior,
  ...['test.sql', 'test-casos.sql', 'test-integracion.sql'].map(leer),
  await catalogosUiSql(), leer('test-revision.sql'), 'rollback;',
].join('\n')
const r = spawnSync(process.execPath, [fileURLToPath(new URL('banco.mjs', import.meta.url)), 'consulta'], {
  input: sql, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024,
})
if (r.status !== 0) {
  process.stderr.write(r.stderr || r.error?.message || 'No terminó el ensayo local\n')
  process.exit(1)
}
process.stdout.write(r.stdout)
process.stdout.write('PASS entrega: preflight → ambas migraciones exactas → catálogo y permisos → cuatro suites SQL → ROLLBACK\n')
