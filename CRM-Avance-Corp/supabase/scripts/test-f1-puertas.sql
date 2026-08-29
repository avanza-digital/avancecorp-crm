-- ACEPTACION de la Fase 1 del P-055 - lo que `test-rls.mjs` no puede probar.
--
-- POR QUE UN ARCHIVO APARTE Y NO CASOS EN EL GATE:
--   1. TRUNCATE, REFERENCES, TRIGGER y MAINTAIN no se pueden ejercitar por
--      PostgREST: no existe una peticion HTTP que los invoque. Solo se ven en
--      el catalogo.
--   2. Comprobar "anon NO puede ejecutar esta funcion" LLAMANDOLA es peligroso
--      en esta plataforma: en la imagen 17.6.1.105 -la que corre el branch-
--      llamar a una funcion sin permiso de EXECUTE revienta el proceso de
--      Postgres en vez de dar "permission denied" (reproducido 4 veces el
--      20/08). Asi que aqui se mira el ACL, que es la misma verdad sin el
--      riesgo de tumbar el banco a mitad del gate.
--
-- COMO SE USA (en el branch, DESPUES de sembrar y de aplicar las 4 migraciones):
--   supabase db query --linked --file supabase/scripts/test-f1-puertas.sql
--
-- No deja nada: todo corre dentro de un bloque que SIEMPRE termina en error, y
-- el resumen viaja en el propio mensaje. Si algo falla, el mensaje dice que.
--
-- SIN DATOS NO HAY PRUEBA: si el banco no tiene un contrato con cuotas o un
-- co-titular, este archivo FALLA en vez de pasar en verde. Es deliberado - un
-- gate que se salta las sondas por falta de datos es peor que no tenerlo (el
-- precedente completo esta en MIGRACIONES.md, "el seed va ANTES de aplicar").

do $aceptacion$
declare
  v_log     text := 'ACEPTACION F1';
  v_paso    text;
  v_ct      uuid;
  v_id      uuid;
  v_antes   bigint;
  v_despues bigint;
  v_colada  boolean;
  v_n       int;
begin
  -- -- 1. Los auditores estan, y el WHEN del de cuotas sigue vivo -----------
  v_paso := 'auditores';
  select count(*) into v_n
  from pg_catalog.pg_trigger t
  where not t.tgisinternal and t.tgenabled = 'O'
    and ((t.tgrelid = 'public.contrato_titulares'::regclass and t.tgname = 'trg_audit_contrato_titulares' and t.tgtype = 29)
      or (t.tgrelid = 'crm.actividades_cliente'::regclass  and t.tgname = 'trg_audit_actividades_cliente' and t.tgtype = 29)
      or (t.tgrelid = 'crm.actividades'::regclass          and t.tgname = 'trg_audit_actividades_cambio_baja' and t.tgtype = 25)
      or (t.tgrelid = 'public.cronograma_pagos'::regclass  and t.tgname = 'trg_audit_cronograma_pago_alta_baja' and t.tgtype = 13));
  if v_n <> 4 then
    raise exception 'F1.1: se esperaban 4 auditores y hay %', v_n;
  end if;
  if not exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = 'public.cronograma_pagos'::regclass
      and t.tgname = 'trg_audit_cronograma_pago' and t.tgqual is not null
  ) then
    raise exception 'F1.1: el auditor de UPDATE de cuotas perdio su clausula WHEN';
  end if;
  -- Y el auditor del ALTA de la gestion del lead tampoco se toco: la Fase 1 es
  -- aditiva, no recrea ninguno de los que ya existian.
  if not exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = 'crm.actividades'::regclass
      and t.tgname = 'trg_audit_actividades' and t.tgtype = 5
  ) then
    raise exception 'F1.1: el auditor del alta de la gestion del lead ya no es AFTER INSERT';
  end if;
  v_log := v_log || ' | 1: 4 auditores + el WHEN intacto';

  -- -- 2. Los 16 guardianes anti-NaN ----------------------------------------
  v_paso := 'guardianes anti-NaN';
  select count(*) into v_n
  from pg_catalog.pg_constraint c
  where c.contype = 'c'
    and (c.conname like '%_finito'
         or c.conname in ('cronograma_pagos_monto_programado_valido',
                          'cronograma_pagos_monto_pagado_valido'))
    and c.conrelid in ('public.cronograma_pagos'::regclass,
                       'crm.cierre_mes_vendedor'::regclass,
                       'crm.ajustes_mes_cerrado'::regclass,
                       'crm.periodos_cerrados'::regclass);
  if v_n <> 16 then
    raise exception 'F1.2: se esperaban 16 guardianes y hay %', v_n;
  end if;
  v_log := v_log || ' | 2: 16 guardianes';

  -- -- 3. Las cuatro letras que la RLS no gobierna, cerradas ----------------
  v_paso := 'permisos de tabla';
  select count(*) into v_n
  from pg_catalog.pg_class c
  where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
    and (has_table_privilege('anon', c.oid, 'TRUNCATE')
      or has_table_privilege('authenticated', c.oid, 'TRUNCATE')
      or has_table_privilege('anon', c.oid, 'REFERENCES')
      or has_table_privilege('authenticated', c.oid, 'REFERENCES')
      or has_table_privilege('anon', c.oid, 'TRIGGER')
      or has_table_privilege('authenticated', c.oid, 'TRIGGER')
      or has_table_privilege('anon', c.oid, 'MAINTAIN')
      or has_table_privilege('authenticated', c.oid, 'MAINTAIN'));
  if v_n <> 0 then
    raise exception 'F1.3: quedan % tablas de public con permisos que la RLS no gobierna', v_n;
  end if;
  -- Y lo que el portal SI usa sigue en pie.
  if not has_table_privilege('authenticated', 'public.contratos', 'SELECT')
     or not has_table_privilege('anon', 'public.perfiles', 'SELECT')
     or not has_table_privilege('service_role', 'public.contratos', 'TRUNCATE') then
    raise exception 'F1.3: se llevo por delante permisos vivos';
  end if;
  v_log := v_log || ' | 3: 0 tablas con TRUNCATE/REFERENCES/TRIGGER/MAINTAIN abiertos';

  -- -- 4. Las 5 consultas de administracion: por ACL, NUNCA llamandolas -----
  v_paso := 'permisos de funcion';
  select count(*) into v_n
  from pg_catalog.pg_proc p
  where p.oid in (
      'public.admin_pagos_metricas()'::regprocedure,
      'public.admin_pagos_resumen()'::regprocedure,
      'public.dashboard_admin_metricas()'::regprocedure,
      'public.pagos_admin_metricas_globales()'::regprocedure,
      'public.pagos_admin_resumen_contratos(text,text,text,integer,integer)'::regprocedure)
    and (has_function_privilege('anon', p.oid, 'EXECUTE')
      or exists (select 1 from aclexplode(p.proacl) a
                 where a.grantee = 0 and a.privilege_type = 'EXECUTE'));
  if v_n <> 0 then
    raise exception 'F1.3: % consultas de administracion siguen abiertas a anon o a PUBLIC', v_n;
  end if;
  select count(*) into v_n
  from pg_catalog.pg_proc p
  where p.oid in (
      'public.admin_pagos_metricas()'::regprocedure,
      'public.admin_pagos_resumen()'::regprocedure,
      'public.dashboard_admin_metricas()'::regprocedure,
      'public.pagos_admin_metricas_globales()'::regprocedure,
      'public.pagos_admin_resumen_contratos(text,text,text,integer,integer)'::regprocedure)
    and has_function_privilege('authenticated', p.oid, 'EXECUTE')
    and has_function_privilege('service_role', p.oid, 'EXECUTE');
  if v_n <> 5 then
    raise exception 'F1.3: las pantallas de administracion perdieron acceso (solo % de 5)', v_n;
  end if;
  v_log := v_log || ' | 4: las 5 RPC cerradas a anon/PUBLIC y vivas para el portal';

  -- -- 5. El cerrojo de la numeracion ---------------------------------------
  -- La cuarta migracion (el cerrojo de la numeracion automatica) SALIO de la
  -- Fase 1 el 28/08: esa numeracion no se necesita todavia. Aqui se comprueba lo
  -- contrario de antes: que `crear_contrato` sigue INTACTA.
  v_paso := 'crear_contrato sin tocar';
  if strpos((select p.prosrc from pg_catalog.pg_proc p
             where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure),
            'public.contratos.numero_contrato') > 0 then
    raise exception 'crear_contrato lleva el cerrojo: esa migracion NO es parte de la Fase 1';
  end if;
  v_log := v_log || ' | 5: crear_contrato intacta (el cerrojo quedo aparcado)';

  -- -- 6. COMPORTAMIENTO. Sin datos, esto FALLA (no pasa en verde) ----------
  v_paso := 'buscar sujetos de prueba';
  select c.id into v_ct
  from public.contratos c
  where not private.contrato_documental_congelado(c.id)
    and not private.contrato_en_eliminacion(c.id)
    and exists (select 1 from public.cronograma_pagos q where q.contrato_id = c.id)
  limit 1;
  if v_ct is null then
    raise exception 'SIN DATOS: no hay contrato libre con cuotas. Sembrar ANTES de correr esta aceptacion (MIGRACIONES.md, "el seed va ANTES de aplicar")';
  end if;

  v_paso := 'el NaN rebota en la tabla real';
  v_colada := true;
  begin
    insert into public.cronograma_pagos (contrato_id, numero_cuota, fecha_programada, monto_programado)
    values (v_ct, 99991, current_date, 'NaN'::numeric);
  exception
    when check_violation then v_colada := false;
    when others then raise exception 'sonda del NaN inconclusa: choco con otro muro (% / %)', sqlstate, sqlerrm;
  end;
  if v_colada then raise exception 'F1.2: un NaN entro en cronograma_pagos'; end if;

  v_paso := 'la cuota de cero tambien rebota';
  v_colada := true;
  begin
    insert into public.cronograma_pagos (contrato_id, numero_cuota, fecha_programada, monto_programado)
    values (v_ct, 99992, current_date, 0);
  exception
    when check_violation then v_colada := false;
    when others then raise exception 'sonda del cero inconclusa (% / %)', sqlstate, sqlerrm;
  end;
  if v_colada then raise exception 'F1.2: una cuota de 0 entro en cronograma_pagos'; end if;

  v_paso := 'una cuota valida entra Y deja rastro de alta';
  select count(*) into v_antes from public.audit_log where tabla = 'cronograma_pagos';
  insert into public.cronograma_pagos (contrato_id, numero_cuota, fecha_programada, monto_programado)
  values (v_ct, 99993, current_date, 1234.56);
  select count(*) into v_despues from public.audit_log where tabla = 'cronograma_pagos';
  if v_despues <> v_antes + 1 then
    raise exception 'F1.1: el alta de una cuota no dejo rastro (% -> %)', v_antes, v_despues;
  end if;

  v_paso := 'borrar una cuota deja rastro';
  select count(*) into v_antes from public.audit_log where tabla = 'cronograma_pagos';
  delete from public.cronograma_pagos where contrato_id = v_ct and numero_cuota = 99993;
  select count(*) into v_despues from public.audit_log where tabla = 'cronograma_pagos';
  if v_despues <> v_antes + 1 then
    raise exception 'F1.1: borrar una cuota no dejo rastro (% -> %)', v_antes, v_despues;
  end if;

  v_paso := 'el sello del cron NO ensucia la auditoria';
  select count(*) into v_antes from public.audit_log where tabla = 'cronograma_pagos';
  update public.cronograma_pagos set recordatorio_3d_enviado_en = now() where contrato_id = v_ct;
  select count(*) into v_despues from public.audit_log where tabla = 'cronograma_pagos';
  if v_despues <> v_antes then
    raise exception 'F1.1: el sello del recordatorio escribio % filas de auditoria', v_despues - v_antes;
  end if;
  v_log := v_log || ' | 6: NaN y 0 fuera, cuota valida con rastro, borrado con rastro, cron limpio';

  v_paso := 'el co-titular borrado deja rastro con su documento';
  select t.id into v_id from public.contrato_titulares t
  where not private.contrato_documental_congelado(t.contrato_id)
    and not private.contrato_en_eliminacion(t.contrato_id)
  limit 1;
  if v_id is null then
    raise exception 'SIN DATOS: no hay co-titular con contrato libre. Sembrar uno antes de correr esta aceptacion';
  end if;
  select count(*) into v_antes from public.audit_log where tabla = 'contrato_titulares';
  delete from public.contrato_titulares where id = v_id;
  select count(*) into v_despues from public.audit_log where tabla = 'contrato_titulares';
  if v_despues <> v_antes + 1 then
    raise exception 'F1.1: borrar un co-titular no dejo rastro (% -> %)', v_antes, v_despues;
  end if;
  if not exists (
    select 1 from public.audit_log a
    where a.tabla = 'contrato_titulares' and a.operacion = 'DELETE'
      and (a.data_antes->>'documento') is not null
    order by a.ts desc limit 1
  ) then
    raise exception 'F1.1: el rastro del co-titular no guarda su documento';
  end if;
  -- Y guarda el ID de la fila borrada: `log_audit_change` usa OLD.id en el
  -- DELETE, no NEW.id. Se comprueba porque un rastro sin `fila_id` obligaria a
  -- buscar por dentro del JSON.
  if not exists (
    select 1 from public.audit_log a
    where a.tabla = 'contrato_titulares' and a.operacion = 'DELETE'
      and a.fila_id = v_id::text
  ) then
    raise exception 'F1.1: el rastro del borrado no guarda el fila_id del co-titular';
  end if;
  v_log := v_log || ' | 7: co-titular borrado con su documento en el rastro';

  -- -- 7. MUTANTES: romper el arreglo para probar que la prueba sirve -------
  v_paso := 'mutante del CHECK';
  alter table public.cronograma_pagos drop constraint cronograma_pagos_monto_programado_valido;
  insert into public.cronograma_pagos (contrato_id, numero_cuota, fecha_programada, monto_programado)
  values (v_ct, 99994, current_date, 'NaN'::numeric);
  if (select count(*) from public.cronograma_pagos
      where contrato_id = v_ct and numero_cuota = 99994 and monto_programado = 'NaN'::numeric) <> 1 then
    raise exception 'MUTANTE: el NaN no entro ni sin el CHECK; la sonda no prueba lo que dice';
  end if;

  v_paso := 'mutante del trigger';
  drop trigger trg_audit_contrato_titulares on public.contrato_titulares;
  select t.id into v_id from public.contrato_titulares t
  where not private.contrato_documental_congelado(t.contrato_id)
    and not private.contrato_en_eliminacion(t.contrato_id)
  limit 1;
  if v_id is not null then
    select count(*) into v_antes from public.audit_log where tabla = 'contrato_titulares';
    delete from public.contrato_titulares where id = v_id;
    select count(*) into v_despues from public.audit_log where tabla = 'contrato_titulares';
    if v_despues <> v_antes then
      raise exception 'MUTANTE: sigue quedando rastro sin el trigger; la sonda no prueba lo que dice';
    end if;
  end if;
  v_log := v_log || ' | 8: los dos mutantes confirman que las sondas prueban lo que dicen';

  raise exception 'ACEPTACION F1 EN VERDE - TODO DESHECHO >>> %', v_log;
exception
  when others then
    if sqlerrm like 'ACEPTACION F1 EN VERDE%' then raise; end if;
    raise exception 'ACEPTACION F1 FALLA EN % >>> % (%) [%]', v_paso, sqlerrm, sqlstate, v_log;
end
$aceptacion$;
