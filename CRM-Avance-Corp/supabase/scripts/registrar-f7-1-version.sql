-- Registra 20260831040000 CON su cuerpo - fail-closed, etiqueta propia.
-- Candados: mundo-vivo (las 7 cerradas + las filas en el libro + HONESTIDAD
-- TEMPORAL: se publica en la ventana de fechas que el seed declara),
-- NULL-statements revienta, relectura post-insert.
do $reg_f71$
declare v_a text[]; v_nombre text; v_n integer;
begin
  if (select p.proacl::text from pg_proc p
      where p.oid = 'crm.metricas_cartera_fn(date)'::regprocedure)
     is distinct from '{postgres=X/postgres}' then
    raise exception 'Registro F7.1: el mundo vivo NO esta migrado — aplicar antes de registrar';
  end if;
  select count(*) into v_n from private.f7_piezas_en_observacion
   where ola = 'F7.1' and current_date between cerrada_en and cerrada_en + 2;
  if v_n <> 7 then
    raise exception 'Registro F7.1: las filas de la ola no estan o su fecha de cierre no coincide con la publicacion real (regenerar fechas del seed)';
  end if;

  select statements into v_a from supabase_migrations.schema_migrations where version='20260831040000';
  if found and v_a is null then
    raise exception 'La version 20260831040000 existe SIN cuerpo (statements NULL): repararla con UPDATE, no re-insertar'; end if;
  if found and v_a <> array[$mig_f71$-- P-055 F7.1 - CERRAR LO QUE QUEDO SUELTO (Fase 7, Ola 1).
--
-- Siete cierres, CERO derribos (plan por olas aprobado por Miguel el 31/08;
-- tabla de OK de esta ola en MIGRACIONES.md). Tres grupos:
--  * SUPERSEDIDAS (a observacion, demolibles 14/09): las puertas v1 y v2 de
--    distribucion de leads (la pantalla viva usa v3; los CORES private siguen
--    vivos - v3_core llama a v2_core). ⚠️ Su dueño es crm_metricas_bridge:
--    el revoke va con SET LOCAL ROLE (un revoke como postgres seria un no-op
--    EN SILENCIO - warning sin efecto).
--  * SOLO-INTERNAS (cerradas PERMANENTES, jamas se derriban): metricas_cartera_fn
--    (unico llamador: conversion_mensual_fn), crear/actualizar_contrato_con_cuenta
--    (organos de pdf_v2/v3) y public.actualizar_numero_contrato (organo de su
--    pdf_v3; ⚠️ toca public - OK explicito de Miguel via su !). La delegacion
--    DEFINER sobrevive: el chequeo de EXECUTE interno corre como OWNER.
--    service_role tambien pierde el EXECUTE que tenia en cartera y numero
--    (0 edges/front las llaman - censo 30-31/08).
--  * LA SIN PARTIDA DE NACIMIENTO: crm.metricas_altas_analista_fn existe en
--    prod SIN DDL en las 167 migraciones (nacio en una de las 12 versiones
--    MUDAS del registro). Aqui se ADOPTA (create or replace con su cuerpo
--    VIVO al byte; pin md5 antes == despues) y LUEGO se cierra (observacion).
--
-- El censo de llamadores/superficies de las 7 lo hace el POSTFLIGHT llamando a
-- private.assert_f7_piezas_cerradas() (el vigilante de la Ola 0, ya endurecido
-- por dos auditorias) sobre las filas recien sembradas.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- =====================================================================
-- 0) PREFLIGHT.
-- =====================================================================
do $$
declare
  -- las 7 (huella + ACL EXACTOS medidos el 31/08):
  v_fn constant text[][] := array[
    array['crm.metricas_distribucion_leads_fn(date,date)',    '9ed153979997aab76667667a58b8b2ee', '{crm_metricas_bridge=X/crm_metricas_bridge,authenticated=X/crm_metricas_bridge}'],
    array['crm.metricas_distribucion_leads_v2_fn(date,date)', 'c7294f041b629b695c9c3f712abec2a0', '{crm_metricas_bridge=X/crm_metricas_bridge,authenticated=X/crm_metricas_bridge}'],
    array['crm.metricas_cartera_fn(date)',                    '0b4ede547cf7079be1e56073311453b3', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'],
    array['crm.metricas_altas_analista_fn(integer)',          'df8a99e0dfc4e1d94794073787aa84d7', '{postgres=X/postgres,authenticated=X/postgres}'],
    array['crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)', '5c92f416c4e34fd4ed864c8be19502eb', '{postgres=X/postgres,authenticated=X/postgres}'],
    array['crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)', 'bdaa1a2753c4f82d87e7e2c28bd80b87', '{postgres=X/postgres,authenticated=X/postgres}'],
    array['public.actualizar_numero_contrato(uuid,text,text,text)', '44270f9706a4515b16962ead8b09ea59', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}']
  ];
  -- delegantes que NO deben moverse (pin md5 univalente):
  v_amb constant text[][] := array[
    array['crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)',  '68cc6c91e84061c0bdf6a62306085c14'],
    array['crm.actualizar_contrato_con_cuenta_pdf_v3(uuid,jsonb,jsonb)', '85614480d6c8939e818342ef3fe63c65'],
    array['crm.actualizar_numero_contrato_pdf_v3(uuid,text,text,text)',  '11ad77e85abd0b9be7790240a6e27c1e']
  ];
  v_fila text[]; v_h text; v_acl text;
begin
  foreach v_fila slice 1 in array v_fn loop
    select md5(p.prosrc), p.proacl::text into v_h, v_acl
      from pg_proc p where p.oid = v_fila[1]::regprocedure;
    if v_h is distinct from v_fila[2] then
      raise exception 'F7.1 preflight: % cambio desde la medicion (huella %)', v_fila[1], v_h;
    end if;
    if v_acl is distinct from v_fila[3] then
      raise exception 'F7.1 preflight: ACL de % no es la medida (%)', v_fila[1], v_acl;
    end if;
  end loop;
  foreach v_fila slice 1 in array v_amb loop
    select md5(p.prosrc) into v_h from pg_proc p where p.oid = v_fila[1]::regprocedure;
    if v_h is distinct from v_fila[2] then
      raise exception 'F7.1 preflight: el delegante % cambio (huella %)', v_fila[1], v_h;
    end if;
  end loop;
  -- conversion_mensual_fn: por MENCION + forma (ATR-4 la roza; sin pin md5):
  if not exists (select 1 from pg_proc p
    where p.oid = 'crm.conversion_mensual_fn(date)'::regprocedure
      and p.prosecdef and p.proowner = 'postgres'::regrole
      and strpos(p.prosrc, 'metricas_cartera_fn') > 0) then
    raise exception 'F7.1 preflight: conversion_mensual_fn ya no delega en metricas_cartera_fn';
  end if;
  -- la Ola 0 esta viva y el mundo limpio:
  if to_regprocedure('private.assert_f7_piezas_cerradas()') is null then
    raise exception 'F7.1 preflight: falta la Ola 0 (el assert no existe)';
  end if;
  if (select count(*) from private.vigia_alertas where resuelta_en is null) <> 0 then
    raise exception 'F7.1 preflight: hay alertas abiertas - resolverlas antes de cerrar mas puertas';
  end if;
  -- postgres puede actuar como el dueño de las v1/v2: tiene la membresia con
  -- ADMIN OPTION (grantor supabase_admin) aunque SIN la opcion SET — abajo se
  -- la auto-otorga SOLO durante esta transaccion y la devuelve al salir.
  if not exists (select 1 from pg_auth_members m
                  where m.roleid = 'crm_metricas_bridge'::regrole
                    and m.member = 'postgres'::regrole and m.admin_option) then
    raise exception 'F7.1 preflight: postgres no tiene ADMIN sobre crm_metricas_bridge (el revoke seria imposible)';
  end if;

  -- FOTO DE ANTES (oraculo read-only bajo claims de gerencia):
  declare v_ger uuid;
  begin
    select e.perfil_id into strict v_ger
      from crm.equipo e join public.perfiles p on p.id = e.perfil_id
     where e.activo and p.activo and e.rol_crm = 'gerencia' limit 1;
    create temp table _f71_actores on commit drop as select v_ger as ger;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
    create temp table _f71_conv_antes on commit drop as
      select crm.conversion_mensual_fn(date_trunc('month', current_date)::date) as fila;
    create temp table _f71_v3_antes on commit drop as
      select * from crm.metricas_distribucion_leads_v3_fn(
        (date_trunc('month', current_date))::date, current_date);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'postgres', true);
  end;
end $$;

-- =====================================================================
-- 1) LA ADOPCION: metricas_altas_analista_fn gana su partida de
--    nacimiento (cuerpo VIVO al byte; el postflight exige el MISMO md5).
-- =====================================================================
CREATE OR REPLACE FUNCTION crm.metricas_altas_analista_fn(p_meses integer DEFAULT 12)
 RETURNS TABLE(mes date, analista_id uuid, analista_nombre text, altas bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'private', 'public', 'crm'
AS $function$
  with ambito as (
    select
      ((select private.es_lector_global())
        or (select private.rol_crm((select auth.uid()))) = 'gerencia') as es_global,
      array(select private.vendedor_ids_visibles((select auth.uid())))  as ids
  )
  select
    (date_trunc('month', cli.creado_en at time zone 'America/Lima'))::date as mes,
    coalesce(cli.asesor_perfil_id, cli.creado_por) as analista_id,
    coalesce(asesor.nombre_completo, 'Sin asesor') as analista_nombre,
    count(*)::bigint as altas
  from public.perfiles cli
  left join public.perfiles asesor
         on asesor.id = coalesce(cli.asesor_perfil_id, cli.creado_por)
  cross join ambito a
  where cli.rol = 'cliente'
    and cli.creado_en >= ((date_trunc('month', now() at time zone 'America/Lima')
          - make_interval(months => least(greatest(p_meses, 1), 60) - 1))
          at time zone 'America/Lima')
    and (
      a.es_global
      or cli.asesor_perfil_id = any (a.ids)
      or (cli.asesor_perfil_id is null and cli.creado_por = any (a.ids))
    )
  group by 1, 2, 3
  order by 1, 4 desc;
$function$;

-- =====================================================================
-- 2) LOS 7 CIERRES.
-- =====================================================================
-- v1/v2: el dueño es crm_metricas_bridge - se actua COMO EL. La membresia de
-- postgres viene SIN opcion SET (medido): con su ADMIN OPTION se auto-otorga
-- el SET solo aqui, y lo devuelve inmediatamente despues (el postflight lo
-- verifica). Un revoke como postgres a secas seria warning SIN efecto.
grant crm_metricas_bridge to postgres with set true;
set local role crm_metricas_bridge;
revoke execute on function crm.metricas_distribucion_leads_fn(date,date)    from authenticated, anon, public;
revoke execute on function crm.metricas_distribucion_leads_v2_fn(date,date) from authenticated, anon, public;
reset role;
grant crm_metricas_bridge to postgres with set false;

revoke execute on function crm.metricas_cartera_fn(date)                        from authenticated, anon, public, service_role;
revoke execute on function crm.metricas_altas_analista_fn(integer)              from authenticated, anon, public;
revoke execute on function crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)     from authenticated, anon, public;
revoke execute on function crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb) from authenticated, anon, public;
revoke execute on function public.actualizar_numero_contrato(uuid,text,text,text) from authenticated, anon, public, service_role;

-- =====================================================================
-- 3) AL LIBRO: 3 en observacion (14 dias) + 4 permanentes.
-- =====================================================================
insert into private.f7_piezas_en_observacion
  (firma, huella_md5, acl_esperada, llamadores_permitidos, patron_censo, ola, estado,
   cerrada_en, drop_no_antes_de, ok_miguel, nota)
values
  ('crm.metricas_distribucion_leads_fn(date,date)', '9ed153979997aab76667667a58b8b2ee',
   '{crm_metricas_bridge=X/crm_metricas_bridge}', '{}',
   '\mmetricas_distribucion_leads_fn\s*\(', 'F7.1', 'observacion',
   date '2026-08-31', date '2026-09-14',
   'Tabla de OK de la Ola 1 en MIGRACIONES.md; publicada con el ! de Miguel',
   'puerta v1, supersedida por v3; su core private sigue vivo'),
  ('crm.metricas_distribucion_leads_v2_fn(date,date)', 'c7294f041b629b695c9c3f712abec2a0',
   '{crm_metricas_bridge=X/crm_metricas_bridge}', '{}',
   '\mmetricas_distribucion_leads_v2_fn\s*\(', 'F7.1', 'observacion',
   date '2026-08-31', date '2026-09-14',
   'Tabla de OK de la Ola 1 en MIGRACIONES.md; publicada con el ! de Miguel',
   'puerta v2 (el "v2 aun llamada" de RETOMAR-57, muerto aqui); su core vive'),
  ('crm.metricas_altas_analista_fn(integer)', 'df8a99e0dfc4e1d94794073787aa84d7',
   '{postgres=X/postgres}', '{}',
   '\mmetricas_altas_analista_fn\s*\(', 'F7.1', 'observacion',
   date '2026-08-31', date '2026-09-14',
   'Tabla de OK de la Ola 1 en MIGRACIONES.md; publicada con el ! de Miguel',
   'adoptada en esta misma migracion (nacio en una version muda del registro)'),
  ('crm.metricas_cartera_fn(date)', '0b4ede547cf7079be1e56073311453b3',
   '{postgres=X/postgres}', array['crm.conversion_mensual_fn(date)'],
   '\mmetricas_cartera_fn\s*\(', 'F7.1', 'cerrada_permanente',
   date '2026-08-31', null,
   'Tabla de OK de la Ola 1 en MIGRACIONES.md; publicada con el ! de Miguel',
   'organo interno de conversion_mensual_fn - JAMAS se derriba'),
  ('crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)', '5c92f416c4e34fd4ed864c8be19502eb',
   '{postgres=X/postgres}', array['crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'],
   '\mcrear_contrato_con_cuenta\s*\(', 'F7.1', 'cerrada_permanente',
   date '2026-08-31', null,
   'Tabla de OK de la Ola 1 en MIGRACIONES.md; publicada con el ! de Miguel',
   'organo interno del alta pdf_v2 - JAMAS se derriba'),
  ('crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)', 'bdaa1a2753c4f82d87e7e2c28bd80b87',
   '{postgres=X/postgres}', array['crm.actualizar_contrato_con_cuenta_pdf_v3(uuid,jsonb,jsonb)'],
   '\mactualizar_contrato_con_cuenta\s*\(', 'F7.1', 'cerrada_permanente',
   date '2026-08-31', null,
   'Tabla de OK de la Ola 1 en MIGRACIONES.md; publicada con el ! de Miguel',
   'organo interno de la correccion pdf_v3 - JAMAS se derriba'),
  ('public.actualizar_numero_contrato(uuid,text,text,text)', '44270f9706a4515b16962ead8b09ea59',
   '{postgres=X/postgres}', array['crm.actualizar_numero_contrato_pdf_v3(uuid,text,text,text)'],
   '\mactualizar_numero_contrato\s*\(', 'F7.1', 'cerrada_permanente',
   date '2026-08-31', null,
   'Tabla de OK de la Ola 1 en MIGRACIONES.md; publicada con el ! de Miguel (toca public: su ! es el OK explicito)',
   'organo interno de numero_pdf_v3 - JAMAS se derriba')
on conflict (firma) do nothing;

-- =====================================================================
-- 4) ORACULO read-only bajo los MISMOS claims + POSTFLIGHT.
-- =====================================================================
do $$
declare v_ger uuid; v_n integer; v_txt text; v_h text; v_fila text[];
  v_fn constant text[][] := array[
    array['crm.metricas_distribucion_leads_fn(date,date)',    '{crm_metricas_bridge=X/crm_metricas_bridge}'],
    array['crm.metricas_distribucion_leads_v2_fn(date,date)', '{crm_metricas_bridge=X/crm_metricas_bridge}'],
    array['crm.metricas_cartera_fn(date)',                    '{postgres=X/postgres}'],
    array['crm.metricas_altas_analista_fn(integer)',          '{postgres=X/postgres}'],
    array['crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)', '{postgres=X/postgres}'],
    array['crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)', '{postgres=X/postgres}'],
    array['public.actualizar_numero_contrato(uuid,text,text,text)', '{postgres=X/postgres}']
  ];
begin
  -- 4a) ACL literal post-cierre, pieza a pieza.
  foreach v_fila slice 1 in array v_fn loop
    if (select p.proacl::text from pg_proc p where p.oid = v_fila[1]::regprocedure)
       is distinct from v_fila[2] then
      raise exception 'F7.1 postflight: % no quedo cerrada (%)', v_fila[1],
        (select p.proacl::text from pg_proc p where p.oid = v_fila[1]::regprocedure);
    end if;
  end loop;

  -- 4b) La adopcion fue un NO-OP al byte.
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'crm.metricas_altas_analista_fn(integer)'::regprocedure;
  if v_h is distinct from 'df8a99e0dfc4e1d94794073787aa84d7' then
    raise exception 'F7.1 postflight: la adopcion CAMBIO el cuerpo de altas (huella %)', v_h;
  end if;

  -- 4c) La delegacion DEFINER sigue viva: conversion_mensual_fn (que llama a
  --     la recien cerrada metricas_cartera_fn) responde IDENTICO bajo claims.
  select ger into v_ger from _f71_actores;
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
  if (select md5(fila::text) from _f71_conv_antes)
     is distinct from md5((select crm.conversion_mensual_fn(date_trunc('month', current_date)::date))::text) then
    raise exception 'F7.1 oraculo: conversion_mensual_fn cambio tras el cierre de su organo interno';
  end if;
  -- 4d) La pantalla viva de distribucion (v3) responde IDENTICO.
  select (select count(*) from ((select * from crm.metricas_distribucion_leads_v3_fn(
            (date_trunc('month', current_date))::date, current_date))
          except all (select * from _f71_v3_antes)) x)
       + (select count(*) from ((select * from _f71_v3_antes)
          except all (select * from crm.metricas_distribucion_leads_v3_fn(
            (date_trunc('month', current_date))::date, current_date))) x)
    into v_n;
  if v_n <> 0 then
    raise exception 'F7.1 oraculo: la distribucion v3 cambio (% filas)', v_n;
  end if;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'postgres', true);

  -- 4e) El libro quedo con las 14 filas y EL VIGILANTE DE LA OLA 0 da OK
  --     (su censo por OID + 4 superficies corre sobre las filas nuevas).
  if (select count(*) from private.f7_piezas_en_observacion) < 14 then
    raise exception 'F7.1 postflight: el libro no tiene las 14 filas';
  end if;
  v_txt := private.assert_f7_piezas_cerradas();
  if v_txt not like 'OK:%' then
    raise exception 'F7.1 postflight: el vigilante no da OK (%)', v_txt;
  end if;
  v_txt := private.veredicto_f7();
  if v_txt not like 'OK:%' then
    raise exception 'F7.1 postflight: el veredicto no da OK (%)', v_txt;
  end if;

  -- La danza del SET quedo deshecha: postgres NO conserva la opcion.
  if exists (select 1 from pg_auth_members m
              where m.roleid = 'crm_metricas_bridge'::regrole
                and m.member = 'postgres'::regrole and m.set_option) then
    raise exception 'F7.1 postflight: postgres se quedo con la opcion SET del rol puente';
  end if;

  perform private.assert_analitica_leads_citas();
  perform private.assert_analista_vigencia();
end $$;

commit;
$mig_f71$] then
    raise exception 'La version 20260831040000 ya existe con OTRO cuerpo'; end if;
  insert into supabase_migrations.schema_migrations (version, name, statements)
  values ('20260831040000','crm_f7_1_cerrar_lo_que_quedo_suelto', array[$mig_f71$-- P-055 F7.1 - CERRAR LO QUE QUEDO SUELTO (Fase 7, Ola 1).
--
-- Siete cierres, CERO derribos (plan por olas aprobado por Miguel el 31/08;
-- tabla de OK de esta ola en MIGRACIONES.md). Tres grupos:
--  * SUPERSEDIDAS (a observacion, demolibles 14/09): las puertas v1 y v2 de
--    distribucion de leads (la pantalla viva usa v3; los CORES private siguen
--    vivos - v3_core llama a v2_core). ⚠️ Su dueño es crm_metricas_bridge:
--    el revoke va con SET LOCAL ROLE (un revoke como postgres seria un no-op
--    EN SILENCIO - warning sin efecto).
--  * SOLO-INTERNAS (cerradas PERMANENTES, jamas se derriban): metricas_cartera_fn
--    (unico llamador: conversion_mensual_fn), crear/actualizar_contrato_con_cuenta
--    (organos de pdf_v2/v3) y public.actualizar_numero_contrato (organo de su
--    pdf_v3; ⚠️ toca public - OK explicito de Miguel via su !). La delegacion
--    DEFINER sobrevive: el chequeo de EXECUTE interno corre como OWNER.
--    service_role tambien pierde el EXECUTE que tenia en cartera y numero
--    (0 edges/front las llaman - censo 30-31/08).
--  * LA SIN PARTIDA DE NACIMIENTO: crm.metricas_altas_analista_fn existe en
--    prod SIN DDL en las 167 migraciones (nacio en una de las 12 versiones
--    MUDAS del registro). Aqui se ADOPTA (create or replace con su cuerpo
--    VIVO al byte; pin md5 antes == despues) y LUEGO se cierra (observacion).
--
-- El censo de llamadores/superficies de las 7 lo hace el POSTFLIGHT llamando a
-- private.assert_f7_piezas_cerradas() (el vigilante de la Ola 0, ya endurecido
-- por dos auditorias) sobre las filas recien sembradas.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- =====================================================================
-- 0) PREFLIGHT.
-- =====================================================================
do $$
declare
  -- las 7 (huella + ACL EXACTOS medidos el 31/08):
  v_fn constant text[][] := array[
    array['crm.metricas_distribucion_leads_fn(date,date)',    '9ed153979997aab76667667a58b8b2ee', '{crm_metricas_bridge=X/crm_metricas_bridge,authenticated=X/crm_metricas_bridge}'],
    array['crm.metricas_distribucion_leads_v2_fn(date,date)', 'c7294f041b629b695c9c3f712abec2a0', '{crm_metricas_bridge=X/crm_metricas_bridge,authenticated=X/crm_metricas_bridge}'],
    array['crm.metricas_cartera_fn(date)',                    '0b4ede547cf7079be1e56073311453b3', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'],
    array['crm.metricas_altas_analista_fn(integer)',          'df8a99e0dfc4e1d94794073787aa84d7', '{postgres=X/postgres,authenticated=X/postgres}'],
    array['crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)', '5c92f416c4e34fd4ed864c8be19502eb', '{postgres=X/postgres,authenticated=X/postgres}'],
    array['crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)', 'bdaa1a2753c4f82d87e7e2c28bd80b87', '{postgres=X/postgres,authenticated=X/postgres}'],
    array['public.actualizar_numero_contrato(uuid,text,text,text)', '44270f9706a4515b16962ead8b09ea59', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}']
  ];
  -- delegantes que NO deben moverse (pin md5 univalente):
  v_amb constant text[][] := array[
    array['crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)',  '68cc6c91e84061c0bdf6a62306085c14'],
    array['crm.actualizar_contrato_con_cuenta_pdf_v3(uuid,jsonb,jsonb)', '85614480d6c8939e818342ef3fe63c65'],
    array['crm.actualizar_numero_contrato_pdf_v3(uuid,text,text,text)',  '11ad77e85abd0b9be7790240a6e27c1e']
  ];
  v_fila text[]; v_h text; v_acl text;
begin
  foreach v_fila slice 1 in array v_fn loop
    select md5(p.prosrc), p.proacl::text into v_h, v_acl
      from pg_proc p where p.oid = v_fila[1]::regprocedure;
    if v_h is distinct from v_fila[2] then
      raise exception 'F7.1 preflight: % cambio desde la medicion (huella %)', v_fila[1], v_h;
    end if;
    if v_acl is distinct from v_fila[3] then
      raise exception 'F7.1 preflight: ACL de % no es la medida (%)', v_fila[1], v_acl;
    end if;
  end loop;
  foreach v_fila slice 1 in array v_amb loop
    select md5(p.prosrc) into v_h from pg_proc p where p.oid = v_fila[1]::regprocedure;
    if v_h is distinct from v_fila[2] then
      raise exception 'F7.1 preflight: el delegante % cambio (huella %)', v_fila[1], v_h;
    end if;
  end loop;
  -- conversion_mensual_fn: por MENCION + forma (ATR-4 la roza; sin pin md5):
  if not exists (select 1 from pg_proc p
    where p.oid = 'crm.conversion_mensual_fn(date)'::regprocedure
      and p.prosecdef and p.proowner = 'postgres'::regrole
      and strpos(p.prosrc, 'metricas_cartera_fn') > 0) then
    raise exception 'F7.1 preflight: conversion_mensual_fn ya no delega en metricas_cartera_fn';
  end if;
  -- la Ola 0 esta viva y el mundo limpio:
  if to_regprocedure('private.assert_f7_piezas_cerradas()') is null then
    raise exception 'F7.1 preflight: falta la Ola 0 (el assert no existe)';
  end if;
  if (select count(*) from private.vigia_alertas where resuelta_en is null) <> 0 then
    raise exception 'F7.1 preflight: hay alertas abiertas - resolverlas antes de cerrar mas puertas';
  end if;
  -- postgres puede actuar como el dueño de las v1/v2: tiene la membresia con
  -- ADMIN OPTION (grantor supabase_admin) aunque SIN la opcion SET — abajo se
  -- la auto-otorga SOLO durante esta transaccion y la devuelve al salir.
  if not exists (select 1 from pg_auth_members m
                  where m.roleid = 'crm_metricas_bridge'::regrole
                    and m.member = 'postgres'::regrole and m.admin_option) then
    raise exception 'F7.1 preflight: postgres no tiene ADMIN sobre crm_metricas_bridge (el revoke seria imposible)';
  end if;

  -- FOTO DE ANTES (oraculo read-only bajo claims de gerencia):
  declare v_ger uuid;
  begin
    select e.perfil_id into strict v_ger
      from crm.equipo e join public.perfiles p on p.id = e.perfil_id
     where e.activo and p.activo and e.rol_crm = 'gerencia' limit 1;
    create temp table _f71_actores on commit drop as select v_ger as ger;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
    create temp table _f71_conv_antes on commit drop as
      select crm.conversion_mensual_fn(date_trunc('month', current_date)::date) as fila;
    create temp table _f71_v3_antes on commit drop as
      select * from crm.metricas_distribucion_leads_v3_fn(
        (date_trunc('month', current_date))::date, current_date);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'postgres', true);
  end;
end $$;

-- =====================================================================
-- 1) LA ADOPCION: metricas_altas_analista_fn gana su partida de
--    nacimiento (cuerpo VIVO al byte; el postflight exige el MISMO md5).
-- =====================================================================
CREATE OR REPLACE FUNCTION crm.metricas_altas_analista_fn(p_meses integer DEFAULT 12)
 RETURNS TABLE(mes date, analista_id uuid, analista_nombre text, altas bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'private', 'public', 'crm'
AS $function$
  with ambito as (
    select
      ((select private.es_lector_global())
        or (select private.rol_crm((select auth.uid()))) = 'gerencia') as es_global,
      array(select private.vendedor_ids_visibles((select auth.uid())))  as ids
  )
  select
    (date_trunc('month', cli.creado_en at time zone 'America/Lima'))::date as mes,
    coalesce(cli.asesor_perfil_id, cli.creado_por) as analista_id,
    coalesce(asesor.nombre_completo, 'Sin asesor') as analista_nombre,
    count(*)::bigint as altas
  from public.perfiles cli
  left join public.perfiles asesor
         on asesor.id = coalesce(cli.asesor_perfil_id, cli.creado_por)
  cross join ambito a
  where cli.rol = 'cliente'
    and cli.creado_en >= ((date_trunc('month', now() at time zone 'America/Lima')
          - make_interval(months => least(greatest(p_meses, 1), 60) - 1))
          at time zone 'America/Lima')
    and (
      a.es_global
      or cli.asesor_perfil_id = any (a.ids)
      or (cli.asesor_perfil_id is null and cli.creado_por = any (a.ids))
    )
  group by 1, 2, 3
  order by 1, 4 desc;
$function$;

-- =====================================================================
-- 2) LOS 7 CIERRES.
-- =====================================================================
-- v1/v2: el dueño es crm_metricas_bridge - se actua COMO EL. La membresia de
-- postgres viene SIN opcion SET (medido): con su ADMIN OPTION se auto-otorga
-- el SET solo aqui, y lo devuelve inmediatamente despues (el postflight lo
-- verifica). Un revoke como postgres a secas seria warning SIN efecto.
grant crm_metricas_bridge to postgres with set true;
set local role crm_metricas_bridge;
revoke execute on function crm.metricas_distribucion_leads_fn(date,date)    from authenticated, anon, public;
revoke execute on function crm.metricas_distribucion_leads_v2_fn(date,date) from authenticated, anon, public;
reset role;
grant crm_metricas_bridge to postgres with set false;

revoke execute on function crm.metricas_cartera_fn(date)                        from authenticated, anon, public, service_role;
revoke execute on function crm.metricas_altas_analista_fn(integer)              from authenticated, anon, public;
revoke execute on function crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)     from authenticated, anon, public;
revoke execute on function crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb) from authenticated, anon, public;
revoke execute on function public.actualizar_numero_contrato(uuid,text,text,text) from authenticated, anon, public, service_role;

-- =====================================================================
-- 3) AL LIBRO: 3 en observacion (14 dias) + 4 permanentes.
-- =====================================================================
insert into private.f7_piezas_en_observacion
  (firma, huella_md5, acl_esperada, llamadores_permitidos, patron_censo, ola, estado,
   cerrada_en, drop_no_antes_de, ok_miguel, nota)
values
  ('crm.metricas_distribucion_leads_fn(date,date)', '9ed153979997aab76667667a58b8b2ee',
   '{crm_metricas_bridge=X/crm_metricas_bridge}', '{}',
   '\mmetricas_distribucion_leads_fn\s*\(', 'F7.1', 'observacion',
   date '2026-08-31', date '2026-09-14',
   'Tabla de OK de la Ola 1 en MIGRACIONES.md; publicada con el ! de Miguel',
   'puerta v1, supersedida por v3; su core private sigue vivo'),
  ('crm.metricas_distribucion_leads_v2_fn(date,date)', 'c7294f041b629b695c9c3f712abec2a0',
   '{crm_metricas_bridge=X/crm_metricas_bridge}', '{}',
   '\mmetricas_distribucion_leads_v2_fn\s*\(', 'F7.1', 'observacion',
   date '2026-08-31', date '2026-09-14',
   'Tabla de OK de la Ola 1 en MIGRACIONES.md; publicada con el ! de Miguel',
   'puerta v2 (el "v2 aun llamada" de RETOMAR-57, muerto aqui); su core vive'),
  ('crm.metricas_altas_analista_fn(integer)', 'df8a99e0dfc4e1d94794073787aa84d7',
   '{postgres=X/postgres}', '{}',
   '\mmetricas_altas_analista_fn\s*\(', 'F7.1', 'observacion',
   date '2026-08-31', date '2026-09-14',
   'Tabla de OK de la Ola 1 en MIGRACIONES.md; publicada con el ! de Miguel',
   'adoptada en esta misma migracion (nacio en una version muda del registro)'),
  ('crm.metricas_cartera_fn(date)', '0b4ede547cf7079be1e56073311453b3',
   '{postgres=X/postgres}', array['crm.conversion_mensual_fn(date)'],
   '\mmetricas_cartera_fn\s*\(', 'F7.1', 'cerrada_permanente',
   date '2026-08-31', null,
   'Tabla de OK de la Ola 1 en MIGRACIONES.md; publicada con el ! de Miguel',
   'organo interno de conversion_mensual_fn - JAMAS se derriba'),
  ('crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)', '5c92f416c4e34fd4ed864c8be19502eb',
   '{postgres=X/postgres}', array['crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'],
   '\mcrear_contrato_con_cuenta\s*\(', 'F7.1', 'cerrada_permanente',
   date '2026-08-31', null,
   'Tabla de OK de la Ola 1 en MIGRACIONES.md; publicada con el ! de Miguel',
   'organo interno del alta pdf_v2 - JAMAS se derriba'),
  ('crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)', 'bdaa1a2753c4f82d87e7e2c28bd80b87',
   '{postgres=X/postgres}', array['crm.actualizar_contrato_con_cuenta_pdf_v3(uuid,jsonb,jsonb)'],
   '\mactualizar_contrato_con_cuenta\s*\(', 'F7.1', 'cerrada_permanente',
   date '2026-08-31', null,
   'Tabla de OK de la Ola 1 en MIGRACIONES.md; publicada con el ! de Miguel',
   'organo interno de la correccion pdf_v3 - JAMAS se derriba'),
  ('public.actualizar_numero_contrato(uuid,text,text,text)', '44270f9706a4515b16962ead8b09ea59',
   '{postgres=X/postgres}', array['crm.actualizar_numero_contrato_pdf_v3(uuid,text,text,text)'],
   '\mactualizar_numero_contrato\s*\(', 'F7.1', 'cerrada_permanente',
   date '2026-08-31', null,
   'Tabla de OK de la Ola 1 en MIGRACIONES.md; publicada con el ! de Miguel (toca public: su ! es el OK explicito)',
   'organo interno de numero_pdf_v3 - JAMAS se derriba')
on conflict (firma) do nothing;

-- =====================================================================
-- 4) ORACULO read-only bajo los MISMOS claims + POSTFLIGHT.
-- =====================================================================
do $$
declare v_ger uuid; v_n integer; v_txt text; v_h text; v_fila text[];
  v_fn constant text[][] := array[
    array['crm.metricas_distribucion_leads_fn(date,date)',    '{crm_metricas_bridge=X/crm_metricas_bridge}'],
    array['crm.metricas_distribucion_leads_v2_fn(date,date)', '{crm_metricas_bridge=X/crm_metricas_bridge}'],
    array['crm.metricas_cartera_fn(date)',                    '{postgres=X/postgres}'],
    array['crm.metricas_altas_analista_fn(integer)',          '{postgres=X/postgres}'],
    array['crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)', '{postgres=X/postgres}'],
    array['crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)', '{postgres=X/postgres}'],
    array['public.actualizar_numero_contrato(uuid,text,text,text)', '{postgres=X/postgres}']
  ];
begin
  -- 4a) ACL literal post-cierre, pieza a pieza.
  foreach v_fila slice 1 in array v_fn loop
    if (select p.proacl::text from pg_proc p where p.oid = v_fila[1]::regprocedure)
       is distinct from v_fila[2] then
      raise exception 'F7.1 postflight: % no quedo cerrada (%)', v_fila[1],
        (select p.proacl::text from pg_proc p where p.oid = v_fila[1]::regprocedure);
    end if;
  end loop;

  -- 4b) La adopcion fue un NO-OP al byte.
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'crm.metricas_altas_analista_fn(integer)'::regprocedure;
  if v_h is distinct from 'df8a99e0dfc4e1d94794073787aa84d7' then
    raise exception 'F7.1 postflight: la adopcion CAMBIO el cuerpo de altas (huella %)', v_h;
  end if;

  -- 4c) La delegacion DEFINER sigue viva: conversion_mensual_fn (que llama a
  --     la recien cerrada metricas_cartera_fn) responde IDENTICO bajo claims.
  select ger into v_ger from _f71_actores;
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
  if (select md5(fila::text) from _f71_conv_antes)
     is distinct from md5((select crm.conversion_mensual_fn(date_trunc('month', current_date)::date))::text) then
    raise exception 'F7.1 oraculo: conversion_mensual_fn cambio tras el cierre de su organo interno';
  end if;
  -- 4d) La pantalla viva de distribucion (v3) responde IDENTICO.
  select (select count(*) from ((select * from crm.metricas_distribucion_leads_v3_fn(
            (date_trunc('month', current_date))::date, current_date))
          except all (select * from _f71_v3_antes)) x)
       + (select count(*) from ((select * from _f71_v3_antes)
          except all (select * from crm.metricas_distribucion_leads_v3_fn(
            (date_trunc('month', current_date))::date, current_date))) x)
    into v_n;
  if v_n <> 0 then
    raise exception 'F7.1 oraculo: la distribucion v3 cambio (% filas)', v_n;
  end if;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'postgres', true);

  -- 4e) El libro quedo con las 14 filas y EL VIGILANTE DE LA OLA 0 da OK
  --     (su censo por OID + 4 superficies corre sobre las filas nuevas).
  if (select count(*) from private.f7_piezas_en_observacion) < 14 then
    raise exception 'F7.1 postflight: el libro no tiene las 14 filas';
  end if;
  v_txt := private.assert_f7_piezas_cerradas();
  if v_txt not like 'OK:%' then
    raise exception 'F7.1 postflight: el vigilante no da OK (%)', v_txt;
  end if;
  v_txt := private.veredicto_f7();
  if v_txt not like 'OK:%' then
    raise exception 'F7.1 postflight: el veredicto no da OK (%)', v_txt;
  end if;

  -- La danza del SET quedo deshecha: postgres NO conserva la opcion.
  if exists (select 1 from pg_auth_members m
              where m.roleid = 'crm_metricas_bridge'::regrole
                and m.member = 'postgres'::regrole and m.set_option) then
    raise exception 'F7.1 postflight: postgres se quedo con la opcion SET del rol puente';
  end if;

  perform private.assert_analitica_leads_citas();
  perform private.assert_analista_vigencia();
end $$;

commit;
$mig_f71$])
  on conflict (version) do nothing;

  select name, statements into v_nombre, v_a
    from supabase_migrations.schema_migrations where version='20260831040000';
  if not found then
    raise exception 'Registro F7.1: la fila no existe tras el insert'; end if;
  if v_nombre is distinct from 'crm_f7_1_cerrar_lo_que_quedo_suelto' then
    raise exception 'Registro F7.1: la fila quedo con OTRO nombre (%)', v_nombre; end if;
  if v_a is distinct from array[$mig_f71$-- P-055 F7.1 - CERRAR LO QUE QUEDO SUELTO (Fase 7, Ola 1).
--
-- Siete cierres, CERO derribos (plan por olas aprobado por Miguel el 31/08;
-- tabla de OK de esta ola en MIGRACIONES.md). Tres grupos:
--  * SUPERSEDIDAS (a observacion, demolibles 14/09): las puertas v1 y v2 de
--    distribucion de leads (la pantalla viva usa v3; los CORES private siguen
--    vivos - v3_core llama a v2_core). ⚠️ Su dueño es crm_metricas_bridge:
--    el revoke va con SET LOCAL ROLE (un revoke como postgres seria un no-op
--    EN SILENCIO - warning sin efecto).
--  * SOLO-INTERNAS (cerradas PERMANENTES, jamas se derriban): metricas_cartera_fn
--    (unico llamador: conversion_mensual_fn), crear/actualizar_contrato_con_cuenta
--    (organos de pdf_v2/v3) y public.actualizar_numero_contrato (organo de su
--    pdf_v3; ⚠️ toca public - OK explicito de Miguel via su !). La delegacion
--    DEFINER sobrevive: el chequeo de EXECUTE interno corre como OWNER.
--    service_role tambien pierde el EXECUTE que tenia en cartera y numero
--    (0 edges/front las llaman - censo 30-31/08).
--  * LA SIN PARTIDA DE NACIMIENTO: crm.metricas_altas_analista_fn existe en
--    prod SIN DDL en las 167 migraciones (nacio en una de las 12 versiones
--    MUDAS del registro). Aqui se ADOPTA (create or replace con su cuerpo
--    VIVO al byte; pin md5 antes == despues) y LUEGO se cierra (observacion).
--
-- El censo de llamadores/superficies de las 7 lo hace el POSTFLIGHT llamando a
-- private.assert_f7_piezas_cerradas() (el vigilante de la Ola 0, ya endurecido
-- por dos auditorias) sobre las filas recien sembradas.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- =====================================================================
-- 0) PREFLIGHT.
-- =====================================================================
do $$
declare
  -- las 7 (huella + ACL EXACTOS medidos el 31/08):
  v_fn constant text[][] := array[
    array['crm.metricas_distribucion_leads_fn(date,date)',    '9ed153979997aab76667667a58b8b2ee', '{crm_metricas_bridge=X/crm_metricas_bridge,authenticated=X/crm_metricas_bridge}'],
    array['crm.metricas_distribucion_leads_v2_fn(date,date)', 'c7294f041b629b695c9c3f712abec2a0', '{crm_metricas_bridge=X/crm_metricas_bridge,authenticated=X/crm_metricas_bridge}'],
    array['crm.metricas_cartera_fn(date)',                    '0b4ede547cf7079be1e56073311453b3', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'],
    array['crm.metricas_altas_analista_fn(integer)',          'df8a99e0dfc4e1d94794073787aa84d7', '{postgres=X/postgres,authenticated=X/postgres}'],
    array['crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)', '5c92f416c4e34fd4ed864c8be19502eb', '{postgres=X/postgres,authenticated=X/postgres}'],
    array['crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)', 'bdaa1a2753c4f82d87e7e2c28bd80b87', '{postgres=X/postgres,authenticated=X/postgres}'],
    array['public.actualizar_numero_contrato(uuid,text,text,text)', '44270f9706a4515b16962ead8b09ea59', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}']
  ];
  -- delegantes que NO deben moverse (pin md5 univalente):
  v_amb constant text[][] := array[
    array['crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)',  '68cc6c91e84061c0bdf6a62306085c14'],
    array['crm.actualizar_contrato_con_cuenta_pdf_v3(uuid,jsonb,jsonb)', '85614480d6c8939e818342ef3fe63c65'],
    array['crm.actualizar_numero_contrato_pdf_v3(uuid,text,text,text)',  '11ad77e85abd0b9be7790240a6e27c1e']
  ];
  v_fila text[]; v_h text; v_acl text;
begin
  foreach v_fila slice 1 in array v_fn loop
    select md5(p.prosrc), p.proacl::text into v_h, v_acl
      from pg_proc p where p.oid = v_fila[1]::regprocedure;
    if v_h is distinct from v_fila[2] then
      raise exception 'F7.1 preflight: % cambio desde la medicion (huella %)', v_fila[1], v_h;
    end if;
    if v_acl is distinct from v_fila[3] then
      raise exception 'F7.1 preflight: ACL de % no es la medida (%)', v_fila[1], v_acl;
    end if;
  end loop;
  foreach v_fila slice 1 in array v_amb loop
    select md5(p.prosrc) into v_h from pg_proc p where p.oid = v_fila[1]::regprocedure;
    if v_h is distinct from v_fila[2] then
      raise exception 'F7.1 preflight: el delegante % cambio (huella %)', v_fila[1], v_h;
    end if;
  end loop;
  -- conversion_mensual_fn: por MENCION + forma (ATR-4 la roza; sin pin md5):
  if not exists (select 1 from pg_proc p
    where p.oid = 'crm.conversion_mensual_fn(date)'::regprocedure
      and p.prosecdef and p.proowner = 'postgres'::regrole
      and strpos(p.prosrc, 'metricas_cartera_fn') > 0) then
    raise exception 'F7.1 preflight: conversion_mensual_fn ya no delega en metricas_cartera_fn';
  end if;
  -- la Ola 0 esta viva y el mundo limpio:
  if to_regprocedure('private.assert_f7_piezas_cerradas()') is null then
    raise exception 'F7.1 preflight: falta la Ola 0 (el assert no existe)';
  end if;
  if (select count(*) from private.vigia_alertas where resuelta_en is null) <> 0 then
    raise exception 'F7.1 preflight: hay alertas abiertas - resolverlas antes de cerrar mas puertas';
  end if;
  -- postgres puede actuar como el dueño de las v1/v2: tiene la membresia con
  -- ADMIN OPTION (grantor supabase_admin) aunque SIN la opcion SET — abajo se
  -- la auto-otorga SOLO durante esta transaccion y la devuelve al salir.
  if not exists (select 1 from pg_auth_members m
                  where m.roleid = 'crm_metricas_bridge'::regrole
                    and m.member = 'postgres'::regrole and m.admin_option) then
    raise exception 'F7.1 preflight: postgres no tiene ADMIN sobre crm_metricas_bridge (el revoke seria imposible)';
  end if;

  -- FOTO DE ANTES (oraculo read-only bajo claims de gerencia):
  declare v_ger uuid;
  begin
    select e.perfil_id into strict v_ger
      from crm.equipo e join public.perfiles p on p.id = e.perfil_id
     where e.activo and p.activo and e.rol_crm = 'gerencia' limit 1;
    create temp table _f71_actores on commit drop as select v_ger as ger;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
    create temp table _f71_conv_antes on commit drop as
      select crm.conversion_mensual_fn(date_trunc('month', current_date)::date) as fila;
    create temp table _f71_v3_antes on commit drop as
      select * from crm.metricas_distribucion_leads_v3_fn(
        (date_trunc('month', current_date))::date, current_date);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'postgres', true);
  end;
end $$;

-- =====================================================================
-- 1) LA ADOPCION: metricas_altas_analista_fn gana su partida de
--    nacimiento (cuerpo VIVO al byte; el postflight exige el MISMO md5).
-- =====================================================================
CREATE OR REPLACE FUNCTION crm.metricas_altas_analista_fn(p_meses integer DEFAULT 12)
 RETURNS TABLE(mes date, analista_id uuid, analista_nombre text, altas bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'private', 'public', 'crm'
AS $function$
  with ambito as (
    select
      ((select private.es_lector_global())
        or (select private.rol_crm((select auth.uid()))) = 'gerencia') as es_global,
      array(select private.vendedor_ids_visibles((select auth.uid())))  as ids
  )
  select
    (date_trunc('month', cli.creado_en at time zone 'America/Lima'))::date as mes,
    coalesce(cli.asesor_perfil_id, cli.creado_por) as analista_id,
    coalesce(asesor.nombre_completo, 'Sin asesor') as analista_nombre,
    count(*)::bigint as altas
  from public.perfiles cli
  left join public.perfiles asesor
         on asesor.id = coalesce(cli.asesor_perfil_id, cli.creado_por)
  cross join ambito a
  where cli.rol = 'cliente'
    and cli.creado_en >= ((date_trunc('month', now() at time zone 'America/Lima')
          - make_interval(months => least(greatest(p_meses, 1), 60) - 1))
          at time zone 'America/Lima')
    and (
      a.es_global
      or cli.asesor_perfil_id = any (a.ids)
      or (cli.asesor_perfil_id is null and cli.creado_por = any (a.ids))
    )
  group by 1, 2, 3
  order by 1, 4 desc;
$function$;

-- =====================================================================
-- 2) LOS 7 CIERRES.
-- =====================================================================
-- v1/v2: el dueño es crm_metricas_bridge - se actua COMO EL. La membresia de
-- postgres viene SIN opcion SET (medido): con su ADMIN OPTION se auto-otorga
-- el SET solo aqui, y lo devuelve inmediatamente despues (el postflight lo
-- verifica). Un revoke como postgres a secas seria warning SIN efecto.
grant crm_metricas_bridge to postgres with set true;
set local role crm_metricas_bridge;
revoke execute on function crm.metricas_distribucion_leads_fn(date,date)    from authenticated, anon, public;
revoke execute on function crm.metricas_distribucion_leads_v2_fn(date,date) from authenticated, anon, public;
reset role;
grant crm_metricas_bridge to postgres with set false;

revoke execute on function crm.metricas_cartera_fn(date)                        from authenticated, anon, public, service_role;
revoke execute on function crm.metricas_altas_analista_fn(integer)              from authenticated, anon, public;
revoke execute on function crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)     from authenticated, anon, public;
revoke execute on function crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb) from authenticated, anon, public;
revoke execute on function public.actualizar_numero_contrato(uuid,text,text,text) from authenticated, anon, public, service_role;

-- =====================================================================
-- 3) AL LIBRO: 3 en observacion (14 dias) + 4 permanentes.
-- =====================================================================
insert into private.f7_piezas_en_observacion
  (firma, huella_md5, acl_esperada, llamadores_permitidos, patron_censo, ola, estado,
   cerrada_en, drop_no_antes_de, ok_miguel, nota)
values
  ('crm.metricas_distribucion_leads_fn(date,date)', '9ed153979997aab76667667a58b8b2ee',
   '{crm_metricas_bridge=X/crm_metricas_bridge}', '{}',
   '\mmetricas_distribucion_leads_fn\s*\(', 'F7.1', 'observacion',
   date '2026-08-31', date '2026-09-14',
   'Tabla de OK de la Ola 1 en MIGRACIONES.md; publicada con el ! de Miguel',
   'puerta v1, supersedida por v3; su core private sigue vivo'),
  ('crm.metricas_distribucion_leads_v2_fn(date,date)', 'c7294f041b629b695c9c3f712abec2a0',
   '{crm_metricas_bridge=X/crm_metricas_bridge}', '{}',
   '\mmetricas_distribucion_leads_v2_fn\s*\(', 'F7.1', 'observacion',
   date '2026-08-31', date '2026-09-14',
   'Tabla de OK de la Ola 1 en MIGRACIONES.md; publicada con el ! de Miguel',
   'puerta v2 (el "v2 aun llamada" de RETOMAR-57, muerto aqui); su core vive'),
  ('crm.metricas_altas_analista_fn(integer)', 'df8a99e0dfc4e1d94794073787aa84d7',
   '{postgres=X/postgres}', '{}',
   '\mmetricas_altas_analista_fn\s*\(', 'F7.1', 'observacion',
   date '2026-08-31', date '2026-09-14',
   'Tabla de OK de la Ola 1 en MIGRACIONES.md; publicada con el ! de Miguel',
   'adoptada en esta misma migracion (nacio en una version muda del registro)'),
  ('crm.metricas_cartera_fn(date)', '0b4ede547cf7079be1e56073311453b3',
   '{postgres=X/postgres}', array['crm.conversion_mensual_fn(date)'],
   '\mmetricas_cartera_fn\s*\(', 'F7.1', 'cerrada_permanente',
   date '2026-08-31', null,
   'Tabla de OK de la Ola 1 en MIGRACIONES.md; publicada con el ! de Miguel',
   'organo interno de conversion_mensual_fn - JAMAS se derriba'),
  ('crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)', '5c92f416c4e34fd4ed864c8be19502eb',
   '{postgres=X/postgres}', array['crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'],
   '\mcrear_contrato_con_cuenta\s*\(', 'F7.1', 'cerrada_permanente',
   date '2026-08-31', null,
   'Tabla de OK de la Ola 1 en MIGRACIONES.md; publicada con el ! de Miguel',
   'organo interno del alta pdf_v2 - JAMAS se derriba'),
  ('crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)', 'bdaa1a2753c4f82d87e7e2c28bd80b87',
   '{postgres=X/postgres}', array['crm.actualizar_contrato_con_cuenta_pdf_v3(uuid,jsonb,jsonb)'],
   '\mactualizar_contrato_con_cuenta\s*\(', 'F7.1', 'cerrada_permanente',
   date '2026-08-31', null,
   'Tabla de OK de la Ola 1 en MIGRACIONES.md; publicada con el ! de Miguel',
   'organo interno de la correccion pdf_v3 - JAMAS se derriba'),
  ('public.actualizar_numero_contrato(uuid,text,text,text)', '44270f9706a4515b16962ead8b09ea59',
   '{postgres=X/postgres}', array['crm.actualizar_numero_contrato_pdf_v3(uuid,text,text,text)'],
   '\mactualizar_numero_contrato\s*\(', 'F7.1', 'cerrada_permanente',
   date '2026-08-31', null,
   'Tabla de OK de la Ola 1 en MIGRACIONES.md; publicada con el ! de Miguel (toca public: su ! es el OK explicito)',
   'organo interno de numero_pdf_v3 - JAMAS se derriba')
on conflict (firma) do nothing;

-- =====================================================================
-- 4) ORACULO read-only bajo los MISMOS claims + POSTFLIGHT.
-- =====================================================================
do $$
declare v_ger uuid; v_n integer; v_txt text; v_h text; v_fila text[];
  v_fn constant text[][] := array[
    array['crm.metricas_distribucion_leads_fn(date,date)',    '{crm_metricas_bridge=X/crm_metricas_bridge}'],
    array['crm.metricas_distribucion_leads_v2_fn(date,date)', '{crm_metricas_bridge=X/crm_metricas_bridge}'],
    array['crm.metricas_cartera_fn(date)',                    '{postgres=X/postgres}'],
    array['crm.metricas_altas_analista_fn(integer)',          '{postgres=X/postgres}'],
    array['crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)', '{postgres=X/postgres}'],
    array['crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)', '{postgres=X/postgres}'],
    array['public.actualizar_numero_contrato(uuid,text,text,text)', '{postgres=X/postgres}']
  ];
begin
  -- 4a) ACL literal post-cierre, pieza a pieza.
  foreach v_fila slice 1 in array v_fn loop
    if (select p.proacl::text from pg_proc p where p.oid = v_fila[1]::regprocedure)
       is distinct from v_fila[2] then
      raise exception 'F7.1 postflight: % no quedo cerrada (%)', v_fila[1],
        (select p.proacl::text from pg_proc p where p.oid = v_fila[1]::regprocedure);
    end if;
  end loop;

  -- 4b) La adopcion fue un NO-OP al byte.
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'crm.metricas_altas_analista_fn(integer)'::regprocedure;
  if v_h is distinct from 'df8a99e0dfc4e1d94794073787aa84d7' then
    raise exception 'F7.1 postflight: la adopcion CAMBIO el cuerpo de altas (huella %)', v_h;
  end if;

  -- 4c) La delegacion DEFINER sigue viva: conversion_mensual_fn (que llama a
  --     la recien cerrada metricas_cartera_fn) responde IDENTICO bajo claims.
  select ger into v_ger from _f71_actores;
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
  if (select md5(fila::text) from _f71_conv_antes)
     is distinct from md5((select crm.conversion_mensual_fn(date_trunc('month', current_date)::date))::text) then
    raise exception 'F7.1 oraculo: conversion_mensual_fn cambio tras el cierre de su organo interno';
  end if;
  -- 4d) La pantalla viva de distribucion (v3) responde IDENTICO.
  select (select count(*) from ((select * from crm.metricas_distribucion_leads_v3_fn(
            (date_trunc('month', current_date))::date, current_date))
          except all (select * from _f71_v3_antes)) x)
       + (select count(*) from ((select * from _f71_v3_antes)
          except all (select * from crm.metricas_distribucion_leads_v3_fn(
            (date_trunc('month', current_date))::date, current_date))) x)
    into v_n;
  if v_n <> 0 then
    raise exception 'F7.1 oraculo: la distribucion v3 cambio (% filas)', v_n;
  end if;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'postgres', true);

  -- 4e) El libro quedo con las 14 filas y EL VIGILANTE DE LA OLA 0 da OK
  --     (su censo por OID + 4 superficies corre sobre las filas nuevas).
  if (select count(*) from private.f7_piezas_en_observacion) < 14 then
    raise exception 'F7.1 postflight: el libro no tiene las 14 filas';
  end if;
  v_txt := private.assert_f7_piezas_cerradas();
  if v_txt not like 'OK:%' then
    raise exception 'F7.1 postflight: el vigilante no da OK (%)', v_txt;
  end if;
  v_txt := private.veredicto_f7();
  if v_txt not like 'OK:%' then
    raise exception 'F7.1 postflight: el veredicto no da OK (%)', v_txt;
  end if;

  -- La danza del SET quedo deshecha: postgres NO conserva la opcion.
  if exists (select 1 from pg_auth_members m
              where m.roleid = 'crm_metricas_bridge'::regrole
                and m.member = 'postgres'::regrole and m.set_option) then
    raise exception 'F7.1 postflight: postgres se quedo con la opcion SET del rol puente';
  end if;

  perform private.assert_analitica_leads_citas();
  perform private.assert_analista_vigencia();
end $$;

commit;
$mig_f71$] then
    raise exception 'Registro F7.1: la fila quedo con OTRO cuerpo (posible insert concurrente)'; end if;
end $reg_f71$;
