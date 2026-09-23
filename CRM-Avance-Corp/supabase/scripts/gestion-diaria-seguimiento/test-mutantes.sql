-- Cada alteración deliberada se revierte en una subtransacción, también si
-- el gate falla. No se debilita la base usada por las siguientes pruebas.
do $mutantes$
declare caso record; detectado boolean; total integer := 0;
begin
  for caso in select * from (values
    ('lector pierde RLS','alter function private.gestion_diaria_avisos(timestamptz) owner to postgres'),
    ('lector sin autenticado','revoke authenticated from crm_gestion_diaria_lector'),
    ('sello legacy alterado','create or replace function crm.alertas_reconocimientos_sellar() returns trigger language plpgsql security definer set search_path='''' as ''begin return new; end'''),
    ('contexto elevado','alter function private.gestion_diaria_contexto(uuid[],timestamptz,jsonb) security definer'),
    ('contexto expuesto','grant execute on function private.gestion_diaria_contexto(uuid[],timestamptz,jsonb) to authenticated'),
    ('SLA expuesto','grant execute on function private.gestion_diaria_alertas_sla() to authenticated'),
    ('SLA sin autorización','create or replace function private.gestion_diaria_alertas_sla() returns jsonb language sql stable security definer set search_path='''' as ''select null::jsonb'''),
    ('RLS entregas','alter table crm.gestion_diaria_entregas disable row level security'),
    ('lectura API','grant select on crm.gestion_diaria_control_avisos to authenticated'),
    ('lectura por columna','grant select (solicitud_id) on crm.gestion_diaria_entregas to anon'),
    ('escritura lector','grant insert on crm.gestion_diaria_entregas to crm_gestion_diaria_lector'),
    ('lector con login','alter role crm_gestion_diaria_lector login'),
    ('membresía API','grant crm_gestion_diaria_lector to service_role'),
    ('unicidad de posponer','drop index crm.alertas_corte_aplazamiento_unico_idx'),
    ('idempotencia de acción','drop index crm.alertas_corte_solicitud_idx'),
    ('unicidad de entrega','alter table crm.gestion_diaria_entregas drop constraint gestion_diaria_entregas_perfil_id_alerta_id_entrega_key'),
    ('auditoría','alter table crm.gestion_diaria_control_avisos disable trigger trg_audit'),
    ('inmutabilidad','alter table crm.gestion_diaria_entregas disable trigger trg_inmutable'),
    ('predicado de ámbito','alter policy lectura_interna on crm.gestion_diaria_entregas using (true)'),
    ('función privada expuesta','grant execute on function private.gestion_diaria_avisos(timestamptz) to authenticated'),
    ('escritura gerencial expuesta','grant execute on function crm.publicar_politica_gestion_diaria(integer,timestamptz,jsonb,text) to anon'),
    ('puerta de avisos invoker','alter function crm.gestion_diaria_avisos_fn() security invoker'),
    ('búsqueda manipulable','alter function crm.gestion_diaria_presentar_corte(text,uuid) set search_path = public'),
    ('política sin cuerpo','create or replace function crm.configuracion_gestion_diaria_fn() returns jsonb language sql stable security definer set search_path='''' as ''select null::jsonb''')
  ) m(nombre,sql) loop
    detectado := false;
    begin
      execute caso.sql;
      begin perform private.assert_gestion_diaria(); exception when others then detectado := true; end;
      raise exception 'Revertir mutante' using errcode='Z0001';
    exception when sqlstate 'Z0001' then null;
    end;
    if not detectado then raise exception 'F4.4/5: el gate no detectó %',caso.nombre; end if;
    total := total+1;
  end loop;
  perform private.assert_gestion_diaria();
  raise notice 'PASS: % mutantes detectados y revertidos',total;
end $mutantes$;
select 'PASS: 24 mutantes de código, autorización, RLS, unicidad, roles y auditoría';
