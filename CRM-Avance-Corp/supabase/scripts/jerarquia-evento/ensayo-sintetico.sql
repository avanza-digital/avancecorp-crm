-- SOLO banco Docker vacío con esquema a paridad; ejecutar como postgres con psql -X -v ON_ERROR_STOP=1.
-- Ningún trigger se apaga. Todo se deshace, incluidos los fixtures de public y auth: ROLLBACK.
-- Normal: aplicar migración con huellas medidas, luego ejecutar este archivo.
-- Control SIN migración: en otra conexión al banco original (o tras la reversa), ejecutar:
--   PGOPTIONS='-c ensayo.jerarquia_sin_migracion=on' psql <conexión DEL BANCO> -X -v ON_ERROR_STOP=1 -f <este archivo>
-- Ese modo exige ausencia de los objetos nuevos y solo ejecuta (c0): dos traslados y CERO eventos.
-- No se permite activar el control negativo sobre una instalación migrada.
begin isolation level read committed;
set local lock_timeout = '10s';
set local statement_timeout = '180s';

do $guardia$
declare
  v_sin_migracion boolean := coalesce(current_setting('ensayo.jerarquia_sin_migracion', true), '') = 'on';
begin
  if exists (select 1 from public.contratos) then
    raise exception 'ENSAYO: la base tiene contratos; solo se permite banco LOCAL vacío de Docker';
  end if;
  if current_user <> 'postgres' or current_setting('session_replication_role') <> 'origin' then
    raise exception 'ENSAYO: requiere postgres y triggers encendidos';
  end if;
  if ((select md5(pg_get_functiondef(to_regprocedure('crm.fijar_membresia_activa_fn(uuid,boolean,uuid,timestamptz,uuid)'))))
      = '9be9925a221e64119b21e0f6a299ceb9') is not true
     or ((select md5(pg_get_functiondef(to_regprocedure('crm.facturacion_diaria_fn(date)'))))
      = '4b11e1da336f2f296c81f064ce30e35b') is not true then
    raise exception 'ENSAYO: baja o Facturación no coinciden con los cuerpos vivos';
  end if;
  if v_sin_migracion then
    if to_regprocedure('private.actor_sistema_eventos()') is not null
       or to_regprocedure('private.trg_equipo_evento_jerarquia()') is not null
       or exists (select 1 from pg_trigger where tgrelid = 'crm.equipo'::regclass
         and tgname in ('trg_equipo_evento_jerarquia_insert', 'trg_equipo_evento_jerarquia_update')) then
      raise exception 'ENSAYO c0: quitar la migración con su reversa; no se deshabilitan triggers';
    end if;
    if md5(pg_get_functiondef(to_regprocedure('crm.actualizar_jerarquia_usuario_fn(uuid,uuid,timestamptz,uuid)')))
         is distinct from '79c43d9888cf0d54b92eb26e8b46c3af'
       or md5(pg_get_functiondef(to_regprocedure('crm.registrar_vendedor_usuario_fn(uuid,text,text,text,text,text,text,text,uuid,uuid)')))
         is distinct from 'c3b73f85fdd791534d6edcc5015b14ff' then
      raise exception 'ENSAYO c0: se requieren las dos RPC originales';
    end if;
  elsif to_regprocedure('private.actor_sistema_eventos()') is null
     or to_regprocedure('private.trg_equipo_evento_jerarquia()') is null
     or (select count(*) from pg_trigger where tgrelid = 'crm.equipo'::regclass
       and tgname in ('trg_equipo_evento_jerarquia_insert', 'trg_equipo_evento_jerarquia_update')
       and tgenabled = 'O') <> 2 then
    raise exception 'ENSAYO: falta aplicar la migración completa con sus huellas medidas';
  end if;
end $guardia$;

create temporary table jerarquia_casos (
  numero integer generated always as identity,
  caso text not null, correcto boolean not null
) on commit drop;
create function pg_temp.jerarquia_comprobar(p_caso text, p_correcto boolean) returns void
language plpgsql as $prueba$
begin
  insert into pg_temp.jerarquia_casos(caso, correcto) values (p_caso, p_correcto is true);
  raise notice '%: %', case when p_correcto is true then 'PASS' else 'FAIL' end, p_caso;
end $prueba$;

do $ensayo$
declare
  v_sin_migracion boolean := coalesce(current_setting('ensayo.jerarquia_sin_migracion', true), '') = 'on';
  v_gerencia uuid := gen_random_uuid();
  v_s1 uuid := gen_random_uuid();
  v_s2 uuid := gen_random_uuid();
  v_s3 uuid := gen_random_uuid();
  v_a uuid := gen_random_uuid();
  v_b uuid := gen_random_uuid();
  v_rpc uuid := gen_random_uuid();
  v_directo uuid := gen_random_uuid();
  v_purga uuid := gen_random_uuid();
  v_hijo_purga uuid := gen_random_uuid();
  v_sin_supervisor uuid := gen_random_uuid();
  v_alta uuid := gen_random_uuid();
  v_alta_existente uuid := gen_random_uuid();
  v_cliente uuid := gen_random_uuid();
  v_venta_antes uuid := gen_random_uuid();
  v_venta_despues uuid := gen_random_uuid();
  v_idem_a uuid := gen_random_uuid();
  v_idem_b uuid := gen_random_uuid();
  v_idem_b2 uuid := gen_random_uuid();
  v_idem_c uuid := gen_random_uuid();
  v_idem_guc uuid := gen_random_uuid();
  v_sistema uuid;
  v_base bigint;
  v_version timestamptz;
  v_equipo_antes jsonb;
  v_respuesta jsonb;
  v_repeticion jsonb;
  v_fila record;
  v_hoy date := (clock_timestamp() at time zone 'America/Lima')::date;
  v_ayer date;
  v_error boolean := false;
  v_restriccion text;
begin
  v_ayer := v_hoy - 1;
  perform set_config('request.jwt.claims', '{}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('crm.evento_jerarquia_idempotencia', '', true);
  perform set_config('crm.evento_jerarquia_objetivo', '', true);
  perform set_config('crm.op_privilegiada', 'on', true);
  for v_fila in select * from (values
    (v_gerencia, 'GERENCIA', 'admin'),
    (v_s1, 'SUPERVISOR SALIENTE', 'comercial'), (v_s2, 'SUPERVISOR REEMPLAZO', 'comercial'),
    (v_s3, 'SUPERVISOR OTRO', 'comercial'), (v_a, 'ANALISTA A', 'comercial'),
    (v_b, 'ANALISTA B', 'comercial'), (v_rpc, 'ANALISTA RPC', 'comercial'),
    (v_directo, 'ANALISTA DIRECTO', 'comercial'), (v_purga, 'SUPERVISOR A PURGAR', 'comercial'),
    (v_hijo_purga, 'SUPERVISOR HIJO', 'comercial'), (v_sin_supervisor, 'SIN SUPERVISOR', 'comercial'),
    (v_alta_existente, 'ALTA EXISTENTE', 'comercial'), (v_cliente, 'CLIENTE', 'cliente')
  ) personas(id, nombre, rol) loop
    insert into auth.users(id, email) values (v_fila.id, v_fila.id::text || '@jerarquia-ensayo.test');
    insert into public.perfiles(id, nombre_completo, correo, rol, activo, tipo_documento, dni,
      debe_cambiar_password, titular_distinto, titular_distinto_usd)
    values (v_fila.id, 'ENSAYO JERARQUIA ' || v_fila.nombre, v_fila.id::text || '@jerarquia-ensayo.test',
      v_fila.rol, true, 'DNI', case when v_fila.id = v_alta_existente then '99817002' end,
      false, false, false);
  end loop;
  insert into crm.equipo(perfil_id, rol_crm, activo) values
    (v_gerencia, 'gerencia', true), (v_s1, 'supervisor', true),
    (v_s2, 'supervisor', true), (v_s3, 'supervisor', true), (v_purga, 'supervisor', true);
  insert into crm.equipo(perfil_id, rol_crm, supervisor_id, activo) values
    (v_a, 'vendedor', v_s1, true), (v_b, 'vendedor', v_s1, true),
    (v_rpc, 'vendedor', v_s3, true), (v_directo, 'vendedor', v_s3, true),
    -- Un SUPERVISOR subordinado admite quedar sin supervisor; un vendedor activo no lo admite
    -- por la guarda existente. La purga no debe esquivar esa regla ajena a esta migración.
    (v_hijo_purga, 'supervisor', v_purga, true);
  perform set_config('crm.op_privilegiada', '', true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_gerencia, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_gerencia::text, true);

  if v_sin_migracion then
    select coalesce(max(id), 0) into v_base from crm.usuario_eventos;
    select actualizado_en into v_version from crm.equipo where perfil_id = v_s1;
    set local role authenticated;
    perform crm.fijar_membresia_activa_fn(v_s1, false, v_s2, v_version, v_idem_c);
    reset role;
    perform pg_temp.jerarquia_comprobar('(c0) SIN migración: dos subordinados trasladados y cero eventos de jerarquía',
      (select count(*) = 2 from crm.equipo where perfil_id in (v_a, v_b) and supervisor_id = v_s2)
      and (select activo is false from crm.equipo where perfil_id = v_s1)
      and (select count(*) = 0 from crm.usuario_eventos where id > v_base and accion = 'jerarquia_actualizada'));
    return;
  end if;
  v_sistema := private.actor_sistema_eventos();
  perform pg_temp.jerarquia_comprobar('Autor sistema: UUID fijo sin perfil artificial',
    v_sistema = 'f6d2941b-2e93-4c81-9a27-0c5e786b104d'::uuid
    and not exists (select 1 from public.perfiles where id = v_sistema));
  perform pg_temp.jerarquia_comprobar('Siembra: INSERT con supervisor produce exactamente cinco eventos automáticos',
    (select count(*) = 5 and bool_and(actor_id = v_sistema and detalle->>'via' = 'automatica'
      and detalle->'supervisor_anterior' = 'null'::jsonb and octet_length(detalle::text) <= 4096)
     from crm.usuario_eventos where objetivo_id in (v_a, v_b, v_rpc, v_directo, v_hijo_purga)
       and accion = 'jerarquia_actualizada'));

  -- (a) Se reintenta con la versión ANTIGUA: la búsqueda por evento precede al rechazo de versión.
  select coalesce(max(id), 0) into v_base from crm.usuario_eventos;
  select actualizado_en into v_version from crm.equipo where perfil_id = v_rpc;
  set local role authenticated;
  v_respuesta := crm.actualizar_jerarquia_usuario_fn(v_rpc, v_s2, v_version, v_idem_a);
  v_repeticion := crm.actualizar_jerarquia_usuario_fn(v_rpc, v_s2, v_version, v_idem_a);
  reset role;
  perform pg_temp.jerarquia_comprobar('(a) RPC: un evento con actor e idempotencia originales',
    (select count(*) = 1 and bool_and(actor_id = v_gerencia and idempotencia = v_idem_a
      and objetivo_id = v_rpc and detalle = jsonb_build_object(
        'supervisor_anterior', v_s3, 'supervisor_nuevo', v_s2, 'via', 'rpc'))
     from crm.usuario_eventos where id > v_base and accion = 'jerarquia_actualizada'));
  perform pg_temp.jerarquia_comprobar('(a) repetición: mismo resultado salvo indicador idempotente, sin duplicados',
    v_respuesta - 'idempotente' = v_repeticion - 'idempotente'
    and v_respuesta->'idempotente' = 'false'::jsonb and v_repeticion->'idempotente' = 'true'::jsonb);
  perform pg_temp.jerarquia_comprobar('(a) ambos GUC consumidos',
    current_setting('crm.evento_jerarquia_idempotencia', true) = ''
    and current_setting('crm.evento_jerarquia_objetivo', true) = '');

  -- (b) Auth solo id/email, luego metadato de origen requerido por la RPC viva.
  insert into auth.users(id, email) values (v_alta, v_alta::text || '@jerarquia-ensayo.test');
  update auth.users set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"origen_app":"crm"}'::jsonb
    where id in (v_alta, v_alta_existente);
  select coalesce(max(id), 0) into v_base from crm.usuario_eventos;
  set local role authenticated;
  v_respuesta := crm.registrar_vendedor_usuario_fn(v_alta, v_alta::text || '@jerarquia-ensayo.test',
    'ENSAYO ALTA NUEVA', 'DNI', '99817001', null, null, null, v_s3, v_idem_b);
  v_repeticion := crm.registrar_vendedor_usuario_fn(v_alta, v_alta::text || '@jerarquia-ensayo.test',
    'ENSAYO ALTA NUEVA', 'DNI', '99817001', null, null, null, v_s3, v_idem_b);
  reset role;
  perform pg_temp.jerarquia_comprobar('(b) alta nueva: 4 eventos totales y una sola jerarquía',
    (select count(*) = 4 and count(distinct accion) = 4
      and count(*) filter (where accion = 'jerarquia_actualizada') = 1
      and bool_and(actor_id = v_gerencia and objetivo_id = v_alta and idempotencia = v_idem_b)
     from crm.usuario_eventos where id > v_base)
    and exists (select 1 from crm.usuario_eventos where id > v_base and accion = 'jerarquia_actualizada'
      and detalle = jsonb_build_object('supervisor_anterior', null, 'supervisor_nuevo', v_s3, 'via', 'rpc')));
  perform pg_temp.jerarquia_comprobar('(b) repetición del alta nueva conserva respuesta y no duplica',
    v_respuesta - 'idempotente' = v_repeticion - 'idempotente'
    and v_respuesta->'idempotente' = 'false'::jsonb and v_repeticion->'idempotente' = 'true'::jsonb);
  select coalesce(max(id), 0) into v_base from crm.usuario_eventos;
  set local role authenticated;
  v_respuesta := crm.registrar_vendedor_usuario_fn(v_alta_existente, v_alta_existente::text || '@jerarquia-ensayo.test',
    'ENSAYO ALTA EXISTENTE', 'DNI', '99817002', null, null, null, v_s3, v_idem_b2);
  v_repeticion := crm.registrar_vendedor_usuario_fn(v_alta_existente, v_alta_existente::text || '@jerarquia-ensayo.test',
    'ENSAYO ALTA EXISTENTE', 'DNI', '99817002', null, null, null, v_s3, v_idem_b2);
  reset role;
  perform pg_temp.jerarquia_comprobar('(b) perfil existente: 3 eventos, una jerarquía, repetición conservada',
    (select count(*) = 3 and count(distinct accion) = 3
      and count(*) filter (where accion = 'jerarquia_actualizada') = 1
      and bool_and(actor_id = v_gerencia and objetivo_id = v_alta_existente and idempotencia = v_idem_b2)
     from crm.usuario_eventos where id > v_base)
    and v_respuesta - 'idempotente' = v_repeticion - 'idempotente'
    and v_respuesta->'idempotente' = 'false'::jsonb and v_repeticion->'idempotente' = 'true'::jsonb);

  -- (j) Historia sintética: el equipo nació ANTEAYER. Solo se fecha su evento de siembra,
  -- nunca el evento real de la baja. Facturación es diaria: el día del cambio ya es del nuevo.
  update crm.usuario_eventos set creado_en = (v_hoy - 2)::timestamp at time zone 'America/Lima'
    where objetivo_id in (v_a, v_b) and accion = 'jerarquia_actualizada';
  perform set_config('crm.op_privilegiada', 'on', true);
  update public.perfiles set asesor_perfil_id = v_a where id = v_cliente;
  insert into public.contratos(id, numero_contrato, cliente_id, capital, moneda, tasa_anual,
    modalidad, tipo_interes, fecha_inicio, fecha_vencimiento, estado, categoria,
    creado_por, analista_cierre_id, es_demo)
  values (v_venta_antes, 'JERARQUIA-' || v_venta_antes::text, v_cliente, 1000, 'PEN', 15,
    'mensual', 'simple', v_ayer, (v_ayer + interval '12 months')::date,
    'activo', 'nuevo', v_a, v_a, false);
  perform set_config('crm.op_privilegiada', '', true);

  -- (c) La baja original NO se reescribe: debe registrar dos eventos nuevos por su UPDATE masivo.
  select coalesce(max(id), 0) into v_base from crm.usuario_eventos;
  select actualizado_en into v_version from crm.equipo where perfil_id = v_s1;
  set local role authenticated;
  perform crm.fijar_membresia_activa_fn(v_s1, false, v_s2, v_version, v_idem_c);
  reset role;
  perform pg_temp.jerarquia_comprobar('(c) baja: dos subordinados activos cambiados y supervisor desactivado',
    (select count(*) = 2 from crm.equipo where perfil_id in (v_a, v_b) and supervisor_id = v_s2 and activo)
    and (select activo is false from crm.equipo where perfil_id = v_s1));
  perform pg_temp.jerarquia_comprobar('(c) baja: dos eventos, autor Gerencia, vía automática e idempotencias distintas',
    (select count(*) = 2 and count(distinct objetivo_id) = 2 and count(distinct idempotencia) = 2
      and bool_and(actor_id = v_gerencia and objetivo_id in (v_a, v_b) and idempotencia <> v_idem_c
        and detalle = jsonb_build_object('supervisor_anterior', v_s1, 'supervisor_nuevo', v_s2, 'via', 'automatica'))
     from crm.usuario_eventos where id > v_base and accion = 'jerarquia_actualizada'));

  perform set_config('crm.op_privilegiada', 'on', true);
  insert into public.contratos(id, numero_contrato, cliente_id, capital, moneda, tasa_anual,
    modalidad, tipo_interes, fecha_inicio, fecha_vencimiento, estado, categoria,
    creado_por, analista_cierre_id, es_demo)
  values (v_venta_despues, 'JERARQUIA-' || v_venta_despues::text, v_cliente, 2000, 'PEN', 15,
    'mensual', 'simple', v_hoy, (v_hoy + interval '12 months')::date,
    'activo', 'nuevo', v_a, v_a, false);
  perform set_config('crm.op_privilegiada', '', true);
  -- Asegurar que ningún candado diferido de los fixtures queda oculto por ROLLBACK.
  set constraints all immediate;
  set constraints all deferred;
  set local role authenticated;
  select coalesce(jsonb_agg(to_jsonb(f)), '[]'::jsonb) into v_respuesta
    from crm.facturacion_diaria_fn(date_trunc('month', v_ayer)::date) f where analista_id = v_a and dia = v_ayer;
  select coalesce(jsonb_agg(to_jsonb(f)), '[]'::jsonb) into v_repeticion
    from crm.facturacion_diaria_fn(date_trunc('month', v_hoy)::date) f where analista_id = v_a and dia = v_hoy;
  reset role;
  perform pg_temp.jerarquia_comprobar('(j) venta anterior conserva supervisor saliente, S/ 1000 y una operación',
    jsonb_array_length(v_respuesta) = 1 and v_respuesta->0->>'supervisor_id' = v_s1::text
    and v_respuesta->0->>'supervisor_nombre' = 'ENSAYO JERARQUIA SUPERVISOR SALIENTE'
    and (v_respuesta->0->>'capital')::numeric = 1000 and (v_respuesta->0->>'operaciones')::integer = 1);
  perform pg_temp.jerarquia_comprobar('(j) venta posterior queda con reemplazo, S/ 2000 y una operación',
    jsonb_array_length(v_repeticion) = 1 and v_repeticion->0->>'supervisor_id' = v_s2::text
    and v_repeticion->0->>'supervisor_nombre' = 'ENSAYO JERARQUIA SUPERVISOR REEMPLAZO'
    and (v_repeticion->0->>'capital')::numeric = 2000 and (v_repeticion->0->>'operaciones')::integer = 1);

  -- (d)-(h) Contexto realmente sin sesión: limpiar ambas fuentes que usa auth.uid().
  perform set_config('request.jwt.claims', '{}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform pg_temp.jerarquia_comprobar('(d) no hay auth.uid()', auth.uid() is null);
  select coalesce(max(id), 0) into v_base from crm.usuario_eventos;
  update crm.equipo set supervisor_id = v_s2 where perfil_id = v_directo;
  perform pg_temp.jerarquia_comprobar('(d) UPDATE directo sin sesión: un evento de sistema',
    (select count(*) = 1 and bool_and(actor_id = v_sistema and objetivo_id = v_directo
      and detalle = jsonb_build_object('supervisor_anterior', v_s3, 'supervisor_nuevo', v_s2, 'via', 'automatica'))
     from crm.usuario_eventos where id > v_base and accion = 'jerarquia_actualizada'));
  select coalesce(max(id), 0) into v_base from crm.usuario_eventos;
  update crm.equipo set supervisor_id = v_s2 where perfil_id = v_directo;
  perform pg_temp.jerarquia_comprobar('(e) UPDATE al mismo supervisor: cero eventos',
    not exists (select 1 from crm.usuario_eventos where id > v_base));
  insert into crm.equipo(perfil_id, rol_crm, activo) values (v_sin_supervisor, 'supervisor', true);
  perform pg_temp.jerarquia_comprobar('(f) INSERT sin supervisor: cero eventos',
    not exists (select 1 from crm.usuario_eventos where id > v_base));

  perform crm.purgar_membresia_crm(v_purga, 'ENSAYO local de cascada SET NULL; se deshace toda la transacción.');
  perform pg_temp.jerarquia_comprobar('(g) purga: supervisor eliminado y FK deja NULL en el subordinado',
    not exists (select 1 from crm.equipo where perfil_id = v_purga)
    and (select supervisor_id is null from crm.equipo where perfil_id = v_hijo_purga));
  perform pg_temp.jerarquia_comprobar('(g) purga: evento sistema con supervisor_nuevo NULL explícito',
    (select count(*) = 1 and bool_and(actor_id = v_sistema and objetivo_id = v_hijo_purga
      and detalle = jsonb_build_object('supervisor_anterior', v_purga, 'supervisor_nuevo', null, 'via', 'automatica'))
     from crm.usuario_eventos where id > v_base and accion = 'jerarquia_actualizada'));

  select coalesce(max(id), 0) into v_base from crm.usuario_eventos;
  update crm.equipo set supervisor_id = v_s3 where perfil_id = v_directo;
  update crm.equipo set supervisor_id = v_s2 where perfil_id = v_directo;
  perform pg_temp.jerarquia_comprobar('(h) dos cambios de una fila en una transacción: dos eventos completos',
    (select count(*) = 2 and count(distinct idempotencia) = 2
      and bool_and(actor_id = v_sistema and objetivo_id = v_directo)
      and jsonb_agg(detalle order by id) = jsonb_build_array(
        jsonb_build_object('supervisor_anterior', v_s2, 'supervisor_nuevo', v_s3, 'via', 'automatica'),
        jsonb_build_object('supervisor_anterior', v_s3, 'supervisor_nuevo', v_s2, 'via', 'automatica'))
     from crm.usuario_eventos where id > v_base and accion = 'jerarquia_actualizada'));

  -- (i) Forzar el INSERT del trigger a chocar con (a). Es una violación REAL de la UNIQUE,
  -- sin cambiar la función ni su detalle. El subbloque debe revertir también equipo y versión.
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_gerencia, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_gerencia::text, true);
  select to_jsonb(e) into v_equipo_antes from crm.equipo e where perfil_id = v_rpc;
  select coalesce(max(id), 0) into v_base from crm.usuario_eventos;
  begin
    perform set_config('crm.evento_jerarquia_idempotencia', v_idem_a::text, true);
    perform set_config('crm.evento_jerarquia_objetivo', v_rpc::text, true);
    update crm.equipo set supervisor_id = v_s3 where perfil_id = v_rpc;
  exception when unique_violation then
    get stacked diagnostics v_restriccion = constraint_name;
    v_error := v_restriccion = 'usuario_eventos_idempotencia_unica';
  end;
  perform pg_temp.jerarquia_comprobar('(i) falla el evento: se revierte toda la fila de equipo y no queda evento parcial',
    v_error and v_equipo_antes = (select to_jsonb(e) from crm.equipo e where perfil_id = v_rpc)
    and not exists (select 1 from crm.usuario_eventos where id > v_base));
  perform set_config('crm.evento_jerarquia_idempotencia', '', true);
  perform set_config('crm.evento_jerarquia_objetivo', '', true);

  -- Contrato adicional de los GUC: la primera fila NO es el objetivo; el siguiente cambio sí.
  perform set_config('crm.evento_jerarquia_idempotencia', v_idem_guc::text, true);
  perform set_config('crm.evento_jerarquia_objetivo', v_rpc::text, true);
  select coalesce(max(id), 0) into v_base from crm.usuario_eventos;
  update crm.equipo set supervisor_id = v_s3 where perfil_id = v_directo;
  perform pg_temp.jerarquia_comprobar('GUC: una fila distinta no consume ni usa la idempotencia del objetivo',
    current_setting('crm.evento_jerarquia_idempotencia') = v_idem_guc::text
    and current_setting('crm.evento_jerarquia_objetivo') = v_rpc::text
    and (select count(*) = 1 and bool_and(idempotencia <> v_idem_guc and detalle->>'via' = 'automatica')
      from crm.usuario_eventos where id > v_base and accion = 'jerarquia_actualizada'));
  update crm.equipo set supervisor_id = v_s3 where perfil_id = v_rpc;
  update crm.equipo set supervisor_id = v_s2 where perfil_id = v_rpc;
  perform pg_temp.jerarquia_comprobar('GUC: solo un cambio usa el recibo; el segundo vuelve a automático',
    (select count(*) = 3 and count(distinct idempotencia) = 3
      and count(*) filter (where idempotencia = v_idem_guc and objetivo_id = v_rpc and detalle->>'via' = 'rpc') = 1
      and count(*) filter (where detalle->>'via' = 'automatica') = 2
     from crm.usuario_eventos where id > v_base and accion = 'jerarquia_actualizada')
    and current_setting('crm.evento_jerarquia_idempotencia') = ''
    and current_setting('crm.evento_jerarquia_objetivo') = '');
end $ensayo$;

set constraints all immediate;
table pg_temp.jerarquia_casos;
do $resultado$
begin
  if exists (select 1 from pg_temp.jerarquia_casos where not correcto) then
    raise exception 'FAIL: % de % casos; deshacer con ROLLBACK',
      (select count(*) from pg_temp.jerarquia_casos where not correcto),
      (select count(*) from pg_temp.jerarquia_casos);
  end if;
  raise notice 'PASS: % casos; todos los datos se deshacen', (select count(*) from pg_temp.jerarquia_casos);
end $resultado$;
rollback;
