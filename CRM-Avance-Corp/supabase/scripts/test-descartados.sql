-- Oraculo transaccional autocontenido de la VISTA de descartados (C1-ter).
-- Exito = token DESCARTADOS_TX_OK; todo queda en rollback.
--
-- Cubre: gate de rol (42501), el ALCANCE DOBLE (solo cola global Y autor de
-- staff: un descarte de vendedor liberado a la cola NO aparece), la ventana de
-- 30 dias, el orden descartado_en DESC, la SEPARACION comentario/nota_descarte
-- (el truncado de uno no borra al otro), creado_en, es_mio por actor,
-- puede_deshacer (propio+24h) y la integracion con deshacer_descarte.

begin;

-- Claims de management del ejecutor (MCP/dashboard) → auth.uid() debe ser null
-- para sembrar como sistema; bajo psql es no-op.
select set_config('request.jwt.claims', '', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, email_confirmed_at, raw_app_meta_data,
  raw_user_meta_data, created_at, updated_at
)
values
  ('1b000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'dsc-coord@test.invalid', now(), '{}', '{}', now(), now()),
  ('1b000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'dsc-sup@test.invalid', now(), '{}', '{}', now(), now()),
  ('1b000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'dsc-vend@test.invalid', now(), '{}', '{}', now(), now()),
  ('1b000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'dsc-ger@test.invalid', now(), '{}', '{}', now(), now());

insert into public.perfiles (id, nombre_completo, correo, rol, activo)
values
  ('1b000000-0000-4000-8000-000000000001', 'Vista Coordinadora', 'dsc-coord@test.invalid', 'comercial', true),
  ('1b000000-0000-4000-8000-000000000002', 'Vista Supervisor', 'dsc-sup@test.invalid', 'comercial', true),
  ('1b000000-0000-4000-8000-000000000003', 'Vista Vendedor', 'dsc-vend@test.invalid', 'comercial', true),
  ('1b000000-0000-4000-8000-000000000004', 'Vista Gerencia', 'dsc-ger@test.invalid', 'comercial', true);

insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
values
  ('1b000000-0000-4000-8000-000000000001', 'coordinador', null, true),
  ('1b000000-0000-4000-8000-000000000002', 'supervisor', null, true),
  ('1b000000-0000-4000-8000-000000000003', 'vendedor', '1b000000-0000-4000-8000-000000000002', true),
  ('1b000000-0000-4000-8000-000000000004', 'gerencia', null, true);

-- Siembra de la cola global (como sistema).
insert into crm.leads (
  id, nombre_completo, telefono, etapa, origen, monto_estimado, moneda,
  categoria_interes, vendedor_id, asignado_supervisor_id, activo, no_contactar, creado_por, nota
)
values
  ('1c000000-0000-4000-8000-000000000001', 'VISTA SQL RECIENTE MIO', '999333001', 'nuevo', 'otro', 1000, 'PEN',
   'nuevo', null, null, true, false, '1b000000-0000-4000-8000-000000000002',
   'quiero un préstamo, llámame al 987 654 321'),
  ('1c000000-0000-4000-8000-000000000002', 'VISTA SQL DE GERENCIA', '999333002', 'nuevo', 'otro', 2000, 'PEN',
   null, null, null, true, false, '1b000000-0000-4000-8000-000000000002', null),
  ('1c000000-0000-4000-8000-000000000003', 'VISTA SQL VIEJO 25H', '999333003', 'nuevo', 'otro', 3000, 'PEN',
   null, null, null, true, false, '1b000000-0000-4000-8000-000000000002', null),
  ('1c000000-0000-4000-8000-000000000004', 'VISTA SQL FUERA DE VENTANA', '999333004', 'nuevo', 'otro', 4000, 'PEN',
   null, null, null, true, false, '1b000000-0000-4000-8000-000000000002', null),
  ('1c000000-0000-4000-8000-000000000005', 'VISTA SQL DE VENDEDOR', '999333005', 'nuevo', 'otro', 5000, 'PEN',
   null, '1b000000-0000-4000-8000-000000000003', null, true, false, '1b000000-0000-4000-8000-000000000002', null),
  -- L6: quedara en la cola global (sin dueno) pero DESCARTADO POR EL VENDEDOR
  -- (fixture directa, trigger apagado abajo) — NO debe aparecer: el autor no es
  -- staff de la cola. Simula un descarte de cartera que gerencia liberó luego.
  ('1c000000-0000-4000-8000-000000000006', 'VISTA SQL AUTOR VENDEDOR', '999333006', 'nuevo', 'otro', 6000, 'PEN',
   null, null, null, true, false, '1b000000-0000-4000-8000-000000000002', null);

-- La coordinadora descarta L1 CON NOTA (para probar la separacion comentario/
-- nota_descarte), L3 y L4 sin nota. Todo por RPC real (sello + actividad).
select set_config('request.jwt.claim.sub', '1b000000-0000-4000-8000-000000000001', true);
set local role authenticated;
do $test$
begin
  perform crm.descartar_lead('1c000000-0000-4000-8000-000000000001', 'pide_credito', 'confirmado: solo quiere plata prestada');
  perform crm.descartar_lead('1c000000-0000-4000-8000-000000000003', 'sin_interes', null);
  perform crm.descartar_lead('1c000000-0000-4000-8000-000000000004', 'datos_invalidos', null);
end;
$test$;
reset role;

-- Gerencia descarta L2 (para probar es_mio=false ante la coordinadora).
select set_config('request.jwt.claim.sub', '1b000000-0000-4000-8000-000000000004', true);
set local role authenticated;
do $test$
begin
  perform crm.descartar_lead('1c000000-0000-4000-8000-000000000002', 'no_responde', null);
end;
$test$;
reset role;

-- El vendedor descarta SU PROPIO lead por UPDATE directo (policy leads_update):
-- ese descarte tiene DUENO y no es asunto de la vista del coordinador.
select set_config('request.jwt.claim.sub', '1b000000-0000-4000-8000-000000000003', true);
set local role authenticated;
update crm.leads
   set etapa = 'descartado', motivo_descarte = 'sin_interes'
 where id = '1c000000-0000-4000-8000-000000000005';
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- Backdates y sello del autor-vendedor: el trigger zz restaura el sello en todo
-- UPDATE (esa inmutabilidad ya la asevera c1b) → se apaga SOLO para fabricar los
-- fixtures, dentro de la tx. L3 a 25h (mio, fuera de la ventana del deshacer),
-- L4 a 40 dias (fuera de la ventana del LISTADO), L6 sellado por el VENDEDOR.
alter table crm.leads disable trigger trg_leads_zz_sello_descarte;
update crm.leads set descartado_en = statement_timestamp() - interval '25 hours'
 where id = '1c000000-0000-4000-8000-000000000003';
update crm.leads set descartado_en = statement_timestamp() - interval '40 days'
 where id = '1c000000-0000-4000-8000-000000000004';
update crm.leads
   set etapa = 'descartado', motivo_descarte = 'sin_interes',
       descartado_en = statement_timestamp(), descartado_por = '1b000000-0000-4000-8000-000000000003'
 where id = '1c000000-0000-4000-8000-000000000006';
alter table crm.leads enable trigger trg_leads_zz_sello_descarte;

-- ── V1: gate de rol — vendedor y supervisor no ven el listado ────────────────
select set_config('request.jwt.claim.sub', '1b000000-0000-4000-8000-000000000003', true);
set local role authenticated;
do $test$
begin
  begin
    perform count(*) from crm.leads_descartados();
    raise exception 'V01 un vendedor pudo listar los descartados de la cola';
  exception
    when insufficient_privilege then null;  -- 42501 esperado
  end;
end;
$test$;
reset role;

select set_config('request.jwt.claim.sub', '1b000000-0000-4000-8000-000000000002', true);
set local role authenticated;
do $test$
begin
  begin
    perform count(*) from crm.leads_descartados();
    raise exception 'V02 un supervisor pudo listar los descartados de la cola';
  exception
    when insufficient_privilege then null;
  end;
end;
$test$;
reset role;

-- ── V2: alcance, ventana, orden y proyeccion (como coordinadora) ─────────────
select set_config('request.jwt.claim.sub', '1b000000-0000-4000-8000-000000000001', true);
set local role authenticated;
do $test$
declare
  v_n int;
  v_fila record;
begin
  -- Del oraculo son visibles L1, L2 y L3. L4 fuera de VENTANA, L5 con DUENO,
  -- L6 AUTOR-VENDEDOR. Se cuentan solo los ids del oraculo (el branch trae otros).
  select count(*) into v_n from crm.leads_descartados()
  where id in ('1c000000-0000-4000-8000-000000000001','1c000000-0000-4000-8000-000000000002',
               '1c000000-0000-4000-8000-000000000003','1c000000-0000-4000-8000-000000000004',
               '1c000000-0000-4000-8000-000000000005','1c000000-0000-4000-8000-000000000006');
  if v_n <> 3 then
    raise exception 'V03 el listado deberia tener 3 filas del oraculo (L1,L2,L3), tiene %', v_n;
  end if;

  if exists (select 1 from crm.leads_descartados() where id = '1c000000-0000-4000-8000-000000000004') then
    raise exception 'V04 un descarte de hace 40 dias aparecio (ventana de 30 rota)';
  end if;
  if exists (select 1 from crm.leads_descartados() where id = '1c000000-0000-4000-8000-000000000005') then
    raise exception 'V05 ALCANCE: un descarte CON DUENO (cartera del vendedor) aparecio en la vista de la cola';
  end if;
  if exists (select 1 from crm.leads_descartados() where id = '1c000000-0000-4000-8000-000000000006') then
    raise exception 'V06 ALCANCE: un descarte cuyo AUTOR es un vendedor aparecio (no es staff de la cola)';
  end if;

  -- Proyeccion de L1: marca + comentario redactado + NOTA del descarte separada.
  select * into v_fila from crm.leads_descartados() where id = '1c000000-0000-4000-8000-000000000001';
  if v_fila.clasificacion_auto is distinct from 'posible_credito' then
    raise exception 'V07 la marca del clasificador no viaja en el listado';
  end if;
  if v_fila.comentario not like '%[teléfono oculto]%' or v_fila.comentario like '%987%' then
    raise exception 'V08 LEGAL: el comentario no salio redactado: %', v_fila.comentario;
  end if;
  if v_fila.comentario like '%DESCARTE%' or v_fila.comentario like '%plata prestada%' then
    raise exception 'V09 la nota del cierre se filtro dentro del comentario del cliente: %', v_fila.comentario;
  end if;
  if v_fila.nota_descarte is distinct from 'confirmado: solo quiere plata prestada' then
    raise exception 'V10 la nota del descarte no viaja separada (%)', v_fila.nota_descarte;
  end if;
  if v_fila.motivo_descarte <> 'pide_credito' then
    raise exception 'V11 el motivo no viaja (%)', v_fila.motivo_descarte;
  end if;
  if v_fila.descartado_por_nombre <> 'Vista Coordinadora' then
    raise exception 'V12 el nombre del actor no viaja (%)', v_fila.descartado_por_nombre;
  end if;
  if v_fila.creado_en is null or v_fila.categoria_interes <> 'nuevo' then
    raise exception 'V13 creado_en/categoria_interes no viajan (creado=%, cat=%)', v_fila.creado_en, v_fila.categoria_interes;
  end if;

  -- es_mio + puede_deshacer segun actor y ventana.
  if v_fila.es_mio is distinct from true or v_fila.puede_deshacer is distinct from true then
    raise exception 'V14 L1 (mio, reciente) deberia ser es_mio=true y puede_deshacer=true';
  end if;
  select * into v_fila from crm.leads_descartados() where id = '1c000000-0000-4000-8000-000000000002';
  if v_fila.es_mio is distinct from false or v_fila.puede_deshacer is distinct from false then
    raise exception 'V15 L2 (de gerencia) deberia ser es_mio=false y puede_deshacer=false';
  end if;
  if v_fila.descartado_por_nombre <> 'Vista Gerencia' then
    raise exception 'V16 el actor de L2 deberia ser Vista Gerencia (%)', v_fila.descartado_por_nombre;
  end if;
  select * into v_fila from crm.leads_descartados() where id = '1c000000-0000-4000-8000-000000000003';
  if v_fila.es_mio is distinct from true or v_fila.puede_deshacer is distinct from false then
    raise exception 'V17 L3 (mio, hace 25h) deberia ser es_mio=true y puede_deshacer=false';
  end if;
  if v_fila.nota_descarte is not null then
    raise exception 'V18 L3 sin nota de cierre deberia llevar nota_descarte null (%)', v_fila.nota_descarte;
  end if;

  -- Orden: descartado_en DESC (L2 se descarto DESPUES de L1 → L2 primero; L3 al final).
  select id into v_fila from crm.leads_descartados()
  where id in ('1c000000-0000-4000-8000-000000000001','1c000000-0000-4000-8000-000000000002',
               '1c000000-0000-4000-8000-000000000003')
  order by descartado_en desc limit 1;
  if v_fila.id <> '1c000000-0000-4000-8000-000000000002' then
    raise exception 'V19 el mas reciente del oraculo deberia ser L2 (%)', v_fila.id;
  end if;
end;
$test$;

-- ── V3: integracion con deshacer — sale del listado y vuelve a la cola ───────
do $test$
declare
  v_res jsonb;
begin
  v_res := crm.deshacer_descarte('1c000000-0000-4000-8000-000000000001');
  if v_res->>'etapa' <> 'nuevo' then
    raise exception 'V20 el deshacer no reabrio en etapa nuevo';
  end if;
  if exists (select 1 from crm.leads_descartados() where id = '1c000000-0000-4000-8000-000000000001') then
    raise exception 'V21 el lead reabierto sigue en el listado de descartados';
  end if;
  if not exists (select 1 from crm.leads_por_repartir() where id = '1c000000-0000-4000-8000-000000000001') then
    raise exception 'V22 el lead reabierto no volvio a la cola por repartir';
  end if;
end;
$test$;
reset role;

-- ── V4: gerencia tambien lista (co-titular del gate) ─────────────────────────
select set_config('request.jwt.claim.sub', '1b000000-0000-4000-8000-000000000004', true);
set local role authenticated;
do $test$
declare
  v_fila record;
begin
  select * into v_fila from crm.leads_descartados() where id = '1c000000-0000-4000-8000-000000000002';
  if not found then
    raise exception 'V23 gerencia no pudo listar los descartados';
  end if;
  if v_fila.es_mio is distinct from true or v_fila.puede_deshacer is distinct from true then
    raise exception 'V24 el descarte propio de gerencia deberia ser suyo y deshacible';
  end if;
end;
$test$;
reset role;

select 'DESCARTADOS_TX_OK' as resultado;

rollback;
