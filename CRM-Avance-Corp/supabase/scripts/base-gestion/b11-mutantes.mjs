// B11 · Mutantes: cada defensa de la suite b11-conversion.sql se neutraliza por separado, dentro de una transacción que
// termina en ROLLBACK, y la suite DEBE caer. Si un mutante sobrevive, esa defensa no está probada y el script falla.
// Requiere B11 aplicada en un banco LOCAL (superusuario del stack: supabase_admin). No acepta URL ni credenciales.
// Uso: node supabase/scripts/base-gestion/b11-mutantes.mjs --puerto <puerto>
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

const i = process.argv.indexOf('--puerto')
const puerto = i > 0 ? process.argv[i + 1] : null
assert.ok(puerto && /^\d+$/.test(puerto), 'Uso: b11-mutantes.mjs --puerto <puerto>')

const aqui = (r) => new URL(r, import.meta.url)
const migracion = readFileSync(aqui('../../migrations/20261006042144_crm_bases_cargadas_conversion.sql'), 'utf8')
const reversa = readFileSync(aqui('./reversa-b11.sql'), 'utf8')
const suite = readFileSync(aqui('./b11-conversion.sql'), 'utf8')

// La suite sin su begin/rollback, para correrla dentro de la transacción del mutante.
const cuerpo = suite.slice(suite.indexOf('do $suite$'), suite.lastIndexOf('rollback;'))
assert.ok(cuerpo.includes('$suite$;'), 'no se encontró el bloque de la suite')

/** El CREATE OR REPLACE de `nombre(` tal como lo trae `texto` (hasta su `$function$;`). */
function bloque(texto, nombre) {
  const ini = texto.indexOf(`CREATE OR REPLACE FUNCTION ${nombre}(`)
  assert.ok(ini >= 0, `no está ${nombre}`)
  const fin = texto.indexOf('$function$;', texto.indexOf('AS $function$', ini) + 13) + '$function$;'.length
  return texto.slice(ini, fin)
}
function cambiar(texto, viejo, nuevo) {
  assert.equal(texto.split(viejo).length - 1, 1, `ancla no única o ausente: ${viejo.slice(0, 80)}`)
  return texto.replace(viejo, nuevo)
}
const nueva = (n) => bloque(migracion, n)
const vieja = (n) => bloque(reversa, n)

const mutantes = [
  ['ayudante sin base_cargada', `create or replace function private.conversion_origen_con_cierre(p_origen text) returns boolean
     language sql immutable parallel safe security invoker set search_path = '' as $$ select p_origen in ('landing', 'formulario', 'referido') $$;`],
  ['conversion_cierres vieja (base pesa 0)', vieja('private.conversion_cierres')],
  ['conversion_cierres: la rama de acreditaciones con la lista vieja', cambiar(nueva('private.conversion_cierres'),
    'when private.conversion_origen_con_cierre(ca.origen) then 1', "when ca.origen in ('landing', 'formulario') then 1")],
  ['registrar_ajuste_si_mes_cerrado vieja', vieja('private.registrar_ajuste_si_mes_cerrado')],
  ['conversion_mensual_por_vendedor vieja', vieja('private.conversion_mensual_por_vendedor')],
  ['metricas_conversiones_equipo_fn vieja', vieja('crm.metricas_conversiones_equipo_fn')],
  ['metricas_conversiones_implementacion vieja', vieja('private.metricas_conversiones_implementacion')],
  ['metricas_distribucion_leads_v3_core vieja', vieja('private.metricas_distribucion_leads_v3_core')],
  ['conversion_mensual_sin_cartera_fn vieja (sonda)', vieja('crm.conversion_mensual_sin_cartera_fn')],
  ['divisor de empresa: base contada como 0', cambiar(nueva('private.conversion_divisor_empresa'),
    "(count(*) filter (where e.tipo = 'cierre' and e.origen = 'base_cargada'))::integer as cierres_base_cargada",
    '0::integer as cierres_base_cargada')],
  ['divisor de empresa: «otros» sigue contando la base', cambiar(nueva('private.conversion_divisor_empresa'),
    "'oficina', 'base_cargada')))::integer as cierres_otros", "'oficina')))::integer as cierres_otros")],
  ['divisor de empresa: mes sellado con 0 inventado', cambiar(nueva('private.conversion_divisor_empresa'),
    '           null::integer\n    from foto f', '           0::integer\n    from foto f')],
  ['totales: base sin sumar', cambiar(nueva('private.conversion_divisor_empresa_totales'),
    'case when v_cierre.periodo is null then coalesce(sum(f.cierres_base_cargada), 0)::integer end as cierres_base_cargada',
    '0::integer as cierres_base_cargada')],
  ['totales: mes sellado con 0 inventado', cambiar(nueva('private.conversion_divisor_empresa_totales'),
    'case when s.desglose_disponible then s.cierres_base_cargada end\n  from suma s;',
    'case when s.desglose_disponible then coalesce(s.cierres_base_cargada, 0) end\n  from suma s;')],
  ['coordinación: sin la clave en los analistas', cambiar(nueva('crm.conversion_divisor_coordinacion_fn'),
    ",\n            'base_cargada', f.cierres_base_cargada", '')],
  ['coordinación: sin la clave en la empresa', cambiar(nueva('crm.conversion_divisor_coordinacion_fn'),
    ",\n        'base_cargada', v_totales.cierres_base_cargada", '')],
]

function correr(sql) {
  const r = spawnSync('psql', ['-X', '-q', '-v', 'ON_ERROR_STOP=1', '-h', '127.0.0.1', '-p', puerto, '-U', 'supabase_admin', '-d', 'postgres', '-f', '-'],
    { encoding: 'utf8', input: sql, env: { ...process.env, PGPASSWORD: 'postgres' }, maxBuffer: 16 * 1024 * 1024 })
  return (r.stdout || '') + (r.stderr || '')
}
const PASA = /PASS 23 de 23/

const control = correr(`begin;\nset local search_path = '';\n${cuerpo}\nrollback;\n`)
assert.match(control, PASA, `CONTROL: la suite no pasa sin mutar:\n${control.slice(-600)}`)
console.log('control: la suite pasa (23/23)')

let vivos = 0
for (const [nombre, mut] of mutantes) {
  const salida = correr(`begin;\nset local search_path = '';\n${mut}\n${cuerpo}\nrollback;\n`)
  const sobrevive = PASA.test(salida)
  const motivo = (salida.match(/ERROR:\s+([^\n]+)/) || [, '(sin error)'])[1]
  console.log(`${sobrevive ? 'SOBREVIVE' : 'CAE      '} · ${nombre}${sobrevive ? '' : ` → ${motivo.slice(0, 110)}`}`)
  if (sobrevive) vivos++
}
console.log(`${mutantes.length - vivos} de ${mutantes.length} mutantes caen`)
if (vivos) process.exit(1)
