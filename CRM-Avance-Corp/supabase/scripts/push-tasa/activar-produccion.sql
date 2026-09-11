-- CANDIDATO PENDIENTE DE AUTORIZACIÓN. No forma parte del replay de una rama.
-- Ejecutar únicamente en el proyecto productivo dctqcbznekcyxhjujuci, DESPUÉS
-- del merge de la migración, despliegue de la Edge y verificación del frontend.
-- En una rama de prueba se debe configurar SU referencia, nunca la de abajo.
begin;
do $$
begin
  if to_regprocedure('crm.verificar_cron_push_tasa_fn(text,bigint)') is null then
    raise exception 'Falta instalar la migración de notificaciones de tasa';
  end if;
  if not exists(select 1 from vault.decrypted_secrets
      where name='cron_notif_secret' and length(decrypted_secret)>=32) then
    raise exception 'Falta una clave cron válida en Vault';
  end if;
  if exists(select 1 from vault.decrypted_secrets where name='crm_push_proyecto'
      and decrypted_secret<>'dctqcbznekcyxhjujuci') then
    raise exception 'El destino de notificaciones ya apunta a otro proyecto; no se sobrescribe';
  end if;
  if not exists(select 1 from vault.decrypted_secrets where name='crm_push_proyecto') then
    perform vault.create_secret('dctqcbznekcyxhjujuci','crm_push_proyecto',
      'Destino de las notificaciones de tasa del CRM. No es una clave privada.');
  end if;
end;
$$;
commit;
