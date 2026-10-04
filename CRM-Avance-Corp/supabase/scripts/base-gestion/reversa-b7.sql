-- REVERSA de 20261004160034_crm_bases_cargadas_esquema.sql (Bases cargadas · B7, esquema).
-- Vuelve EXACTAMENTE a B6c: borra las tres tablas, el sello de crm.leads, el disparador de los recibos y la fila
-- base_cargada del enfriamiento; repone los CHECK de origen, motivo y capital, el NOT NULL de monto_estimado, su comentario,
-- el CHECK de la política de enfriamiento y private.leads_before_insert con el texto de 20260928192822 (sin comentario).
-- Solo mientras B7 no se usó: se NIEGA si hay una sola base, fila de base o recibo, o algún lead con origen o motivo
-- base_cargada o sin capital (regla de la casa: en producción no se borra lo que tiene datos; se cierra y se observa).
-- Se niega también si alguna función (B8–B10) usa las tablas o la válvula: primero su reversa.
-- Conserva la fila de schema_migrations: anotar la reversa en MIGRACIONES.md.
-- HUELLAS (Codex r1, P2): antes de sobrescribir nada exige que lo vivo sea EXACTAMENTE lo que dejó B7 —cuerpo, identidad,
--   ACL y comentario de private.leads_before_insert, del sello y del inmutable; definición, estado y comentario del trigger
--   del sello; los tres CHECK de crm.leads; la columna monto_estimado; el CHECK y la fila base_cargada del enfriamiento; y
--   de las tres tablas: dueño, RLS (activa y FORCE), ACL de tabla y por columna, columnas (tipo, NOT NULL, default, identidad,
--   colación), restricciones, índices, policies (con PERMISSIVE/RESTRICTIVE y roles), disparadores, reglas, publicaciones y
--   comentarios (r2, Codex r2: grant por columna, policy restrictiva y FORCE RLS no se veían)—. Cualquier deriva (un cambio posterior) →
--   se niega y lo nombra: la reversa no pisa trabajo ajeno ni declara un éxito falso. Toma además el candado de migración
--   de la casa (crm_migracion_funciones, el mismo que la migración) para excluir otro despliegue en curso. Las huellas se
--   recalculan con la consulta del bloque $huellas$ en un banco con B7 recién aplicada (search_path vacío).
-- CANDADOS (memoria «DROP de tabla con FK bloquea las referenciadas», medido 30/09): DROP TABLE de una tabla con FK toma
--   ACCESS EXCLUSIVE sobre las tablas REFERENCIADAS (crm.leads y public.perfiles). Orden fijo, ANTES de comprobar el vacío y
--   hasta el commit: crm.leads → public.perfiles → crm.enfriamiento_politica → tablas nuevas (de la que más apunta a la base).
--   Una operación en vuelo termina antes (y la reversa ve sus filas y se niega) o espera a la reversa (y muere porque las
--   tablas ya no existen). ⚠️ Mientras se retienen nadie LEE ni escribe crm.leads ni public.perfiles (portal): MEDIDO en el
--   banco (04/10, 3083 leads) 90–144 ms de retención; una lectura concurrente esperó como máximo 94 ms y una escritura 71 ms.
--   lock_timeout 3 s solo limita la espera para obtenerlos (si salta, reintentar). Correr en horario bajo.
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
    to_regclass('crm.bases_carga') is not null
    and to_regclass('crm.base_carga_leads') is not null
    and to_regclass('crm.base_carga_operaciones') is not null
    and to_regprocedure('private.trg_leads_base_cargada_solo_puerta()') is not null
    and to_regprocedure('private.bases_carga_operacion_inmutable()') is not null
  ) is not true then
    raise exception 'REVERSA B7: la migracion no esta aplicada (faltan sus objetos)';
  end if;
  -- Ninguna función ajena a B7 usa sus tablas ni su válvula (B8–B10 se revierten antes).
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname not in ('pg_catalog', 'information_schema')
                and (p.prosrc ~ 'bases_carga|base_carga_leads|base_carga_operaciones' or p.prosrc ~ 'op_bases_carga')
                and p.oid not in (to_regprocedure('private.trg_leads_base_cargada_solo_puerta()')::oid,
                                  to_regprocedure('private.bases_carga_operacion_inmutable()')::oid)) then
    raise exception 'REVERSA B7: hay funciones que usan las tablas de bases o la valvula crm.op_bases_carga (B8 en adelante): corre antes su reversa';
  end if;
  if exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
              where c.relkind in ('v', 'm') and n.nspname not in ('pg_catalog', 'information_schema')
                and pg_get_viewdef(c.oid) ~ 'bases_carga|base_carga_leads|base_carga_operaciones') then
    raise exception 'REVERSA B7: hay vistas que leen las tablas de bases: corre antes su reversa';
  end if;
end;
$chk$;

-- Foto del censo ANTES de los candados de tabla (solo catálogo, ~0,1 s): no alarga el ACCESS EXCLUSIVE.
create temp table _rb7_censo_antes on commit drop as select c.objeto from private.contadores_crudos_leads_citas() c;

lock table crm.leads in access exclusive mode;
lock table public.perfiles in access exclusive mode;
lock table crm.enfriamiento_politica in access exclusive mode;
lock table crm.base_carga_operaciones, crm.base_carga_leads, crm.bases_carga in access exclusive mode;

-- Lo vivo es EXACTAMENTE lo que dejó B7 (comprobado bajo los candados: no cambia hasta el commit).
do $huellas$
declare
  v_deriva text;
begin
  with esperado(pieza, huella) as (values
      ('checks_leads', 'd92c97af75bc1583e8de62dac350ba18'),
      ('enfriamiento', '1c5efcd4ed780101c3627e926fb90d64'),
      ('inmutable_fn', '08289937da85d58120658b9afcabc21c'),
      ('leads_before_insert', '2bbe78715b418a8987eadaf7907dc434'),
      ('monto_columna', '88a6c455d8d969e22542e3e1bd5d8deb'),
      ('sello_fn', '88388bdf0adfbf5a4e175fa8306c5303'),
      ('sello_trigger', '37e087fdaa099c788b58b87a8ce56956'),
      ('tabla_base_carga_leads', 'c5a69534c53557c1ac6248aa8b85ba7d'),
      ('tabla_base_carga_operaciones', 'd8c6952fcb8299de51edd2404c974c36'),
      ('tabla_bases_carga', '78fdd853c4820d06f00a15e641efe5bf')),
  fn(pieza, firma) as (values ('leads_before_insert', 'private.leads_before_insert()'), ('sello_fn', 'private.trg_leads_base_cargada_solo_puerta()'),
                              ('inmutable_fn', 'private.bases_carga_operacion_inmutable()')),
  vivo(pieza, huella) as (
    select fn.pieza, md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|'
           || p.proowner::regrole::text || '|' || coalesce(p.proacl::text, 'NULL') || '|' || coalesce(obj_description(p.oid, 'pg_proc'), ''))
      from fn join pg_proc p on p.oid = to_regprocedure(fn.firma)
    union all
    select 'sello_trigger', md5(pg_get_triggerdef(t.oid) || '|' || t.tgenabled::text || '|' || coalesce(obj_description(t.oid, 'pg_trigger'), ''))
      from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_000_base_cargada_solo_puerta'
    union all
    select 'checks_leads', md5(string_agg(c.conname || '=' || pg_get_constraintdef(c.oid) || '|' || c.convalidated::text || '|' || coalesce(obj_description(c.oid, 'pg_constraint'), ''), ' ## ' order by c.conname))
      from pg_constraint c where c.conrelid = 'crm.leads'::regclass and c.conname in ('leads_origen_check', 'leads_motivo_descarte_check', 'leads_monto_estimado_valido')
    union all
    select 'monto_columna', md5(a.attnotnull::text || '|' || format_type(a.atttypid, a.atttypmod) || '|' || coalesce(col_description(a.attrelid, a.attnum), ''))
      from pg_attribute a where a.attrelid = 'crm.leads'::regclass and a.attname = 'monto_estimado'
    union all
    select 'enfriamiento', md5((select pg_get_constraintdef(c.oid) || '|' || c.convalidated::text || '|' || coalesce(obj_description(c.oid, 'pg_constraint'), '')
                                  from pg_constraint c where c.conrelid = 'crm.enfriamiento_politica'::regclass and c.conname = 'enfriamiento_politica_motivo_check')
                               || '|' || coalesce((select ep.dias::text || '|' || coalesce(ep.actualizado_por::text, '') from crm.enfriamiento_politica ep where ep.motivo = 'base_cargada'), 'sin fila')
                               || '|' || (select count(*) from crm.enfriamiento_politica)::text)
    union all
    -- r2 (Codex r2, P2): todo atributo de tabla, columna, restricción, índice, policy, trigger, regla o publicación que afecte
    -- a la autorización o a la restauración exacta: dueño, RLS activa Y FORCE, ACL de tabla y POR COLUMNA, opciones,
    -- persistencia, identidad de réplica, identidad/generada/colación de columna, validez y comentarios, policy PERMISSIVE o
    -- RESTRICTIVE con sus roles, reglas y publicaciones (realtime).
    select 'tabla_' || c.relname, md5(concat_ws(' ## ',
             c.relowner::regrole::text, c.relrowsecurity::text, c.relforcerowsecurity::text, coalesce(c.relacl::text, 'NULL'),
             coalesce(array_to_string(c.reloptions, ','), ''), c.relpersistence::text, c.relreplident::text,
             coalesce(obj_description(c.oid, 'pg_class'), ''),
             (select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull::text || ':' || coalesce(pg_get_expr(d.adbin, d.adrelid), '')
                                || ':' || a.attidentity::text || ':' || a.attgenerated::text || ':' || a.attcollation::regcollation::text
                                || ':' || coalesce(a.attacl::text, 'NULL') || ':' || coalesce(col_description(a.attrelid, a.attnum), ''), ',' order by a.attnum)
                from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped),
             (select string_agg(k.conname || '=' || pg_get_constraintdef(k.oid) || ':' || k.convalidated::text || ':' || coalesce(obj_description(k.oid, 'pg_constraint'), ''), ',' order by k.conname)
                from pg_constraint k where k.conrelid = c.oid),
             (select string_agg(pg_get_indexdef(i.indexrelid) || ':' || i.indisvalid::text || ':' || coalesce(obj_description(i.indexrelid, 'pg_class'), ''), ',' order by pg_get_indexdef(i.indexrelid))
                from pg_index i where i.indrelid = c.oid),
             (select string_agg(pol.polname || ':' || pol.polcmd::text || ':' || pol.polpermissive::text || ':'
                                || (select string_agg(case when r.oid = 0 then 'public' else r.oid::regrole::text end, ',' order by 1) from unnest(pol.polroles) r(oid))
                                || ':' || coalesce(pg_get_expr(pol.polqual, pol.polrelid), '') || ':' || coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), '')
                                || ':' || coalesce(obj_description(pol.oid, 'pg_policy'), ''), ',' order by pol.polname)
                from pg_policy pol where pol.polrelid = c.oid),
             (select string_agg(pg_get_triggerdef(t.oid) || ':' || t.tgenabled::text || ':' || coalesce(obj_description(t.oid, 'pg_trigger'), ''), ',' order by t.tgname)
                from pg_trigger t where t.tgrelid = c.oid and not t.tgisinternal),
             (select string_agg(rw.rulename || '=' || pg_get_ruledef(rw.oid), ',' order by rw.rulename) from pg_rewrite rw where rw.ev_class = c.oid),
             (select string_agg(pb.pubname, ',' order by pb.pubname) from pg_publication_rel pr join pg_publication pb on pb.oid = pr.prpubid where pr.prrelid = c.oid)))
      from pg_class c where c.oid in ('crm.bases_carga'::regclass, 'crm.base_carga_leads'::regclass, 'crm.base_carga_operaciones'::regclass))
  select string_agg(e.pieza, ', ' order by e.pieza) into v_deriva
    from esperado e left join vivo v on v.pieza = e.pieza
   where v.huella is distinct from e.huella;
  if v_deriva is not null then
    raise exception 'REVERSA B7: deriva en %: lo vivo no es lo que dejo B7 (algo lo cambio despues); no se sobrescribe, revisalo a mano', v_deriva;
  end if;
end;
$huellas$;

do $vacio$
begin
  if (
    not exists (select 1 from crm.bases_carga)
    and not exists (select 1 from crm.base_carga_leads)
    and not exists (select 1 from crm.base_carga_operaciones)
    and not exists (select 1 from crm.leads l
                     where l.origen = 'base_cargada' or l.motivo_descarte = 'base_cargada' or l.monto_estimado is null)
  ) is not true then
    raise exception 'REVERSA B7: hay bases, filas o recibos, o leads con origen/motivo base_cargada o sin capital; no se borran datos';
  end if;
end;
$vacio$;

-- 1 · El sello y las tablas nuevas (con sus policies, índices, disparadores y comentarios).
drop trigger trg_leads_000_base_cargada_solo_puerta on crm.leads;
drop function private.trg_leads_base_cargada_solo_puerta();
drop table crm.base_carga_operaciones;
drop table crm.base_carga_leads;
drop table crm.bases_carga;
drop function private.bases_carga_operacion_inmutable();

-- 2 · La fila del enfriamiento y su CHECK de antes.
delete from crm.enfriamiento_politica where motivo = 'base_cargada';
alter table crm.enfriamiento_politica
  drop constraint enfriamiento_politica_motivo_check,
  add constraint enfriamiento_politica_motivo_check check ((motivo = any (array['sin_interes'::text, 'sin_fondos'::text, 'competencia'::text, 'no_responde'::text, 'datos_invalidos'::text, 'pide_credito'::text, 'otro'::text])));

-- 3 · crm.leads: CHECK de antes (20260717163959/20260928192822, 20260717222018, motivo de cimientos) y NOT NULL.
alter table crm.leads
  drop constraint leads_origen_check,
  add constraint leads_origen_check check ((origen = any (array['referido'::text, 'landing'::text, 'formulario'::text, 'oficina'::text, 'otro'::text, 'web'::text, 'campania'::text, 'whatsapp'::text]))),
  drop constraint leads_motivo_descarte_check,
  add constraint leads_motivo_descarte_check check ((motivo_descarte = any (array['sin_interes'::text, 'sin_fondos'::text, 'competencia'::text, 'no_responde'::text, 'datos_invalidos'::text, 'pide_credito'::text, 'otro'::text]))),
  drop constraint leads_monto_estimado_valido,
  add constraint leads_monto_estimado_valido check (((monto_estimado > (0)::numeric) and (monto_estimado <= 9999999999.99) and (monto_estimado = trunc(monto_estimado, 2)))),
  alter column monto_estimado set not null;
comment on column crm.leads.monto_estimado is
  'Capital que el lead estima invertir. Obligatorio, mayor que 0, maximo 9999999999.99 y hasta 2 decimales; clasificado siempre junto con moneda.';

-- 4 · private.leads_before_insert: el texto vivo de 20260928192822, byte a byte, sin comentario.
create or replace function private.leads_before_insert()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'crm', 'public'
as $function$
declare
  v_priv boolean := coalesce(current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  -- Tambien aplica a importaciones y mantenimiento: no crear nuevos Otro.
  if new.origen is null or new.origen not in ('referido','landing','formulario','oficina','web','campania','whatsapp') then
    raise exception using errcode = '22023', message = 'Selecciona un canal concreto: Landing, Formulario, Referido o Walking';
  end if;
  if not v_priv then
    if new.etapa not in ('nuevo','contactado','reunion_agendada','propuesta_enviada') then
      raise exception 'Un lead nuevo no puede nacer en estado terminal';
    end if;
    new.perfil_id := null;
    new.contrato_id := null;
    new.convertido_en := null;
  end if;
  return new;
end;
$function$;
comment on function private.leads_before_insert() is null;

create temp table _rb7_censo_despues on commit drop as select c.objeto from private.contadores_crudos_leads_citas() c;
do $post$
begin
  if (
    to_regclass('crm.bases_carga') is null
    and to_regclass('crm.base_carga_leads') is null
    and to_regclass('crm.base_carga_operaciones') is null
    and to_regprocedure('private.trg_leads_base_cargada_solo_puerta()') is null
    and to_regprocedure('private.bases_carga_operacion_inmutable()') is null
    and not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_000_base_cargada_solo_puerta')
    and not exists (select 1 from crm.enfriamiento_politica where motivo = 'base_cargada')
    and (select count(*) from crm.enfriamiento_politica) = 7
    and (select pg_get_constraintdef(c.oid) = 'CHECK ((origen = ANY (ARRAY[''referido''::text, ''landing''::text, ''formulario''::text, ''oficina''::text, ''otro''::text, ''web''::text, ''campania''::text, ''whatsapp''::text])))'
                and c.convalidated and obj_description(c.oid, 'pg_constraint') is null
           from pg_constraint c where c.conrelid = 'crm.leads'::regclass and c.conname = 'leads_origen_check')
    and (select pg_get_constraintdef(c.oid) = 'CHECK ((motivo_descarte = ANY (ARRAY[''sin_interes''::text, ''sin_fondos''::text, ''competencia''::text, ''no_responde''::text, ''datos_invalidos''::text, ''pide_credito''::text, ''otro''::text])))'
                and c.convalidated and obj_description(c.oid, 'pg_constraint') is null
           from pg_constraint c where c.conrelid = 'crm.leads'::regclass and c.conname = 'leads_motivo_descarte_check')
    and (select pg_get_constraintdef(c.oid) = 'CHECK (((monto_estimado > (0)::numeric) AND (monto_estimado <= 9999999999.99) AND (monto_estimado = trunc(monto_estimado, 2))))'
                and c.convalidated and obj_description(c.oid, 'pg_constraint') is null
           from pg_constraint c where c.conrelid = 'crm.leads'::regclass and c.conname = 'leads_monto_estimado_valido')
    and (select pg_get_constraintdef(c.oid) = 'CHECK ((motivo = ANY (ARRAY[''sin_interes''::text, ''sin_fondos''::text, ''competencia''::text, ''no_responde''::text, ''datos_invalidos''::text, ''pide_credito''::text, ''otro''::text])))'
                and c.convalidated and obj_description(c.oid, 'pg_constraint') is null
           from pg_constraint c where c.conrelid = 'crm.enfriamiento_politica'::regclass and c.conname = 'enfriamiento_politica_motivo_check')
    and (select a.attnotnull and md5(coalesce(col_description(a.attrelid, a.attnum), '')) = '46535ad03f2be4cca8b4ccc7b3e3388c'
           from pg_attribute a where a.attrelid = 'crm.leads'::regclass and a.attname = 'monto_estimado')
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|'
                    || coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text) = '61451ff1ec7002a3c73670ac50f7b81a'
                and md5(p.prosrc) = '5d8df9e9f913604b1d72d0e4b0598cb2'
                and p.proacl is not null and p.proacl::text = '{postgres=X/postgres}'
                and obj_description(p.oid, 'pg_proc') is null
           from pg_proc p where p.oid = to_regprocedure('private.leads_before_insert()'))
    and not exists (select 1 from pg_temp._rb7_censo_despues c where c.objeto not in (select a.objeto from pg_temp._rb7_censo_antes a))
    and (select count(*) from pg_temp._rb7_censo_antes) = (select count(*) from pg_temp._rb7_censo_despues)
  ) is not true then
    raise exception 'REVERSA B7: no quedo exactamente como B6c';
  end if;
  raise notice 'REVERSA B7 OK: sin tablas de bases ni sello; CHECK, NOT NULL, comentario y leads_before_insert como antes; enfriamiento con 7 motivos; censo igual.';
end;
$post$;
notify pgrst, 'reload schema';
commit;
