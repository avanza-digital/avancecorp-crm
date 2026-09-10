-- F6: conflicto HTTP 409 sin el bucle de reintentos de PostgREST 14.
-- Mantiene intacta la migración F6 inicial. No cambia firmas, permisos o datos.
-- El bloque exterior conserva el rollback íntegro antes de traducir SQLSTATE.
-- Fuente: https://supabase.com/docs/guides/troubleshooting/high-cpu-and-infinite-transaction-retries-when-using-custom-error-codes-in-rpc-functions-77326b
begin;
set local lock_timeout='5s';
do $f6_http$
declare
  r record; v_oid oid; v_cuerpo text; v_nuevo text; v_def text; v_cierre text;
begin
  if not exists(select 1 from crm.multiempresa_flags where nombre='postventa_neutral' and not activo)
    or exists(select 1 from crm.multiempresa_flags where nombre in ('postventa_neutral','ficha_360_neutral','inversiones_escritura') and activo) then
    raise exception 'Instala la corrección con F4/F5/F6 apagadas';
  end if;
  for r in select * from (values
    ('crm.inversionista_ficha_fn(uuid,integer,integer)','f241a200ada86c075fec1d9836f020c2','ficha'),
    ('crm.postventa_agenda_fn()','54631ca16638bb4c167761ce46b32767','frontera'),
    ('crm.postventa_agendar_fn(uuid,uuid,jsonb,uuid)','4e13a5e5f308b14e955bc0f6ea49b9ba','frontera'),
    ('crm.postventa_estado_fn()','734d290410f2accddbce98cbc14e1304','frontera'),
    ('crm.postventa_ficha_fn(uuid)','8183a28c70a964b5da4eee5656878415','frontera'),
    ('crm.postventa_operacion_estado_fn(uuid,uuid)','18393c806b5900202556d471a97879b2','frontera'),
    ('crm.postventa_perfil_fn(uuid)','4507f5682dcae5a1348f3e71fef41c38','frontera'),
    ('crm.postventa_revisar_retiro_fn(uuid,uuid,integer,text,text,uuid)','2a1c8a2e3d33f14389b67fede72eba87','frontera'),
    ('crm.postventa_solicitar_retiro_fn(uuid,uuid,uuid,text,uuid)','851d9cb4abf5179a75f357adce2c7a72','frontera'),
    ('crm.postventa_tarea_fn(uuid,uuid,integer,text,jsonb,uuid)','8b2d8a3648c5446e61b9acae78e5f83f','frontera'),
    ('crm.postventa_vencimientos_fn(text,integer)','b37169580bb234b9f56910eda2940c9a','frontera'),
    ('crm.postventa_veto_fn(uuid,uuid,boolean,text,uuid)','c8edafdf8297d256d0ab3be2d42745ad','frontera'),
    ('crm.preparar_reinversion_fn(uuid,uuid,jsonb)','db7c7d14b3f5b88be645bdc9e7046cac','frontera'),
    ('private.postventa_reinversion_guard()','b1457ba615609b69fcfc3cbe85ef1ab1','frontera'),
    ('private.postventa_sincronizar(uuid)','0c069c97967c93a275a107bfc5799011','frontera'),
    ('crm.confirmar_inversion_revisada_fn(uuid,integer)','3c71c824423ac6b49a8a90e89a5069cd','solicitud'),
    ('crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text)','5e31ff361858d23c817d8a20a79d8c51','solicitud'),
    ('crm.revisar_solicitud_inversion_fn(uuid,uuid,integer,text)','8f162da7df9d86dd336dd485acc663e7','solicitud')
  ) as esperado(firma,huella,modo)
  loop
    v_oid:=to_regprocedure(r.firma);
    select prosrc into v_cuerpo from pg_proc where oid=v_oid;
    if v_oid is null or md5(v_cuerpo) is distinct from r.huella then
      raise exception 'Base F6 distinta para %; revisar antes de continuar',r.firma;
    end if;
    v_nuevo:=v_cuerpo;
    if r.firma='crm.postventa_agenda_fn()' or r.modo='ficha' then
      if position('exception when serialization_failure or lock_not_available then' in v_nuevo)=0 then
        raise exception 'No se encontró la degradación acotada de %',r.firma;
      end if;
      v_nuevo:=replace(v_nuevo,
        'exception when serialization_failure or lock_not_available then',
        'exception when serialization_failure or lock_not_available or sqlstate ''PT409'' then');
    end if;
    if r.modo<>'ficha' then
      v_cierre:=E'\nexception when serialization_failure then\n';
      if r.modo='solicitud' then
        -- El trámite F4 conserva su comportamiento anterior salvo cuando
        -- la solicitud procede de una reinversión F6 identificada previamente.
        v_cierre:=v_cierre||E'  if not exists(select 1 from crm.inversion_solicitud_origenes where solicitud_id=p_solicitud) then raise; end if;\n';
      end if;
      v_cierre:=v_cierre||E'  raise exception using errcode=''PT409'', message=''La operación coincidió con otro cambio. Vuelve a intentarlo.'';\nend;\n';
      v_nuevo:=E'begin\n'||v_nuevo||v_cierre;
    end if;
    v_def:=pg_get_functiondef(v_oid);
    if (length(v_def)-length(replace(v_def,v_cuerpo,'')))/length(v_cuerpo)<>1 then
      raise exception 'Definición ambigua para %',r.firma;
    end if;
    execute replace(v_def,v_cuerpo,v_nuevo);
  end loop;
end;
$f6_http$;
commit;
