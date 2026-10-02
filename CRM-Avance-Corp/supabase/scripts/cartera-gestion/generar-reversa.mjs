// Genera reversa.sql: retira la firma de 13 argumentos y reinstala la de 12 BYTE A BYTE.
// La definición de la de 12 NO se reteclea: la toma `ensayar.mjs` del banco con
// `pg_get_functiondef` mientras sigue viva (md5 7169d942…, la de producción) y llega aquí
// tal cual. Las huellas de la firma nueva (md5 y huella del censo) se miden al instalarla.
import assert from 'node:assert/strict';

export const VERSION = '20261001154153';
export const NOMBRE = 'crm_cartera_filtro_gestion';
export const F12 = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean)';
export const F13 = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
export const F12_LARGA = 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean)';
export const F13_LARGA = 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
// Identidad de la función viva antes de esta entrega (producción = banco, con search_path vacío).
export const MD5_F12 = '7169d94239dcb191bafa3faed46f916f';
export const MD5_PROSRC_F12 = 'e48f00b152c965d3bae303a9660dad09';
export const HUELLA_F12 = '1e2cdd16e5d59f2dd6a8280052312009'; // huella del censo analítico
// Textos que dejó 20260929195918_crm_leads_reasignados.sql; la reversa los devuelve.
const RAZON_F12 = 'Inventario operativo unico para listado y resumen: filtros de etapa, analista, busqueda, recepcion, origen, procedencia y reasignacion entre analistas. No calcula conversion mensual.';
const COMENTARIO_F12 = 'Inventario de Leads con filtros comunes, incluido reasignados: titular actual con una asignacion anterior a un analista. Sistema/Manual conserva el alta. Filas, totales y embudo desde la misma base, bajo RLS.';

const q = (s) => "'" + s.replaceAll("'", "''") + "'";

export function generarReversa({ definicion12, md5F13, huellaF13 }) {
  assert.match(md5F13, /^[0-9a-f]{32}$/);
  assert.match(huellaF13, /^[0-9a-f]{32}$/);
  assert.ok(definicion12.startsWith('CREATE OR REPLACE FUNCTION crm.cartera_filtrada_fn('), 'La definición de 12 argumentos no viene del banco');
  assert.ok(!definicion12.includes('p_gestion'), 'La definición recibida ya es la nueva');
  return `-- REVERSA de ${VERSION}_${NOMBRE}: retira la firma de 13 argumentos de
-- crm.cartera_filtrada_fn y reinstala la de 12 publicada por 20260929195918 (definición tomada
-- del banco a paridad con producción, md5 ${MD5_F12}), con su declaración
-- analítica original, y resella. No toca datos.
-- ANTES: retirar el frente que envía p_gestion (las pestañas abiertas conservan su JavaScript
-- hasta recargar: con la firma de 12 recibirían PGRST202 al pedir «Gestionado»).
-- Guardas: no retira una función corregida después de esta entrega ni resella una lista de
-- exenciones alterada por fuera. Conserva la fila de schema_migrations: anotarlo en MIGRACIONES.md.
-- LÍMITE: NO detecta un consumidor de SERVIDOR que ya pase p_gestion. plpgsql enlaza tarde: una
-- función que llame crm.cartera_filtrada_fn(..., p_gestion => ...) seguiría existiendo y fallaría
-- al EJECUTARSE contra la firma de 12. Hoy no hay ninguno (resumen_cartera_fn solo pasa
-- p_limite); antes de revertir, buscarlo:
--   select p.oid::regprocedure from pg_proc p where p.prosrc ~ 'p_gestion' and p.proname <> 'cartera_filtrada_fn';
-- GENERADO por supabase/scripts/cartera-gestion/generar-reversa.mjs; no editar a mano.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '30s';
set local search_path = '';

lock table private.analitica_leads_citas_exenciones,
  private.analitica_lc_sello in share row exclusive mode;

do $preflight$
declare
  f12 constant text := '${F12}';
  f13 constant text := '${F13}';
  f13_larga constant text := '${F13_LARGA}';
begin
  if (
    to_regprocedure(f13) is not null
    and to_regprocedure(f12) is null
    and (select count(*) from pg_proc where proname = 'cartera_filtrada_fn'
           and pronamespace = 'crm'::regnamespace) = 1
  ) is not true then
    raise exception 'REVERSA: la firma de 13 argumentos no es la unica instalada';
  end if;
  -- Exactamente lo que publicó ${VERSION}: una corrección posterior no se pisa.
  if (
    md5(pg_get_functiondef(to_regprocedure(f13))) = '${md5F13}'
    and (select e.huella from private.analitica_leads_citas_exenciones e where e.objeto = f13_larga) = '${huellaF13}'
    and exists (select 1 from private.contadores_crudos_leads_citas() c
                 where c.objeto = f13_larga and c.declarada and c.huella_ok)
  ) is not true then
    raise exception 'REVERSA: la funcion de 13 argumentos no es la publicada por ${VERSION}';
  end if;
  if ((select s.sello from private.analitica_lc_sello s where s.id)
        = private.huella_exenciones_analitica_lc()) is not true then
    raise exception 'REVERSA: la lista de exenciones no coincide con su sello; no se resella a ciegas';
  end if;
end;
$preflight$;

create temporary table cartera_gestion_reversa on commit drop as
select
  (select to_jsonb(p) from (select proowner::regrole::text as duenio,
      prosecdef, provolatile, proconfig, proacl
    from pg_proc where oid = '${F13}'::regprocedure) p) as contrato,
  (select count(*) from private.contadores_crudos_leads_citas()) as censo,
  (select coalesce(string_agg(c.objeto, ',' order by c.objeto), '')
    from private.contadores_crudos_leads_citas() c
    where not (c.declarada and c.huella_ok)) as censo_rojo,
  (select jsonb_agg(to_jsonb(e) order by e.objeto)
    from private.analitica_leads_citas_exenciones e
    where e.objeto <> '${F13_LARGA}') as otras,
  (select to_jsonb(e) - 'objeto' - 'huella' - 'razon'
    from private.analitica_leads_citas_exenciones e
    where e.objeto = '${F13_LARGA}') as declaracion,
  md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) as resumen_md5;

drop function ${F13};

${definicion12.trimEnd()}
;

revoke all on function ${F12} from public, anon, authenticated, service_role;
grant execute on function ${F12} to authenticated;
comment on function ${F12} is
  ${q(COMENTARIO_F12)};

update private.analitica_leads_citas_exenciones e set
  objeto = '${F12_LARGA}',
  huella = '${HUELLA_F12}',
  razon = ${q(RAZON_F12)}
where e.objeto = '${F13_LARGA}';
update private.analitica_lc_sello
  set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
  where id;

do $postflight$
declare
  f12 constant text := '${F12}';
  f13 constant text := '${F13}';
  f12_larga constant text := '${F12_LARGA}';
  pre record;
begin
  select * into strict pre from pg_temp.cartera_gestion_reversa;
  if (
    to_regprocedure(f13) is null
    and to_regprocedure(f12) is not null
    and (select count(*) from pg_proc where proname = 'cartera_filtrada_fn'
           and pronamespace = 'crm'::regnamespace) = 1
    and md5(pg_get_functiondef(to_regprocedure(f12))) = '${MD5_F12}'
    and not has_function_privilege('anon', f12, 'EXECUTE')
    and not has_function_privilege('service_role', f12, 'EXECUTE')
    and has_function_privilege('authenticated', f12, 'EXECUTE')
    and (select to_jsonb(p) from (select proowner::regrole::text as duenio,
            prosecdef, provolatile, proconfig, proacl
          from pg_proc where oid = to_regprocedure(f12)) p) = pre.contrato
  ) is not true then
    raise exception 'REVERSA: la funcion restaurada no es byte a byte la de 12 argumentos, o cambio su contrato';
  end if;
  if (
    (select s.sello from private.analitica_lc_sello s where s.id)
      = private.huella_exenciones_analitica_lc()
    and (select count(*) from private.contadores_crudos_leads_citas()) = pre.censo
    and exists (select 1 from private.contadores_crudos_leads_citas() c
                 where c.objeto = f12_larga and c.declarada and c.huella_ok)
    and (select coalesce(string_agg(c.objeto, ',' order by c.objeto), '')
           from private.contadores_crudos_leads_citas() c
          where not (c.declarada and c.huella_ok)) = pre.censo_rojo
    and (select jsonb_agg(to_jsonb(e) order by e.objeto)
           from private.analitica_leads_citas_exenciones e
          where e.objeto <> f12_larga) is not distinct from pre.otras
    and (select to_jsonb(e) - 'objeto' - 'huella' - 'razon'
           from private.analitica_leads_citas_exenciones e
          where e.objeto = f12_larga) = pre.declaracion
    and md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) = pre.resumen_md5
  ) is not true then
    raise exception 'REVERSA: el censo analitico, una declaracion o un consumidor ajeno no quedo como estaba';
  end if;
  raise notice 'REVERSA cartera_filtro_gestion OK: vuelve la firma de 12 argumentos (md5 ${MD5_F12}) con su declaracion, sellada.';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
`;
}
