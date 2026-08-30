-- Registra 20260831050000 CON su cuerpo - fail-closed, etiqueta propia.
-- Candados: mundo-vivo (las 7 cerradas + vigilante AMPLIADO + filas VIGENTES
-- en el libro + HONESTIDAD TEMPORAL en hora de LIMA, no UTC - hallazgo Codex
-- 30/08), NULL-statements revienta, relectura post-insert.
do $reg_f71$
declare v_a text[]; v_nombre text; v_n integer;
begin
  if (select p.proacl::text from pg_proc p
      where p.oid = 'crm.metricas_cartera_fn(date)'::regprocedure)
     is distinct from '{postgres=X/postgres}' then
    raise exception 'Registro F7.1: el mundo vivo NO esta migrado — aplicar antes de registrar';
  end if;
  -- el vigilante debe ser el AMPLIADO (strpos, jamas LIKE):
  if (select strpos(p.prosrc, $srv$'authenticated', 'anon', 'service_role'$srv$)
        from pg_proc p
       where p.oid = 'private.assert_f7_piezas_cerradas()'::regprocedure) = 0 then
    raise exception 'Registro F7.1: el vigilante NO es el ampliado de F7.1 — aplicar antes de registrar';
  end if;
  -- honestidad temporal en el reloj COMERCIAL (America/Lima): las fechas del
  -- seed deben corresponder a la publicacion real.
  select count(*) into v_n from private.f7_piezas_en_observacion
   where ola = 'F7.1' and estado in ('observacion', 'cerrada_permanente')
     and (now() at time zone 'America/Lima')::date between cerrada_en and cerrada_en + 2;
  if v_n <> 7 then
    raise exception 'Registro F7.1: las filas VIGENTES de la ola no estan o su fecha de cierre no coincide con la publicacion real en hora de Lima (regenerar fechas del seed)';
  end if;

  select statements into v_a from supabase_migrations.schema_migrations where version='20260831050000';
  if found and v_a is null then
    raise exception 'La version 20260831050000 existe SIN cuerpo (statements NULL): repararla con UPDATE, no re-insertar'; end if;
  if found and v_a <> array[$mig_f71$-- P-055 F7.1 - CERRAR LO QUE QUEDO SUELTO (Fase 7, Ola 1).
--
-- Siete cierres, CERO derribos (plan por olas aprobado por Miguel el 31/08;
-- tabla de OK de esta ola en MIGRACIONES.md). Tres grupos:
--  * SUPERSEDIDAS (a observacion, demolibles 14/09): las puertas v1 y v2 de
--    distribucion de leads (la pantalla viva usa v3; los CORES private siguen
--    vivos - v3_core llama a v2_core). Su dueño es crm_metricas_bridge, pero
--    postgres HEREDA del dueño (membresia con USAGE): el revoke directo se
--    ejecuta COMO el dueño y el ACL resultante lleva al bridge como grantor
--    (MEDIDO contra prod el 30/08, ida y vuelta al byte). Sin cambio de rol.
--  * SOLO-INTERNAS (cerradas PERMANENTES, jamas se derriban): metricas_cartera_fn
--    (unico llamador: conversion_mensual_fn), crear/actualizar_contrato_con_cuenta
--    (organos de pdf_v2/v3) y public.actualizar_numero_contrato (organo de su
--    pdf_v3; ⚠️ toca public - OK explicito de Miguel via su !). La delegacion
--    DEFINER sobrevive: el chequeo de EXECUTE interno corre como OWNER.
--    service_role tambien pierde el EXECUTE que tenia en cartera y numero
--    (0 edges/front las llaman - censo 30-31/08).
--  * crm.metricas_altas_analista_fn: su partida de nacimiento SI esta en el
--    registro de prod (version 20260716203331, crm_metricas_gerencia_fn, CON
--    cuerpo - verificado contra prod el 30/08); lo que falta es el ARCHIVO
--    local (el repo tiene 167 de las 189 versiones). No se adopta nada: se
--    cierra tal cual, con su huella pinneada.
--
-- El censo de llamadores/superficies de las 7 lo hace el POSTFLIGHT llamando a
-- private.assert_f7_piezas_cerradas() (el vigilante de la Ola 0, ya endurecido
-- por dos auditorias) sobre las filas recien sembradas. Esta ola ademas AMPLIA
-- ese vigilante: el cierre transversal de herencia ahora vigila TAMBIEN que
-- service_role no alcance a postgres por membresia (hallazgo Codex 30/08 -
-- esta misma ola le quita a service_role dos EXECUTE directos).
--
-- (Reemplaza a la 20260831040000 preparada y NUNCA publicada: 3 hallazgos de
-- la refutacion de diseño de Codex del 30/08 - la danza del rol puente sobraba,
-- la adopcion sobraba, y el cierre transversal quedaba corto. Enmienda
-- registrada en MIGRACIONES.md.)

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
  -- postgres actua como el dueño de las v1/v2 por HERENCIA de la membresia
  -- (Codex 30/08 + medicion ida-y-vuelta contra prod): el revoke directo se
  -- ejecuta como el rol que de verdad posee el privilegio. Sin USAGE, el
  -- revoke seria un warning SIN efecto - por eso este candado.
  if not pg_has_role('postgres', 'crm_metricas_bridge', 'USAGE') then
    raise exception 'F7.1 preflight: postgres no HEREDA de crm_metricas_bridge (el revoke seria un no-op silencioso)';
  end if;
  -- El vigilante que esta ola AMPLIA debe ser el publicado en la Ola 0:
  if (select md5(p.prosrc) from pg_proc p
      where p.oid = 'private.assert_f7_piezas_cerradas()'::regprocedure)
     is distinct from 'e6f0070260e1fff2757201df8134167b' then
    raise exception 'F7.1 preflight: assert_f7_piezas_cerradas no es el de la Ola 0 (remedir antes de ampliarlo)';
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
-- 1) LOS 7 CIERRES.
-- =====================================================================
-- v1/v2: el dueño es crm_metricas_bridge; postgres HEREDA del dueño, asi que
-- el revoke directo se ejecuta COMO el (medido 30/08 contra prod: el ACL
-- resultante lleva al bridge como grantor, identico al que dejaria el propio
-- dueño; la vuelta con grant restaura el literal al byte). El postflight
-- compara el ACL LITERAL - un no-op silencioso no pasaria.
revoke execute on function crm.metricas_distribucion_leads_fn(date,date)    from authenticated, anon, public;
revoke execute on function crm.metricas_distribucion_leads_v2_fn(date,date) from authenticated, anon, public;

revoke execute on function crm.metricas_cartera_fn(date)                        from authenticated, anon, public, service_role;
revoke execute on function crm.metricas_altas_analista_fn(integer)              from authenticated, anon, public;
revoke execute on function crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)     from authenticated, anon, public;
revoke execute on function crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb) from authenticated, anon, public;
revoke execute on function public.actualizar_numero_contrato(uuid,text,text,text) from authenticated, anon, public, service_role;

-- =====================================================================
-- 2) AL LIBRO: 3 en observacion (14 dias) + 4 permanentes.
-- =====================================================================
-- RE-APLICACION tras un rollback: aquel NO borra (doctrina del libro: jamas
-- DELETE; la salida es estado='liberada') - deja las filas de esta ola en
-- 'liberada'. Aqui se RE-DECLARAN bajando el candado NOMBRADO (doctrina
-- limpieza-leads), con rastro en nota. En el primer viaje esto es un no-op.
alter table private.f7_piezas_en_observacion disable trigger trg_f7_obs_00_solo_crece;
update private.f7_piezas_en_observacion
   set estado = 'observacion',
       nota = coalesce(nota, '') || ' | re-declarada en re-aplicacion de F7.1'
 where ola = 'F7.1' and estado = 'liberada'
   and firma in ('crm.metricas_distribucion_leads_fn(date,date)',
                 'crm.metricas_distribucion_leads_v2_fn(date,date)',
                 'crm.metricas_altas_analista_fn(integer)');
update private.f7_piezas_en_observacion
   set estado = 'cerrada_permanente',
       nota = coalesce(nota, '') || ' | re-declarada en re-aplicacion de F7.1'
 where ola = 'F7.1' and estado = 'liberada';
alter table private.f7_piezas_en_observacion enable trigger trg_f7_obs_00_solo_crece;

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
   'nacida en la version 20260716203331 (crm_metricas_gerencia_fn) del registro de prod; el archivo local no existe - repo incompleto, NO version muda (Codex 30/08)'),
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
-- 3) EL VIGILANTE SE AMPLIA (hallazgo Codex 30/08): el cierre transversal
--    de herencia ahora vigila tambien a service_role. Esta ola le quita dos
--    EXECUTE directos; sin esta ampliacion, un GRANT futuro de MEMBRESIA
--    se los devolveria todos SIN tocar proacl y el vigia seguiria verde.
--    Cuerpo identico al de la Ola 0 salvo el trio de lineas del cierre
--    (preflight arriba pinnea la huella de la Ola 0; postflight verifica
--    que el nuevo cuerpo menciona a service_role via strpos - LIKE jamas:
--    el guion bajo es comodin).
-- =====================================================================
create or replace function private.assert_f7_piezas_cerradas()
returns text
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  r record; v_h text; v_acl text; v_n integer; v_p text;
  v_excluidos oid[]; v_permitidos oid[];
  v_obs integer := 0; v_perm integer := 0; v_dem integer := 0; v_lib integer := 0;
begin
  if not exists (select 1 from private.f7_piezas_en_observacion) then
    raise exception 'F7: la tabla de observacion esta VACIA (fail-closed)';
  end if;

  -- El conjunto vigilado entero se excluye de todo censo: las gemelas se
  -- nombran entre si y todas estan congeladas por huella de todos modos.
  select coalesce(array_agg((to_regprocedure(o.firma))::oid), '{}'::oid[]) into v_excluidos
    from private.f7_piezas_en_observacion o
   where to_regprocedure(o.firma) is not null;

  for r in select * from private.f7_piezas_en_observacion order by firma loop
    if r.estado = 'liberada' then
      -- Llegar aqui SOLO es posible por una migracion que bajo el candado
      -- (la maquina de estados lo prohibe por UPDATE): la pieza volvio al
      -- servicio deliberadamente y deja de vigilarse.
      v_lib := v_lib + 1; continue;
    end if;

    if r.estado = 'demolida' then
      if to_regprocedure(r.firma) is not null then
        raise exception 'F7: % RENACIO despues de su demolicion', r.firma;
      end if;
      if r.drop_no_antes_de is not null and current_date < r.drop_no_antes_de then
        raise exception 'F7: % fue demolida ANTES de su ventana (no antes de %)', r.firma, r.drop_no_antes_de;
      end if;
      v_dem := v_dem + 1; continue;
    end if;

    -- observacion / cerrada_permanente: existe, congelada, cerrada.
    if to_regprocedure(r.firma) is null then
      raise exception 'F7: % desaparecio SIN pasar por la demolicion', r.firma;
    end if;
    select md5(p.prosrc) into v_h from pg_proc p where p.oid = r.firma::regprocedure;
    if v_h is distinct from r.huella_md5 then
      raise exception 'F7: el cuerpo de % cambio estando cerrada (huella %)', r.firma, v_h;
    end if;
    select p.proacl::text into v_acl from pg_proc p where p.oid = r.firma::regprocedure;
    if v_acl is distinct from r.acl_esperada then
      raise exception 'F7: % SE REABRIO (ACL %, se esperaba %)', r.firma, v_acl, r.acl_esperada;
    end if;

    v_permitidos := '{}'::oid[];
    foreach v_p in array r.llamadores_permitidos loop
      if to_regprocedure(v_p) is null then
        raise exception 'F7: el llamador permitido % de % ya no resuelve', v_p, r.firma;
      end if;
      v_permitidos := v_permitidos || (to_regprocedure(v_p))::oid;
    end loop;

    -- Codex P0-1: el cuerpo de una funcion SQL-standard vive en prosqlbody
    -- (prosrc queda vacio) — se censan AMBOS textos.
    select count(*) into v_n
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname not in ('pg_catalog', 'information_schema')
       and p.oid <> all (v_excluidos || v_permitidos)
       and lower(replace(
             regexp_replace(regexp_replace(
               coalesce(p.prosrc, '') || ' ' || coalesce(pg_get_function_sqlbody(p.oid), ''),
               '--[^\n]*', ' ', 'g'),
               '/\*.*?\*/', ' ', 'g'), '"', '')) ~ r.patron_censo;
    if v_n <> 0 then
      raise exception 'F7: % funciones NUEVAS nombran a % — alguien empezo a usarla', v_n, r.firma;
    end if;

    -- Codex P0-1: las VISTAS y REGLAS tambien pueden llamarla — se censan.
    select count(*) into v_n
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname not in ('pg_catalog', 'information_schema')
       and c.relkind in ('v', 'm')
       and lower(replace(pg_get_viewdef(c.oid), '"', '')) ~ r.patron_censo;
    if v_n <> 0 then
      raise exception 'F7: % VISTAS nombran a % — alguien la cableo por una vista', v_n, r.firma;
    end if;

    -- Auditoria F7.0 (P1): el parser resuelve MAYUSCULAS y comillas — el censo
    -- tambien: todo texto se normaliza con lower() y sin comillas dobles.
    select (select count(*) from pg_policy pol
             where lower(replace(coalesce(pg_get_expr(pol.polqual, pol.polrelid), ''), '"', '')) ~ r.patron_censo
                or lower(replace(coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), ''), '"', '')) ~ r.patron_censo)
         + (select count(*) from pg_attrdef ad
             where lower(replace(pg_get_expr(ad.adbin, ad.adrelid), '"', '')) ~ r.patron_censo)
         + (select count(*) from pg_constraint c
             where c.contype = 'c' and lower(replace(pg_get_constraintdef(c.oid), '"', '')) ~ r.patron_censo)
         + (select count(*) from cron.job j where lower(replace(j.command, '"', '')) ~ r.patron_censo)
      into v_n;
    if v_n <> 0 then
      raise exception 'F7: % aparece en % superficies (policies/defaults/checks/cron)', r.firma, v_n;
    end if;

    if r.estado = 'observacion' then v_obs := v_obs + 1; else v_perm := v_perm + 1; end if;
  end loop;

  -- Codex P0-4: un GRANT de MEMBRESIA (rol puente hacia postgres) transmite
  -- los privilegios del owner SIN tocar proacl. Cierre transversal: ni
  -- authenticated, ni anon, NI service_role (ampliado en F7.1 - hallazgo Codex
  -- 30/08: esta ola le quita a service_role dos EXECUTE directos; sin esto, un
  -- GRANT futuro de membresia se los devolveria todos SIN tocar proacl y el
  -- vigia seguiria verde) pueden alcanzar a postgres por la cadena de roles.
  if exists (
    with recursive alcance as (
      select pr.oid from pg_roles pr where pr.rolname in ('authenticated', 'anon', 'service_role')
      union
      select m.roleid from pg_auth_members m join alcance al on al.oid = m.member
    )
    select 1 from alcance al2 join pg_roles pr2 on pr2.oid = al2.oid where pr2.rolname = 'postgres'
  ) then
    raise exception 'F7: authenticated/anon/service_role ALCANZAN a postgres por membresia de roles — puerta trasera de herencia';
  end if;

  return format('OK: %s piezas vigiladas (observacion %s, permanentes %s, demolidas %s, liberadas %s)',
                v_obs + v_perm + v_dem + v_lib, v_obs, v_perm, v_dem, v_lib);
end;
$function$;

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

  -- 4b) Los CUERPOS de las 7 no se movieron: esta ola solo toca ACLs (la
  --     huella de cada pieza queda ademas sellada en el libro, que el
  --     vigilante re-mide a diario).
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'crm.metricas_altas_analista_fn(integer)'::regprocedure;
  if v_h is distinct from 'df8a99e0dfc4e1d94794073787aa84d7' then
    raise exception 'F7.1 postflight: el cuerpo de altas cambio dentro de la transaccion (huella %)', v_h;
  end if;
  -- 4b2) El vigilante ampliado quedo en su sitio: menciona a service_role en
  --      el cierre transversal (strpos, jamas LIKE: el guion bajo es comodin)
  --      y su veredicto YA corre con la lista ampliada mas abajo (4e).
  if (select strpos(p.prosrc, $srv$'authenticated', 'anon', 'service_role'$srv$)
        from pg_proc p
       where p.oid = 'private.assert_f7_piezas_cerradas()'::regprocedure) = 0 then
    raise exception 'F7.1 postflight: el vigilante NO quedo ampliado con service_role';
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

  -- Sin danza no hay nada que deshacer, pero se deja MEDIDO que la membresia
  -- del puente no gano opciones dentro de esta transaccion (defensa barata).
  if exists (select 1 from pg_auth_members m
              where m.roleid = 'crm_metricas_bridge'::regrole
                and m.member = 'postgres'::regrole and m.set_option) then
    raise exception 'F7.1 postflight: la membresia del rol puente gano la opcion SET (nadie debio tocarla)';
  end if;

  perform private.assert_analitica_leads_citas();
  perform private.assert_analista_vigencia();
end $$;

commit;
$mig_f71$] then
    raise exception 'La version 20260831050000 ya existe con OTRO cuerpo'; end if;
  insert into supabase_migrations.schema_migrations (version, name, statements)
  values ('20260831050000','crm_f7_1_cerrar_lo_que_quedo_suelto', array[$mig_f71$-- P-055 F7.1 - CERRAR LO QUE QUEDO SUELTO (Fase 7, Ola 1).
--
-- Siete cierres, CERO derribos (plan por olas aprobado por Miguel el 31/08;
-- tabla de OK de esta ola en MIGRACIONES.md). Tres grupos:
--  * SUPERSEDIDAS (a observacion, demolibles 14/09): las puertas v1 y v2 de
--    distribucion de leads (la pantalla viva usa v3; los CORES private siguen
--    vivos - v3_core llama a v2_core). Su dueño es crm_metricas_bridge, pero
--    postgres HEREDA del dueño (membresia con USAGE): el revoke directo se
--    ejecuta COMO el dueño y el ACL resultante lleva al bridge como grantor
--    (MEDIDO contra prod el 30/08, ida y vuelta al byte). Sin cambio de rol.
--  * SOLO-INTERNAS (cerradas PERMANENTES, jamas se derriban): metricas_cartera_fn
--    (unico llamador: conversion_mensual_fn), crear/actualizar_contrato_con_cuenta
--    (organos de pdf_v2/v3) y public.actualizar_numero_contrato (organo de su
--    pdf_v3; ⚠️ toca public - OK explicito de Miguel via su !). La delegacion
--    DEFINER sobrevive: el chequeo de EXECUTE interno corre como OWNER.
--    service_role tambien pierde el EXECUTE que tenia en cartera y numero
--    (0 edges/front las llaman - censo 30-31/08).
--  * crm.metricas_altas_analista_fn: su partida de nacimiento SI esta en el
--    registro de prod (version 20260716203331, crm_metricas_gerencia_fn, CON
--    cuerpo - verificado contra prod el 30/08); lo que falta es el ARCHIVO
--    local (el repo tiene 167 de las 189 versiones). No se adopta nada: se
--    cierra tal cual, con su huella pinneada.
--
-- El censo de llamadores/superficies de las 7 lo hace el POSTFLIGHT llamando a
-- private.assert_f7_piezas_cerradas() (el vigilante de la Ola 0, ya endurecido
-- por dos auditorias) sobre las filas recien sembradas. Esta ola ademas AMPLIA
-- ese vigilante: el cierre transversal de herencia ahora vigila TAMBIEN que
-- service_role no alcance a postgres por membresia (hallazgo Codex 30/08 -
-- esta misma ola le quita a service_role dos EXECUTE directos).
--
-- (Reemplaza a la 20260831040000 preparada y NUNCA publicada: 3 hallazgos de
-- la refutacion de diseño de Codex del 30/08 - la danza del rol puente sobraba,
-- la adopcion sobraba, y el cierre transversal quedaba corto. Enmienda
-- registrada en MIGRACIONES.md.)

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
  -- postgres actua como el dueño de las v1/v2 por HERENCIA de la membresia
  -- (Codex 30/08 + medicion ida-y-vuelta contra prod): el revoke directo se
  -- ejecuta como el rol que de verdad posee el privilegio. Sin USAGE, el
  -- revoke seria un warning SIN efecto - por eso este candado.
  if not pg_has_role('postgres', 'crm_metricas_bridge', 'USAGE') then
    raise exception 'F7.1 preflight: postgres no HEREDA de crm_metricas_bridge (el revoke seria un no-op silencioso)';
  end if;
  -- El vigilante que esta ola AMPLIA debe ser el publicado en la Ola 0:
  if (select md5(p.prosrc) from pg_proc p
      where p.oid = 'private.assert_f7_piezas_cerradas()'::regprocedure)
     is distinct from 'e6f0070260e1fff2757201df8134167b' then
    raise exception 'F7.1 preflight: assert_f7_piezas_cerradas no es el de la Ola 0 (remedir antes de ampliarlo)';
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
-- 1) LOS 7 CIERRES.
-- =====================================================================
-- v1/v2: el dueño es crm_metricas_bridge; postgres HEREDA del dueño, asi que
-- el revoke directo se ejecuta COMO el (medido 30/08 contra prod: el ACL
-- resultante lleva al bridge como grantor, identico al que dejaria el propio
-- dueño; la vuelta con grant restaura el literal al byte). El postflight
-- compara el ACL LITERAL - un no-op silencioso no pasaria.
revoke execute on function crm.metricas_distribucion_leads_fn(date,date)    from authenticated, anon, public;
revoke execute on function crm.metricas_distribucion_leads_v2_fn(date,date) from authenticated, anon, public;

revoke execute on function crm.metricas_cartera_fn(date)                        from authenticated, anon, public, service_role;
revoke execute on function crm.metricas_altas_analista_fn(integer)              from authenticated, anon, public;
revoke execute on function crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)     from authenticated, anon, public;
revoke execute on function crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb) from authenticated, anon, public;
revoke execute on function public.actualizar_numero_contrato(uuid,text,text,text) from authenticated, anon, public, service_role;

-- =====================================================================
-- 2) AL LIBRO: 3 en observacion (14 dias) + 4 permanentes.
-- =====================================================================
-- RE-APLICACION tras un rollback: aquel NO borra (doctrina del libro: jamas
-- DELETE; la salida es estado='liberada') - deja las filas de esta ola en
-- 'liberada'. Aqui se RE-DECLARAN bajando el candado NOMBRADO (doctrina
-- limpieza-leads), con rastro en nota. En el primer viaje esto es un no-op.
alter table private.f7_piezas_en_observacion disable trigger trg_f7_obs_00_solo_crece;
update private.f7_piezas_en_observacion
   set estado = 'observacion',
       nota = coalesce(nota, '') || ' | re-declarada en re-aplicacion de F7.1'
 where ola = 'F7.1' and estado = 'liberada'
   and firma in ('crm.metricas_distribucion_leads_fn(date,date)',
                 'crm.metricas_distribucion_leads_v2_fn(date,date)',
                 'crm.metricas_altas_analista_fn(integer)');
update private.f7_piezas_en_observacion
   set estado = 'cerrada_permanente',
       nota = coalesce(nota, '') || ' | re-declarada en re-aplicacion de F7.1'
 where ola = 'F7.1' and estado = 'liberada';
alter table private.f7_piezas_en_observacion enable trigger trg_f7_obs_00_solo_crece;

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
   'nacida en la version 20260716203331 (crm_metricas_gerencia_fn) del registro de prod; el archivo local no existe - repo incompleto, NO version muda (Codex 30/08)'),
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
-- 3) EL VIGILANTE SE AMPLIA (hallazgo Codex 30/08): el cierre transversal
--    de herencia ahora vigila tambien a service_role. Esta ola le quita dos
--    EXECUTE directos; sin esta ampliacion, un GRANT futuro de MEMBRESIA
--    se los devolveria todos SIN tocar proacl y el vigia seguiria verde.
--    Cuerpo identico al de la Ola 0 salvo el trio de lineas del cierre
--    (preflight arriba pinnea la huella de la Ola 0; postflight verifica
--    que el nuevo cuerpo menciona a service_role via strpos - LIKE jamas:
--    el guion bajo es comodin).
-- =====================================================================
create or replace function private.assert_f7_piezas_cerradas()
returns text
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  r record; v_h text; v_acl text; v_n integer; v_p text;
  v_excluidos oid[]; v_permitidos oid[];
  v_obs integer := 0; v_perm integer := 0; v_dem integer := 0; v_lib integer := 0;
begin
  if not exists (select 1 from private.f7_piezas_en_observacion) then
    raise exception 'F7: la tabla de observacion esta VACIA (fail-closed)';
  end if;

  -- El conjunto vigilado entero se excluye de todo censo: las gemelas se
  -- nombran entre si y todas estan congeladas por huella de todos modos.
  select coalesce(array_agg((to_regprocedure(o.firma))::oid), '{}'::oid[]) into v_excluidos
    from private.f7_piezas_en_observacion o
   where to_regprocedure(o.firma) is not null;

  for r in select * from private.f7_piezas_en_observacion order by firma loop
    if r.estado = 'liberada' then
      -- Llegar aqui SOLO es posible por una migracion que bajo el candado
      -- (la maquina de estados lo prohibe por UPDATE): la pieza volvio al
      -- servicio deliberadamente y deja de vigilarse.
      v_lib := v_lib + 1; continue;
    end if;

    if r.estado = 'demolida' then
      if to_regprocedure(r.firma) is not null then
        raise exception 'F7: % RENACIO despues de su demolicion', r.firma;
      end if;
      if r.drop_no_antes_de is not null and current_date < r.drop_no_antes_de then
        raise exception 'F7: % fue demolida ANTES de su ventana (no antes de %)', r.firma, r.drop_no_antes_de;
      end if;
      v_dem := v_dem + 1; continue;
    end if;

    -- observacion / cerrada_permanente: existe, congelada, cerrada.
    if to_regprocedure(r.firma) is null then
      raise exception 'F7: % desaparecio SIN pasar por la demolicion', r.firma;
    end if;
    select md5(p.prosrc) into v_h from pg_proc p where p.oid = r.firma::regprocedure;
    if v_h is distinct from r.huella_md5 then
      raise exception 'F7: el cuerpo de % cambio estando cerrada (huella %)', r.firma, v_h;
    end if;
    select p.proacl::text into v_acl from pg_proc p where p.oid = r.firma::regprocedure;
    if v_acl is distinct from r.acl_esperada then
      raise exception 'F7: % SE REABRIO (ACL %, se esperaba %)', r.firma, v_acl, r.acl_esperada;
    end if;

    v_permitidos := '{}'::oid[];
    foreach v_p in array r.llamadores_permitidos loop
      if to_regprocedure(v_p) is null then
        raise exception 'F7: el llamador permitido % de % ya no resuelve', v_p, r.firma;
      end if;
      v_permitidos := v_permitidos || (to_regprocedure(v_p))::oid;
    end loop;

    -- Codex P0-1: el cuerpo de una funcion SQL-standard vive en prosqlbody
    -- (prosrc queda vacio) — se censan AMBOS textos.
    select count(*) into v_n
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname not in ('pg_catalog', 'information_schema')
       and p.oid <> all (v_excluidos || v_permitidos)
       and lower(replace(
             regexp_replace(regexp_replace(
               coalesce(p.prosrc, '') || ' ' || coalesce(pg_get_function_sqlbody(p.oid), ''),
               '--[^\n]*', ' ', 'g'),
               '/\*.*?\*/', ' ', 'g'), '"', '')) ~ r.patron_censo;
    if v_n <> 0 then
      raise exception 'F7: % funciones NUEVAS nombran a % — alguien empezo a usarla', v_n, r.firma;
    end if;

    -- Codex P0-1: las VISTAS y REGLAS tambien pueden llamarla — se censan.
    select count(*) into v_n
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname not in ('pg_catalog', 'information_schema')
       and c.relkind in ('v', 'm')
       and lower(replace(pg_get_viewdef(c.oid), '"', '')) ~ r.patron_censo;
    if v_n <> 0 then
      raise exception 'F7: % VISTAS nombran a % — alguien la cableo por una vista', v_n, r.firma;
    end if;

    -- Auditoria F7.0 (P1): el parser resuelve MAYUSCULAS y comillas — el censo
    -- tambien: todo texto se normaliza con lower() y sin comillas dobles.
    select (select count(*) from pg_policy pol
             where lower(replace(coalesce(pg_get_expr(pol.polqual, pol.polrelid), ''), '"', '')) ~ r.patron_censo
                or lower(replace(coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), ''), '"', '')) ~ r.patron_censo)
         + (select count(*) from pg_attrdef ad
             where lower(replace(pg_get_expr(ad.adbin, ad.adrelid), '"', '')) ~ r.patron_censo)
         + (select count(*) from pg_constraint c
             where c.contype = 'c' and lower(replace(pg_get_constraintdef(c.oid), '"', '')) ~ r.patron_censo)
         + (select count(*) from cron.job j where lower(replace(j.command, '"', '')) ~ r.patron_censo)
      into v_n;
    if v_n <> 0 then
      raise exception 'F7: % aparece en % superficies (policies/defaults/checks/cron)', r.firma, v_n;
    end if;

    if r.estado = 'observacion' then v_obs := v_obs + 1; else v_perm := v_perm + 1; end if;
  end loop;

  -- Codex P0-4: un GRANT de MEMBRESIA (rol puente hacia postgres) transmite
  -- los privilegios del owner SIN tocar proacl. Cierre transversal: ni
  -- authenticated, ni anon, NI service_role (ampliado en F7.1 - hallazgo Codex
  -- 30/08: esta ola le quita a service_role dos EXECUTE directos; sin esto, un
  -- GRANT futuro de membresia se los devolveria todos SIN tocar proacl y el
  -- vigia seguiria verde) pueden alcanzar a postgres por la cadena de roles.
  if exists (
    with recursive alcance as (
      select pr.oid from pg_roles pr where pr.rolname in ('authenticated', 'anon', 'service_role')
      union
      select m.roleid from pg_auth_members m join alcance al on al.oid = m.member
    )
    select 1 from alcance al2 join pg_roles pr2 on pr2.oid = al2.oid where pr2.rolname = 'postgres'
  ) then
    raise exception 'F7: authenticated/anon/service_role ALCANZAN a postgres por membresia de roles — puerta trasera de herencia';
  end if;

  return format('OK: %s piezas vigiladas (observacion %s, permanentes %s, demolidas %s, liberadas %s)',
                v_obs + v_perm + v_dem + v_lib, v_obs, v_perm, v_dem, v_lib);
end;
$function$;

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

  -- 4b) Los CUERPOS de las 7 no se movieron: esta ola solo toca ACLs (la
  --     huella de cada pieza queda ademas sellada en el libro, que el
  --     vigilante re-mide a diario).
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'crm.metricas_altas_analista_fn(integer)'::regprocedure;
  if v_h is distinct from 'df8a99e0dfc4e1d94794073787aa84d7' then
    raise exception 'F7.1 postflight: el cuerpo de altas cambio dentro de la transaccion (huella %)', v_h;
  end if;
  -- 4b2) El vigilante ampliado quedo en su sitio: menciona a service_role en
  --      el cierre transversal (strpos, jamas LIKE: el guion bajo es comodin)
  --      y su veredicto YA corre con la lista ampliada mas abajo (4e).
  if (select strpos(p.prosrc, $srv$'authenticated', 'anon', 'service_role'$srv$)
        from pg_proc p
       where p.oid = 'private.assert_f7_piezas_cerradas()'::regprocedure) = 0 then
    raise exception 'F7.1 postflight: el vigilante NO quedo ampliado con service_role';
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

  -- Sin danza no hay nada que deshacer, pero se deja MEDIDO que la membresia
  -- del puente no gano opciones dentro de esta transaccion (defensa barata).
  if exists (select 1 from pg_auth_members m
              where m.roleid = 'crm_metricas_bridge'::regrole
                and m.member = 'postgres'::regrole and m.set_option) then
    raise exception 'F7.1 postflight: la membresia del rol puente gano la opcion SET (nadie debio tocarla)';
  end if;

  perform private.assert_analitica_leads_citas();
  perform private.assert_analista_vigencia();
end $$;

commit;
$mig_f71$])
  on conflict (version) do nothing;

  select name, statements into v_nombre, v_a
    from supabase_migrations.schema_migrations where version='20260831050000';
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
--    vivos - v3_core llama a v2_core). Su dueño es crm_metricas_bridge, pero
--    postgres HEREDA del dueño (membresia con USAGE): el revoke directo se
--    ejecuta COMO el dueño y el ACL resultante lleva al bridge como grantor
--    (MEDIDO contra prod el 30/08, ida y vuelta al byte). Sin cambio de rol.
--  * SOLO-INTERNAS (cerradas PERMANENTES, jamas se derriban): metricas_cartera_fn
--    (unico llamador: conversion_mensual_fn), crear/actualizar_contrato_con_cuenta
--    (organos de pdf_v2/v3) y public.actualizar_numero_contrato (organo de su
--    pdf_v3; ⚠️ toca public - OK explicito de Miguel via su !). La delegacion
--    DEFINER sobrevive: el chequeo de EXECUTE interno corre como OWNER.
--    service_role tambien pierde el EXECUTE que tenia en cartera y numero
--    (0 edges/front las llaman - censo 30-31/08).
--  * crm.metricas_altas_analista_fn: su partida de nacimiento SI esta en el
--    registro de prod (version 20260716203331, crm_metricas_gerencia_fn, CON
--    cuerpo - verificado contra prod el 30/08); lo que falta es el ARCHIVO
--    local (el repo tiene 167 de las 189 versiones). No se adopta nada: se
--    cierra tal cual, con su huella pinneada.
--
-- El censo de llamadores/superficies de las 7 lo hace el POSTFLIGHT llamando a
-- private.assert_f7_piezas_cerradas() (el vigilante de la Ola 0, ya endurecido
-- por dos auditorias) sobre las filas recien sembradas. Esta ola ademas AMPLIA
-- ese vigilante: el cierre transversal de herencia ahora vigila TAMBIEN que
-- service_role no alcance a postgres por membresia (hallazgo Codex 30/08 -
-- esta misma ola le quita a service_role dos EXECUTE directos).
--
-- (Reemplaza a la 20260831040000 preparada y NUNCA publicada: 3 hallazgos de
-- la refutacion de diseño de Codex del 30/08 - la danza del rol puente sobraba,
-- la adopcion sobraba, y el cierre transversal quedaba corto. Enmienda
-- registrada en MIGRACIONES.md.)

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
  -- postgres actua como el dueño de las v1/v2 por HERENCIA de la membresia
  -- (Codex 30/08 + medicion ida-y-vuelta contra prod): el revoke directo se
  -- ejecuta como el rol que de verdad posee el privilegio. Sin USAGE, el
  -- revoke seria un warning SIN efecto - por eso este candado.
  if not pg_has_role('postgres', 'crm_metricas_bridge', 'USAGE') then
    raise exception 'F7.1 preflight: postgres no HEREDA de crm_metricas_bridge (el revoke seria un no-op silencioso)';
  end if;
  -- El vigilante que esta ola AMPLIA debe ser el publicado en la Ola 0:
  if (select md5(p.prosrc) from pg_proc p
      where p.oid = 'private.assert_f7_piezas_cerradas()'::regprocedure)
     is distinct from 'e6f0070260e1fff2757201df8134167b' then
    raise exception 'F7.1 preflight: assert_f7_piezas_cerradas no es el de la Ola 0 (remedir antes de ampliarlo)';
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
-- 1) LOS 7 CIERRES.
-- =====================================================================
-- v1/v2: el dueño es crm_metricas_bridge; postgres HEREDA del dueño, asi que
-- el revoke directo se ejecuta COMO el (medido 30/08 contra prod: el ACL
-- resultante lleva al bridge como grantor, identico al que dejaria el propio
-- dueño; la vuelta con grant restaura el literal al byte). El postflight
-- compara el ACL LITERAL - un no-op silencioso no pasaria.
revoke execute on function crm.metricas_distribucion_leads_fn(date,date)    from authenticated, anon, public;
revoke execute on function crm.metricas_distribucion_leads_v2_fn(date,date) from authenticated, anon, public;

revoke execute on function crm.metricas_cartera_fn(date)                        from authenticated, anon, public, service_role;
revoke execute on function crm.metricas_altas_analista_fn(integer)              from authenticated, anon, public;
revoke execute on function crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)     from authenticated, anon, public;
revoke execute on function crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb) from authenticated, anon, public;
revoke execute on function public.actualizar_numero_contrato(uuid,text,text,text) from authenticated, anon, public, service_role;

-- =====================================================================
-- 2) AL LIBRO: 3 en observacion (14 dias) + 4 permanentes.
-- =====================================================================
-- RE-APLICACION tras un rollback: aquel NO borra (doctrina del libro: jamas
-- DELETE; la salida es estado='liberada') - deja las filas de esta ola en
-- 'liberada'. Aqui se RE-DECLARAN bajando el candado NOMBRADO (doctrina
-- limpieza-leads), con rastro en nota. En el primer viaje esto es un no-op.
alter table private.f7_piezas_en_observacion disable trigger trg_f7_obs_00_solo_crece;
update private.f7_piezas_en_observacion
   set estado = 'observacion',
       nota = coalesce(nota, '') || ' | re-declarada en re-aplicacion de F7.1'
 where ola = 'F7.1' and estado = 'liberada'
   and firma in ('crm.metricas_distribucion_leads_fn(date,date)',
                 'crm.metricas_distribucion_leads_v2_fn(date,date)',
                 'crm.metricas_altas_analista_fn(integer)');
update private.f7_piezas_en_observacion
   set estado = 'cerrada_permanente',
       nota = coalesce(nota, '') || ' | re-declarada en re-aplicacion de F7.1'
 where ola = 'F7.1' and estado = 'liberada';
alter table private.f7_piezas_en_observacion enable trigger trg_f7_obs_00_solo_crece;

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
   'nacida en la version 20260716203331 (crm_metricas_gerencia_fn) del registro de prod; el archivo local no existe - repo incompleto, NO version muda (Codex 30/08)'),
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
-- 3) EL VIGILANTE SE AMPLIA (hallazgo Codex 30/08): el cierre transversal
--    de herencia ahora vigila tambien a service_role. Esta ola le quita dos
--    EXECUTE directos; sin esta ampliacion, un GRANT futuro de MEMBRESIA
--    se los devolveria todos SIN tocar proacl y el vigia seguiria verde.
--    Cuerpo identico al de la Ola 0 salvo el trio de lineas del cierre
--    (preflight arriba pinnea la huella de la Ola 0; postflight verifica
--    que el nuevo cuerpo menciona a service_role via strpos - LIKE jamas:
--    el guion bajo es comodin).
-- =====================================================================
create or replace function private.assert_f7_piezas_cerradas()
returns text
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  r record; v_h text; v_acl text; v_n integer; v_p text;
  v_excluidos oid[]; v_permitidos oid[];
  v_obs integer := 0; v_perm integer := 0; v_dem integer := 0; v_lib integer := 0;
begin
  if not exists (select 1 from private.f7_piezas_en_observacion) then
    raise exception 'F7: la tabla de observacion esta VACIA (fail-closed)';
  end if;

  -- El conjunto vigilado entero se excluye de todo censo: las gemelas se
  -- nombran entre si y todas estan congeladas por huella de todos modos.
  select coalesce(array_agg((to_regprocedure(o.firma))::oid), '{}'::oid[]) into v_excluidos
    from private.f7_piezas_en_observacion o
   where to_regprocedure(o.firma) is not null;

  for r in select * from private.f7_piezas_en_observacion order by firma loop
    if r.estado = 'liberada' then
      -- Llegar aqui SOLO es posible por una migracion que bajo el candado
      -- (la maquina de estados lo prohibe por UPDATE): la pieza volvio al
      -- servicio deliberadamente y deja de vigilarse.
      v_lib := v_lib + 1; continue;
    end if;

    if r.estado = 'demolida' then
      if to_regprocedure(r.firma) is not null then
        raise exception 'F7: % RENACIO despues de su demolicion', r.firma;
      end if;
      if r.drop_no_antes_de is not null and current_date < r.drop_no_antes_de then
        raise exception 'F7: % fue demolida ANTES de su ventana (no antes de %)', r.firma, r.drop_no_antes_de;
      end if;
      v_dem := v_dem + 1; continue;
    end if;

    -- observacion / cerrada_permanente: existe, congelada, cerrada.
    if to_regprocedure(r.firma) is null then
      raise exception 'F7: % desaparecio SIN pasar por la demolicion', r.firma;
    end if;
    select md5(p.prosrc) into v_h from pg_proc p where p.oid = r.firma::regprocedure;
    if v_h is distinct from r.huella_md5 then
      raise exception 'F7: el cuerpo de % cambio estando cerrada (huella %)', r.firma, v_h;
    end if;
    select p.proacl::text into v_acl from pg_proc p where p.oid = r.firma::regprocedure;
    if v_acl is distinct from r.acl_esperada then
      raise exception 'F7: % SE REABRIO (ACL %, se esperaba %)', r.firma, v_acl, r.acl_esperada;
    end if;

    v_permitidos := '{}'::oid[];
    foreach v_p in array r.llamadores_permitidos loop
      if to_regprocedure(v_p) is null then
        raise exception 'F7: el llamador permitido % de % ya no resuelve', v_p, r.firma;
      end if;
      v_permitidos := v_permitidos || (to_regprocedure(v_p))::oid;
    end loop;

    -- Codex P0-1: el cuerpo de una funcion SQL-standard vive en prosqlbody
    -- (prosrc queda vacio) — se censan AMBOS textos.
    select count(*) into v_n
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname not in ('pg_catalog', 'information_schema')
       and p.oid <> all (v_excluidos || v_permitidos)
       and lower(replace(
             regexp_replace(regexp_replace(
               coalesce(p.prosrc, '') || ' ' || coalesce(pg_get_function_sqlbody(p.oid), ''),
               '--[^\n]*', ' ', 'g'),
               '/\*.*?\*/', ' ', 'g'), '"', '')) ~ r.patron_censo;
    if v_n <> 0 then
      raise exception 'F7: % funciones NUEVAS nombran a % — alguien empezo a usarla', v_n, r.firma;
    end if;

    -- Codex P0-1: las VISTAS y REGLAS tambien pueden llamarla — se censan.
    select count(*) into v_n
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname not in ('pg_catalog', 'information_schema')
       and c.relkind in ('v', 'm')
       and lower(replace(pg_get_viewdef(c.oid), '"', '')) ~ r.patron_censo;
    if v_n <> 0 then
      raise exception 'F7: % VISTAS nombran a % — alguien la cableo por una vista', v_n, r.firma;
    end if;

    -- Auditoria F7.0 (P1): el parser resuelve MAYUSCULAS y comillas — el censo
    -- tambien: todo texto se normaliza con lower() y sin comillas dobles.
    select (select count(*) from pg_policy pol
             where lower(replace(coalesce(pg_get_expr(pol.polqual, pol.polrelid), ''), '"', '')) ~ r.patron_censo
                or lower(replace(coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), ''), '"', '')) ~ r.patron_censo)
         + (select count(*) from pg_attrdef ad
             where lower(replace(pg_get_expr(ad.adbin, ad.adrelid), '"', '')) ~ r.patron_censo)
         + (select count(*) from pg_constraint c
             where c.contype = 'c' and lower(replace(pg_get_constraintdef(c.oid), '"', '')) ~ r.patron_censo)
         + (select count(*) from cron.job j where lower(replace(j.command, '"', '')) ~ r.patron_censo)
      into v_n;
    if v_n <> 0 then
      raise exception 'F7: % aparece en % superficies (policies/defaults/checks/cron)', r.firma, v_n;
    end if;

    if r.estado = 'observacion' then v_obs := v_obs + 1; else v_perm := v_perm + 1; end if;
  end loop;

  -- Codex P0-4: un GRANT de MEMBRESIA (rol puente hacia postgres) transmite
  -- los privilegios del owner SIN tocar proacl. Cierre transversal: ni
  -- authenticated, ni anon, NI service_role (ampliado en F7.1 - hallazgo Codex
  -- 30/08: esta ola le quita a service_role dos EXECUTE directos; sin esto, un
  -- GRANT futuro de membresia se los devolveria todos SIN tocar proacl y el
  -- vigia seguiria verde) pueden alcanzar a postgres por la cadena de roles.
  if exists (
    with recursive alcance as (
      select pr.oid from pg_roles pr where pr.rolname in ('authenticated', 'anon', 'service_role')
      union
      select m.roleid from pg_auth_members m join alcance al on al.oid = m.member
    )
    select 1 from alcance al2 join pg_roles pr2 on pr2.oid = al2.oid where pr2.rolname = 'postgres'
  ) then
    raise exception 'F7: authenticated/anon/service_role ALCANZAN a postgres por membresia de roles — puerta trasera de herencia';
  end if;

  return format('OK: %s piezas vigiladas (observacion %s, permanentes %s, demolidas %s, liberadas %s)',
                v_obs + v_perm + v_dem + v_lib, v_obs, v_perm, v_dem, v_lib);
end;
$function$;

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

  -- 4b) Los CUERPOS de las 7 no se movieron: esta ola solo toca ACLs (la
  --     huella de cada pieza queda ademas sellada en el libro, que el
  --     vigilante re-mide a diario).
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'crm.metricas_altas_analista_fn(integer)'::regprocedure;
  if v_h is distinct from 'df8a99e0dfc4e1d94794073787aa84d7' then
    raise exception 'F7.1 postflight: el cuerpo de altas cambio dentro de la transaccion (huella %)', v_h;
  end if;
  -- 4b2) El vigilante ampliado quedo en su sitio: menciona a service_role en
  --      el cierre transversal (strpos, jamas LIKE: el guion bajo es comodin)
  --      y su veredicto YA corre con la lista ampliada mas abajo (4e).
  if (select strpos(p.prosrc, $srv$'authenticated', 'anon', 'service_role'$srv$)
        from pg_proc p
       where p.oid = 'private.assert_f7_piezas_cerradas()'::regprocedure) = 0 then
    raise exception 'F7.1 postflight: el vigilante NO quedo ampliado con service_role';
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

  -- Sin danza no hay nada que deshacer, pero se deja MEDIDO que la membresia
  -- del puente no gano opciones dentro de esta transaccion (defensa barata).
  if exists (select 1 from pg_auth_members m
              where m.roleid = 'crm_metricas_bridge'::regrole
                and m.member = 'postgres'::regrole and m.set_option) then
    raise exception 'F7.1 postflight: la membresia del rol puente gano la opcion SET (nadie debio tocarla)';
  end if;

  perform private.assert_analitica_leads_citas();
  perform private.assert_analista_vigencia();
end $$;

commit;
$mig_f71$] then
    raise exception 'Registro F7.1: la fila quedo con OTRO cuerpo (posible insert concurrente)'; end if;
end $reg_f71$;
