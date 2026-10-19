-- Conflictos de acceso deterministas: PostgREST no debe reintentarlos como
-- serialización. La fecha de inicio se fija únicamente al activar exigencia.
begin;
set local search_path='';
set local quote_all_identifiers=off;
do $$
declare v_acceso text;v_control text;v_ancla text;
begin
  v_acceso:=pg_get_functiondef('crm.acceso_inversion_fn(uuid,text,jsonb)'::regprocedure);
  v_control:=pg_get_functiondef('crm.recorrido_configurar_fn(text,text,integer,timestamptz)'::regprocedure);
  if md5(v_acceso)<>'282a3e9f27385611c6f4d794f977546e'
    or md5(v_control)<>'6597bef760830dc37673df68e174cbec' then
    raise exception 'Cambio el contrato revisado de acceso o control; revisar antes de instalar' using errcode='55000';
  end if;
  execute replace(v_acceso,'errcode=''40001''','errcode=''PT409''');
  v_ancla:='  select * into strict v_control from crm.recorrido_control where id for update;';
  execute replace(v_control,v_ancla,$guard$  if p_cohorte_desde is not null and p_modo<>'exigir' then
    raise exception 'La fecha inicial solo se programa al activar la exigencia' using errcode='22023';
  end if;
$guard$||v_ancla);
end $$;
notify pgrst,'reload schema';
commit;
