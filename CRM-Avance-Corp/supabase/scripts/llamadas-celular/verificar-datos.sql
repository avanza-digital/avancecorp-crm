-- Oráculo de 20261001145242_crm_llamadas_celular_datos.sql (F2-b). Se corre en un banco, como
-- dueño de las tablas, DESPUÉS de aplicar la migración. Todo ocurre dentro de una transacción que
-- termina en ROLLBACK: no deja rastro (ni en public.audit_log). Cada regla se prueba
-- EJECUTÁNDOLA; una defensa que no muerde hace fallar el oráculo.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/scripts/llamadas-celular/verificar-datos.sql
--
-- Necesita al menos dos miembros activos de crm.equipo con rol vendedor y dos leads activos en
-- etapa abierta (la semilla del gate y el banco reducido de supabase/tests/llamadas-celular los
-- traen). Datos sintéticos: ningún número real.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local timezone = 'America/Lima';

do $oraculo$
declare
  v_analista uuid;
  v_otro uuid;
  v_lead uuid;
  v_lead_otro uuid;
  v_asig uuid;
  v_asig2 uuid;
  v_ev uuid;
  v_ev2 uuid;
  v_ev3 uuid;
  v_ev4 uuid;
  v_ev5 uuid;
  v_act uuid;
  v_act2 uuid;
  v_act_otro uuid;
  v_nota uuid;
  v_t text;
  v_enlace uuid;
  v_hash constant text := repeat('a', 64);
  v_hash2 constant text := repeat('b', 64);
  v_hash3 constant text := repeat('c', 64);
  v_hash4 constant text := repeat('d', 64);
  v_n integer;
  v_ok integer := 0;
  v_cascada text := 'no comprobada';
begin
  -- ── actores y leads del banco ──────────────────────────────────────────────────────────────
  select e.perfil_id into v_analista
  from crm.equipo e join public.perfiles p on p.id = e.perfil_id
  where e.rol_crm = 'vendedor' and e.activo and p.activo
  order by e.creado_en, e.perfil_id limit 1;
  select e.perfil_id into v_otro
  from crm.equipo e join public.perfiles p on p.id = e.perfil_id
  where e.rol_crm = 'vendedor' and e.activo and p.activo and e.perfil_id <> v_analista
  order by e.creado_en, e.perfil_id limit 1;
  if v_analista is null or v_otro is null then
    raise exception 'ORACULO: hacen falta dos analistas activos en crm.equipo';
  end if;
  select l.id into v_lead from crm.leads l
  where l.activo and l.etapa not in ('convertido', 'descartado') order by l.creado_en, l.id limit 1;
  select l.id into v_lead_otro from crm.leads l
  where l.activo and l.etapa not in ('convertido', 'descartado') and l.id <> v_lead
  order by l.creado_en, l.id limit 1;
  if v_lead is null or v_lead_otro is null then
    raise exception 'ORACULO: hacen falta dos leads activos en etapa abierta';
  end if;

  -- ── 1. política: una fila, perillas de las decisiones del 30/09 ───────────────────────────
  select count(*) into v_n from crm.llamadas_celular_politica;
  if v_n <> 1 then raise exception 'ORACULO 1: la política no tiene exactamente una fila'; end if;
  if (select guardar_sin_identificar or entrantes_activas from crm.llamadas_celular_politica) then
    raise exception 'ORACULO 1: las perillas deben nacer apagadas (decisiones 2 y 3)';
  end if;
  if (select dias_retencion_descartados <> 30 or dias_retencion_sin_resolver <> 30
      from crm.llamadas_celular_politica) then
    raise exception 'ORACULO 1: la retención debe nacer en 30 días (decisión 6)';
  end if;
  begin
    delete from crm.llamadas_celular_politica;
    raise exception 'ORACULO 1: la política se dejó borrar';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  begin
    insert into crm.llamadas_celular_politica (singleton) values (false);
    raise exception 'ORACULO 1: se admitió una segunda fila de política';
  exception when check_violation or unique_violation then v_ok := v_ok + 1; end;
  begin
    update crm.llamadas_celular_politica set dias_retencion_descartados = 0;
    raise exception 'ORACULO 1: retención de 0 días aceptada';
  exception when check_violation then v_ok := v_ok + 1; end;
  update crm.llamadas_celular_politica set dias_retencion_descartados = 1, dias_retencion_sin_resolver = 1;
  if (select singleton from crm.llamadas_celular_politica) is not true then
    raise exception 'ORACULO 1: el candado no conservó singleton';
  end if;

  -- ── 2. asignaciones: una vigente por etiqueta, cierre único, inmutable después ─────────────
  insert into crm.celulares_asignaciones (etiqueta, analista_id, credencial_hash)
  values ('C1', v_analista, v_hash) returning id into v_asig;
  begin
    insert into crm.celulares_asignaciones (etiqueta, analista_id, credencial_hash)
    values ('C1', v_otro, v_hash2);
    raise exception 'ORACULO 2: dos asignaciones vigentes de C1';
  exception when unique_violation or exclusion_violation then v_ok := v_ok + 1; end;
  begin
    insert into crm.celulares_asignaciones (etiqueta, analista_id, credencial_hash)
    values ('C2', v_otro, v_hash);
    raise exception 'ORACULO 2: la misma credencial en dos asignaciones';
  exception when unique_violation then v_ok := v_ok + 1; end;
  begin
    insert into crm.celulares_asignaciones (etiqueta, analista_id, credencial_hash)
    values ('celular 1', v_otro, v_hash2);
    raise exception 'ORACULO 2: etiqueta fuera de forma aceptada';
  exception when check_violation then v_ok := v_ok + 1; end;
  begin
    insert into crm.celulares_asignaciones (etiqueta, analista_id, credencial_hash)
    values ('C3', v_otro, 'clave-en-claro');
    raise exception 'ORACULO 2: credencial que no es un sha256 aceptada';
  exception when check_violation then v_ok := v_ok + 1; end;
  begin
    update crm.celulares_asignaciones set analista_id = v_otro where id = v_asig;
    raise exception 'ORACULO 2: se dejó cambiar el analista de una asignación';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  begin
    delete from crm.celulares_asignaciones where id = v_asig;
    raise exception 'ORACULO 2: se dejó borrar una asignación';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  begin
    update crm.celulares_asignaciones set vigente_hasta = clock_timestamp() where id = v_asig; -- sin motivo
    raise exception 'ORACULO 2: cierre sin motivo aceptado';
  exception when check_violation then v_ok := v_ok + 1; end;
  -- Rotación real de otro celular: cerrar, comprobar que queda inmutable y abrir la siguiente.
  insert into crm.celulares_asignaciones (etiqueta, analista_id, credencial_hash, vigente_desde)
  values ('C2', v_otro, v_hash2, clock_timestamp() - interval '2 hours') returning id into v_asig2;
  update crm.celulares_asignaciones
     set vigente_hasta = clock_timestamp() - interval '1 hour', motivo_cierre = 'rotacion'
   where id = v_asig2;
  begin
    update crm.celulares_asignaciones set motivo_cierre = 'otro' where id = v_asig2;
    raise exception 'ORACULO 2: una asignación cerrada se dejó modificar';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  begin
    insert into crm.celulares_asignaciones (etiqueta, analista_id, credencial_hash, vigente_desde)
    values ('C2', v_analista, v_hash3, clock_timestamp() - interval '90 minutes');
    raise exception 'ORACULO 2: una vigencia que pisa el historial aceptada';
  exception when exclusion_violation then v_ok := v_ok + 1; end;
  insert into crm.celulares_asignaciones (etiqueta, analista_id, credencial_hash, vigente_desde)
  values ('C2', v_analista, v_hash4, clock_timestamp() - interval '30 minutes');

  -- ── 3. eventos: coherencias, inmutabilidad del payload, transiciones ──────────────────────
  insert into crm.llamadas_celular_eventos
    (asignacion_id, analista_id, evento_origen_id, hash_payload, numero_canonico, direccion,
     estado_tecnico, ocurrio_en, identificacion, atencion, lead_id, metodo_asociacion, asociado_en)
  values
    (v_asig, v_analista, 'c1-0001', v_hash, '+51999000111', 'saliente',
     'desconocido', now() - interval '1 minute', 'identificado', 'requiere_resultado', v_lead, 'exacto', now())
  returning id into v_ev;
  begin
    insert into crm.llamadas_celular_eventos
      (asignacion_id, analista_id, evento_origen_id, hash_payload, identificacion, atencion)
    values (v_asig, v_analista, 'c1-0001', v_hash2, 'ambiguo', 'por_revisar');
    raise exception 'ORACULO 3: mismo origen dos veces en la misma asignación';
  exception when unique_violation then v_ok := v_ok + 1; end;
  begin
    insert into crm.llamadas_celular_eventos
      (asignacion_id, analista_id, evento_origen_id, hash_payload, identificacion, atencion)
    values (v_asig, v_analista, 'c1-0002', v_hash2, 'identificado', 'requiere_resultado'); -- sin lead
    raise exception 'ORACULO 3: identificado sin lead aceptado';
  exception when check_violation then v_ok := v_ok + 1; end;
  begin
    insert into crm.llamadas_celular_eventos
      (asignacion_id, analista_id, evento_origen_id, hash_payload, identificacion, atencion, numero_canonico)
    values (v_asig, v_analista, 'c1-0003', v_hash2, 'ambiguo', 'por_revisar', '999000111'); -- no E.164
    raise exception 'ORACULO 3: número fuera de E.164 aceptado';
  exception when check_violation then v_ok := v_ok + 1; end;
  begin
    insert into crm.llamadas_celular_eventos
      (asignacion_id, analista_id, evento_origen_id, hash_payload, identificacion, atencion,
       motivo_descarte, descartado_por, descartado_en)
    values (v_asig, v_analista, 'c1-0004', v_hash2, 'ambiguo', 'descartado_con_motivo',
            'otro', v_analista, now()); -- «otro» sin detalle
    raise exception 'ORACULO 3: descarte «otro» sin detalle aceptado';
  exception when check_violation then v_ok := v_ok + 1; end;
  begin
    insert into crm.llamadas_celular_eventos
      (asignacion_id, analista_id, evento_origen_id, hash_payload, identificacion, atencion,
       lead_id, metodo_asociacion, asociado_en)
    values (v_asig, v_analista, 'c1-0005', v_hash2, 'identificado', 'requiere_resultado',
            v_lead, 'manual', now()); -- manual sin quién
    raise exception 'ORACULO 3: asociación manual sin autor aceptada';
  exception when check_violation then v_ok := v_ok + 1; end;
  begin
    insert into crm.llamadas_celular_eventos
      (asignacion_id, analista_id, evento_origen_id, hash_payload, identificacion, atencion,
       lead_id, metodo_asociacion, asociado_en, direccion)
    values (v_asig, v_analista, 'c1-0006', v_hash2, 'identificado', 'requiere_devolucion',
            v_lead, 'exacto', now(), 'saliente'); -- devolución de una saliente
    raise exception 'ORACULO 3: «requiere devolución» en una saliente aceptado';
  exception when check_violation then v_ok := v_ok + 1; end;
  begin
    update crm.llamadas_celular_eventos set numero_canonico = '+51999000222' where id = v_ev;
    raise exception 'ORACULO 3: el número de una llamada se dejó cambiar';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  begin
    update crm.llamadas_celular_eventos set ocurrio_en = now() where id = v_ev;
    raise exception 'ORACULO 3: la hora de una llamada se dejó cambiar';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  begin
    update crm.llamadas_celular_eventos set atencion = 'por_revisar', identificacion = 'ambiguo', lead_id = null,
      metodo_asociacion = null, asociado_en = null where id = v_ev;
    raise exception 'ORACULO 3: una identificada volvió a ambigua';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  begin
    delete from crm.llamadas_celular_eventos where id = v_ev;
    raise exception 'ORACULO 3: DELETE directo aceptado';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  -- corrección de lead permitida mientras está por atender
  update crm.llamadas_celular_eventos
     set lead_id = v_lead_otro, metodo_asociacion = 'manual', asociado_por = v_analista, asociado_en = now()
   where id = v_ev;
  update crm.llamadas_celular_eventos
     set lead_id = v_lead, metodo_asociacion = 'manual', asociado_por = v_analista, asociado_en = now()
   where id = v_ev;

  -- ── 4. enlaces: solo a un resultado de llamada del mismo lead; cambio solo si fue deshecho ─
  perform set_config('crm.op_resultado_llamada', 'on', true);
  insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
  values (v_lead, 'llamada_no_contestada', 'oráculo F2-b',
          jsonb_build_object('evento', 'resultado_llamada', 'resultado', 'no_contesto'), v_analista)
  returning id into v_act;
  insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
  values (v_lead, 'llamada_realizada', 'oráculo F2-b (corregida)',
          jsonb_build_object('evento', 'resultado_llamada', 'resultado', 'volver_a_llamar'), v_analista)
  returning id into v_act2;
  -- Un resultado de llamada válido pero de OTRO lead, y una nota del MISMO lead: cada caso de
  -- abajo viola una sola regla, para que quitar cualquiera de ellas haga fallar el oráculo.
  insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
  values (v_lead_otro, 'llamada_realizada', 'oráculo F2-b (otro lead)',
          jsonb_build_object('evento', 'resultado_llamada', 'resultado', 'volver_a_llamar'), v_analista)
  returning id into v_act_otro;
  perform set_config('crm.op_resultado_llamada', 'off', true);
  insert into crm.actividades (lead_id, tipo, detalle, creado_por)
  values (v_lead, 'nota', 'oráculo F2-b nota', v_analista)
  returning id into v_nota;

  begin
    insert into crm.llamadas_celular_enlaces (evento_id, actividad_id, lead_id, enlazado_por)
    values (v_ev, v_nota, v_lead, v_analista);
    raise exception 'ORACULO 4: enlace a una nota (no es un resultado de llamada) aceptado';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  begin
    insert into crm.llamadas_celular_enlaces (evento_id, actividad_id, lead_id, enlazado_por)
    values (v_ev, v_act_otro, v_lead, v_analista);
    raise exception 'ORACULO 4: enlace a un resultado de llamada de otro lead aceptado';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  begin
    insert into crm.llamadas_celular_enlaces (evento_id, actividad_id, lead_id, enlazado_por)
    values (v_ev, v_act_otro, v_lead_otro, v_analista);
    raise exception 'ORACULO 4: enlace con un lead distinto al de la llamada aceptado';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  begin
    insert into crm.llamadas_celular_enlaces (evento_id, lead_id, enlazado_por) values (v_ev, v_lead, v_analista);
    raise exception 'ORACULO 4: enlace sin actividad aceptado';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  insert into crm.llamadas_celular_enlaces (evento_id, actividad_id, lead_id, enlazado_por)
  values (v_ev, v_act, v_lead, v_analista) returning id into v_enlace;
  begin
    insert into crm.llamadas_celular_enlaces (evento_id, actividad_id, lead_id, enlazado_por)
    values (v_ev, v_act2, v_lead, v_analista);
    raise exception 'ORACULO 4: una llamada con dos enlaces aceptada';
  exception when unique_violation then v_ok := v_ok + 1; end;
  update crm.llamadas_celular_eventos set atencion = 'registrado' where id = v_ev;
  begin
    update crm.llamadas_celular_eventos
       set lead_id = v_lead_otro, metodo_asociacion = 'manual', asociado_por = v_analista, asociado_en = now()
     where id = v_ev;
    raise exception 'ORACULO 4: una llamada registrada se dejó cambiar de lead';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  begin
    update crm.llamadas_celular_enlaces set actividad_id = v_act2 where id = v_enlace;
    raise exception 'ORACULO 4: el enlace cambió sin que el resultado anterior estuviera deshecho';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  perform set_config('crm.op_resultado_llamada', 'on', true);
  update crm.actividades set metadata = metadata || jsonb_build_object('deshecho_en', now()) where id = v_act;
  perform set_config('crm.op_resultado_llamada', 'off', true);
  -- Con el resultado ya deshecho, desenlazar sigue prohibido: se marca, no se borra.
  begin
    update crm.llamadas_celular_enlaces set actividad_id = null where id = v_enlace;
    raise exception 'ORACULO 4: el enlace se dejó desenlazar';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  update crm.llamadas_celular_enlaces set actividad_id = v_act2 where id = v_enlace;
  begin
    update crm.llamadas_celular_eventos set atencion = 'requiere_resultado' where id = v_ev;
    raise exception 'ORACULO 4: una llamada registrada volvió a pedir resultado';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  begin
    delete from crm.llamadas_celular_enlaces where id = v_enlace;
    raise exception 'ORACULO 4: DELETE directo del enlace aceptado';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;

  -- ── 5. retención: solo lo vencido y solo por la purga; la auditoría sin número ni hash ────
  insert into crm.llamadas_celular_eventos
    (asignacion_id, analista_id, evento_origen_id, hash_payload, numero_canonico, identificacion, atencion,
     motivo_descarte, descartado_por, descartado_en, recibido_en)
  values (v_asig, v_analista, 'c1-0007', v_hash3, '+51999000333', 'ambiguo', 'descartado_con_motivo',
          'personal', v_analista, now() - interval '3 days', now() - interval '3 days')
  returning id into v_ev2;
  insert into crm.llamadas_celular_eventos
    (asignacion_id, analista_id, evento_origen_id, hash_payload, numero_canonico, identificacion, atencion, recibido_en)
  values (v_asig, v_analista, 'c1-0008', v_hash4, '+51999000444', 'ambiguo', 'por_revisar', now() - interval '3 days')
  returning id into v_ev3;
  -- Lo reciente NO se purga: un descarte de hoy y una ambigua de hoy sobreviven.
  insert into crm.llamadas_celular_eventos
    (asignacion_id, analista_id, evento_origen_id, hash_payload, identificacion, atencion,
     motivo_descarte, descartado_por, descartado_en)
  values (v_asig, v_analista, 'c1-0009', v_hash3, 'ambiguo', 'descartado_con_motivo',
          'numero_de_prueba', v_analista, now())
  returning id into v_ev4;
  insert into crm.llamadas_celular_eventos
    (asignacion_id, analista_id, evento_origen_id, hash_payload, identificacion, atencion)
  values (v_asig, v_analista, 'c1-0010', v_hash4, 'ambiguo', 'por_revisar')
  returning id into v_ev5;
  begin
    update crm.llamadas_celular_eventos set identificacion = 'sin_identificar' where id = v_ev3;
    raise exception 'ORACULO 5: una ambigua retrocedió a sin identificar';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  begin
    update crm.llamadas_celular_eventos set atencion = 'registrado' where id = v_ev3;
    raise exception 'ORACULO 5: «por revisar» saltó a «registrado» sin pasar por el resultado';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  begin
    update crm.llamadas_celular_eventos set motivo_descarte = 'no_comercial' where id = v_ev2;
    raise exception 'ORACULO 5: el motivo de un descarte se dejó reescribir';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  select private.caducar_llamadas_celular() into v_n;
  if v_n <> 2 then raise exception 'ORACULO 5: la purga borró % filas, se esperaban 2 (política a 1 día)', v_n; end if;
  if exists (select 1 from crm.llamadas_celular_eventos where id in (v_ev2, v_ev3)) then
    raise exception 'ORACULO 5: la purga no retiró lo vencido';
  end if;
  if not exists (select 1 from crm.llamadas_celular_eventos where id = v_ev) then
    raise exception 'ORACULO 5: la purga tocó una llamada registrada';
  end if;
  if (select count(*) from crm.llamadas_celular_eventos where id in (v_ev4, v_ev5)) <> 2 then
    raise exception 'ORACULO 5: la purga borró llamadas recientes (dentro del plazo de retención)';
  end if;
  if coalesce(current_setting('crm.op_purga_llamadas', true), 'off') = 'on' then
    raise exception 'ORACULO 5: la purga dejó el GUC encendido';
  end if;
  select count(*) into v_n from public.audit_log a
  where a.tabla = 'crm.llamadas_celular_eventos' and a.operacion = 'DELETE'
    and a.data_antes ->> 'numero_canonico' = '***' and a.data_antes ->> 'hash_payload' = '***';
  if v_n < 2 then
    raise exception 'ORACULO 5: la auditoría no conservó las dos llamadas purgadas enmascaradas (hay %)', v_n;
  end if;
  if exists (select 1 from public.audit_log a
             where a.tabla in ('crm.llamadas_celular_eventos', 'crm.celulares_asignaciones')
               and (coalesce(a.data_antes::text, '') || coalesce(a.data_despues::text, '')) ~ '\+51999|aaaaaaaaaaaaaaaa|bbbbbbbbbbbbbbbb|cccccccccccccccc|dddddddddddddddd') then
    raise exception 'ORACULO 5: la auditoría copió un número, un hash de payload o una credencial';
  end if;

  -- ── 6. ninguna de las cuatro tablas se vacía (ni en cascada) ──────────────────────────────
  foreach v_t in array array['crm.llamadas_celular_politica', 'crm.celulares_asignaciones',
                             'crm.llamadas_celular_eventos', 'crm.llamadas_celular_enlaces'] loop
    begin
      execute 'truncate ' || v_t || ' cascade';
      raise exception 'ORACULO 6: % se dejó vaciar', v_t;
    exception when insufficient_privilege then v_ok := v_ok + 1; end;
  end loop;

  -- ── 7. cascada: eliminar el lead se lleva la llamada y su enlace ───────────────────────────
  -- En producción los leads no se borran (y el ledger de asignaciones lo impide con RESTRICT);
  -- en un banco con ledger el caso no es construible y se informa en vez de fingirlo.
  begin
    perform set_config('crm.op_privilegiada', 'on', true);
    delete from crm.leads where id = v_lead;
    perform set_config('crm.op_privilegiada', 'off', true);
    if exists (select 1 from crm.llamadas_celular_eventos where id = v_ev)
       or exists (select 1 from crm.llamadas_celular_enlaces where id = v_enlace) then
      raise exception 'ORACULO 7: la cascada del lead no retiró la llamada o su enlace';
    end if;
    v_cascada := 'comprobada';
  -- Solo la restricción de otra tabla (el ledger) hace el caso no construible. Un 42501 de los
  -- candados de esta migración en plena cascada sería un fallo real: no se atrapa.
  exception when foreign_key_violation then
    v_cascada := 'no construible en este banco (' || sqlerrm || ')';
  end;

  raise notice 'ORACULO F2-b OK: % defensas mordieron; transiciones, re-enlace y purga comprobados; cascada %', v_ok, v_cascada;
end;
$oraculo$;

rollback;
