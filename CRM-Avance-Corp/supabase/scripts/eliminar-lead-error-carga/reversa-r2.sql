-- Reversa de 20261015150731_crm_eliminar_lead_ficha_inversionista.sql (r2).
--
-- Devuelve crm.eliminar_lead_error_carga a su cuerpo r1 (20261015044917; copia en
-- candados-produccion/crm.eliminar_lead_error_carga.r1.sql) y el candado de tasa a su cuerpo de producción del 15/10
-- (candados-produccion/private.trg_solicitudes_tasa_solo_por_puerta.sql), con sus comentarios. Se NIEGA si la puerta no es
-- exactamente la r2 acreditada o si el candado de tasa cambió además del bloque. Las copias en crm.leads_eliminados se
-- conservan. Aplicar en UN mensaje, solo con OK de Miguel.

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

do $preflight$
declare
  v_bloque constant text := $b$  if tg_op = 'DELETE' then
    -- Única excepción: la vía oficial crm.eliminar_lead_error_carga, y solo para una fila ya copiada en
    -- crm.leads_eliminados en ESTA transacción (ver private.borrado_lead_error_autoriza).
    if private.borrado_lead_error_autoriza(tg_table_name, pg_catalog.to_jsonb(old)) then return old; end if;
  end if;
$b$;
begin
  if (md5(pg_catalog.pg_get_functiondef('crm.eliminar_lead_error_carga(uuid,text)'::regprocedure)) = '15ce9327e21306ec9682552815936e71'
      and md5(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_solicitudes_tasa_solo_por_puerta()'::regprocedure), v_bloque, '')) = '46d48b78c9e8e6553416654664bad1d8'
      and pg_catalog.length(pg_catalog.pg_get_functiondef('private.trg_solicitudes_tasa_solo_por_puerta()'::regprocedure)) - pg_catalog.length(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_solicitudes_tasa_solo_por_puerta()'::regprocedure), v_bloque, '')) = pg_catalog.length(v_bloque)) is not true then
    raise exception 'REVERSA r2: la puerta o el candado de tasa cambiaron después de la migración; no se revierte a ciegas';
  end if;
end
$preflight$;

CREATE OR REPLACE FUNCTION crm.eliminar_lead_error_carga(p_lead_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  c_dias_max constant integer := 30;
  v_uid uuid := (select auth.uid());
  v_roles jsonb;
  v_rol text;
  v_motivo text := private.motivo_normalizado(p_motivo);
  v_lead crm.leads%rowtype;
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

  -- Fail-closed: toda llave foránea hacia el lead o hacia lo que se borra tiene que estar en esta lista, con sus
  -- columnas de origen y de destino y su acción ON DELETE (catálogo de producción, 14/10/2026). Una tabla o columna nueva enlazada, o una acción
  -- que cambie (p. ej. a CASCADE), se revisa antes de poder borrar: sin copia no se borra nada.
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
                          'private.llamadas_celular_intenciones'::regclass)
  ) k
  where k.clave <> all (array[
    'crm.actividades:lead_id:crm.leads:id:c',
    'crm.actividades_cliente:tarea_id:crm.tareas:id:n',
    'crm.ajustes_mes_cerrado:lead_id:crm.leads:id:r',
    'crm.base_carga_leads:lead_id:crm.leads:id:a',
    'crm.busquedas_cliente_existente:lead_id:crm.leads:id:a',
    'crm.cierres_avance_anulados:lead_id:crm.leads:id:r',
    'crm.cierres_externos:lead_id:crm.leads:id:r',
    'crm.conversion_acreditaciones:episodio_id:crm.lead_asignaciones:id:a',
    'crm.conversion_acreditaciones:lead_id:crm.leads:id:a',
    'crm.conversion_reservas:lead_id:crm.leads:id:r',
    'crm.inversion_solicitudes:lead_origen_id:crm.leads:id:a',
    'crm.inversionista_gestiones:tarea_id:crm.tareas:id:a',
    'crm.inversionista_leads:lead_id:crm.leads:id:a',
    'crm.inversionista_operaciones:lead_id:crm.leads:id:a',
    'crm.lead_asignacion_sla_hitos:lead_asignacion_id:crm.lead_asignaciones:id:r',
    'crm.lead_asignaciones:lead_id:crm.leads:id:r',
    'crm.lead_potencial:lead_id:crm.leads:id:a',
    'crm.lead_potencial_eventos:lead_id:crm.leads:id:a',
    'crm.lead_sla_ciclos:lead_id:crm.leads:id:r',
    'crm.lead_sla_etapa_ajustes:etapa_sla_id:crm.lead_sla_etapas:id:r',
    'crm.lead_sla_etapa_ajustes:origen_actividad_id:crm.actividades:id:r',
    'crm.lead_sla_etapas:lead_id,ciclo_n:crm.lead_sla_ciclos:lead_id,ciclo_n:r',
    'crm.lead_sla_etapas:lead_id:crm.leads:id:r',
    'crm.llamadas_celular_enlaces:actividad_id:crm.actividades:id:n',
    'crm.llamadas_celular_enlaces:evento_id:crm.llamadas_celular_eventos:id:c',
    'crm.llamadas_celular_enlaces:lead_id:crm.leads:id:c',
    'crm.llamadas_celular_eventos:lead_id:crm.leads:id:c',
    'crm.sla_operacion_recibos:lead_id:crm.leads:id:a',
    'crm.solicitudes_tasa:lead_id:crm.leads:id:r',
    'crm.tarea_sla_contexto:lead_id,ciclo_n:crm.lead_sla_ciclos:lead_id,ciclo_n:r',
    'crm.tarea_sla_contexto:tarea_id:crm.tareas:id:r',
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

  -- Mismo candado que crm.cerrar_periodo, tomado ANTES de las filas (mismo orden que el cierre: sin abrazo mortal), para
  -- que nadie selle un mes entre la comprobación del mes cerrado y el borrado.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);

  -- El lead primero (bloquea también toda fila nueva que quiera colgarse de él: su FK necesita KEY SHARE).
  select * into v_lead from crm.leads l where l.id = p_lead_id for update;
  if not found then
    raise exception 'El lead no existe o ya fue eliminado' using errcode = 'P0002';
  end if;
  -- Los padres de cada nivel, en sentencias ANTERIORES a la copia: desde aquí ninguna fila nueva puede colgarse de ellos
  -- (su FK necesita KEY SHARE) ni una asignación puede cambiar de resultado, y la copia (otra sentencia, otra
  -- instantánea) ve todo lo confirmado hasta ahora.
  perform 1 from crm.lead_asignaciones x where x.lead_id = p_lead_id order by x.id for update;
  perform 1 from crm.lead_sla_ciclos x where x.lead_id = p_lead_id order by x.id for update;
  perform 1 from crm.lead_sla_etapas x where x.lead_id = p_lead_id order by x.id for update;
  perform 1 from crm.tareas x where x.lead_id = p_lead_id order by x.id for update;
  perform 1 from crm.actividades x where x.lead_id = p_lead_id order by x.id for update;
  perform 1 from crm.llamadas_celular_eventos x where x.lead_id = p_lead_id order by x.id for update;

  if v_lead.contrato_id is not null then v_no := v_no || 'tiene un contrato enlazado'::text; end if;
  if v_lead.perfil_id is not null then v_no := v_no || 'está enlazado a un perfil de cliente'::text; end if;
  if v_lead.inversionista_id is not null then v_no := v_no || 'está enlazado a un inversionista'::text; end if;
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
  if exists (select 1 from crm.solicitudes_tasa x where x.lead_id = p_lead_id) then
    v_no := v_no || 'tiene solicitudes de tasa'::text; end if;
  if exists (select 1 from crm.inversion_solicitudes x where x.lead_origen_id = p_lead_id) then
    v_no := v_no || 'es el origen de una solicitud de inversión'::text; end if;
  if exists (select 1 from crm.inversionista_leads x where x.lead_id = p_lead_id)
     or exists (select 1 from crm.inversionista_operaciones x where x.lead_id = p_lead_id) then
    v_no := v_no || 'está en la cartera de inversionistas'::text; end if;
  if exists (select 1 from crm.busquedas_cliente_existente x where x.lead_id = p_lead_id) then
    v_no := v_no || 'tiene búsquedas de cliente existente registradas'::text; end if;
  if exists (select 1 from crm.inversionista_gestiones g join crm.tareas t on t.id = g.tarea_id where t.lead_id = p_lead_id) then
    v_no := v_no || 'tiene gestiones de inversionista'::text; end if;
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
    'version', 1,
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
            for update) r), '[]'::jsonb));
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

  -- Orden por llaves foráneas (RESTRICT/NO ACTION primero; las tareas antes que las actividades para que su
  -- ON DELETE SET NULL no reescriba tareas que también se van). Cada DELETE tiene que borrar EXACTAMENTE lo copiado.
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
  delete from crm.leads x where x.id = p_lead_id;               -- cascada: llamadas del celular (sus candados la aceptan)
  get diagnostics v_n = row_count;

  perform pg_catalog.set_config('crm.borrado_lead_error', coalesce(v_previa, ''), true);

  -- Cuadre: lo borrado = lo copiado, tabla por tabla; y de las cascadas no queda ninguna fila copiada.
  if v_n <> 1
     or exists (select 1 from pg_catalog.jsonb_each(v_cuadre) d
                where d.value <> v_filas -> d.key)
     or exists (select 1 from crm.llamadas_celular_eventos x
                where x.id in (select (e ->> 'id')::uuid from pg_catalog.jsonb_array_elements(v_copia -> 'llamadas_celular_eventos') e))
     or exists (select 1 from crm.llamadas_celular_enlaces x
                where x.id in (select (e ->> 'id')::uuid from pg_catalog.jsonb_array_elements(v_copia -> 'llamadas_celular_enlaces') e))
     or exists (select 1 from private.llamadas_celular_intenciones x
                where x.id in (select (e ->> 'id')::uuid from pg_catalog.jsonb_array_elements(v_copia -> 'llamadas_celular_intenciones') e)) then
    raise exception 'La eliminación no cuadró con la copia; no se aplicó nada' using errcode = '55000';
  end if;

  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'copia_id', v_id, 'filas', v_filas);
end $function$;

CREATE OR REPLACE FUNCTION private.trg_solicitudes_tasa_solo_por_puerta()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
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

comment on function private.trg_solicitudes_tasa_solo_por_puerta() is
  'Rentabilidad R1: cinturón contra escrituras ACCIDENTALES desde postgres (dashboard, migraciones, scripts): la API no '
  'tiene UPDATE/DELETE en la tabla (esa es la frontera de seguridad); el GUC crm.solicitud_tasa_por_puerta lo fijan las '
  'puertas crm.*_tasa_fn. No cubre INSERT (solo lo hace solicitar_tasa_fn).';
comment on column crm.leads_eliminados.copia is
  'DATOS PERSONALES. Copia jsonb: lead y un arreglo por tabla hija (tareas, actividades, asignaciones, SLA, recibos, '
  'potencial, base cargada, llamadas del celular). Enmascarada en public.audit_log.';
comment on function crm.eliminar_lead_error_carga(uuid, text) is
  'Elimina un lead cargado por error con todo lo que cuelga de él, dejando antes una copia en crm.leads_eliminados. Solo '
  'gerencia (CRM) o admin/superadmin (portal); motivo obligatorio. Rechaza (P0409) leads con contrato, perfil, '
  'inversionista, conversión o cierre, historia de inversión, más de 30 días o en un mes cerrado.';

do $postflight$
begin
  if (md5(pg_catalog.pg_get_functiondef('crm.eliminar_lead_error_carga(uuid,text)'::regprocedure)) = '016efb19dd29937619598dbe24137dd2'
      and md5(pg_catalog.pg_get_functiondef('private.trg_solicitudes_tasa_solo_por_puerta()'::regprocedure)) = '46d48b78c9e8e6553416654664bad1d8') is not true then
    raise exception 'REVERSA r2 POSTFLIGHT: la puerta o el candado de tasa no volvieron a su huella';
  end if;
end
$postflight$;

notify pgrst, 'reload schema';
commit;
select pg_advisory_unlock(hashtext('crm_migracion_funciones'));
