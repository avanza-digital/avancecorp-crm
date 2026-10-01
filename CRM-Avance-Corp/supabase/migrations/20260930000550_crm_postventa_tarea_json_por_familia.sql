-- ============================================================================
-- Agenda de postventa: los perfiles de la persona se buscan en su familia, no en las
-- 565 personas (private.postventa_tarea_json)
-- ============================================================================
-- Paso 3 · fase 1 del refactor por módulos, aprobado por Miguel el 29/09/2026 («dale»).
-- Nota del vault: «CRM - perfil de carga lectura vs escritura (2026-09-29)».
--
-- Problema medido en producción (29/09): la lista de tareas (tareas_pendientes_fn, 22 ms) arrastra
-- la agenda de postventa (postventa_agenda_fn, 532 ms) en cada carga de Hoy/agenda de todos los
-- analistas y supervisores (~1.300 veces al día). De esos 532 ms, 320 ms son `postventa_perfil_ids`:
-- por cada una de las 16 tareas de postventa se recorren las 565 personas llamando a
-- inversionista_canonica() dos veces por fila.
--
-- Cambio: las candidatas salen de la FAMILIA de la persona (su raíz canónica y quienes cuelgan de
-- ella, tope 16 como inversionista_canonica) y sobre ese puñado se aplica el MISMO criterio de antes
-- (`inversionista_canonica(i.id) = inversionista_canonica(p_t.inversionista_id)`). Toda persona con la
-- misma canónica cuelga de esa raíz en ≤ 15 saltos, así que el conjunto es idéntico también con
-- ciclos o cadenas raras; hoy no hay ninguna persona con padre (0). Prototipo medido: 320 ms → 1 ms;
-- equivalencia comprobada sobre las 568 personas (0 distintas). Nada más cambia: misma firma,
-- STABLE STRICT, INVOKER, search_path vacío, dueño y ACL. Ninguna puerta ni el front cambian.
--
-- Huellas (md5 de pg_get_functiondef): viva c29fd1d25ab775ecd63ab2660a847d0e → nueva bff893c533d645be75d884788173bd50.
-- Idempotente y fail-closed. Reversa: supabase/scripts/postventa-tarea-familia/reversa.sql (restaura el
-- cuerpo vivo del 29/09 tal cual; conserva la fila de schema_migrations: anotarlo en el ledger).

begin;
set local lock_timeout = '10s';

do $mig$
declare
  v_md5 text; v_oid oid := 'private.postventa_tarea_json(crm.tareas)'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  -- Invariantes que la huella NO cubre: dueño, ACL (nunca NULL), INVOKER (no definer), STABLE y search_path
  -- vacío (se guarda como search_path="", con comillas). Se evalúa con IS NOT TRUE para que un NULL también rechace.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is false and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'PREFLIGHT: dueño/ACL/definer/volatilidad/search_path de la función viva no son los esperados (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  if v_md5 = 'bff893c533d645be75d884788173bd50' then
    raise notice 'postventa_tarea_json_por_familia: ya aplicada (huella %)', v_md5;
    return;
  end if;
  if v_md5 <> 'c29fd1d25ab775ecd63ab2660a847d0e' then
    raise exception 'PREFLIGHT: private.postventa_tarea_json(crm.tareas) no es el cuerpo vivo del 29/09/2026 (huella %)', v_md5;
  end if;

  execute $def$
CREATE OR REPLACE FUNCTION private.postventa_tarea_json(p_t crm.tareas)
 RETURNS jsonb
 LANGUAGE sql
 STABLE STRICT
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'id',p_t.id,'lead_id',p_t.lead_id,'perfil_id',p_t.perfil_id,
    'inversionista_id',p_t.inversionista_id,'postventa_revision',p_t.postventa_revision,
    'inversionista_canonico_id',private.inversionista_canonica(p_t.inversionista_id),
    'postventa_perfil_ids',(with recursive familia as (
        -- Candidatas: la raíz canónica de la persona y quienes cuelgan de ella (tope 16, como
        -- inversionista_canonica). Es un superconjunto de las personas con la misma canónica; el
        -- filtro de abajo conserva el criterio EXACTO de antes sin recorrer las 565 personas por
        -- tarea (320 de los 532 ms de la agenda de postventa, medido el 29/09/2026).
        select i.id,1 as n from crm.inversionistas i where i.id=private.inversionista_canonica(p_t.inversionista_id)
        union all
        select i.id,f.n+1 from crm.inversionistas i join familia f on i.inversionista_canonico_id=f.id where f.n<16)
      select array(select i.perfil_id from crm.inversionistas i
        where i.id in (select f.id from familia f) and i.perfil_id is not null
          and private.inversionista_canonica(i.id)=private.inversionista_canonica(p_t.inversionista_id)
        order by i.perfil_id)),
    'vendedor_id',p_t.vendedor_id,'asignado_supervisor_id',p_t.asignado_supervisor_id,
    'tipo',p_t.tipo,'titulo',p_t.titulo,'nota',p_t.nota,'vence_en',p_t.vence_en,
    'duracion_min',p_t.duracion_min,'estado',p_t.estado,'modalidad_reunion',p_t.modalidad_reunion,
    'ubicacion_reunion',p_t.ubicacion_reunion,'enlace_reunion',p_t.enlace_reunion,
    'resultado_reunion',p_t.resultado_reunion,'motivo_no_realizada',p_t.motivo_no_realizada,
    'detalle_cierre_reunion',p_t.detalle_cierre_reunion,'confirmada_en',p_t.confirmada_en,
    'reagendada_de',p_t.reagendada_de,'reprogramaciones',p_t.reprogramaciones,
    'activo',p_t.activo,'creado_en',p_t.creado_en);
$function$
$def$;

  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 <> 'bff893c533d645be75d884788173bd50' then
    raise exception 'POSTFLIGHT: huella inesperada tras el cambio (%)', v_md5;
  end if;
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is false and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'POSTFLIGHT: dueño, ACL, definer, volatilidad o search_path cambiaron (dueño %, acl %, definer %, vol %, cfg %)', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  raise notice 'postventa_tarea_json_por_familia: aplicada (huella %)', v_md5;
end $mig$;

commit;
