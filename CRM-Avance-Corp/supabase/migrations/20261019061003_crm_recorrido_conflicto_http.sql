-- Ensayo hosted: PostgREST 14 reintenta indefinidamente un SQLSTATE 40001
-- intencional. Una revisión obsoleta es un conflicto HTTP 409, no una carrera
-- de serialización que pueda resolverse repitiendo la misma petición.
-- https://supabase.com/docs/guides/troubleshooting/high-cpu-and-infinite-transaction-retries-when-using-custom-error-codes-in-rpc-functions-77326b
begin;
set local search_path='';
set local quote_all_identifiers=off;
do $$
declare v_def text;
begin
  v_def:=pg_get_functiondef('crm.recorrido_configurar_fn(text,text,integer,timestamptz)'::regprocedure);
  if md5(v_def)<>'37384dfb598340150a5dd7a8025d47c5' then
    raise exception 'El contrato de configuracion del recorrido cambio; revisar antes de corregir el conflicto HTTP'
      using errcode='55000';
  end if;
  execute replace(v_def,'errcode=''40001''','errcode=''PT409''');
end $$;
notify pgrst,'reload schema';
commit;
