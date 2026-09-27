import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { spawnSync } from 'node:child_process'

// Banco sintético exclusivo. No acepta URL, credenciales ni destinos remotos.
const carpeta = new URL('.', import.meta.url)
const migracion = readFileSync(new URL('../../migrations/20260927015203_crm_ranking_cartera_legada.sql', carpeta), 'utf8')
const prueba = readFileSync(new URL('prueba-local.sql', carpeta), 'utf8')
const reversion = readFileSync(new URL('revertir.sql', carpeta), 'utf8')
if (prueba.split('-- @MIGRACION@').length !== 2) throw new Error('Debe existir un solo punto de instalación')
if (prueba.split('-- @REVERSION@').length !== 2) throw new Error('Debe existir una sola reversión')
const sql = prueba.replace('-- @MIGRACION@', migracion).replace('-- @REVERSION@', reversion)
function ejecutar(nombre, sql, falloEsperado) {
const resultado = spawnSync('docker', ['exec', '-i', 'supabase_db_crm-avance-corp-local',
  'psql', '-X', '-U', 'postgres', '-d', 'ranking_cartera_20260926', '-v', 'ON_ERROR_STOP=1'],
{ input: sql, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024, timeout: 120_000 })
if (resultado.error) throw resultado.error
if (falloEsperado && resultado.status !== 0 && resultado.stderr?.includes(falloEsperado)) {
  console.log(`PASS: ${nombre}; mutante rechazado por su aserción específica`)
  return
}
process.stdout.write(resultado.stdout ?? '')
process.stderr.write(resultado.stderr ?? '')
if (falloEsperado) throw new Error(`Mutante no detectado correctamente: ${nombre}`)
if (resultado.status !== 0) process.exit(resultado.status ?? 1)
console.log(`PASS: ${nombre}; transacción revertida`)
}
ejecutar(fileURLToPath(new URL('prueba-local.sql', carpeta)), sql)
const regresion = readFileSync(new URL('../ranking-origen/prueba-local.sql', carpeta), 'utf8')
const inicio = `begin;
set local statement_timeout = '40s';
set local lock_timeout = '3s';
select set_config('crm.op_privilegiada','on',true);
`
ejecutar('regresión previa del ranking bajo el candidato', inicio + migracion + regresion + '\nrollback;')
ejecutar('mes ya sellado conserva foto y respuesta pública', inicio + regresion + `
create temp table fotos_antes as select * from crm.cierre_mes_vendedor;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000003',true);
create temp table rpc_antes as select crm.ranking_origen_vendedor_fn('2026-09-01',
 'b0000000-0000-4000-8000-000000000002') as datos;
` + migracion + `
do $$ begin
 if not exists(select 1 from fotos_antes where origenes_ranking is not null) then
   raise exception 'Sello de prueba vacío';
 end if;
 if exists((select * from fotos_antes except all select * from crm.cierre_mes_vendedor)
 union all (select * from crm.cierre_mes_vendedor except all select * from fotos_antes)) then
   raise exception 'La migración alteró una foto sellada';
 end if;
 if (select datos from rpc_antes) is distinct from crm.ranking_origen_vendedor_fn(
 '2026-09-01','b0000000-0000-4000-8000-000000000002') then
   raise exception 'La lectura pública del mes cerrado cambió';
 end if;
 raise notice 'PASS: foto no vacía y RPC sellada intactas tras migración';
end $$;
rollback;`)

// Las defensas negativas deben detectar la ausencia de cada guarda.
// No basta con que el candidato sin mutar dé los importes esperados.
for (const [guarda, fallo] of [
  ['and o.cliente_id = c.cliente_id', 'FAIL: ledger de otro cliente no clasifica'],
  ['and o.moneda = c.moneda', 'FAIL: ledger de otra moneda no clasifica'],
  ['and o.fecha_operacion = c.fecha_cierre_comercial', 'FAIL: ledger de otra fecha no clasifica'],
]) {
  if (!migracion.includes(guarda)) throw new Error(`No existe la guarda: ${guarda}`)
  ejecutar(`sin ${guarda}`, prueba.replace('-- @MIGRACION@', migracion.replace(guarda, ''))
    .replace('-- @REVERSION@', reversion), fallo)
}
