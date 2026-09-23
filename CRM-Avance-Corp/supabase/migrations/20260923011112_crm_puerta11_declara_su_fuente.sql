-- =========================================================================
-- CRM · Ola 2 · La puerta #11 (resumen de cartera) DECLARA su fuente
-- =========================================================================
-- QUE HACE: anade las cuatro claves del contrato al payload de
-- `crm.resumen_cartera_fn()`. Nada mas. NO cambia ni un numero.
--
-- LA EXCEPCION DEL GRUPO: esta puerta **no publica ninguna tasa**. Publica
-- recuentos —`totales.convertidos` (cierres del mes, sin ponderar) y
-- `totales.operaciones_cartera`— que no pasan por ningun divisor. No hay cifra
-- que delegar; lo unico que le faltaba era decir con que criterio cuenta.
--
-- Por eso declara `ajuste_aplicado: false` sin que eso sea un defecto: la deuda
-- de anulacion se resta del NUMERADOR PONDERADO, que aqui no existe. Ponerle
-- `true` seria afirmar algo que la funcion no hace.
--
-- ENTRA SIN PESTILLO: `ResumenCarteraSchema` del front es `v.object`
-- (`app/src/lib/resumen-cartera.ts:44`), que ignora lo que no conoce.
--
-- MEDIDO EN PRODUCCION EL 22/09/2026, y fijado en el preflight:
--   · md5(pg_get_functiondef) = b4ffcf91c130265d86def01b5e5a0863
--   · dueno postgres · clase `operativo` · **NO en el censo** de contadores
--     crudos -> no hay huella que re-sellar; el postflight exige que siga fuera.
--
-- REVERSA: volver a declarar el cuerpo sin las cuatro claves.
-- =========================================================================

begin;

set local statement_timeout = '180s';

do $preflight$
declare v_md5 text;
begin
  select md5(pg_get_functiondef(p.oid)) into v_md5 from pg_proc p
   where p.oid = to_regprocedure('crm.resumen_cartera_fn()');
  if v_md5 is distinct from 'b4ffcf91c130265d86def01b5e5a0863' then
    raise exception 'PREFLIGHT: el cuerpo vivo NO es el revisado (md5 %)', v_md5;
  end if;
  if not exists (select 1 from pg_proc p
                  where p.oid = to_regprocedure('crm.resumen_cartera_fn()')
                    and p.proowner = 'postgres'::regrole and p.prosecdef and p.provolatile = 's') then
    raise exception 'PREFLIGHT: dueno, definer o volatilidad inesperados';
  end if;
end;
$preflight$;

create temp table _p11_antes (payload jsonb) on commit drop;

do $antes$
declare
  v_claims text := current_setting('request.jwt.claims', true);
  v_gerente uuid;
begin
  select e.perfil_id into v_gerente from crm.equipo e
   where e.rol_crm = 'gerencia' and e.activo and private.rol_crm(e.perfil_id) = 'gerencia'
   order by e.perfil_id limit 1;
  if v_gerente is null then
    raise exception 'PREFLIGHT: no hay perfil de gerencia activo';
  end if;
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', v_gerente, 'role', 'authenticated')::text, true);
  begin
    insert into _p11_antes (payload) select crm.resumen_cartera_fn();
  exception when others then
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
end;
$antes$;

CREATE OR REPLACE FUNCTION crm.resumen_cartera_fn()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid:=(select auth.uid());
  v_rol text:=private.rol_crm(v_uid);
  v_lector boolean:=private.es_lector_global();
  v_visibles uuid[]:=array(select private.vendedor_ids_visibles(v_uid));
  v_ahora timestamptz:=now();
  v_mes date:=date_trunc('month',v_ahora at time zone 'America/Lima')::date;
  v_payload jsonb;
  v_cierres bigint;
  v_operaciones bigint;
begin
  if v_uid is null or (v_rol is null and not v_lector) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  v_payload:=crm.cartera_filtrada_fn(p_limite=>1)->'resumen';
  select coalesce(sum(n.cierres_no_referidos+n.cierres_referidos),0),coalesce(sum(n.operaciones),0)
  into v_cierres,v_operaciones from (
    select e.analista_id,
      count(distinct e.lead_id) filter(where e.tipo='cierre' and not e.anulado and not e.fue_referido) as cierres_no_referidos,
      count(distinct e.lead_id) filter(where e.tipo='cierre' and not e.anulado and e.fue_referido) as cierres_referidos,
      count(*) filter(where e.tipo='operacion') as operaciones
    from private.conversion_episodios(v_mes::timestamp at time zone 'America/Lima',
      (v_mes+interval '1 month')::timestamp at time zone 'America/Lima',v_mes,true,'{}'::uuid[],
      private.peso_referido_conversion(v_mes)) e
    where e.analista_id=any(v_visibles) or v_rol='gerencia' or v_lector
    group by e.analista_id
  ) n;
  return v_payload || jsonb_build_object(
    -- DECLARACION (Ola 2, 22/09/2026). Esta puerta es la excepcion del grupo:
    -- NO publica ninguna tasa de conversion. Lo que publica es un RECUENTO
    -- —`totales.convertidos`, cierres del mes sin ponderar, y
    -- `totales.operaciones_cartera`— que no pasa por ningun divisor. Por eso
    -- no delega: no hay cifra que delegar.
    --   es_mes_calendario: true. Siempre mide el mes en curso (`v_mes` = dia 1),
    --     y ya lo decia en `ventana_metrica`.
    --   fuente: 'rango_vivo'. Cuenta sobre `private.conversion_episodios`.
    --   sellado: null. No se delego, asi que no sabe si el mes esta sellado.
    --   ajuste_aplicado: false. Un recuento de cierres no resta la deuda de
    --     anulacion: esa resta vive en el NUMERADOR ponderado, que esta puerta
    --     no publica. Declararlo `true` seria afirmar algo que no hace.
    'es_mes_calendario', true,
    'fuente', 'rango_vivo',
    'sellado', null,
    'ajuste_aplicado', false,
    'version',1,'generado_en',v_ahora,
    'ventana_convertidos_dias',45,'ventana_metrica','mes_calendario','mes_metrica',v_mes,
    'totales',(v_payload->'totales') || jsonb_build_object('convertidos',v_cierres,'operaciones_cartera',v_operaciones));
end;
$function$;

do $postflight$
declare
  v_ok text; v_antes jsonb; v_despues jsonb; v_a jsonb; v_d jsonb;
  v_claims text := current_setting('request.jwt.claims', true);
  v_gerente uuid;
begin
  v_ok := private.assert_analitica_leads_citas();
  if v_ok not like 'OK:%' then
    raise exception 'POSTFLIGHT: el trinquete quedo en rojo: %', v_ok;
  end if;

  select payload into v_antes from _p11_antes;
  select e.perfil_id into v_gerente from crm.equipo e
   where e.rol_crm = 'gerencia' and e.activo and private.rol_crm(e.perfil_id) = 'gerencia'
   order by e.perfil_id limit 1;
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', v_gerente, 'role', 'authenticated')::text, true);
  begin
    v_despues := crm.resumen_cartera_fn();
  exception when others then
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

  -- 1) NI UN NUMERO MOVIDO.
  v_a := v_antes - 'generado_en';
  v_d := (v_despues - 'generado_en')
           - 'es_mes_calendario' - 'fuente' - 'sellado' - 'ajuste_aplicado';
  if v_a is distinct from v_d then
    raise exception 'POSTFLIGHT: movio algo fuera de las cuatro claves. Bloques distintos: %',
      (select string_agg(k, ', ' order by k) from jsonb_object_keys(v_a) k
        where (v_a -> k) is distinct from (v_d -> k));
  end if;

  -- 2) Las cuatro claves, con los valores que le corresponden a una puerta que
  --    CUENTA en vez de dividir.
  if (v_despues ->> 'es_mes_calendario')::boolean is not true
     or (v_despues ->> 'fuente') is distinct from 'rango_vivo'
     or v_despues -> 'sellado' <> 'null'::jsonb
     or (v_despues ->> 'ajuste_aplicado')::boolean is not false then
    raise exception 'POSTFLIGHT: declaracion inesperada: %',
      jsonb_build_object('es_mes_calendario', v_despues -> 'es_mes_calendario',
                         'fuente', v_despues -> 'fuente', 'sellado', v_despues -> 'sellado',
                         'ajuste_aplicado', v_despues -> 'ajuste_aplicado');
  end if;

  -- 3) Sigue sin publicar ninguna tasa: si algun dia la publicara, esta
  --    declaracion se quedaria corta y habria que revisarla.
  if v_despues #> '{totales,conversion_pct}' is not null
     or v_despues -> 'conversion_pct' is not null then
    raise exception 'POSTFLIGHT: esta puerta empezo a publicar una tasa; su declaracion ya no vale';
  end if;

  -- 4) Dueno, definer, volatilidad y search_path, intactos.
  if not exists (select 1 from pg_proc p
                  where p.oid = to_regprocedure('crm.resumen_cartera_fn()')
                    and p.proowner = 'postgres'::regrole and p.prosecdef
                    and p.provolatile = 's' and p.proconfig @> array['search_path=""']) then
    raise exception 'POSTFLIGHT: cambio el dueno, el definer, la volatilidad o el search_path';
  end if;

  -- 5) Sigue FUERA del censo de contadores crudos.
  if exists (select 1 from private.contadores_crudos_leads_citas() c
              where c.objeto = 'crm.resumen_cartera_fn()') then
    raise exception 'POSTFLIGHT: ENTRO al censo; hay que declarar su huella aqui mismo';
  end if;
end;
$postflight$;

comment on function crm.resumen_cartera_fn() is
  'Resumen de la cartera del mes en curso. Desde la Ola 2 (22/09/2026) declara su fuente. Es '
  'la excepcion de las doce puertas: NO publica ninguna tasa de conversion, sino recuentos '
  '(totales.convertidos = cierres del mes sin ponderar, totales.operaciones_cartera), asi que '
  'no hay cifra que delegar. es_mes_calendario=true, fuente=rango_vivo, sellado=null y '
  'ajuste_aplicado=false: la deuda de anulacion se resta del numerador ponderado, que aqui no '
  'existe.';

select 'puerta11-declara-su-fuente' as migracion,
       private.assert_analitica_leads_citas() as trinquete;

commit;
