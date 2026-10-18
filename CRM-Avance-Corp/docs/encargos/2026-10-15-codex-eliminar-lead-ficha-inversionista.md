ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo: REFUTAR la migración r2 de «eliminar lead por error de carga» (CRM Avance Corp, Postgres) — LEVEL 3

Contexto: la r1 (20261015044917, ya en producción y revisada por ti en dos rondas) creó `crm.eliminar_lead_error_carga`,
la copia `crm.leads_eliminados` y una llave única `private.borrado_lead_error_autoriza(tabla, fila)` que 8 candados
usan para aceptar un DELETE solo si la fila está copiada idéntica en esta transacción, por el mismo actor, con el
permiso `crm.borrado_lead_error` = id del lead. La r2 (abajo, completa) amplía la puerta a leads que NO son clientes
pero tienen una ficha de inversionista sin dinero, solicitudes de inversión canceladas o una solicitud de tasa sin
usar, y añade la misma excepción al candado `private.trg_solicitudes_tasa_solo_por_puerta`.

Decisión de negocio (Miguel): «el que tiene contrato, inversión, cierre o conversión es cliente y nunca se borra»;
se mantienen el tope de 30 días y el mes sellado. Medido en producción (15/10): de 3.535 leads no clientes, 7 tienen
ficha de inversionista, las 7 exclusivas de su lead y sin inversiones (2 nacieron con el lead por su documento, 5 al
preparar una inversión que no se completó: identificador DNI con fuente `conversion_inversion`, una gestión
`responsable` sin tarea, un responsable, a veces una lectura de cartera); 3 solicitudes de inversión por lead de origen
(2 canceladas, 1 preparada; ninguna con correcciones, revisiones ni orígenes); 1 solicitud de tasa (rechazada, sin
ledger, su lead tiene >30 días). Triggers BEFORE DELETE en las tablas nuevas que se borran: solo
`trg_solicitudes_tasa_00_solo_por_puerta`; `inversion_solicitud_correcciones/revisiones` tienen
`private.f4_fuente_inmutable` (no se toca: si existen filas, la puerta rechaza). Las demás tablas nuevas solo tienen
auditoría AFTER. Todas las FK hacia `crm.inversionistas` son NO ACTION (23, en la lista blanca de la migración).

Intenta ROMPERLA. Formato: VERDICT, SUMMARY, FINDINGS P0–P3 (línea/símbolo + escenario concreto), RISKS/TEST GAPS,
NEXT ACTIONS, CONFIDENCE. Sin hallazgo sin evidencia; separa hipótesis. Preguntas:
1. ¿Puede la r2 borrar algo de un CLIENTE o de OTRA persona/lead (ficha compartida, solicitud de otra ficha, fusión,
   cotitular, cascada)? ¿Falta alguna referencia a la ficha que debería impedir borrarla?
2. ¿El orden de borrado y el cuadre por row_count son correctos con las nuevas tablas (inversion_solicitudes por
   lead_origen O por ficha; inversionista_leads por lead O por ficha)? ¿Puede contarse doble o quedar algo sin copia?
3. ¿Carreras: alguien crea una inversión/solicitud/enlace para la ficha mientras se borra? (la ficha se bloquea
   FOR UPDATE antes de validar; las FK a inversionistas toman KEY SHARE).
4. ¿El candado de tasa con la excepción abre algo fuera de la puerta? ¿Pre/postflight suficientes?

## Migración r2 completa
```sql
-- 20261015150731_crm_eliminar_lead_ficha_inversionista.sql
--
-- «Eliminar lead (error de carga)», r2: también los leads que NO son clientes pero tienen una ficha de inversionista
-- sin dinero, una solicitud de inversión cancelada o una solicitud de tasa sin usar.
-- Pedido de Miguel (15/10/2026, AskUserQuestion): «yo quiero borrar cualquier tipo de lead»; «eso no es un lead, eso ya
-- sería cliente» (contrato, inversión, cierre o conversión: NUNCA se borran); se mantienen el tope de 30 días y el mes
-- sellado. Caso que lo motivó: «Prueba leeds» (17d1f122, 07/10) rechazado por «está enlazado a un inversionista».
--
-- MEDIDO EN PRODUCCIÓN (15/10): de 3.535 leads que no son clientes, 7 tienen ficha de inversionista; las 7 son solo de
-- su lead y sin inversiones (2 nacieron con el lead por su documento; 5 al empezar a registrarle una inversión que no se
-- completó). 3 solicitudes de inversión por lead de origen: 2 canceladas, 1 preparada (sin revisiones ni fuentes). 1
-- solicitud de tasa (rechazada, sin ledger; su lead tiene más de 30 días).
--
-- QUÉ CAMBIA (solo la puerta y UN candado; el resto de 20261015044917 queda igual):
--   1. crm.eliminar_lead_error_carga: el lead ya no se rechaza por tener inversionista_id / inversionista_leads. Sus
--      fichas se borran con él (copia completa) si cada una es SOLO de este lead y no tiene dinero ni historia propia:
--      sin perfil de cliente, sin otro lead, sin inversiones, titulares, cierres, reservas, acreditaciones, postventa,
--      fusiones, cotitulares, operaciones, tareas, búsquedas ni mapa de backfill, y sin gestiones atadas a tareas.
--      Se borran con la ficha: su enlace al lead, identificadores, responsables, gestiones sin tarea, lecturas de
--      cartera, datos de contacto y solicitudes de inversión CANCELADAS sin revisiones, correcciones ni fuentes.
--      Solicitud de inversión no cancelada (o con inversión) → «cancélala primero». Solicitud de tasa usada (consumida,
--      con contrato o con movimiento de rentabilidad) → rechazo; sin usar → se borra con sus envíos push.
--      Todo lo demás igual: roles, motivo, 30 días, mes sellado, clientes, copia, llave de los candados, cuadre.
--   2. private.trg_solicitudes_tasa_solo_por_puerta: la misma excepción de 5 líneas que los otros 8 candados.
--      El candado de revisiones/correcciones (private.f4_fuente_inmutable) NO se toca: si existen, se rechaza.
--   3. Fail-closed de llaves foráneas ampliado a las 10 tablas nuevas que se borran (67 firmas, de producción).
--
-- CAPAS: igual que 20261015044917. NO toca objetos de public. Aplicar en UN mensaje.
-- REVERSA: supabase/scripts/eliminar-lead-error-carga/reversa-r2.sql (vuelve la puerta y el candado de tasa a su
-- huella de hoy; se niega si cambiaron después).

begin;
set local lock_timeout = '5s';
select pg_advisory_lock(hashtext('crm_migracion_funciones'));
commit;

begin;
set transaction isolation level repeatable read;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

-- ── 0 · Preflight ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $preflight$
begin
  if not exists (select 1 from pg_catalog.pg_locks l
                 where l.locktype = 'advisory' and l.pid = pg_catalog.pg_backend_pid() and l.granted
                   and l.mode = 'ExclusiveLock' and l.objsubid = 1
                   and ((l.classid::bigint << 32) | l.objid::bigint) = pg_catalog.hashtext('crm_migracion_funciones')::bigint) then
    raise exception 'PREFLIGHT eliminar_lead r2: esta sesión no tiene el candado de migraciones';
  end if;
  -- Lo que se reemplaza, tal como quedó en producción el 15/10 (20261015044917).
  if (md5(pg_catalog.pg_get_functiondef('crm.eliminar_lead_error_carga(uuid,text)'::regprocedure)) = '016efb19dd29937619598dbe24137dd2'
      and md5(pg_catalog.pg_get_functiondef('private.trg_solicitudes_tasa_solo_por_puerta()'::regprocedure)) = '46d48b78c9e8e6553416654664bad1d8') is not true then
    raise exception 'PREFLIGHT eliminar_lead r2: cambió la puerta o el candado de tasa que se reemplazan';
  end if;
  -- Lo que se usa sin tocar: la llave, los 8 candados de r1 y los ayudantes.
  if (
      md5(pg_catalog.pg_get_functiondef('private.borrado_lead_error_autoriza(text,jsonb)'::regprocedure)) = 'ca2d68e24202413ff4b7b3c962c07ed5'
      and md5(pg_catalog.pg_get_functiondef('private.eliminar_inversion_roles(uuid)'::regprocedure)) = 'e9a2341105e4028565f81164d5e02c4c'
      and md5(pg_catalog.pg_get_functiondef('private.motivo_normalizado(text)'::regprocedure)) = '08602d4022e0731952cbf61c28efe9d7'
      and md5(pg_catalog.pg_get_functiondef('private.potencial_evento_inmutable()'::regprocedure)) = '3dede26ca03faf565fdec3406562944a'
      and md5(pg_catalog.pg_get_functiondef('private.trg_actividades_no_contactar_solo_puerta()'::regprocedure)) = '8f60ebed7499eaa101e9faa2d424793c'
      and md5(pg_catalog.pg_get_functiondef('private.trg_lead_asignacion_sla_hitos_guard()'::regprocedure)) = 'f0b5874060957068ab4267593fdf989b'
      and md5(pg_catalog.pg_get_functiondef('private.trg_lead_asignaciones_inmutables()'::regprocedure)) = '53c8b34bf3a13465123f74b0a22d7c47'
      and md5(pg_catalog.pg_get_functiondef('private.trg_lead_sla_ciclos_guard()'::regprocedure)) = '9b8765c4b8debf58b28b5edec8aec31d'
      and md5(pg_catalog.pg_get_functiondef('private.trg_lead_sla_etapas_guard()'::regprocedure)) = '73ea8058cb3befe0fa97fa84bba03450'
      and md5(pg_catalog.pg_get_functiondef('private.trg_sla_nucleo_entrada_guard()'::regprocedure)) = '4e3e825c92d95049ef6c7076ecaa5066'
      and md5(pg_catalog.pg_get_functiondef('private.trg_sla_recibo_guard()'::regprocedure)) = 'f111fdd9d8eb904fde961c6dcc7a9a9a'
  ) is not true then
    raise exception 'PREFLIGHT eliminar_lead r2: cambió una función que la puerta usa';
  end if;
  if (select pg_catalog.array_agg(pg_catalog.pg_get_triggerdef(t.oid) || ' [' || t.tgenabled::text || ']'
                                  order by pg_catalog.pg_get_triggerdef(t.oid) || ' [' || t.tgenabled::text || ']')
      from pg_catalog.pg_trigger t
      where not t.tgisinternal and t.tgfoid in ('private.potencial_evento_inmutable()'::regprocedure, 'private.trg_actividades_no_contactar_solo_puerta()'::regprocedure, 'private.trg_lead_asignacion_sla_hitos_guard()'::regprocedure, 'private.trg_lead_asignaciones_inmutables()'::regprocedure, 'private.trg_lead_sla_ciclos_guard()'::regprocedure, 'private.trg_lead_sla_etapas_guard()'::regprocedure, 'private.trg_sla_nucleo_entrada_guard()'::regprocedure, 'private.trg_sla_recibo_guard()'::regprocedure, 'private.trg_solicitudes_tasa_solo_por_puerta()'::regprocedure)) is distinct from array[
        'CREATE TRIGGER lead_potencial_evento_inmutable BEFORE DELETE OR UPDATE ON crm.lead_potencial_eventos FOR EACH ROW EXECUTE FUNCTION private.potencial_evento_inmutable() [O]',
        'CREATE TRIGGER lead_potencial_evento_no_truncate BEFORE TRUNCATE ON crm.lead_potencial_eventos FOR EACH STATEMENT EXECUTE FUNCTION private.potencial_evento_inmutable() [O]',
        'CREATE TRIGGER sla_recibo_guard BEFORE INSERT OR DELETE OR UPDATE ON crm.sla_operacion_recibos FOR EACH ROW EXECUTE FUNCTION private.trg_sla_recibo_guard() [O]',
        'CREATE TRIGGER sla_recibo_truncate_guard BEFORE TRUNCATE ON crm.sla_operacion_recibos FOR EACH STATEMENT EXECUTE FUNCTION private.trg_sla_recibo_guard() [O]',
        'CREATE TRIGGER trg_00_actividades_no_contactar_solo_puerta BEFORE INSERT OR DELETE OR UPDATE ON crm.actividades FOR EACH ROW EXECUTE FUNCTION private.trg_actividades_no_contactar_solo_puerta() [O]',
        'CREATE TRIGGER trg_lead_asignacion_sla_hitos_guard BEFORE INSERT OR DELETE OR UPDATE ON crm.lead_asignacion_sla_hitos FOR EACH ROW EXECUTE FUNCTION private.trg_lead_asignacion_sla_hitos_guard() [O]',
        'CREATE TRIGGER trg_lead_asignaciones_00_inmutables BEFORE INSERT OR DELETE OR UPDATE ON crm.lead_asignaciones FOR EACH ROW EXECUTE FUNCTION private.trg_lead_asignaciones_inmutables() [O]',
        'CREATE TRIGGER trg_lead_sla_ciclos_guard BEFORE INSERT OR DELETE OR UPDATE ON crm.lead_sla_ciclos FOR EACH ROW EXECUTE FUNCTION private.trg_lead_sla_ciclos_guard() [O]',
        'CREATE TRIGGER trg_lead_sla_etapas_guard BEFORE INSERT OR DELETE OR UPDATE ON crm.lead_sla_etapas FOR EACH ROW EXECUTE FUNCTION private.trg_lead_sla_etapas_guard() [O]',
        'CREATE TRIGGER trg_sla_nucleo_guard BEFORE INSERT OR DELETE OR UPDATE ON crm.lead_sla_etapa_ajustes FOR EACH ROW EXECUTE FUNCTION private.trg_sla_nucleo_entrada_guard() [O]',
        'CREATE TRIGGER trg_sla_nucleo_guard BEFORE INSERT OR DELETE OR UPDATE ON crm.sla_operacion_control FOR EACH ROW EXECUTE FUNCTION private.trg_sla_nucleo_entrada_guard() [O]',
        'CREATE TRIGGER trg_sla_nucleo_guard BEFORE INSERT OR DELETE OR UPDATE ON crm.sla_politica_etapas_operacion FOR EACH ROW EXECUTE FUNCTION private.trg_sla_nucleo_entrada_guard() [O]',
        'CREATE TRIGGER trg_sla_nucleo_guard BEFORE INSERT OR DELETE OR UPDATE ON crm.tarea_sla_contexto FOR EACH ROW EXECUTE FUNCTION private.trg_sla_nucleo_entrada_guard() [O]',
        'CREATE TRIGGER trg_sla_nucleo_no_truncate BEFORE TRUNCATE ON crm.lead_sla_etapa_ajustes FOR EACH STATEMENT EXECUTE FUNCTION private.trg_sla_nucleo_entrada_guard() [O]',
        'CREATE TRIGGER trg_sla_nucleo_no_truncate BEFORE TRUNCATE ON crm.sla_operacion_control FOR EACH STATEMENT EXECUTE FUNCTION private.trg_sla_nucleo_entrada_guard() [O]',
        'CREATE TRIGGER trg_sla_nucleo_no_truncate BEFORE TRUNCATE ON crm.sla_politica_etapas_operacion FOR EACH STATEMENT EXECUTE FUNCTION private.trg_sla_nucleo_entrada_guard() [O]',
        'CREATE TRIGGER trg_sla_nucleo_no_truncate BEFORE TRUNCATE ON crm.tarea_sla_contexto FOR EACH STATEMENT EXECUTE FUNCTION private.trg_sla_nucleo_entrada_guard() [O]',
        'CREATE TRIGGER trg_solicitudes_tasa_00_solo_por_puerta BEFORE DELETE OR UPDATE ON crm.solicitudes_tasa FOR EACH ROW EXECUTE FUNCTION private.trg_solicitudes_tasa_solo_por_puerta() [O]'
      ]::text[] then
    raise exception 'PREFLIGHT eliminar_lead r2: los triggers de los candados no están en su modo normal';
  end if;
end
$preflight$;

-- ── 1 · Candado de solicitudes de tasa: idéntico a producción salvo las 5 líneas del DELETE ─────────────────────────
CREATE OR REPLACE FUNCTION private.trg_solicitudes_tasa_solo_por_puerta()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'DELETE' then
    -- Única excepción: la vía oficial crm.eliminar_lead_error_carga, y solo para una fila ya copiada en
    -- crm.leads_eliminados en ESTA transacción (ver private.borrado_lead_error_autoriza).
    if private.borrado_lead_error_autoriza(tg_table_name, pg_catalog.to_jsonb(old)) then return old; end if;
  end if;
  if tg_op = 'DELETE' then
    raise exception 'Una solicitud de tasa no se borra: queda como historia' using errcode = 'P0409';
  end if;
  if coalesce(current_setting('crm.solicitud_tasa_por_puerta', true), 'off') <> 'on' then
    raise exception 'Una solicitud de tasa solo cambia por sus puertas (crm.*_tasa_fn)' using errcode = 'P0409';
  end if;
  new.actualizado_en := statement_timestamp();
  return new;
end;
$function$;

-- ── 2 · Puerta ─────────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function crm.eliminar_lead_error_carga(p_lead_id uuid, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
declare
  c_dias_max constant integer := 30;
  v_uid uuid := (select auth.uid());
  v_roles jsonb;
  v_rol text;
  v_motivo text := private.motivo_normalizado(p_motivo);
  v_lead crm.leads%rowtype;
  v_inv uuid[];
  v_no text[] := '{}';
  v_meses text;
  v_nuevas text;
  v_copia jsonb;
  v_filas jsonb;
  v_id uuid;
  v_n bigint;
  v_cuadre jsonb := '{}'::jsonb;
  v_previa text := pg_catalog.current_setting('crm.borrado_lead_error', true);
begin
  if v_uid is null then
    raise exception 'Inicia sesión para eliminar un lead' using errcode = '42501';
  end if;
  v_roles := private.eliminar_inversion_roles(v_uid);
  v_rol := case when coalesce((v_roles ->> 'gerencia')::boolean, false) then 'gerencia' else v_roles ->> 'portal' end;
  if v_rol is null then
    raise exception 'Solo gerencia o un admin del portal pueden eliminar un lead' using errcode = '42501';
  end if;
  if p_lead_id is null then
    raise exception 'Falta el lead a eliminar' using errcode = '22023';
  end if;
  if pg_catalog.char_length(v_motivo) < 10 then
    raise exception 'Escribe el motivo de la eliminación (al menos 10 caracteres)' using errcode = '22023';
  end if;
  if pg_catalog.char_length(v_motivo) > 500 then
    raise exception 'El motivo admite como máximo 500 caracteres' using errcode = '22023';
  end if;
  -- Cada sentencia necesita su propia instantánea: la copia tiene que ver lo que existe DESPUÉS de los bloqueos, y la
  -- comprobación del mes cerrado tiene que ver un cierre recién confirmado.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'Esta operación necesita aislamiento READ COMMITTED' using errcode = '55000';
  end if;

  -- Fail-closed: toda llave foránea hacia lo que se borra tiene que estar en esta lista, con sus columnas de origen y
  -- de destino y su acción ON DELETE (catálogo de producción, 15/10/2026).
  select pg_catalog.string_agg(k.clave, ', ' order by k.clave) into v_nuevas
  from (
    select c.conrelid::regclass::text || ':'
             || (select pg_catalog.string_agg(a.attname::text, ',' order by u.ord)
                 from pg_catalog.unnest(c.conkey) with ordinality u(attnum, ord)
                 join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = u.attnum)
             || ':' || c.confrelid::regclass::text || ':'
             || (select pg_catalog.string_agg(a.attname::text, ',' order by u.ord)
                 from pg_catalog.unnest(c.confkey) with ordinality u(attnum, ord)
                 join pg_catalog.pg_attribute a on a.attrelid = c.confrelid and a.attnum = u.attnum)
             || ':' || c.confdeltype::text as clave
    from pg_catalog.pg_constraint c
    where c.contype = 'f'
      and c.confrelid in ('crm.leads'::regclass, 'crm.tareas'::regclass, 'crm.actividades'::regclass,
                          'crm.lead_asignaciones'::regclass, 'crm.lead_sla_ciclos'::regclass, 'crm.lead_sla_etapas'::regclass,
                          'crm.tarea_sla_contexto'::regclass, 'crm.lead_asignacion_sla_hitos'::regclass,
                          'crm.lead_sla_etapa_ajustes'::regclass, 'crm.actividades_cliente'::regclass,
                          'crm.sla_operacion_recibos'::regclass, 'crm.lead_potencial'::regclass,
                          'crm.lead_potencial_eventos'::regclass, 'crm.base_carga_leads'::regclass,
                          'crm.llamadas_celular_eventos'::regclass, 'crm.llamadas_celular_enlaces'::regclass,
                          'private.llamadas_celular_intenciones'::regclass,
                          'crm.inversionistas'::regclass, 'crm.inversionista_leads'::regclass,
                          'crm.inversionista_identificadores'::regclass, 'crm.inversionista_responsables'::regclass,
                          'crm.inversionista_gestiones'::regclass, 'crm.cartera_lecturas'::regclass,
                          'crm.inversionista_datos_contacto'::regclass, 'crm.inversion_solicitudes'::regclass,
                          'crm.solicitudes_tasa'::regclass, 'crm.envios_push_tasa'::regclass)
  ) k
  where k.clave <> all (array[
    'crm.actividades:lead_id:crm.leads:id:c',
    'crm.actividades_cliente:tarea_id:crm.tareas:id:n',
    'crm.ajustes_mes_cerrado:lead_id:crm.leads:id:r',
    'crm.backfill_multiempresa_mapa:inversionista_id:crm.inversionistas:id:a',
    'crm.base_carga_leads:lead_id:crm.leads:id:a',
    'crm.busquedas_cliente_existente:inversionista_id:crm.inversionistas:id:a',
    'crm.busquedas_cliente_existente:lead_id:crm.leads:id:a',
    'crm.cartera_lecturas:inversionista_id:crm.inversionistas:id:a',
    'crm.cierres_avance_anulados:lead_id:crm.leads:id:r',
    'crm.cierres_externos:inversionista_id:crm.inversionistas:id:a',
    'crm.cierres_externos:lead_id:crm.leads:id:r',
    'crm.conversion_acreditaciones:episodio_id:crm.lead_asignaciones:id:a',
    'crm.conversion_acreditaciones:inversionista_id:crm.inversionistas:id:a',
    'crm.conversion_acreditaciones:lead_id:crm.leads:id:a',
    'crm.conversion_reservas:inversionista_id:crm.inversionistas:id:a',
    'crm.conversion_reservas:lead_id:crm.leads:id:r',
    'crm.envios_push_tasa:solicitud_id:crm.solicitudes_tasa:id:a',
    'crm.inversion_cotitular_origenes:identificador_origen_id:crm.inversionista_identificadores:id:a',
    'crm.inversion_cotitular_origenes:persona_origen_id:crm.inversionistas:id:a',
    'crm.inversion_solicitud_correcciones:solicitud_id:crm.inversion_solicitudes:id:a',
    'crm.inversion_solicitud_origenes:solicitud_id:crm.inversion_solicitudes:id:a',
    'crm.inversion_solicitud_revisiones:solicitud_id:crm.inversion_solicitudes:id:a',
    'crm.inversion_solicitudes:inversionista_id:crm.inversionistas:id:a',
    'crm.inversion_solicitudes:lead_origen_id:crm.leads:id:a',
    'crm.inversion_titulares:inversionista_id:crm.inversionistas:id:a',
    'crm.inversiones:inversionista_id:crm.inversionistas:id:a',
    'crm.inversionista_datos_contacto:inversionista_id:crm.inversionistas:id:a',
    'crm.inversionista_fusiones:canonico_id:crm.inversionistas:id:a',
    'crm.inversionista_fusiones:fusionado_id:crm.inversionistas:id:a',
    'crm.inversionista_gestiones:inversionista_id:crm.inversionistas:id:a',
    'crm.inversionista_gestiones:tarea_id:crm.tareas:id:a',
    'crm.inversionista_identificadores:inversionista_id:crm.inversionistas:id:a',
    'crm.inversionista_leads:inversionista_id:crm.inversionistas:id:a',
    'crm.inversionista_leads:lead_id:crm.leads:id:a',
    'crm.inversionista_operaciones:identificador_anterior_id:crm.inversionista_identificadores:id:a',
    'crm.inversionista_operaciones:identificador_nuevo_id:crm.inversionista_identificadores:id:a',
    'crm.inversionista_operaciones:inversionista_id:crm.inversionistas:id:a',
    'crm.inversionista_operaciones:lead_id:crm.leads:id:a',
    'crm.inversionista_responsables:inversionista_id:crm.inversionistas:id:a',
    'crm.inversionistas:inversionista_canonico_id:crm.inversionistas:id:a',
    'crm.lead_asignacion_sla_hitos:lead_asignacion_id:crm.lead_asignaciones:id:r',
    'crm.lead_asignaciones:lead_id:crm.leads:id:r',
    'crm.lead_potencial:lead_id:crm.leads:id:a',
    'crm.lead_potencial_eventos:lead_id:crm.leads:id:a',
    'crm.lead_sla_ciclos:lead_id:crm.leads:id:r',
    'crm.lead_sla_etapa_ajustes:etapa_sla_id:crm.lead_sla_etapas:id:r',
    'crm.lead_sla_etapa_ajustes:origen_actividad_id:crm.actividades:id:r',
    'crm.lead_sla_etapas:lead_id,ciclo_n:crm.lead_sla_ciclos:lead_id,ciclo_n:r',
    'crm.lead_sla_etapas:lead_id:crm.leads:id:r',
    'crm.leads:inversionista_id:crm.inversionistas:id:a',
    'crm.ledger_rentabilidad:solicitud_id:crm.solicitudes_tasa:id:r',
    'crm.llamadas_celular_enlaces:actividad_id:crm.actividades:id:n',
    'crm.llamadas_celular_enlaces:evento_id:crm.llamadas_celular_eventos:id:c',
    'crm.llamadas_celular_enlaces:lead_id:crm.leads:id:c',
    'crm.llamadas_celular_eventos:lead_id:crm.leads:id:c',
    'crm.postventa_operaciones:inversionista_id:crm.inversionistas:id:a',
    'crm.postventa_retiros:inversionista_id:crm.inversionistas:id:a',
    'crm.sla_operacion_recibos:lead_id:crm.leads:id:a',
    'crm.solicitudes_tasa:lead_id:crm.leads:id:r',
    'crm.tarea_sla_contexto:lead_id,ciclo_n:crm.lead_sla_ciclos:lead_id,ciclo_n:r',
    'crm.tarea_sla_contexto:tarea_id:crm.tareas:id:r',
    'crm.tareas:inversionista_id:crm.inversionistas:id:a',
    'crm.tareas:lead_id:crm.leads:id:c',
    'crm.tareas:reagendada_de:crm.tareas:id:n',
    'crm.tareas:resultado_actividad_id:crm.actividades:id:n',
    'private.llamadas_celular_intenciones:actividad_id:crm.actividades:id:c',
    'private.llamadas_celular_intenciones:lead_id:crm.leads:id:c'
  ]);
  if v_nuevas is not null then
    raise exception 'Hay tablas nuevas enlazadas al lead que esta eliminación no conoce (%); hay que revisarla antes', v_nuevas
      using errcode = '55000';
  end if;

  -- Mismo candado que crm.cerrar_periodo, tomado ANTES de las filas (mismo orden que el cierre: sin abrazo mortal).
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);

  -- El lead primero (bloquea también toda fila nueva que quiera colgarse de él: su FK necesita KEY SHARE).
  select * into v_lead from crm.leads l where l.id = p_lead_id for update;
  if not found then
    raise exception 'El lead no existe o ya fue eliminado' using errcode = 'P0002';
  end if;
  -- Sus fichas de inversionista (por la columna del lead y por el enlace).
  select coalesce(pg_catalog.array_agg(distinct z.i), '{}') into v_inv
  from (select v_lead.inversionista_id as i where v_lead.inversionista_id is not null
        union select il.inversionista_id from crm.inversionista_leads il where il.lead_id = p_lead_id) z;
  -- Los padres de cada nivel, en sentencias ANTERIORES a la copia.
  perform 1 from crm.lead_asignaciones x where x.lead_id = p_lead_id order by x.id for update;
  perform 1 from crm.lead_sla_ciclos x where x.lead_id = p_lead_id order by x.id for update;
  perform 1 from crm.lead_sla_etapas x where x.lead_id = p_lead_id order by x.id for update;
  perform 1 from crm.tareas x where x.lead_id = p_lead_id order by x.id for update;
  perform 1 from crm.actividades x where x.lead_id = p_lead_id order by x.id for update;
  perform 1 from crm.llamadas_celular_eventos x where x.lead_id = p_lead_id order by x.id for update;
  perform 1 from crm.inversionistas x where x.id = any (v_inv) order by x.id for update;
  perform 1 from crm.inversionista_identificadores x where x.inversionista_id = any (v_inv) order by x.id for update;
  perform 1 from crm.inversion_solicitudes x
  where x.lead_origen_id = p_lead_id or x.inversionista_id = any (v_inv) order by x.id for update;
  perform 1 from crm.solicitudes_tasa x where x.lead_id = p_lead_id order by x.id for update;

  -- Un CLIENTE nunca se borra.
  if v_lead.contrato_id is not null then v_no := v_no || 'tiene un contrato enlazado'::text; end if;
  if v_lead.perfil_id is not null then v_no := v_no || 'está enlazado a un perfil de cliente'::text; end if;
  if v_lead.convertido_en is not null
     or exists (select 1 from crm.lead_asignaciones a where a.lead_id = p_lead_id and a.resultado = 'convertido') then
    v_no := v_no || 'tiene una conversión registrada'::text;
  end if;
  if exists (select 1 from crm.conversion_acreditaciones x where x.lead_id = p_lead_id) then
    v_no := v_no || 'tiene una conversión acreditada'::text; end if;
  if exists (select 1 from crm.conversion_reservas x where x.lead_id = p_lead_id) then
    v_no := v_no || 'tiene una reserva de conversión'::text; end if;
  if exists (select 1 from crm.cierres_externos x where x.lead_id = p_lead_id) then
    v_no := v_no || 'tiene un cierre en cooperativa'::text; end if;
  if exists (select 1 from crm.cierres_avance_anulados x where x.lead_id = p_lead_id) then
    v_no := v_no || 'tiene un cierre anulado'::text; end if;
  if exists (select 1 from crm.ajustes_mes_cerrado x where x.lead_id = p_lead_id) then
    v_no := v_no || 'tiene un ajuste de mes cerrado'::text; end if;
  -- Historia del lead que no se borra con él.
  if exists (select 1 from crm.inversionista_operaciones x where x.lead_id = p_lead_id) then
    v_no := v_no || 'tiene operaciones de inversionista registradas'::text; end if;
  if exists (select 1 from crm.busquedas_cliente_existente x where x.lead_id = p_lead_id) then
    v_no := v_no || 'tiene búsquedas de cliente existente registradas'::text; end if;
  if exists (select 1 from crm.inversionista_gestiones g join crm.tareas t on t.id = g.tarea_id where t.lead_id = p_lead_id) then
    v_no := v_no || 'tiene gestiones de inversionista'::text; end if;
  -- Solicitudes de inversión (por lead de origen o de sus fichas): solo canceladas, sin inversión ni historia.
  if exists (select 1 from crm.inversion_solicitudes s
             where (s.lead_origen_id = p_lead_id or s.inversionista_id = any (v_inv))
               and (s.estado is distinct from 'cancelada' or s.inversion_id is not null)) then
    v_no := v_no || 'tiene una solicitud de inversión en curso (cancélala primero)'::text;
  end if;
  if exists (select 1 from crm.inversion_solicitudes s
             where (s.lead_origen_id = p_lead_id or s.inversionista_id = any (v_inv))
               and (exists (select 1 from crm.inversion_solicitud_correcciones c where c.solicitud_id = s.id)
                    or exists (select 1 from crm.inversion_solicitud_revisiones c where c.solicitud_id = s.id)
                    or exists (select 1 from crm.inversion_solicitud_origenes c where c.solicitud_id = s.id))) then
    v_no := v_no || 'tiene una solicitud de inversión con revisiones o fuentes registradas'::text;
  end if;
  -- Solicitudes de tasa: solo si nunca se usaron.
  if exists (select 1 from crm.solicitudes_tasa t
             where t.lead_id = p_lead_id
               and (t.estado = 'consumida' or t.contrato_id is not null
                    or exists (select 1 from crm.ledger_rentabilidad r where r.solicitud_id = t.id))) then
    v_no := v_no || 'tiene una solicitud de tasa ya usada'::text;
  end if;
  -- Fichas de inversionista: solo si cada una es de este lead y no tiene dinero ni historia propia.
  if pg_catalog.cardinality(v_inv) > 0 then
    if exists (select 1 from crm.inversionistas i where i.id = any (v_inv) and i.perfil_id is not null) then
      v_no := v_no || 'su ficha de inversionista tiene acceso de cliente'::text; end if;
    if exists (select 1 from crm.leads o where o.inversionista_id = any (v_inv) and o.id <> p_lead_id)
       or exists (select 1 from crm.inversionista_leads o where o.inversionista_id = any (v_inv) and o.lead_id <> p_lead_id) then
      v_no := v_no || 'su ficha de inversionista también pertenece a otro lead'::text; end if;
    if exists (select 1 from crm.inversiones x where x.inversionista_id = any (v_inv))
       or exists (select 1 from crm.inversion_titulares x where x.inversionista_id = any (v_inv))
       or exists (select 1 from crm.cierres_externos x where x.inversionista_id = any (v_inv))
       or exists (select 1 from crm.conversion_reservas x where x.inversionista_id = any (v_inv))
       or exists (select 1 from crm.conversion_acreditaciones x where x.inversionista_id = any (v_inv))
       or exists (select 1 from crm.postventa_operaciones x where x.inversionista_id = any (v_inv))
       or exists (select 1 from crm.postventa_retiros x where x.inversionista_id = any (v_inv)) then
      v_no := v_no || 'su ficha de inversionista tiene inversiones o cierres'::text; end if;
    if exists (select 1 from crm.inversionistas i
               where i.id = any (v_inv) and (i.inversionista_canonico_id is not null or i.fusionado_en is not null))
       or exists (select 1 from crm.inversionistas o where o.inversionista_canonico_id = any (v_inv))
       or exists (select 1 from crm.inversionista_fusiones x where x.canonico_id = any (v_inv) or x.fusionado_id = any (v_inv)) then
      v_no := v_no || 'su ficha de inversionista está fusionada con otra'::text; end if;
    if exists (select 1 from crm.inversion_cotitular_origenes x
               where x.persona_origen_id = any (v_inv)
                  or x.identificador_origen_id in (select d.id from crm.inversionista_identificadores d where d.inversionista_id = any (v_inv)))
       or exists (select 1 from crm.inversionista_operaciones x
                  where x.inversionista_id = any (v_inv)
                     or x.identificador_anterior_id in (select d.id from crm.inversionista_identificadores d where d.inversionista_id = any (v_inv))
                     or x.identificador_nuevo_id in (select d.id from crm.inversionista_identificadores d where d.inversionista_id = any (v_inv)))
       or exists (select 1 from crm.tareas x where x.inversionista_id = any (v_inv))
       or exists (select 1 from crm.busquedas_cliente_existente x where x.inversionista_id = any (v_inv))
       or exists (select 1 from crm.backfill_multiempresa_mapa x where x.inversionista_id = any (v_inv))
       or exists (select 1 from crm.inversionista_gestiones x where x.inversionista_id = any (v_inv) and x.tarea_id is not null) then
      v_no := v_no || 'su ficha de inversionista tiene historia propia (cotitulares, operaciones, tareas o búsquedas)'::text; end if;
  end if;
  -- Filas de OTROS leads que apuntan a las suyas (su ON DELETE SET NULL las reescribiría sin copia).
  if exists (select 1 from crm.tareas o
             where o.lead_id is distinct from p_lead_id
               and (o.reagendada_de in (select t.id from crm.tareas t where t.lead_id = p_lead_id)
                    or o.resultado_actividad_id in (select a.id from crm.actividades a where a.lead_id = p_lead_id)))
     or exists (select 1 from crm.llamadas_celular_enlaces o
                where o.lead_id is distinct from p_lead_id
                  and o.actividad_id in (select a.id from crm.actividades a where a.lead_id = p_lead_id)) then
    v_no := v_no || 'otro lead tiene tareas o llamadas enlazadas a las suyas'::text;
  end if;
  if v_lead.creado_en < pg_catalog.clock_timestamp() - pg_catalog.make_interval(days => c_dias_max) then
    v_no := v_no || pg_catalog.format('se creó hace más de %s días (%s)', c_dias_max,
                      pg_catalog.to_char(v_lead.creado_en at time zone 'America/Lima', 'DD/MM/YYYY'));
  end if;
  -- Mes cerrado (el candado de crm.cerrar_periodo ya está tomado arriba).
  select pg_catalog.string_agg(pg_catalog.to_char(pc.periodo, 'MM/YYYY'), ', ' order by pc.periodo) into v_meses
  from crm.periodos_cerrados pc
  where pc.periodo >= pg_catalog.date_trunc('month', v_lead.creado_en at time zone 'America/Lima')::date;
  if v_meses is not null then
    v_no := v_no || pg_catalog.format('aparece en un mes cerrado (%s)', v_meses);
  end if;
  if pg_catalog.cardinality(v_no) > 0 then
    raise exception 'No se puede eliminar este lead: %.', pg_catalog.array_to_string(v_no, '; ') using errcode = 'P0409';
  end if;

  -- Copia completa (cada fila bloqueada FOR UPDATE: lo copiado es exactamente lo que se borra).
  v_copia := pg_catalog.jsonb_build_object(
    'version', 2,
    'lead', pg_catalog.to_jsonb(v_lead),
    'tareas', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.tareas x where x.lead_id = p_lead_id for update) r), '[]'::jsonb),
    'actividades_cliente', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.actividades_cliente x
            where x.tarea_id in (select t.id from crm.tareas t where t.lead_id = p_lead_id) for update) r), '[]'::jsonb),
    'tarea_sla_contexto', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.tarea_id)
      from (select * from crm.tarea_sla_contexto x where x.lead_id = p_lead_id for update) r), '[]'::jsonb),
    'actividades', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.actividades x where x.lead_id = p_lead_id for update) r), '[]'::jsonb),
    'lead_asignaciones', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.lead_asignaciones x where x.lead_id = p_lead_id for update) r), '[]'::jsonb),
    'lead_asignacion_sla_hitos', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.lead_asignacion_id)
      from (select * from crm.lead_asignacion_sla_hitos x
            where x.lead_asignacion_id in (select a.id from crm.lead_asignaciones a where a.lead_id = p_lead_id)
            for update) r), '[]'::jsonb),
    'lead_sla_ciclos', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.ciclo_n)
      from (select * from crm.lead_sla_ciclos x where x.lead_id = p_lead_id for update) r), '[]'::jsonb),
    'lead_sla_etapas', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.lead_sla_etapas x where x.lead_id = p_lead_id for update) r), '[]'::jsonb),
    'lead_sla_etapa_ajustes', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.lead_sla_etapa_ajustes x
            where x.etapa_sla_id in (select e.id from crm.lead_sla_etapas e where e.lead_id = p_lead_id) for update) r),
      '[]'::jsonb),
    'sla_operacion_recibos', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r))
      from (select * from crm.sla_operacion_recibos x where x.lead_id = p_lead_id for update) r), '[]'::jsonb),
    'lead_potencial', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r))
      from (select * from crm.lead_potencial x where x.lead_id = p_lead_id for update) r), '[]'::jsonb),
    'lead_potencial_eventos', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r))
      from (select * from crm.lead_potencial_eventos x where x.lead_id = p_lead_id for update) r), '[]'::jsonb),
    'base_carga_leads', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.base_carga_leads x where x.lead_id = p_lead_id for update) r), '[]'::jsonb),
    'llamadas_celular_eventos', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.llamadas_celular_eventos x where x.lead_id = p_lead_id for update) r), '[]'::jsonb),
    'llamadas_celular_enlaces', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.llamadas_celular_enlaces x
            where x.lead_id = p_lead_id
               or x.evento_id in (select e.id from crm.llamadas_celular_eventos e where e.lead_id = p_lead_id)
            for update) r), '[]'::jsonb),
    'llamadas_celular_intenciones', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from private.llamadas_celular_intenciones x
            where x.lead_id = p_lead_id
               or x.actividad_id in (select a.id from crm.actividades a where a.lead_id = p_lead_id)
            for update) r), '[]'::jsonb))
  || pg_catalog.jsonb_build_object(
    'solicitudes_tasa', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.solicitudes_tasa x where x.lead_id = p_lead_id for update) r), '[]'::jsonb),
    'envios_push_tasa', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.envios_push_tasa x
            where x.solicitud_id in (select t.id from crm.solicitudes_tasa t where t.lead_id = p_lead_id) for update) r),
      '[]'::jsonb),
    'inversion_solicitudes', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.inversion_solicitudes x
            where x.lead_origen_id = p_lead_id or x.inversionista_id = any (v_inv) for update) r), '[]'::jsonb),
    'inversionista_leads', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.inversionista_leads x
            where x.lead_id = p_lead_id or x.inversionista_id = any (v_inv) for update) r), '[]'::jsonb),
    'inversionistas', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.inversionistas x where x.id = any (v_inv) for update) r), '[]'::jsonb),
    'inversionista_identificadores', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.inversionista_identificadores x where x.inversionista_id = any (v_inv) for update) r), '[]'::jsonb),
    'inversionista_responsables', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.inversionista_responsables x where x.inversionista_id = any (v_inv) for update) r), '[]'::jsonb),
    'inversionista_gestiones', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.inversionista_gestiones x where x.inversionista_id = any (v_inv) for update) r), '[]'::jsonb),
    'cartera_lecturas', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.id)
      from (select * from crm.cartera_lecturas x where x.inversionista_id = any (v_inv) for update) r), '[]'::jsonb),
    'inversionista_datos_contacto', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.inversionista_id)
      from (select * from crm.inversionista_datos_contacto x where x.inversionista_id = any (v_inv) for update) r), '[]'::jsonb));
  select pg_catalog.jsonb_object_agg(e.key, pg_catalog.jsonb_array_length(e.value)) into v_filas
  from pg_catalog.jsonb_each(v_copia) e where pg_catalog.jsonb_typeof(e.value) = 'array';

  -- Un CHECK fallido devolvería «Failing row contains (…)» con la copia (datos personales): se responde sin detalle.
  begin
    insert into crm.leads_eliminados (lead_id, motivo, eliminado_por, rol_actor, copia, filas)
    values (p_lead_id, v_motivo, v_uid, v_rol, v_copia, v_filas)
    returning id into v_id;
  exception when check_violation or not_null_violation or unique_violation then
    raise exception 'No se pudo guardar la copia del lead; no se eliminó nada' using errcode = '55000';
  end;

  -- Permiso de borrado de ESTE lead, solo en esta transacción; los candados exigen además la fila en la copia.
  perform pg_catalog.set_config('crm.borrado_lead_error', p_lead_id::text, true);

  -- Orden por llaves foráneas (RESTRICT/NO ACTION primero). Cada DELETE tiene que borrar EXACTAMENTE lo copiado.
  delete from crm.tarea_sla_contexto x where x.lead_id = p_lead_id;
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('tarea_sla_contexto', v_n);
  delete from crm.lead_asignacion_sla_hitos x
  where x.lead_asignacion_id in (select a.id from crm.lead_asignaciones a where a.lead_id = p_lead_id);
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('lead_asignacion_sla_hitos', v_n);
  delete from crm.lead_sla_etapa_ajustes x
  where x.etapa_sla_id in (select e.id from crm.lead_sla_etapas e where e.lead_id = p_lead_id);
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('lead_sla_etapa_ajustes', v_n);
  delete from crm.actividades_cliente x where x.tarea_id in (select t.id from crm.tareas t where t.lead_id = p_lead_id);
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('actividades_cliente', v_n);
  delete from crm.tareas x where x.lead_id = p_lead_id;
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('tareas', v_n);
  delete from crm.sla_operacion_recibos x where x.lead_id = p_lead_id;
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('sla_operacion_recibos', v_n);
  delete from crm.lead_potencial_eventos x where x.lead_id = p_lead_id;
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('lead_potencial_eventos', v_n);
  delete from crm.lead_potencial x where x.lead_id = p_lead_id;
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('lead_potencial', v_n);
  delete from crm.base_carga_leads x where x.lead_id = p_lead_id;
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('base_carga_leads', v_n);
  delete from crm.actividades x where x.lead_id = p_lead_id;   -- cascada: intenciones; los enlaces quedan sin actividad
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('actividades', v_n);
  delete from crm.lead_sla_etapas x where x.lead_id = p_lead_id;
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('lead_sla_etapas', v_n);
  delete from crm.lead_sla_ciclos x where x.lead_id = p_lead_id;
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('lead_sla_ciclos', v_n);
  delete from crm.lead_asignaciones x where x.lead_id = p_lead_id;
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('lead_asignaciones', v_n);
  delete from crm.envios_push_tasa x
  where x.solicitud_id in (select t.id from crm.solicitudes_tasa t where t.lead_id = p_lead_id);
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('envios_push_tasa', v_n);
  delete from crm.solicitudes_tasa x where x.lead_id = p_lead_id;
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('solicitudes_tasa', v_n);
  delete from crm.inversion_solicitudes x where x.lead_origen_id = p_lead_id or x.inversionista_id = any (v_inv);
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('inversion_solicitudes', v_n);
  delete from crm.inversionista_leads x where x.lead_id = p_lead_id or x.inversionista_id = any (v_inv);
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('inversionista_leads', v_n);
  delete from crm.leads x where x.id = p_lead_id;               -- cascada: llamadas del celular (sus candados la aceptan)
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'La eliminación no cuadró con la copia; no se aplicó nada' using errcode = '55000';
  end if;
  -- Las fichas de inversionista, ya sin lead.
  delete from crm.inversionista_identificadores x where x.inversionista_id = any (v_inv);
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('inversionista_identificadores', v_n);
  delete from crm.inversionista_responsables x where x.inversionista_id = any (v_inv);
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('inversionista_responsables', v_n);
  delete from crm.inversionista_gestiones x where x.inversionista_id = any (v_inv);
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('inversionista_gestiones', v_n);
  delete from crm.cartera_lecturas x where x.inversionista_id = any (v_inv);
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('cartera_lecturas', v_n);
  delete from crm.inversionista_datos_contacto x where x.inversionista_id = any (v_inv);
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('inversionista_datos_contacto', v_n);
  delete from crm.inversionistas x where x.id = any (v_inv);
  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('inversionistas', v_n);

  perform pg_catalog.set_config('crm.borrado_lead_error', coalesce(v_previa, ''), true);

  -- Cuadre: lo borrado = lo copiado, tabla por tabla; y de las cascadas no queda ninguna fila copiada.
  if exists (select 1 from pg_catalog.jsonb_each(v_cuadre) d where d.value <> v_filas -> d.key)
     or exists (select 1 from crm.llamadas_celular_eventos x
                where x.id in (select (e ->> 'id')::uuid from pg_catalog.jsonb_array_elements(v_copia -> 'llamadas_celular_eventos') e))
     or exists (select 1 from crm.llamadas_celular_enlaces x
                where x.id in (select (e ->> 'id')::uuid from pg_catalog.jsonb_array_elements(v_copia -> 'llamadas_celular_enlaces') e))
     or exists (select 1 from private.llamadas_celular_intenciones x
                where x.id in (select (e ->> 'id')::uuid from pg_catalog.jsonb_array_elements(v_copia -> 'llamadas_celular_intenciones') e)) then
    raise exception 'La eliminación no cuadró con la copia; no se aplicó nada' using errcode = '55000';
  end if;

  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'copia_id', v_id, 'filas', v_filas);
end $$;

comment on function crm.eliminar_lead_error_carga(uuid, text) is
  'Elimina un lead que NO es cliente con todo lo que cuelga de él (incluidas sus fichas de inversionista sin dinero, '
  'solicitudes de inversión canceladas y de tasa sin usar), dejando antes una copia en crm.leads_eliminados. Solo '
  'gerencia (CRM) o admin/superadmin (portal); motivo obligatorio. Rechaza (P0409) clientes (contrato, perfil, '
  'conversión, cierre), fichas compartidas o con dinero, más de 30 días o un mes cerrado.';

-- ── 3 · Postflight ─────────────────────────────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_bloque constant text := $b$  if tg_op = 'DELETE' then
    -- Única excepción: la vía oficial crm.eliminar_lead_error_carga, y solo para una fila ya copiada en
    -- crm.leads_eliminados en ESTA transacción (ver private.borrado_lead_error_autoriza).
    if private.borrado_lead_error_autoriza(tg_table_name, pg_catalog.to_jsonb(old)) then return old; end if;
  end if;
$b$;
begin
  if (md5(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_solicitudes_tasa_solo_por_puerta()'::regprocedure), v_bloque, '')) = '46d48b78c9e8e6553416654664bad1d8'
      and pg_catalog.length(pg_catalog.pg_get_functiondef('private.trg_solicitudes_tasa_solo_por_puerta()'::regprocedure))
          - pg_catalog.length(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_solicitudes_tasa_solo_por_puerta()'::regprocedure), v_bloque, ''))
          = pg_catalog.length(v_bloque)) is not true then
    raise exception 'POSTFLIGHT: el candado de tasa no quedó como producción + la excepción del DELETE';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p
             where p.oid = 'private.trg_solicitudes_tasa_solo_por_puerta()'::regprocedure
               and (p.proowner <> 'postgres'::regrole or p.proacl is distinct from '{postgres=X/postgres}'::aclitem[])) then
    raise exception 'POSTFLIGHT: dueño o permisos del candado de tasa';
  end if;
  if (select p.prosecdef and p.proconfig @> array['search_path=""'] and p.proowner = 'postgres'::regrole
             and p.proacl = '{postgres=X/postgres,authenticated=X/postgres}'::aclitem[]
      from pg_catalog.pg_proc p where p.oid = 'crm.eliminar_lead_error_carga(uuid,text)'::regprocedure) is not true then
    raise exception 'POSTFLIGHT: la puerta perdió DEFINER, search_path vacío, dueño o permisos';
  end if;
  if (
      md5(pg_catalog.pg_get_functiondef('private.borrado_lead_error_autoriza(text,jsonb)'::regprocedure)) = 'ca2d68e24202413ff4b7b3c962c07ed5'
      and md5(pg_catalog.pg_get_functiondef('private.eliminar_inversion_roles(uuid)'::regprocedure)) = 'e9a2341105e4028565f81164d5e02c4c'
      and md5(pg_catalog.pg_get_functiondef('private.motivo_normalizado(text)'::regprocedure)) = '08602d4022e0731952cbf61c28efe9d7'
      and md5(pg_catalog.pg_get_functiondef('private.potencial_evento_inmutable()'::regprocedure)) = '3dede26ca03faf565fdec3406562944a'
      and md5(pg_catalog.pg_get_functiondef('private.trg_actividades_no_contactar_solo_puerta()'::regprocedure)) = '8f60ebed7499eaa101e9faa2d424793c'
      and md5(pg_catalog.pg_get_functiondef('private.trg_lead_asignacion_sla_hitos_guard()'::regprocedure)) = 'f0b5874060957068ab4267593fdf989b'
      and md5(pg_catalog.pg_get_functiondef('private.trg_lead_asignaciones_inmutables()'::regprocedure)) = '53c8b34bf3a13465123f74b0a22d7c47'
      and md5(pg_catalog.pg_get_functiondef('private.trg_lead_sla_ciclos_guard()'::regprocedure)) = '9b8765c4b8debf58b28b5edec8aec31d'
      and md5(pg_catalog.pg_get_functiondef('private.trg_lead_sla_etapas_guard()'::regprocedure)) = '73ea8058cb3befe0fa97fa84bba03450'
      and md5(pg_catalog.pg_get_functiondef('private.trg_sla_nucleo_entrada_guard()'::regprocedure)) = '4e3e825c92d95049ef6c7076ecaa5066'
      and md5(pg_catalog.pg_get_functiondef('private.trg_sla_recibo_guard()'::regprocedure)) = 'f111fdd9d8eb904fde961c6dcc7a9a9a'
  ) is not true then
    raise exception 'POSTFLIGHT: cambió una función que debía quedar igual';
  end if;
  if exists (select 1 from private.contadores_crudos_leads_citas() c where c.objeto = 'crm.eliminar_lead_error_carga(uuid,text)') then
    raise exception 'POSTFLIGHT: la puerta entró al censo analítico';
  end if;
  if (select pg_catalog.array_agg(pg_catalog.pg_get_triggerdef(t.oid) || ' [' || t.tgenabled::text || ']'
                                  order by pg_catalog.pg_get_triggerdef(t.oid) || ' [' || t.tgenabled::text || ']')
      from pg_catalog.pg_trigger t
      where not t.tgisinternal and t.tgfoid in ('private.potencial_evento_inmutable()'::regprocedure, 'private.trg_actividades_no_contactar_solo_puerta()'::regprocedure, 'private.trg_lead_asignacion_sla_hitos_guard()'::regprocedure, 'private.trg_lead_asignaciones_inmutables()'::regprocedure, 'private.trg_lead_sla_ciclos_guard()'::regprocedure, 'private.trg_lead_sla_etapas_guard()'::regprocedure, 'private.trg_sla_nucleo_entrada_guard()'::regprocedure, 'private.trg_sla_recibo_guard()'::regprocedure, 'private.trg_solicitudes_tasa_solo_por_puerta()'::regprocedure)) is distinct from array[
        'CREATE TRIGGER lead_potencial_evento_inmutable BEFORE DELETE OR UPDATE ON crm.lead_potencial_eventos FOR EACH ROW EXECUTE FUNCTION private.potencial_evento_inmutable() [O]',
        'CREATE TRIGGER lead_potencial_evento_no_truncate BEFORE TRUNCATE ON crm.lead_potencial_eventos FOR EACH STATEMENT EXECUTE FUNCTION private.potencial_evento_inmutable() [O]',
        'CREATE TRIGGER sla_recibo_guard BEFORE INSERT OR DELETE OR UPDATE ON crm.sla_operacion_recibos FOR EACH ROW EXECUTE FUNCTION private.trg_sla_recibo_guard() [O]',
        'CREATE TRIGGER sla_recibo_truncate_guard BEFORE TRUNCATE ON crm.sla_operacion_recibos FOR EACH STATEMENT EXECUTE FUNCTION private.trg_sla_recibo_guard() [O]',
        'CREATE TRIGGER trg_00_actividades_no_contactar_solo_puerta BEFORE INSERT OR DELETE OR UPDATE ON crm.actividades FOR EACH ROW EXECUTE FUNCTION private.trg_actividades_no_contactar_solo_puerta() [O]',
        'CREATE TRIGGER trg_lead_asignacion_sla_hitos_guard BEFORE INSERT OR DELETE OR UPDATE ON crm.lead_asignacion_sla_hitos FOR EACH ROW EXECUTE FUNCTION private.trg_lead_asignacion_sla_hitos_guard() [O]',
        'CREATE TRIGGER trg_lead_asignaciones_00_inmutables BEFORE INSERT OR DELETE OR UPDATE ON crm.lead_asignaciones FOR EACH ROW EXECUTE FUNCTION private.trg_lead_asignaciones_inmutables() [O]',
        'CREATE TRIGGER trg_lead_sla_ciclos_guard BEFORE INSERT OR DELETE OR UPDATE ON crm.lead_sla_ciclos FOR EACH ROW EXECUTE FUNCTION private.trg_lead_sla_ciclos_guard() [O]',
        'CREATE TRIGGER trg_lead_sla_etapas_guard BEFORE INSERT OR DELETE OR UPDATE ON crm.lead_sla_etapas FOR EACH ROW EXECUTE FUNCTION private.trg_lead_sla_etapas_guard() [O]',
        'CREATE TRIGGER trg_sla_nucleo_guard BEFORE INSERT OR DELETE OR UPDATE ON crm.lead_sla_etapa_ajustes FOR EACH ROW EXECUTE FUNCTION private.trg_sla_nucleo_entrada_guard() [O]',
        'CREATE TRIGGER trg_sla_nucleo_guard BEFORE INSERT OR DELETE OR UPDATE ON crm.sla_operacion_control FOR EACH ROW EXECUTE FUNCTION private.trg_sla_nucleo_entrada_guard() [O]',
        'CREATE TRIGGER trg_sla_nucleo_guard BEFORE INSERT OR DELETE OR UPDATE ON crm.sla_politica_etapas_operacion FOR EACH ROW EXECUTE FUNCTION private.trg_sla_nucleo_entrada_guard() [O]',
        'CREATE TRIGGER trg_sla_nucleo_guard BEFORE INSERT OR DELETE OR UPDATE ON crm.tarea_sla_contexto FOR EACH ROW EXECUTE FUNCTION private.trg_sla_nucleo_entrada_guard() [O]',
        'CREATE TRIGGER trg_sla_nucleo_no_truncate BEFORE TRUNCATE ON crm.lead_sla_etapa_ajustes FOR EACH STATEMENT EXECUTE FUNCTION private.trg_sla_nucleo_entrada_guard() [O]',
        'CREATE TRIGGER trg_sla_nucleo_no_truncate BEFORE TRUNCATE ON crm.sla_operacion_control FOR EACH STATEMENT EXECUTE FUNCTION private.trg_sla_nucleo_entrada_guard() [O]',
        'CREATE TRIGGER trg_sla_nucleo_no_truncate BEFORE TRUNCATE ON crm.sla_politica_etapas_operacion FOR EACH STATEMENT EXECUTE FUNCTION private.trg_sla_nucleo_entrada_guard() [O]',
        'CREATE TRIGGER trg_sla_nucleo_no_truncate BEFORE TRUNCATE ON crm.tarea_sla_contexto FOR EACH STATEMENT EXECUTE FUNCTION private.trg_sla_nucleo_entrada_guard() [O]',
        'CREATE TRIGGER trg_solicitudes_tasa_00_solo_por_puerta BEFORE DELETE OR UPDATE ON crm.solicitudes_tasa FOR EACH ROW EXECUTE FUNCTION private.trg_solicitudes_tasa_solo_por_puerta() [O]'
      ]::text[] then
    raise exception 'POSTFLIGHT: los triggers de los candados no siguen en su modo normal';
  end if;
end
$postflight$;

notify pgrst, 'reload schema';
commit;
select pg_advisory_unlock(hashtext('crm_migracion_funciones'));
```

## Protocolo global de revisión
# Protocolo global Codex ↔ Claude Code

Aplica al usuario de esta Mac, en cualquier proyecto, aunque no exista `.ai/`.
Las instrucciones del repositorio definen negocio, arquitectura y comandos;
este protocolo define los roles y el aislamiento de las consultas.

## Roles y autoridad

- PRIMARY: posee la tarea, inspecciona, decide, implementa, ejecuta checks,
  evalúa hallazgos y entrega el resultado. Es el único escritor.
- SECONDARY_REVIEWER: analiza evidencia, bugs, regresiones, seguridad,
  arquitectura, casos límite y pruebas faltantes. No escribe archivos, no
  implementa, no hace commits, no cambia configuración, no ejecuta acciones
  destructivas, no llama al otro agente y no delega ni inicia otro review.
- Una tarea normal del usuario define un PRIMARY. Un prompt que comienza con
  `ROLE: SECONDARY_REVIEWER` define un consultor, aunque existan instrucciones
  generales de autonomía. Si le piden otra opinión, devuelve su propio análisis.
- La única cadena permitida es PRIMARY → SECONDARY_REVIEWER → PRIMARY.
- El reviewer es asesor; el PRIMARY decide con evidencia. Un PASS de IA no
  significa que la tarea esté terminada.

## Cuándo consultar

- LEVEL 1: formato, documentación sencilla, CSS pequeño, rename o fix obvio:
  cero consultas.
- LEVEL 2: lógica relevante, integración, endpoint, componente importante o
  refactor moderado: normalmente una consulta si aporta valor independiente.
- LEVEL 3: auth, permisos, secretos, seguridad, schemas/migraciones, arquitectura,
  concurrencia, pagos, lógica financiera, APIs importantes o cambios destructivos:
  una consulta cuando sea razonablemente posible.
- Máximo habitual: dos consultas por tarea, contando reviewers especializados.
  La segunda necesita nueva evidencia, discrepancia importante o corrección de
  riesgo que justifique otra verificación. No repetir hasta conseguir un PASS.
- Las instrucciones explícitas del usuario sobre consultas prevalecen. No
  consultar para confirmar trivialidades ni abrir cadenas recursivas.

## Evidence-first y formato

**NO FINDING WITHOUT EVIDENCE.** Citar archivo/líneas, símbolo, diff, test,
error, log o reproducción. Identificar como hipótesis lo no demostrado.
Omitir secciones vacías y recomendaciones genéricas sin relación con la tarea.

```text
VERDICT:
PASS | CHANGES_REQUESTED | BLOCK

SUMMARY:
Conclusión técnica breve.

FINDINGS:
[P0 | P1 | P2 | P3] Título
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

TEST GAPS:
- ...
ARCHITECTURE RISKS:
- ...
SECURITY RISKS:
- ...
REGRESSION RISKS:
- ...
RECOMMENDED NEXT ACTIONS:
1. ...
CONFIDENCE:
HIGH | MEDIUM | LOW
```

PASS: sin hallazgos obligatorios en lo revisado. CHANGES_REQUESTED: correcciones
accionables. BLOCK: riesgo crítico o evidencia insuficiente para revisar.
Resolver desacuerdos por requisitos, comportamiento, pruebas y documentación
oficial, no mediante consultas repetitivas.

## Interfaces

Codex PRIMARY usa `~/.local/bin/claude-review`, o el wrapper del repo cuando
sus instrucciones lo requieran. Adjunta código/diff saneado, rutas/líneas,
requisitos y resultados de checks. No enviar secretos. CodeGraph se usa por
el PRIMARY si el proyecto está indexado, nunca se indexa automáticamente.

El wrapper global incorpora este protocolo y, si existe, el protocolo `.ai/`
del proyecto. Claude reviewer tiene todas las herramientas, MCP, hooks y
personalizaciones deshabilitadas; no persiste la sesión. Cinco turnos por
defecto, máximo ocho. Exit 0 indica entrega válida, no necesariamente PASS.
Usa `dontAsk`, sin solicitudes de permiso, y comprueba que el evento de inicio
declare cero herramientas y cero MCP antes de aceptar un resultado único.
Las menciones genéricas a herramientas en el texto del modelo no acreditan
disponibilidad: la comprobación debe usar el inventario efectivo de la CLI.

Claude PRIMARY usa `mcp__codex__codex` con:

```text
sandbox: read-only
approval-policy: never
prompt:
ROLE: SECONDARY_REVIEWER.
Claude is the PRIMARY agent.
Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.
```

Adjuntar el contenido de este protocolo, las reglas relevantes del proyecto y
la evidencia: el reviewer no tiene herramientas para abrirlos. Solo se permite
añadir `model`; no `cwd`, `config` ni overrides de instrucciones. `codex-reply`
está bloqueado; una segunda consulta justificada inicia otro review seguro.

El MCP global usa `~/.local/bin/codex-review-mcp`. Trabaja en una carpeta neutral
de esta instalación para no cargar configuración específica de otros proyectos.
Deshabilita shell, subagentes, apps, hooks, navegador, plugins y cada MCP heredado.
Las tablas vacías TOML se fusionan: no sirven para eliminar los MCP del usuario.
Una entrada MCP local/de proyecto puede tener precedencia; comprobar su
aislamiento antes de usarla. No sustituir una interfaz protegida por una directa.

## Verificación, simultaneidad y límites

Aplicar `~/.config/ai-collaboration/VERIFICATION.md` y los gates concretos del repo.
Dos PRIMARY simultáneos en tareas distintas requieren working trees separados.
No crear worktrees automáticamente; un reviewer read-only no necesita uno.

Los hooks globales de Claude protegen secretos y operaciones peligrosas comunes;
los hooks no analizan los efectos indirectos de scripts arbitrarios. Las reglas
nativas ocultan `.env.*` también en búsquedas; incluyen `.env.example`, que se
gestiona manualmente. El usuario conserva sus modelos, plugins y ajustes normales.

El inventario del MCP se fija al arrancar. No cambiar MCP/plugins/configuración
de agentes durante el review. Tras cambiarlos, reconectar `codex` y ejecutar
`~/.local/bin/codex-review-mcp --check` antes de la siguiente consulta. No se
afirma aislamiento frente a cambios concurrentes de terceros.
