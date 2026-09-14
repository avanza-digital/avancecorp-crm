-- Lectura previa a instalar las dos candidatas F8. No modifica ninguna fila.
-- Su resultado NO autoriza un merge: faltan paridad completa de rama/Edge,
-- pruebas remotas, Main verificado y aprobación del SQL.
begin isolation level repeatable read read only;
set local search_path='';
set local timezone='UTC';
set local lock_timeout='1s';
set local statement_timeout='30s';

with esperadas(firma,huella,acl) as (values
  ('private.inversiones_escritura_bajo_candado()','cf559da325be6be049a70d67d6212d81','{postgres=X/postgres}'),
  ('private.inversion_persona_autorizada(uuid)','758d7a5b9f6e3aaacfa0b240d8e1d3c9','{postgres=X/postgres}'),
  ('crm.cartera_inversionistas_estado_fn()','ec7e3d8d67a0ee52d176bcbd03b4cc5c','{postgres=X/postgres,authenticated=X/postgres}'),
  ('private.postventa_modo()','c110199948db88483875ee376cb28bfa','{postgres=X/postgres}'),
  ('private.postventa_visible_actor(uuid,uuid)','16dcf91c2217edc7f2c2d10dd3543597','{postgres=X/postgres}'),
  ('private.cartera_f5_fuentes()','94fa33cfcca657f70a1a94f98c3bf482','{postgres=X/postgres}'),
  ('public.marcar_contrato_demo(uuid,boolean,text)','8f3ebaefbf88f1edfdc15e7f5444b1c0','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
  ('private.trg_contratos_demo_solo_por_la_puerta()','37651e917b240da1dd7768a927e22d32',null),
  ('crm.cartera_inversionistas_fn(integer,integer,text,text,uuid,boolean)','350989c4bde7dc99779f59374a455a3a','{postgres=X/postgres,authenticated=X/postgres}'),
  ('crm.inversionista_ficha_fn(uuid,integer,integer)','82fe243e7748c392db73f53501ece1e9','{postgres=X/postgres,authenticated=X/postgres}'),
  ('crm.inversionista_documento_fn(uuid,uuid,uuid)','6139b23100b5004a797b69a50eab1989','{postgres=X/postgres,authenticated=X/postgres}'),
  ('private.postventa_fuente(uuid,uuid,text)','f66eb77a61942a617f2f84b17845c85d','{postgres=X/postgres}'),
  ('crm.postventa_vencimientos_fn(text,integer)','191d24569c9248cb336aa1b475714062','{postgres=X/postgres,authenticated=X/postgres}'),
  ('private.cartera_f5_personas_visibles()','2fa1627bf8f36e731756e0502136549f','{postgres=X/postgres}')
), funciones as (
  select e.firma,
    coalesce(md5(pg_get_functiondef(p.oid))=e.huella,false) as definicion_coincide,
    coalesce(p.proowner='postgres'::regrole,false) as propietario_postgres,
    -- NULL es aquí la ACL por defecto esperada de la función trigger existente,
    -- no una expectativa omitida. No se modifica ninguna autorización.
    (p.oid is not null and p.proacl::text is not distinct from e.acl) as acl_exigida_coincide
  from esperadas e left join pg_proc p on p.oid=to_regprocedure(e.firma)
), fuentes as materialized (select * from private.cartera_f5_fuentes()),
grupos as (
  select f.es_demo,count(*) as fuentes,
    count(*) filter(where not coalesce(f.identidad_coherente,false) or i.id is null
      or i.inversionista_canonico_id is not null) as brechas_identidad
  from fuentes f left join crm.inversionistas i on i.id=f.inversionista_id
  group by f.es_demo
), catalogo_funciones as (
  select n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' as firma,
    jsonb_build_object('def',pg_get_functiondef(p.oid),
      'owner',p.proowner::regrole::text,'config',p.proconfig,
      'comentario',obj_description(p.oid,'pg_proc'),
      'acl',(select jsonb_agg(jsonb_build_array(a.grantor::regrole::text,
        a.grantee::regrole::text,a.privilege_type,a.is_grantable)
        order by a.grantor::regrole::text,a.grantee::regrole::text,a.privilege_type,a.is_grantable)
        from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a)) as valor
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname in ('public','private','crm') and p.prokind in ('f','p')
)
select jsonb_build_object(
  'version',1,
  'inicio_captura_utc',transaction_timestamp(),
  'fin_captura_utc',clock_timestamp(),
  'alcance','precondiciones-produccion-sin-autorizacion-de-merge',
  'banderas',(select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags
    where nombre in ('resolver_en_puertas','inversiones_escritura',
      'ficha_360_neutral','postventa_neutral','metricas_multiempresa_sombra')),
  'instalacion',jsonb_build_object(
    'control',to_regclass('crm.piloto_f8_control') is not null,
    'miembros',to_regclass('crm.piloto_f8_miembros') is not null,
    'exclusion_demo',to_regprocedure('private.cartera_f5_fuentes_reales()') is not null),
  'funciones',(select jsonb_agg(f order by firma) from funciones f),
  'fuentes',(select jsonb_agg(g order by es_demo nulls last) from grupos g),
  'es_demo_not_null',exists(select 1 from pg_attribute
    where attrelid='public.contratos'::regclass and attname='es_demo'
      and attnotnull and not attisdropped),
  'proteccion_demo_presente',exists(select 1 from pg_trigger
    where tgrelid='public.contratos'::regclass
      and tgname='trg_contratos_demo_solo_por_la_puerta'
      and tgfoid=to_regprocedure('private.trg_contratos_demo_solo_por_la_puerta()')
      and tgenabled='O'),
  'historial',(select jsonb_build_object('n',count(*),'ultima',max(version),
    'md5_arrays',md5(string_agg(jsonb_build_object('version',version,'name',name,
      'statements',to_jsonb(statements))::text,E'\n' order by version)))
    from supabase_migrations.schema_migrations),
  'catalogo_funciones',(select jsonb_build_object('n',count(*),
    'md5',md5(string_agg(firma||':'||valor::text,E'\n' order by firma)))
    from catalogo_funciones)
) as captura;
rollback;
