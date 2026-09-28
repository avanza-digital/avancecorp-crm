// Emite SQL para una BD local vacía. No abre conexiones ni conoce credenciales.
// Verifica componentes del cambio; no sustituye replay, vigilante ni RLS remotos.
import { readFileSync } from 'node:fs'
const leer = (ruta) => readFileSync(new URL(ruta, import.meta.url), 'utf8')
const anterior = leer('../../migrations/20260927172930_crm_vigilante_pre_citas.sql')
const migracion = leer('../../migrations/20260928163532_crm_ranking_origen_acreditado.sql')
function extraer(texto, inicio, fin) {
  const a = texto.indexOf(inicio)
  const b = texto.indexOf(fin, a)
  if (a < 0 || b < 0) throw new Error(`No se encontró ${inicio}`)
  return texto.slice(a, b + fin.length)
}
process.stdout.write([
  '\\set ON_ERROR_STOP on',
  leer('./prueba-acreditaciones-fixture.sql'),
  extraer(anterior, 'create function private.ranking_vinculos_lead_filas(', '$function$;'),
  extraer(anterior, 'create or replace function private.ranking_capital_origen_filas(', '$function$;'),
  "create temp table antes as select * from private.ranking_capital_origen_filas('2026-09-01 00:00-05','2026-10-01 00:00-05',null);",
  extraer(migracion, 'create function private.ranking_origenes_acreditados_filas(', '$cambio$;'),
  leer('./prueba-acreditaciones-aserciones.sql'),
].join('\n'))
