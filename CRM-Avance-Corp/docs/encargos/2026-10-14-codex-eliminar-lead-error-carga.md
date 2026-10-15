ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo: REFUTAR la migración «eliminar lead por error de carga» (CRM Avance Corp, Postgres/Supabase) — LEVEL 3

Tú no ves la base ni la red: todo lo que necesitas está transcrito abajo (catálogo de PRODUCCIÓN leído el 14/10/2026).
Intenta ROMPERLA, no confirmarla. Formato: VERDICT, SUMMARY, FINDINGS P0–P3 (cada uno con línea/símbolo y escenario
concreto), RISKS/TEST GAPS, NEXT ACTIONS, CONFIDENCE. Sin hallazgo sin evidencia; separa hipótesis.

## Pedido de Miguel (resumen)
RPC crm.eliminar_lead_error_carga(p_lead_id uuid, p_motivo text) → jsonb, SECURITY DEFINER, search_path ''. Solo gerencia
(rol CRM) o admin/superadmin (portal), 42501 si no. Motivo ≥10. Solo si el lead no tiene contrato/perfil/inversionista, ni
conversión/cierres, ni mes cerrado, y ≤30 días. Permiso de borrado por set_config('crm.borrado_lead_error', lead, true)
que los guards aceptan solo para ese lead; sin DISABLE TRIGGER; los candados NO se debilitan. Copia previa en
crm.leads_eliminados (solo lectura gerencia, nadie borra). DELETE directo sin la RPC debe seguir bloqueado.

## Preguntas concretas para refutar
1. ¿Existe algún camino por el que la excepción añadida a los 8 candados abra un DELETE fuera de la puerta (otro rol,
   otra transacción, GUC puesto a mano, fila no copiada, fila de otro lead, cascada)? ¿Puede un cliente PostgREST fijar
   `crm.borrado_lead_error`?
2. ¿El orden de borrado funciona con las FK y triggers transcritos (RESTRICT, NO ACTION, CASCADE, SET NULL, candados de
   llamadas que aceptan pg_trigger_depth()>1, SET NULL que dispara BEFORE UPDATE)? ¿Algún DELETE muere o deja algo?
3. ¿La comparación `copia -> tabla @> jsonb_build_array(to_jsonb(old))` falla en algún tipo (timestamptz, numeric,
   xid8, arrays) entre la fila copiada y OLD dentro de la misma transacción?
4. ¿Las condiciones de rechazo son suficientes (conversión, mes cerrado, 30 días)? ¿Carreras con conversión o sellado?
5. ¿El postflight realmente prueba que los candados solo cambiaron en el bloque añadido? ¿El preflight es fiable?
6. Capas/permisos: ¿la política de lectura, grants y la llave (no DEFINER, sin EXECUTE para authenticated) son correctos?
   Nota: 3 de los candados son SECURITY INVOKER (trg_sla_nucleo_entrada_guard, trg_sla_recibo_guard,
   potencial_evento_inmutable) y llaman a la llave como current_user.

## Catálogo de producción (14/10/2026)
### FK recursivas hacia crm.leads (nivel, hijo, padre, constraint, confdeltype a=no action r=restrict c=cascade n=set null)
nivel,hijo,padre,conname,confdeltype,def
2,crm.actividades_cliente,crm.tareas,actividades_cliente_tarea_id_fkey,n,FOREIGN KEY (tarea_id) REFERENCES crm.tareas(id) ON DELETE SET NULL
1,crm.actividades,crm.leads,actividades_lead_id_fkey,c,FOREIGN KEY (lead_id) REFERENCES crm.leads(id) ON DELETE CASCADE
1,crm.ajustes_mes_cerrado,crm.leads,ajustes_mes_cerrado_lead_id_fkey,r,FOREIGN KEY (lead_id) REFERENCES crm.leads(id) ON DELETE RESTRICT
1,crm.base_carga_leads,crm.leads,base_carga_leads_lead_id_fkey,a,FOREIGN KEY (lead_id) REFERENCES crm.leads(id)
1,crm.busquedas_cliente_existente,crm.leads,busquedas_cliente_existente_lead_id_fkey,a,FOREIGN KEY (lead_id) REFERENCES crm.leads(id)
1,crm.cierres_avance_anulados,crm.leads,cierres_avance_anulados_lead_id_fkey,r,FOREIGN KEY (lead_id) REFERENCES crm.leads(id) ON DELETE RESTRICT
1,crm.cierres_externos,crm.leads,cierres_externos_lead_id_fkey,r,FOREIGN KEY (lead_id) REFERENCES crm.leads(id) ON DELETE RESTRICT
2,crm.conversion_acreditaciones,crm.lead_asignaciones,conversion_acreditaciones_episodio_id_fkey,a,FOREIGN KEY (episodio_id) REFERENCES crm.lead_asignaciones(id)
1,crm.conversion_acreditaciones,crm.leads,conversion_acreditaciones_lead_id_fkey,a,FOREIGN KEY (lead_id) REFERENCES crm.leads(id)
1,crm.conversion_reservas,crm.leads,conversion_reservas_lead_id_fkey,r,FOREIGN KEY (lead_id) REFERENCES crm.leads(id) ON DELETE RESTRICT
2,crm.depositos_reclamados,crm.cierres_externos,depositos_reclamados_cierre_id_fkey,r,FOREIGN KEY (cierre_id) REFERENCES crm.cierres_externos(id) ON DELETE RESTRICT
2,crm.envios_push_tasa,crm.solicitudes_tasa,envios_push_tasa_solicitud_id_fkey,a,FOREIGN KEY (solicitud_id) REFERENCES crm.solicitudes_tasa(id)
3,crm.inversion_ajustes_mes_cerrado,crm.inversiones,inversion_ajustes_mes_cerrado_inversion_id_fkey,a,FOREIGN KEY (inversion_id) REFERENCES crm.inversiones(id)
3,crm.inversion_cotitular_origenes,crm.inversiones,inversion_cotitular_origenes_inversion_id_fkey,a,FOREIGN KEY (inversion_id) REFERENCES crm.inversiones(id)
3,crm.inversion_eventos,crm.inversiones,inversion_eventos_inversion_id_fkey,a,FOREIGN KEY (inversion_id) REFERENCES crm.inversiones(id)
2,crm.inversion_solicitud_correcciones,crm.inversion_solicitudes,inversion_solicitud_correcciones_solicitud_id_fkey,a,FOREIGN KEY (solicitud_id) REFERENCES crm.inversion_solicitudes(id)
2,crm.inversion_solicitud_origenes,crm.cierres_externos,inversion_solicitud_origenes_fuente_id_fkey,a,FOREIGN KEY (fuente_id) REFERENCES crm.cierres_externos(id)
2,crm.inversion_solicitud_origenes,crm.inversion_solicitudes,inversion_solicitud_origenes_solicitud_id_fkey,a,FOREIGN KEY (solicitud_id) REFERENCES crm.inversion_solicitudes(id)
2,crm.inversion_solicitud_revisiones,crm.inversion_solicitudes,inversion_solicitud_revisiones_solicitud_id_fkey,a,FOREIGN KEY (solicitud_id) REFERENCES crm.inversion_solicitudes(id)
2,crm.inversion_solicitudes,crm.busquedas_cliente_existente,inversion_solicitudes_busqueda_id_fkey,a,FOREIGN KEY (busqueda_id) REFERENCES crm.busquedas_cliente_existente(id)
3,crm.inversion_solicitudes,crm.inversiones,inversion_solicitudes_inversion_id_fkey,a,FOREIGN KEY (inversion_id) REFERENCES crm.inversiones(id)
1,crm.inversion_solicitudes,crm.leads,inversion_solicitudes_lead_origen_id_fkey,a,FOREIGN KEY (lead_origen_id) REFERENCES crm.leads(id)
3,crm.inversion_titulares,crm.inversiones,inversion_titulares_inversion_id_fkey,a,FOREIGN KEY (inversion_id) REFERENCES crm.inversiones(id)
2,crm.inversiones,crm.cierres_externos,inversiones_cierre_externo_id_fkey,r,FOREIGN KEY (cierre_externo_id) REFERENCES crm.cierres_externos(id) ON DELETE RESTRICT
2,crm.inversionista_gestiones,crm.tareas,inversionista_gestiones_tarea_id_fkey,a,FOREIGN KEY (tarea_id) REFERENCES crm.tareas(id)
1,crm.inversionista_leads,crm.leads,inversionista_leads_lead_id_fkey,a,FOREIGN KEY (lead_id) REFERENCES crm.leads(id)
1,crm.inversionista_operaciones,crm.leads,inversionista_operaciones_lead_id_fkey,a,FOREIGN KEY (lead_id) REFERENCES crm.leads(id)
2,crm.lead_asignacion_sla_hitos,crm.lead_asignaciones,lead_asignacion_sla_hitos_lead_asignacion_id_fkey,r,FOREIGN KEY (lead_asignacion_id) REFERENCES crm.lead_asignaciones(id) ON DELETE RESTRICT
1,crm.lead_asignaciones,crm.leads,lead_asignaciones_lead_id_fkey,r,FOREIGN KEY (lead_id) REFERENCES crm.leads(id) ON DELETE RESTRICT
1,crm.lead_potencial_eventos,crm.leads,lead_potencial_eventos_lead_id_fkey,a,FOREIGN KEY (lead_id) REFERENCES crm.leads(id)
1,crm.lead_potencial,crm.leads,lead_potencial_lead_id_fkey,a,FOREIGN KEY (lead_id) REFERENCES crm.leads(id)
1,crm.lead_sla_ciclos,crm.leads,lead_sla_ciclos_lead_id_fkey,r,FOREIGN KEY (lead_id) REFERENCES crm.leads(id) ON DELETE RESTRICT
2,crm.lead_sla_etapa_ajustes,crm.lead_sla_etapas,lead_sla_etapa_ajustes_etapa_sla_id_fkey,r,FOREIGN KEY (etapa_sla_id) REFERENCES crm.lead_sla_etapas(id) ON DELETE RESTRICT
2,crm.lead_sla_etapa_ajustes,crm.actividades,lead_sla_etapa_ajustes_origen_actividad_id_fkey,r,FOREIGN KEY (origen_actividad_id) REFERENCES crm.actividades(id) ON DELETE RESTRICT
2,crm.lead_sla_etapas,crm.lead_sla_ciclos,lead_sla_etapas_ciclo_fk,r,"FOREIGN KEY (lead_id, ciclo_n) REFERENCES crm.lead_sla_ciclos(lead_id, ciclo_n) ON DELETE RESTRICT"
1,crm.lead_sla_etapas,crm.leads,lead_sla_etapas_lead_id_fkey,r,FOREIGN KEY (lead_id) REFERENCES crm.leads(id) ON DELETE RESTRICT
2,crm.ledger_rentabilidad,crm.solicitudes_tasa,ledger_rentabilidad_solicitud_id_fkey,r,FOREIGN KEY (solicitud_id) REFERENCES crm.solicitudes_tasa(id) ON DELETE RESTRICT
2,crm.llamadas_celular_enlaces,crm.actividades,llamadas_celular_enlaces_actividad_id_fkey,n,FOREIGN KEY (actividad_id) REFERENCES crm.actividades(id) ON DELETE SET NULL
2,crm.llamadas_celular_enlaces,crm.llamadas_celular_eventos,llamadas_celular_enlaces_evento_id_fkey,c,FOREIGN KEY (evento_id) REFERENCES crm.llamadas_celular_eventos(id) ON DELETE CASCADE
1,crm.llamadas_celular_enlaces,crm.leads,llamadas_celular_enlaces_lead_id_fkey,c,FOREIGN KEY (lead_id) REFERENCES crm.leads(id) ON DELETE CASCADE
1,crm.llamadas_celular_eventos,crm.leads,llamadas_celular_eventos_lead_id_fkey,c,FOREIGN KEY (lead_id) REFERENCES crm.leads(id) ON DELETE CASCADE
2,private.llamadas_celular_intenciones,crm.actividades,llamadas_celular_intenciones_actividad_id_fkey,c,FOREIGN KEY (actividad_id) REFERENCES crm.actividades(id) ON DELETE CASCADE
1,private.llamadas_celular_intenciones,crm.leads,llamadas_celular_intenciones_lead_id_fkey,c,FOREIGN KEY (lead_id) REFERENCES crm.leads(id) ON DELETE CASCADE
2,crm.postventa_retiros,crm.cierres_externos,postventa_retiros_fuente_id_fkey,a,FOREIGN KEY (fuente_id) REFERENCES crm.cierres_externos(id)
1,crm.sla_operacion_recibos,crm.leads,sla_operacion_recibos_lead_id_fkey,a,FOREIGN KEY (lead_id) REFERENCES crm.leads(id) DEFERRABLE INITIALLY DEFERRED
1,crm.solicitudes_tasa,crm.leads,solicitudes_tasa_lead_id_fkey,r,FOREIGN KEY (lead_id) REFERENCES crm.leads(id) ON DELETE RESTRICT
2,crm.tarea_sla_contexto,crm.lead_sla_ciclos,tarea_sla_contexto_lead_id_ciclo_n_fkey,r,"FOREIGN KEY (lead_id, ciclo_n) REFERENCES crm.lead_sla_ciclos(lead_id, ciclo_n) ON DELETE RESTRICT"
2,crm.tarea_sla_contexto,crm.tareas,tarea_sla_contexto_tarea_id_fkey,r,FOREIGN KEY (tarea_id) REFERENCES crm.tareas(id) ON DELETE RESTRICT
1,crm.tareas,crm.leads,tareas_lead_id_fkey,c,FOREIGN KEY (lead_id) REFERENCES crm.leads(id) ON DELETE CASCADE
2,crm.tareas,crm.tareas,tareas_reagendada_de_fkey,n,FOREIGN KEY (reagendada_de) REFERENCES crm.tareas(id) ON DELETE SET NULL
2,crm.tareas,crm.actividades,tareas_resultado_actividad_id_fkey,n,FOREIGN KEY (resultado_actividad_id) REFERENCES crm.actividades(id) ON DELETE SET NULL

### Triggers que disparan en DELETE/TRUNCATE sobre esas tablas (tabla, trigger, función, cuándo, nivel, eventos I|D|U|T)
tabla,tgname,fn,cuando,nivel,eventos,en,tgdeferrable
crm.actividades,trg_00_actividades_no_contactar_solo_puerta,private.trg_actividades_no_contactar_solo_puerta,BEFORE,ROW,I|D|U,O,false
crm.actividades,trg_audit_actividades_cambio_baja,private.log_audit_crm,AFTER,ROW,D|U,O,false
crm.actividades_cliente,trg_audit_actividades_cliente,private.log_audit_crm,AFTER,ROW,I|D|U,O,false
crm.ajustes_mes_cerrado,trg_ajustes_mes_cerrado_00_solo_saldar,private.trg_ajustes_mes_cerrado_solo_saldar,BEFORE,ROW,D|U,O,false
crm.ajustes_mes_cerrado,trg_audit_ajustes_mes_cerrado,private.log_audit_crm,AFTER,ROW,I|D|U,O,false
crm.base_carga_leads,trg_audit_base_carga_leads,private.log_audit_crm,AFTER,ROW,I|D|U,O,false
crm.busquedas_cliente_existente,busqueda_cliente_inmutable,private.busqueda_cliente_inmutable,BEFORE,ROW,D|U,O,false
crm.busquedas_cliente_existente,busqueda_cliente_no_truncate,private.busqueda_cliente_inmutable,BEFORE,STMT,T,O,false
crm.busquedas_cliente_existente,trg_audit_busquedas_cliente_existente,private.log_audit_sin_secretos,AFTER,ROW,I|D|U,O,false
crm.cierres_avance_anulados,trg_audit_cierres_avance_anulados,private.log_audit_crm,AFTER,ROW,I|D|U,O,false
crm.cierres_avance_anulados,trg_cierres_avance_anulados_00_append_only,private.trg_cierres_avance_anulados_append_only,BEFORE,ROW,D|U,O,false
crm.cierres_externos,trg_audit_cierres_externos,private.log_audit_sin_secretos,AFTER,ROW,I|D|U,O,false
crm.cierres_externos,trg_cierres_externos_00_inmutables,private.trg_cierres_externos_inmutables,BEFORE,ROW,D|U,O,false
crm.conversion_acreditaciones,trg_audit_conversion_acreditaciones,private.log_audit_crm,AFTER,ROW,I|D|U,O,false
crm.conversion_reservas,trg_audit_conversion_reservas,private.log_audit_crm,AFTER,ROW,I|D|U,O,false
crm.inversion_solicitudes,trg_audit_inversion_solicitudes,private.log_audit_sin_secretos,AFTER,ROW,I|D|U,O,false
crm.inversionista_gestiones,trg_audit_inversionista_gestiones,private.log_audit_crm,AFTER,ROW,I|D|U,O,false
crm.inversionista_leads,trg_audit_inversionista_leads,private.log_audit_crm,AFTER,ROW,I|D|U,O,false
crm.inversionista_operaciones,trg_audit_inversionista_operaciones,private.log_audit_crm,AFTER,ROW,I|D|U,O,false
crm.inversionista_operaciones,trg_inversionista_operaciones_append_only,private.inversionista_operaciones_append_only,BEFORE,ROW,D|U,O,false
crm.lead_asignacion_sla_hitos,trg_audit_lead_asignacion_sla_hitos_completa,private.log_audit_crm,AFTER,ROW,D,O,false
crm.lead_asignacion_sla_hitos,trg_lead_asignacion_sla_hitos_guard,private.trg_lead_asignacion_sla_hitos_guard,BEFORE,ROW,I|D|U,O,false
crm.lead_asignaciones,trg_audit_lead_asignaciones_completa,private.log_audit_crm,AFTER,ROW,D,O,false
crm.lead_asignaciones,trg_lead_asignaciones_00_inmutables,private.trg_lead_asignaciones_inmutables,BEFORE,ROW,I|D|U,O,false
crm.lead_potencial,trg_audit_lead_potencial,private.log_audit_crm,AFTER,ROW,I|D|U,O,false
crm.lead_potencial_eventos,lead_potencial_evento_inmutable,private.potencial_evento_inmutable,BEFORE,ROW,D|U,O,false
crm.lead_potencial_eventos,lead_potencial_evento_no_truncate,private.potencial_evento_inmutable,BEFORE,STMT,T,O,false
crm.lead_potencial_eventos,trg_audit_lead_potencial_eventos,private.log_audit_crm,AFTER,ROW,I|D|U,O,false
crm.lead_sla_ciclos,trg_audit_lead_sla_ciclos_completa,private.log_audit_crm,AFTER,ROW,D,O,false
crm.lead_sla_ciclos,trg_lead_sla_ciclos_guard,private.trg_lead_sla_ciclos_guard,BEFORE,ROW,I|D|U,O,false
crm.lead_sla_etapa_ajustes,trg_audit_lead_sla_etapa_ajustes,private.log_audit_crm,AFTER,ROW,I|D|U,O,false
crm.lead_sla_etapa_ajustes,trg_sla_nucleo_guard,private.trg_sla_nucleo_entrada_guard,BEFORE,ROW,I|D|U,O,false
crm.lead_sla_etapa_ajustes,trg_sla_nucleo_no_truncate,private.trg_sla_nucleo_entrada_guard,BEFORE,STMT,T,O,false
crm.lead_sla_etapas,trg_audit_lead_sla_etapas_completa,private.log_audit_crm,AFTER,ROW,D,O,false
crm.lead_sla_etapas,trg_lead_sla_etapas_guard,private.trg_lead_sla_etapas_guard,BEFORE,ROW,I|D|U,O,false
crm.leads,trg_audit_leads,private.log_audit_sin_secretos,AFTER,ROW,I|D|U,O,false
crm.llamadas_celular_enlaces,trg_audit_llamadas_celular_enlaces,private.log_audit_crm,AFTER,ROW,I|D|U,O,false
crm.llamadas_celular_enlaces,trg_llamadas_celular_enlaces_00_candado,private.trg_llamadas_celular_enlaces_candado,BEFORE,ROW,I|D|U,O,false
crm.llamadas_celular_enlaces,trg_llamadas_celular_enlaces_00_sin_vaciar,private.trg_llamadas_celular_sin_vaciar,BEFORE,STMT,T,O,false
crm.llamadas_celular_eventos,trg_audit_llamadas_celular_eventos,private.log_audit_sin_secretos,AFTER,ROW,I|D|U,O,false
crm.llamadas_celular_eventos,trg_llamadas_celular_eventos_00_candado,private.trg_llamadas_celular_eventos_candado,BEFORE,ROW,D|U,O,false
crm.llamadas_celular_eventos,trg_llamadas_celular_eventos_00_sin_vaciar,private.trg_llamadas_celular_sin_vaciar,BEFORE,STMT,T,O,false
crm.sla_operacion_recibos,audit_sla_operacion_recibos,private.log_audit_crm,AFTER,ROW,I|D|U,O,false
crm.sla_operacion_recibos,sla_recibo_guard,private.trg_sla_recibo_guard,BEFORE,ROW,I|D|U,O,false
crm.sla_operacion_recibos,sla_recibo_truncate_guard,private.trg_sla_recibo_guard,BEFORE,STMT,T,O,false
crm.solicitudes_tasa,trg_audit_solicitudes_tasa,private.log_audit_crm,AFTER,ROW,I|D|U,O,false
crm.solicitudes_tasa,trg_solicitudes_tasa_00_solo_por_puerta,private.trg_solicitudes_tasa_solo_por_puerta,BEFORE,ROW,D|U,O,false
crm.tarea_sla_contexto,trg_audit_tarea_sla_contexto,private.log_audit_crm,AFTER,ROW,I|D|U,O,false
crm.tarea_sla_contexto,trg_sla_nucleo_guard,private.trg_sla_nucleo_entrada_guard,BEFORE,ROW,I|D|U,O,false
crm.tarea_sla_contexto,trg_sla_nucleo_no_truncate,private.trg_sla_nucleo_entrada_guard,BEFORE,STMT,T,O,false
crm.tareas,trg_audit_tareas,private.log_audit_crm,AFTER,ROW,I|D|U,O,false
private.llamadas_celular_intenciones,trg_llamadas_celular_intenciones_00_candado,private.trg_llamadas_celular_intenciones_candado,BEFORE,ROW,D|U,O,false
private.llamadas_celular_intenciones,trg_llamadas_celular_intenciones_00_sin_vaciar,private.trg_llamadas_celular_sin_vaciar,BEFORE,STMT,T,O,false

### Candados de llamadas del celular (NO se modifican; aceptan cascada)
```sql
CREATE OR REPLACE FUNCTION private.trg_llamadas_celular_eventos_candado()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'DELETE' then
    -- Solo la purga programada (GUC de transacción) o una cascada (el lead se elimina: la
    -- evidencia de su número se va con él) pueden borrar. Un DELETE directo muere aquí.
    if coalesce(pg_catalog.current_setting('crm.op_purga_llamadas', true), 'off') = 'on'
       or pg_catalog.pg_trigger_depth() > 1 then
      return old;
    end if;
    raise exception using errcode = '42501',
      message = 'Una llamada del celular no se borra a mano: la retira la retención programada';
  end if;

  -- El payload es la evidencia: inmutable aunque lo escriba el núcleo.
  if new.id <> old.id or new.asignacion_id <> old.asignacion_id or new.analista_id <> old.analista_id
-- …
CREATE OR REPLACE FUNCTION private.trg_llamadas_celular_enlaces_candado()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_act crm.actividades%rowtype;
  v_ev  crm.llamadas_celular_eventos%rowtype;
  v_deshecha boolean;
begin
  if tg_op = 'DELETE' then
    if pg_catalog.pg_trigger_depth() > 1 then
      return old; -- cascada: se fue el evento o el lead
    end if;
    raise exception using errcode = '42501', message = 'El enlace de una llamada no se borra';
  end if;

  if tg_op = 'UPDATE' then
    -- La actividad se eliminó (cascada del lead → ON DELETE SET NULL): única escritura anidada
    -- aceptada, y solo si no cambia nada más.
    if pg_catalog.pg_trigger_depth() > 1 and new.actividad_id is null and old.actividad_id is not null
       and (pg_catalog.to_jsonb(new) - 'actividad_id' - 'actualizado_en')
         = (pg_catalog.to_jsonb(old) - 'actividad_id' - 'actualizado_en') then
      new.actualizado_en := pg_catalog.now();
      return new;
    end if;
    if new.id <> old.id or new.evento_id <> old.evento_id or new.lead_id <> old.lead_id
       or new.creado_en <> old.creado_en or new.via <> old.via then
      raise exception using errcode = '42501', message = 'El enlace de una llamada no cambia de evento, de lead ni de vía';
-- …
CREATE OR REPLACE FUNCTION private.trg_llamadas_celular_intenciones_candado()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_deshecha boolean;
begin
  if tg_op = 'DELETE' then
    -- La cumple la ingesta (GUC de enlace), la retira la purga (su GUC) o se va con su lead o su resultado (cascada).
    if coalesce(pg_catalog.current_setting('crm.op_enlace_llamadas', true), 'off') = 'on'
       or coalesce(pg_catalog.current_setting('crm.op_purga_llamadas', true), 'off') = 'on'
       or pg_catalog.pg_trigger_depth() > 1 then
      return old;
    end if;
    raise exception using errcode = '42501', message = 'Una intención de enlace no se borra a mano';
  end if;
  if new.id <> old.id or new.evento_origen_id <> old.evento_origen_id or new.analista_id <> old.analista_id
     or new.lead_id <> old.lead_id or new.via <> old.via or new.creado_en <> old.creado_en then
-- …
```

### Funciones que la puerta llama sin tocar
```sql
CREATE OR REPLACE FUNCTION private.eliminar_inversion_roles(p_actor uuid) RETURNS jsonb LANGUAGE plpgsql SET search_path TO '' AS $function$ declare v_portal text; begin select p.rol into v_portal from public.perfiles p where p.id = p_actor and p.activo for share; perform 1 from crm.equipo e where e.perfil_id = p_actor order by e.perfil_id for share; return jsonb_build_object('portal', case when v_portal in ('admin','superadmin') then v_portal end, 'gerencia', coalesce(private.rol_crm(p_actor) = 'gerencia', false)); end $function$
-- crm.cerrar_periodo toma: pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);
-- crm.periodos_cerrados hoy: solo 2026-08. Roles: postgres rolbypassrls=true, no superuser. private.rol_crm ACL {postgres=X,authenticated=X}, DEFINER.
-- private.log_audit_crm / log_audit_sin_secretos: AFTER ROW, escriben en public.audit_log (to_jsonb old/new).
```

### Caso real (lead de667c0d, origen oficina, creado 12/10, etapa nuevo): filas hijas
tareas 1, tarea_sla_contexto 1, lead_asignaciones 1 (no convertido), hitos 1, sla_ciclos 1, sla_etapas 1; resto 0. Sin contrato/perfil/inversionista.
Global: 3.687 leads; 2.901 con sla_operacion_recibos; 290 con lead_potencial_eventos; 0 con busquedas/base_carga.

## Migración propuesta (completa)
```sql
-- 20261015044917_crm_eliminar_lead_error_carga.sql
--
-- «Eliminar lead (error de carga)»: vía oficial para que gerencia (rol CRM) o un admin/superadmin del portal borre un
-- lead cargado por error, con todo lo que cuelga de él, dejando ANTES una copia completa e inmutable.
-- Pedido de Miguel (14/10/2026). Caso real: lead de667c0d (MARGARITA, origen oficina): hoy no se puede borrar porque los
-- candados del SLA y del ledger prohíben SIEMPRE el DELETE, y el origen no se cambia después del alta (P0409).
--
-- LOS CANDADOS NO SE QUITAN NI SE DEBILITAN. Cada uno gana UNA excepción, la misma en los 8 y solo para DELETE: la fila
-- tiene que estar ya copiada, idéntica, en crm.leads_eliminados, en ESTA transacción, por ESTE actor (auth.uid()), y el
-- permiso de transacción crm.borrado_lead_error tiene que nombrar a ESE lead. Una sola definición de la regla:
-- private.borrado_lead_error_autoriza. Sin la puerta, un DELETE directo muere igual que hoy. Nada de
-- ALTER TABLE … DISABLE TRIGGER. INSERT, UPDATE y TRUNCATE no cambian. Mismo patrón que «Eliminar inversión»
-- (20261005200945, private.inversion_eliminacion_autoriza).
--
-- QUÉ HACE
--   1. crm.leads_eliminados: copia inmutable (UPDATE, DELETE y TRUNCATE prohibidos para todos). RLS: solo SELECT, y solo
--      gerencia del CRM. Nadie la escribe salvo la puerta.
--   2. private.borrado_lead_error_autoriza(tabla, fila): la llave de los candados.
--   3. Los 8 candados que custodian filas del lead. Cuerpo de producción + 5 líneas al empezar; el postflight prueba que
--      el resto quedó idéntico byte a byte:
--        private.trg_sla_nucleo_entrada_guard             (tarea_sla_contexto, lead_sla_etapa_ajustes)
--        private.trg_lead_asignacion_sla_hitos_guard      (lead_asignacion_sla_hitos)
--        private.trg_lead_sla_etapas_guard                (lead_sla_etapas)
--        private.trg_lead_sla_ciclos_guard                (lead_sla_ciclos)
--        private.trg_lead_asignaciones_inmutables         (lead_asignaciones)
--        private.trg_sla_recibo_guard                     (sla_operacion_recibos: 2.901 de 3.687 leads tienen recibos)
--        private.potencial_evento_inmutable               (lead_potencial_eventos: 290 leads)
--        private.trg_actividades_no_contactar_solo_puerta (solo si el lead tiene una nota de «No contactar»)
--      Las llamadas del celular NO se tocan: sus candados ya aceptan la cascada del lead («la evidencia de su número se
--      va con él»).
--   4. Puerta crm.eliminar_lead_error_carga(p_lead_id, p_motivo) → jsonb. DEFINER. Justificación: las tablas del SLA y
--      del ledger no tienen DELETE para nadie; el actor y su rol se resuelven SIEMPRE en el servidor con auth.uid().
--        · Rol: gerencia del CRM o admin/superadmin del portal, con private.eliminar_inversion_roles (la misma de
--          «Eliminar inversión»: bloquea perfil y membresía FOR SHARE). Otro → 42501.
--        · Motivo de 10 a 500 caracteres (private.motivo_normalizado) → 22023.
--        · Solo si el lead: no tiene contrato, perfil ni inversionista; no tiene conversión (convertido_en,
--          lead_asignaciones.resultado = 'convertido', acreditación, reserva, cierre externo, cierre anulado, ajuste de mes
--          cerrado); no tiene historia de inversión (solicitud de tasa, solicitud de inversión de origen, cartera de
--          inversionistas, búsqueda de cliente existente, gestión de inversionista en sus tareas); se creó hace
--          30 días o menos; y ningún mes desde su alta está cerrado (crm.periodos_cerrados, bajo el mismo candado
--          que crm.cerrar_periodo). Si algo falla → P0409 con TODAS las razones en el mensaje.
--        · Fail-closed ante tablas nuevas: si aparece una llave foránea hacia el lead o sus filas que esta puerta no
--          conoce → 55000 (no se borra nada sin copia).
--        · Copia → borra en orden → comprueba que no quedó nada.
--
-- LLAVES FORÁNEAS HACIA crm.leads (catálogo de producción del 14/10/2026, recorrido recursivo; no asumidas):
--   se BORRAN, con copia: tarea_sla_contexto, lead_asignacion_sla_hitos, lead_sla_etapa_ajustes, actividades_cliente (de
--     sus tareas), tareas, sla_operacion_recibos, lead_potencial_eventos, lead_potencial, base_carga_leads, actividades,
--     lead_sla_etapas, lead_sla_ciclos, lead_asignaciones, leads; y por cascada del lead o de la actividad:
--     llamadas_celular_eventos, llamadas_celular_enlaces, private.llamadas_celular_intenciones.
--   RECHAZAN, porque son historia de negocio: conversion_acreditaciones, conversion_reservas, cierres_externos,
--     cierres_avance_anulados, ajustes_mes_cerrado, solicitudes_tasa, inversion_solicitudes, inversionista_leads,
--     inversionista_operaciones, busquedas_cliente_existente, inversionista_gestiones.
--
-- CAPAS: puerta (crm) → núcleo (private) → tablas. CENSO ANALÍTICO: la puerta no usa count( (los conteos salen de
-- jsonb_array_length sobre la copia). negocio_id: como las demás tablas crm (un solo negocio), no lo lleva.
-- NO toca objetos de public. Aplicar en UN mensaje (`supabase db query --linked --file`).
-- REVERSA: supabase/scripts/eliminar-lead-error-carga/reversa.sql (restaura los 8 candados con su huella de hoy y retira
-- la puerta; la tabla de copias se conserva si tiene filas).
-- PRUEBAS: supabase/scripts/eliminar-lead-error-carga/test-eliminar-lead.sql (banco Docker, ROLLBACK).

-- Exclusión de migraciones ANTES de la instantánea: candado de SESIÓN en su propia transacción.
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
    raise exception 'PREFLIGHT eliminar_lead_error_carga: esta sesión no tiene el candado de migraciones';
  end if;
  -- Lo que se reemplaza: los 8 candados, tal como están en producción el 14/10/2026.
  if (
      md5(pg_catalog.pg_get_functiondef('private.trg_sla_nucleo_entrada_guard()'::regprocedure)) = '3d052e4dc970d0b2b23a81cb73d6c60f'
      and md5(pg_catalog.pg_get_functiondef('private.trg_lead_asignacion_sla_hitos_guard()'::regprocedure)) = '2e2971b4325c7aad4253387dad301400'
      and md5(pg_catalog.pg_get_functiondef('private.trg_lead_asignaciones_inmutables()'::regprocedure)) = 'ab7507ef09420c7f8445a4d563a3566f'
      and md5(pg_catalog.pg_get_functiondef('private.trg_lead_sla_ciclos_guard()'::regprocedure)) = '04ce52eeb57ea8fde1fa71f9d021e025'
      and md5(pg_catalog.pg_get_functiondef('private.trg_lead_sla_etapas_guard()'::regprocedure)) = 'bdc42cc17888cffea22aaf63162344fe'
      and md5(pg_catalog.pg_get_functiondef('private.trg_sla_recibo_guard()'::regprocedure)) = '903e9260918bc7e100bde650d46c1ee4'
      and md5(pg_catalog.pg_get_functiondef('private.potencial_evento_inmutable()'::regprocedure)) = 'a9eed979747620bb83d8670a2ffcf869'
      and md5(pg_catalog.pg_get_functiondef('private.trg_actividades_no_contactar_solo_puerta()'::regprocedure)) = '30015d7ddda774c110082de47b5b3056'
  ) is not true then
    raise exception 'PREFLIGHT eliminar_lead_error_carga: cambió uno de los candados que se reemplazan';
  end if;
  -- Lo que se llama sin tocar.
  if (md5(pg_catalog.pg_get_functiondef('private.eliminar_inversion_roles(uuid)'::regprocedure)) = 'e9a2341105e4028565f81164d5e02c4c'
      and md5(pg_catalog.pg_get_functiondef('private.motivo_normalizado(text)'::regprocedure)) = '08602d4022e0731952cbf61c28efe9d7'
      and md5(pg_catalog.pg_get_functiondef('private.rol_crm(uuid)'::regprocedure)) = '99827f3fe2fbc3cfae5668c30015c758'
      and md5(pg_catalog.pg_get_functiondef('private.log_audit_sin_secretos()'::regprocedure)) = 'ae7225bc9e86131813ac0328fff4c3ae') is not true then
    raise exception 'PREFLIGHT eliminar_lead_error_carga: cambió una función que la puerta usa';
  end if;
  if to_regclass('crm.leads_eliminados') is not null
     or to_regprocedure('crm.eliminar_lead_error_carga(uuid,text)') is not null
     or to_regprocedure('private.borrado_lead_error_autoriza(text,jsonb)') is not null
     or to_regprocedure('private.proteger_lead_eliminado()') is not null then
    raise exception 'PREFLIGHT eliminar_lead_error_carga: los objetos nuevos ya existen';
  end if;
  if (select count(*) from pg_catalog.pg_trigger t
      where t.tgenabled = 'O' and t.tgfoid in ('private.trg_sla_nucleo_entrada_guard()'::regprocedure, 'private.trg_lead_asignacion_sla_hitos_guard()'::regprocedure, 'private.trg_lead_asignaciones_inmutables()'::regprocedure, 'private.trg_lead_sla_ciclos_guard()'::regprocedure, 'private.trg_lead_sla_etapas_guard()'::regprocedure, 'private.trg_sla_recibo_guard()'::regprocedure, 'private.potencial_evento_inmutable()'::regprocedure, 'private.trg_actividades_no_contactar_solo_puerta()'::regprocedure)) <> 17 then
    raise exception 'PREFLIGHT eliminar_lead_error_carga: los triggers de los candados no están en su modo normal';
  end if;
end
$preflight$;

-- ── 1 · Tabla de copias ────────────────────────────────────────────────────────────────────────────────────────────────
create table crm.leads_eliminados (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null unique,
  motivo text not null check (motivo = private.motivo_normalizado(motivo) and char_length(motivo) between 10 and 500),
  eliminado_por uuid not null,
  rol_actor text not null check (rol_actor in ('gerencia', 'admin', 'superadmin')),
  eliminado_en timestamptz not null default statement_timestamp(),
  copia jsonb not null check (jsonb_typeof(copia) = 'object' and jsonb_typeof(copia -> 'lead') = 'object'),
  filas jsonb not null check (jsonb_typeof(filas) = 'object'),
  transaccion xid8 not null default pg_current_xact_id()
);
alter table crm.leads_eliminados enable row level security;

create function private.proteger_lead_eliminado()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception 'La copia de un lead eliminado es inmutable' using errcode = '42501';
end $$;

create trigger trg_audit_leads_eliminados after insert or update or delete on crm.leads_eliminados
  for each row execute function private.log_audit_sin_secretos('copia');
create trigger trg_leads_eliminados_inmutables before update or delete on crm.leads_eliminados
  for each row execute function private.proteger_lead_eliminado();
create trigger trg_leads_eliminados_no_truncate before truncate on crm.leads_eliminados
  for each statement execute function private.proteger_lead_eliminado();

create policy leads_eliminados_select_gerencia on crm.leads_eliminados
  for select to authenticated
  using ((select private.rol_crm((select auth.uid()))) = 'gerencia');

-- ── 2 · Núcleo: la llave única de los 8 candados ───────────────────────────────────────────────────────────────────────
create function private.borrado_lead_error_autoriza(p_tabla text, p_fila jsonb)
returns boolean language sql stable set search_path = '' as $$
  select coalesce(pg_catalog.current_setting('crm.borrado_lead_error', true), '') <> ''
    and (select auth.uid()) is not null
    and exists (
      select 1 from crm.leads_eliminados e
      where e.lead_id::text = pg_catalog.current_setting('crm.borrado_lead_error', true)
        and e.transaccion = pg_catalog.pg_current_xact_id_if_assigned()
        and e.eliminado_por = (select auth.uid())
        and jsonb_typeof(e.copia -> p_tabla) = 'array'
        and e.copia -> p_tabla @> pg_catalog.jsonb_build_array(p_fila))
$$;

-- ── 3 · Los 8 candados: idénticos a producción salvo las 5 líneas del DELETE ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION private.trg_sla_nucleo_entrada_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_lead uuid;v_evento crm.actividades%rowtype;v_etapa crm.lead_sla_etapas%rowtype;
  v_regla crm.sla_politica_etapas_operacion%rowtype;v_hechos record;v_control crm.sla_operacion_control%rowtype;v_decision record;
begin
  if tg_op = 'DELETE' then
    -- Única excepción: la vía oficial crm.eliminar_lead_error_carga, y solo para una fila ya copiada en
    -- crm.leads_eliminados en ESTA transacción (ver private.borrado_lead_error_autoriza).
    if private.borrado_lead_error_autoriza(tg_table_name, pg_catalog.to_jsonb(old)) then return old; end if;
  end if;
  if tg_op in ('DELETE','TRUNCATE') then raise exception 'Los hechos SLA no se borran' using errcode='55000';end if;
  if current_user::regrole::oid<>(select relowner from pg_class where oid=tg_relid) then
    raise exception 'Solo el nucleo escribe entradas SLA' using errcode='42501';end if;
  if tg_table_name='sla_operacion_control' then
    if tg_op<>'UPDATE' or current_setting('crm.sla_control_writer',true) is distinct from 'on' then
      raise exception 'El modo solo cambia por su comando' using errcode='55000';end if;
    if (old.primera_activacion_en is not null and
       (new.primera_activacion_en is distinct from old.primera_activacion_en
        or new.politica_adopcion_id is distinct from old.politica_adopcion_id))
      or new.revision<>old.revision+1 then
      raise exception 'Adopcion inmutable o revision invalida' using errcode='55000';end if;
    if new.politica_adopcion_id is not null and not private.sla_reglas_operacion_validas(
      (select jsonb_agg(to_jsonb(r)-'politica_id') from crm.sla_politica_etapas_operacion r where r.politica_id=new.politica_adopcion_id)) then
      raise exception 'La adopcion requiere cuatro reglas completas' using errcode='23514';end if;
  elsif tg_op='UPDATE' then
    raise exception 'Entrada SLA inmutable' using errcode='55000';
  elsif tg_table_name='sla_politica_etapas_operacion' then
    if current_setting('crm.sla_config_writer',true) is distinct from 'on'
      or exists(select 1 from crm.lead_sla_etapas e where e.politica_id=new.politica_id) then
      raise exception 'Reglas solo durante publicacion, nunca sobre episodios existentes' using errcode='55000';end if;
  elsif tg_table_name='tarea_sla_contexto' then
    if ((new.fuente='evento' and pg_trigger_depth()>=2
               and current_setting('crm.sla_contexto_writer',true)='evento')
         or (new.fuente='reconstruido' and current_setting('crm.sla_contexto_writer',true)='reconstruido')) is distinct from true then
      raise exception 'Contexto solo por captura o reconstruccion privada' using errcode='55000';end if;
    select lead_id into v_lead from crm.tareas where id=new.tarea_id;
    if v_lead is distinct from new.lead_id then
      raise exception 'Contexto ajeno a tarea' using errcode='23514';end if;
  elsif tg_table_name='lead_sla_etapa_ajustes' then
    if (pg_trigger_depth()<2 and current_setting('crm.sla_finalizando_gesto',true) is distinct from 'on')
      or current_setting('crm.sla_ajuste_writer',true) is distinct from 'on' then
      raise exception 'Ajuste solo desde evento de gestion' using errcode='55000';end if;
    select * into strict v_evento from crm.actividades where id=new.origen_actividad_id;
    select * into strict v_etapa from crm.lead_sla_etapas where id=new.etapa_sla_id;
    select * into strict v_regla from crm.sla_politica_etapas_operacion
      where politica_id=v_etapa.politica_id and etapa=v_etapa.etapa;
    select * into strict v_control from crm.sla_operacion_control where id;
    select * into strict v_hechos from private.sla_etapa_hechos(v_etapa.id,v_etapa.lead_id,v_etapa.ciclo_n,v_etapa.etapa);
    select * into strict v_decision from private.sla_evaluar_prorroga(v_etapa.etapa,v_evento.tipo,v_evento.creado_por,
      v_etapa.finalizado_en is null,v_control.modo,v_control.primera_activacion_en,v_evento.creado_en,
      v_etapa.limite_en+v_hechos.minutos*interval '1 minute',v_etapa.limite_en+v_regla.tope_extra_minutos*interval '1 minute',
      v_regla.prorroga_minutos,v_regla.prorroga_max,v_hechos.usadas,false);
    if v_evento.lead_id<>v_etapa.lead_id or v_evento.creado_por is distinct from new.creado_por
      or auth.uid() is distinct from new.creado_por or not v_decision.elegible
      or new.secuencia<>v_hechos.usadas+1 or new.minutos_reales<>v_decision.minutos_reales
      or new.limite_antes<>v_etapa.limite_en+v_hechos.minutos*interval '1 minute'
      or new.limite_despues<>v_decision.limite_despues then
      raise exception 'Ajuste fuera de causa, secuencia o presupuesto' using errcode='23514';end if;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.trg_lead_asignacion_sla_hitos_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_asignado_en timestamptz;
  v_finalizado_en timestamptz;
begin
  if tg_op = 'DELETE' then
    -- Única excepción: la vía oficial crm.eliminar_lead_error_carga, y solo para una fila ya copiada en
    -- crm.leads_eliminados en ESTA transacción (ver private.borrado_lead_error_autoriza).
    if private.borrado_lead_error_autoriza(tg_table_name, pg_catalog.to_jsonb(old)) then return old; end if;
  end if;
  if tg_op='DELETE' then
    raise exception 'Los hitos SLA de asignacion no se eliminan' using errcode='55000';
  end if;
  if coalesce(current_setting('crm.sla_writer',true),'off')<>'on'
    or pg_trigger_depth()<2 then
    raise exception 'Los hitos SLA solo se sellan desde eventos CRM' using errcode='42501';
  end if;
  select a.asignado_en,a.finalizado_en into v_asignado_en,v_finalizado_en
  from crm.lead_asignaciones a where a.id=new.lead_asignacion_id;
  if not found then raise exception 'Asignacion SLA inexistente' using errcode='23503'; end if;
  if tg_op='UPDATE' and (
    old.id is distinct from new.id
    or old.lead_asignacion_id is distinct from new.lead_asignacion_id
    or old.creado_en is distinct from new.creado_en
    or (old.primera_gestion_en is not null
      and old.primera_gestion_en is distinct from new.primera_gestion_en)
    or (old.primer_contacto_en is not null
      and old.primer_contacto_en is distinct from new.primer_contacto_en)
  ) then
    raise exception 'Los hitos SLA de asignacion son inmutables' using errcode='55000';
  end if;
  if (new.primera_gestion_en is not null and (
      new.primera_gestion_en<v_asignado_en
      or (v_finalizado_en is not null and new.primera_gestion_en>v_finalizado_en)
    )) or (new.primer_contacto_en is not null and (
      new.primera_gestion_en is null
      or new.primer_contacto_en<new.primera_gestion_en
      or (v_finalizado_en is not null and new.primer_contacto_en>v_finalizado_en)
    )) then
    raise exception 'Hito SLA fuera del episodio de asignacion' using errcode='23514';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.trg_lead_asignaciones_inmutables()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if tg_op = 'DELETE' then
    -- Única excepción: la vía oficial crm.eliminar_lead_error_carga, y solo para una fila ya copiada en
    -- crm.leads_eliminados en ESTA transacción (ver private.borrado_lead_error_autoriza).
    if private.borrado_lead_error_autoriza(tg_table_name, pg_catalog.to_jsonb(old)) then return old; end if;
  end if;
  if tg_op = 'DELETE' then
    raise exception 'Los episodios de asignacion no se eliminan';
  end if;

  if coalesce(current_setting('crm.ledger_writer', true), 'off') <> 'on'
     or pg_trigger_depth() < 2 then
    raise exception 'El ledger solo se escribe desde el movimiento del lead';
  end if;

  if tg_op = 'INSERT' then
    return new;
  end if;

  if old.finalizado_en is not null then
    raise exception 'Un episodio cerrado es inmutable';
  end if;

  if old.id is distinct from new.id
     or old.lead_id is distinct from new.lead_id
     or old.ciclo_n is distinct from new.ciclo_n
     or old.episodio_n is distinct from new.episodio_n
     or old.analista_id is distinct from new.analista_id
     or old.motivo_apertura is distinct from new.motivo_apertura
     or old.asignado_en is distinct from new.asignado_en
     or old.asignado_por is distinct from new.asignado_por
     or old.supervisor_origen_id is distinct from new.supervisor_origen_id
     or old.monto_estimado is distinct from new.monto_estimado
     or old.moneda is distinct from new.moneda
     or old.origen is distinct from new.origen
     or old.categoria_interes is distinct from new.categoria_interes
     or old.aproximado is distinct from new.aproximado
     or old.creado_en is distinct from new.creado_en then
    raise exception 'La fotografia de un episodio es inmutable';
  end if;

  if new.finalizado_en is null or new.motivo_cierre is null then
    raise exception 'La unica actualizacion valida del ledger es su cierre completo';
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.trg_lead_sla_ciclos_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if tg_op = 'DELETE' then
    -- Única excepción: la vía oficial crm.eliminar_lead_error_carga, y solo para una fila ya copiada en
    -- crm.leads_eliminados en ESTA transacción (ver private.borrado_lead_error_autoriza).
    if private.borrado_lead_error_autoriza(tg_table_name, pg_catalog.to_jsonb(old)) then return old; end if;
  end if;
  if tg_op='DELETE' then raise exception 'Los ciclos SLA no se eliminan' using errcode='55000'; end if;
  if coalesce(current_setting('crm.sla_writer',true),'off')<>'on' or pg_trigger_depth()<2 then
    raise exception 'Los ciclos SLA solo se escriben desde eventos CRM' using errcode='42501';
  end if;
  if tg_op='INSERT' then return new; end if;
  if old.id is distinct from new.id or old.lead_id is distinct from new.lead_id
    or old.ciclo_n is distinct from new.ciclo_n or old.politica_id is distinct from new.politica_id
    or old.iniciado_en is distinct from new.iniciado_en
    or old.primera_gestion_limite_en is distinct from new.primera_gestion_limite_en
    or old.primer_contacto_limite_en is distinct from new.primer_contacto_limite_en
    or old.aproximado is distinct from new.aproximado or old.creado_en is distinct from new.creado_en
    or (old.primera_gestion_en is not null and old.primera_gestion_en is distinct from new.primera_gestion_en)
    or (old.primer_contacto_en is not null and old.primer_contacto_en is distinct from new.primer_contacto_en) then
    raise exception 'Snapshot/eventos SLA inmutables' using errcode='55000';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.trg_lead_sla_etapas_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if tg_op = 'DELETE' then
    -- Única excepción: la vía oficial crm.eliminar_lead_error_carga, y solo para una fila ya copiada en
    -- crm.leads_eliminados en ESTA transacción (ver private.borrado_lead_error_autoriza).
    if private.borrado_lead_error_autoriza(tg_table_name, pg_catalog.to_jsonb(old)) then return old; end if;
  end if;
  if tg_op='DELETE' then raise exception 'Las etapas SLA no se eliminan' using errcode='55000'; end if;
  if coalesce(current_setting('crm.sla_writer',true),'off')<>'on' or pg_trigger_depth()<2 then
    raise exception 'Las etapas SLA solo se escriben desde crm.leads' using errcode='42501';
  end if;
  if tg_op='INSERT' then return new; end if;
  if old.finalizado_en is not null or new.finalizado_en is null or new.motivo_cierre is null
    or old.id is distinct from new.id or old.lead_id is distinct from new.lead_id
    or old.ciclo_n is distinct from new.ciclo_n or old.episodio_n is distinct from new.episodio_n
    or old.etapa is distinct from new.etapa or old.politica_id is distinct from new.politica_id
    or old.iniciado_en is distinct from new.iniciado_en or old.limite_en is distinct from new.limite_en
    or old.aproximado is distinct from new.aproximado or old.creado_en is distinct from new.creado_en then
    raise exception 'Solo se permite cerrar una etapa SLA abierta' using errcode='55000';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.trg_sla_recibo_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'DELETE' then
    -- Única excepción: la vía oficial crm.eliminar_lead_error_carga, y solo para una fila ya copiada en
    -- crm.leads_eliminados en ESTA transacción (ver private.borrado_lead_error_autoriza).
    if private.borrado_lead_error_autoriza(tg_table_name, pg_catalog.to_jsonb(old)) then return old; end if;
  end if;
  if tg_op in ('DELETE','TRUNCATE') then
    raise exception 'Los recibos de gestion no se borran' using errcode='55000';
  end if;
  if tg_op='UPDATE' and (old.respuesta is not null or new.respuesta is null
      or (to_jsonb(new)-'respuesta'-'confirmado_en') is distinct from
         (to_jsonb(old)-'respuesta'-'confirmado_en')) then
    raise exception 'El recibo solo puede confirmarse una vez' using errcode='55000';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.potencial_evento_inmutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'DELETE' then
    -- Única excepción: la vía oficial crm.eliminar_lead_error_carga, y solo para una fila ya copiada en
    -- crm.leads_eliminados en ESTA transacción (ver private.borrado_lead_error_autoriza).
    if private.borrado_lead_error_autoriza(tg_table_name, pg_catalog.to_jsonb(old)) then return old; end if;
  end if;
  raise exception 'El historial de potencial no se modifica ni se borra' using errcode = 'P0409';
end;
$function$;

CREATE OR REPLACE FUNCTION private.trg_actividades_no_contactar_solo_puerta()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_exento boolean := false;
  v_veto boolean := false;
begin
  if tg_op = 'DELETE' then
    -- Única excepción: la vía oficial crm.eliminar_lead_error_carga, y solo para una fila ya copiada en
    -- crm.leads_eliminados en ESTA transacción (ver private.borrado_lead_error_autoriza).
    if private.borrado_lead_error_autoriza(tg_table_name, pg_catalog.to_jsonb(old)) then return old; end if;
  end if;
  -- B6c: la nota del veto (metadata evento = no_contactar) es la fuente de la marca que la base para gestión muestra a
  -- Supervisión y Gerencia (cuándo, motivo, quién). Solo la escriben sus puertas, bajo la válvula de transacción
  -- crm.op_privilegiada = on (marcar_no_contactar, levantar_no_contactar y postventa_veto_fn), y no se cambia ni se borra.
  if (select auth.uid()) is null then
    v_exento := true;  -- sin usuario (migraciones, backfills, service_role sin sub), como los otros sellos de crm.actividades
  elsif coalesce(pg_catalog.current_setting('crm.op_privilegiada', true), 'off') = 'on' then
    v_exento := true;  -- la válvula de las puertas del veto
  end if;
  if not v_exento then
    if tg_op <> 'DELETE' then
      v_veto := pg_catalog.lower(pg_catalog.btrim(coalesce(new.metadata->>'evento', ''), E' \t\r\n')) = 'no_contactar';
    end if;
    if tg_op <> 'INSERT' and not v_veto then
      v_veto := pg_catalog.lower(pg_catalog.btrim(coalesce(old.metadata->>'evento', ''), E' \t\r\n')) = 'no_contactar';
    end if;
    if v_veto then
      raise exception 'La nota de No contactar solo la escriben sus puertas (marcar, levantar o postventa); no se cambia ni se borra'
        using errcode = '42501';
    end if;
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$function$;

-- ── 4 · Puerta ─────────────────────────────────────────────────────────────────────────────────────────────────────────
create function crm.eliminar_lead_error_carga(p_lead_id uuid, p_motivo text)
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
  v_no text[] := '{}';
  v_meses text;
  v_nuevas text;
  v_copia jsonb;
  v_filas jsonb;
  v_id uuid;
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

  -- Fail-closed: toda llave foránea hacia el lead o hacia lo que se borra tiene que estar en esta lista (catálogo de
  -- producción, 14/10/2026). Una tabla nueva enlazada se revisa antes de poder borrar: sin copia no se borra nada.
  select pg_catalog.string_agg(distinct c.conrelid::regclass::text || ' → ' || c.confrelid::regclass::text, ', ')
    into v_nuevas
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
    and (c.conrelid::regclass::text, c.confrelid::regclass::text) not in (
      ('crm.actividades', 'crm.leads'), ('crm.ajustes_mes_cerrado', 'crm.leads'), ('crm.base_carga_leads', 'crm.leads'),
      ('crm.busquedas_cliente_existente', 'crm.leads'), ('crm.cierres_avance_anulados', 'crm.leads'),
      ('crm.cierres_externos', 'crm.leads'), ('crm.conversion_acreditaciones', 'crm.leads'),
      ('crm.conversion_reservas', 'crm.leads'), ('crm.inversion_solicitudes', 'crm.leads'),
      ('crm.inversionista_leads', 'crm.leads'), ('crm.inversionista_operaciones', 'crm.leads'),
      ('crm.lead_asignaciones', 'crm.leads'), ('crm.lead_potencial_eventos', 'crm.leads'),
      ('crm.lead_potencial', 'crm.leads'), ('crm.lead_sla_ciclos', 'crm.leads'), ('crm.lead_sla_etapas', 'crm.leads'),
      ('crm.llamadas_celular_enlaces', 'crm.leads'), ('crm.llamadas_celular_eventos', 'crm.leads'),
      ('private.llamadas_celular_intenciones', 'crm.leads'), ('crm.sla_operacion_recibos', 'crm.leads'),
      ('crm.solicitudes_tasa', 'crm.leads'), ('crm.tareas', 'crm.leads'),
      ('crm.actividades_cliente', 'crm.tareas'), ('crm.inversionista_gestiones', 'crm.tareas'),
      ('crm.tarea_sla_contexto', 'crm.tareas'), ('crm.tareas', 'crm.tareas'),
      ('crm.lead_sla_etapa_ajustes', 'crm.actividades'), ('crm.llamadas_celular_enlaces', 'crm.actividades'),
      ('private.llamadas_celular_intenciones', 'crm.actividades'), ('crm.tareas', 'crm.actividades'),
      ('crm.conversion_acreditaciones', 'crm.lead_asignaciones'), ('crm.lead_asignacion_sla_hitos', 'crm.lead_asignaciones'),
      ('crm.lead_sla_etapas', 'crm.lead_sla_ciclos'), ('crm.tarea_sla_contexto', 'crm.lead_sla_ciclos'),
      ('crm.lead_sla_etapa_ajustes', 'crm.lead_sla_etapas'),
      ('crm.llamadas_celular_enlaces', 'crm.llamadas_celular_eventos'));
  if v_nuevas is not null then
    raise exception 'Hay tablas nuevas enlazadas al lead que esta eliminación no conoce (%); hay que revisarla antes', v_nuevas
      using errcode = '55000';
  end if;

  -- El lead primero (bloquea también toda fila nueva que quiera colgarse de él: su FK necesita KEY SHARE).
  select * into v_lead from crm.leads l where l.id = p_lead_id for update;
  if not found then
    raise exception 'El lead no existe o ya fue eliminado' using errcode = 'P0002';
  end if;

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
  if v_lead.creado_en < pg_catalog.now() - pg_catalog.make_interval(days => c_dias_max) then
    v_no := v_no || pg_catalog.format('se creó hace más de %s días (%s)', c_dias_max,
                      pg_catalog.to_char(v_lead.creado_en at time zone 'America/Lima', 'DD/MM/YYYY'));
  end if;
  -- Mes cerrado: mismo candado que crm.cerrar_periodo, para que nadie selle un mes entre esta lectura y el borrado.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);
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

  insert into crm.leads_eliminados (lead_id, motivo, eliminado_por, rol_actor, copia, filas)
  values (p_lead_id, v_motivo, v_uid, v_rol, v_copia, v_filas)
  returning id into v_id;

  -- Permiso de borrado de ESTE lead, solo en esta transacción; los candados exigen además la fila en la copia.
  perform pg_catalog.set_config('crm.borrado_lead_error', p_lead_id::text, true);

  -- Orden por llaves foráneas (RESTRICT/NO ACTION primero; las tareas antes que las actividades para que su
  -- ON DELETE SET NULL no reescriba tareas que también se van).
  delete from crm.tarea_sla_contexto x where x.lead_id = p_lead_id;
  delete from crm.lead_asignacion_sla_hitos x
  where x.lead_asignacion_id in (select a.id from crm.lead_asignaciones a where a.lead_id = p_lead_id);
  delete from crm.lead_sla_etapa_ajustes x
  where x.etapa_sla_id in (select e.id from crm.lead_sla_etapas e where e.lead_id = p_lead_id);
  delete from crm.actividades_cliente x where x.tarea_id in (select t.id from crm.tareas t where t.lead_id = p_lead_id);
  delete from crm.tareas x where x.lead_id = p_lead_id;
  delete from crm.sla_operacion_recibos x where x.lead_id = p_lead_id;
  delete from crm.lead_potencial_eventos x where x.lead_id = p_lead_id;
  delete from crm.lead_potencial x where x.lead_id = p_lead_id;
  delete from crm.base_carga_leads x where x.lead_id = p_lead_id;
  delete from crm.actividades x where x.lead_id = p_lead_id;   -- cascada: intenciones; los enlaces quedan sin actividad
  delete from crm.lead_sla_etapas x where x.lead_id = p_lead_id;
  delete from crm.lead_sla_ciclos x where x.lead_id = p_lead_id;
  delete from crm.lead_asignaciones x where x.lead_id = p_lead_id;
  delete from crm.leads x where x.id = p_lead_id;               -- cascada: llamadas del celular (sus candados la aceptan)

  perform pg_catalog.set_config('crm.borrado_lead_error', coalesce(v_previa, ''), true);

  if exists (select 1 from crm.leads x where x.id = p_lead_id)
     or exists (select 1 from crm.lead_asignaciones x where x.lead_id = p_lead_id)
     or exists (select 1 from crm.lead_sla_ciclos x where x.lead_id = p_lead_id)
     or exists (select 1 from crm.tareas x where x.lead_id = p_lead_id)
     or exists (select 1 from crm.actividades x where x.lead_id = p_lead_id) then
    raise exception 'La eliminación quedó incompleta; no se aplicó nada' using errcode = '55000';
  end if;

  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'copia_id', v_id, 'filas', v_filas);
end $$;

-- ── 5 · Permisos ───────────────────────────────────────────────────────────────────────────────────────────────────────
revoke all on table crm.leads_eliminados from public, anon, authenticated, service_role;
grant select on table crm.leads_eliminados to authenticated;
revoke all on function private.proteger_lead_eliminado() from public, anon, authenticated, service_role;
revoke all on function private.borrado_lead_error_autoriza(text, jsonb) from public, anon, authenticated, service_role;
revoke all on function crm.eliminar_lead_error_carga(uuid, text) from public, anon, service_role;
grant execute on function crm.eliminar_lead_error_carga(uuid, text) to authenticated;

-- ── 6 · Comentarios ────────────────────────────────────────────────────────────────────────────────────────────────────
comment on table crm.leads_eliminados is
  'Copia inmutable de cada lead eliminado por error de carga (crm.eliminar_lead_error_carga, 14/10/2026): el lead y todas '
  'sus filas hijas, tal como estaban al borrarlas. Solo lectura y solo para gerencia del CRM (RLS); nadie la modifica ni '
  'la borra. Contiene datos personales del lead (nombre, teléfono, documento) dentro de la copia.';
comment on column crm.leads_eliminados.id is 'Identificador de la copia.';
comment on column crm.leads_eliminados.lead_id is 'Lead eliminado (ya no existe en crm.leads; sin llave foránea a propósito).';
comment on column crm.leads_eliminados.motivo is 'Motivo escrito por quien eliminó (10 a 500 caracteres).';
comment on column crm.leads_eliminados.eliminado_por is 'Perfil que eliminó (auth.uid() resuelto en el servidor).';
comment on column crm.leads_eliminados.rol_actor is 'Rol que habilitó la eliminación: gerencia (CRM), admin o superadmin (portal).';
comment on column crm.leads_eliminados.eliminado_en is 'Momento de la eliminación.';
comment on column crm.leads_eliminados.copia is
  'DATOS PERSONALES. Copia jsonb: lead y un arreglo por tabla hija (tareas, actividades, asignaciones, SLA, recibos, '
  'potencial, base cargada, llamadas del celular). Enmascarada en public.audit_log.';
comment on column crm.leads_eliminados.filas is 'Cuántas filas se copiaron y borraron, por tabla.';
comment on column crm.leads_eliminados.transaccion is
  'Transacción que copió y borró; los candados solo abren el DELETE dentro de ella (private.borrado_lead_error_autoriza).';
comment on function private.proteger_lead_eliminado() is 'Candado de crm.leads_eliminados: UPDATE, DELETE y TRUNCATE prohibidos (42501).';
comment on function private.borrado_lead_error_autoriza(text, jsonb) is
  'Llave única de los 8 candados para el DELETE de un lead por error de carga: exige el permiso crm.borrado_lead_error '
  'con el id del lead, la copia de ESTA transacción, del MISMO actor, y la fila idéntica dentro de la copia.';
comment on function crm.eliminar_lead_error_carga(uuid, text) is
  'Elimina un lead cargado por error con todo lo que cuelga de él, dejando antes una copia en crm.leads_eliminados. Solo '
  'gerencia (CRM) o admin/superadmin (portal); motivo obligatorio. Rechaza (P0409) leads con contrato, perfil, '
  'inversionista, conversión o cierre, historia de inversión, más de 30 días o en un mes cerrado.';

-- ── 7 · Postflight ─────────────────────────────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_bloque constant text := $b$  if tg_op = 'DELETE' then
    -- Única excepción: la vía oficial crm.eliminar_lead_error_carga, y solo para una fila ya copiada en
    -- crm.leads_eliminados en ESTA transacción (ver private.borrado_lead_error_autoriza).
    if private.borrado_lead_error_autoriza(tg_table_name, pg_catalog.to_jsonb(old)) then return old; end if;
  end if;
$b$;
begin
  -- Los 8 candados: llevan el bloque una sola vez y, sin él, son idénticos a producción byte a byte.
  if (
      md5(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_sla_nucleo_entrada_guard()'::regprocedure), v_bloque, '')) = '3d052e4dc970d0b2b23a81cb73d6c60f'
      and pg_catalog.length(pg_catalog.pg_get_functiondef('private.trg_sla_nucleo_entrada_guard()'::regprocedure)) - pg_catalog.length(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_sla_nucleo_entrada_guard()'::regprocedure), v_bloque, '')) = pg_catalog.length(v_bloque)
      and md5(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_lead_asignacion_sla_hitos_guard()'::regprocedure), v_bloque, '')) = '2e2971b4325c7aad4253387dad301400'
      and pg_catalog.length(pg_catalog.pg_get_functiondef('private.trg_lead_asignacion_sla_hitos_guard()'::regprocedure)) - pg_catalog.length(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_lead_asignacion_sla_hitos_guard()'::regprocedure), v_bloque, '')) = pg_catalog.length(v_bloque)
      and md5(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_lead_asignaciones_inmutables()'::regprocedure), v_bloque, '')) = 'ab7507ef09420c7f8445a4d563a3566f'
      and pg_catalog.length(pg_catalog.pg_get_functiondef('private.trg_lead_asignaciones_inmutables()'::regprocedure)) - pg_catalog.length(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_lead_asignaciones_inmutables()'::regprocedure), v_bloque, '')) = pg_catalog.length(v_bloque)
      and md5(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_lead_sla_ciclos_guard()'::regprocedure), v_bloque, '')) = '04ce52eeb57ea8fde1fa71f9d021e025'
      and pg_catalog.length(pg_catalog.pg_get_functiondef('private.trg_lead_sla_ciclos_guard()'::regprocedure)) - pg_catalog.length(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_lead_sla_ciclos_guard()'::regprocedure), v_bloque, '')) = pg_catalog.length(v_bloque)
      and md5(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_lead_sla_etapas_guard()'::regprocedure), v_bloque, '')) = 'bdc42cc17888cffea22aaf63162344fe'
      and pg_catalog.length(pg_catalog.pg_get_functiondef('private.trg_lead_sla_etapas_guard()'::regprocedure)) - pg_catalog.length(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_lead_sla_etapas_guard()'::regprocedure), v_bloque, '')) = pg_catalog.length(v_bloque)
      and md5(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_sla_recibo_guard()'::regprocedure), v_bloque, '')) = '903e9260918bc7e100bde650d46c1ee4'
      and pg_catalog.length(pg_catalog.pg_get_functiondef('private.trg_sla_recibo_guard()'::regprocedure)) - pg_catalog.length(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_sla_recibo_guard()'::regprocedure), v_bloque, '')) = pg_catalog.length(v_bloque)
      and md5(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.potencial_evento_inmutable()'::regprocedure), v_bloque, '')) = 'a9eed979747620bb83d8670a2ffcf869'
      and pg_catalog.length(pg_catalog.pg_get_functiondef('private.potencial_evento_inmutable()'::regprocedure)) - pg_catalog.length(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.potencial_evento_inmutable()'::regprocedure), v_bloque, '')) = pg_catalog.length(v_bloque)
      and md5(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_actividades_no_contactar_solo_puerta()'::regprocedure), v_bloque, '')) = '30015d7ddda774c110082de47b5b3056'
      and pg_catalog.length(pg_catalog.pg_get_functiondef('private.trg_actividades_no_contactar_solo_puerta()'::regprocedure)) - pg_catalog.length(pg_catalog.replace(pg_catalog.pg_get_functiondef('private.trg_actividades_no_contactar_solo_puerta()'::regprocedure), v_bloque, '')) = pg_catalog.length(v_bloque)
  ) is not true then
    raise exception 'POSTFLIGHT: un candado no quedó como producción + la excepción del DELETE';
  end if;
  if (select relrowsecurity from pg_catalog.pg_class where oid = 'crm.leads_eliminados'::regclass) is not true then
    raise exception 'POSTFLIGHT: crm.leads_eliminados sin RLS';
  end if;
  if (select count(*) from pg_catalog.pg_policy where polrelid = 'crm.leads_eliminados'::regclass) <> 1
     or exists (select 1 from pg_catalog.pg_policy where polrelid = 'crm.leads_eliminados'::regclass and polcmd <> 'r') then
    raise exception 'POSTFLIGHT: crm.leads_eliminados debe tener una sola política, de lectura';
  end if;
  if not has_table_privilege('authenticated', 'crm.leads_eliminados', 'select')
     or has_table_privilege('authenticated', 'crm.leads_eliminados', 'insert, update, delete, truncate')
     or has_table_privilege('anon', 'crm.leads_eliminados', 'select, insert, update, delete, truncate')
     or has_table_privilege('service_role', 'crm.leads_eliminados', 'select, insert, update, delete, truncate') then
    raise exception 'POSTFLIGHT: permisos de crm.leads_eliminados';
  end if;
  if (select count(*) from pg_catalog.pg_trigger where tgrelid = 'crm.leads_eliminados'::regclass and not tgisinternal) <> 3 then
    raise exception 'POSTFLIGHT: triggers de crm.leads_eliminados';
  end if;
  if not has_function_privilege('authenticated', 'crm.eliminar_lead_error_carga(uuid,text)', 'execute')
     or has_function_privilege('anon', 'crm.eliminar_lead_error_carga(uuid,text)', 'execute')
     or has_function_privilege('service_role', 'crm.eliminar_lead_error_carga(uuid,text)', 'execute')
     or has_function_privilege('authenticated', 'private.borrado_lead_error_autoriza(text,jsonb)', 'execute')
     or has_function_privilege('anon', 'private.borrado_lead_error_autoriza(text,jsonb)', 'execute') then
    raise exception 'POSTFLIGHT: permisos de las funciones nuevas';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p
             where p.oid in ('crm.eliminar_lead_error_carga(uuid,text)'::regprocedure,
                             'private.borrado_lead_error_autoriza(text,jsonb)'::regprocedure,
                             'private.proteger_lead_eliminado()'::regprocedure)
               and p.proowner <> 'postgres'::regrole) then
    raise exception 'POSTFLIGHT: dueño de las funciones nuevas';
  end if;
  if (select p.prosecdef and p.proconfig @> array['search_path=""'] from pg_catalog.pg_proc p
      where p.oid = 'crm.eliminar_lead_error_carga(uuid,text)'::regprocedure) is not true then
    raise exception 'POSTFLIGHT: la puerta debe ser DEFINER con search_path vacío';
  end if;
  if exists (select 1 from private.contadores_crudos_leads_citas() c
             where c.objeto in ('crm.eliminar_lead_error_carga(uuid,text)', 'private.borrado_lead_error_autoriza(text,jsonb)')) then
    raise exception 'POSTFLIGHT: una función nueva entró al censo analítico';
  end if;
  if (select count(*) from pg_catalog.pg_trigger t
      where t.tgenabled = 'O' and t.tgfoid in ('private.trg_sla_nucleo_entrada_guard()'::regprocedure, 'private.trg_lead_asignacion_sla_hitos_guard()'::regprocedure, 'private.trg_lead_asignaciones_inmutables()'::regprocedure, 'private.trg_lead_sla_ciclos_guard()'::regprocedure, 'private.trg_lead_sla_etapas_guard()'::regprocedure, 'private.trg_sla_recibo_guard()'::regprocedure, 'private.potencial_evento_inmutable()'::regprocedure, 'private.trg_actividades_no_contactar_solo_puerta()'::regprocedure)) <> 17 then
    raise exception 'POSTFLIGHT: los triggers de los candados no siguen en su modo normal';
  end if;
end
$postflight$;

notify pgrst, 'reload schema';
commit;
-- Soltar la exclusión de migraciones (candado de SESIÓN tomado antes de la instantánea).
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
