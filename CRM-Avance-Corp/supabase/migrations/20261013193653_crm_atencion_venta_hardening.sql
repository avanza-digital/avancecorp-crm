-- Hardening del bloque aprobado. Reversa conjunta: supabase/scripts/atencion-venta/reversa.sql.
begin;
revoke all on function private.puede_cambiar_atencion() from public,anon,authenticated,service_role;
revoke all on function private.cambiar_atencion_persona(uuid,uuid,text) from public,anon,authenticated,service_role;
revoke all on function private.analista_previsto_contrato(uuid,uuid,uuid,uuid,uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function private.cambio_responsabilidad_previa(text,uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function private.ejecutar_cambio_responsabilidad(text,uuid,uuid,text,text,boolean) from public,anon,authenticated,service_role;
revoke all on function crm.previsualizar_cambio_responsabilidad_fn(text,uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function crm.previsualizar_cambio_responsabilidad_fn(text,uuid,uuid) to authenticated;
revoke all on function crm.confirmar_cambio_responsabilidad_fn(text,uuid,uuid,text,text) from public,anon,authenticated,service_role;
grant execute on function crm.confirmar_cambio_responsabilidad_fn(text,uuid,uuid,text,text) to authenticated;
revoke all on function public.reasignar_analista_contrato(uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.reasignar_analista_contrato(uuid,uuid,text) to authenticated;
revoke all on function crm.reasignar_responsable_relacion_fn(uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function crm.reasignar_responsable_relacion_fn(uuid,uuid,text) to authenticated;
revoke all on function private.trg_perfiles_asesor_por_nucleo() from public,anon,authenticated,service_role;
revoke all on function private.atencion_perfil_permitida(uuid,uuid) from public,anon,authenticated,service_role;
commit;
