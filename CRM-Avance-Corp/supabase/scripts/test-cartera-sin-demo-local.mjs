// Banco contractual aislado. NO acepta URLs, TCP ni credenciales productivas.
// Uso: node ...mjs /tmp/avancecorp-cartera.XXXXXX archivo_migracion.sql
// El cluster debe estar recién creado por initdb, con listen_addresses=''.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'

const socket = process.argv[2]
const migrationName = process.argv[3]
assert.match(socket ?? '', /^\/tmp\/avancecorp-cartera\.[A-Za-z0-9]+$/)
assert.match(migrationName ?? '', /^\d{14}_crm_cartera_excluir_contratos_demo\.sql$/)
const args = ['-X', '-w', '-h', socket, '-p', '55437', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-A', '-t']
function query(sql, expectedError) {
  const result = spawnSync('psql', [...args, '-c', sql], { encoding: 'utf8', maxBuffer: 2_000_000 })
  if (expectedError) {
    assert.notEqual(result.status, 0, 'La guarda debía rechazar la operación')
    assert.match(result.stderr, expectedError)
  } else {
    assert.equal(result.status, 0, result.stderr || String(result.error))
  }
  return result.stdout.trim()
}
assert.equal(query("select (inet_server_addr() is null and current_setting('listen_addresses')='' and to_regnamespace('crm') is null)::text"), 'true')
const fixture = readFileSync(new URL('./test-cartera-sin-demo-fixtures.sql', import.meta.url), 'utf8')
const migration = readFileSync(new URL('../migrations/' + migrationName, import.meta.url), 'utf8')
const rollback = readFileSync(new URL('./rollback-cartera-excluir-demo.sql', import.meta.url), 'utf8')
query(fixture)
query(migration)

query(`
do $test$
declare ctx record; c record; resultado jsonb; resultado_v2 jsonb;
  cuotas integer; titulares integer; visible boolean; filas_vista integer;
begin
 for ctx in select x.*,o.real,o.real_v2 from public.contextos x join public.oraculo o using(nombre) loop
  perform set_config('cartera.actor',coalesce(ctx.actor::text,''),true);
  perform set_config('cartera.rol',coalesce(ctx.rol,''),true);
  perform set_config('cartera.global',ctx.global::text,true);
  perform set_config('cartera.visibles',ctx.visibles::text,true);
  set local role authenticated;
  select coalesce(jsonb_agg(to_jsonb(f) order by f.id),'[]') into resultado from crm.contratos_cartera_fn() f;
  select coalesce(jsonb_agg(to_jsonb(f) order by f.id),'[]') into resultado_v2 from crm.contratos_cartera_v2_fn() f;
  select count(*) into filas_vista from crm.contratos_cartera;
  reset role;
  if resultado is distinct from ctx.real or resultado_v2 is distinct from ctx.real_v2
     or filas_vista <> jsonb_array_length(ctx.real) then
    raise exception 'Fachada, V2 o vista no concilian: %',ctx.nombre;
  end if;
  for c in select id from public.contratos loop
    visible := ctx.real @> jsonb_build_array(jsonb_build_object('id',c.id));
    set local role authenticated;
    select count(*) into cuotas from crm.cronograma_contrato_fn(c.id);
    select count(*) into titulares from crm.titulares_contrato_fn(c.id);
    reset role;
    if cuotas <> visible::integer or titulares <> visible::integer then
      raise exception 'Dependencias fuera de ámbito: %',ctx.nombre;
    end if;
  end loop;
 end loop;
 begin
  set local role anon;
  perform * from crm.contratos_cartera_fn();
  raise exception 'anon no debía ejecutar la fachada';
 exception when insufficient_privilege then reset role;
 end;
 if (select huella from public.datos_antes) is distinct from
    (select md5(string_agg(to_jsonb(ct)::text,',' order by ct.id)) from public.contratos ct) then
   raise exception 'La migración modificó datos contractuales';
 end if;
end;
$test$;
select 'CARTERA_SIN_DEMO_LOCAL_OK: 7 contextos, V1/V2/vista, 56 cronogramas y 56 titulares, ACL y datos intactos';
`)
// Un segundo intento debe abortar; no sobrescribe un estado distinto.
query(migration, /La fachada cambio o no existe/)
query(rollback)
query(`
do $test$
declare ctx record; resultado jsonb;
begin
 for ctx in select x.*,o.original from public.contextos x join public.oraculo o using(nombre) loop
  perform set_config('cartera.actor',coalesce(ctx.actor::text,''),true);
  perform set_config('cartera.rol',coalesce(ctx.rol,''),true);
  perform set_config('cartera.global',ctx.global::text,true);
  perform set_config('cartera.visibles',ctx.visibles::text,true);
  set local role authenticated;
  select coalesce(jsonb_agg(to_jsonb(f) order by f.id),'[]') into resultado from crm.contratos_cartera_fn() f;
  reset role;
  if resultado is distinct from ctx.original then raise exception 'Reversión no concilia: %',ctx.nombre; end if;
 end loop;
end;
$test$;
`)
query(migration)
assert.equal(query("select md5(pg_get_functiondef('crm.contratos_cartera_fn()'::regprocedure))"), 'afa02c967897b50312d1a963deed0d44')
console.log('CARTERA_SIN_DEMO_LOCAL_OK: 7 contextos, V1/V2/vista, 56 cronogramas, 56 titulares, ACL, reversión, reaplicación y datos intactos')
