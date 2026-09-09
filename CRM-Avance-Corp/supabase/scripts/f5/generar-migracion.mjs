// Ensambla el SQL exacto de F5. No conecta a una base ni enciende banderas.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const ruta=new URL('../../migrations/20260908230249_crm_f5_cartera_ficha_multiempresa.sql',import.meta.url);
const modulo=readFileSync(new URL('01-lecturas.sql',import.meta.url),'utf8');
assert.equal((modulo.match(/create or replace function /g)??[]).length,9);
assert(!/\b(?:alter|create|drop)\s+(?:table|function|trigger|policy)\s+(?:if\s+exists\s+)?public\./i.test(modulo));
const pre=`-- F5: cartera y ficha multiempresa. Candidata revisable; no encender producción.
-- Prerrequisito: revisión publicada F4 20260908211349 (no su candidata anterior).
-- Este archivo es generado por scripts/f5/generar-migracion.mjs.
do $pre$
begin
  if to_regprocedure('crm.confirmar_inversion_revisada_fn(uuid,integer)') is null
    or to_regprocedure('private.inversion_persona_contexto(uuid)') is null then
    raise exception 'Falta el prerrequisito publicado de F4';
  end if;
  if not exists(select 1 from crm.multiempresa_flags where nombre='ficha_360_neutral')
    or exists(select 1 from crm.multiempresa_flags where nombre='ficha_360_neutral' and activo) then
    raise exception 'Instalar F5 con su bandera existente apagada';
  end if;
end;
$pre$;

`;
const post=`
-- Sin grants de tabla ni permisos de escritura nuevos. La API solo ejecuta RPC.
do $post$
declare n integer;
begin
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
  where (ns.nspname='crm' and p.proname in ('cartera_inversionistas_estado_fn','cartera_inversionistas_fn',
    'inversionista_ficha_fn','inversionista_cuentas_fn','inversionista_documento_fn')
    or ns.nspname='private' and p.proname in ('cartera_f5_fuentes','cartera_f5_exigir','cartera_f5_personas_visibles','cartera_f5_registrar'))
    and p.prosecdef and p.proconfig=array['search_path=""'];
  if n<>9 or not (select relrowsecurity from pg_class where oid='crm.cartera_lecturas'::regclass)
    or has_table_privilege('authenticated','crm.cartera_lecturas','SELECT') then
    raise exception 'Postflight F5: revisar funciones, search_path, RLS y ACL';
  end if;
end;
$post$;
notify pgrst, 'reload schema';
`;
const sql=pre+modulo+post;
if(process.argv.includes('--check')) assert.equal(readFileSync(ruta,'utf8'),sql,'El SQL versionado difiere del módulo revisado');
else writeFileSync(ruta,sql);
console.log(JSON.stringify({archivo:ruta.pathname.split('/').at(-1),sha256:createHash('sha256').update(sql).digest('hex'),funciones:9,tablas:1,banderasModificadas:0}));
