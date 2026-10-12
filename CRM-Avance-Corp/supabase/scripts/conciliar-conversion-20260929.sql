-- Reparación puntual autorizada por el usuario en Codex, 2026-09-29.
-- Usa las puertas existentes; no modifica esquema, permisos ni atribuciones confirmadas.
-- Cuenta administrativa y motivo explícito: no se atribuye la reparación a la supervisora.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
do $conciliar$
declare
  v_lead_id constant uuid := '5cb6fb83-7a10-4d95-9bdd-a587e20388f2';
  v_persona_id constant uuid := 'efcac514-c690-48dc-9bf2-49b4cba12536';
  v_solicitud_id constant uuid := '27b9ea65-6be5-4e19-a8e0-fa86d51fceaa';
  v_admin constant uuid := 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127';
  v_anterior constant uuid := 'ad36b962-5175-4e4e-b644-e546897c3a85';
  v_nuevo constant uuid := '1de5eba1-e6bb-435d-9eff-74286e881d01';
  v_motivo constant text := 'Corrección técnica mediante Codex autorizada por el usuario el 2026-09-29: conciliar persona y borrador con la reasignación vigente del lead. Sin confirmar inversión ni alterar condiciones.';
  v_l crm.leads%rowtype; v_i crm.inversionistas%rowtype;
  v_s crm.inversion_solicitudes%rowtype;
  v_tramo uuid; v_revision integer; v_antes jsonb;
begin
  if md5(pg_get_functiondef('crm.reasignar_responsable_relacion_fn(uuid,uuid,text)'::regprocedure))<>'8d5f2dc4630ba00bf5dc26d7cbef82a8'
    or md5(pg_get_functiondef('crm.revisar_solicitud_inversion_fn(uuid,uuid,integer,text)'::regprocedure))<>'dc622b938e8d8e9777a033cfa625b11a'
    or md5(pg_get_functiondef('crm.preparar_persona_lead_inversion_fn(uuid,text,text,text)'::regprocedure))<>'b40dded8a923dcd02f028b24bc4de94e'
    or md5(pg_get_functiondef('private.inversion_persona_contexto_para(uuid,uuid,uuid,uuid)'::regprocedure))<>'dcc540a48b7f252c783f814f6a184144'
    or md5(pg_get_functiondef('private.inversion_persona_autorizada_para(uuid,uuid,uuid)'::regprocedure))<>'c91e82b30558d121782f94aefab39d6e' then
    raise exception 'Las puertas cambiaron desde la revisión: detener reparación';
  end if;
  perform set_config('request.jwt.claim.sub',v_admin::text,true);
  perform pg_advisory_xact_lock_shared(hashtextextended('crm.equipo.usuarios_jerarquia',0));
  if auth.uid() is distinct from v_admin or private.es_gerencia_crm_activa() is not true
    or private.rol_crm(v_nuevo) is distinct from 'vendedor' then
    raise exception 'La cuenta administrativa o el destinatario no están activos';
  end if;
  perform private.identidad_bloquear_documentos_de(array[v_persona_id]);
  select * into strict v_i from crm.inversionistas where id=v_persona_id for update;
  select * into strict v_l from crm.leads where id=v_lead_id for update nowait;
  select * into strict v_s from crm.inversion_solicitudes where id=v_solicitud_id for update nowait;
  if v_l.inversionista_id is distinct from v_persona_id or v_l.vendedor_id is distinct from v_nuevo
    or v_l.activo is not true or (v_l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')) is not true
    or v_l.no_contactar is not false or v_l.asignado_supervisor_id is not null
    or v_i.estado is distinct from 'activo' or v_i.perfil_id is not null or v_i.no_contactar is not false
    or v_s.inversionista_id is distinct from v_persona_id or v_s.lead_origen_id is distinct from v_lead_id
    or v_s.estado is distinct from 'preparada' or v_s.puerta is distinct from 'cartera' or v_s.auth_claim_id is not null
    or v_s.inversion_id is not null or v_s.analista_cierre_id is not null
    or exists(select 1 from crm.inversiones where inversionista_id=v_persona_id)
    or exists(select 1 from private.leads_de_personas(array[v_persona_id]) x where x<>v_lead_id)
    or exists(select 1 from private.leads_de_identidades(array[v_persona_id]) x where x<>v_lead_id)
    or exists(select 1 from crm.inversion_solicitudes where inversionista_id=v_persona_id and id<>v_solicitud_id)
    or exists(select 1 from crm.conversion_reservas where
      (lead_id=v_lead_id or inversionista_id=v_persona_id) and
      (efectos_iniciados_en is not null or expira_en>now())) then
    raise exception 'El caso cambió o tiene efectos económicos: detener reparación';
  end if;
  if v_i.responsable_relacion_id=v_nuevo and v_s.responsable_esperado_id=v_nuevo
    and (select count(*) from crm.inversionista_responsables where inversionista_id=v_persona_id and hasta is null)=1
    and exists(select 1 from crm.inversionista_responsables where inversionista_id=v_persona_id and hasta is null and responsable_id=v_nuevo) then
    raise notice 'Ya conciliado: no se escribe nuevamente';
    return;
  end if;
  if v_i.responsable_relacion_id is distinct from v_anterior
    or v_s.responsable_esperado_id is distinct from v_anterior
    or v_s.hash_payload is distinct from 'aef6368458f9ff28baac305a824b96948407dd9dc39243dcb196b69917a27809'
    or v_s.revision_datos is distinct from 0 then
    raise exception 'Cambió la asignación o el borrador: detener reparación';
  end if;
  select id into strict v_tramo from crm.inversionista_responsables
    where inversionista_id=v_persona_id and hasta is null and responsable_id=v_anterior for update;
  select coalesce(max(revision),0) into v_revision from crm.inversion_solicitud_revisiones where solicitud_id=v_solicitud_id;
  if v_revision<>0 then raise exception 'La solicitud ya fue revisada: detener reparación'; end if;
  v_antes:=to_jsonb(v_s)-'responsable_esperado_id'-'actualizado_en';

  perform crm.reasignar_responsable_relacion_fn(v_persona_id,v_nuevo,v_motivo);
  perform crm.revisar_solicitud_inversion_fn(v_solicitud_id,v_nuevo,v_revision,v_motivo);

  if (select to_jsonb(s)-'responsable_esperado_id'-'actualizado_en' from crm.inversion_solicitudes s where id=v_solicitud_id) is distinct from v_antes
    or (select to_jsonb(l) from crm.leads l where id=v_lead_id) is distinct from to_jsonb(v_l)
    or (select responsable_relacion_id from crm.inversionistas where id=v_persona_id) is distinct from v_nuevo
    or (select responsable_esperado_id from crm.inversion_solicitudes where id=v_solicitud_id) is distinct from v_nuevo
    or exists(select 1 from crm.inversiones where inversionista_id=v_persona_id)
    or (select count(*) from crm.inversionista_responsables where inversionista_id=v_persona_id and hasta is null)<>1
    or not exists(select 1 from crm.inversionista_responsables where inversionista_id=v_persona_id and hasta is null and responsable_id=v_nuevo)
    or not exists(select 1 from crm.inversionista_responsables where id=v_tramo and hasta is not null)
    or not exists(select 1 from crm.inversion_solicitud_revisiones where solicitud_id=v_solicitud_id
      and revision=1 and responsable_anterior_id=v_anterior and responsable_nuevo_id=v_nuevo and revisado_por=v_admin)
    or not exists(select 1 from crm.actividades a join crm.inversionista_responsables r
      on a.metadata->>'tramo_id'=r.id::text
      where a.lead_id=v_lead_id and a.creado_por=v_admin and a.metadata->>'evento'='reasignacion_responsable'
        and r.inversionista_id=v_persona_id and r.responsable_id=v_nuevo and r.hasta is null and r.motivo=v_motivo) then
    raise exception 'Postcondiciones incumplidas: revertir toda la reparación';
  end if;
  raise notice 'PASS: asignaciones conciliadas, historial preservado, borrador intacto y sin inversión creada';
end $conciliar$;
commit;
