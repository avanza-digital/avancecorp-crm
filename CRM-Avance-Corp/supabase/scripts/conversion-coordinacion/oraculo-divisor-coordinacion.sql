-- Oráculo transaccional de la conversión por analista para Coordinación
-- (`crm.conversion_divisor_coordinacion_fn` → `private.conversion_divisor_empresa`).
--
-- Qué prueba, con un mundo SINTÉTICO que se siembra aquí mismo y se deshace al final:
--   E01 estructura: propiedades, ACL y el candado de dispersión (ninguna de las
--       dos funciones lee leads ni el ledger: el divisor solo sale del núcleo).
--   E02 autorización: coordinador y gerencia entran; vendedor, supervisor,
--       directorio, coordinador inactivo y anónimo reciben 42501 (antes que 22023).
--   E03 período: mes futuro y día que no es el primero → 22023.
--   E04 regla del divisor recorriendo las PUERTAS REALES del reparto (turno →
--       repartir → derivar → devolver a bandeja → derivar): el lead reasignado
--       cuenta UNA vez en quien lo recibió primero (A→B y A→B→A), no cambia el
--       divisor de B, la alta manual no entra, el referido pesa 0, el lead sin
--       asignar cuenta en la empresa, y el alta a las 23:30 del último día del
--       mes anterior (hora Lima) queda en ESE mes aunque se reparta hoy.
--   E05 paridad pantalla = núcleo: cada fila de la puerta es igual a
--       `private.conversion_neta_por_vendedor`, formulario + landing = divisor,
--       y la empresa suma analistas + sin analista. Gerencia recibe lo mismo.
--   E06 contraste con el reporte de entregas: allí el lead devuelto y
--       re-entregado cuenta en B; en la puerta B sigue en 0.
--   E07 mes sellado: se sirve la foto (`crm.cierre_mes_vendedor`), el desglose
--       por origen va en null y el núcleo vivo rechaza recalcularlo.
--   E08 huellas: los conteos operativos y el núcleo conservan su cuerpo del
--       30/09/2026 (este cambio no los toca).
--   E09 (v2, desglose + rango): el desglose de cierres suma el numerador y casa con
--       el núcleo; un rango que es el mes exacto se trata como el mes (también sellado);
--       del 1 a hoy reproduce el mes; rangos inválidos (fechas cruzadas, futuro, > 366
--       días, mes y rango a la vez) → 22023; un rango parcial no supera al mes.
--
-- Requiere un banco con el esquema de producción, `crm.conversion_pesos`,
-- las políticas SLA y las migraciones 20260930185623 y 20260930221500 (v2) aplicadas.
-- No deja datos.
-- Correr con psql -f (un mensaje por sentencia): `statement_timestamp()` avanza
-- entre llamadas y el oráculo lo tolera.

\set ON_ERROR_STOP on

begin;
set local statement_timeout = '120s';
set local lock_timeout = '5s';
set local timezone = 'America/Lima';

-- ─────────────────────────────────────────────────────────────────────────────
-- E01 · Estructura
-- ─────────────────────────────────────────────────────────────────────────────
do $estructura$
declare
  v_base regprocedure := to_regprocedure('private.conversion_divisor_base(date,date)');
  v_nucleo regprocedure := to_regprocedure('private.conversion_divisor_empresa(date,date)');
  v_totales regprocedure := to_regprocedure('private.conversion_divisor_empresa_totales(date,date)');
  v_puerta regprocedure := to_regprocedure('crm.conversion_divisor_coordinacion_fn(date,date,date)');
  v_cuerpo text;
begin
  if v_base is null or v_nucleo is null or v_totales is null or v_puerta is null then
    raise exception 'E01a faltan las funciones de la conversión de Coordinación (v2)';
  end if;
  if to_regprocedure('crm.conversion_divisor_coordinacion_fn(date)') is not null then
    raise exception 'E01h la firma vieja de la puerta sigue viva junto a la nueva';
  end if;
  if (select count(*) from pg_proc p where p.oid in (v_base, v_nucleo, v_totales, v_puerta)
        and p.prosecdef and p.provolatile = 's' and p.proconfig @> array['search_path=""']) <> 4 then
    raise exception 'E01b deben ser STABLE, SECURITY DEFINER y search_path vacío';
  end if;
  if not has_function_privilege('authenticated', v_puerta, 'execute')
     or has_function_privilege('anon', v_puerta, 'execute')
     or has_function_privilege('service_role', v_puerta, 'execute')
     or has_function_privilege('public', v_puerta, 'execute')
     or (select bool_or(has_function_privilege(r, f, 'execute'))
         from unnest(array['authenticated','anon','service_role','public']) r,
              unnest(array[v_base, v_nucleo, v_totales]) f) then
    raise exception 'E01c ACL inesperada';
  end if;
  for v_cuerpo in
    select regexp_replace(lower(p.prosrc), '--[^\n]*', ' ', 'g')
    from pg_proc p where p.oid in (v_base, v_nucleo, v_totales, v_puerta)
  loop
    if v_cuerpo ~ '\mcrm\.\s*leads\M' or v_cuerpo ~ '"leads"' or v_cuerpo ~ '\mlead_asignaciones\M' then
      raise exception 'E01d DISPERSIÓN: la conversión de Coordinación vuelve a contar leads o el ledger';
    end if;
  end loop;
  -- La puerta no lee ninguna tabla: autoriza, valida, delega y da forma.
  select regexp_replace(lower(p.prosrc), '--[^\n]*', ' ', 'g') into v_cuerpo from pg_proc p where p.oid = v_puerta;
  if v_cuerpo ~ '\m(from|join)\s+crm\.' or v_cuerpo ~ '\m(from|join)\s+public\.' then
    raise exception 'E01g SALTO DE CAPA: la puerta lee tablas en vez de delegar en el núcleo';
  end if;
  select lower(p.prosrc) into v_cuerpo from pg_proc p where p.oid = v_base;
  if v_cuerpo !~ 'private\.conversion_neta_por_vendedor\(' or v_cuerpo !~ 'private\.conversion_mensual_por_vendedor\(' then
    raise exception 'E01e la base debe leer conversion_neta_por_vendedor (mes) y conversion_mensual_por_vendedor (rango)';
  end if;
  select lower(p.prosrc) into v_cuerpo from pg_proc p where p.oid = v_nucleo;
  if v_cuerpo !~ 'private\.conversion_divisor_base\(' or v_cuerpo !~ 'private\.conversion_episodios\(' then
    raise exception 'E01e el núcleo debe leer conversion_divisor_base y conversion_episodios';
  end if;
  select lower(p.prosrc) into v_cuerpo from pg_proc p where p.oid = v_puerta;
  if v_cuerpo !~ 'private\.puede_operar_reparto_crm\(\)' then
    raise exception 'E01f la puerta debe autorizar con private.puede_operar_reparto_crm()';
  end if;
end;
$estructura$;

-- ─────────────────────────────────────────────────────────────────────────────
-- E08 · Huellas del 30/09/2026 (lo que este cambio NO toca)
-- ─────────────────────────────────────────────────────────────────────────────
do $huellas$
declare
  v_esperadas jsonb := '{
    "private.conversion_neta_por_vendedor(date,boolean,uuid[])": "67d7b57536bad97083630a023caec865",
    "private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)": "9c606dd40fb9e4b0ea816731b04b1cb1",
    "private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)": "6e62d66e1c9536a50657245d6e633f56",
    "private.puede_operar_reparto_crm()": "38c03bf93b5d05873d387823c0dd760a",
    "crm.reporte_derivaciones_coordinacion_fn(date,date)": "033f8aeaba9668e66fe094b84cab4eb7",
    "crm.conversion_mensual_sin_cartera_fn(date)": "f613d94208b035f241c4e13b351c55be"
  }'::jsonb;
  v_firma text;
  v_md5 text;
begin
  for v_firma, v_md5 in select key, value #>> '{}' from jsonb_each(v_esperadas) loop
    if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure(v_firma)) is distinct from v_md5 then
      raise exception 'E08 % cambió de cuerpo respecto al 30/09/2026 (o no existe): revisar antes de fiarse de este oráculo', v_firma;
    end if;
  end loop;
end;
$huellas$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Siembra sintética (rollback al final). UUIDs reconocibles c0000000-…
-- ─────────────────────────────────────────────────────────────────────────────
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, confirmation_token,
  recovery_token, email_change_token, email_change, raw_app_meta_data,
  raw_user_meta_data, created_at, updated_at
)
select x.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
       x.correo, '', '', '', '', '', '{"provider":"email"}'::jsonb, '{}'::jsonb, now(), now()
from (values
  ('c0000000-0000-4000-8000-000000000001'::uuid, 'oraculo.coord@avancecorp.test'),
  ('c0000000-0000-4000-8000-000000000002'::uuid, 'oraculo.gerencia@avancecorp.test'),
  ('c0000000-0000-4000-8000-000000000003'::uuid, 'oraculo.sup1@avancecorp.test'),
  ('c0000000-0000-4000-8000-000000000004'::uuid, 'oraculo.sup2@avancecorp.test'),
  ('c0000000-0000-4000-8000-000000000005'::uuid, 'oraculo.ana@avancecorp.test'),
  ('c0000000-0000-4000-8000-000000000006'::uuid, 'oraculo.bea@avancecorp.test'),
  ('c0000000-0000-4000-8000-000000000007'::uuid, 'oraculo.carla@avancecorp.test'),
  ('c0000000-0000-4000-8000-000000000008'::uuid, 'oraculo.directorio@avancecorp.test'),
  ('c0000000-0000-4000-8000-000000000009'::uuid, 'oraculo.coord.inactiva@avancecorp.test')
) as x(id, correo);

insert into public.perfiles (id, nombre_completo, rol, activo, tipo_documento, debe_cambiar_password, titular_distinto, titular_distinto_usd)
values
  ('c0000000-0000-4000-8000-000000000001', 'ORACULO COORDINADORA', 'comercial', true, 'DNI', false, false, false),
  ('c0000000-0000-4000-8000-000000000002', 'ORACULO GERENCIA', 'admin', true, 'DNI', false, false, false),
  ('c0000000-0000-4000-8000-000000000003', 'ORACULO SUPERVISORA UNO', 'analista', true, 'DNI', false, false, false),
  ('c0000000-0000-4000-8000-000000000004', 'ORACULO SUPERVISOR DOS', 'analista', true, 'DNI', false, false, false),
  ('c0000000-0000-4000-8000-000000000005', 'ORACULO ANA', 'analista', true, 'DNI', false, false, false),
  ('c0000000-0000-4000-8000-000000000006', 'ORACULO BEA', 'analista', true, 'DNI', false, false, false),
  ('c0000000-0000-4000-8000-000000000007', 'ORACULO CARLA', 'analista', true, 'DNI', false, false, false),
  ('c0000000-0000-4000-8000-000000000008', 'ORACULO DIRECTORIO', 'directorio', true, 'DNI', false, false, false),
  ('c0000000-0000-4000-8000-000000000009', 'ORACULO COORDINADORA INACTIVA', 'comercial', true, 'DNI', false, false, false);

insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values
  ('c0000000-0000-4000-8000-000000000001', 'coordinador', null, true),
  ('c0000000-0000-4000-8000-000000000002', 'gerencia', null, true),
  ('c0000000-0000-4000-8000-000000000003', 'supervisor', null, true),
  ('c0000000-0000-4000-8000-000000000004', 'supervisor', null, true),
  ('c0000000-0000-4000-8000-000000000008', 'directorio', null, true),
  ('c0000000-0000-4000-8000-000000000009', 'coordinador', null, false);
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values
  ('c0000000-0000-4000-8000-000000000005', 'vendedor', 'c0000000-0000-4000-8000-000000000003', true),
  ('c0000000-0000-4000-8000-000000000006', 'vendedor', 'c0000000-0000-4000-8000-000000000003', true),
  ('c0000000-0000-4000-8000-000000000007', 'vendedor', 'c0000000-0000-4000-8000-000000000004', true);

-- Destinos del turno diario: la agenda solo admite supervisoras declaradas.
insert into private.agenda_reparto_destinos (supervisor_id, alias, orden) values
  ('c0000000-0000-4000-8000-000000000003', 'Oraculo uno', 8),
  ('c0000000-0000-4000-8000-000000000004', 'Oraculo dos', 9);

-- Leads en la COLA GLOBAL (sin dueño ni bandeja), como los deja la landing/hoja.
-- L6 nace a las 23:30 del último día del mes anterior (hora Lima).
insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, moneda, creado_en, alta_manual)
values
  ('c1000000-0000-4000-8000-000000000001', 'ORACULO LEAD UNO FORMULARIO', '+51900000001', 'formulario', 10000, 'PEN', now(), false),
  ('c1000000-0000-4000-8000-000000000002', 'ORACULO LEAD DOS FORMULARIO', '+51900000002', 'formulario', 10000, 'PEN', now(), false),
  ('c1000000-0000-4000-8000-000000000003', 'ORACULO LEAD TRES LANDING', '+51900000003', 'landing', 10000, 'PEN', now(), false),
  ('c1000000-0000-4000-8000-000000000004', 'ORACULO LEAD CUATRO MANUAL', '+51900000004', 'formulario', 10000, 'PEN', now(), true),
  ('c1000000-0000-4000-8000-000000000005', 'ORACULO LEAD CINCO REFERIDO', '+51900000005', 'referido', 10000, 'PEN', now(), false),
  ('c1000000-0000-4000-8000-000000000007', 'ORACULO LEAD SIETE SIN ASIGNAR', '+51900000007', 'formulario', 10000, 'PEN', now(), false);

-- L6 nace a las 23:30 del último día del mes anterior (hora Lima). El servidor
-- sella `creado_en` con su propio reloj en el guard de tenencia (candado
-- correcto: nadie fecha un lead a mano), así que un alta del pasado solo puede
-- sembrarse fuera de banda: se apaga ese guard para UNA sentencia dentro de
-- esta transacción (mismo patrón que la baja histórica del seed del gate) y se
-- vuelve a encender antes de seguir. Solo en un banco; nunca en producción.
alter table crm.leads disable trigger trg_leads_00_guard_tenencia;
insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, moneda, creado_en, alta_manual)
values ('c1000000-0000-4000-8000-000000000006', 'ORACULO LEAD SEIS BORDE', '+51900000006', 'formulario', 10000, 'PEN',
  (date_trunc('month', now() at time zone 'America/Lima') - interval '30 minutes') at time zone 'America/Lima', false);
alter table crm.leads enable trigger trg_leads_00_guard_tenencia;

do $siembra_ok$
begin
  if (select count(*) from crm.leads where id::text like 'c1000000-%' and vendedor_id is null and asignado_supervisor_id is null) <> 7 then
    raise exception 'S01 los 7 leads sintéticos no quedaron en la cola global';
  end if;
  if (select (creado_en at time zone 'America/Lima')::date from crm.leads where id = 'c1000000-0000-4000-8000-000000000006')
     <> (date_trunc('month', now() at time zone 'America/Lima') - interval '1 day')::date then
    raise exception 'S02 el alta del lead de borde no quedó en el último día del mes anterior (Lima)';
  end if;
  if private.rol_crm('c0000000-0000-4000-8000-000000000001') is distinct from 'coordinador'
     or private.rol_crm('c0000000-0000-4000-8000-000000000002') is distinct from 'gerencia'
     or private.rol_crm('c0000000-0000-4000-8000-000000000005') is distinct from 'vendedor'
     or private.rol_crm('c0000000-0000-4000-8000-000000000008') is distinct from 'directorio'
     or private.rol_crm('c0000000-0000-4000-8000-000000000009') is not null then
    raise exception 'S03 los roles sintéticos no resuelven como se esperaba';
  end if;
end;
$siembra_ok$;

-- Mes SELLADO sintético: dos meses atrás, con foto por persona y cobertura. La foto por
-- persona lleva su desglose por origen escrito a mano: el trigger que lo recalcula al
-- sellar (`trg_cierre_mes_vendedor_10_ranking_origen`, sobre datos vivos) se apaga para
-- ESTA siembra, porque aquí no hay datos vivos de hace dos meses. Solo en banco.
alter table crm.cierre_mes_vendedor disable trigger trg_cierre_mes_vendedor_10_ranking_origen;
insert into crm.periodos_cerrados (periodo, cerrado_en, cerrado_por, automatico, ponderacion_referido, meta_revision, cobertura)
values (
  (date_trunc('month', now() at time zone 'America/Lima') - interval '2 months')::date,
  now(), null, true, 0.5, 1,
  '{"medible": true, "modelo_conversion": "llegadas_v2", "fuera_ranking": [{"persona_id": "c0000000-0000-4000-8000-000000000003", "conversion": {"divisor": 5, "numerador": 1}}, {"persona_id": "c0000000-0000-4000-8000-000000000004", "conversion": null}], "conversion_sin_analista": {"divisor": 3, "numerador": 0}}'::jsonb
);
-- Tres meses atrás: foto con `conversion_sin_analista` en JSON null (ausencia).
insert into crm.periodos_cerrados (periodo, cerrado_en, cerrado_por, automatico, ponderacion_referido, meta_revision, cobertura)
values (
  (date_trunc('month', now() at time zone 'America/Lima') - interval '3 months')::date,
  now(), null, true, 0.5, 1,
  '{"medible": true, "modelo_conversion": "llegadas_v2", "fuera_ranking": [], "conversion_sin_analista": null}'::jsonb
);
insert into crm.cierre_mes_vendedor (
  periodo, vendedor_id, nombre_completo, supervisor_id, supervisor_nombre, divisor, divisor_aproximado,
  divisor_por_motivo, cierres_no_referidos, cierres_referidos, cierres_de_arrastre, numerador, conversion_pct,
  estado, referidos_recibidos, referidos_dados_de_alta, referidos_aporta_pct, procedencia, ajuste_numerador, ajuste_pen, ajuste_usd,
  conversion_objetivo, cartera, origenes_ranking
) values (
  (date_trunc('month', now() at time zone 'America/Lima') - interval '2 months')::date,
  'c0000000-0000-4000-8000-000000000005', 'ORACULO ANA', 'c0000000-0000-4000-8000-000000000003', 'ORACULO SUPERVISORA UNO',
  -- numerador 4 = 2 formulario + 1 landing + 2 referidos × 0,5 (1) + 0 upgrade… no: con la foto de abajo,
  -- partes = 2 + 1 + 2×0,5 + 1 upgrade + 2×0,5 renovación = 6 y ajuste_numerador 2 → neto 4.
  40, 0, '{"llegada": 40}'::jsonb, 3, 2, 0, 4, 10.00, 'sellado', 2, 0, null, '[]'::jsonb, 2, 0, 0,
  8.00,
  -- `operaciones_*` cuenta TODAS las operaciones; `conversiones_*` solo la primera elegible por
  -- cliente y mes, que es la que sumó el numerador. Se siembran distintas para cazar la confusión.
  '{"conversiones_clientes": 3, "conversiones_renovacion": 2, "conversiones_upgrade": 1, "operaciones_renovacion": 5, "operaciones_upgrade": 4, "capital_renovado_pen": 0, "capital_renovado_usd": 0, "capital_adicional_pen": 0, "capital_adicional_usd": 0, "renovaciones_sin_desglose": 0}'::jsonb,
  '{"disponible": true, "filas": [{"origen": "formulario", "leads": 20, "cierres": 2}, {"origen": "landing", "leads": 15, "cierres": 1}, {"origen": "referido", "leads": 3, "cierres": 2}, {"origen": "oficina", "leads": 2, "cierres": 1}, {"origen": "whatsapp", "leads": 1, "cierres": 1}]}'::jsonb
);
alter table crm.cierre_mes_vendedor enable trigger trg_cierre_mes_vendedor_10_ranking_origen;

-- ─────────────────────────────────────────────────────────────────────────────
-- Recorrido por las puertas REALES del reparto, como usuario autenticado.
-- ─────────────────────────────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', 'c0000000-0000-4000-8000-000000000001', true);
set local role authenticated;

do $recorrido$
declare
  v_coord uuid := 'c0000000-0000-4000-8000-000000000001';
  v_sup1 uuid := 'c0000000-0000-4000-8000-000000000003';
  v_sup2 uuid := 'c0000000-0000-4000-8000-000000000004';
  v_ana uuid := 'c0000000-0000-4000-8000-000000000005';
  v_bea uuid := 'c0000000-0000-4000-8000-000000000006';
  v_carla uuid := 'c0000000-0000-4000-8000-000000000007';
  v_l1 uuid := 'c1000000-0000-4000-8000-000000000001';
  v_l2 uuid := 'c1000000-0000-4000-8000-000000000002';
  v_l3 uuid := 'c1000000-0000-4000-8000-000000000003';
  v_l4 uuid := 'c1000000-0000-4000-8000-000000000004';
  v_l5 uuid := 'c1000000-0000-4000-8000-000000000005';
  v_l6 uuid := 'c1000000-0000-4000-8000-000000000006';
  v_hoy date := (now() at time zone 'America/Lima')::date;
begin
  -- Turno de hoy: landing → SUP2, formulario → SUP1 (obligatorio desde el 10/09).
  perform set_config('request.jwt.claim.sub', v_coord::text, true);
  perform crm.guardar_agenda_reparto_diaria(v_hoy, v_sup2, v_sup1);

  -- Coordinación reparte a las bandejas (L7 se queda en la cola a propósito).
  perform crm.repartir_lead(v_l1, v_sup1);
  perform crm.repartir_lead(v_l2, v_sup1);
  perform crm.repartir_lead(v_l3, v_sup2);
  perform crm.repartir_lead(v_l4, v_sup1);
  perform crm.repartir_lead(v_l5, v_sup1);
  perform crm.repartir_lead(v_l6, v_sup1);

  -- SUP1 entrega; devuelve a la bandeja antes de gestionar; vuelve a entregar.
  perform set_config('request.jwt.claim.sub', v_sup1::text, true);
  perform crm.derivar_leads_equipo_fn(array[v_l1, v_l2, v_l4, v_l5, v_l6], array[v_ana, v_ana, v_ana, v_ana, v_ana]);
  perform crm.revertir_derivacion_equipo_fn(v_l1);
  perform crm.derivar_leads_equipo_fn(array[v_l1], array[v_bea]);          -- L1: ANA → BEA
  perform crm.revertir_derivacion_equipo_fn(v_l2);
  perform crm.derivar_leads_equipo_fn(array[v_l2], array[v_bea]);
  perform crm.revertir_derivacion_equipo_fn(v_l2);
  perform crm.derivar_leads_equipo_fn(array[v_l2], array[v_ana]);          -- L2: ANA → BEA → ANA

  -- SUP2 entrega la landing sin vueltas.
  perform set_config('request.jwt.claim.sub', v_sup2::text, true);
  perform crm.derivar_leads_equipo_fn(array[v_l3], array[v_carla]);
end;
$recorrido$;

-- Las comprobaciones de tenencia y ledger se hacen con la consola (sin RLS):
-- a la coordinadora la RLS no le enseña esos leads, y eso es correcto.
reset role;
do $recorrido_ok$
declare
  v_ana uuid := 'c0000000-0000-4000-8000-000000000005';
  v_bea uuid := 'c0000000-0000-4000-8000-000000000006';
  v_carla uuid := 'c0000000-0000-4000-8000-000000000007';
  v_l1 uuid := 'c1000000-0000-4000-8000-000000000001';
  v_l2 uuid := 'c1000000-0000-4000-8000-000000000002';
  v_l3 uuid := 'c1000000-0000-4000-8000-000000000003';
begin
  if (select vendedor_id from crm.leads where id = v_l1) is distinct from v_bea
     or (select vendedor_id from crm.leads where id = v_l2) is distinct from v_ana
     or (select vendedor_id from crm.leads where id = v_l3) is distinct from v_carla then
    raise exception 'R01 la tenencia final no es la esperada (L1→BEA, L2→ANA, L3→CARLA)';
  end if;
  if (select count(*) from crm.lead_asignaciones where lead_id = v_l1) <> 2
     or (select count(*) from crm.lead_asignaciones where lead_id = v_l2) <> 3 then
    raise exception 'R02 el ledger no registró los episodios esperados (L1: 2, L2: 3)';
  end if;
  if not exists (
    select 1 from crm.lead_asignaciones a
    where a.lead_id = v_l1 and a.analista_id = v_ana and a.motivo_cierre = 'parqueado'
      and a.supervisor_destino_id = a.supervisor_origen_id
  ) then
    raise exception 'R03 la devolución a la misma bandeja no quedó como «parqueado» del mismo supervisor';
  end if;
end;
$recorrido_ok$;
set local role authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- E02/E03 · Autorización y período
-- ─────────────────────────────────────────────────────────────────────────────
do $autorizacion$
declare
  v_mes date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_quien uuid;
  v_etiqueta text;
begin
  for v_quien, v_etiqueta in
    select * from (values
      ('c0000000-0000-4000-8000-000000000005'::uuid, 'vendedor'),
      ('c0000000-0000-4000-8000-000000000003'::uuid, 'supervisor'),
      ('c0000000-0000-4000-8000-000000000008'::uuid, 'directorio'),
      ('c0000000-0000-4000-8000-000000000009'::uuid, 'coordinador inactivo')
    ) as t(id, etiqueta)
  loop
    perform set_config('request.jwt.claim.sub', v_quien::text, true);
    begin
      perform crm.conversion_divisor_coordinacion_fn(v_mes);
      raise exception 'E02 % entró a la conversión de Coordinación', v_etiqueta;
    exception when insufficient_privilege then null;
    end;
    -- Gate ANTES que validación: un mes futuro también da 42501 para el denegado.
    begin
      perform crm.conversion_divisor_coordinacion_fn((v_mes + interval '1 month')::date);
      raise exception 'E02b % con mes futuro no recibió 42501', v_etiqueta;
    exception when insufficient_privilege then null;
    end;
  end loop;

  perform set_config('request.jwt.claim.sub', '', true);
  begin
    perform crm.conversion_divisor_coordinacion_fn(v_mes);
    raise exception 'E02c sin identidad entró a la conversión de Coordinación';
  exception when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claim.sub', 'c0000000-0000-4000-8000-000000000001', true);
  begin
    perform crm.conversion_divisor_coordinacion_fn((v_mes + interval '1 month')::date);
    raise exception 'E03a el coordinador pudo pedir un mes futuro';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform crm.conversion_divisor_coordinacion_fn(v_mes + 14);
    raise exception 'E03b se aceptó un día que no es el primero del mes';
  exception when sqlstate '22023' then null;
  end;
end;
$autorizacion$;

-- ─────────────────────────────────────────────────────────────────────────────
-- E04/E05/E06 · Regla del divisor, paridad con el núcleo y contraste con entregas
-- ─────────────────────────────────────────────────────────────────────────────
do $divisor$
declare
  v_coord uuid := 'c0000000-0000-4000-8000-000000000001';
  v_ger uuid := 'c0000000-0000-4000-8000-000000000002';
  v_ana uuid := 'c0000000-0000-4000-8000-000000000005';
  v_bea uuid := 'c0000000-0000-4000-8000-000000000006';
  v_carla uuid := 'c0000000-0000-4000-8000-000000000007';
  v_mes date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_mes_previo date := (date_trunc('month', now() at time zone 'America/Lima') - interval '1 month')::date;
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_pay jsonb;
  v_pay_ger jsonb;
  v_prev jsonb;
  v_reporte jsonb;
  v_fila jsonb;
  v_ana_f int; v_ana_l int; v_ana_d int;
  v_bea_d int; v_carla_d int; v_carla_l int;
  v_bea_entregas int;
begin
  perform set_config('request.jwt.claim.sub', v_coord::text, true);
  v_pay := crm.conversion_divisor_coordinacion_fn(v_mes);

  if (v_pay->>'version')::int <> 1 or v_pay->>'alcance' <> 'global' or (v_pay->>'sellado')::boolean
     or v_pay->'periodo'->>'desde' <> v_mes::text or v_pay->'periodo'->>'zona' <> 'America/Lima' then
    raise exception 'E04a cabecera del payload inesperada: %', v_pay - 'analistas';
  end if;
  if v_pay::text ~ '"(lead_id|telefono|correo|dni|monto_estimado|nota|nombre_completo)"' then
    raise exception 'E04b el payload expone datos de leads o PII de contacto';
  end if;

  select (a->>'divisor_formulario')::int, (a->>'divisor_landing')::int, (a->>'divisor')::int
    into v_ana_f, v_ana_l, v_ana_d
  from jsonb_array_elements(v_pay->'analistas') a where a->>'analista_id' = v_ana::text;
  select coalesce((a->>'divisor')::int, 0) into v_bea_d
  from jsonb_array_elements(v_pay->'analistas') a where a->>'analista_id' = v_bea::text;
  select (a->>'divisor')::int, (a->>'divisor_landing')::int into v_carla_d, v_carla_l
  from jsonb_array_elements(v_pay->'analistas') a where a->>'analista_id' = v_carla::text;

  -- ANA recibió primero L1 (→BEA) y L2 (→BEA→ANA): 2 formulario. L4 manual y L5 referido: 0. L6 es del mes anterior.
  if v_ana_f is distinct from 2 or v_ana_l is distinct from 0 or v_ana_d is distinct from 2 then
    raise exception 'E04c ANA esperaba formulario 2 / landing 0 / divisor 2 y tiene %/%/%', v_ana_f, v_ana_l, v_ana_d;
  end if;
  -- BEA recibió L1 y L2 por reasignación: NO cambia su divisor.
  if coalesce(v_bea_d, 0) <> 0 then
    raise exception 'E04d el lead reasignado sumó al divisor de BEA (%)', v_bea_d;
  end if;
  if v_carla_d is distinct from 1 or v_carla_l is distinct from 1 then
    raise exception 'E04e CARLA esperaba 1 landing y tiene divisor % / landing %', v_carla_d, v_carla_l;
  end if;
  -- L7 nunca se asignó: cuenta en la empresa, sin responsable.
  if (v_pay->'sin_analista'->>'divisor')::int is distinct from 1 then
    raise exception 'E04f el lead sin asignar no quedó en «sin analista» (%)', v_pay->'sin_analista';
  end if;
  if (v_pay->'empresa'->>'divisor')::int <> 4
     or (v_pay->'empresa'->>'divisor_formulario')::int <> 3
     or (v_pay->'empresa'->>'divisor_landing')::int <> 1 then
    raise exception 'E04g la empresa esperaba 4 = 3 formulario + 1 landing y tiene %', v_pay->'empresa';
  end if;
  -- Nombres y supervisor del mes salen del perfil y del roster/equipo.
  if not exists (
    select 1 from jsonb_array_elements(v_pay->'analistas') a
    where a->>'analista_id' = v_ana::text and a->>'nombre' = 'ORACULO ANA'
      and a->>'supervisor_id' = 'c0000000-0000-4000-8000-000000000003'
      and a->>'supervisor_nombre' = 'ORACULO SUPERVISORA UNO'
  ) then
    raise exception 'E04h la fila de ANA no trae su nombre y supervisor';
  end if;

  -- Borde de mes: L6 (alta 23:30 del último día del mes anterior, repartido HOY) pesa en el mes anterior, en ANA.
  v_prev := crm.conversion_divisor_coordinacion_fn(v_mes_previo);
  if (select (a->>'divisor_formulario')::int from jsonb_array_elements(v_prev->'analistas') a where a->>'analista_id' = v_ana::text) is distinct from 1 then
    raise exception 'E04i el alta de las 23:30 del último día (Lima) no quedó en el mes anterior para ANA: %', v_prev->'analistas';
  end if;

  -- E05a–c se comprueban con la consola (el núcleo privado no tiene ejecutores de la API).
  perform set_config('oraculo.pay', v_pay::text, true);

  -- Gerencia recibe exactamente lo mismo (misma foto, distinto reloj).
  perform set_config('request.jwt.claim.sub', v_ger::text, true);
  v_pay_ger := crm.conversion_divisor_coordinacion_fn(v_mes);
  if (v_pay_ger - 'generado_en') <> (v_pay - 'generado_en') then
    raise exception 'E05d Gerencia no recibió el mismo payload que Coordinación';
  end if;

  -- E06 · Contraste con el reporte de entregas: allí L1 cuenta en BEA (la devolución
  -- a la misma bandeja deja de sumar y la re-entrega sí suma).
  perform set_config('request.jwt.claim.sub', v_coord::text, true);
  v_reporte := crm.reporte_derivaciones_coordinacion_fn(v_hoy, v_hoy);
  select coalesce(sum((e->>'derivados')::int), 0) into v_bea_entregas
  from jsonb_array_elements(v_reporte->'dias') d
  cross join lateral jsonb_array_elements(d->'entregas') e
  where e->>'analista_id' = v_bea::text and e->>'origen' = 'formulario';
  if v_bea_entregas <> 1 then
    raise exception 'E06 el reporte de entregas debía contar L1 en BEA (1) y cuenta %', v_bea_entregas;
  end if;
end;
$divisor$;


-- E05 · Paridad fila a fila con el núcleo (la pieza que usa Metas), con la consola.
reset role;
do $paridad$
declare
  v_mes date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_fin date := (date_trunc('month', now() at time zone 'America/Lima') + interval '1 month' - interval '1 day')::date;
  v_pay jsonb := current_setting('oraculo.pay')::jsonb;
begin
  if exists (
    select 1
    from jsonb_array_elements(v_pay->'analistas') a
    full join (
      select * from private.conversion_neta_por_vendedor(v_mes, true, null::uuid[]) x
      where x.analista_id is not null
    ) n on n.analista_id = (a->>'analista_id')::uuid
    where a is null
       or n.analista_id is null
       or (a->>'divisor')::int is distinct from n.divisor
       or (a->>'numerador')::numeric is distinct from n.numerador
       or (a->>'conversion_pct')::numeric is distinct from n.conversion_pct
       or (a->>'divisor_formulario')::int + (a->>'divisor_landing')::int <> (a->>'divisor')::int
  ) then
    raise exception 'E05a la pantalla no reproduce el núcleo fila a fila';
  end if;
  -- v2: cada analista trae desglose y sus partes suman el numerador bruto; el neto lleva el ajuste.
  if exists (
    select 1 from jsonb_array_elements(v_pay->'analistas') a
    where (a->>'desglose_disponible')::boolean is not true
       or (a->>'numerador_bruto')::numeric is distinct from
          (a#>>'{cierres,formulario}')::numeric + (a#>>'{cierres,landing}')::numeric + (a#>>'{cierres,referido_aporte}')::numeric
          + (a#>>'{cartera,upgrade}')::numeric + (a#>>'{cartera,renovacion_aporte}')::numeric
       or (a->>'numerador')::numeric is distinct from private.conversion_con_ajuste((a->>'numerador_bruto')::numeric, (a->>'ajuste_pendiente')::numeric)
  ) then
    raise exception 'E05f el desglose de cierres no suma el numerador en el payload';
  end if;
  if v_pay->'periodo'->>'modo' is distinct from 'mes' or (v_pay->'periodo'->>'dias')::int is distinct from (v_fin - v_mes + 1)
     or (v_pay->'periodo'->>'hasta')::date is distinct from v_fin then
    raise exception 'E05g el período del payload no describe el mes (modo, dias, hasta inclusivo): %', v_pay->'periodo';
  end if;
  -- La fila SIN analista del núcleo (id nulo) es exactamente `sin_analista`.
  if (v_pay->'sin_analista'->>'divisor')::int is distinct from
     (select n.divisor from private.conversion_neta_por_vendedor(v_mes, true, null::uuid[]) n where n.analista_id is null) then
    raise exception 'E05e «sin analista» no es la fila sin analista del núcleo';
  end if;
  if (select coalesce(sum((a->>'divisor')::int), 0) from jsonb_array_elements(v_pay->'analistas') a)
       + coalesce((v_pay->'sin_analista'->>'divisor')::int, 0)
     <> (v_pay->'empresa'->>'divisor')::int then
    raise exception 'E05b la empresa no suma analistas + sin analista';
  end if;
  if (v_pay->'empresa'->>'divisor')::int
     <> (select coalesce(sum(n.divisor), 0) from private.conversion_neta_por_vendedor(v_mes, true, null::uuid[]) n) then
    raise exception 'E05c el total de la empresa no es el del núcleo';
  end if;

end;
$paridad$;
set local role authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- E09 · Modo rango
-- ─────────────────────────────────────────────────────────────────────────────
do $rango$
declare
  v_coord uuid := 'c0000000-0000-4000-8000-000000000001';
  v_ana uuid := 'c0000000-0000-4000-8000-000000000005';
  v_mes date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_fin date := (date_trunc('month', now() at time zone 'America/Lima') + interval '1 month' - interval '1 day')::date;
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_mes_sellado date := (date_trunc('month', now() at time zone 'America/Lima') - interval '2 months')::date;
  v_mes_previo date := (date_trunc('month', now() at time zone 'America/Lima') - interval '1 month')::date;
  v_pay_mes jsonb;
  v_pay jsonb;
  v_pay_prev jsonb;
begin
  perform set_config('request.jwt.claim.sub', v_coord::text, true);
  v_pay_mes := crm.conversion_divisor_coordinacion_fn(v_mes);

  -- (a) Un rango que es exactamente un mes calendario ES ese mes (misma foto, salvo el
  --     reloj). Se usa el mes ANTERIOR, que siempre está completo en el pasado.
  v_pay := crm.conversion_divisor_coordinacion_fn(null, v_mes_previo, (v_mes - interval '1 day')::date);
  if (v_pay - 'generado_en') <> (crm.conversion_divisor_coordinacion_fn(v_mes_previo) - 'generado_en')
     or v_pay->'periodo'->>'modo' <> 'mes' or v_pay->'fuente'->>'modo' <> 'mensual'
     or (v_pay->'periodo'->>'cruza_meses_sellados')::boolean is not false then
    raise exception 'E09a el rango 1 → fin del mes anterior no es idéntico al mes: %', v_pay->'periodo';
  end if;
  -- (a2) El mes anterior abierto por rango tiene a ANA con L6 (alta del último día del mes anterior).
  if (select (a->>'divisor')::int from jsonb_array_elements(v_pay->'analistas') a where a->>'analista_id' = v_ana::text) is distinct from 1 then
    raise exception 'E09a2 el mes anterior por rango no trae la llegada de borde de ANA';
  end if;

  -- (b) Del 1 a hoy: modo rango (salvo el último día del mes, en que ES el mes),
  --     reproduce las cifras del mes (nada vive en el futuro), sin ajuste.
  v_pay := crm.conversion_divisor_coordinacion_fn(null, v_mes, v_hoy);
  if v_pay->'periodo'->>'modo' <> (case when v_hoy = v_fin then 'mes' else 'rango' end)
     or (v_pay->>'sellado')::boolean
     or (v_pay->'periodo'->>'dias')::int <> (v_hoy - v_mes + 1)
     or (v_hoy <> v_fin and v_pay->'periodo'->'mes' <> 'null'::jsonb)
     or (v_pay->'empresa'->>'divisor')::int is distinct from (v_pay_mes->'empresa'->>'divisor')::int
     or (v_pay->'empresa'->>'numerador_bruto')::numeric is distinct from (v_pay_mes->'empresa'->>'numerador_bruto')::numeric
     or (v_hoy <> v_fin and ((v_pay->'empresa'->>'ajuste_pendiente')::numeric is distinct from 0
                             or (v_pay->'empresa'->>'numerador')::numeric is distinct from (v_pay->'empresa'->>'numerador_bruto')::numeric
                             or v_pay->'fuente'->>'modo' is distinct from 'rango_vivo'))
     or (select (a->>'divisor')::int from jsonb_array_elements(v_pay->'analistas') a where a->>'analista_id' = v_ana::text) is distinct from 2 then
    raise exception 'E09b el rango 1 → hoy no reproduce el bruto del mes: % vs %', v_pay->'empresa', v_pay_mes->'empresa';
  end if;

  -- (b2) Un rango REAL cualquier día del año: del 15 del mes anterior a hoy cruza el
  --      límite de mes, nunca es «mes exacto» y cae en modo rango_vivo; sus partes
  --      suman su bruto, no lleva ajuste, y sus llegadas son la suma de las dos piezas.
  v_pay := crm.conversion_divisor_coordinacion_fn(null, (v_mes_previo + 14)::date, v_hoy);
  v_pay_prev := crm.conversion_divisor_coordinacion_fn(null, (v_mes_previo + 14)::date, (v_mes - interval '1 day')::date);
  if v_pay->'periodo'->>'modo' <> 'rango' or v_pay->'fuente'->>'modo' <> 'rango_vivo' or (v_pay->>'sellado')::boolean
     or (v_pay->'periodo'->>'cruza_meses_sellados')::boolean is not false
     or (v_pay->'empresa'->>'ajuste_pendiente')::numeric is distinct from 0
     or (v_pay->'empresa'->>'numerador')::numeric is distinct from (v_pay->'empresa'->>'numerador_bruto')::numeric
     or (v_pay->'empresa'->>'divisor')::int is distinct from (v_pay_prev->'empresa'->>'divisor')::int + (v_pay_mes->'empresa'->>'divisor')::int
     or exists (
       select 1 from jsonb_array_elements(v_pay->'analistas') a
       where (a->>'numerador_bruto')::numeric is distinct from
             (a#>>'{cierres,formulario}')::numeric + (a#>>'{cierres,landing}')::numeric + (a#>>'{cierres,referido_aporte}')::numeric
             + (a#>>'{cartera,upgrade}')::numeric + (a#>>'{cartera,renovacion_aporte}')::numeric
          or (a->>'ajuste_pendiente')::numeric is distinct from 0
          or (a->>'numerador')::numeric is distinct from (a->>'numerador_bruto')::numeric) then
    raise exception 'E09b2 el rango que cruza el mes anterior no cumple la invariante: %', v_pay->'empresa';
  end if;
  -- (b3) Un rango libre que TOCA el mes sellado lo declara.
  v_pay := crm.conversion_divisor_coordinacion_fn(null, (v_mes_sellado + 14)::date, v_hoy);
  if (v_pay->'periodo'->>'cruza_meses_sellados')::boolean is not true or v_pay->'fuente'->>'modo' <> 'rango_vivo' or (v_pay->>'sellado')::boolean then
    raise exception 'E09b3 el rango que cruza un mes sellado no lo declara: %', v_pay->'periodo';
  end if;

  -- (c) Un rango parcial no puede superar al mes (L1 y L2 nacieron hoy: del 1 a ayer ANA no las tiene).
  if v_hoy > v_mes then
    v_pay := crm.conversion_divisor_coordinacion_fn(null, v_mes, v_hoy - 1);
    if coalesce((select (a->>'divisor')::int from jsonb_array_elements(v_pay->'analistas') a where a->>'analista_id' = v_ana::text), 0) <> 0 then
      raise exception 'E09c el rango que termina ayer atribuye a ANA llegadas de hoy';
    end if;
  end if;

  -- (d) Un rango que es exactamente el mes sellado sirve la foto (sellado = true).
  v_pay := crm.conversion_divisor_coordinacion_fn(null, v_mes_sellado, (v_mes_sellado + interval '1 month' - interval '1 day')::date);
  if (v_pay->>'sellado')::boolean is not true or v_pay->'periodo'->>'modo' <> 'mes' then
    raise exception 'E09d el rango del mes sellado no sirvió la foto: %', v_pay->'periodo';
  end if;

  -- (e) Rangos inválidos → 22023 (gate primero: sigue siendo la coordinadora).
  begin
    perform crm.conversion_divisor_coordinacion_fn(null, v_hoy, v_hoy - 1);
    raise exception 'E09e aceptó desde > hasta';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform crm.conversion_divisor_coordinacion_fn(null, v_hoy, v_hoy + 1);
    raise exception 'E09f aceptó un rango con futuro';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform crm.conversion_divisor_coordinacion_fn(null, v_hoy - 366, v_hoy);
    raise exception 'E09g aceptó un rango de más de 366 días';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform crm.conversion_divisor_coordinacion_fn(v_mes, v_mes, v_hoy);
    raise exception 'E09h aceptó mes y rango a la vez';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform crm.conversion_divisor_coordinacion_fn(null, v_mes, null);
    raise exception 'E09i aceptó un rango con una sola fecha';
  exception when sqlstate '22023' then null;
  end;
  -- Y un vendedor con rango sigue fuera (42501 antes que cualquier validación).
  perform set_config('request.jwt.claim.sub', v_ana::text, true);
  begin
    perform crm.conversion_divisor_coordinacion_fn(null, v_mes, v_hoy);
    raise exception 'E09j un vendedor entró por el modo rango';
  exception when insufficient_privilege then null;
  end;
end;
$rango$;

-- ─────────────────────────────────────────────────────────────────────────────
-- E07 · Mes sellado: foto, sin desglose, sin recalcular
-- ─────────────────────────────────────────────────────────────────────────────
do $sellado$
declare
  v_mes date := (date_trunc('month', now() at time zone 'America/Lima') - interval '2 months')::date;
  v_pay jsonb;
  v_fila jsonb;
begin
  perform set_config('request.jwt.claim.sub', 'c0000000-0000-4000-8000-000000000001', true);
  v_pay := crm.conversion_divisor_coordinacion_fn(v_mes);
  if not (v_pay->>'sellado')::boolean then
    raise exception 'E07a el mes sellado no se declaró sellado';
  end if;
  select a into v_fila from jsonb_array_elements(v_pay->'analistas') a
  where a->>'analista_id' = 'c0000000-0000-4000-8000-000000000005';
  if v_fila is null or (v_fila->>'divisor')::int is distinct from 40 or (v_fila->>'numerador')::numeric is distinct from 4
     or (v_fila->>'conversion_pct')::numeric is distinct from 10.00
     or v_fila->'divisor_formulario' is distinct from 'null'::jsonb or v_fila->'divisor_landing' is distinct from 'null'::jsonb
     or v_fila->'numerador_bruto' is distinct from 'null'::jsonb or v_fila->'ajuste_pendiente' is distinct from 'null'::jsonb then
    raise exception 'E07b la fila sellada no es la foto (40 / 4 / 10.00, sin llegadas por origen ni bruto): %', v_fila;
  end if;
  -- El desglose sellado sale de la foto: origenes_ranking.filas (conteos por origen) y
  -- cartera.conversiones_* (NO operaciones_*), con los pesos SELLADOS (0,5); y sus partes
  -- reproducen el numerador de la foto más el ajuste que se aplicó al sellar (6 − 2 = 4).
  if (v_fila->>'desglose_disponible')::boolean is not true
     or (v_fila#>>'{cierres,formulario}')::int is distinct from 2 or (v_fila#>>'{cierres,landing}')::int is distinct from 1
     or (v_fila#>>'{cierres,referido}')::int is distinct from 2 or (v_fila#>>'{cierres,referido_aporte}')::numeric is distinct from 1.0
     or (v_fila#>>'{cierres,oficina}')::int is distinct from 1 or (v_fila#>>'{cierres,otros}')::int is distinct from 1
     or (v_fila#>>'{cartera,upgrade}')::int is distinct from 1 or (v_fila#>>'{cartera,renovacion}')::int is distinct from 2
     or (v_fila#>>'{cartera,renovacion_aporte}')::numeric is distinct from 1.0 then
    raise exception 'E07b2 el desglose sellado no sale de la foto (conversiones_*, pesos sellados): %', v_fila;
  end if;
  if (v_fila#>>'{cierres,formulario}')::numeric + (v_fila#>>'{cierres,landing}')::numeric + (v_fila#>>'{cierres,referido_aporte}')::numeric
     + (v_fila#>>'{cartera,upgrade}')::numeric + (v_fila#>>'{cartera,renovacion_aporte}')::numeric
     is distinct from (v_fila->>'numerador')::numeric + 2 /* ajuste_numerador sembrado en la foto */ then
    raise exception 'E07b3 las partes selladas no reproducen numerador + ajuste de la foto: %', v_fila;
  end if;
  -- Empresa = foto por persona (40 / 4) + fuera_ranking con conversión (5 / 1) + sin analista (3 / 0).
  if (v_pay->'empresa'->>'divisor')::int is distinct from 48 or (v_pay->'empresa'->>'numerador')::numeric is distinct from 5
     or (v_pay->'empresa'->>'conversion_pct')::numeric is distinct from round(100.0 * 5 / 48, 2)
     or (v_pay->'sin_analista'->>'divisor')::int is distinct from 3
     or v_pay->'empresa'->'divisor_formulario' is distinct from 'null'::jsonb
     or (v_pay->>'peso_referido')::numeric is distinct from 0.5
     or (v_pay->'empresa'->>'desglose_disponible')::boolean is not false
     or v_pay->'empresa'->'cierres' is distinct from 'null'::jsonb
     or v_pay->'fuente'->>'modo' is distinct from 'foto' then
    raise exception 'E07c la empresa sellada no suma foto + fuera_ranking + sin analista, o declara un desglose que no cubre el total: %', v_pay->'empresa';
  end if;
  -- Foto con conversion_sin_analista en JSON null: ausencia, no un objeto de nulos.
  v_pay := crm.conversion_divisor_coordinacion_fn((v_mes - interval '1 month')::date);
  if (v_pay->>'sellado')::boolean is not true or v_pay->'sin_analista' is distinct from 'null'::jsonb
     or (v_pay->'empresa'->>'divisor')::int is distinct from 0 or jsonb_array_length(v_pay->'analistas') is distinct from 0 then
    raise exception 'E07e una foto con conversion_sin_analista null debe servir sin_analista = null: %', v_pay - 'analistas';
  end if;
end;
$sellado$;


reset role;
-- E07f · La suma sellada de la empresa es la MISMA que sirve la puerta mensual oficial a
-- gerencia (foto por persona + fuera_ranking + sin analista). La oficial deniega al coordinador
-- y solo la ejecuta su envoltorio, así que aquí se llama con la consola y la identidad de gerencia.
do $sellado_oficial$
declare
  v_mes date := (date_trunc('month', now() at time zone 'America/Lima') - interval '2 months')::date;
  v_pay jsonb;
  v_oficial jsonb;
begin
  perform set_config('request.jwt.claim.sub', 'c0000000-0000-4000-8000-000000000002', true);
  v_pay := crm.conversion_divisor_coordinacion_fn(v_mes);
  v_oficial := crm.conversion_mensual_sin_cartera_fn(v_mes);
  if (v_oficial->'total'->>'divisor')::int is distinct from (v_pay->'empresa'->>'divisor')::int
     or (v_oficial->'total'->>'numerador')::numeric is distinct from (v_pay->'empresa'->>'numerador')::numeric then
    raise exception 'E07f la empresa sellada (%) no coincide con el total de la puerta oficial (%)',
      v_pay->'empresa', v_oficial->'total';
  end if;
end;
$sellado_oficial$;

-- El núcleo vivo se niega a recalcular un mes sellado: la puerta sirve la foto y no lo llama.
do $sellado_nucleo$
declare
  v_mes date := (date_trunc('month', now() at time zone 'America/Lima') - interval '2 months')::date;
begin
  begin
    perform private.conversion_neta_por_vendedor(v_mes, true, null::uuid[]);
    raise exception 'E07d el núcleo recalculó un mes sellado';
  exception when sqlstate '22023' then null;
  end;
end;
$sellado_nucleo$;

select 'ORACULO-DIVISOR-COORDINACION-OK' as resultado;

rollback;
