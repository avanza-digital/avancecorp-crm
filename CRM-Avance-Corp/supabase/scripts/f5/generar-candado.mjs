// Corrección aditiva: la migración F5 original permanece inmutable.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const archivo='20260909170900_crm_f5_candado_estado_cartera.sql';
const ruta=new URL(`../../migrations/${archivo}`,import.meta.url);
const modulo=readFileSync(new URL('02-estado-bajo-candado.sql',import.meta.url),'utf8');
assert.equal((modulo.match(/create or replace function /g)??[]).length,1);
const sql=`-- F5: corregir el censo D-19 sin alterar el archivo ya versionado.
-- Instalar después de 20260908230249_crm_f5_cartera_ficha_multiempresa.sql.
-- Generado por scripts/f5/generar-candado.mjs; no activa ninguna bandera.
do $pre$
begin
  if to_regprocedure('crm.cartera_inversionistas_estado_fn()') is null
    or to_regprocedure('private.resolver_en_puertas_bajo_candado()') is null then
    raise exception 'Faltan F5 o el bloqueo publicado de identidad';
  end if;
  if (select md5(prosrc) from pg_proc where oid='crm.cartera_inversionistas_estado_fn()'::regprocedure)
    is distinct from 'f8da95a16b2134e5046b82ddaf82a740' then
    raise exception 'La capacidad F5 cambió: revisar antes de sustituirla';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='ficha_360_neutral'),true) then
    raise exception 'Instalar la corrección con F5 apagada';
  end if;
end;
$pre$;

${modulo}
do $post$
begin
  if not exists(select 1 from pg_proc p where p.oid='crm.cartera_inversionistas_estado_fn()'::regprocedure
    and p.prosecdef and p.proowner='postgres'::regrole and p.provolatile='v'
    and p.proconfig @> array['search_path=""','lock_timeout=5s']
    and strpos(p.prosrc,'resolver_en_puertas_bajo_candado()')>0)
    or has_function_privilege('anon','crm.cartera_inversionistas_estado_fn()','EXECUTE')
    or has_function_privilege('service_role','crm.cartera_inversionistas_estado_fn()','EXECUTE')
    or not has_function_privilege('authenticated','crm.cartera_inversionistas_estado_fn()','EXECUTE') then
    raise exception 'Postflight: revisar bloqueo, volatilidad y permisos de F5';
  end if;
end;
$post$;
notify pgrst, 'reload schema';
`;
if(process.argv.includes('--check'))assert.equal(readFileSync(ruta,'utf8'),sql,'La corrección versionada difiere del módulo');
else writeFileSync(ruta,sql);
console.log(JSON.stringify({archivo,sha256:createHash('sha256').update(sql).digest('hex'),funciones:1,banderasModificadas:0}));
