-- Reproducción sobre schema real, sin sustituir funciones ni desactivar triggers.
-- Ejecutar solo en banco aislado: psql -v corregido=0 antes, =1 después.
\set ON_ERROR_STOP on
begin;
\ir fixtures.sql
insert into crm.multiempresa_flags(nombre,activo) values ('resolver_en_puertas',false)
on conflict(nombre) do update set activo=false;
select set_config('crm.op_privilegiada','on',true);
select set_config('prueba.formulario3.corregido',:'corregido',true);
do $prueba$
declare v_cerrado integer; v_vivo integer; v_persona uuid;
begin
  v_persona := private.inversionista_resolver('DNI','49100001',true,'prueba-formulario3');
  insert into crm.leads(id,nombre_completo,telefono,dni,origen,monto_estimado,etapa,motivo_descarte,inversionista_id)
  values ('f3100000-0000-0000-0000-000000000001','Prueba ficha cerrada','981000001','49100001','formulario',5000,'descartado','otro',v_persona);
  insert into crm.leads(id,nombre_completo,telefono,dni,origen,monto_estimado,etapa)
  values ('f3100000-0000-0000-0000-000000000002','Prueba ficha viva','981000002','49100001','formulario',5000,'nuevo');
  update crm.multiempresa_flags set activo=true where nombre='resolver_en_puertas';
  execute 'set local role service_role';
  perform crm.importar_lead_fn('{"fila":2,"nombre_completo":"Prueba reingreso","telefono":"981000003","dni":"49100001","origen":"formulario","monto_estimado":5000,"moneda":"PEN"}');
  execute 'reset role';
  select count(*) into v_cerrado from crm.actividades where lead_id='f3100000-0000-0000-0000-000000000001' and metadata->>'evento'='reingreso';
  select count(*) into v_vivo from crm.actividades where lead_id='f3100000-0000-0000-0000-000000000002' and metadata->>'evento'='reingreso';
  if current_setting('prueba.formulario3.corregido')='1' then
    if v_cerrado<>0 or v_vivo<>1 then raise exception 'Reingreso mal dirigido: cerrado=%, vivo=%',v_cerrado,v_vivo; end if;
    raise notice 'PASS: reingreso en ficha viva, cero en ficha cerrada';
  else
    if v_cerrado<>1 or v_vivo<>0 then raise exception 'No se reprodujo el defecto: cerrado=%, vivo=%',v_cerrado,v_vivo; end if;
    raise notice 'DEFECTO REPRODUCIDO: reingreso en ficha cerrada pese a existir una viva';
  end if;
end;
$prueba$;
rollback;
