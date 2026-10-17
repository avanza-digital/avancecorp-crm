import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import assert from 'node:assert/strict'
import { nombres, cuerpoMigracion } from './migraciones-locales.mjs'

let fixture = readFileSync(new URL('prueba-atribucion.sql', import.meta.url), 'utf8')
  .split('-- @MIGRACION_OPERACIONES@')[0]
const migraciones = nombres.map((nombre) => {
  const cuerpo = cuerpoMigracion(nombre)
  if (nombre !== '20261016220524_crm_facturacion_detalle_cortes.sql') return cuerpo
  return `
create temp table lista_paridad_antes(actor uuid,periodo date,resultado jsonb);
do $paridad$ declare a record; m date; anterior text:=current_setting('request.jwt.claim.sub',true); begin
  for a in select perfil_id from crm.equipo where rol_crm in('supervisor','coordinador') loop
    perform set_config('request.jwt.claim.sub',a.perfil_id::text,true);
    foreach m in array array[date '2026-09-01',date '2026-10-01'] loop
      insert into lista_paridad_antes values(a.perfil_id,m,crm.listar_operaciones_facturacion_v2_fn(m,(m+interval '1 month - 1 day')::date));
    end loop;
  end loop;
  perform set_config('request.jwt.claim.sub',coalesce(anterior,''),true);
end $paridad$;
${cuerpo}
do $paridad$ declare a record; anterior text:=current_setting('request.jwt.claim.sub',true); begin
  for a in select * from lista_paridad_antes loop
    perform set_config('request.jwt.claim.sub',a.actor::text,true);
    if a.resultado is distinct from crm.listar_operaciones_facturacion_v2_fn(a.periodo,(a.periodo+interval '1 month - 1 day')::date) then
      raise exception 'La extracción de Facturación cambió un payload v2';
    end if;
  end loop;
  perform set_config('request.jwt.claim.sub',coalesce(anterior,''),true);
end $paridad$;
select pg_temp.comprobar((select bool_or((resultado->>'total')::integer>0) from lista_paridad_antes),'payloads v2 idénticos antes/después, con datos y ámbitos de supervisión/coordinación');
`
}).join('\n')
const prueba = readFileSync(new URL('prueba-cortes.sql', import.meta.url), 'utf8')
  .replace('-- @REEVALUACION_CIERRE@', () => readFileSync(new URL('prueba-reevaluacion.sql', import.meta.url), 'utf8'))
  .replace('-- @CITAS_SIN_CORTE@', () => readFileSync(new URL('prueba-citas-sin-corte.sql', import.meta.url), 'utf8'))
  .replace('-- @CITAS_CON_CORTE@', () => readFileSync(new URL('prueba-citas.sql', import.meta.url), 'utf8'))
  .replace('-- @CITAS_PENDIENTE@', () => readFileSync(new URL('prueba-citas-pendiente.sql', import.meta.url), 'utf8'))
  .replace('-- @CITAS_SELLADO@', () => readFileSync(new URL('prueba-citas-sellado.sql', import.meta.url), 'utf8'))
const escritores = readFileSync(new URL('prueba-escritores.sql', import.meta.url), 'utf8')
const catalogo = readFileSync(new URL('prueba-catalogo-public.sql', import.meta.url), 'utf8')
assert.ok(prueba.trimEnd().endsWith('rollback;'))
const replay = process.argv.includes('--replay')
const banco = replay ? `tc_venta_replay_${process.pid}` : 'tc_venta'
assert.match(banco, /^tc_venta(?:_replay_\d+)?$/)
function ejecutar(db, sql) {
  const resultado = spawnSync('docker', ['exec', '-i', 'avancecorp-tc-20261016',
    'psql', '-X', '-qAt', '-U', 'supabase_admin', '-d', db, '-v', 'ON_ERROR_STOP=1', '-f', '-'], {
    input: sql, encoding: 'utf8', timeout: 120_000, maxBuffer: 2 * 1024 * 1024,
  })
  if (resultado.error) throw resultado.error
  if (resultado.status !== 0) throw new Error(resultado.stderr || 'Falló el banco de cortes')
  return resultado
}
let creado = false
let resultado
try {
  if (replay) {
    ejecutar('postgres', `create database ${banco} template tc_venta;`)
    creado = true
    const reversa = readFileSync(new URL('reversa-persistencia.sql', import.meta.url), 'utf8')
    const persistencia = readFileSync(new URL('../../migrations/20261016190725_crm_tipo_cambio_por_venta.sql', import.meta.url), 'utf8')
    ejecutar(banco, reversa + '\n' + persistencia)
    fixture = fixture.replace("current_database()<>'tc_venta'", `current_database()<>'${banco}'`)
  }
  const comprobarPublic = `select pg_temp.comprobar((select huella=pg_temp.huella_catalogo_public() from catalogo_public_antes),'las ${nombres.length+1} candidatas conservan funciones, tablas, columnas, constraints, triggers, RLS y permisos de public');`
  resultado = ejecutar(banco, fixture + '\n' + catalogo + '\n' + migraciones + '\n' + comprobarPublic + '\n' + escritores + '\n' + prueba)
} finally {
  if (creado) ejecutar('postgres', `drop database ${banco} with(force);`)
}
const mensajes = (resultado.stderr ?? '').split('\n').filter((s) => s.includes('PASS:'))
for (const mensaje of mensajes) console.log(mensaje)
for (const mensaje of (resultado.stderr ?? '').split('\n').filter((s) => s.includes('MEDICION:'))) console.log(mensaje)
console.log(`PASS: ${mensajes.length} aserciones de cortes y permisos; rollback completo`)
if (replay) console.log(`PASS: replay íntegro de las ${nombres.length + 1} migraciones desde esquema base; clon propio eliminado`)
if (process.argv.includes('--fixtures') || process.argv.includes('--fixtures-citas')) {
  const soloCitas = process.argv.includes('--fixtures-citas')
  const fixtures = Object.fromEntries(resultado.stdout.split('\n').filter((linea) => linea.startsWith('{'))
    .map((linea) => JSON.parse(linea)).filter((objeto) => objeto.tc_fixture)
    .filter((objeto) => objeto.tc_fixture.startsWith('citas-') === soloCitas)
    .map((objeto) => [objeto.tc_fixture, objeto.payload]))
  assert.deepEqual(Object.keys(fixtures).sort(), soloCitas
    ? ['citas-activo', 'citas-pendiente', 'citas-sellado', 'citas-sin-corte']
    : ['activo', 'detalle', 'detalle-sellado', 'facturacion', 'facturacion-lista', 'facturacion-lista-coordinacion', 'facturacion-lista-mixta', 'pendiente', 'sellado'])
  const directorio = new URL(soloCitas ? '../../../app/test-fixtures/capital-valorado/'
    : '../../../app/src/lib/__fixtures__/capital-valorado/', import.meta.url)
  mkdirSync(directorio, { recursive: true })
  for (const [nombre, payload] of Object.entries(fixtures)) {
    writeFileSync(new URL(`${nombre}.json`, directorio), JSON.stringify(payload, null, 2) + '\n')
  }
  console.log('PASS: fixtures de API generados al ejecutar el banco SQL sintético, sin filas productivas')
}
