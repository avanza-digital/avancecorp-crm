-- Oraculo del asiento «Operaciones» del Portal (2026-08-21).
--
-- Se ejecuta ENVUELTO en la migracion y dentro de una transaccion que termina
-- SIEMPRE en rollback: siembra una identidad efimera, ejerce los tres asientos
-- contra los datos REALES y no deja rastro. Ver
-- `run-test-portal-asiento-operaciones.sh`.
--
-- Regla: crear la politica no prueba nada. Cada afirmacion EJECUTA la accion.
-- Los cuatro mutantes que lo ponen rojo viven en el runner.

-- ===========================================================================
-- Referencias reales de produccion (solo lectura) + identidad efimera.
-- ===========================================================================
create temp table _ref on commit drop as
select
  (select c.id from public.contratos c where c.estado = 'activo'
     order by c.creado_en desc limit 1)                             as contrato_id,
  (select c.cliente_id from public.contratos c where c.estado = 'activo'
     order by c.creado_en desc limit 1)                             as cliente_id,
  (select cp.id from public.cronograma_pagos cp
     join public.contratos c on c.id = cp.contrato_id
    where c.estado = 'activo' and cp.estado = 'pendiente'
    order by cp.fecha_programada desc limit 1)                      as cuota_id,
  '11111111-1111-4111-8111-111111111111'::uuid                      as ops_id,
  '41544ccc-cbfd-430f-a0e7-73491e296c26'::uuid                      as gloria_id,
  '7c124080-c310-40d3-b245-794657852968'::uuid                      as analista_id,
  -- Un analista GARANTIZADO distinto del que ya tiene ese cliente. Sin esto la
  -- prueba era dependiente del dato: si el cliente ya estaba con ese analista,
  -- el UPDATE no tocaba ninguna fila, el trigger no se ejercitaba y el mutante
  -- que le quita el corte pasaba en VERDE. Un fixture no es un invariante.
  (select a.id
     from public.perfiles a
    where a.rol = 'analista'
      and a.activo
      and a.id is distinct from (
        select cli.asesor_perfil_id
        from public.contratos c
        join public.perfiles cli on cli.id = c.cliente_id
        where c.estado = 'activo'
        order by c.creado_en desc
        limit 1
      )
    order by a.creado_en
    limit 1)                                                        as asesor_objetivo;

grant select on _ref to authenticated;

insert into auth.users (id) select ops_id from _ref;
insert into public.perfiles (id, nombre_completo, rol, activo, correo)
select ops_id, 'ENSAYO OPERACIONES', 'operaciones', true,
       'ensayo-operaciones@invalido.local'
from _ref;

-- ===========================================================================
-- ACTO 1 — el asiento nuevo.
-- ===========================================================================
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';

do $ops$
declare
  r record;
  v_n integer;
  v_doc uuid;
  v_msg text;
  v_fallos text[] := '{}';
begin
  select * into r from _ref;

  -- Identidad -------------------------------------------------------------
  if not public.es_operaciones() then
    v_fallos := array_append(v_fallos, 'es_operaciones() deberia ser cierto');
  end if;
  if not public.es_gestor_cartera() then
    v_fallos := array_append(v_fallos, 'es_gestor_cartera() deberia ser cierto');
  end if;
  if public.es_admin() then
    v_fallos := array_append(v_fallos, 'CONTAMINACION: es_admin() se volvio cierta para operaciones');
  end if;
  if public.es_superadmin() or public.es_analista() then
    v_fallos := array_append(v_fallos, 'CONTAMINACION: es_superadmin()/es_analista() ciertas');
  end if;

  -- PUEDE: las cuatro pantallas -------------------------------------------
  select count(*) into v_n from public.contratos;
  if v_n < 1 then v_fallos := array_append(v_fallos, 'no ve contratos'); end if;

  select count(*) into v_n from public.perfiles where rol = 'cliente';
  if v_n < 1 then v_fallos := array_append(v_fallos, 'no ve clientes'); end if;

  select count(*) into v_n from public.cronograma_pagos;
  if v_n < 1 then v_fallos := array_append(v_fallos, 'no ve el cronograma de pagos'); end if;

  if not public.puede_ver_contrato(r.contrato_id) then
    v_fallos := array_append(v_fallos, 'puede_ver_contrato() la niega');
  end if;

  -- Pagos: registrar/revertir es un UPDATE directo sobre la cuota.
  update public.cronograma_pagos set fecha_programada = fecha_programada
   where id = r.cuota_id;
  get diagnostics v_n = row_count;
  if v_n <> 1 then v_fallos := array_append(v_fallos, 'no puede tocar una cuota (Pagos)'); end if;

  -- Clientes: activar/desactivar y reasignar asesor.
  update public.perfiles set activo = activo where id = r.cliente_id;
  get diagnostics v_n = row_count;
  if v_n <> 1 then v_fallos := array_append(v_fallos, 'no puede editar un cliente'); end if;

  -- Documentos: subir.
  begin
    insert into public.documentos (contrato_id, nombre, tipo, storage_path, subido_por)
    values (r.contrato_id, 'ensayo.pdf', 'contrato',
            r.contrato_id::text || '/ensayo.pdf', r.ops_id)
    returning id into v_doc;
  exception when others then
    v_doc := null;
  end;
  if v_doc is null then
    v_fallos := array_append(v_fallos, 'no puede subir un documento');
  end if;

  -- Contratos: los portones de las RPC. Se sondean SIN mutar: el chequeo de
  -- autorizacion es lo primero que corre, asi que un argumento invalido
  -- distingue «no autorizado» de «autorizado y el dato esta mal».
  begin
    perform public.actualizar_numero_contrato(r.contrato_id, '   ');
    v_fallos := array_append(v_fallos, 'actualizar_numero_contrato acepto un numero vacio');
  exception when others then
    v_msg := sqlerrm;
    if v_msg like '%No autorizado%' then
      v_fallos := array_append(v_fallos, 'actualizar_numero_contrato la rechaza');
    end if;
  end;

  -- Pagos consume una funcion del CRM: debe dejarla pasar.
  begin
    perform * from crm.cuentas_pago_contratos_fn(array[r.contrato_id]);
  exception when others then
    if sqlerrm like '%No autorizado%' then
      v_fallos := array_append(v_fallos, 'cuentas_pago_contratos_fn la rechaza (rompe Pagos)');
    end if;
  end;

  -- NO PUEDE ---------------------------------------------------------------
  begin
    insert into public.novedades (titulo, mensaje, enviado_por)
    values ('ENSAYO', 'no deberia entrar', r.ops_id);
    v_fallos := array_append(v_fallos, 'GRAVE: pudo publicar un comunicado');
  exception when insufficient_privilege then null;
    when others then
      if sqlerrm not like '%row-level security%' then
        v_fallos := array_append(v_fallos, 'comunicado: error inesperado -> ' || sqlerrm);
      end if;
  end;

  delete from public.documentos where id = v_doc;
  get diagnostics v_n = row_count;
  if v_n <> 0 then v_fallos := array_append(v_fallos, 'GRAVE: pudo borrar un documento'); end if;

  delete from public.cronograma_pagos where id = r.cuota_id;
  get diagnostics v_n = row_count;
  if v_n <> 0 then v_fallos := array_append(v_fallos, 'GRAVE: pudo borrar una cuota'); end if;

  update public.perfiles set cargo = cargo where id = r.analista_id;
  get diagnostics v_n = row_count;
  if v_n <> 0 then v_fallos := array_append(v_fallos, 'GRAVE: pudo editar a un analista'); end if;

  -- Cerrar el ciclo de un contrato es de Gloria. El chequeo de autorizacion es
  -- lo PRIMERO de la funcion, asi que un resultado invalido distingue las dos
  -- respuestas sin mutar nada: «No autorizado» (bien) vs «Resultado invalido».
  begin
    perform public.cerrar_contrato(r.contrato_id, 'ensayo-invalido');
    v_fallos := array_append(v_fallos, 'GRAVE: cerrar_contrato no la corta');
  exception when others then
    if sqlerrm not like '%No autorizado%' then
      v_fallos := array_append(v_fallos, 'GRAVE: paso el porton de cerrar_contrato');
    end if;
  end;

  -- Mover un cliente de analista es decision comercial: el trigger levanta la voz.
  if r.asesor_objetivo is null then
    v_fallos := array_append(v_fallos, 'la siembra no encontro un analista distinto: la prueba del asesor no probaria nada');
  end if;
  begin
    update public.perfiles
       set asesor_perfil_id = r.asesor_objetivo
     where id = r.cliente_id;
    if found then
      v_fallos := array_append(v_fallos, 'GRAVE: pudo reasignar el asesor de un cliente');
    end if;
  exception when insufficient_privilege then null;
    when others then
      if sqlerrm not like '%no puede reasignar el asesor%' then
        v_fallos := array_append(v_fallos, ('reasignar: error inesperado -> ' || sqlerrm));
      end if;
  end;

  update public.perfiles set cargo = cargo where id = r.gloria_id;
  get diagnostics v_n = row_count;
  if v_n <> 0 then v_fallos := array_append(v_fallos, 'GRAVE: pudo editar la fila de Gloria'); end if;

  begin
    update public.perfiles set rol = 'admin' where id = r.ops_id;
    if (select rol from public.perfiles where id = r.ops_id) <> 'operaciones' then
      v_fallos := array_append(v_fallos, 'GRAVE: pudo ascenderse a admin');
    end if;
  exception when others then null;
  end;

  select count(*) into v_n from public.audit_log;
  if v_n <> 0 then v_fallos := array_append(v_fallos, 'GRAVE: ve el audit_log'); end if;

  begin
    perform * from public.bandeja_actividad(1, 0);
    v_fallos := array_append(v_fallos, 'GRAVE: pudo abrir la bandeja de Actividad');
  exception when others then null;
  end;

  begin
    perform public.metricas_directorio();
    v_fallos := array_append(v_fallos, 'GRAVE: pudo abrir el cockpit del Directorio');
  exception when others then null;
  end;

  if cardinality(v_fallos) > 0 then
    raise exception E'ACTO 1 (operaciones) — % fallo(s):\n  · %',
      cardinality(v_fallos), array_to_string(v_fallos, E'\n  · ');
  end if;
  raise notice 'ACTO 1 (operaciones): OK';
end
$ops$;

-- ===========================================================================
-- ACTO 2 — Gloria (admin) no pierde nada.
-- ===========================================================================
set local request.jwt.claims = '{"sub":"41544ccc-cbfd-430f-a0e7-73491e296c26","role":"authenticated"}';

do $gloria$
declare
  r record;
  v_n integer;
  v_doc uuid;
  v_fallos text[] := '{}';
begin
  select * into r from _ref;

  if not public.es_admin() then v_fallos := array_append(v_fallos, 'es_admin() dejo de ser cierta'); end if;
  if public.es_operaciones() then v_fallos := array_append(v_fallos, 'es_operaciones() cierta para Gloria'); end if;
  if not public.es_gestor_cartera() then v_fallos := array_append(v_fallos, 'es_gestor_cartera() falsa para Gloria'); end if;

  select count(*) into v_n from public.contratos;
  if v_n < 1 then v_fallos := array_append(v_fallos, 'dejo de ver contratos'); end if;

  select count(*) into v_n from public.audit_log;
  if v_n < 1 then v_fallos := array_append(v_fallos, 'dejo de ver el audit_log'); end if;

  insert into public.novedades (titulo, mensaje, enviado_por)
  values ('ENSAYO', 'Gloria sigue comunicando', r.gloria_id);

  update public.perfiles set cargo = cargo where id = r.analista_id;
  get diagnostics v_n = row_count;
  if v_n <> 1 then v_fallos := array_append(v_fallos, 'dejo de poder editar analistas'); end if;

  -- Gloria conserva las dos llaves que el asiento nuevo NO recibe.
  begin
    perform public.cerrar_contrato(r.contrato_id, 'ensayo-invalido');
    v_fallos := array_append(v_fallos, 'cerrar_contrato acepto un resultado invalido');
  exception when others then
    if sqlerrm like '%No autorizado%' then
      v_fallos := array_append(v_fallos, 'GRAVE: Gloria dejo de poder cerrar ciclo');
    end if;
  end;

  update public.perfiles set asesor_perfil_id = asesor_perfil_id where id = r.cliente_id;
  get diagnostics v_n = row_count;
  if v_n <> 1 then v_fallos := array_append(v_fallos, 'Gloria dejo de poder tocar el asesor'); end if;

  insert into public.documentos (contrato_id, nombre, tipo, storage_path, subido_por)
  values (r.contrato_id, 'ensayo-gloria.pdf', 'contrato',
          r.contrato_id::text || '/ensayo-gloria.pdf', r.gloria_id)
  returning id into v_doc;
  delete from public.documentos where id = v_doc;
  get diagnostics v_n = row_count;
  if v_n <> 1 then v_fallos := array_append(v_fallos, 'dejo de poder borrar documentos'); end if;

  if cardinality(v_fallos) > 0 then
    raise exception E'ACTO 2 (Gloria) — % fallo(s):\n  · %',
      cardinality(v_fallos), array_to_string(v_fallos, E'\n  · ');
  end if;
  raise notice 'ACTO 2 (Gloria admin): OK';
end
$gloria$;

-- ===========================================================================
-- ACTO 3 — un analista no gana nada.
-- ===========================================================================
set local request.jwt.claims = '{"sub":"7c124080-c310-40d3-b245-794657852968","role":"authenticated"}';

do $analista$
declare
  v_n integer;
  v_total integer;
  v_fallos text[] := '{}';
begin
  if public.es_gestor_cartera() then
    v_fallos := array_append(v_fallos, 'GRAVE: un analista quedo como gestor de cartera');
  end if;
  if public.es_operaciones() or public.es_admin() then
    v_fallos := array_append(v_fallos, 'GRAVE: identidad contaminada');
  end if;

  select count(*) into v_n from public.contratos;
  select count(*) into v_total from public.contratos c where true;
  if v_n = 0 then
    v_fallos := array_append(v_fallos, 'el analista dejo de ver su cartera');
  end if;

  select count(*) into v_n from public.audit_log;
  if v_n <> 0 then v_fallos := array_append(v_fallos, 'GRAVE: el analista ve el audit_log'); end if;

  if cardinality(v_fallos) > 0 then
    raise exception E'ACTO 3 (analista) — % fallo(s):\n  · %',
      cardinality(v_fallos), array_to_string(v_fallos, E'\n  · ');
  end if;
  raise notice 'ACTO 3 (analista): OK';
end
$analista$;

reset role;
select 'ORACULO COMPLETO: 3/3 actos en verde' as resultado;
