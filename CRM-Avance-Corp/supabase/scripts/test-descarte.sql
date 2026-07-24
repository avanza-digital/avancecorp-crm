-- Oraculo transaccional autocontenido del descarte de la cola (C1-bis, coordinador).
-- Exito = token DESCARTE_TX_OK; todo queda en rollback.
--
-- Cubre: el clasificador de credito en el alta (marca/no-marca, el cliente API no
-- decide), la inmutabilidad de clasificacion_auto, el comentario REDACTADO y trunco
-- de la cola v2, los gates de rol de descartar/deshacer, el contrato de SQLSTATE
-- (42501/22023/P0002), la idempotencia del doble descarte, el sello nominal, la
-- nota que se appendea sin pisarse, el deshacer con su ventana de 24 h y el choque
-- 23505->22023 al reabrir contra un lead vivo con el mismo telefono. La CARRERA de
-- descarte NO se prueba aqui (necesita dos sesiones simultaneas): el CAS del UPDATE
-- es el mismo patron ya cubierto por testReparto en test-rls.mjs.

begin;

-- El ejecutor puede traer claims de management en la conexion (p. ej. el SQL
-- del MCP/dashboard): auth.uid() dejaria de ser null y la siembra ambos-null
-- dispararia la rama "solo gerencia deja un lead en la cola" del guard de
-- tenencia. Se neutraliza para sembrar como SISTEMA; bajo psql es un no-op.
select set_config('request.jwt.claims', '', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, email_confirmed_at, raw_app_meta_data,
  raw_user_meta_data, created_at, updated_at
)
values
  ('19000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'desc-coord@test.invalid', now(), '{}', '{}', now(), now()),
  ('19000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'desc-sup@test.invalid', now(), '{}', '{}', now(), now()),
  ('19000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'desc-vend@test.invalid', now(), '{}', '{}', now(), now()),
  ('19000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'desc-ger@test.invalid', now(), '{}', '{}', now(), now()),
  ('19000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'desc-cliente@test.invalid', now(), '{}', '{}', now(), now());

insert into public.perfiles (id, nombre_completo, correo, rol, activo)
values
  ('19000000-0000-4000-8000-000000000001', 'Descarte Coordinadora', 'desc-coord@test.invalid', 'comercial', true),
  ('19000000-0000-4000-8000-000000000002', 'Descarte Supervisor', 'desc-sup@test.invalid', 'comercial', true),
  ('19000000-0000-4000-8000-000000000003', 'Descarte Vendedor', 'desc-vend@test.invalid', 'comercial', true),
  ('19000000-0000-4000-8000-000000000004', 'Descarte Gerencia', 'desc-ger@test.invalid', 'comercial', true),
  ('19000000-0000-4000-8000-000000000005', 'Descarte Cliente', 'desc-cliente@test.invalid', 'cliente', true);

insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
values
  ('19000000-0000-4000-8000-000000000001', 'coordinador', null, true),
  ('19000000-0000-4000-8000-000000000002', 'supervisor', null, true),
  ('19000000-0000-4000-8000-000000000003', 'vendedor', '19000000-0000-4000-8000-000000000002', true),
  ('19000000-0000-4000-8000-000000000004', 'gerencia', null, true);

-- Siembra como owner (sin RLS, triggers SI corren). Los valores de
-- clasificacion_auto / descartado_por que se mandan aqui son BASURA deliberada:
-- el trigger zz debe ignorarlos y decidir solo (D01-D03).
insert into crm.leads (
  id, nombre_completo, telefono, etapa, origen, monto_estimado, moneda,
  vendedor_id, asignado_supervisor_id, activo, no_contactar, creado_por,
  nota, clasificacion_auto, descartado_por
)
values
  -- L1: pide prestamo (con tilde y mayusculas) -> el codigo DEBE marcarlo,
  --     aunque la siembra intente imponer null.
  ('1a000000-0000-4000-8000-000000000001', 'DESCARTE SQL PRESTAMO', '999222001', 'nuevo', 'otro', 1000, 'PEN',
   null, null, true, false, '19000000-0000-4000-8000-000000000002',
   'Necesito un PRÉSTAMO urgente para mi negocio', null, null),
  -- L2: la pregunta MAS comun de un buen cliente -> NO se marca, aunque la
  --     siembra intente imponer 'posible_credito' ("prestan" != "prestam*").
  ('1a000000-0000-4000-8000-000000000002', 'DESCARTE SQL COOPERATIVA', '999222002', 'nuevo', 'otro', 2000, 'PEN',
   null, null, true, false, '19000000-0000-4000-8000-000000000002',
   '¿Son una cooperativa de ahorro y crédito? ¿Me pueden prestar información?', 'posible_credito', null),
  -- L3: PII dentro del texto libre -> la cola la muestra REDACTADA.
  ('1a000000-0000-4000-8000-000000000003', 'DESCARTE SQL PII', '999222003', 'nuevo', 'otro', 3000, 'PEN',
   null, null, true, false, '19000000-0000-4000-8000-000000000002',
   'escríbeme a juan.perez@gmail.com o al 987 654 321, mi DNI es 45687364, quiero invertir', null, null),
  -- L4: con dueno (vendedor) -> fuera de la cola global, P0002 al descartar.
  --     La siembra manda un descartado_por basura que el trigger debe limpiar.
  ('1a000000-0000-4000-8000-000000000004', 'DESCARTE SQL CON DUENO', '999222004', 'nuevo', 'otro', 4000, 'USD',
   '19000000-0000-4000-8000-000000000003', null, true, false, '19000000-0000-4000-8000-000000000002',
   null, null, '19000000-0000-4000-8000-000000000003'),
  -- L5: No Insista -> excluido de la cola, pero descartable (cerrar no es contactar).
  ('1a000000-0000-4000-8000-000000000005', 'DESCARTE SQL NO INSISTA', '999222005', 'nuevo', 'otro', 5000, 'PEN',
   null, null, true, true, '19000000-0000-4000-8000-000000000002',
   'financiamiento ya no me interesa, no me llamen', null, null),
  -- L6: sin nota -> comentario null en la cola; luego protagoniza el 23505.
  ('1a000000-0000-4000-8000-000000000006', 'DESCARTE SQL SIN NOTA', '999222006', 'nuevo', 'otro', 6000, 'PEN',
   null, null, true, false, '19000000-0000-4000-8000-000000000002',
   null, null, null),
  -- L7: nota larga sin PII -> la cola la trunca a 400.
  ('1a000000-0000-4000-8000-000000000007', 'DESCARTE SQL NOTA LARGA', '999222007', 'nuevo', 'otro', 7000, 'PEN',
   null, null, true, false, '19000000-0000-4000-8000-000000000002',
   repeat('inversion segura ', 30), null, null);

-- L8: convertido (nace terminal SOLO via flag privilegiado, como la RPC real).
select set_config('crm.op_privilegiada', 'on', true);
insert into crm.leads (
  id, nombre_completo, telefono, etapa, origen, monto_estimado, moneda,
  vendedor_id, asignado_supervisor_id, activo, no_contactar, creado_por,
  perfil_id, convertido_en
)
values
  ('1a000000-0000-4000-8000-000000000008', 'DESCARTE SQL CONVERTIDO', '999222008', 'convertido', 'otro', 8000, 'PEN',
   null, null, true, false, '19000000-0000-4000-8000-000000000002',
   '19000000-0000-4000-8000-000000000005', now());
select set_config('crm.op_privilegiada', 'off', true);

-- ── D-A: el clasificador decide en el alta; el cliente API no ────────────────
do $test$
declare
  v_clasif text;
begin
  select clasificacion_auto into v_clasif from crm.leads where id = '1a000000-0000-4000-8000-000000000001';
  if v_clasif is distinct from 'posible_credito' then
    raise exception 'D01 "necesito un préstamo" no quedo marcado (clasificacion_auto=%)', v_clasif;
  end if;

  select clasificacion_auto into v_clasif from crm.leads where id = '1a000000-0000-4000-8000-000000000002';
  if v_clasif is not null then
    raise exception 'D02 la cooperativa/prestar-informacion quedo marcada (falso positivo, y el INSERT respeto el valor del cliente)';
  end if;

  if exists (
    select 1 from crm.leads
    where id = '1a000000-0000-4000-8000-000000000004'
      and (descartado_por is not null or descartado_en is not null)
  ) then
    raise exception 'D03 el INSERT respeto un sello de descarte mandado por el cliente';
  end if;

  select clasificacion_auto into v_clasif from crm.leads where id = '1a000000-0000-4000-8000-000000000005';
  if v_clasif is distinct from 'posible_credito' then
    raise exception 'D04 "financiamiento" no quedo marcado (clasificacion_auto=%)', v_clasif;
  end if;
end;
$test$;

-- ── D-B: la marca del codigo es inmutable via UPDATE ─────────────────────────
update crm.leads set clasificacion_auto = null
 where id = '1a000000-0000-4000-8000-000000000001';
update crm.leads set clasificacion_auto = 'posible_credito'
 where id = '1a000000-0000-4000-8000-000000000002';

do $test$
begin
  if (select clasificacion_auto from crm.leads where id = '1a000000-0000-4000-8000-000000000001')
     is distinct from 'posible_credito' then
    raise exception 'D05 un UPDATE pudo borrar la marca del clasificador';
  end if;
  if (select clasificacion_auto from crm.leads where id = '1a000000-0000-4000-8000-000000000002')
     is not null then
    raise exception 'D06 un UPDATE pudo inventar una marca del clasificador';
  end if;
end;
$test$;

-- ── D-C: la cola v2 — marca visible, comentario redactado y trunco ──────────
select set_config('request.jwt.claim.sub', '19000000-0000-4000-8000-000000000001', true);
set local role authenticated;

do $test$
declare
  v_n int;
  v_comentario text;
begin
  select count(*) into v_n from crm.leads_por_repartir();
  if v_n <> 5 then
    raise exception 'D07 la cola deberia tener 5 leads (L1,L2,L3,L6,L7), tiene %', v_n;
  end if;

  if not exists (
    select 1 from crm.leads_por_repartir()
    where id = '1a000000-0000-4000-8000-000000000001' and clasificacion_auto = 'posible_credito'
  ) then
    raise exception 'D08 la marca posible_credito no viaja en la cola';
  end if;

  select comentario into v_comentario from crm.leads_por_repartir()
  where id = '1a000000-0000-4000-8000-000000000003';
  if v_comentario not like '%[correo oculto]%'
     or v_comentario not like '%[teléfono oculto]%'
     or v_comentario not like '%[documento oculto]%' then
    raise exception 'D09 el comentario no salio redactado: %', v_comentario;
  end if;
  if v_comentario like '%juan.perez%' or v_comentario like '%45687364%' or v_comentario like '%987%' then
    raise exception 'D10 LEGAL: quedo PII legible en el comentario de la cola: %', v_comentario;
  end if;
  if v_comentario not like '%quiero invertir%' then
    raise exception 'D11 la redaccion se comio el contenido util del comentario: %', v_comentario;
  end if;

  select comentario into v_comentario from crm.leads_por_repartir()
  where id = '1a000000-0000-4000-8000-000000000006';
  if v_comentario is not null then
    raise exception 'D12 un lead sin nota deberia llevar comentario null, llevo %', v_comentario;
  end if;

  select comentario into v_comentario from crm.leads_por_repartir()
  where id = '1a000000-0000-4000-8000-000000000007';
  if length(v_comentario) <> 400 then
    raise exception 'D13 el comentario largo no quedo truncado a 400 (length=%)', length(v_comentario);
  end if;
end;
$test$;
reset role;

-- ── D-D: gate de rol — vendedor y supervisor quedan fuera ────────────────────
select set_config('request.jwt.claim.sub', '19000000-0000-4000-8000-000000000003', true);
set local role authenticated;
do $test$
begin
  begin
    perform crm.descartar_lead('1a000000-0000-4000-8000-000000000001', 'pide_credito', null);
    raise exception 'D14 un vendedor pudo descartar un lead de la cola';
  exception
    when insufficient_privilege then null;  -- 42501 esperado
  end;

  begin
    perform crm.deshacer_descarte('1a000000-0000-4000-8000-000000000001');
    raise exception 'D15 un vendedor pudo deshacer un descarte';
  exception
    when insufficient_privilege then null;
  end;
end;
$test$;
reset role;

select set_config('request.jwt.claim.sub', '19000000-0000-4000-8000-000000000002', true);
set local role authenticated;
do $test$
begin
  begin
    perform crm.descartar_lead('1a000000-0000-4000-8000-000000000001', 'pide_credito', null);
    raise exception 'D16 un supervisor pudo descartar un lead de la cola';
  exception
    when insufficient_privilege then null;
  end;
end;
$test$;
reset role;

-- ── D-E: contrato de argumentos (22023) y lead inexistente (P0002) ───────────
select set_config('request.jwt.claim.sub', '19000000-0000-4000-8000-000000000001', true);
set local role authenticated;
do $test$
declare
  v_sqlstate text;
begin
  begin
    perform crm.descartar_lead('1a000000-0000-4000-8000-000000000001', 'motivo_inventado', null);
    raise exception 'D17 se acepto un motivo fuera del catalogo';
  exception
    when others then
      v_sqlstate := SQLSTATE;
      if v_sqlstate <> '22023' then
        raise exception 'D18 motivo invalido devolvio % en vez de 22023', v_sqlstate;
      end if;
  end;

  begin
    perform crm.descartar_lead('1a000000-0000-4000-8000-000000000001', 'pide_credito', repeat('x', 501));
    raise exception 'D19 se acepto una nota de descarte de mas de 500 caracteres';
  exception
    when others then
      v_sqlstate := SQLSTATE;
      if v_sqlstate <> '22023' then
        raise exception 'D20 nota larga devolvio % en vez de 22023', v_sqlstate;
      end if;
  end;

  begin
    perform crm.descartar_lead(null, 'pide_credito', null);
    raise exception 'D21 se acepto un lead null';
  exception
    when others then
      v_sqlstate := SQLSTATE;
      if v_sqlstate <> '22023' then
        raise exception 'D22 lead null devolvio % en vez de 22023', v_sqlstate;
      end if;
  end;

  begin
    perform crm.descartar_lead('1a000000-0000-4000-8000-0000000000ff', 'pide_credito', null);
    raise exception 'D23 se pudo descartar un lead inexistente';
  exception
    when others then
      v_sqlstate := SQLSTATE;
      if v_sqlstate <> 'P0002' then
        raise exception 'D24 lead inexistente devolvio % en vez de P0002', v_sqlstate;
      end if;
  end;
end;
$test$;

-- ── D-F: fuera de la cola — con dueno y convertido ───────────────────────────
do $test$
declare
  v_sqlstate text;
begin
  begin
    perform crm.descartar_lead('1a000000-0000-4000-8000-000000000004', 'sin_interes', null);
    raise exception 'D25 se pudo descartar un lead con dueno (no es de la cola global)';
  exception
    when others then
      v_sqlstate := SQLSTATE;
      if v_sqlstate <> 'P0002' then
        raise exception 'D26 lead con dueno devolvio % en vez de P0002', v_sqlstate;
      end if;
  end;

  begin
    perform crm.descartar_lead('1a000000-0000-4000-8000-000000000008', 'sin_interes', null);
    raise exception 'D27 se pudo descartar un lead convertido';
  exception
    when others then
      v_sqlstate := SQLSTATE;
      if v_sqlstate <> 'P0002' then
        raise exception 'D28 lead convertido devolvio % en vez de P0002', v_sqlstate;
      end if;
  end;
end;
$test$;

-- ── D-G: camino feliz — descarte con motivo pide_credito y nota ──────────────
do $test$
declare
  v_res jsonb;
begin
  v_res := crm.descartar_lead(
    '1a000000-0000-4000-8000-000000000001', 'pide_credito', 'solo busca préstamo');

  if (v_res->>'ya_estaba')::boolean is distinct from false then
    raise exception 'D29 el primer descarte devolvio ya_estaba=true';
  end if;
  if v_res->>'motivo_descarte' <> 'pide_credito' then
    raise exception 'D30 la RPC no devolvio el motivo aplicado';
  end if;
  if v_res->>'descartado_por' <> '19000000-0000-4000-8000-000000000001' then
    raise exception 'D31 el sello no acredita a la coordinadora';
  end if;

  -- Ya no esta en la cola.
  if exists (
    select 1 from crm.leads_por_repartir()
    where id = '1a000000-0000-4000-8000-000000000001'
  ) then
    raise exception 'D32 el lead descartado sigue apareciendo en la cola';
  end if;
end;
$test$;
reset role;

do $test$
declare
  v_lead crm.leads%rowtype;
begin
  select * into v_lead from crm.leads where id = '1a000000-0000-4000-8000-000000000001';

  if v_lead.etapa <> 'descartado' or v_lead.motivo_descarte <> 'pide_credito' then
    raise exception 'D33 estado incorrecto tras el descarte (etapa=%, motivo=%)', v_lead.etapa, v_lead.motivo_descarte;
  end if;
  if v_lead.descartado_por <> '19000000-0000-4000-8000-000000000001' or v_lead.descartado_en is null then
    raise exception 'D34 el sello nominal no quedo escrito';
  end if;
  if v_lead.activo is distinct from true then
    raise exception 'D35 el descarte desactivo el lead (debe seguir activo=true)';
  end if;
  -- La nota se appendea, nunca se pisa (regla dura de Miguel).
  if v_lead.nota not like 'Necesito un PRÉSTAMO urgente%' or v_lead.nota not like '%DESCARTE: solo busca préstamo%' then
    raise exception 'D36 la nota del cliente se piso o el sufijo DESCARTE no quedo (nota=%)', v_lead.nota;
  end if;
  -- La actividad la escribe el trigger, acreditando a la coordinadora.
  if not exists (
    select 1 from crm.actividades
    where lead_id = '1a000000-0000-4000-8000-000000000001'
      and tipo = 'cambio_etapa'
      and creado_por = '19000000-0000-4000-8000-000000000001'
  ) then
    raise exception 'D37 no quedo traza del descarte acreditada a la coordinadora';
  end if;
end;
$test$;

-- ── D-H: idempotencia — mismo actor y motivo si; otro motivo u otro actor no ─
select set_config('request.jwt.claim.sub', '19000000-0000-4000-8000-000000000001', true);
set local role authenticated;
do $test$
declare
  v_res jsonb;
  v_sqlstate text;
begin
  v_res := crm.descartar_lead(
    '1a000000-0000-4000-8000-000000000001', 'pide_credito', 'solo busca préstamo');
  if (v_res->>'ya_estaba')::boolean is distinct from true then
    raise exception 'D38 el reintento del mismo descarte no fue idempotente';
  end if;

  begin
    perform crm.descartar_lead('1a000000-0000-4000-8000-000000000001', 'sin_interes', null);
    raise exception 'D39 se pudo re-descartar con OTRO motivo sin error';
  exception
    when others then
      v_sqlstate := SQLSTATE;
      if v_sqlstate <> 'P0002' then
        raise exception 'D40 re-descarte con otro motivo devolvio % en vez de P0002', v_sqlstate;
      end if;
  end;
end;
$test$;
reset role;

do $test$
begin
  -- El reintento idempotente NO duplica la traza.
  if (select count(*) from crm.actividades
      where lead_id = '1a000000-0000-4000-8000-000000000001' and tipo = 'cambio_etapa') <> 1 then
    raise exception 'D41 el reintento idempotente duplico la actividad de cambio de etapa';
  end if;
end;
$test$;

select set_config('request.jwt.claim.sub', '19000000-0000-4000-8000-000000000004', true);
set local role authenticated;
do $test$
declare
  v_sqlstate text;
begin
  -- Gerencia repitiendo el descarte de la coordinadora: conflicto real, no idempotencia.
  begin
    perform crm.descartar_lead('1a000000-0000-4000-8000-000000000001', 'pide_credito', null);
    raise exception 'D42 el descarte fue idempotente para OTRO actor';
  exception
    when others then
      v_sqlstate := SQLSTATE;
      if v_sqlstate <> 'P0002' then
        raise exception 'D43 descarte de otro actor devolvio % en vez de P0002', v_sqlstate;
      end if;
  end;
end;
$test$;
reset role;

-- ── D-I: descartar a un No Insista SI se permite (cerrar no es contactar) ────
select set_config('request.jwt.claim.sub', '19000000-0000-4000-8000-000000000001', true);
set local role authenticated;
do $test$
declare
  v_res jsonb;
begin
  v_res := crm.descartar_lead('1a000000-0000-4000-8000-000000000005', 'sin_interes', null);
  if (v_res->>'ya_estaba')::boolean is distinct from false then
    raise exception 'D44 no se pudo cerrar la ficha de un lead No Insista';
  end if;
end;
$test$;
reset role;

do $test$
begin
  if (select no_contactar from crm.leads where id = '1a000000-0000-4000-8000-000000000005')
     is distinct from true then
    raise exception 'D45 LEGAL: el descarte toco la marca no_contactar';
  end if;
end;
$test$;

-- ── D-J: deshacer — camino feliz, sello limpio, ciclo incrementado ───────────
select set_config('request.jwt.claim.sub', '19000000-0000-4000-8000-000000000001', true);
set local role authenticated;
do $test$
declare
  v_res jsonb;
begin
  perform crm.descartar_lead('1a000000-0000-4000-8000-000000000002', 'sin_interes', null);
  v_res := crm.deshacer_descarte('1a000000-0000-4000-8000-000000000002');
  if v_res->>'etapa' <> 'nuevo' then
    raise exception 'D46 el deshacer no devolvio el lead a etapa nuevo';
  end if;
  if (v_res->>'ciclo_actual')::int <> 2 then
    raise exception 'D47 la reapertura no incremento ciclo_actual (=%)', v_res->>'ciclo_actual';
  end if;

  -- Vuelve a la cola.
  if not exists (
    select 1 from crm.leads_por_repartir()
    where id = '1a000000-0000-4000-8000-000000000002'
  ) then
    raise exception 'D48 el lead reabierto no volvio a la cola';
  end if;
end;
$test$;
reset role;

do $test$
begin
  if exists (
    select 1 from crm.leads
    where id = '1a000000-0000-4000-8000-000000000002'
      and (motivo_descarte is not null or descartado_en is not null or descartado_por is not null)
  ) then
    raise exception 'D49 el deshacer dejo un sello o motivo rancio';
  end if;
end;
$test$;

-- ── D-K: deshacer es personal — otro actor no puede ──────────────────────────
select set_config('request.jwt.claim.sub', '19000000-0000-4000-8000-000000000004', true);
set local role authenticated;
do $test$
declare
  v_sqlstate text;
begin
  -- L1 lo descarto la coordinadora; gerencia no puede deshacerlo.
  begin
    perform crm.deshacer_descarte('1a000000-0000-4000-8000-000000000001');
    raise exception 'D50 gerencia pudo deshacer un descarte ajeno';
  exception
    when others then
      v_sqlstate := SQLSTATE;
      if v_sqlstate <> 'P0002' then
        raise exception 'D51 deshacer ajeno devolvio % en vez de P0002', v_sqlstate;
      end if;
  end;
end;
$test$;
reset role;

-- ── D-L: la ventana de 24 h se cierra ────────────────────────────────────────
-- El trigger zz restaura el sello en todo UPDATE (esa inmutabilidad es D05/D06),
-- asi que un descarte "viejo" no se puede fabricar con un UPDATE normal: se
-- desactiva el trigger SOLO para backdatear la fixture, dentro de esta tx.
alter table crm.leads disable trigger trg_leads_zz_sello_descarte;
update crm.leads
   set descartado_en = statement_timestamp() - interval '25 hours'
 where id = '1a000000-0000-4000-8000-000000000001';
alter table crm.leads enable trigger trg_leads_zz_sello_descarte;

select set_config('request.jwt.claim.sub', '19000000-0000-4000-8000-000000000001', true);
set local role authenticated;
do $test$
declare
  v_sqlstate text;
begin
  begin
    perform crm.deshacer_descarte('1a000000-0000-4000-8000-000000000001');
    raise exception 'D52 se pudo deshacer un descarte de hace 25 horas';
  exception
    when others then
      v_sqlstate := SQLSTATE;
      if v_sqlstate <> 'P0002' then
        raise exception 'D53 deshacer fuera de ventana devolvio % en vez de P0002', v_sqlstate;
      end if;
  end;
end;
$test$;
reset role;

-- ── D-M: reabrir choca con un lead vivo del mismo telefono → 22023 ───────────
select set_config('request.jwt.claim.sub', '19000000-0000-4000-8000-000000000001', true);
set local role authenticated;
do $test$
begin
  perform crm.descartar_lead('1a000000-0000-4000-8000-000000000006', 'datos_invalidos', null);
end;
$test$;
reset role;

-- Entra un lead VIVO con el mismo telefono (el indice unico excluye descartados).
-- El claim del bloque anterior sigue vivo en la tx: se limpia para que este
-- INSERT de sistema (ambos-null) no dispare la rama de cola del guard.
select set_config('request.jwt.claim.sub', '', true);
insert into crm.leads (
  id, nombre_completo, telefono, etapa, origen, monto_estimado, moneda,
  vendedor_id, asignado_supervisor_id, activo, no_contactar, creado_por
)
values
  ('1a000000-0000-4000-8000-000000000009', 'DESCARTE SQL REINGRESO', '999222006', 'nuevo', 'otro', 9000, 'PEN',
   null, null, true, false, '19000000-0000-4000-8000-000000000002');

select set_config('request.jwt.claim.sub', '19000000-0000-4000-8000-000000000001', true);
set local role authenticated;
do $test$
declare
  v_sqlstate text;
begin
  begin
    perform crm.deshacer_descarte('1a000000-0000-4000-8000-000000000006');
    raise exception 'D54 se reabrio un lead chocando con otro vivo del mismo telefono';
  exception
    when others then
      v_sqlstate := SQLSTATE;
      if v_sqlstate <> '22023' then
        raise exception 'D55 el choque de reapertura devolvio % en vez de 22023 (¿23505 crudo?)', v_sqlstate;
      end if;
  end;
end;
$test$;
reset role;

select 'DESCARTE_TX_OK' as resultado;

rollback;
