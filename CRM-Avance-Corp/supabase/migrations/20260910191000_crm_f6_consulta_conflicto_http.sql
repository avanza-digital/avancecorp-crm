-- Completa la frontera HTTP de F6 durante la recuperación de su solicitud F4.
-- La consulta ordinaria F4 conserva su contrato; sólo F6 traduce 40001 a PT409.
begin;
set local lock_timeout='5s';
do $f6_consulta$
declare
  v_oid oid:=to_regprocedure('crm.solicitud_inversion_fn(uuid)');
  v_cuerpo text; v_def text; v_nuevo text;
begin
  if not exists(select 1 from crm.multiempresa_flags where nombre='postventa_neutral' and not activo)
    or exists(select 1 from crm.multiempresa_flags where nombre in ('postventa_neutral','ficha_360_neutral','inversiones_escritura') and activo) then
    raise exception 'Instala la corrección con F4/F5/F6 apagadas';
  end if;
  select prosrc into v_cuerpo from pg_proc where oid=v_oid;
  if v_oid is null or md5(v_cuerpo) is distinct from '126902a5f95479c1aaf5365c6122650a' then
    raise exception 'La consulta F4 cambió; revisar antes de continuar';
  end if;
  v_nuevo:=E'begin\n'||v_cuerpo||E'\nexception when serialization_failure then
  if not exists(select 1 from crm.inversion_solicitud_origenes where solicitud_id=p_solicitud) then raise; end if;
  raise exception using errcode=''PT409'', message=''La operación coincidió con otro cambio. Vuelve a intentarlo.'';
end;\n';
  v_def:=pg_get_functiondef(v_oid);
  if (length(v_def)-length(replace(v_def,v_cuerpo,'')))/length(v_cuerpo)<>1 then
    raise exception 'Definición ambigua de la consulta F4';
  end if;
  execute replace(v_def,v_cuerpo,v_nuevo);
end;
$f6_consulta$;
commit;
