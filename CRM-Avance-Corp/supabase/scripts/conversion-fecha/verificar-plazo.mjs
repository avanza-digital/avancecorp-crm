import { readFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'

const base = new URL('.', import.meta.url)
const migracion = readFileSync(new URL('../../migrations/20260927073637_crm_conversion_fecha_comercial_plazo.sql', base), 'utf8')
const prueba = readFileSync(new URL('prueba-plazo.sql', base), 'utf8')
const activacionBanco = readFileSync(new URL('activar-politica-banco.sql', base), 'utf8')
if (prueba.split('-- @MIGRACION@').length !== 2) throw new Error('Punto de instalación duplicado o ausente')
// Destino exclusivo, local y sintético. No acepta URL/env de producción.
function ejecutar(nombre, candidato, falloEsperado, pruebaElegida = prueba, marca = 'PASS: calendario', activarUnidad = true) {
  const r = spawnSync('docker', ['exec', '-i', 'supabase_db_crm-avance-corp-local',
    'psql', '-X', '-U', 'postgres', '-d', 'conversion_fecha_20260927', '-v', 'ON_ERROR_STOP=1'],
  { input: pruebaElegida.replace('-- @MIGRACION@', candidato + (activarUnidad ? activacionBanco : '')), encoding: 'utf8', timeout: 45_000, maxBuffer: 2 ** 20 })
  if (r.error) throw r.error
  if (falloEsperado) {
    if (r.status === 0 || !r.stderr.includes(`FAIL: ${falloEsperado}`)) {
      process.stderr.write(r.stderr)
      throw new Error(`Mutante sobrevivió o falló por otra causa: ${nombre}`)
    }
  } else if (r.status !== 0 || !r.stdout.includes(marca)) {
    process.stderr.write(r.stdout.slice(-3000))
    process.stderr.write(r.stderr)
    throw new Error(`Falló ${nombre}`)
  }
  console.log(`PASS: ${nombre}; conexión cerrada y transacción revertida`)
}
ejecutar('calendario y decisión temporal', migracion)
ejecutar('registro estable de acreditación', migracion, null,
  readFileSync(new URL('prueba-acreditacion.sql', base), 'utf8'), 'PASS: acreditacion estable')
ejecutar('selección exacta e históricos no vacíos', migracion, null,
  readFileSync(new URL('prueba-regresiones.sql', base), 'utf8'), 'PASS: regresiones')
ejecutar('integración de enlace, corrección, cierre y anulación', migracion, null,
  readFileSync(new URL('prueba-integracion.sql', base), 'utf8').replace('-- @RELOJ_CIERRE@',
    readFileSync(new URL('reloj-cierre-banco.sql', base), 'utf8')), 'PASS: integracion')
ejecutar('lectura autorizada y estados', migracion, null,
  readFileSync(new URL('prueba-estado.sql', base), 'utf8'), 'PASS: lectura de estado')
ejecutar('fuente excluida antes del sello, sin deuda posterior', migracion, null,
  readFileSync(new URL('prueba-exclusion-sello.sql', base), 'utf8').replace('-- @RELOJ_CIERRE@',
    readFileSync(new URL('reloj-cierre-banco.sql', base), 'utf8')), 'PASS: exclusion anterior')
ejecutar('retirada de fuente antes y después del sello', migracion, null,
  readFileSync(new URL('prueba-retiro-sello.sql', base), 'utf8').replace('-- @RELOJ_CIERRE@',
    readFileSync(new URL('reloj-cierre-banco.sql', base), 'utf8')), 'PASS: retiro antes')
ejecutar('instalación sin hueco y activación atómica', migracion, null,
  readFileSync(new URL('prueba-activacion.sql', base), 'utf8'), 'PASS: activacion atomica', false)
ejecutar('reversa exacta y compatible', migracion, null,
  readFileSync(new URL('prueba-reversa.sql', base), 'utf8').replace('-- @REVERSA@',
    readFileSync(new URL('reversa.sql', base), 'utf8').replace(/^begin;\n/m, '').replace(/commit;\s*$/, '')),
  'PASS: reversa compatible')
// Reusar el banco oficial de escritores compartidos (incluye Avance/Auth y
// cooperativa). Usa dos de sus seis leads; nuestra plantilla tiene dos libres.
// No se altera la suite original ni se omite una validación de negocio.
let escritores = readFileSync(new URL('../conversion-inversion/test-conversion.sql', base), 'utf8')
for (const [original, reemplazo] of [
  ['begin;\n', `begin;\n-- @MIGRACION@\n
    -- Completar el firmante sintético del banco de Ranking: el PDF exige su
    -- correo legal, además del DNI/teléfono que ya completa la suite original.
    update public.perfiles set correo=coalesce(nullif(correo,''),'analista.conversion@example.invalid')
      where id='b0000000-0000-4000-8000-000000000002';\n`],
  ["(select count(*) from ci_leads)=6", "(select count(*) from ci_leads)>=2"],
  ["perform pg_temp.exigir(r->>'estado'='preparada','solicitud no preparada');", `
    perform pg_temp.exigir(r->>'estado'='preparada','solicitud no preparada');
    perform pg_temp.exigir(not exists(select 1 from crm.conversion_acreditaciones where lead_id=l.id),
      'solicitud pendiente no reserva credito');`],
  ["repetido:=crm.confirmar_inversion_revisada_fn(solicitud,0);", `
    repetido:=crm.confirmar_inversion_revisada_fn(solicitud,0);
    perform pg_temp.exigir((select count(*)=1 from crm.conversion_acreditaciones where lead_id=l.id
      and fuente_tipo='cierre_externo' and fuente_id=(confirmado#>>'{fuente,cierre_id}')::uuid and estado='acreditada'),
      'cooperativa confirmada acredita una vez la fuente exacta');`],
  ["set constraints all immediate;", `
    set constraints all immediate;
    perform pg_temp.exigir((select count(*)=1 from crm.conversion_acreditaciones where lead_id=l.id
      and fuente_tipo='contrato' and fuente_id=(confirmado#>>'{fuente,id}')::uuid and estado='acreditada'),
      'Avance confirmado acredita la fuente exacta');`],
  ["rollback;", "select 'PASS: escritores reales confirmados' as resultado;\nrollback;"],
]) {
  if (!escritores.includes(original)) throw new Error('Cambió el punto de integración del banco de escritores')
  escritores = escritores.replace(original, reemplazo)
}
ejecutar('escritores reales de Avance y cooperativa', migracion, null, escritores, 'PASS: escritores reales')
for (const [nombre, original, alterado, fallo] of [
  ['no recortar el día 10', "interval '1 month 10 days'", "interval '1 month 9 days'", 'dia 10 completo Lima'],
  ['corte excluido', 'acreditado_en >= plazo_hasta', 'acreditado_en > plazo_hasta', 'corte exacto'],
  ['vínculo obligatorio', 'greatest(p_confirmado_en, p_vinculado_en)', 'p_confirmado_en', 'vinculo tardio'],
  ['confirmación obligatoria', "when p_confirmado_en is null then 'pendiente_confirmacion'", '', 'pendiente no reserva'],
  ['sello respetado', "when p_sellado_en is not null and acreditado_en >= p_sellado_en then 'mes_sellado'", '', 'sello ya existente'],
]) {
  if (!migracion.includes(original)) throw new Error(`Falta la guarda de ${nombre}`)
  ejecutar(nombre, migracion.replace(original, alterado), fallo)
}
