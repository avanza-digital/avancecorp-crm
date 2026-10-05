-- REVERSA de 20261004222602_crm_bases_cargadas_repartir.sql (Bases cargadas · B9: repartir y recoger), r1.
-- Vuelve EXACTAMENTE a B8 (20261004184501): borra las tres puertas (crm.repartir_base, crm.recoger_de_base,
-- crm.contactos_de_base) y las 10 funciones del núcleo (private.bases_carga_reparto_*, bases_carga_repartir_core,
-- bases_carga_recoger_core, bases_carga_contactos_core) y REPONE la ayudante de B6 private.base_gestion_en_gestion_hasta con su
-- texto y comentario de B6 (20261003162500:46-75: el seguimiento activo vuelve a contar desde el descarte). B9 no creó tablas,
-- columnas, disparadores ni permisos de tabla: no hay nada más que deshacer.
-- DATOS: NO borra ni cambia filas. Lo que B9 hizo con datos queda como está y es coherente sin B9: los contactos repartidos
--   siguen siendo leads descartados de su analista (crm.leads.vendedor_id; la actividad «reasignación» en su historial), las
--   pertenencias conservan analista_id/asignado_en/asignado_por y los recibos repartir/recoger son inmutables. Reaplicar B9 los
--   vuelve a servir (el replay de un recibo vuelve a funcionar). Por eso, a diferencia de B8, se puede correr con datos: avisa
--   cuántos hay.
-- Se NIEGA si otra función o vista (B10 en adelante) usa las puertas o el núcleo de B9 (revertir antes la suya).
-- HUELLAS (solo lo PROPIO): antes de borrar exige que cada función de B9 —y la ayudante de B6 tal como la dejó B9— sea
--   EXACTAMENTE la que dejó B9 —cuerpo, seguridad, volatilidad, configuración, dueño, ACL y comentario— y que no haya
--   sobrecargas nuevas con sus nombres; cualquier deriva posterior → se niega y la nombra (no pisa trabajo ajeno). Huellas
--   medidas con B9 recién aplicada y search_path vacío. Después de reponer la de B6, exige su identidad de B6 (la que fija el
--   preflight de B9 y la reversa de B6: e90da5df…/af0701a9…, comentario 6b4c155f…).
-- LO AJENO (sin huellas de entorno): una FOTO, en esta misma base y bajo el candado de migración, de las demás funciones de
--   crm y private (identidad completa) y de los disparadores de crm.leads (nombre, función, habilitado); al final se exige
--   que la reversa no la haya cambiado. Y el censo analítico, igual antes y después.
-- CANDADOS: el de migración de la casa (crm_migracion_funciones). B9 no tiene disparadores ni tablas: DROP FUNCTION no bloquea
--   crm.leads. Una operación de B9 en vuelo termina antes o falla al llamar a la puerta borrada (sin efectos a medias: es una
--   transacción).
-- Conserva la fila de schema_migrations: anotar la reversa en MIGRACIONES.md.
begin;
set transaction isolation level read committed;
set local lock_timeout = '3s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;
select pg_advisory_xact_lock(hashtext('crm_migracion_funciones'));

do $chk$
begin
  if (
    to_regprocedure('crm.repartir_base(uuid,uuid,jsonb)') is not null
    and to_regprocedure('private.bases_carga_repartir_core(uuid,uuid,uuid,jsonb)') is not null
  ) is not true then
    raise exception 'REVERSA B9: la migracion no esta aplicada (faltan sus objetos)';
  end if;
  -- Ninguna función ajena a B9 usa sus puertas o su núcleo (B10 en adelante se revierte antes).
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname not in ('pg_catalog', 'information_schema')
                and p.prosrc ~ '(bases_carga_reparto_|bases_carga_repartir_core|bases_carga_recoger_core|bases_carga_contactos_core|repartir_base|recoger_de_base|contactos_de_base)'
                and not (n.nspname in ('crm', 'private')
                         and (p.proname like 'bases\_carga\_reparto\_%'
                              or p.proname in ('bases_carga_repartir_core', 'bases_carga_recoger_core', 'bases_carga_contactos_core',
                                               'repartir_base', 'recoger_de_base', 'contactos_de_base')))) then
    raise exception 'REVERSA B9: hay funciones que usan las puertas o el nucleo de B9 (B10 en adelante): corre antes su reversa';
  end if;
  if exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
              where c.relkind in ('v', 'm') and n.nspname not in ('pg_catalog', 'information_schema')
                and pg_get_viewdef(c.oid) ~ '(bases_carga_reparto_|repartir_base|recoger_de_base|contactos_de_base)') then
    raise exception 'REVERSA B9: hay vistas que usan B9: corre antes su reversa';
  end if;
end;
$chk$;

create temp table _rb9_censo_antes on commit drop as select c.objeto from private.contadores_crudos_leads_citas() c;
-- Foto de lo AJENO (misma base, bajo el candado de migración): funciones de crm y private salvo las de B9, con su identidad
-- completa; y los disparadores de crm.leads.
create temp table _rb9_ajeno_antes on commit drop as
  select p.oid::regprocedure::text as firma,
         md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|'
             || p.proowner::regrole::text || '|' || coalesce(p.proacl::text, 'NULL') || '|' || coalesce(obj_description(p.oid, 'pg_proc'), '')) as huella
    from pg_proc p
   where p.pronamespace in ('crm'::regnamespace, 'private'::regnamespace)
     and not (p.proname like 'bases\_carga\_reparto\_%'
              or p.proname in ('bases_carga_repartir_core', 'bases_carga_recoger_core', 'bases_carga_contactos_core',
                               'repartir_base', 'recoger_de_base', 'contactos_de_base', 'base_gestion_en_gestion_hasta'))
  union all
  select 'trigger ' || t.tgname, t.tgfoid::regprocedure::text || '|' || t.tgenabled::text
    from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and not t.tgisinternal;

-- Lo vivo es EXACTAMENTE lo que dejó B9.
do $huellas$
declare
  v_deriva text;
begin
  with esperado(pieza, huella) as (values
      ('crm.contactos_de_base(uuid,text)', '791d4aa9b6ffd323c085aa43a152506b'),
      ('crm.recoger_de_base(uuid,uuid,uuid)', '63bd40e4dc5ce756f72ed6deb0063515'),
      ('crm.repartir_base(uuid,uuid,jsonb)', '07a55655344cf3c394852876c2e44bea'),
      ('private.base_gestion_en_gestion_hasta(uuid)', '29677aeb5508a3cd457ec8616498884f'),
      ('private.bases_carga_contactos_core(uuid,uuid,text)', 'ebb846dfecfba53788f7da273c0a629f'),
      ('private.bases_carga_recoger_core(uuid,uuid,uuid,uuid)', '319adc522fbcec1129f105607b9fb2e0'),
      ('private.bases_carga_repartir_core(uuid,uuid,uuid,jsonb)', '3b9e9c832009fe0576caa42decd4cb1c'),
      ('private.bases_carga_reparto_analista(text,uuid[],uuid)', 'f1e0ee1ec0952a63212134776333adab'),
      ('private.bases_carga_reparto_constantes()', 'fb5d8cb42d3c8019be980fdc896abe17'),
      ('private.bases_carga_reparto_estado(boolean,boolean,text,uuid,boolean,date,uuid,boolean,boolean,boolean,boolean,date)', '3c4862f3a0a65e062c2bdc14f85a1baa'),
      ('private.bases_carga_reparto_hechos(uuid,timestamp with time zone)', '45af3c106b3bd875ee5081eee4924609'),
      ('private.bases_carga_reparto_motivo(boolean,boolean,text,boolean,date,boolean,date)', 'a04f72688e04836a84f8fe6f51ab973f'),
      ('private.bases_carga_reparto_recogible(uuid,uuid,timestamp with time zone,boolean)', 'dc38f1163d059bc7d91835529f172a95'),
      ('private.bases_carga_reparto_rol(uuid)', 'd2b70e1062f52a418227ca9453369723')),
  vivo(pieza, huella) as (
    select e.pieza, md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|'
           || p.proowner::regrole::text || '|' || coalesce(p.proacl::text, 'NULL') || '|' || coalesce(obj_description(p.oid, 'pg_proc'), ''))
      from esperado e join pg_proc p on p.oid = to_regprocedure(e.pieza))
  select string_agg(e.pieza, ', ' order by e.pieza) into v_deriva
    from esperado e left join vivo v on v.pieza = e.pieza
   where v.huella is distinct from e.huella;
  if v_deriva is not null then
    raise exception 'REVERSA B9: deriva en %: lo vivo no es lo que dejo B9 (algo lo cambio despues); no se sobrescribe, revisalo a mano', v_deriva;
  end if;
  if (select count(*) from pg_proc p where p.pronamespace in ('crm'::regnamespace, 'private'::regnamespace)
        and (p.proname like 'bases\_carga\_reparto\_%'
             or p.proname in ('bases_carga_repartir_core', 'bases_carga_recoger_core', 'bases_carga_contactos_core',
                              'repartir_base', 'recoger_de_base', 'contactos_de_base'))) <> 13 then
    raise exception 'REVERSA B9: deriva en el numero de funciones de B9 (sobrecargas nuevas): revisalo a mano';
  end if;
end;
$huellas$;

-- Las puertas primero; luego el núcleo.
drop function crm.repartir_base(uuid, uuid, jsonb);
drop function crm.recoger_de_base(uuid, uuid, uuid);
drop function crm.contactos_de_base(uuid, text);
drop function private.bases_carga_repartir_core(uuid, uuid, uuid, jsonb);
drop function private.bases_carga_recoger_core(uuid, uuid, uuid, uuid);
drop function private.bases_carga_contactos_core(uuid, uuid, text);
drop function private.bases_carga_reparto_estado(boolean, boolean, text, uuid, boolean, date, uuid, boolean, boolean, boolean, boolean, date);
drop function private.bases_carga_reparto_recogible(uuid, uuid, timestamptz, boolean);
drop function private.bases_carga_reparto_hechos(uuid, timestamptz);
drop function private.bases_carga_reparto_motivo(boolean, boolean, text, boolean, date, boolean, date);
drop function private.bases_carga_reparto_analista(text, uuid[], uuid);
drop function private.bases_carga_reparto_rol(uuid);
drop function private.bases_carga_reparto_constantes();

-- La ayudante de B6, con su texto y su comentario de B6 (20261003162500), exactos. CREATE OR REPLACE conserva dueño y ACL.
create or replace function private.base_gestion_en_gestion_hasta(p_lead_id uuid)
returns date
language sql stable security invoker set search_path = '' as $$
  -- Hasta qué día (Lima) el lead descartado sigue en gestión de su analista: el último intento de la base del ciclo vigente
  -- (desde descartado_en) + 7 días, o el día de la rellamada agendada en ese ciclo, lo que llegue más lejos. NULL si ya no
  -- está en gestión, si no está descartado o si su dueño ya no está activo (una baja libera sus leads).
  select case when x.hasta >= (pg_catalog.now() at time zone 'America/Lima')::date then x.hasta end
    from (
      select greatest(
               (i.ultimo at time zone 'America/Lima')::date + 7,
               -- La rellamada solo cuenta si la agendó un intento de ESTE ciclo (una de un ciclo anterior no bloquea).
               case when i.ultimo is not null then (l.proxima_llamada_en at time zone 'America/Lima')::date end) as hasta
        from crm.leads l
        cross join lateral (
          select max(a.creado_en) as ultimo
            from crm.actividades a
           where a.lead_id = l.id
             and a.metadata->>'evento' = 'intento_base'
             and a.creado_en >= l.descartado_en
        ) i
       where l.id = p_lead_id
         and l.etapa = 'descartado'
         and exists (select 1 from crm.equipo e join public.perfiles p on p.id = e.perfil_id
                      where e.perfil_id = l.vendedor_id and e.activo and p.activo)
    ) x
$$;
comment on function private.base_gestion_en_gestion_hasta(uuid) is
  'B6 (Miguel, 03/10/2026): seguimiento activo de un lead descartado. Último día (Lima) en que sigue en gestión de su analista: último intento de la base del ciclo vigente (desde descartado_en) + 7 días, o el día de la rellamada agendada en ese ciclo, el mayor. NULL si no hay seguimiento activo, si el lead no está descartado o si su dueño ya no está activo. Fuente única del candado (trg_leads_00_seguimiento_activo) y del gris del Centro de rescate. INVOKER, sin EXECUTE para roles de la API.';

create temp table _rb9_censo_despues on commit drop as select c.objeto from private.contadores_crudos_leads_citas() c;
do $post$
declare
  v_repartidos integer;
  v_recibos integer;
begin
  if (
    -- Nada de B9 queda.
    not exists (select 1 from pg_proc p where p.pronamespace in ('crm'::regnamespace, 'private'::regnamespace)
                 and (p.proname like 'bases\_carga\_reparto\_%'
                      or p.proname in ('bases_carga_repartir_core', 'bases_carga_recoger_core', 'bases_carga_contactos_core',
                                       'repartir_base', 'recoger_de_base', 'contactos_de_base')))
    -- Lo ajeno, igual que en la foto (ni más, ni menos, ni cambiado).
    and not exists ((select * from pg_temp._rb9_ajeno_antes)
                    except
                    (select p.oid::regprocedure::text,
                            md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|'
                                || p.proowner::regrole::text || '|' || coalesce(p.proacl::text, 'NULL') || '|' || coalesce(obj_description(p.oid, 'pg_proc'), ''))
                       from pg_proc p where p.pronamespace in ('crm'::regnamespace, 'private'::regnamespace)
                        and p.oid <> 'private.base_gestion_en_gestion_hasta(uuid)'::regprocedure
                     union all
                     select 'trigger ' || t.tgname, t.tgfoid::regprocedure::text || '|' || t.tgenabled::text
                       from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and not t.tgisinternal))
    and (select count(*) from pg_temp._rb9_ajeno_antes)
        = (select count(*) from pg_proc p where p.pronamespace in ('crm'::regnamespace, 'private'::regnamespace)) - 1
          + (select count(*) from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and not t.tgisinternal)
    -- La ayudante de B6, exactamente la de B6 (identidad, cuerpo, ACL y comentario).
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = 'e90da5df4c53fa1c30f0ca5f71431631'
                and md5(p.prosrc) = 'af0701a9e095e1004a64b7e289789d7c'
                and p.proacl is not null and p.proacl::text = '{postgres=X/postgres}'
                and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = '6b4c155f38d0722f9e9247547b5c3c2a'
           from pg_proc p where p.oid = to_regprocedure('private.base_gestion_en_gestion_hasta(uuid)'))
    -- Censo igual.
    and not exists (select 1 from pg_temp._rb9_censo_despues c where c.objeto not in (select a.objeto from pg_temp._rb9_censo_antes a))
    and (select count(*) from pg_temp._rb9_censo_antes) = (select count(*) from pg_temp._rb9_censo_despues)
  ) is not true then
    raise exception 'POSTFLIGHT REVERSA B9: quedo algo de B9, cambio algo ajeno o el censo';
  end if;
  select count(*) into v_repartidos from crm.base_carga_leads bl where bl.analista_id is not null;
  select count(*) into v_recibos from crm.base_carga_operaciones o where o.tipo in ('repartir', 'recoger');
  raise notice 'REVERSA B9 OK: 3 puertas y 10 funciones del nucleo borradas; ayudante de B6 repuesta exacta; lo ajeno y el censo, iguales. Datos que quedan (sin cambios): % contactos repartidos, % recibos repartir/recoger.', v_repartidos, v_recibos;
end;
$post$;
notify pgrst, 'reload schema';
commit;
