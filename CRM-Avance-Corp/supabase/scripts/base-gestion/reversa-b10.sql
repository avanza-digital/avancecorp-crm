-- REVERSA de 20261004223253_crm_bases_cargadas_seguimiento.sql (Bases cargadas · B10: seguimiento, la base en la lista y el
-- capital al reactivar; r2: la definición única del estado en B9). Vuelve EXACTAMENTE a B9 r2 (20261004222602): borra
-- crm.seguimiento_bases, crm.seguimiento_base, crm.seguimiento_base_detalle, crm.reactivar_lead_base_v2,
-- crm.registrar_intento_base_v2, los núcleos con capital (private.base_gestion_reactivar_capital_core y
-- private.base_gestion_intento_capital_core) y los ayudantes private.bases_carga_estado_contacto,
-- private.bases_carga_reparto_motivo_bloque y private.bases_carga_seguimiento_* (cifras, rol, exigir_base, filas); repone de
-- B9 r2, byte a byte (cuerpo, identidad, ACL y comentario): su clasificador private.bases_carga_reparto_estado (lo vuelve a
-- crear), las tres piezas de su núcleo (private.bases_carga_contactos_core, private.bases_carga_reparto_recogible,
-- private.bases_carga_repartir_core) y el comentario de sus tres puertas (crm.repartir_base, crm.recoger_de_base,
-- crm.contactos_de_base, cuyo cuerpo B10 no tocó); repone
-- crm.obtener_base_gestion(uuid, boolean) con el texto de B6b (md5 36af7e9c…), su ACL y su comentario (el de B6c, md5
-- 67f83881…), y el CUERPO y el comentario de private.base_gestion_reactivar_core(uuid,uuid,uuid,text) (B3c, md5 c7e19f14…) y
-- de private.base_gestion_intento_core(…6…) (B3c, md5 db8ba2b4…): sus firmas y ACL nunca cambiaron. Las puertas publicadas
-- crm.reactivar_lead_base y crm.registrar_intento_base no se tocan.
-- Sin datos que perder: B10 no tiene tablas. Un capital que ya se puso al reactivar se queda en el lead (es un dato del lead).
-- ⚠ Si la pantalla F6 ya llama a reactivar_lead_base_v2 o al seguimiento, tras revertir verá «disponible pronto» (PGRST202).
-- Antes que la de B9 (la de B9 se niega mientras su núcleo tenga el texto de B10). Se NIEGA si otra función (F6/B11 en
-- adelante) usa los objetos de B10, si la puerta publicada o el intento ya no son los de
-- antes (llamarían al núcleo con otra forma), o si algo de B10 derivó.
-- HUELLAS: solo las PROPIAS (lección de la rama de B8: nada de huellas globales que dependen del entorno). Antes de sobrescribir
--   nada exige que cada función de B10 sea EXACTAMENTE la que dejó B10 —cuerpo, seguridad, volatilidad, configuración, dueño,
--   ACL y comentario—, medidas con B10 recién aplicada y search_path vacío. De lo AJENO, una foto antes y otra después (todas
--   las funciones de crm y private salvo las de B10, y el censo analítico), en esta misma transacción: la reversa no lo cambia.
-- CANDADOS: solo el de migración de la casa (crm_migracion_funciones). Sin candados de tabla (B10 no tiene tablas).
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
    to_regprocedure('crm.seguimiento_bases()') is not null
    and to_regprocedure('crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)') is not null
    and to_regprocedure('private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)') is not null
  ) is not true then
    raise exception 'REVERSA B10: la migracion no esta aplicada (faltan sus objetos)';
  end if;
  -- B10 borró el clasificador de B9 (private.bases_carga_reparto_estado): si alguien lo repuso, no se pisa.
  if to_regprocedure('private.bases_carga_reparto_estado(boolean,boolean,text,uuid,boolean,date,uuid,boolean,boolean,boolean,boolean,date)') is not null then
    raise exception 'REVERSA B10: el clasificador de B9 ya existe (otra migracion lo repuso): revisalo a mano';
  end if;
  -- Ninguna función ajena a B10 usa sus puertas o sus ayudantes (F6/B11 en adelante se revierte antes).
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname not in ('pg_catalog', 'information_schema')
                and p.prosrc ~ 'seguimiento_bases|seguimiento_base|reactivar_lead_base_v2|registrar_intento_base_v2|bases_carga_estado_contacto|bases_carga_reparto_motivo_bloque|bases_carga_seguimiento_|base_gestion_reactivar_capital_core|base_gestion_intento_capital_core'
                and p.oid::regprocedure::text not in ('crm.obtener_base_gestion(uuid,boolean)',
                                   'crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)',
                                   'crm.seguimiento_base(uuid)',
                                   'crm.seguimiento_base_detalle(uuid,uuid,text)',
                                   'crm.seguimiento_bases()',
                                   'private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)',
                                   'private.base_gestion_reactivar_core(uuid,uuid,uuid,text)',
                                   'private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamp with time zone,numeric,text)',
                                   'private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone)',
                                   'crm.registrar_intento_base_v2(uuid,uuid,text,text,timestamp with time zone,numeric,text)',
                                   'private.bases_carga_estado_contacto(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamp with time zone,timestamp with time zone,uuid,uuid[],date,boolean,boolean,boolean)',
                                   'private.bases_carga_reparto_motivo_bloque(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamp with time zone,timestamp with time zone,uuid,uuid[],date)',
                                   'private.bases_carga_contactos_core(uuid,uuid,text)',
                                   'private.bases_carga_reparto_recogible(uuid,uuid,timestamp with time zone,boolean)',
                                   'private.bases_carga_repartir_core(uuid,uuid,uuid,jsonb)',
                                   'crm.contactos_de_base(uuid,text)',
                                   'crm.recoger_de_base(uuid,uuid,uuid)',
                                   'crm.repartir_base(uuid,uuid,jsonb)',
                                   'private.bases_carga_seguimiento_cifras()',
                                   'private.bases_carga_seguimiento_exigir_base(uuid,text,uuid)',
                                   'private.bases_carga_seguimiento_filas(uuid[],date)',
                                   'private.bases_carga_seguimiento_rol(uuid)',
                                   'private.bases_carga_reparto_estado(boolean,boolean,text,uuid,boolean,date,uuid,boolean,boolean,boolean,boolean,date)')) then
    raise exception 'REVERSA B10: hay funciones que usan las puertas o los ayudantes de B10 (F6/B11 en adelante): corre antes su reversa';
  end if;
  if exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
              where c.relkind in ('v', 'm') and n.nspname not in ('pg_catalog', 'information_schema')
                and pg_get_viewdef(c.oid) ~ 'seguimiento_base|reactivar_lead_base_v2|registrar_intento_base_v2|bases_carga_estado_contacto|bases_carga_reparto_|bases_carga_seguimiento_|bases_carga_contactos_core|bases_carga_repartir_core|obtener_base_gestion|base_gestion_reactivar_|base_gestion_intento_') then
    raise exception 'REVERSA B10: hay vistas que usan B10: corre antes su reversa';
  end if;
  -- Quienes llaman a los núcleos: a los de siempre, solo las puertas publicadas (con su cuerpo de antes); a los núcleos con
  -- capital, solo lo de B10 (que se borra o se repone aquí).
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname not in ('pg_catalog', 'information_schema') and p.prosrc ~ 'base_gestion_reactivar_core'
                and p.oid not in (to_regprocedure('crm.reactivar_lead_base(uuid,uuid,text)'), to_regprocedure('private.bases_carga_reparto_hechos(uuid,timestamp with time zone)')))  -- B9: la nombra en un comentario
     or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname not in ('pg_catalog', 'information_schema') and p.prosrc ~ 'base_gestion_intento_core'
                   and p.oid not in (to_regprocedure('crm.registrar_intento_base(uuid,uuid,text,text,timestamp with time zone)'), to_regprocedure('private.bases_carga_reparto_hechos(uuid,timestamp with time zone)')))  -- B9: la nombra en un comentario
     or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname not in ('pg_catalog', 'information_schema') and p.prosrc ~ 'base_gestion_reactivar_capital_core'
                   and p.oid not in (to_regprocedure('private.base_gestion_reactivar_core(uuid,uuid,uuid,text)'),
                                     to_regprocedure('crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)'),
                                     to_regprocedure('private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamp with time zone,numeric,text)')))
     or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname not in ('pg_catalog', 'information_schema') and p.prosrc ~ 'base_gestion_intento_capital_core'
                   and p.oid not in (to_regprocedure('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone)'),
                                     to_regprocedure('crm.registrar_intento_base_v2(uuid,uuid,text,text,timestamp with time zone,numeric,text)')))
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.reactivar_lead_base(uuid,uuid,text)')) is distinct from 'bf59d77929877e7a5eb46704d934363e'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.registrar_intento_base(uuid,uuid,text,text,timestamp with time zone)')) is distinct from 'd92c791fbe6f84e5d4f8ca39357b4721'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.base_gestion_resumen()')) is distinct from 'b773a7c49fbdfc45133b3405991b1958'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.base_gestion_resumen_detalle(uuid,text)')) is distinct from '068372248be4127c80ba002542c9b4b8' then
    raise exception 'REVERSA B10: las puertas publicadas de reactivar o de intentos o los envoltorios de la lista ya no son los de antes de B10, u otra funcion llama a los nucleos: revisalo a mano';
  end if;
end;
$chk$;

-- Lo vivo de B10 es EXACTAMENTE lo que dejó B10 (si no, se niega y nombra la deriva; no pisa trabajo ajeno).
do $huellas$
declare
  v_deriva text;
begin
  with esperado(firma, huella) as (values
      ('crm.obtener_base_gestion(uuid,boolean)', '7def61844c1effddaf89a112a1e7a1c4'),
      ('crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)', '34c3b4a29bd21c4331ad8bd28310f4b3'),
      ('crm.seguimiento_base(uuid)', 'e2b46f500df423dd9233038fabd331ca'),
      ('crm.seguimiento_base_detalle(uuid,uuid,text)', '09edeb801a523100b13f77ffc04d32de'),
      ('crm.seguimiento_bases()', '7e608ca814f148ba0ee86cec31665536'),
      ('private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)', '06424643a117c165a98081b812cad285'),
      ('private.base_gestion_reactivar_core(uuid,uuid,uuid,text)', '11020929ecb70edb27446c76ad3d2cca'),
      ('private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamp with time zone,numeric,text)', '8618a8eadc220aeeaae79ccca78e00de'),
      ('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone)', '27ebca8ce85f0da758c0436362cca5e5'),
      ('crm.registrar_intento_base_v2(uuid,uuid,text,text,timestamp with time zone,numeric,text)', 'e5e9a7cb1835df3eb25663846e7d3429'),
      ('private.bases_carga_estado_contacto(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamp with time zone,timestamp with time zone,uuid,uuid[],date,boolean,boolean,boolean)', '551a745e37500ff611950109d816974c'),
      ('private.bases_carga_reparto_motivo_bloque(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamp with time zone,timestamp with time zone,uuid,uuid[],date)', '8bccfebc1255775d702fae303248df2a'),
      ('private.bases_carga_contactos_core(uuid,uuid,text)', '1a4247b6918cd46380f7d1cd1737599f'),
      ('private.bases_carga_reparto_recogible(uuid,uuid,timestamp with time zone,boolean)', 'a65034e810f94573bec8d3c225c78af6'),
      ('private.bases_carga_repartir_core(uuid,uuid,uuid,jsonb)', '9cea709447081fe3d292cb0c880e9965'),
      ('crm.contactos_de_base(uuid,text)', 'c6f0f0247659cde9060fe70c503e3a05'),
      ('crm.recoger_de_base(uuid,uuid,uuid)', '40765f05d261d58e7a4257fb9d55757c'),
      ('crm.repartir_base(uuid,uuid,jsonb)', '64f6d7e109030760192cb6c046b5ae64'),
      ('private.bases_carga_seguimiento_cifras()', '94eea94ed4051a380f36fa99e8fec740'),
      ('private.bases_carga_seguimiento_exigir_base(uuid,text,uuid)', '482935da963e9e3e404c762fcf9a73d7'),
      ('private.bases_carga_seguimiento_filas(uuid[],date)', 'f7b0e98a759bbfff5ab072b1cc4f9380'),
      ('private.bases_carga_seguimiento_rol(uuid)', 'd26ce1ca2603fd319c4cc46a51035f9f')),
  vivo(firma, huella) as (
    select e.firma, md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text || '|' || coalesce(p.proacl::text, 'NULL') || '|' || coalesce(obj_description(p.oid, 'pg_proc'), ''))
      from esperado e join pg_proc p on p.oid = to_regprocedure(e.firma))
  select string_agg(e.firma, ', ' order by e.firma) into v_deriva
    from esperado e left join vivo v on v.firma = e.firma
   where v.huella is distinct from e.huella;
  if v_deriva is not null then
    raise exception 'REVERSA B10: deriva en %: lo vivo no es lo que dejo B10 (revisalo a mano)', v_deriva;
  end if;
  if (select count(*) from pg_proc p where p.pronamespace in ('crm'::regnamespace, 'private'::regnamespace)
        and p.proname in ('obtener_base_gestion', 'reactivar_lead_base_v2', 'seguimiento_bases', 'seguimiento_base', 'seguimiento_base_detalle',
                          'base_gestion_reactivar_core', 'base_gestion_reactivar_capital_core', 'base_gestion_intento_core',
                          'base_gestion_intento_capital_core', 'registrar_intento_base_v2', 'bases_carga_estado_contacto', 'bases_carga_reparto_motivo_bloque', 'bases_carga_contactos_core',
                          'bases_carga_reparto_recogible', 'bases_carga_repartir_core', 'contactos_de_base', 'recoger_de_base', 'repartir_base', 'bases_carga_seguimiento_cifras',
                          'bases_carga_seguimiento_exigir_base', 'bases_carga_seguimiento_filas', 'bases_carga_seguimiento_rol')) <> 22 then
    raise exception 'REVERSA B10: el numero de funciones de B10 no es el esperado (una sobrecarga nueva?): revisalo a mano';
  end if;
end;
$huellas$;

-- Foto de lo AJENO (solo catálogo): toda función de crm y private salvo las de B10, y el censo analítico.
create temp table _rb10_ajeno_antes on commit drop as
  select p.oid::regprocedure::text as firma,
         md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|'
             || p.proowner::regrole::text || '|' || coalesce(p.proacl::text, 'NULL')) as huella
    from pg_proc p
   where p.pronamespace in ('crm'::regnamespace, 'private'::regnamespace)
     and p.oid::regprocedure::text not in ('crm.obtener_base_gestion(uuid,boolean)',
                                   'crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)',
                                   'crm.seguimiento_base(uuid)',
                                   'crm.seguimiento_base_detalle(uuid,uuid,text)',
                                   'crm.seguimiento_bases()',
                                   'private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)',
                                   'private.base_gestion_reactivar_core(uuid,uuid,uuid,text)',
                                   'private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamp with time zone,numeric,text)',
                                   'private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone)',
                                   'crm.registrar_intento_base_v2(uuid,uuid,text,text,timestamp with time zone,numeric,text)',
                                   'private.bases_carga_estado_contacto(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamp with time zone,timestamp with time zone,uuid,uuid[],date,boolean,boolean,boolean)',
                                   'private.bases_carga_reparto_motivo_bloque(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamp with time zone,timestamp with time zone,uuid,uuid[],date)',
                                   'private.bases_carga_contactos_core(uuid,uuid,text)',
                                   'private.bases_carga_reparto_recogible(uuid,uuid,timestamp with time zone,boolean)',
                                   'private.bases_carga_repartir_core(uuid,uuid,uuid,jsonb)',
                                   'crm.contactos_de_base(uuid,text)',
                                   'crm.recoger_de_base(uuid,uuid,uuid)',
                                   'crm.repartir_base(uuid,uuid,jsonb)',
                                   'private.bases_carga_seguimiento_cifras()',
                                   'private.bases_carga_seguimiento_exigir_base(uuid,text,uuid)',
                                   'private.bases_carga_seguimiento_filas(uuid[],date)',
                                   'private.bases_carga_seguimiento_rol(uuid)',
                                   'private.bases_carga_reparto_estado(boolean,boolean,text,uuid,boolean,date,uuid,boolean,boolean,boolean,boolean,date)');
create temp table _rb10_censo_antes on commit drop as select c.objeto from private.contadores_crudos_leads_citas() c;

-- ── Las puertas y los ayudantes de B10 ──
drop function crm.seguimiento_base_detalle(uuid, uuid, text);
drop function crm.seguimiento_base(uuid);
drop function crm.seguimiento_bases();
drop function crm.reactivar_lead_base_v2(uuid, uuid, text, numeric, text);
drop function crm.registrar_intento_base_v2(uuid, uuid, text, text, timestamptz, numeric, text);
drop function private.bases_carga_seguimiento_filas(uuid[], date);
drop function private.bases_carga_seguimiento_exigir_base(uuid, text, uuid);
drop function private.bases_carga_seguimiento_rol(uuid);
drop function private.bases_carga_seguimiento_cifras();

-- ── B9 r2 tal cual estaba: su clasificador (con dueño, ACL y comentario), las tres piezas de su núcleo y los comentarios
--    de sus tres puertas (sus cuerpos nunca cambiaron) ──
create function private.bases_carga_reparto_estado(p_activo boolean, p_no_contactar boolean, p_etapa text, p_vendedor_id uuid,
                                                   p_en_ambito boolean, p_enfriado_hasta date, p_analista_id uuid,
                                                   p_intento boolean, p_cita boolean, p_reactivado boolean, p_en_gestion boolean,
                                                   p_hoy date)
returns text
language sql
immutable
security invoker
set search_path = ''
as $function$
  -- UNA definición del estado de un contacto de la base (contrato B9), en este orden:
  --   no_contactar · movido_otra_via (retirado; repartido pero otro lo tiene; sin repartir fuera del ámbito del dueño; o salió
  --   del descarte por otra vía —E14—) · cita (salió del descarte con un intento «agendó cita») · reactivado (salió del
  --   descarte reactivado desde la base) · en_descanso · sin repartir: trabajado si alguien lo tiene en seguimiento activo
  --   (B6: no se puede repartir) o sin_repartir · repartido: trabajado (≥ 1 intento) o sin_tocar. Los hechos (intento, cita,
  --   reactivado) son los de private.bases_carga_reparto_hechos desde asignado_en o, sin repartir, desde que entró a la base.
  select case
           when p_no_contactar is not false then 'no_contactar'
           when p_activo is not true then 'movido_otra_via'
           when p_analista_id is not null and p_vendedor_id is distinct from p_analista_id then 'movido_otra_via'
           when p_analista_id is null and p_en_ambito is not true then 'movido_otra_via'
           when p_etapa is distinct from 'descartado' and p_cita is true then 'cita'
           when p_etapa is distinct from 'descartado' and p_reactivado is true then 'reactivado'
           when p_etapa is distinct from 'descartado' then 'movido_otra_via'
           when p_enfriado_hasta is not null and p_enfriado_hasta > p_hoy then 'en_descanso'
           when p_analista_id is null then case when p_en_gestion is true then 'trabajado' else 'sin_repartir' end
           when p_intento is true then 'trabajado'
           else 'sin_tocar'
         end;
$function$;
alter function private.bases_carga_reparto_estado(boolean, boolean, text, uuid, boolean, date, uuid, boolean, boolean, boolean, boolean, date) owner to postgres;
revoke all on function private.bases_carga_reparto_estado(boolean, boolean, text, uuid, boolean, date, uuid, boolean, boolean, boolean, boolean, date) from public, anon, authenticated, service_role;
comment on function private.bases_carga_reparto_estado(boolean, boolean, text, uuid, boolean, date, uuid, boolean, boolean, boolean, boolean, date) is 'Bases cargadas (B9): UNA definición del estado de un contacto de la base (contrato B9): no_contactar · movido_otra_via · cita · reactivado · en_descanso · sin_repartir/trabajado (sin repartir) · trabajado/sin_tocar (repartido, desde asignado_en). B10 puede reutilizarla para sus conteos.';
create or replace function private.bases_carga_contactos_core(p_actor uuid, p_base_id uuid, p_estado text)
returns table(lead_id uuid, nombre_completo text, telefono text, distrito text, agregado_en timestamptz, analista_id uuid,
              analista_nombre text, estado text)
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_rol text := private.bases_carga_reparto_rol(p_actor);
  v_filtro text := coalesce(p_estado, 'sin_repartir');
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_sup uuid;
  v_subarbol uuid[];
begin
  if p_base_id is null then
    raise exception 'La base es obligatoria' using errcode = '22023';
  end if;
  if (v_filtro in ('sin_repartir', 'repartidos', 'todos')) is not true then
    raise exception 'El filtro es sin_repartir, repartidos o todos' using errcode = '22023';
  end if;
  select b.supervisor_id into v_sup from crm.bases_carga b where b.id = p_base_id;
  if not found or not private.bases_carga_base_visible(p_actor, v_rol, v_sup) then
    raise exception 'Base no encontrada o fuera de tu ámbito' using errcode = 'P0002';
  end if;
  v_subarbol := array(select private.bases_carga_subarbol(v_sup));
  -- Solo contactos que el actor VE y siguen activos (private.bases_carga_lead_ref, la regla de B8 para toda referencia).
  return query
    select l.id, l.nombre_completo, l.telefono, l.distrito, bl.creado_en, bl.analista_id, p.nombre_completo,
           private.bases_carga_reparto_estado(l.activo, l.no_contactar, l.etapa, l.vendedor_id,
                                              private.bases_carga_en_subarbol(v_subarbol, l.vendedor_id, l.asignado_supervisor_id),
                                              l.enfriado_hasta, bl.analista_id, h.intento, h.cita, h.reactivado,
                                              bl.analista_id is null and private.base_gestion_en_gestion_hasta(l.id) is not null, v_hoy)
      from crm.base_carga_leads bl
      join crm.leads l on l.id = bl.lead_id
      left join public.perfiles p on p.id = bl.analista_id
      cross join lateral private.bases_carga_reparto_hechos(l.id, coalesce(bl.asignado_en, bl.creado_en)) h
     where bl.base_id = p_base_id and bl.activo
       and (v_filtro = 'todos' or (v_filtro = 'sin_repartir') = (bl.analista_id is null))
       and private.bases_carga_lead_ref(p_actor, v_rol, l.id)
     order by bl.creado_en, l.creado_en, l.id;
end;
$function$;
create or replace function private.bases_carga_reparto_recogible(p_lead_id uuid, p_analista_id uuid, p_asignado_en timestamptz, p_baja boolean)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $function$
  -- UNA definición de «se puede recoger» (la usan la foto y la revisión bajo candado de recoger): sigue vivo, descartado y en
  -- manos de ESE analista (lo movido por otra vía no se deshace, E14), sin intento desde que se le repartió —salvo que el
  -- analista esté de baja (r1, auditor P3): entonces manda B6, que la baja libera— y sin seguimiento activo B6. `is true`.
  select coalesce((select (l.activo and l.etapa = 'descartado' and l.vendedor_id = p_analista_id
                           and (p_baja is true or not h.intento)
                           and private.base_gestion_en_gestion_hasta(l.id) is null) is true
                     from crm.leads l
                     cross join lateral private.bases_carga_reparto_hechos(l.id, p_asignado_en) h
                    where l.id = p_lead_id), false);
$function$;
create or replace function private.bases_carga_repartir_core(p_actor uuid, p_operacion_id uuid, p_base_id uuid, p_reparto jsonb)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
declare
  v_rol text := private.bases_carga_reparto_rol(p_actor);
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_max integer;
  v_max_analistas integer;
  v_modo text;
  v_asig jsonb;
  v_n integer;
  v_tope integer;
  v_md5 text;
  v_prev jsonb;
  v_sup uuid;
  v_base crm.bases_carga%rowtype;
  v_subarbol uuid[];
  e record;
  c record;
  a_analista uuid[] := '{}';   -- bloque: los analistas en el orden pedido; individual: el analista de cada fila
  a_cantidad integer[] := '{}';
  a_lead uuid[] := '{}';
  a_ev_lead uuid[];
  a_ev_motivo text[];
  v_total integer := 0;
  v_bloqueados uuid[];
  v_elegibles uuid[] := '{}';
  v_pend uuid[];
  v_lote uuid[];
  v_marca bigint := 0;
  v_hasta bigint;
  v_falta integer;
  v_holgura integer;
  v_presupuesto integer;
  v_tomados integer := 0;
  v_examinados uuid[];
  v_disponibles integer;
  v_omitidos jsonb := '[]'::jsonb;
  v_rechazos jsonb := '[]'::jsonb;
  v_dest_lead uuid[] := '{}';
  v_dest_analista uuid[] := '{}';
  v_por_analista jsonb;
  v_pos integer := 0;
  v_motivo text;
  v_upd integer;
  v_ahora timestamptz;
  v_estado text;
  v_resp jsonb;
  i integer;
begin
  select k.max_contactos, k.max_analistas, k.holgura_candados into v_max, v_max_analistas, v_holgura from private.bases_carga_reparto_constantes() k;
  -- Candado y LUEGO evaluación: cada sentencia debe ver lo confirmado tras tomar los candados (como reactivar).
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'Repartir requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation')
      using errcode = '0A000';
  end if;
  if p_base_id is null then
    raise exception 'La base es obligatoria' using errcode = '22023';
  end if;
  -- 1 · FORMA (vale igual para una operación nueva y para su reintento).
  if p_reparto is null or pg_catalog.jsonb_typeof(p_reparto) is distinct from 'object'
     or pg_catalog.jsonb_typeof(p_reparto -> 'asignaciones') is distinct from 'array' then
    raise exception 'El reparto llega como {"modo": "bloque" o "individual", "asignaciones": [...]}' using errcode = '22023';
  end if;
  v_modo := p_reparto ->> 'modo';
  if (v_modo in ('bloque', 'individual')) is not true then
    raise exception 'El modo del reparto es «bloque» o «individual»' using errcode = '22023';
  end if;
  v_asig := p_reparto -> 'asignaciones';
  v_n := pg_catalog.jsonb_array_length(v_asig);
  v_tope := (case when v_modo = 'bloque' then v_max_analistas else v_max end);
  if v_n < 1 or v_n > v_tope then
    raise exception 'Un reparto en % trae entre 1 y % asignaciones (este trae %)', v_modo, v_tope, v_n using errcode = '22023';
  end if;
  for e in select x.valor, x.pos from pg_catalog.jsonb_array_elements(v_asig) with ordinality as x(valor, pos) order by x.pos loop
    if pg_catalog.jsonb_typeof(e.valor) is distinct from 'object'
       or ((e.valor ->> 'analista_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') is not true then
      raise exception 'La asignación % no trae un analista válido', e.pos using errcode = '22023';
    end if;
    if v_modo = 'bloque' then
      if pg_catalog.jsonb_typeof(e.valor -> 'cantidad') is distinct from 'number'
         or ((e.valor ->> 'cantidad') ~ '^[1-9][0-9]{0,5}$') is not true then
        raise exception 'La asignación % no trae una cantidad entera mayor que 0', e.pos using errcode = '22023';
      end if;
      if (e.valor ->> 'analista_id')::uuid = any (a_analista) then
        raise exception 'El analista de la asignación % se repite', e.pos using errcode = '22023';
      end if;
      a_analista := a_analista || (e.valor ->> 'analista_id')::uuid;
      a_cantidad := a_cantidad || (e.valor ->> 'cantidad')::integer;
      v_total := v_total + (e.valor ->> 'cantidad')::integer;
    else
      if ((e.valor ->> 'lead_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') is not true then
        raise exception 'La asignación % no trae un contacto válido', e.pos using errcode = '22023';
      end if;
      if (e.valor ->> 'lead_id')::uuid = any (a_lead) then
        raise exception 'El contacto de la asignación % se repite', e.pos using errcode = '22023';
      end if;
      a_lead := a_lead || (e.valor ->> 'lead_id')::uuid;
      a_analista := a_analista || (e.valor ->> 'analista_id')::uuid;
    end if;
  end loop;
  if v_modo = 'bloque' and v_total > v_max then
    raise exception 'Un reparto mueve hasta % contactos por operación (este pide %)', v_max, v_total using errcode = '22023';
  end if;
  if v_modo = 'individual' and pg_catalog.cardinality(array(select distinct x from pg_catalog.unnest(a_analista) x)) > v_max_analistas then
    raise exception 'Un reparto va a lo más a % analistas', v_max_analistas using errcode = '22023';
  end if;

  -- 2 · Idempotencia: el mismo pedido con el mismo id devuelve su recibo (B8: base aún visible); cada lead_id que el recibo
  -- nombra se vuelve a juzgar con el actor de hoy (si alguno ya no está a su alcance, no se repite: P0002).
  v_md5 := pg_catalog.md5(pg_catalog.jsonb_build_object('tipo', 'repartir', 'base_id', p_base_id, 'reparto', p_reparto)::text);
  v_prev := private.bases_carga_operacion_previa(p_actor, v_rol, p_operacion_id, 'repartir', v_md5);
  if v_prev is not null then
    if exists (select 1 from pg_catalog.jsonb_array_elements(coalesce(v_prev -> 'omitidos', '[]'::jsonb)) x
                where x ->> 'lead_id' is not null and not private.bases_carga_lead_ref(p_actor, v_rol, (x ->> 'lead_id')::uuid)) then
      raise exception 'La respuesta guardada nombra contactos que ya no están a tu alcance; repite la operación con otro identificador'
        using errcode = 'P0002';
    end if;
    return v_prev;
  end if;

  -- 3 · La base: visible (sin delatar si existe), su fila bloqueada NOWAIT, viva y con su supervisor dueño activo.
  select b.supervisor_id into v_sup from crm.bases_carga b where b.id = p_base_id;
  if not found or not private.bases_carga_base_visible(p_actor, v_rol, v_sup) then
    raise exception 'Base no encontrada o fuera de tu ámbito' using errcode = 'P0002';
  end if;
  begin
    select b.* into v_base from crm.bases_carga b where b.id = p_base_id for update nowait;
  exception when lock_not_available then
    raise exception 'Hay otra operación en curso de esta base; reintenta' using errcode = '55P03';
  end;
  if not v_base.activo then
    raise exception 'La base está retirada: no se reparte' using errcode = '22023';
  end if;
  if private.es_destino_crm_activo(v_base.supervisor_id, array['supervisor']::text[]) is not true then
    raise exception 'El supervisor dueño de la base ya no está activo: no se puede repartir' using errcode = '22023';
  end if;
  v_subarbol := array(select private.bases_carga_subarbol(v_base.supervisor_id));
  -- 4 · Los analistas (en el orden en que aparecen).
  for c in select u.a from pg_catalog.unnest(a_analista) with ordinality as u(a, pos) group by u.a order by min(u.pos) loop
    perform private.bases_carga_reparto_analista(v_rol, v_subarbol, c.a);
  end loop;

  if v_modo = 'bloque' then
    -- 5b · Foto SIN candados: los contactos sin repartir de la base, en el orden del reparto (los más antiguos en la base
    -- primero), con su motivo de hoy (private.bases_carga_reparto_motivo, una definición).
    select coalesce(pg_catalog.array_agg(q.lead_id order by q.orden), '{}'), coalesce(pg_catalog.array_agg(q.motivo order by q.orden), '{}')
      into a_ev_lead, a_ev_motivo
      from (select bl.lead_id,
                   pg_catalog.row_number() over (order by bl.creado_en, l.creado_en, l.id) as orden,
                   private.bases_carga_reparto_motivo(l.activo,
                                                      private.bases_carga_en_subarbol(v_subarbol, l.vendedor_id, l.asignado_supervisor_id),
                                                      l.etapa, l.no_contactar, l.enfriado_hasta,
                                                      private.base_gestion_en_gestion_hasta(l.id) is not null, v_hoy) as motivo
              from crm.base_carga_leads bl
              join crm.leads l on l.id = bl.lead_id
             where bl.base_id = p_base_id and bl.activo and bl.analista_id is null) q;
    v_pend := array(select x.l from unnest(a_ev_lead, a_ev_motivo) with ordinality as x(l, m, o) where x.m is null order by x.o);
    -- r1 (Codex P2): candado SOLO de lo necesario. Por tandas, en ese orden, solo los que faltan, FOR UPDATE SKIP LOCKED (lo que
    -- otro proceso tiene se salta sin esperar; nada fuera de lo pedido queda bloqueado). Bajo el candado, en otra sentencia (ve
    -- lo confirmado), se vuelve a juzgar cada uno con la MISMA definición y, además, que nadie le haya registrado un intento
    -- DURANTE esta operación: B6 cuenta desde la «reasignación», que lleva la hora de esta sentencia, y el analista nuevo lo
    -- heredaría. Lo que no pasa queda sin repartir y bloqueado hasta el commit: r2 (Codex P2) por eso hay un PRESUPUESTO de
    -- candados acumulado —todos los tomados, aceptados o no—: greatest(pedidos + holgura, ceil(pedidos × 1,1)); si se agota
    -- antes de completar, nada (55P03, reintenta: el todo o nada se mantiene).
    v_presupuesto := greatest(v_total + v_holgura, pg_catalog.ceil(v_total * 1.1)::integer);
    loop
      v_falta := v_total - pg_catalog.cardinality(v_elegibles);
      exit when v_falta <= 0;
      if v_tomados >= v_presupuesto then
        raise exception 'Los contactos están cambiando; reintenta' using errcode = '55P03';
      end if;
      select coalesce(pg_catalog.array_agg(b.id order by b.o), '{}'), max(b.o) into v_lote, v_hasta
        from (select l.id, p.o
                from crm.leads l
                join unnest(v_pend) with ordinality as p(id, o) on p.id = l.id
               where p.o > v_marca
               order by p.o
               limit least(v_falta, v_presupuesto - v_tomados)
                 for update of l skip locked) b;
      exit when v_hasta is null;
      v_marca := v_hasta;
      v_tomados := v_tomados + pg_catalog.cardinality(v_lote);
      v_elegibles := v_elegibles || array(
        select x.id from unnest(v_lote) with ordinality as x(id, o) join crm.leads l on l.id = x.id
         where private.bases_carga_reparto_motivo(l.activo,
                                                  private.bases_carga_en_subarbol(v_subarbol, l.vendedor_id, l.asignado_supervisor_id),
                                                  l.etapa, l.no_contactar, l.enfriado_hasta,
                                                  private.base_gestion_en_gestion_hasta(l.id) is not null, v_hoy) is null
           and not exists (select 1 from crm.actividades a
                            where a.lead_id = l.id and a.metadata ->> 'evento' = 'intento_base' and a.creado_en >= pg_catalog.statement_timestamp())
         order by x.o);
    end loop;
    v_disponibles := pg_catalog.cardinality(v_elegibles);
    if v_disponibles < v_total then
      raise exception 'Solo hay % contactos disponibles para repartir en esta base (pediste %)', v_disponibles, v_total
        using errcode = '22023', detail = v_disponibles::text;
    end if;
    -- Los más antiguos, en el orden de las asignaciones (Ana 40 · Luis 30: Ana recibe los 40 primeros).
    for i in 1 .. pg_catalog.cardinality(a_analista) loop
      v_dest_lead := v_dest_lead || v_elegibles[v_pos + 1 : v_pos + a_cantidad[i]];
      v_dest_analista := v_dest_analista || pg_catalog.array_fill(a_analista[i], array[a_cantidad[i]]);
      v_pos := v_pos + a_cantidad[i];
    end loop;
    -- Omitidos del bloque, por motivo (lead_id null y su cantidad): los sin repartir que la foto ya descartaba, con su motivo, y
    -- los examinados que no se eligieron, con su motivo de ahora o «ocupado» (otro proceso lo tenía; reintenta).
    v_examinados := array(select p.id from unnest(v_pend) with ordinality as p(id, o) where p.o <= v_marca and not (p.id = any (v_elegibles)));
    select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('lead_id', null, 'motivo', g.m, 'cantidad', g.n) order by g.m), '[]'::jsonb)
      into v_omitidos
      from (select y.m, pg_catalog.cardinality(pg_catalog.array_agg(y.l)) as n
              from (select x.l, x.m from unnest(a_ev_lead, a_ev_motivo) as x(l, m) where x.m is not null
                    union all
                    select l.id, coalesce(private.bases_carga_reparto_motivo(l.activo,
                                            private.bases_carga_en_subarbol(v_subarbol, l.vendedor_id, l.asignado_supervisor_id),
                                            l.etapa, l.no_contactar, l.enfriado_hasta,
                                            private.base_gestion_en_gestion_hasta(l.id) is not null, v_hoy), 'ocupado')
                      from crm.leads l where l.id = any (v_examinados)) y
             group by y.m) g;
    v_por_analista := (select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('analista_id', x.a, 'cantidad', x.n) order by x.o)
                         from unnest(a_analista, a_cantidad) with ordinality as x(a, n, o));
  else
    -- 5i · Todo o nada: (1) cada uno es de la base y el actor lo ve (si no, P0002 sin decir cuál existe) — r1 (auditor P3):
    -- ANTES de los candados, para no bloquear nada fuera de su alcance —; (2) candado de los pedidos, en orden de id, SKIP
    -- LOCKED; (3) bajo el candado siguen a su alcance (otra vía pudo llevárselos en el intervalo: P0002) y ninguno lo tiene otro
    -- proceso ni recibió un intento durante esta operación (55P03, reintenta); (4) cada uno se puede repartir a SU analista
    -- (22023 con los rechazados).
    if exists (select 1 from pg_catalog.unnest(a_lead) as u(id)
                where not exists (select 1 from crm.base_carga_leads bl where bl.base_id = p_base_id and bl.activo and bl.lead_id = u.id)
                   or not private.bases_carga_lead_ref(p_actor, v_rol, u.id)) then
      raise exception 'Hay contactos que no están en esta base o están fuera de tu ámbito' using errcode = 'P0002';
    end if;
    select coalesce(pg_catalog.array_agg(b.id order by b.id), '{}') into v_bloqueados
      from (select l.id from crm.leads l
             where l.id = any (a_lead)
               and l.id in (select bl.lead_id from crm.base_carga_leads bl where bl.base_id = p_base_id and bl.activo)
             order by l.id
               for update of l skip locked) b;
    if exists (select 1 from pg_catalog.unnest(a_lead) as u(id) where not private.bases_carga_lead_ref(p_actor, v_rol, u.id)) then
      raise exception 'Hay contactos que no están en esta base o están fuera de tu ámbito' using errcode = 'P0002';
    end if;
    if exists (select 1 from pg_catalog.unnest(a_lead) as u(id)
                where not (u.id = any (v_bloqueados))
                   or exists (select 1 from crm.actividades a
                               where a.lead_id = u.id and a.metadata ->> 'evento' = 'intento_base' and a.creado_en >= pg_catalog.statement_timestamp())) then
      raise exception 'Otra operación está usando alguno de esos contactos; reintenta' using errcode = '55P03';
    end if;
    for c in
      select u.lead_id, u.analista_id, bl.analista_id as bl_analista, l.activo, l.etapa, l.no_contactar, l.enfriado_hasta,
             l.vendedor_id, l.asignado_supervisor_id
        from unnest(a_lead, a_analista) with ordinality as u(lead_id, analista_id, pos)
        join crm.base_carga_leads bl on bl.base_id = p_base_id and bl.activo and bl.lead_id = u.lead_id
        join crm.leads l on l.id = u.lead_id
       order by u.pos
    loop
      -- El seguimiento activo (B6) solo cuenta si el contacto CAMBIA de analista (darlo al que ya lo tiene no reasigna).
      -- r1 (Codex P2): en el ámbito también lo que B9 repartió (Gerencia) fuera del equipo del dueño: la pertenencia dice que
      -- quien lo tiene es su analista. Lo que otra vía movió fuera del equipo, no.
      v_motivo := private.bases_carga_reparto_motivo(c.activo,
                                                     private.bases_carga_en_subarbol(v_subarbol, c.vendedor_id, c.asignado_supervisor_id)
                                                       or (c.bl_analista is not null and c.bl_analista = c.vendedor_id),
                                                     c.etapa, c.no_contactar, c.enfriado_hasta,
                                                     c.vendedor_id is distinct from c.analista_id
                                                       and private.base_gestion_en_gestion_hasta(c.lead_id) is not null, v_hoy);
      if v_motivo is not null then
        v_rechazos := v_rechazos || pg_catalog.jsonb_build_object('lead_id', c.lead_id, 'motivo', v_motivo);
      elsif c.bl_analista is not distinct from c.analista_id and c.vendedor_id is not distinct from c.analista_id then
        v_omitidos := v_omitidos || pg_catalog.jsonb_build_object('lead_id', c.lead_id, 'motivo', 'ya_asignado');
      else
        v_dest_lead := v_dest_lead || c.lead_id;
        v_dest_analista := v_dest_analista || c.analista_id;
      end if;
    end loop;
    if pg_catalog.jsonb_array_length(v_rechazos) > 0 then
      raise exception '% de los contactos pedidos no se pueden repartir (en gestión, en descanso, No contactar o fuera de la base); no se repartió ninguno',
        pg_catalog.jsonb_array_length(v_rechazos)
        using errcode = '22023', detail = pg_catalog.jsonb_build_object('rechazados', v_rechazos)::text;
    end if;
    v_por_analista := coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('analista_id', g.a, 'cantidad', g.n) order by g.o)
                                  from (select x.a, pg_catalog.cardinality(pg_catalog.array_agg(x.l)) as n, min(x.o) as o
                                          from unnest(v_dest_lead, v_dest_analista) with ordinality as x(l, a, o) group by x.a) g), '[]'::jsonb);
  end if;

  -- 6 · El reparto: el lead al analista (sigue descartado), por el camino de la casa (todos sus candados corren); y la
  -- pertenencia con su analista, cuándo (después de los candados) y quién.
  v_ahora := pg_catalog.clock_timestamp();
  begin
    update crm.leads l
       set vendedor_id = x.analista, asignado_supervisor_id = null
      from unnest(v_dest_lead, v_dest_analista) as x(lead, analista)
     where l.id = x.lead
       and (l.vendedor_id is distinct from x.analista or l.asignado_supervisor_id is not null);
    get diagnostics v_upd = row_count;
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate;
    if private.bases_carga_error_transitorio(v_estado) then
      raise exception using errcode = v_estado, message = pg_catalog.format('El reparto se interrumpió (%s); reintenta', v_estado);
    end if;
    raise exception using errcode = v_estado, message = pg_catalog.format('No se pudo repartir (%s); no se repartió ninguno', v_estado);
  end;
  update crm.base_carga_leads bl
     set analista_id = x.analista, asignado_en = v_ahora, asignado_por = p_actor
    from unnest(v_dest_lead, v_dest_analista) as x(lead, analista)
   where bl.base_id = p_base_id and bl.activo and bl.lead_id = x.lead;
  get diagnostics v_n = row_count;
  if v_n is distinct from pg_catalog.cardinality(v_dest_lead) then
    raise exception 'El reparto no quedó como se previó' using errcode = 'P0001';
  end if;

  v_resp := pg_catalog.jsonb_build_object('ok', true, 'operacion_id', p_operacion_id, 'base_id', p_base_id, 'modo', v_modo,
                                          'repartidos', pg_catalog.cardinality(v_dest_lead), 'por_analista', v_por_analista,
                                          'omitidos', v_omitidos);
  insert into crm.base_carga_operaciones (actor, operacion_id, base_id, tipo, pedido_md5, respuesta)
  values (p_actor, p_operacion_id, p_base_id, 'repartir', v_md5, v_resp);
  return v_resp;
end;
$function$;
comment on function private.bases_carga_contactos_core(uuid, uuid, text) is 'Bases cargadas (B9): núcleo de crm.contactos_de_base: base visible, solo contactos con private.bases_carga_lead_ref (visibles y activos), estado de private.bases_carga_reparto_estado.';
comment on function private.bases_carga_reparto_recogible(uuid, uuid, timestamptz, boolean) is 'Bases cargadas (B9 r1): UNA definición de «se puede recoger»: vivo, descartado y en manos de ese analista (lo movido por otra vía no se deshace, E14), sin intento desde que se le repartió (salvo analista de baja: manda B6, que la baja libera) y sin seguimiento activo B6. La usan la foto y la revisión bajo candado de recoger.';
comment on function private.bases_carga_repartir_core(uuid, uuid, uuid, jsonb) is 'Bases cargadas (B9; r1): núcleo de crm.repartir_base. Orden: forma → idempotencia (recibo repartir, replay que revalida referencias) → base (visible, FOR UPDATE NOWAIT, viva, dueño activo) → analistas → bloque: foto sin candados de los sin repartir con su motivo y candado SKIP LOCKED SOLO de los que faltan, por tandas y en el orden del reparto; individual: ámbito (P0002) ANTES del candado SKIP LOCKED de lo pedido → revisión bajo candado con la misma definición y sin intento durante la operación → UPDATE de crm.leads por el camino de la casa → pertenencia → recibo. Sin count( ni sum(1) (censo).';
comment on function crm.repartir_base(uuid, uuid, jsonb) is 'Bases cargadas (B9, 04/10/2026): reparte contactos de una base a analistas, TODO O NADA. p_reparto: {"modo":"bloque","asignaciones":[{"analista_id","cantidad"}]} (el servidor elige los SIN REPARTIR más antiguos en la base y salta los que no se pueden repartir: retirados, fuera del ámbito del dueño, que salieron del descarte, No contactar, en descanso, en gestión B6 u ocupados; si no alcanzan → 22023 con detail = disponibles, el número en texto) o {"modo":"individual","asignaciones":[{"lead_id","analista_id"}]} (cada contacto de la base, visible para el actor —si no, P0002—, sin repartir o repartido a otro —se reasigna— y elegible; si no → 22023 con detail {"rechazados":[{lead_id, motivo}]}; tomado por otro proceso → 55P03; el que ya es de ese analista sale en omitidos como ya_asignado). Analista activo, rol vendedor, del subárbol del supervisor DUEÑO (Gerencia: cualquiera, y puede volver a repartir lo que B9 le dio a alguien fuera del equipo del dueño; fuera del equipo → P0002, inactivo o no analista → 22023). Bloquea solo lo necesario (r1). Efecto: crm.leads.vendedor_id = analista (sigue descartado; sin ciclo SLA ni episodio; la actividad «reasignación» y el candado B6 corren solos) y base_carga_leads.analista_id/asignado_en/asignado_por. Topes en private.bases_carga_reparto_constantes. Idempotente por (actor, p_operacion_id). Devuelve {ok, operacion_id, base_id, modo, repartidos, por_analista[{analista_id, cantidad}], omitidos[{lead_id|null, motivo, cantidad?}]} (en bloque, por motivo con lead_id null). Supervisión y Gerencia (otros → 42501); otra operación de la base en curso → 55P03. DEFINER, search_path vacío, lock_timeout 5 s, EXECUTE solo authenticated.';
comment on function crm.recoger_de_base(uuid, uuid, uuid) is 'Bases cargadas (B9, 04/10/2026; r1): devuelve a «sin repartir» (bandeja del supervisor dueño de la base) los contactos que ese analista tiene de la base SIN intento desde que se le repartieron (de un analista de baja no se exige: manda B6, que la baja libera), sin seguimiento activo (B6) y que siguen descartados y en sus manos (lo movido por otra vía no se deshace, E14); los tomados por otro proceso quedan. Supervisión: analistas de su equipo (activos o no); Gerencia: cualquiera. Tope por operación (private.bases_carga_reparto_constantes): lo que excede queda en pendientes. Idempotente por (actor, p_operacion_id). Devuelve {ok, operacion_id, base_id, analista_id, recogidos, omitidos, pendientes}. DEFINER, search_path vacío, lock_timeout 5 s, EXECUTE solo authenticated.';
comment on function crm.contactos_de_base(uuid, text) is 'Bases cargadas (B9, 04/10/2026): los contactos de una base visible para el actor (Supervisión: su subárbol; Gerencia: todas; si no, P0002; otros roles → 42501), para el reparto individual y la pestaña «Bases». p_estado: sin_repartir (por defecto) | repartidos | todos. Solo contactos que el actor ve y siguen activos (nada fuera de su ámbito). Lleva nombre, teléfono y distrito: la pantalla los usa para marcar filas en el reparto individual (el actor ya los ve en su Base para gestión). estado ∈ sin_repartir · sin_tocar · trabajado · en_descanso · cita · reactivado · movido_otra_via · no_contactar (private.bases_carga_reparto_estado). Orden: el del reparto en bloque (más antiguos en la base primero). DEFINER, search_path vacío, EXECUTE solo authenticated.';

-- ── Los núcleos de siempre con su texto de B3c (misma firma: CREATE OR REPLACE conserva dueño y ACL); después, sin
--    llamadores, se borran los núcleos con capital ──
create or replace function private.base_gestion_reactivar_core(p_actor uuid, p_operacion_id uuid, p_lead_id uuid, p_nota text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_rol text;
  v_lead crm.leads%rowtype;
  v_prev jsonb;
  v_n integer;
  v_guc text;
  v_resp jsonb;
  v_reabrir jsonb;
begin
  if p_actor is null or p_operacion_id is null or p_lead_id is null then
    raise exception 'Operacion, lead y actor son obligatorios' using errcode = '22023';
  end if;
  v_rol := private.base_gestion_rol(p_actor);
  if length(coalesce(p_nota, '')) > 2000 then
    raise exception 'La nota supera los 2000 caracteres' using errcode = '22023';
  end if;
  -- Candados de la casa: persona ANTES que lead (como llamada_registrar y marcar_no_contactar); reabrir_lead_fn los
  -- vuelve a tomar dentro de la misma transaccion sin esperar.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'Reactivar requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  perform private.bloquear_personas_de_leads(array[p_lead_id], null);
  select * into v_lead from crm.leads where id = p_lead_id for update;
  -- Idempotencia DESPUES del candado del lead: dos clics concurrentes → el segundo espera y recibe el replay.
  select a.metadata->'respuesta' into v_prev from crm.actividades a where a.id = p_operacion_id and a.creado_por = p_actor;
  if found then
    if v_prev is null or (v_prev->>'lead_id')::uuid is distinct from p_lead_id or v_prev->>'evento' is distinct from 'reactivacion_base' then
      raise exception 'Esta operacion ya corresponde a otro contenido' using errcode = '23505';
    end if;
    return v_prev || jsonb_build_object('replay', true);
  end if;
  if v_lead.id is null or not v_lead.activo
     or not private.base_gestion_lead_visible(p_actor, v_rol, v_lead.vendedor_id, v_lead.asignado_supervisor_id) then
    raise exception 'Lead no encontrado o fuera de tu ambito' using errcode = 'P0002';
  end if;
  if v_lead.etapa <> 'descartado' then
    raise exception 'El lead ya no esta en la base (no esta descartado)' using errcode = '22023';
  end if;
  if v_lead.no_contactar then
    raise exception 'No insistir: el lead esta marcado No contactar' using errcode = 'P0429';
  end if;
  -- 1. Reabrir por la puerta sellada (→ nuevo, ciclo nuevo, SLA reiniciado, veto de persona verificado).
  v_reabrir := crm.reabrir_lead_fn(p_lead_id);
  -- 2. En la misma transaccion, a «contactado» (D1): el guard de tenencia lo permite porque ya old.etapa = nuevo.
  update crm.leads set etapa = 'contactado' where id = p_lead_id and activo and etapa = 'nuevo';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'No se pudo avanzar el lead reabierto a contactado' using errcode = 'P0001';
  end if;
  -- 3. Sello de la base: marca de reactivacion, sin rellamada ni descanso.
  v_guc := coalesce(pg_catalog.current_setting('crm.op_base_gestion', true), 'off');
  perform pg_catalog.set_config('crm.op_base_gestion', 'on', true);
  update crm.leads set reactivado_en = now(), proxima_llamada_en = null, enfriado_hasta = null where id = p_lead_id;
  perform pg_catalog.set_config('crm.op_base_gestion', v_guc, true);
  select * into v_lead from crm.leads where id = p_lead_id;
  v_resp := jsonb_build_object('ok', true, 'evento', 'reactivacion_base', 'lead_id', p_lead_id, 'etapa', v_lead.etapa,
                               'reactivado_en', v_lead.reactivado_en, 'ciclo_n', v_lead.ciclo_actual,
                               'reabierto_por', v_reabrir->>'reabierto_por', 'replay', false);
  -- 4. Historial (D9): la linea de la reactivacion, con la respuesta para la idempotencia, bajo el sello de actividades.
  perform pg_catalog.set_config('crm.op_base_gestion', 'on', true);
  insert into crm.actividades (id, lead_id, tipo, detalle, metadata, creado_por)
  values (p_operacion_id, p_lead_id, 'nota', coalesce(nullif(pg_catalog.btrim(p_nota), ''), 'Reactivado desde la base para gestión'),
          jsonb_build_object('evento', 'reactivacion_base', 'via', 'base_gestion', 'etapa', 'contactado',
                             'ciclo_n', v_lead.ciclo_actual, 'respuesta', v_resp),
          p_actor);
  perform pg_catalog.set_config('crm.op_base_gestion', v_guc, true);
  return v_resp;
end;
$function$;
revoke all on function private.base_gestion_reactivar_core(uuid, uuid, uuid, text) from public, anon, authenticated, service_role;
comment on function private.base_gestion_reactivar_core(uuid, uuid, uuid, text) is 'Base para gestión (B3, D1/D2/D9): reabre por crm.reabrir_lead_fn (sellada; → nuevo, ciclo nuevo, SLA reiniciado, veto verificado), avanza a contactado en la misma transacción, sella reactivado_en y limpia rellamada y descanso; deja la actividad reactivacion_base con la respuesta (idempotencia por id = operación). Solo la llama la puerta crm.reactivar_lead_base.';
create or replace function private.base_gestion_intento_core(p_actor uuid, p_operacion_id uuid, p_lead_id uuid, p_resultado text, p_nota text, p_proxima timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_rol text;
  v_c record;
  v_lead crm.leads%rowtype;
  v_prev jsonb;
  v_n integer;
  v_tipo text;
  v_guc1 text;
  v_guc2 text;
  v_meta jsonb;
  v_resp jsonb;
  v_react jsonb;
  v_hoy date := (now() at time zone 'America/Lima')::date;
begin
  if p_actor is null or p_operacion_id is null or p_lead_id is null then
    raise exception 'Operacion, lead y actor son obligatorios' using errcode = '22023';
  end if;
  v_rol := private.base_gestion_rol(p_actor);
  if p_resultado is null or p_resultado not in ('no_contesto', 'volver_a_llamar', 'agendo_reunion', 'no_interesado',
                                                'numero_errado', 'no_es_la_persona', 'pide_otro_producto') then
    raise exception 'Resultado de llamada invalido' using errcode = '22023';
  end if;
  select * into v_c from private.base_gestion_constantes();
  -- Validaciones de FORMA (valen igual para una operacion nueva y para su reintento).
  if p_resultado = 'volver_a_llamar' and p_proxima is null then
    raise exception 'Indica cuando volver a llamar' using errcode = '22023';
  elsif p_resultado <> 'volver_a_llamar' and p_proxima is not null then
    raise exception 'Solo "volver a llamar" lleva fecha de rellamada' using errcode = '22023';
  end if;
  if length(coalesce(p_nota, '')) > 2000 then
    raise exception 'La nota supera los 2000 caracteres' using errcode = '22023';
  end if;
  -- «agendó cita» reactivara: candados de persona ANTES del lead (protocolo de la casa).
  if p_resultado = 'agendo_reunion' then
    if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
      raise exception 'Agendar cita desde la base requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
    end if;
    perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
    perform private.bloquear_personas_de_leads(array[p_lead_id], null);
  end if;
  select * into v_lead from crm.leads where id = p_lead_id for update;
  -- Idempotencia DESPUES del candado del lead, solo entre operaciones del mismo actor y ANTES de las validaciones
  -- temporales (Codex B3 #1: el reintento de una rellamada ya vencida debe seguir devolviendo su respuesta). La identidad
  -- de la operacion incluye lead, resultado, fecha de rellamada y nota (Codex B3 #2).
  select a.metadata->'respuesta' into v_prev from crm.actividades a where a.id = p_operacion_id and a.creado_por = p_actor;
  if found then
    if v_prev is null or (v_prev->>'lead_id')::uuid is distinct from p_lead_id or v_prev->>'resultado' is distinct from p_resultado
       or v_prev->>'evento' is distinct from 'intento_base'
       or (v_prev->>'solicitud_proxima')::timestamptz is distinct from p_proxima
       or v_prev->>'nota_md5' is distinct from md5(coalesce(pg_catalog.btrim(p_nota), '')) then
      raise exception 'Esta operacion ya corresponde a otro contenido' using errcode = '23505';
    end if;
    return v_prev || jsonb_build_object('replay', true);
  end if;
  -- Validaciones TEMPORALES: solo para una operacion nueva.
  if p_resultado = 'volver_a_llamar' then
    if p_proxima <= now() then
      raise exception 'La rellamada debe ser futura' using errcode = '22023';
    end if;
    if p_proxima > now() + make_interval(days => v_c.dias_max_rellamada) then
      raise exception 'La rellamada se agenda como maximo % dias adelante', v_c.dias_max_rellamada using errcode = '22023';
    end if;
  end if;
  if v_lead.id is null or not v_lead.activo
     or not private.base_gestion_lead_visible(p_actor, v_rol, v_lead.vendedor_id, v_lead.asignado_supervisor_id) then
    raise exception 'Lead no encontrado o fuera de tu ambito' using errcode = 'P0002';
  end if;
  if v_lead.etapa <> 'descartado' then
    raise exception 'El lead no esta en la base (no esta descartado)' using errcode = '22023';
  end if;
  if v_lead.no_contactar then
    raise exception 'No insistir: el lead esta marcado No contactar' using errcode = 'P0429';
  end if;
  if v_lead.enfriado_hasta is not null and v_lead.enfriado_hasta > v_hoy then
    raise exception 'El lead esta en descanso hasta el %', to_char(v_lead.enfriado_hasta, 'DD/MM/YYYY') using errcode = '22023';
  end if;
  -- B3c: los intentos del ciclo se cuentan en private.base_gestion_intentos_ciclo (una sola definición, misma ventana D13).
  v_n := coalesce((select c.n from private.base_gestion_intentos_ciclo(array[p_lead_id], array[private.base_gestion_intentos_desde(v_lead.descartado_en, v_lead.creado_en, v_lead.enfriado_hasta, v_hoy)]) c), 0) + 1;  -- D13
  v_tipo := case when p_resultado in ('no_contesto', 'numero_errado', 'no_es_la_persona')
                 then 'llamada_no_contestada' else 'llamada_realizada' end;
  v_meta := jsonb_strip_nulls(jsonb_build_object(
    'evento', 'intento_base', 'via', 'base_gestion', 'resultado', p_resultado, 'intento_n', v_n,
    'ciclo_n', v_lead.ciclo_actual, 'proxima_llamada_en', p_proxima));  -- to_jsonb(timestamptz): ISO con zona, nunca ::text
  v_guc1 := coalesce(pg_catalog.current_setting('crm.op_resultado_llamada', true), 'off');
  v_guc2 := coalesce(pg_catalog.current_setting('crm.op_base_gestion', true), 'off');
  perform pg_catalog.set_config('crm.op_resultado_llamada', 'on', true);
  perform pg_catalog.set_config('crm.op_base_gestion', 'on', true);
  insert into crm.actividades (id, lead_id, tipo, detalle, metadata, creado_por)
  values (p_operacion_id, p_lead_id, v_tipo, nullif(pg_catalog.btrim(p_nota), ''), v_meta, p_actor);
  update crm.leads set proxima_llamada_en = case when p_resultado = 'volver_a_llamar' then p_proxima else null end
   where id = p_lead_id
     and proxima_llamada_en is distinct from case when p_resultado = 'volver_a_llamar' then p_proxima else null end;
  perform pg_catalog.set_config('crm.op_resultado_llamada', v_guc1, true);
  perform pg_catalog.set_config('crm.op_base_gestion', v_guc2, true);
  -- «agendó cita» reactiva en la misma transaccion (D3); la cita se agenda despues por el flujo normal del lead vivo.
  if p_resultado = 'agendo_reunion' then
    -- Codex B3 #3: la operacion hija lleva un uuid NUEVO (no derivable del padre) y no puede ser un replay ajeno; la
    -- idempotencia del conjunto la da la operacion padre.
    v_react := private.base_gestion_reactivar_core(p_actor, gen_random_uuid(), p_lead_id, 'Agendó cita desde la base para gestión');
    if coalesce((v_react->>'replay')::boolean, false) or v_react->>'etapa' is distinct from 'contactado' then
      raise exception 'La reactivacion de "agendo cita" no se completo' using errcode = 'P0001';
    end if;
  end if;
  select * into v_lead from crm.leads where id = p_lead_id;  -- tras el trigger de enfriamiento (B4) y la reactivacion
  v_resp := jsonb_build_object('ok', true, 'evento', 'intento_base', 'lead_id', p_lead_id, 'actividad_id', p_operacion_id,
                               'resultado', p_resultado, 'intento_n', v_n, 'ciclo_n', v_meta->>'ciclo_n',
                               'proxima_llamada_en', v_lead.proxima_llamada_en, 'enfriado_hasta', v_lead.enfriado_hasta,
                               'reactivado', v_react is not null, 'etapa', v_lead.etapa, 'replay', false,
                               'solicitud_proxima', p_proxima, 'nota_md5', md5(coalesce(pg_catalog.btrim(p_nota), '')));
  perform pg_catalog.set_config('crm.op_resultado_llamada', 'on', true);
  perform pg_catalog.set_config('crm.op_base_gestion', 'on', true);
  update crm.actividades set metadata = metadata || jsonb_build_object('respuesta', v_resp) where id = p_operacion_id;
  perform pg_catalog.set_config('crm.op_resultado_llamada', v_guc1, true);
  perform pg_catalog.set_config('crm.op_base_gestion', v_guc2, true);
  return v_resp;
end;
$function$;
revoke all on function private.base_gestion_intento_core(uuid, uuid, uuid, text, text, timestamptz) from public, anon, authenticated, service_role;
comment on function private.base_gestion_intento_core(uuid, uuid, uuid, text, text, timestamptz) is 'Base para gestión (B3, D3/D7-bis/D10/D11): registra un intento sobre un lead descartado del ámbito del actor (7 resultados; volver_a_llamar exige fecha futura ≤ dias_max_rellamada; descanso vigente y No contactar rechazan), escribe la actividad intento_base bajo los dos GUC, fija o limpia proxima_llamada_en y, con agendo_reunion, reactiva en la misma transacción. Idempotente por id = operación (guarda la respuesta). El enfriamiento lo pone el trigger de B4. Solo la llama la puerta crm.registrar_intento_base. B3c (03/10/2026): sus conteos de intentos salen de private.base_gestion_intentos_ciclo; fuera del censo analítico.';
drop function private.base_gestion_intento_capital_core(uuid, uuid, uuid, text, text, timestamptz, numeric, text);
drop function private.base_gestion_reactivar_capital_core(uuid, uuid, uuid, text, numeric, text);

-- ── La lista de B6b ──
drop function crm.obtener_base_gestion(uuid, boolean);
create function crm.obtener_base_gestion(p_vendedor_id uuid DEFAULT NULL::uuid, p_incluir_vetados boolean DEFAULT false)
 RETURNS TABLE(lead_id uuid, nombre_completo text, telefono text, distrito text, origen text, categoria_interes text, monto_estimado numeric, moneda text, motivo_descarte text, descartado_en timestamp with time zone, dias_desde_descarte integer, etapa_maxima text, intentos integer, ultimo_resultado text, ultimo_intento_en timestamp with time zone, proxima_llamada_en timestamp with time zone, rellamada_hoy boolean, enfriado_hasta date, ciclo_n integer, vendedor_id uuid, gestiona text, recibido_en timestamp with time zone, no_contactar boolean, no_contactar_en timestamp with time zone, no_contactar_motivo text, no_contactar_por text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_vetados boolean := coalesce(p_incluir_vetados, false);  -- B6b: null = false
begin
  v_rol := private.base_gestion_rol(v_uid);
  -- B6b (Miguel, 03/10/2026): los leads «No contactar» solo los ven Supervisión y Gerencia, y solo si los piden.
  if v_vetados and (v_rol in ('supervisor', 'gerencia')) is not true then
    raise exception 'Solo Supervision y Gerencia ven los leads marcados No contactar' using errcode = '42501';
  end if;
  if p_vendedor_id is not null then
    if v_rol = 'vendedor' and p_vendedor_id <> v_uid then
      raise exception 'Un analista solo consulta su propia base' using errcode = '42501';
    end if;
    if v_rol = 'supervisor' and p_vendedor_id not in (select private.vendedor_ids_visibles(v_uid)) then
      raise exception 'Analista no encontrado o fuera de tu ambito' using errcode = 'P0002';
    end if;
  end if;
  return query
  with base as (
    select l.id, l.nombre_completo, l.telefono, l.distrito, l.origen, l.categoria_interes, l.monto_estimado, l.moneda,
           l.motivo_descarte, l.descartado_en, l.proxima_llamada_en, l.enfriado_hasta, l.ciclo_actual, l.vendedor_id,
           coalesce(l.tenencia_desde, l.creado_en) as recibido_en,  -- B5: cuando le llego el lead a quien lo tiene (el MES del lead)
           l.no_contactar,  -- B6b: solo puede venir en true si se pidieron los vetados
           l.inversionista_id, l.dni,  -- B6b: para resolver la persona del lead (no se devuelven)
           private.base_gestion_intentos_desde(l.descartado_en, l.creado_en, l.enfriado_hasta, v_hoy) as desde  -- D13: ventana desde el descarte o desde el fin del ultimo descanso
    from crm.leads l
    where l.activo and l.etapa = 'descartado' and (not l.no_contactar or v_vetados)  -- B6b: los vetados, solo a pedido
      and (l.enfriado_hasta is null or l.enfriado_hasta <= v_hoy or (v_vetados and l.no_contactar))  -- B6b: un vetado en descanso tambien se ve; un no vetado en descanso, no
      and private.base_gestion_lead_visible(v_uid, v_rol, l.vendedor_id, l.asignado_supervisor_id)
      and (p_vendedor_id is null or l.vendedor_id = p_vendedor_id)
  ),
  intentos as (
    -- B3c: contador, último resultado (desempate por intento_n, Codex B3 #5) y último intento salen de la MISMA definición
    -- que usan el núcleo y el enfriamiento: private.base_gestion_intentos_ciclo, con la ventana D13 de cada lead.
    select c.lead_id, c.n, c.ultimo, c.ultimo_en
    from (select array_agg(b.id order by b.id) as ids, array_agg(b.desde order by b.id) as desdes from base b) q
    cross join lateral private.base_gestion_intentos_ciclo(q.ids, q.desdes) c
  ),
  ciclo as (
    -- El ciclo vigente empieza en la ultima reapertura (cambio_etapa descartado → nuevo) o, si nunca hubo, al inicio.
    -- Se acota con el propio historial (misma fuente y mismo reloj que los cambios de etapa): robusto frente a
    -- transacciones multi-sentencia, donde now() del log y statement_timestamp() del ledger difieren.
    select b.id as lead_id,
           coalesce((select max(a.creado_en) from crm.actividades a
                      where a.lead_id = b.id and a.tipo = 'cambio_etapa' and a.metadata->>'etapa_anterior' = 'descartado'),
                    '-infinity'::timestamptz) as desde
    from base b
  ),
  etapas as (
    select a.lead_id,
           max(greatest(private.base_gestion_etapa_rango(a.metadata->>'etapa_anterior'),
                        private.base_gestion_etapa_rango(case when a.metadata->>'etapa_nueva' <> 'descartado' then a.metadata->>'etapa_nueva' end))) as rango
    from crm.actividades a join ciclo c on c.lead_id = a.lead_id
    where a.tipo = 'cambio_etapa' and a.creado_en >= c.desde
      -- Codex B3 #6: el descarte del ciclo anterior puede compartir instante con la reapertura (misma transaccion): fuera.
      and not (a.creado_en = c.desde and a.metadata->>'etapa_nueva' = 'descartado')
    group by a.lead_id
  ),
  marca as (
    -- B6b: cuándo, por qué y quién marcó «No contactar». Evento vigente del veto: si el lead tiene persona y la persona está
    -- vetada, la ÚLTIMA nota del veto entre TODOS los leads de la persona (los que marcar/levantar/postventa actualizan); si
    -- no, la última nota del propio lead. Se muestra solo si ese evento es un «marcar» y su lead es visible para quien llama.
    select b.id as lead_id, ev.creado_en, ev.motivo, ev.creado_por
    from base b
    cross join lateral (
      -- La persona, EXACTAMENTE como la resuelven marcar/levantar: enlace; si no, puente (canónica); si no, DNI.
      select coalesce(b.inversionista_id,
                      (select private.inversionista_canonica(il.inversionista_id) from crm.inversionista_leads il
                        where il.lead_id = b.id order by (il.rol = 'canonico') desc, il.inversionista_id limit 1),
                      private.inversionista_por_documento('DNI', b.dni)) as id
    ) pe
    left join crm.inversionistas i on i.id = pe.id
    cross join lateral (
      -- La más reciente entre las ÚLTIMAS notas de cada lead del conjunto: cada una sale del índice (lead_id, creado_en desc).
      select n.ev_lead, n.creado_en, n.accion, n.creado_por, n.motivo
        from (select b.id as lid
              union
              select x from private.leads_de_persona_veto(pe.id) x where i.no_contactar is true) s  -- el conjunto de las puertas
        cross join lateral (
          select a.lead_id as ev_lead, a.creado_en, a.id, a.metadata->>'accion' as accion, a.creado_por,
                 coalesce(a.metadata->>'motivo',
                          case when a.metadata ? 'postventa_gestion_id' then pg_catalog.regexp_replace(a.detalle, '^No contactar: ', '') end) as motivo
            from crm.actividades a
           where a.lead_id = s.lid and a.metadata->>'evento' = 'no_contactar'
           order by a.creado_en desc, a.id desc
           limit 1
        ) n
       order by n.creado_en desc, n.id desc
       limit 1
    ) ev
    join crm.leads le on le.id = ev.ev_lead
    where b.no_contactar and ev.accion = 'marcar'
      and le.activo and private.base_gestion_lead_visible(v_uid, v_rol, le.vendedor_id, le.asignado_supervisor_id)  -- nada de otro equipo
  )
  select b.id, b.nombre_completo, b.telefono, b.distrito, b.origen, b.categoria_interes, b.monto_estimado, b.moneda,
         b.motivo_descarte, b.descartado_en,
         case when b.descartado_en is null then null else (v_hoy - (b.descartado_en at time zone 'America/Lima')::date)::integer end,
         case coalesce(e.rango, 0) when 1 then 'nuevo' when 2 then 'contactado' when 3 then 'reunion_agendada'
                                   when 4 then 'propuesta_enviada' when 5 then 'convertido' else 'sin_datos' end,
         coalesce(i.n, 0), i.ultimo, i.ultimo_en,
         b.proxima_llamada_en,
         (not b.no_contactar and b.proxima_llamada_en is not null and (b.proxima_llamada_en at time zone 'America/Lima')::date <= v_hoy),  -- B6b: un vetado nunca va a «Llamar hoy»
         b.enfriado_hasta, b.ciclo_actual, b.vendedor_id, p.nombre_completo, b.recibido_en,
         b.no_contactar, m.creado_en, m.motivo, pm.nombre_completo
  from base b
  left join intentos i on i.lead_id = b.id
  left join etapas e on e.lead_id = b.id
  left join public.perfiles p on p.id = b.vendedor_id
  left join marca m on m.lead_id = b.id
  left join public.perfiles pm on pm.id = m.creado_por
  -- Contrato (encargo): rellamada vencida o de hoy → etapa maxima (desc) → dias desde el descarte (asc); la hora de la
  -- rellamada solo desempata (Codex B3 #4). B6b: los vetados, al final (sin vetados el orden es el de B5).
  order by b.no_contactar,
           (not b.no_contactar and b.proxima_llamada_en is not null and (b.proxima_llamada_en at time zone 'America/Lima')::date <= v_hoy) desc,
           coalesce(e.rango, 0) desc,
           (b.descartado_en at time zone 'America/Lima')::date desc nulls last,  -- menos dias desde el descarte primero
           b.proxima_llamada_en asc nulls last,
           b.id;
end;
$function$;
alter function crm.obtener_base_gestion(uuid, boolean) owner to postgres;
revoke all on function crm.obtener_base_gestion(uuid, boolean) from public, anon, authenticated, service_role;
grant execute on function crm.obtener_base_gestion(uuid, boolean) to authenticated;
comment on function crm.obtener_base_gestion(uuid, boolean) is 'Base para gestión (B3): leads descartados vivos del ámbito del actor (analista → los suyos; Supervisión → subárbol; Gerencia → todo), sin «no contactar» ni descanso vigente (salvo p_incluir_vetados, ver B6b), con intentos del ciclo, último resultado, próxima rellamada, etapa máxima alcanzada y quién gestiona. Orden: rellamada vencida o de hoy → etapa máxima → menos días desde el descarte. p_vendedor_id filtra un analista dentro del ámbito. DEFINER: ámbito explícito (espejo de leads_select), search_path vacío, EXECUTE solo authenticated. B3c (03/10/2026): sus conteos de intentos salen de private.base_gestion_intentos_ciclo; fuera del censo analítico. B5 (03/10/2026): devuelve al final recibido_en = coalesce(tenencia_desde, creado_en), cuándo le llegó el lead a quien lo tiene: el MES por el que se organiza el analista. B6b (03/10/2026, F4): p_incluir_vetados (default false; null = false) suma los leads «No contactar» del ámbito, también los que están en descanso; solo Supervisión y Gerencia (otro rol → 42501). Los vetados van al final y nunca en «Llamar hoy» (rellamada_hoy = false). Columnas finales no_contactar, no_contactar_en, no_contactar_motivo y no_contactar_por (nombre del autor): de la nota del evento vigente del veto — si la persona del lead (enlace, puente o DNI, como en marcar/levantar) está vetada, la última nota del veto entre los leads de la persona (private.leads_de_persona_veto ∪ el propio lead); si no, la del propio lead — solo si es un «marcar» (también el de postventa, motivo en el detalle) y su lead es visible para quien llama; si no, NULL. Residuo: empate exacto de clock_timestamp, desempate por id. B6c (04/10/2026, decisión de Miguel): la nota del veto (metadata evento = no_contactar) solo la escriben sus puertas (marcar_no_contactar, levantar_no_contactar y postventa_veto_fn, bajo crm.op_privilegiada; trigger trg_00_actividades_no_contactar_solo_puerta en crm.actividades): desde la API ya no se puede firmar el motivo, el autor ni la fecha de la marca, y la nota ya escrita no se cambia ni se borra. No acredita las notas anteriores a B6c (04/10/2026). Residuo (auditor-rls B6b, P3): esta función no lee la bandera resolver_en_puertas (encendida desde el 07/09/2026) y resuelve siempre la persona como las puertas con la bandera encendida; si se apagara, las puertas actuarían solo sobre el lead y la marca de un lead cuya persona siga vetada podría salir NULL o venir de otro lead de la persona (nunca de uno fuera del ámbito de quien llama). Con false, el resultado es el de B5. Envoltorios DEFINER en la base: crm.base_gestion_resumen y crm.base_gestion_resumen_detalle (re-auditarlos si cambia leads_select).';
-- Sin llamadores ya (B9 repuesta, la lista de B6b repuesta, el seguimiento borrado): la definición única y el motivo del bloque.
drop function private.bases_carga_reparto_motivo_bloque(uuid, boolean, boolean, text, uuid, uuid, date, uuid, timestamptz, timestamptz, uuid, uuid[], date);
drop function private.bases_carga_estado_contacto(uuid, boolean, boolean, text, uuid, uuid, date, uuid, timestamptz, timestamptz, uuid, uuid[], date, boolean, boolean, boolean);

do $post$
begin
  if (
    -- Lo repuesto, con la identidad de antes de B10 (las del preflight de B10).
    (select md5(p.prosrc) = '36af7e9cc4d6ec319b3d8004f3903473'
            and md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '889f42a55ad100335b11a3e6bef4967c'
            and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
            and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = '67f83881ece789fee1a37e0799123c18'
       from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid,boolean)'))
    and (select md5(p.prosrc) = 'c7e19f14bfb29811dcf3b46e533329ef'
            and md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = 'b4afaf414e4c755e80c14e27d584f840'
            and p.proacl::text = '{postgres=X/postgres}'
            and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = '2d01d61e55440923a0a4efa876265c7e'
       from pg_proc p where p.oid = to_regprocedure('private.base_gestion_reactivar_core(uuid,uuid,uuid,text)'))
    and (select md5(p.prosrc) = 'db8ba2b4df43c84438f216924f20e73d'
            and md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '727c4c0629aae25b0d701bdac8a41bb5'
            and p.proacl::text = '{postgres=X/postgres}'
            and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = '2bd000b154679af92d052194304f55fa'
       from pg_proc p where p.oid = to_regprocedure('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone)'))
    -- B9 r2, byte a byte: cuerpo, identidad, ACL y comentario (las huellas del preflight de B10).
    and (select string_agg(x.firma, ',' order by x.firma) from (values
           ('private.bases_carga_repartir_core(uuid,uuid,uuid,jsonb)', '8ace9326744cba6c262adb20203b4be0', '194eeb751dadd93a633699269e771340', '{postgres=X/postgres}', '0288e89e8938d90bb83101feecea2195'),
           ('private.bases_carga_contactos_core(uuid,uuid,text)', '0faaf15b274890e1e788632c27b477bd', 'a9bb62c38eb5fe46f3ef74109800d0cf', '{postgres=X/postgres}', 'c486469dfe54d349463472b0a75dd2b6'),
           ('private.bases_carga_reparto_recogible(uuid,uuid,timestamp with time zone,boolean)', '36d80e0e61b293d9cdd710fc00758054', '48e70fe5af1cad17aaf921f4bb9d2539', '{postgres=X/postgres}', 'a57b0dd26e0f120dcfa7655db771a018'),
           ('private.bases_carga_reparto_estado(boolean,boolean,text,uuid,boolean,date,uuid,boolean,boolean,boolean,boolean,date)', '28ae6bf56e4d54fdf45ec5f976ddbce3', 'f2ed9b90aac655e8d925629a19a6dfb9', '{postgres=X/postgres}', '3163053015c2e32323184e804a72c212'),
           ('crm.repartir_base(uuid,uuid,jsonb)', 'fd7531ba7cd7cf8a259a389e2895ee2e', 'fa967cde9c19fa033aebb2020202b85a', '{postgres=X/postgres,authenticated=X/postgres}', '0893508c3762d3588f7725a9bc506737'),
           ('crm.recoger_de_base(uuid,uuid,uuid)', '4744f70e69c0f70c22a6a295184e3095', 'f9be2c8a556f2ca0a57768675041ce4a', '{postgres=X/postgres,authenticated=X/postgres}', '7f99efc1751c49a220ce04d2604ec717'),
           ('crm.contactos_de_base(uuid,text)', 'd528bab6930698d160f9635417a3ca7a', 'fb57997d070d4c8064cde67a8d5ae9d5', '{postgres=X/postgres,authenticated=X/postgres}', '3b14ee12d12694e78ee7eecf40c533c6')) x(firma, cuerpo, ident, acl, com)
         left join pg_proc p on p.oid = to_regprocedure(x.firma)
        where (md5(p.prosrc) = x.cuerpo
               and md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                       || '|' || p.proowner::regrole::text) = x.ident
               and p.proacl is not null and p.proacl::text = x.acl
               and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = x.com) is not true) is null
    and (select count(*) from pg_proc p where p.pronamespace = 'private'::regnamespace
          and (p.proname like 'bases\_carga\_reparto\_%' or p.proname in ('bases_carga_repartir_core', 'bases_carga_recoger_core', 'bases_carga_contactos_core'))) = 10
    -- Nada de B10 queda.
    and not exists (select 1 from pg_proc p where p.pronamespace in ('crm'::regnamespace, 'private'::regnamespace)
                     and (p.proname in ('seguimiento_bases', 'seguimiento_base', 'seguimiento_base_detalle', 'reactivar_lead_base_v2',
                                        'bases_carga_estado_contacto', 'bases_carga_reparto_motivo_bloque',
                                        'base_gestion_reactivar_capital_core', 'base_gestion_intento_capital_core',
                                        'registrar_intento_base_v2') or p.proname like 'bases\_carga\_seguimiento\_%'))
    and (select count(*) from pg_proc p where p.pronamespace = 'crm'::regnamespace and p.proname = 'obtener_base_gestion') = 1
    and (select count(*) from pg_proc p where p.pronamespace = 'private'::regnamespace and p.proname = 'base_gestion_reactivar_core') = 1
    and (select count(*) from pg_proc p where p.pronamespace = 'private'::regnamespace and p.proname = 'base_gestion_intento_core') = 1
    -- Lo ajeno, igual que antes; el censo, igual.
    and not exists ((select a.firma, a.huella from pg_temp._rb10_ajeno_antes a
                     except
                     select p.oid::regprocedure::text, md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|'
                                                         || p.proowner::regrole::text || '|' || coalesce(p.proacl::text, 'NULL'))
                       from pg_proc p where p.pronamespace in ('crm'::regnamespace, 'private'::regnamespace))
                    union all
                    (select p.oid::regprocedure::text, md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|'
                                                         || p.proowner::regrole::text || '|' || coalesce(p.proacl::text, 'NULL'))
                       from pg_proc p where p.pronamespace in ('crm'::regnamespace, 'private'::regnamespace)
                        and p.oid::regprocedure::text not in ('crm.obtener_base_gestion(uuid,boolean)',
                                   'crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)',
                                   'crm.seguimiento_base(uuid)',
                                   'crm.seguimiento_base_detalle(uuid,uuid,text)',
                                   'crm.seguimiento_bases()',
                                   'private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)',
                                   'private.base_gestion_reactivar_core(uuid,uuid,uuid,text)',
                                   'private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamp with time zone,numeric,text)',
                                   'private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone)',
                                   'crm.registrar_intento_base_v2(uuid,uuid,text,text,timestamp with time zone,numeric,text)',
                                   'private.bases_carga_estado_contacto(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamp with time zone,timestamp with time zone,uuid,uuid[],date,boolean,boolean,boolean)',
                                   'private.bases_carga_reparto_motivo_bloque(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamp with time zone,timestamp with time zone,uuid,uuid[],date)',
                                   'private.bases_carga_contactos_core(uuid,uuid,text)',
                                   'private.bases_carga_reparto_recogible(uuid,uuid,timestamp with time zone,boolean)',
                                   'private.bases_carga_repartir_core(uuid,uuid,uuid,jsonb)',
                                   'crm.contactos_de_base(uuid,text)',
                                   'crm.recoger_de_base(uuid,uuid,uuid)',
                                   'crm.repartir_base(uuid,uuid,jsonb)',
                                   'private.bases_carga_seguimiento_cifras()',
                                   'private.bases_carga_seguimiento_exigir_base(uuid,text,uuid)',
                                   'private.bases_carga_seguimiento_filas(uuid[],date)',
                                   'private.bases_carga_seguimiento_rol(uuid)',
                                   'private.bases_carga_reparto_estado(boolean,boolean,text,uuid,boolean,date,uuid,boolean,boolean,boolean,boolean,date)')
                     except
                     select a.firma, a.huella from pg_temp._rb10_ajeno_antes a))
    and not exists ((select c.objeto from private.contadores_crudos_leads_citas() c except select a.objeto from pg_temp._rb10_censo_antes a)
                    union all
                    (select a.objeto from pg_temp._rb10_censo_antes a except select c.objeto from private.contadores_crudos_leads_citas() c))
  ) is not true then
    raise exception 'REVERSA B10: lo repuesto no es lo de antes de B10, quedo algo de B10, cambio algo ajeno o el censo';
  end if;
  raise notice 'REVERSA B10 OK: B9 r2 repuesta (clasificador, tres piezas del nucleo y comentarios de sus puertas, byte a byte), lista de B6b y nucleos de reactivar y de intentos repuestos (cuerpo, identidad, ACL y comentario), puertas, nucleos con capital y ayudantes de B10 borrados, lo ajeno y el censo intactos';
end;
$post$;
notify pgrst, 'reload schema';
commit;
