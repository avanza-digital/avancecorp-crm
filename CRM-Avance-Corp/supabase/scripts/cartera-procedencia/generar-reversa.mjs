// Genera reversa.sql: retira la firma de 11 argumentos y restaura la de 10
// publicada el 16/09 BYTE A BYTE. La definición se toma de la copia del banco,
// que el ensayo exige idéntica a producción (md5 de pg_get_functiondef medido en
// producción el 19/09: be33021420cd8ae2edbf58692b45e9eb). Las huellas de la
// firma nueva (md5 y huella del censo) llegan de verificacion.json, escrito por
// ensayar.mjs tras instalar; sin ellas la reversa no sabría qué está retirando.
import { readFileSync, writeFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { sql } from './banco.mjs';

export const F10 = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text)';
export const F11 = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text)';
export const F10_LARGA = 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text)';
export const F11_LARGA = 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text)';
export const MD5_F10 = 'be33021420cd8ae2edbf58692b45e9eb'; // producción, 19/09
export const HUELLA_F10 = 'd7a47e4c8377115178d75fc2bfcd35a2'; // censo en producción, 19/09
const RAZON_F10 = 'Inventario operativo único para listado y resumen: filtros de etapa, analista, búsqueda, recepción del dueño actual y origen del lead. No calcula conversión mensual: el adaptador general conserva el núcleo oficial.';
const COMENTARIO_F10 = 'Leads e indicadores con filtros comunes: etapa, analista, búsqueda, recepción y origen. Recepción del analista actual, días inclusivos de Lima, un lead por resultado. RLS vigente y sin acceso a otros equipos. Sin fechas conserva inventario operativo de 45 días.';

const q = (s) => "'" + s.replaceAll("'", "''") + "'";

/** Definición viva de la firma de 10 (del banco a paridad), o la de pg_temp si ya se retiró. */
export function definicionF10() {
  const def = sql(`select pg_get_functiondef(to_regprocedure('${F10}'))`);
  assert.ok(def.startsWith('CREATE OR REPLACE FUNCTION crm.cartera_filtrada_fn('), 'La firma de 10 no está en el banco');
  const md5 = sql(`select md5(pg_get_functiondef(to_regprocedure('${F10}')))`);
  assert.equal(md5, MD5_F10, 'La definición del banco no es la de producción');
  return def;
}

export function generarReversa({ md5F11, huellaF11, definicion }) {
  assert.match(md5F11, /^[0-9a-f]{32}$/); assert.match(huellaF11, /^[0-9a-f]{32}$/);
  return `-- Reversa de la procedencia: retira la firma de 11 argumentos y restaura la
-- de 10 publicada el 16/09 (definición tomada del banco a paridad con producción,
-- md5 ${MD5_F10}) con su declaración analítica original.
-- Ejecutar solo tras retirar el frontend que envía p_procedencia (las pestañas
-- ya abiertas conservan su JavaScript hasta recargar: pueden seguir enviándolo).
-- Guardas: no retira una función corregida después de esta entrega ni re-sella
-- una lista de exenciones alterada por fuera. No toca datos.
-- GENERADO por supabase/scripts/cartera-procedencia/generar-reversa.mjs; no editar a mano.
begin;
set local lock_timeout='10s';
lock table private.analitica_leads_citas_exenciones,private.analitica_leads_citas_tope,
  private.analitica_lc_sello in share row exclusive mode;
do $preflight$
begin
  if to_regprocedure('${F11}') is null
     or (select count(*) from pg_proc where proname='cartera_filtrada_fn' and pronamespace='crm'::regnamespace)<>1 then
    raise exception 'REVERSA: la firma de 11 argumentos no es la única instalada';
  end if;
  -- Exactamente la función publicada por 20260919170500 (md5 de la definición y
  -- huella del censo medidos al ensayarla); una corrección posterior no se pisa.
  if md5(pg_get_functiondef('${F11}'::regprocedure)) is distinct from '${md5F11}'
     or (select huella from private.analitica_leads_citas_exenciones where objeto='${F11_LARGA}')
        is distinct from '${huellaF11}'
     or not exists (select 1 from private.contadores_crudos_leads_citas()
        where objeto='${F11_LARGA}' and declarada and huella_ok) then
    raise exception 'REVERSA: la función de 11 argumentos no es la publicada por 20260919170500';
  end if;
  if (select sello from private.analitica_lc_sello where id) is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'REVERSA: la lista de exenciones no coincide con su sello; no se re-sella a ciegas';
  end if;
end;
$preflight$;
create temporary table cartera_procedencia_reversa on commit drop as
select (select jsonb_agg(to_jsonb(e) order by objeto) from private.analitica_leads_citas_exenciones e
    where objeto<>'${F11_LARGA}') as otras,
  (select to_jsonb(t) from private.analitica_leads_citas_tope t where id) as tope,
  (select proacl from pg_proc where oid='${F11}'::regprocedure) as acl,
  (select count(*) from private.contadores_crudos_leads_citas()) as censo,
  (select coalesce(string_agg(objeto,',' order by objeto),'') from private.contadores_crudos_leads_citas()
    where not (declarada and huella_ok)) as censo_rojo,
  md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) as resumen_md5;

drop function ${F11};
${definicion.trimEnd()}
;
revoke all on function ${F10} from public, anon, authenticated, service_role;
grant execute on function ${F10} to authenticated;
comment on function ${F10} is ${q(COMENTARIO_F10)};

-- La declaración analítica vuelve a la firma de 10 con su huella y razón del
-- 16/09 (fecha de declaración intacta) y se re-sella.
update private.analitica_leads_citas_exenciones e set
  objeto='${F10_LARGA}',
  huella='${HUELLA_F10}',
  razon=${q(RAZON_F10)}
where e.objeto='${F11_LARGA}';
update private.analitica_lc_sello set sello=private.huella_exenciones_analitica_lc(),sellado_en=now() where id;

do $postflight$
declare f text:='${F10}';
begin
  if md5(pg_get_functiondef(f::regprocedure)) is distinct from '${MD5_F10}' then
    raise exception 'REVERSA: la función restaurada no es byte a byte la del 16/09';
  end if;
  if not exists(select 1 from pg_proc p where p.oid=to_regprocedure(f)
      and p.proowner='postgres'::regrole and not p.prosecdef
      and p.provolatile='s' and p.proconfig @> array['search_path=""'])
    or has_function_privilege('anon',f,'EXECUTE')
    or has_function_privilege('service_role',f,'EXECUTE')
    or not has_function_privilege('authenticated',f,'EXECUTE')
    or (select proacl from pg_proc where oid=to_regprocedure(f))
       is distinct from (select acl from cartera_procedencia_reversa) then
    raise exception 'REVERSA: contrato de seguridad inválido para %',f;
  end if;
  if to_regprocedure('${F11}') is not null
    or (select count(*) from pg_proc where proname='cartera_filtrada_fn' and pronamespace='crm'::regnamespace)<>1 then
    raise exception 'REVERSA: la firma de 11 sigue instalada';
  end if;
  if (select count(*) from private.contadores_crudos_leads_citas())
       <> (select censo from cartera_procedencia_reversa)
    or not exists (select 1 from private.contadores_crudos_leads_citas()
       where objeto='${F10_LARGA}' and declarada and huella_ok)
    or (select coalesce(string_agg(objeto,',' order by objeto),'') from private.contadores_crudos_leads_citas()
       where not (declarada and huella_ok)) <> (select censo_rojo from cartera_procedencia_reversa)
    or (select sello from private.analitica_lc_sello where id) is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'REVERSA: el censo analítico no quedó como se esperaba';
  end if;
  if (select jsonb_agg(to_jsonb(e) order by objeto) from private.analitica_leads_citas_exenciones e
      where objeto<>'${F10_LARGA}')
       is distinct from (select otras from cartera_procedencia_reversa)
    or (select to_jsonb(t) from private.analitica_leads_citas_tope t where id)
       is distinct from (select tope from cartera_procedencia_reversa)
    or md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure))
       is distinct from (select resumen_md5 from cartera_procedencia_reversa) then
    raise exception 'REVERSA: cambió una declaración ajena, el techo o el resumen general';
  end if;
end;
$postflight$;
notify pgrst,'reload schema';
commit;
`;
}

if (process.argv[1] && import.meta.url.endsWith(process.argv[1].split('/').pop())) {
  const v = JSON.parse(readFileSync(new URL('verificacion.json', import.meta.url), 'utf8'));
  const salida = generarReversa({ md5F11: v.md5_f11, huellaF11: v.huella_f11, definicion: definicionF10() });
  writeFileSync(new URL('reversa.sql', import.meta.url), salida);
  console.log(`reversa escrita (${salida.length} bytes)`);
}
