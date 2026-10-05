-- B9 · consultas de SOLO LECTURA para la rama con datos (y, si Miguel quiere, producción con `!`), ANTES de aplicar
-- 20261004222602. No escribe nada (una transacción de solo lectura que termina en ROLLBACK). Una fila por medida.
--   M1 leads con analista Y bandeja a la vez (el guard de tenencia lo impide; si hay históricos, el corte de B6 los ignora: su
--      «reasignación» tiene que cambiar de vendedor);
--   M2 actividades «reasignación» que NO cambiaron el vendedor (auditor r2, P3: B9 no las usa como corte);
--   M3 descartados con dueño activo: con alguna «reasignación» hacia su dueño actual (cuentan desde ella) y sin ninguna (cuentan
--      desde el descarte, como B6: puede bloquear de más, nunca de menos);
--   M4 impacto del cambio de regla de B6: descartados «en gestión» HOY con la regla vieja (desde el descarte) y con la nueva
--      (desde que el dueño actual lo recibió; la rellamada, la del último intento posterior al corte);
--   M5 las 12 definiciones de disparadores que fija el preflight de B9, iguales (12 de 12), y la ayudante de B6 con la huella
--      que el preflight exige.
begin transaction read only;
set local statement_timeout = '60s';
set local search_path = '';

select 'M1 leads con vendedor y bandeja a la vez: ' || pg_catalog.count(*) from crm.leads l
 where l.vendedor_id is not null and l.asignado_supervisor_id is not null;

select 'M2 reasignaciones sin cambio de vendedor: ' || pg_catalog.count(*) || ' (con vendedor nuevo, las únicas que podrían cortar: '
       || pg_catalog.count(*) filter (where a.metadata->>'vendedor_nuevo' is not null) || ')' from crm.actividades a
 where a.tipo = 'reasignacion' and (a.metadata->>'vendedor_anterior') is not distinct from (a.metadata->>'vendedor_nuevo');

select 'M3 descartados con dueño activo: con reasignación hacia su dueño ' || pg_catalog.count(*) filter (where x.con)
       || ' · sin ella (desde el descarte) ' || pg_catalog.count(*) filter (where not x.con)
  from (select exists (select 1 from crm.actividades r where r.lead_id = l.id and r.tipo = 'reasignacion'
                         and r.metadata->>'vendedor_nuevo' = l.vendedor_id::text
                         and (r.metadata->>'vendedor_anterior') is distinct from (r.metadata->>'vendedor_nuevo')) as con
          from crm.leads l
         where l.activo and l.etapa = 'descartado'
           and exists (select 1 from crm.equipo e join public.perfiles p on p.id = e.perfil_id
                        where e.perfil_id = l.vendedor_id and e.activo and p.activo)) x;

with d as (
  select l.id, l.descartado_en, l.proxima_llamada_en,
         (select max(r.creado_en) from crm.actividades r
           where r.lead_id = l.id and r.tipo = 'reasignacion' and r.metadata->>'vendedor_nuevo' = l.vendedor_id::text
             and (r.metadata->>'vendedor_anterior') is distinct from (r.metadata->>'vendedor_nuevo')) as corte
    from crm.leads l
   where l.activo and l.etapa = 'descartado'
     and exists (select 1 from crm.equipo e join public.perfiles p on p.id = e.perfil_id
                  where e.perfil_id = l.vendedor_id and e.activo and p.activo)
), v as (
  select d.id,
         (select greatest((max(a.creado_en) at time zone 'America/Lima')::date + 7,
                          case when max(a.creado_en) is not null then (d.proxima_llamada_en at time zone 'America/Lima')::date end)
            from crm.actividades a where a.lead_id = d.id and a.metadata->>'evento' = 'intento_base' and a.creado_en >= d.descartado_en) as vieja,
         (select greatest((a.creado_en at time zone 'America/Lima')::date + 7, ((a.metadata->>'proxima_llamada_en')::timestamptz at time zone 'America/Lima')::date)
            from crm.actividades a where a.lead_id = d.id and a.metadata->>'evento' = 'intento_base' and a.creado_en >= d.descartado_en
                                     and (d.corte is null or a.creado_en >= d.corte)
           order by a.creado_en desc, a.id desc limit 1) as nueva
    from d
)
select 'M4 en gestión hoy: regla vieja ' || pg_catalog.count(*) filter (where v.vieja >= (pg_catalog.now() at time zone 'America/Lima')::date)
       || ' · regla nueva ' || pg_catalog.count(*) filter (where v.nueva >= (pg_catalog.now() at time zone 'America/Lima')::date)
       || ' · liberados por la regla nueva ' || pg_catalog.count(*) filter (where v.vieja >= (pg_catalog.now() at time zone 'America/Lima')::date
                                                                          and (v.nueva >= (pg_catalog.now() at time zone 'America/Lima')::date) is not true)
  from v;

select 'M5 definiciones de disparadores iguales a las del preflight: ' || pg_catalog.count(*) || ' de 12' from (values
  ('crm.leads', 'trg_leads_000_base_cargada_solo_puerta', 'CREATE TRIGGER trg_leads_000_base_cargada_solo_puerta BEFORE INSERT OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_leads_base_cargada_solo_puerta()'),
  ('crm.leads', 'trg_leads_00_devolucion_equipo_solo_rpc', 'CREATE TRIGGER trg_leads_00_devolucion_equipo_solo_rpc BEFORE UPDATE OF vendedor_id, asignado_supervisor_id ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_devolucion_equipo_solo_rpc()'),
  ('crm.leads', 'trg_leads_00_guard_tenencia', 'CREATE TRIGGER trg_leads_00_guard_tenencia BEFORE INSERT OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_leads_guard_tenencia()'),
  ('crm.leads', 'trg_leads_00_seguimiento_activo', 'CREATE TRIGGER trg_leads_00_seguimiento_activo BEFORE UPDATE ON crm.leads FOR EACH ROW WHEN (((old.etapa = ''descartado''::text) AND (new.vendedor_id IS DISTINCT FROM old.vendedor_id))) EXECUTE FUNCTION private.trg_leads_guard_seguimiento_activo()'),
  ('crm.leads', 'trg_leads_02_sla_versionado', 'CREATE TRIGGER trg_leads_02_sla_versionado AFTER INSERT OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_leads_sla_versionado()'),
  ('crm.leads', 'trg_leads_asignaciones', 'CREATE TRIGGER trg_leads_asignaciones AFTER INSERT OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_leads_asignaciones()'),
  ('crm.leads', 'trg_leads_bloquear_reasignacion', 'CREATE TRIGGER trg_leads_bloquear_reasignacion BEFORE UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_leads_bloquear_reasignacion()'),
  ('crm.leads', 'trg_leads_reasignacion', 'CREATE TRIGGER trg_leads_reasignacion BEFORE UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_leads_reasignacion()'),
  ('crm.leads', 'trg_leads_zz_sync_tareas', 'CREATE TRIGGER trg_leads_zz_sync_tareas AFTER UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_leads_sync_tareas()'),
  ('crm.leads', 'trg_leads_zzz_tenencia_desde', 'CREATE TRIGGER trg_leads_zzz_tenencia_desde BEFORE INSERT OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_leads_tenencia_desde()'),
  ('crm.leads', 'trg_zzzz_usuario_retirado', 'CREATE TRIGGER trg_zzzz_usuario_retirado BEFORE INSERT OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.no_asignar_usuario_retirado()'),
  ('crm.actividades', 'trg_01_gestion_lead_serializada', 'CREATE TRIGGER trg_01_gestion_lead_serializada BEFORE INSERT ON crm.actividades FOR EACH ROW EXECUTE FUNCTION private.trg_gestion_lead_serializada()')) x(tabla, nombre, definicion)
  join pg_catalog.pg_trigger t on t.tgrelid = x.tabla::regclass and t.tgname = x.nombre
 where t.tgenabled = 'O' and pg_catalog.pg_get_triggerdef(t.oid) = x.definicion;

select 'M5 ayudante de B6 (antes de B9): identidad ' || pg_catalog.md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|'
       || coalesce(pg_catalog.array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text)
       || ' (esperada e90da5df4c53fa1c30f0ca5f71431631) · cuerpo ' || pg_catalog.md5(p.prosrc) || ' (af0701a9e095e1004a64b7e289789d7c)'
       || ' · comentario ' || pg_catalog.md5(coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), '')) || ' (6b4c155f38d0722f9e9247547b5c3c2a)'
  from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('private.base_gestion_en_gestion_hasta(uuid)');
rollback;
