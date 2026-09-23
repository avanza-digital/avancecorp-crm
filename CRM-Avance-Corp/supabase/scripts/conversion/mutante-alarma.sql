-- MUTANTE DE LA ALARMA — SOLO EN BRANCH. Termina SIEMPRE en rollback.
--
-- Una alarma que nunca ha sonado no se sabe si funciona. Este guion inyecta
-- a propósito una discrepancia entre caminos: reemplaza, dentro de una
-- transacción que se deshace, el envoltorio crm.metricas_conversiones_fn por
-- uno que suma 1 al numerador del núcleo del rango. Luego pregunta a la
-- alarma. Si dice «cuadra», el mutante sobrevivió y la alarma es de adorno.
--
-- NO correrlo contra producción: aunque el rollback deshace el reemplazo, es
-- DDL sobre una función viva. Es para el branch de Supabase:
--   supabase db query --db-url "$BRANCH_DB_URL" --file supabase/scripts/conversion/mutante-alarma.sql
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $antes$
declare v_r jsonb;
begin
  v_r := crm.alarma_conversion_fn();
  if (v_r ->> 'cuadra')::boolean is distinct from true then
    raise exception 'ANTES DEL MUTANTE la alarma ya está en rojo: % — arreglar eso primero', v_r;
  end if;
  raise notice 'antes del mutante: cuadra=true · %', v_r -> 'detalle';
end;
$antes$;

-- El mutante: mismo gate, misma implementación, numerador del núcleo + 1.
create or replace function crm.metricas_conversiones_fn(p_desde date, p_hasta date, p_origen text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $mutante$
declare
  v_actor uuid := (select auth.uid());
  v_payload jsonb;
begin
  if v_actor is null or not coalesce(private.rol_crm(v_actor) = 'gerencia' or private.es_lector_global(), false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  v_payload := private.metricas_conversiones_implementacion(p_desde, p_hasta, p_origen);
  v_payload := jsonb_set(v_payload, '{nucleo,numerador}',
    to_jsonb((v_payload -> 'nucleo' ->> 'numerador')::numeric + 1), false);
  return private.filtrar_desglose_sujetos_crm(v_payload, 'responsables', 'vendedor_id', array['vendedor']);
end;
$mutante$;

do $despues$
declare v_r jsonb;
begin
  v_r := crm.alarma_conversion_fn();
  if (v_r ->> 'cuadra')::boolean then
    raise exception 'FILO 1 SOBREVIVIÓ: el rango publica numerador+1 y la alarma dice cuadra. La alarma NO protege nada. %', v_r;
  end if;
  raise notice 'FILO 1 CAZADO (numerador del rango +1): cuadra=false · %', v_r -> 'detalle';

end;
$despues$;

-- Pase lo que pase, el envoltorio vuelve a ser el de antes.
-- ── FILO 2: mover SOLO EL DIVISOR del rango ─────────────────────────────────
-- Lo levantó el auditor el 22/09. Al pasar la comparación a «los TRES
-- publicados entre sí», el DIVISOR del núcleo dejaba de estar anclado y este
-- mutante SOBREVIVIRÍA. La migración de la conciliación recuperó esa cláusula;
-- este filo la prueba.
--
-- 🔑 La deuda solo toca el NUMERADOR (`greatest(num - pend, 0)`), nunca el
-- divisor. Así que el divisor DEBE seguir idéntico en los cuatro caminos, haya
-- deuda o no: un desvío ahí es un fallo real, no una consecuencia del ajuste.
create or replace function crm.metricas_conversiones_fn(p_desde date, p_hasta date, p_origen text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $mutante2$
declare
  v_actor uuid := (select auth.uid());
  v_payload jsonb;
begin
  if v_actor is null or not coalesce(private.rol_crm(v_actor) = 'gerencia' or private.es_lector_global(), false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  v_payload := private.metricas_conversiones_implementacion(p_desde, p_hasta, p_origen);
  v_payload := jsonb_set(v_payload, '{nucleo,divisor}',
    to_jsonb((v_payload -> 'nucleo' ->> 'divisor')::numeric + 1), false);
  return private.filtrar_desglose_sujetos_crm(v_payload, 'responsables', 'vendedor_id', array['vendedor']);
end;
$mutante2$;

do $despues2$
declare v_r jsonb;
begin
  v_r := crm.alarma_conversion_fn();
  if coalesce((v_r ->> 'cuadra')::boolean, false) then
    raise exception 'FILO 2 SOBREVIVIÓ: el rango publica divisor+1 y la alarma dice cuadra. El divisor no está anclado. %', v_r;
  end if;
  raise notice 'FILO 2 CAZADO (divisor del rango +1): cuadra=false · %', v_r -> 'detalle';
end;
$despues2$;

rollback;
