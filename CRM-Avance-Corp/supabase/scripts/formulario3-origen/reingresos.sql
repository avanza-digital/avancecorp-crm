-- Reintentos reales entre productores legados y canónicos. Identidad encendida.
create function pg_temp.importar_f3(p jsonb) returns jsonb language plpgsql as $$
declare r jsonb; begin
  execute 'set local role service_role';
  r := crm.importar_lead_fn(p);
  execute 'reset role';
  return r;
exception when others then execute 'reset role'; raise;
end $$;

do $reingresos$
declare
  i integer; con_ficha boolean; canonico_primero boolean; persona uuid; perfil uuid; lead uuid;
  p jsonb; r jsonb; repetido jsonb; actividad uuid; v_tareas bigint; notas bigint;
  seccion text; canal text;
begin
  for i in 1..4 loop
    con_ficha := i <= 2;
    canonico_primero := i % 2 = 0;
    update crm.multiempresa_flags set activo=false where nombre='resolver_en_puertas';
    persona := private.inversionista_resolver('DNI','4950010'||i,true,'fixture-origen-f3');
    p := jsonb_build_object('nombre_completo','REINGRESO SINTETICO '||i,
      'telefono','98500100'||i,'dni','4950010'||i,'origen','formulario',
      'campania_origen','Formulario 3','monto_estimado',5000,'moneda','PEN');
    if con_ficha then
      r := pg_temp.importar_f3(p - 'campania_origen');
      lead := (r->>'lead_id')::uuid;
      perform pg_temp.exigir(lead is not null,'fixture con ficha viva');
      seccion := 'reingreso';
    else
      perfil := ('f6200000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid;
      perform set_config('crm.op_privilegiada','on',true);
      insert into auth.users(id) values(perfil);
      insert into public.perfiles(id,nombre_completo,rol,tipo_documento,dni,correo,asesor_perfil_id,activo)
      values(perfil,'CLIENTE SINTETICO '||i,'cliente','DNI','4950010'||i,
        'f3-'||i||'@example.invalid','f6000000-0000-0000-0000-000000000001',true);
      update crm.inversionistas set perfil_id=perfil where id=persona;
      perform set_config('crm.op_privilegiada','off',true);
      seccion := 'solicitud';
    end if;
    update crm.multiempresa_flags set activo=true where nombre='resolver_en_puertas';
    canal := case when canonico_primero then 'formulario_3' else 'formulario' end;
    r := pg_temp.importar_f3(p || jsonb_build_object('origen',canal));
    actividad := (r->seccion->>'actividad_id')::uuid;
    perform pg_temp.exigir(r->>'resultado'='ya_cliente' and actividad is not null,
      seccion||': reconocimiento real');
    select count(*) into v_tareas from crm.tareas;
    select (select count(*) from crm.actividades)+(select count(*) from crm.actividades_cliente) into notas;
    canal := case when canonico_primero then 'formulario' else 'formulario_3' end;
    repetido := pg_temp.importar_f3(p || jsonb_build_object('fila',900+i,'origen',canal));
    perform pg_temp.exigir(repetido->seccion->>'repetido'='true'
      and (repetido->seccion->>'actividad_id')::uuid=actividad,
      seccion||': legado/canónico conserva el recibo en ambos sentidos');
    perform pg_temp.exigir((select count(*)=v_tareas from crm.tareas)
      and (select (select count(*) from crm.actividades)+(select count(*) from crm.actividades_cliente))=notas,
      seccion||': no duplica notas ni tareas');
    if con_ficha then
      perform pg_temp.exigir((select origen='formulario' and campania_origen is null from crm.leads where id=lead),
        'reingreso no cambia la atribución de la ficha existente');
    else
      perform pg_temp.exigir(not exists(select 1 from crm.leads where dni='4950010'||i),
        'cliente reconocido no genera un lead adicional');
      perform pg_temp.exigir(r->seccion->>'tarea_id' is not null,'solicitud crea tarea para el analista');
    end if;
  end loop;
end $reingresos$;
update crm.multiempresa_flags set activo=false where nombre='resolver_en_puertas';
