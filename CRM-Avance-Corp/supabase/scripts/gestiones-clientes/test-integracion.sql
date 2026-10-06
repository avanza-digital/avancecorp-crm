-- La misma transacción sintética de ensayar; ningún cambio sobrevive.
set local request.jwt.claim.sub='b0000000-0000-4000-8000-000000000002';
set local role authenticated;
do $$ begin
  for i in 1..28 loop
    perform crm.postventa_agendar_fn(gen_random_uuid(),'10bfe922-e51a-40f5-9557-4a3436923c09',
      jsonb_build_object('tipo','reunion','titulo','Página sintética '||i,'vence_en',now()+interval '1 day',
        'duracion_min',30,'modalidad_reunion','virtual'));
  end loop;
end $$;
set local request.jwt.claim.sub='b0000000-0000-4000-8000-000000000001';
do $$
declare v_dia date:=(now() at time zone 'America/Lima')::date; v_antes jsonb; v_despues jsonb;
  v_p jsonb; v_cursor jsonb; v_ids uuid[]:='{}'; v_total int; v_item jsonb;
begin
  v_antes:=crm.gestion_diaria_citas_fn(v_dia,'analista','b0000000-0000-4000-8000-000000000002');
  v_despues:=crm.gestion_diaria_citas_v2_fn(v_dia,'analista','b0000000-0000-4000-8000-000000000002');
  perform pg_temp.exigir(v_antes-'version'-'items'=v_despues-'version'-'items','G4b conserva total, corte, scope y cursor');
  perform pg_temp.exigir(exists(select 1 from jsonb_array_elements(v_despues->'items') e
    where e->>'sujeto_tipo'='inversionista' and (e->>'identidad_visible')::boolean),'G4b v2 identifica clientes reales');
  perform pg_temp.exigir((select jsonb_agg(e-'sujeto_tipo'-'sujeto_id'-'sujeto_nombre'-'inversionista_id'-'perfil_id'-'identidad_visible')
    from jsonb_array_elements(v_despues->'items') e)=v_antes->'items','G4b no modifica las filas base');
  v_antes:=crm.gestion_diaria_pendientes_fn('b0000000-0000-4000-8000-000000000002');
  v_despues:=crm.gestion_diaria_pendientes_v2_fn('b0000000-0000-4000-8000-000000000002');
  perform pg_temp.exigir(v_antes-'version'-'items'-'generado_en'-'pendientes_al'=v_despues-'version'-'items'-'generado_en'-'pendientes_al',
    'pendientes conserva scope, resumen y cursor');
  perform pg_temp.exigir(exists(select 1 from jsonb_array_elements(v_despues->'items') e
    where e->>'sujeto_tipo'='inversionista' and (e->>'identidad_visible')::boolean),'pendientes identifica clientes reales');
  loop
    v_p:=crm.citas_clientes_fn(v_dia,v_dia+3,p_limite=>10,p_despues_de=>(v_cursor->>'despues_de')::timestamptz,p_despues_id=>(v_cursor->>'despues_id')::uuid);
    if v_total is null then v_total:=(v_p->'resumen'->>'total')::int; end if;
    perform pg_temp.exigir((v_p->'resumen'->>'total')::int=v_total,'Citas mantiene población entre páginas');
    for v_item in select * from jsonb_array_elements(v_p->'items') loop
      perform pg_temp.exigir(not (v_item->>'id')::uuid=any(v_ids),'sin citas repetidas entre páginas');
      v_ids:=array_append(v_ids,(v_item->>'id')::uuid);
    end loop;
    exit when not (v_p->>'hay_mas')::boolean;
    v_cursor:=v_p->'siguiente_cursor';
    if cardinality(v_ids)>100 then raise exception 'Cursor de citas sin fin'; end if;
  end loop;
  perform pg_temp.exigir(cardinality(v_ids)=v_total and v_total>25,'Citas recorre toda la población');
end $$;
select pg_temp.falla($q$select crm.gestion_diaria_citas_v2_fn((now() at time zone 'America/Lima')::date,'analista','b0000000-0000-4000-8000-000000000013')$q$,'42501');
select pg_temp.falla($q$select crm.gestion_diaria_pendientes_v2_fn('b0000000-0000-4000-8000-000000000013')$q$,'42501');
reset role;

-- Gerencia conserva la cola de citas sin responsable; no se atribuye a un analista.
savepoint cita_sin_responsable;
alter table crm.tareas disable trigger user;
update crm.tareas set vendedor_id=null where id='cf000000-0000-4000-8000-000000000031';
alter table crm.tareas enable trigger user;
set local request.jwt.claim.sub='b0000000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.exigir(exists(select 1 from jsonb_array_elements(crm.citas_clientes_fn((now() at time zone 'America/Lima')::date,((now() at time zone 'America/Lima')::date)+3,p_limite=>100)->'items') e
 where e->>'id'='cf000000-0000-4000-8000-000000000031' and e->>'vendedor_id' is null),'Gerencia ve cita sin responsable');
set local request.jwt.claim.sub='b0000000-0000-4000-8000-000000000001';
select pg_temp.exigir(not exists(select 1 from jsonb_array_elements(crm.citas_clientes_fn((now() at time zone 'America/Lima')::date,((now() at time zone 'America/Lima')::date)+3,p_limite=>100)->'items') e
 where e->>'id'='cf000000-0000-4000-8000-000000000031'),'supervisor no hereda la cola sin responsable');
rollback to cita_sin_responsable;
reset role;

-- Medianoche Lima y espejo: llamadas del día, sin duplicar F6 como lead.
set local request.jwt.claim.sub='b0000000-0000-4000-8000-000000000002';
select set_config('crm.op_privilegiada','on',true);
insert into crm.leads(id,nombre_completo,telefono,origen,monto_estimado,vendedor_id,creado_por)
values('cf000000-0000-4000-8000-000000000071','LEAD SINTETICO DE REGRESION','900987621','oficina',1000,
 'b0000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000002');
insert into crm.actividades(lead_id,tipo,detalle,metadata,creado_por,creado_en)
values('cf000000-0000-4000-8000-000000000071','llamada_realizada','Llamada de lead', '{}','b0000000-0000-4000-8000-000000000002',now()),
 ('cf000000-0000-4000-8000-000000000071','llamada_realizada','Espejo de cliente', '{"postventa_gestion_id":"cf000000-0000-4000-8000-000000000011"}','b0000000-0000-4000-8000-000000000002',now());
insert into crm.actividades_cliente(id,cliente_id,vendedor_id,tipo,detalle,creado_por,creado_en)
select ('cf000000-0000-4000-8000-00000000008'||i)::uuid,'c0000000-0000-4000-8000-000000000002',
 'b0000000-0000-4000-8000-000000000002','llamada_no_contestada','Borde Lima '||i,'b0000000-0000-4000-8000-000000000002',
 ((now() at time zone 'America/Lima')::date::timestamp at time zone 'America/Lima')+
 case i when 1 then interval '-1 microsecond' when 2 then interval '0' else interval '1 day' end
from generate_series(1,3) i;
select set_config('crm.op_privilegiada','off',true);
set local role authenticated;
set local request.jwt.claim.sub='b0000000-0000-4000-8000-000000000002';
select pg_temp.exigir((select count(*)=1 from private.gestiones_operativas_eventos((now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date)
 where lead_id='cf000000-0000-4000-8000-000000000071' and tipo='llamada_realizada'),'lead real permanece y espejo se elimina');
select pg_temp.exigir((select array_agg(id)=array['cf000000-0000-4000-8000-000000000082'::uuid] from private.gestiones_clientes_eventos((now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date)
 where id in ('cf000000-0000-4000-8000-000000000081','cf000000-0000-4000-8000-000000000082','cf000000-0000-4000-8000-000000000083')),'ventana Lima inclusiva al inicio y exclusiva al final');
reset role;

-- La bandera neutral desactiva su lectura; perfiles y leads conservan su ámbito.
savepoint bandera;
update crm.multiempresa_flags set activo=false where nombre='postventa_neutral';
set local role authenticated;
select pg_temp.exigir(not exists(select 1 from private.gestiones_clientes_eventos((now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date) where origen='postventa'),'bandera apagada sin registros F6');
select pg_temp.exigir(not exists(select 1 from jsonb_array_elements(crm.citas_clientes_fn((now() at time zone 'America/Lima')::date,((now() at time zone 'America/Lima')::date)+3)->'items') e where e->>'sujeto_tipo'='inversionista'),'bandera apagada sin citas F6');
rollback to bandera;
reset role;

-- Roles excluidos incluso invocando helpers directamente.
savepoint directorio;
-- Preparación de identidad sintética; aquí se prueba lectura, no la transición
-- comercial entre roles (el fixture tiene tareas asignadas). Ambos triggers
-- quedan activos ANTES de invocar las RPC y el savepoint revierte la identidad.
alter table crm.equipo disable trigger user;
alter table public.perfiles disable trigger user;
update public.perfiles set rol='directorio' where id='b0000000-0000-4000-8000-000000000002';
update crm.equipo set rol_crm='directorio',supervisor_id=null where perfil_id='b0000000-0000-4000-8000-000000000002';
alter table public.perfiles enable trigger user;
alter table crm.equipo enable trigger user;
set local role authenticated;
select pg_temp.exigir(private.rol_crm(auth.uid())='directorio','fixture Directorio efectivo');
select pg_temp.falla($q$select crm.gestiones_resumen_fn(current_date,current_date)$q$,'42501');
select pg_temp.falla($q$select private.gestiones_clientes_identidades('[]')$q$,'42501');
rollback to directorio;
set local role anon;
select pg_temp.falla($q$select crm.citas_clientes_fn(current_date,current_date)$q$,'42501');
reset role;
select 'PASS: listas G4b/pendientes, cursor Citas, espejo, frontera Lima, bandera y roles excluidos';
