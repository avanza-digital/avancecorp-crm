-- PostgREST 14.5 reintenta SQLSTATE 40001 indefinidamente. Una revisión
-- obsoleta exige intervención del usuario: se responde HTTP 409 (PT409).
-- Se conservan comprobaciones, mensajes, bloqueos, firmas, permisos y datos.
begin;
set local lock_timeout = '5s';
set local search_path = '';

do $conflictos$
declare
  v_firma text;
  v_esperado text;
  v_sql text;
begin
  for v_firma, v_esperado in
    select * from (values
      ('crm.confirmar_inversion_revisada_fn(uuid,integer)', '0b258ad5cc577f6a3b630b8c270453fa'),
      ('crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text)', '014ef6ae658f3aa6965d287f9c960299')
    ) as firmas(firma, huella)
  loop
    v_sql := pg_catalog.pg_get_functiondef(v_firma::regprocedure);
    if pg_catalog.md5(v_sql) <> v_esperado then
      raise exception 'La definición de % cambió; revisar antes de aplicar', v_firma;
    end if;
    if (length(v_sql) - length(replace(v_sql, 'errcode=''40001''', ''))) / length('errcode=''40001''') <> 2 then
      raise exception 'Número inesperado de conflictos en %', v_firma;
    end if;
    execute replace(v_sql, 'errcode=''40001''', 'errcode=''PT409''');
  end loop;
end;
$conflictos$;

notify pgrst, 'reload schema';
commit;
