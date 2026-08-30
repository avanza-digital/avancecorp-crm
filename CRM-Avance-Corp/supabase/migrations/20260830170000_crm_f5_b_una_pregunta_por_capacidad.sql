-- P-055 Fase 5.b - UNA SOLA PREGUNTA POR CAPACIDAD y LOS PARES DECLARADOS.
--
-- LAS 4 DECISIONES DE MIGUEL (chat del 30/08, firmadas una a una):
--   D1 Registrar/editar VENTAS = "Administracion + equipo comercial vigente":
--      una sola pregunta - es admin del Portal O miembro activo del CRM
--      (vendedor/supervisor/gerencia) - y las DOS puertas gemelas responden lo
--      mismo. GABRIEL y GLORIA conservan lo que hacen; ALAN gana por el Portal
--      lo que ya tenia por el CRM.
--   D2 Ver el CATALOGO de productos = "Administracion + todo miembro CRM +
--      lector": la poblacion mas amplia de las dos puertas de hoy; solo lectura.
--   D3 CERRAR contrato = "admin O gerencia CRM activa": muere la trampa latente
--      (una gerencia del CRM que no fuera admin del Portal quedaba capada).
--   D4 GABRIEL y GLORIA quedan DECLARADOS como administracion sin CRM: el par
--      admin<->sin-ficha es legitimo y el candado de pares lo reconoce.
--
-- TOCA `public` (4 funciones: las 3 gemelas de producto y cerrar_contrato, mas
-- un trigger nuevo sobre public.perfiles para el candado de pares) CON ESE OK.
--
-- FORMA: dos preguntas nuevas en `private` (EXECUTE solo postgres, como los
-- nucleos: todas las puertas que las llaman son SECURITY DEFINER); las OCHO
-- puertas se convierten por REEMPLAZO ANCLADO sobre el cuerpo vivo; los pares
-- persona<->rol quedan en una tabla DECLARADA con candado en las dos mitades
-- (la ficha del CRM y el rol del Portal), con valvula del mismo idioma que
-- crm.op_privilegiada para las transiciones ordenadas (estilo Carlos Valles).

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- =====================================================================
-- 0) PREFLIGHT: las 8 puertas, ancladas por huella cruda (30/08).
-- =====================================================================
do $$
declare
  v_fn constant text[][] := array[
    array['public.crear_contrato_producto(uuid,jsonb,jsonb)',                   'a6ea3a7c41c952d5365c7640fe944aeb'],
    array['public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',         'a418a64e8f1273fe6dfae2606cce308e'],
    array['public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)','f0d90f4a266a07a50f04b8d3173e597d'],
    array['crm.crear_contrato_producto(uuid,jsonb,jsonb)',                      '081f65a5150a3347cbf897c1d4e12c63'],
    array['crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)',     'f3a9c0ae017672f5311f0c3fe86e82ef'],
    array['crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',            '1fb5724cc929aa9396a7e3ae654cf084'],
    array['crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)', 'fd7ab45765786037ef2c9416fe64e53e'],
    array['public.productos_inversion_seleccion_fn(uuid)',                      '0af48d75e921cd8d2033a3a5582fa44d'],
    array['crm.productos_inversion_seleccion_fn()',                             'b6460ac5f23b4821ddacbc7d982b9c1d'],
    array['public.cerrar_contrato(uuid,text,uuid)',                             'd2516b0b185e8387c75cb31e6dcaa0f3']
  ];
  v_fila text[]; v_h text;
begin
  foreach v_fila slice 1 in array v_fn loop
    select md5(p.prosrc) into v_h from pg_proc p where p.oid = v_fila[1]::regprocedure;
    if v_h is distinct from v_fila[2] then
      raise exception 'F5.b preflight: % cambio desde la medicion (huella %)', v_fila[1], v_h;
    end if;
  end loop;
end $$;

-- =====================================================================
-- 1) LAS DOS PREGUNTAS.
-- =====================================================================
create or replace function private.puede_registrar_ventas()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  -- D1: administracion del Portal O equipo comercial vigente del CRM.
  -- La membresia del CRM ya exige activo en las dos mitades (rol_crm()).
  select public.es_admin()
      or private.puede_gestionar_contratos_crm();
$function$;
comment on function private.puede_registrar_ventas() is
  'P-055 F5.b (D1). LA pregunta unica de la capacidad "registrar/editar ventas": admin del Portal O vendedor/supervisor/gerencia activo del CRM. Las puertas gemelas de public y crm preguntan ESTO.';
revoke all on function private.puede_registrar_ventas() from public;

create or replace function private.puede_ver_catalogo_productos()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  -- D2: administracion O cualquier miembro activo del CRM O lector global.
  select public.es_admin()
      or private.rol_crm((select auth.uid())) is not null
      or private.es_lector_global();
$function$;
comment on function private.puede_ver_catalogo_productos() is
  'P-055 F5.b (D2). LA pregunta unica de la capacidad "ver el catalogo de productos de inversion" (solo lectura de la carta).';
revoke all on function private.puede_ver_catalogo_productos() from public;

-- =====================================================================
-- 2) LAS OCHO PUERTAS PREGUNTAN LO MISMO (reemplazo anclado).
-- =====================================================================
do $$
declare
  v_caso constant text[][] := array[
    -- gemelas de VENTAS, lado Portal (3)
    array['public.crear_contrato_producto(uuid,jsonb,jsonb)',
          'if not ((select public.es_admin()) or (select public.es_analista())) then',
          'if not (select private.puede_registrar_ventas()) then', '1'],
    array['public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
          'if not ((select public.es_admin()) or (select public.es_analista())) then',
          'if not (select private.puede_registrar_ventas()) then', '1'],
    array['public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
          'if not ((select public.es_admin()) or (select public.es_analista())) then',
          'if not (select private.puede_registrar_ventas()) then', '1'],
    -- gemelas de VENTAS, lado CRM (4)
    array['crm.crear_contrato_producto(uuid,jsonb,jsonb)',
          'if not private.puede_gestionar_contratos_crm() then',
          'if not (select private.puede_registrar_ventas()) then', '1'],
    array['crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)',
          'if not private.puede_gestionar_contratos_crm() then',
          'if not (select private.puede_registrar_ventas()) then', '1'],
    array['crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
          'if not private.puede_gestionar_contratos_crm() then',
          'if not (select private.puede_registrar_ventas()) then', '1'],
    array['crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
          'if not private.puede_gestionar_contratos_crm() then',
          'if not (select private.puede_registrar_ventas()) then', '1']
  ];
  v_fila text[]; v_def text; v_veces integer;
begin
  foreach v_fila slice 1 in array v_caso loop
    select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.oid = v_fila[1]::regprocedure;
    v_veces := (length(v_def) - length(replace(v_def, v_fila[2], ''))) / length(v_fila[2]);
    if v_veces <> v_fila[4]::integer then
      raise exception 'F5.b: el ancla de % aparece % veces', v_fila[1], v_veces;
    end if;
    execute replace(v_def, v_fila[2], v_fila[3]);
  end loop;
end $$;

-- El catalogo, lado Portal: SOLO el gate de entrada. La rama del "contrato
-- reciente propio" conserva es_analista_vigente a proposito: no es la carta,
-- es VER LA CONDICION de un contrato concreto y esa exige ser su autor vigente.
do $$
declare v_def text; v_veces integer; v_ancla text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p where p.oid = 'public.productos_inversion_seleccion_fn(uuid)'::regprocedure;
  v_ancla := 'or not ((select public.es_admin()) or (select private.es_analista_vigente())) then';
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then raise exception 'F5.b: ancla del catalogo Portal aparece % veces', v_veces; end if;
  v_def := replace(v_def, v_ancla, 'or not (select private.puede_ver_catalogo_productos()) then');
  execute v_def;

  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p where p.oid = 'crm.productos_inversion_seleccion_fn()'::regprocedure;
  v_ancla := 'or (
       private.rol_crm(v_actor) is null
       and not private.es_lector_global()
     ) then';
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then raise exception 'F5.b: ancla del catalogo CRM aparece % veces', v_veces; end if;
  v_def := replace(v_def, v_ancla, 'or not (select private.puede_ver_catalogo_productos()) then');
  execute v_def;

  -- D3: cerrar contrato - muere la trampa latente.
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p where p.oid = 'public.cerrar_contrato(uuid,text,uuid)'::regprocedure;
  v_ancla := 'IF NOT es_admin() THEN';
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then raise exception 'F5.b: ancla de cerrar_contrato aparece % veces', v_veces; end if;
  v_def := replace(v_def, v_ancla, 'IF NOT (es_admin() OR private.es_gerencia_crm_activa()) THEN');
  execute v_def;
end $$;

-- =====================================================================
-- 3) LOS PARES DECLARADOS (D4) y SU CANDADO en las dos mitades.
-- =====================================================================
create table if not exists private.pares_autoridad (
  rol_portal text not null,
  rol_crm    text,           -- NULL = "sin ficha en el CRM" (par legitimo)
  razon      text not null,
  constraint razon_de_verdad check (length(btrim(razon)) >= 30),
  constraint par_unico unique nulls not distinct (rol_portal, rol_crm)
);
alter table private.pares_autoridad enable row level security;
comment on table private.pares_autoridad is
  'P-055 F5.b (D4). Los pares rol-Portal <-> rol-CRM que la casa reconoce. Un par que no este aqui no puede existir: lo vigilan los candados de crm.equipo y public.perfiles (valvula crm.cambiando_par para transiciones ordenadas).';

insert into private.pares_autoridad (rol_portal, rol_crm, razon) values
  ('superadmin','gerencia',  'La llave que asigna roles: una sola persona; su autoridad operativa viene de la membresia de gerencia.'),
  ('admin',     'gerencia',  'Gerencia real del negocio: es_admin gatea contratos, productos y cartera (caso Carlos Valles).'),
  ('admin',     null,        'Administracion del Portal sin trabajo de leads: GABRIEL y GLORIA, declarados por decision D4 del 30/08.'),
  ('directorio','directorio','Par amarrado desde la Fase 1: Directorio es capacidad de lectura, no alias de gerencia.'),
  ('analista',  'vendedor',  'El par estandar del equipo comercial: la misma persona con sus dos nombres.'),
  ('analista',  'supervisor','Supervisora del equipo que ademas lleva cartera propia en el Portal.'),
  ('comercial', 'vendedor',  'Perfil comercial del Portal (sin cartera de clientes propia) que vende en el CRM.'),
  ('comercial', 'supervisor','Perfil comercial del Portal que supervisa en el CRM (cuenta de prueba incluida).'),
  ('comercial', 'coordinador','La coordinadora de reparto: sin cartera en el Portal y sin venta propia en el CRM.')
on conflict (rol_portal, rol_crm) do update set razon = excluded.razon;

create or replace function private.par_autoridad_valido(p_rol_portal text, p_rol_crm text)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists (
    select 1 from private.pares_autoridad pa
    where pa.rol_portal = p_rol_portal
      and pa.rol_crm is not distinct from p_rol_crm
  );
$function$;
revoke all on function private.par_autoridad_valido(text, text) from public;

-- Un par declarado no se borra por fuera: borrarlo RELAJA el candado sin dejar
-- huella (leccion F1.6). Se retira en una migracion que lo justifique.
create or replace function private.trg_pares_autoridad_no_borrar()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if (select auth.uid()) is not null then
    raise exception 'Un par de autoridad no se borra desde una sesion de persona.' using errcode = '42501';
  end if;
  if tg_op = 'TRUNCATE' then
    raise exception 'La tabla de pares no se vacia.' using errcode = '42501';
  end if;
  raise exception 'Un par de autoridad no se borra desde una migracion sin justificarlo.' using errcode = '42501';
end;
$function$;

drop trigger if exists trg_pares_autoridad_no_borrar on private.pares_autoridad;
create trigger trg_pares_autoridad_no_borrar
  before delete on private.pares_autoridad
  for each row execute function private.trg_pares_autoridad_no_borrar();
drop trigger if exists trg_pares_autoridad_no_truncar on private.pares_autoridad;
create trigger trg_pares_autoridad_no_truncar
  before truncate on private.pares_autoridad
  for each statement execute function private.trg_pares_autoridad_no_borrar();

-- Candado, mitad CRM: nadie entra al equipo (ni cambia de rol ahi) con un par
-- que la casa no reconozca. La valvula permite la transicion ordenada.
create or replace function private.trg_equipo_par_autoridad()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare v_rol_portal text;
begin
  -- El guardian vive donde hay una PERSONA detras (panel: RPC DEFINER con
  -- auth.uid presente). service_role (edges, seed), la consola postgres
  -- (migraciones, guiones tipo Carlos Valles) y el replay del seed operan con
  -- auth.uid()=NULL y son deliberados: exentos, como proteger_campos_inmutables.
  if (select auth.uid()) is null
     or coalesce(current_setting('crm.cambiando_par', true), '') = 'on' then
    return new;
  end if;
  select p.rol into v_rol_portal from public.perfiles p where p.id = new.perfil_id;
  if v_rol_portal is null then
    raise exception 'La ficha del equipo necesita un perfil del Portal (%).', new.perfil_id;
  end if;
  if not private.par_autoridad_valido(v_rol_portal, new.rol_crm) then
    raise exception 'El par %/% no esta declarado en private.pares_autoridad. Si es legitimo, se declara en una migracion; si es una transicion, usa la valvula crm.cambiando_par con el guion ordenado.',
      v_rol_portal, new.rol_crm using errcode = '42501';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_equipo_par_autoridad on crm.equipo;
create trigger trg_equipo_par_autoridad
  before insert or update of rol_crm, perfil_id on crm.equipo
  for each row execute function private.trg_equipo_par_autoridad();

-- Candado, mitad Portal: cambiar el rol del Portal de alguien CON ficha exige
-- que el par resultante este declarado (misma valvula).
create or replace function private.trg_perfiles_par_autoridad()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare v_rol_crm text; v_tiene boolean;
begin
  if (select auth.uid()) is null
     or coalesce(current_setting('crm.cambiando_par', true), '') = 'on' then
    return new;
  end if;
  select true, e.rol_crm into v_tiene, v_rol_crm from crm.equipo e where e.perfil_id = new.id;
  if coalesce(v_tiene, false) and not private.par_autoridad_valido(new.rol, v_rol_crm) then
    raise exception 'El par %/% no esta declarado en private.pares_autoridad (la persona tiene ficha en el CRM). Transiciones: valvula crm.cambiando_par + guion ordenado.',
      new.rol, v_rol_crm using errcode = '42501';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_perfiles_par_autoridad on public.perfiles;
create trigger trg_perfiles_par_autoridad
  before update of rol on public.perfiles
  for each row
  when (old.rol is distinct from new.rol)
  execute function private.trg_perfiles_par_autoridad();

-- =====================================================================
-- 3b) HIGIENE DEL TRINQUETE DE VIGENCIA (F5.a). Las 3 gemelas del Portal
--     dejan de nombrar es_analista (ahora preguntan puede_registrar_ventas):
--     salen del censo de vigencia. Sus exenciones quedan huerfanas y el tope
--     se aprieta al conteo nuevo (solo baja).
-- =====================================================================
delete from private.analista_vigencia_exenciones
 where objeto in ('public.crear_contrato_producto(uuid,jsonb,jsonb)',
                  'public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
                  'public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)');
update private.analista_vigencia_tope
   set tope = (select count(*) from private.puertas_analista_sin_vigencia())
 where id;

-- =====================================================================
-- 4) POSTFLIGHT.
-- =====================================================================
do $$
declare v_n integer; v_malos text;
begin
  -- 4.1 Las 7 gemelas de ventas preguntan LO MISMO y ninguna conserva su
  --     criterio viejo en el gate.
  select count(*) into v_n from pg_proc p
   where p.oid in ('public.crear_contrato_producto(uuid,jsonb,jsonb)'::regprocedure,
                   'public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)'::regprocedure,
                   'public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)'::regprocedure,
                   'crm.crear_contrato_producto(uuid,jsonb,jsonb)'::regprocedure,
                   'crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)'::regprocedure,
                   'crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)'::regprocedure,
                   'crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)'::regprocedure)
     and strpos(p.prosrc, 'puede_registrar_ventas') > 0
     and strpos(p.prosrc, 'if not private.puede_gestionar_contratos_crm() then') = 0
     and p.prosrc !~ 'if not \(\(select public\.es_admin\(\)\) or \(select public\.es_analista\(\)\)\)';
  if v_n <> 7 then
    raise exception 'F5.b postflight: solo % de 7 gemelas de ventas quedaron unificadas', v_n;
  end if;

  -- 4.2 Las 2 del catalogo.
  select count(*) into v_n from pg_proc p
   where p.oid in ('public.productos_inversion_seleccion_fn(uuid)'::regprocedure,
                   'crm.productos_inversion_seleccion_fn()'::regprocedure)
     and strpos(p.prosrc, 'puede_ver_catalogo_productos') > 0;
  if v_n <> 2 then
    raise exception 'F5.b postflight: el catalogo no quedo unificado (%/2)', v_n;
  end if;

  -- 4.3 Cerrar contrato con la gerencia dentro.
  if not exists (select 1 from pg_proc p
    where p.oid = 'public.cerrar_contrato(uuid,text,uuid)'::regprocedure
      and strpos(p.prosrc, 'es_gerencia_crm_activa') > 0) then
    raise exception 'F5.b postflight: cerrar_contrato sigue solo-admin';
  end if;

  -- 4.4 ACL de las preguntas nuevas: SOLO postgres.
  if exists (
    select 1 from pg_proc p
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     where p.oid in ('private.puede_registrar_ventas()'::regprocedure,
                     'private.puede_ver_catalogo_productos()'::regprocedure,
                     'private.par_autoridad_valido(text,text)'::regprocedure)
       and a.grantee <> 'postgres'::regrole::oid
  ) then
    raise exception 'F5.b postflight: una pregunta nueva quedo con EXECUTE para alguien mas que postgres';
  end if;

  -- 4.5 La tabla de pares con RLS y TODO el mundo real conforme.
  if not (select relrowsecurity from pg_class where oid = 'private.pares_autoridad'::regclass) then
    raise exception 'F5.b postflight: pares_autoridad sin RLS';
  end if;
  select string_agg(p.nombre_completo || ' (' || p.rol || '/' || coalesce(e.rol_crm,'sin ficha') || ')', ', ')
    into v_malos
    from public.perfiles p
    left join crm.equipo e on e.perfil_id = p.id
   where p.rol <> 'cliente'
     and not private.par_autoridad_valido(p.rol, e.rol_crm);
  if v_malos is not null then
    raise exception 'F5.b postflight: personas fuera de los pares declarados: %', v_malos;
  end if;

  -- 4.6 Los candados de pares, activos (equipo cubre rol_crm y perfil_id).
  if (select count(*) from pg_trigger t
       where (t.tgrelid = 'crm.equipo'::regclass and t.tgname = 'trg_equipo_par_autoridad')
          or (t.tgrelid = 'public.perfiles'::regclass and t.tgname = 'trg_perfiles_par_autoridad')
     ) <> 2 then
    raise exception 'F5.b postflight: falta un candado de pares';
  end if;
  if not exists (select 1 from pg_trigger t
       where t.tgrelid = 'crm.equipo'::regclass and t.tgname = 'trg_equipo_par_autoridad'
         and (t.tgattr::int2[] @> array[(select attnum from pg_attribute where attrelid='crm.equipo'::regclass and attname='perfil_id')]::int2[])) then
    raise exception 'F5.b postflight: el candado del equipo no vigila perfil_id';
  end if;

  -- 4.7 Los DOS trinquetes previos siguen verdes tras esta migracion.
  declare v_v text; v_a text;
  begin
    select private.assert_analista_vigencia() into v_v;
    if v_v not like 'OK:%' then raise exception 'F5.b postflight: el trinquete de vigencia (F5.a) quedo roto: %', v_v; end if;
    select private.assert_analitica_leads_citas() into v_a;
    if v_a not like 'OK:%' then raise exception 'F5.b postflight: el trinquete de analitica (F6) quedo roto: %', v_a; end if;
  end;
end $$;

commit;
