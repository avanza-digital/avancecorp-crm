-- =========================================================================
-- METAS CONTRA LA OFICIAL, persona por persona · solo lectura
-- =========================================================================
-- Responde a una pregunta: ¿Metas y Ranking publican, para cada analista, la
-- MISMA conversion que la oficial? Desde 20260923164903 las dos beben de una
-- sola pieza del nucleo (private.conversion_neta_por_vendedor), asi que esto
-- tiene que salir siempre en PASS; si no, alguien volvio a calcular por su
-- cuenta en una de las dos.
--
-- Compara, como Gerencia y en el mes vigente y el anterior:
--   · cada fila de Metas (crm.cumplimiento_metas_fn -> vendedores) con la de la
--     oficial (crm.conversion_mensual_fn -> responsables): numerador,
--     conversion_real = conversion_pct, resueltos = divisor, los dos cierres,
--     la deuda pendiente, y convertidos = no referidos + referidos + clientes
--     de cartera;
--   · cada persona de «fuera del ranking» a la que la oficial NOMBRA: su
--     numerador tiene que ser el de la oficial (el NETO).
--
-- COMO SE CORRE:
--   supabase db query --linked --file supabase/scripts/conversion/metas-vs-oficial.sql
-- Termina SIEMPRE en `raise`, asi que el resultado llega como un error. Eso es
-- lo que garantiza que no escribe nada.
-- =========================================================================

do $v$
declare
  v_claims text := current_setting('request.jwt.claims', true);
  v_ger uuid;
  v_vigente date := date_trunc('month', (now() at time zone 'America/Lima'))::date;
  v_mes date;
  o jsonb;
  m jsonb;
  v_filas integer;
  v_fallos text;
  v_fuera integer;
  v_fallos_fuera text;
  v_salida text := '';
  v_todo_ok boolean := true;
begin
  select e.perfil_id into v_ger
    from crm.equipo e
   where e.rol_crm = 'gerencia' and e.activo and private.rol_crm(e.perfil_id) = 'gerencia'
   order by e.perfil_id limit 1;
  if v_ger is null then
    raise exception 'metas-vs-oficial: no hay perfil de gerencia activo para pedir las dos cifras';
  end if;
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', v_ger, 'role', 'authenticated')::text, true);

  foreach v_mes in array array[v_vigente, (v_vigente - interval '1 month')::date] loop
    o := crm.conversion_mensual_fn(v_mes);
    m := crm.cumplimiento_metas_fn(v_mes);

    select count(*),
           string_agg(format('%s num=%s/%s pct=%s/%s div=%s/%s nr=%s/%s r=%s/%s deuda=%s/%s conv=%s/%s',
             left(r ->> 'vendedor_id', 8),
             r ->> 'numerador', v ->> 'numerador',
             r ->> 'conversion_pct', v ->> 'conversion_real',
             r ->> 'divisor', v ->> 'resueltos',
             r ->> 'cierres_no_referidos', v ->> 'cierres_no_referidos',
             r ->> 'cierres_referidos', v ->> 'cierres_referidos',
             r #>> '{ajuste,pendiente}', v #>> '{ajuste,pendiente}',
             (r ->> 'cierres_no_referidos')::numeric + (r ->> 'cierres_referidos')::numeric
               + coalesce((r #>> '{cartera,conversiones_clientes}')::numeric, 0),
             v ->> 'convertidos'), ' | ')
             filter (where (r -> 'numerador') is distinct from (v -> 'numerador')
                        or (r -> 'conversion_pct') is distinct from (v -> 'conversion_real')
                        or (r -> 'divisor') is distinct from (v -> 'resueltos')
                        or (r -> 'cierres_no_referidos') is distinct from (v -> 'cierres_no_referidos')
                        or (r -> 'cierres_referidos') is distinct from (v -> 'cierres_referidos')
                        or (r #> '{ajuste,pendiente}') is distinct from (v #> '{ajuste,pendiente}')
                        or ((r ->> 'cierres_no_referidos')::numeric + (r ->> 'cierres_referidos')::numeric
                            + coalesce((r #>> '{cartera,conversiones_clientes}')::numeric, 0))
                           is distinct from (v ->> 'convertidos')::numeric)
      into v_filas, v_fallos
      from jsonb_array_elements(coalesce(o -> 'responsables', '[]'::jsonb)) r
      join jsonb_array_elements(coalesce(m -> 'vendedores', '[]'::jsonb)) v
        on v ->> 'vendedor_id' = r ->> 'vendedor_id';

    select count(*),
           string_agg(format('%s fuera=%s oficial=%s', left(f ->> 'persona_id', 8),
             f #>> '{conversion,numerador}', r ->> 'numerador'), ' | ')
             filter (where (f #> '{conversion,numerador}') is distinct from (r -> 'numerador'))
      into v_fuera, v_fallos_fuera
      from jsonb_array_elements(coalesce(m -> 'fuera_ranking', '[]'::jsonb)) f
      join jsonb_array_elements(coalesce(o -> 'responsables', '[]'::jsonb)) r
        on r ->> 'vendedor_id' = f ->> 'persona_id'
     where f -> 'conversion' <> 'null'::jsonb;

    v_todo_ok := v_todo_ok and v_fallos is null and v_fallos_fuera is null and v_filas > 0;
    v_salida := v_salida || format(E'\n%s · %s personas comparadas · %s de fuera del ranking nombradas por la oficial · %s',
      v_mes, v_filas, v_fuera,
      case when v_fallos is null and v_fallos_fuera is null and v_filas > 0 then 'PASS'
           when v_filas = 0 then 'FAIL (nada que comparar: comparacion vacua)'
           else 'FAIL: ' || coalesce(v_fallos, '') || ' ' || coalesce(v_fallos_fuera, '') end);
  end loop;

  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  raise exception 'METAS VS OFICIAL >> % %', case when v_todo_ok then 'PASS' else 'FAIL' end, v_salida;
end;
$v$;
