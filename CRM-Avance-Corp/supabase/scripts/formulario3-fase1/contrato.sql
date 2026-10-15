\set ON_ERROR_STOP on
begin;
\ir fixtures.sql
create temporary table comprobaciones(nombre text);
create function pg_temp.exigir(v boolean, nombre text) returns void language plpgsql as $$
begin
  if v is distinct from true then raise exception 'FAIL: %',nombre; end if;
  insert into comprobaciones values(nombre);
end;
$$;

-- Todos los caminos pasan por la ACL real del importador.
create function pg_temp.importar(p jsonb) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  execute 'set local role service_role';
  r := crm.importar_lead_fn(p);
  execute 'reset role';
  return r;
exception when others then
  execute 'reset role';
  raise;
end;
$$;

do $contrato$
declare
  p jsonb := '{"fila":2,"nombre_completo":"Prueba contrato","telefono":"982000001","origen":"formulario","monto_estimado":5000,"moneda":"PEN"}';
  r jsonb; r2 jsonb; l uuid; l2 uuid; datos jsonb; antes jsonb;
  perfil uuid := 'f3200000-0000-0000-0000-000000000001';
  persona uuid; actividad uuid; tarea uuid; valor jsonb;
  propietario uuid := 'f3000000-0000-0000-0000-000000000001';
begin
  -- La puerta real se invoca como service_role, como lo hace el Edge.
  r := pg_temp.importar(p);
  r2 := pg_temp.importar(p || '{"telefono":"982000002","campania_origen":" FORMULARIO 3 "}');
  l := (r->>'lead_id')::uuid; l2 := (r2->>'lead_id')::uuid;
  perform pg_temp.exigir(r->>'resultado'='importado' and r2->>'resultado'='importado','altas legacy y campaña');
  perform pg_temp.exigir((select campania_origen is null from crm.leads where id=l),'legacy mantiene NULL');
  perform pg_temp.exigir((select campania_origen='Formulario 3' from crm.leads where id=l2),'campaña canónica persistida en alta');
  perform pg_temp.exigir((select not alta_manual and creado_por is null and vendedor_id is null and asignado_supervisor_id is null and origen='formulario' from crm.leads where id=l2),'misma procedencia automática y cola por repartir');
  perform pg_temp.exigir((select to_jsonb(a)-array['id','telefono','campania_origen'] = to_jsonb(b)-array['id','telefono','campania_origen'] from crm.leads a cross join crm.leads b where a.id=l and b.id=l2),'paridad de todas las demás columnas del alta');
  select to_jsonb(x) into antes from crm.leads x where id=l2;
  r := pg_temp.importar(p || '{"fila":99,"telefono":"982000002","campania_origen":"Otra campaña"}');
  perform pg_temp.exigir(r->>'resultado'='duplicado','reintento/campaña diferente sigue duplicado');
  perform pg_temp.exigir((select to_jsonb(x)=antes from crm.leads x where id=l2),'duplicado no modifica origen, campaña, dueño ni fila original');

  -- La misma regla de asignación abre episodios FORMULARIO automáticos.
  r := pg_temp.importar(p || jsonb_build_object('telefono','982000003','vendedor_id',propietario));
  r2 := pg_temp.importar(p || jsonb_build_object('telefono','982000004','vendedor_id',propietario,'campania_origen','Formulario 3'));
  perform pg_temp.exigir((select count(*)=2 from crm.lead_asignaciones where lead_id in ((r->>'lead_id')::uuid,(r2->>'lead_id')::uuid) and analista_id=propietario and origen='formulario' and motivo_apertura='ingreso' and finalizado_en is null),'dos altas equivalentes en el ledger de reparto');
  perform pg_temp.exigir((select to_jsonb(a)-array['id','lead_id'] = to_jsonb(b)-array['id','lead_id'] from crm.lead_asignaciones a cross join crm.lead_asignaciones b where a.lead_id=(r->>'lead_id')::uuid and b.lead_id=(r2->>'lead_id')::uuid),'episodios idénticos salvo identificadores');

  perform pg_temp.exigir((select count(*)=2 and sum(aporte_divisor)=2 and sum(aporte_numerador)=0
    from private.conversion_episodios(now()-interval '1 day',now()+interval '1 day',null,true,null,1)
    where lead_id in ((r->>'lead_id')::uuid,(r2->>'lead_id')::uuid) and tipo='recibido'),
    'mismo aporte al divisor de conversión que FORMULARIO automático');

  -- Valor explícito inválido nunca se pierde silenciosamente ni deja alta parcial.
  for valor in select x from jsonb_array_elements('["", "   ", 3, false, {}, [], "uno\ndos"]') x loop
    begin
      perform pg_temp.importar(p || jsonb_build_object('telefono','982000099','campania_origen',valor));
      raise exception 'Se aceptó campaña inválida';
    exception when sqlstate '22023' then
      perform pg_temp.exigir(true,'rechazo explícito '||valor::text);
    end;
  end loop;
  begin
    perform pg_temp.importar(p || '{"telefono":"982000099","origen":"landing","campania_origen":"Formulario 3"}');
    raise exception 'Se aceptó campaña con canal incorrecto';
  exception when sqlstate '22023' then perform pg_temp.exigir(true,'rechazo de canal incompatible'); end;
  perform pg_temp.exigir(not exists(select 1 from crm.leads where telefono='+51982000099'),'rechazos sin alta parcial');
  perform pg_temp.exigir(private.normalizar_campania_origen(to_jsonb(repeat('🌱',80)),'formulario')=repeat('🌱',80),'límite cuenta caracteres Unicode');
  begin
    perform private.normalizar_campania_origen(to_jsonb(repeat('🌱',81)),'formulario');
    raise exception 'Se aceptaron 81 caracteres';
  exception when sqlstate '22023' then perform pg_temp.exigir(true,'límite superior de campaña'); end;

  -- Una corrección privilegiada de canal conserva su contrato anterior.
  perform set_config('crm.op_privilegiada','on',true);
  update crm.leads set origen='landing' where id=l2;
  perform pg_temp.exigir((select origen='landing' and campania_origen='Formulario 3' from crm.leads where id=l2),'corrección autorizada de canal no queda bloqueada por campaña');
  perform set_config('crm.op_privilegiada','off',true);

  -- Persona reconocida con lead vivo. La campaña de origen nunca se sobrescribe.
  persona := private.inversionista_resolver('DNI','49200001',true,'prueba-formulario3');
  r := pg_temp.importar(p || '{"telefono":"982000005","dni":"49200001"}');
  l := (r->>'lead_id')::uuid;
  update crm.multiempresa_flags set activo=true where nombre='resolver_en_puertas';
  p := p || '{"telefono":"982000006","dni":"49200001"}';
  r := pg_temp.importar(p);
  actividad := (r->'reingreso'->>'actividad_id')::uuid;
  perform pg_temp.exigir(r->>'resultado'='ya_cliente' and actividad is not null,'persona reconocida usa reingreso');
  r2 := pg_temp.importar(p || '{"fila":100,"campania_origen":null}');
  perform pg_temp.exigir(r2->'reingreso'->>'repetido'='true' and (r2->'reingreso'->>'actividad_id')::uuid=actividad,'reingreso legacy sigue idempotente con fila movida y campaña nula');
  r := pg_temp.importar(p || '{"campania_origen":"Formulario 3"}');
  actividad := (r->'reingreso'->>'actividad_id')::uuid;
  perform pg_temp.exigir((select metadata->'datos'->>'campania_origen'='Formulario 3' and detalle like '%Formulario 3%' from crm.actividades where id=actividad),'allowlist y detalle conservan campaña');
  r2 := pg_temp.importar(p || '{"fila":101,"campania_origen":"Formulario 3"}');
  perform pg_temp.exigir(r2->'reingreso'->>'repetido'='true' and (r2->'reingreso'->>'actividad_id')::uuid=actividad,'mismo reingreso de campaña no duplica nota');
  r := pg_temp.importar(p || '{"campania_origen":"Campaña distinta"}');
  perform pg_temp.exigir((select count(*)=3 from crm.actividades where lead_id=l and metadata->>'evento'='reingreso'),'campañas distintas registran contactos distintos');
  perform pg_temp.exigir((select campania_origen is null and origen='formulario' from crm.leads where id=l),'el reingreso conserva campaña de origen anterior');

  -- Cliente sin ficha viva: nota y tarea, huella al final aun con nota larga.
  perform set_config('crm.op_privilegiada','on',true);
  insert into auth.users(id) values(perfil);
  insert into public.perfiles(id,nombre_completo,rol,tipo_documento,dni,correo,asesor_perfil_id,activo)
  values(perfil,'Prueba cliente','cliente','DNI','49200002','prueba-formulario3@example.invalid',propietario,true);
  persona := private.inversionista_resolver('DNI','49200002',true,'prueba-formulario3');
  update crm.inversionistas set perfil_id=perfil where id=persona;
  p := p || jsonb_build_object('dni','49200002','telefono','982000007','nota',repeat('x',2200));
  r := pg_temp.importar(p);
  actividad := (r->'solicitud'->>'actividad_id')::uuid;
  r2 := pg_temp.importar(p || '{"fila":102,"campania_origen":null}');
  perform pg_temp.exigir(r2->'solicitud'->>'repetido'='true' and (r2->'solicitud'->>'actividad_id')::uuid=actividad,'solicitud legacy conserva huella de siete días');
  r := pg_temp.importar(p || '{"campania_origen":"Formulario 3"}');
  actividad := (r->'solicitud'->>'actividad_id')::uuid; tarea := (r->'solicitud'->>'tarea_id')::uuid;
  perform pg_temp.exigir(r->>'resultado'='ya_cliente' and actividad is not null and tarea is not null,'cliente reconocido produce nota y tarea');
  perform pg_temp.exigir((select detalle like '%campaña: Formulario 3%' and detalle ~ ' · Ref: [a-f0-9]{32}$' and char_length(detalle)<=2000 from crm.actividades_cliente where id=actividad),'campaña visible y huella intacta tras truncar nota');
  perform pg_temp.exigir((select nota like '%campaña: Formulario 3%' and vendedor_id=propietario from crm.tareas where id=tarea),'tarea conserva campaña y analista');
  r2 := pg_temp.importar(p || '{"fila":103,"campania_origen":"Formulario 3"}');
  perform pg_temp.exigir(r2->'solicitud'->>'repetido'='true','reintento de cliente marcado repetido');
  perform pg_temp.exigir((select count(*)=2 from crm.actividades_cliente where cliente_id=perfil) and (select count(*)=2 from crm.tareas where perfil_id=perfil),'solo una nota y tarea por solicitud distinta');
  r := pg_temp.importar(p || '{"campania_origen":"Campaña distinta"}');
  perform pg_temp.exigir((select count(*)=3 from crm.actividades_cliente where cliente_id=perfil) and (select count(*)=3 from crm.tareas where perfil_id=perfil),'otra campaña genera otra solicitud, sin duplicar cliente');
  perform pg_temp.exigir(not exists(select 1 from crm.leads where dni='49200002'),'cliente existente no se convierte en otro lead');
end;
$contrato$;
select count(*) as comprobaciones_aprobadas from comprobaciones;
rollback;
