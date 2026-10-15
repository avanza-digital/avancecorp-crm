-- VERIFICACIÓN posterior de 20261015000852_crm_plazo_carga_mes (SOLO LECTURA). Se corre DESPUÉS de aplicarla y
-- registrarla. Devuelve UNA fila con el veredicto (supabase db query solo muestra la última sentencia con filas).
-- «APLICADA Y REGISTRADA» exige además que las 14 piezas creadas o reemplazadas tengan su huella esperada exacta.
--   npx supabase db query --linked --file supabase/scripts/plazo-carga-mes/verificar-produccion.sql
set search_path = '';
-- Huellas esperadas (md5 de pg_get_functiondef con search_path vacío) de lo que la migración crea o reemplaza, medidas en
-- el banco con la migración aplicada (revisiones Codex r1 y r2 incluidas). El veredicto exige que TODAS coincidan.
with esperadas (firma, huella) as (values
  ('crm.cerrar_periodo(date)', '93f09c459ac98c954ee280a9f4f3a03c'),
  ('crm.fijar_plazo_carga_mes(date,date,text)', 'd9ff1cf163c3406a44c01e17351e3441'),
  ('crm.plazos_carga_mes_fn()', '4e7fdee83363ff84360038c1ac5f757a'),
  ('private.conversion_plazo_hasta(date)', '4ce984684a471d20aa779365c9b92452'),
  ('private.reabrir_mes(date,text,uuid)', '9983ea772ff3e4c0bc7231f696391854'),
  ('private.reapertura_autoriza(date,uuid)', '2dd1b1194dd53864e58a8dbaea60aa73'),
  ('private.reapertura_impedimento(date)', 'bcd7f90aa567e1e4fe9fda835f1f2262'),
  ('private.fijar_plazo_carga(date,date,text,uuid)', '927fd44b675a3571979131068510a10d'),
  ('private.plazos_carga_mes_lectura()', '91cd95daab6ab2de00f92417422476df'),
  ('private.trg_reaperturas_mes_llave()', '961723b931f6dda80be7beb768482ba8'),
  ('private.conversion_reevaluar_plazo(date)', '6154da0f3b1b7a9cbd9e2e376e8d984c'),
  ('private.f4_fuente_inmutable()', 'f4608368a957e5ce1fe191562d5b5bea'),
  ('private.trg_cierre_mes_append_only()', 'd0c47d994002426fc58148ac361a1907'),
  ('private.trg_cierres_externos_inmutables()', 'c9f55c70e526975476b1f6aead562cd4')
), medidas as (
  select e.firma, e.huella as esperada,
         (select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) from pg_catalog.pg_proc p
           where p.oid = pg_catalog.to_regprocedure(e.firma)) as medida
    from esperadas e
)
select jsonb_build_object(
  'veredicto', case when (
      to_regclass('crm.plazos_carga_mes') is not null and to_regclass('crm.reaperturas_mes') is not null
      and to_regprocedure('crm.fijar_plazo_carga_mes(date,date,text)') is not null
      and to_regprocedure('crm.plazos_carga_mes_fn()') is not null
      and (select p.provolatile from pg_catalog.pg_proc p where p.oid = 'private.conversion_plazo_hasta(date)'::regprocedure) = 's'
      and (select p.provolatile from pg_catalog.pg_proc p where p.oid = 'private.cierre_mes_ventana_desde(date)'::regprocedure) = 's'
      and exists (select 1 from pg_catalog.pg_constraint c where c.conrelid = 'crm.conversion_acreditaciones'::regclass
                   and c.conname = 'conversion_acreditaciones_plazo_minimo_check')
      and (select p.proacl::text from pg_catalog.pg_proc p where p.oid = 'crm.fijar_plazo_carga_mes(date,date,text)'::regprocedure)
            = '{postgres=X/postgres,authenticated=X/postgres}'
      and exists (select 1 from supabase_migrations.schema_migrations where version = '20261015000852')
      and not exists (select 1 from medidas m where m.medida is distinct from m.esperada)
    ) then 'APLICADA Y REGISTRADA' else 'REVISAR' end,
  'registrada', exists (select 1 from supabase_migrations.schema_migrations where version = '20261015000852'),
  'huellas_ok', not exists (select 1 from medidas m where m.medida is distinct from m.esperada),
  'huellas_distintas', (select coalesce(pg_catalog.jsonb_object_agg(m.firma, m.medida), '{}'::jsonb)
                          from medidas m where m.medida is distinct from m.esperada),
  'decisiones', (select pg_catalog.count(*) from crm.plazos_carga_mes),
  'reaperturas', (select pg_catalog.count(*) from crm.reaperturas_mes),
  'meses_sellados', (select pg_catalog.jsonb_agg(pc.periodo order by pc.periodo) from crm.periodos_cerrados pc),
  'plazo_septiembre_vigente_lima', (private.conversion_plazo_hasta(date '2026-09-01') at time zone 'America/Lima'),
  'plazo_octubre_vigente_lima', (private.conversion_plazo_hasta(date '2026-10-01') at time zone 'America/Lima'),
  'ciclo_diario', (select pg_catalog.jsonb_build_object('activo', j.active, 'horario', j.schedule, 'comando', j.command)
                     from cron.job j where j.jobid = 3),
  'trinquetes', (select pg_catalog.jsonb_object_agg(x.f, x.r) from (
      select 'f7' as f, (select pg_catalog.count(*) from private.f7_piezas_en_observacion) as r
      union all select 'contadores_sin_declarar',
        (select pg_catalog.count(*) from private.contadores_crudos_leads_citas() c where not c.declarada)
      union all select 'contadores_huella_caducada',
        (select pg_catalog.count(*) from private.contadores_crudos_leads_citas() c where c.declarada and not c.huella_ok)
      union all select 'tablas_sin_rastro', (select pg_catalog.count(*) from private.tablas_sin_rastro())) x)
) as verificacion;
