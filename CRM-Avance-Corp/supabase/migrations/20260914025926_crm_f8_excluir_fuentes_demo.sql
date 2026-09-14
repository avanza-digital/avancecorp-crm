-- F8: el universo operativo comprende fuentes reales. La historia bruta conserva
-- los demos y sus huecos de identidad. No marca filas, inventa documentos, enlaza
-- personas ni activa el piloto. Requiere 20260913215240 instalado y apagado.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';

do $preflight$
declare r record;
begin
  if to_regclass('crm.piloto_f8_control') is null then
    raise exception 'Instalar primero el control F8 apagado';
  end if;
  if current_setting('transaction_isolation')<>'read committed' then
    raise exception 'La instalación requiere READ COMMITTED' using errcode='0A000';
  end if;
  -- Mismo candado que la activación y el rollout: nadie puede encenderlos
  -- después del preflight y antes del COMMIT de las ocho definiciones.
  perform pg_advisory_xact_lock(hashtext('crm_piloto_f8_control'));
  if exists(select 1 from crm.piloto_f8_control where activo)
    or exists(select 1 from crm.multiempresa_flags where activo and nombre in
      ('inversiones_escritura','ficha_360_neutral','postventa_neutral','metricas_multiempresa_sombra')) then
    raise exception 'La exclusión demo requiere F8 y F4-F7 apagados';
  end if;
  if to_regprocedure('private.cartera_f5_fuentes_reales()') is not null then
    raise exception 'La exclusión demo ya existe; no se reinstala';
  end if;
  -- Estas autoridades ya clasifican los demos. Se conservan sin cambios, junto
  -- con sus permisos, motivo obligatorio, auditoría y veto a meses sellados.
  for r in select * from (values
    ('private.cartera_f5_fuentes()','94fa33cfcca657f70a1a94f98c3bf482'),
    ('public.marcar_contrato_demo(uuid,boolean,text)','8f3ebaefbf88f1edfdc15e7f5444b1c0'),
    ('private.trg_contratos_demo_solo_por_la_puerta()','37651e917b240da1dd7768a927e22d32')
  ) v(firma,huella) loop
    if to_regprocedure(r.firma) is null
      or md5(pg_get_functiondef(to_regprocedure(r.firma))) is distinct from r.huella then
      raise exception 'La autoridad demo cambió: revisar %',r.firma;
    end if;
  end loop;
  if not exists(select 1 from pg_trigger where tgrelid='public.contratos'::regclass
      and tgname='trg_contratos_demo_solo_por_la_puerta'
      and tgfoid='private.trg_contratos_demo_solo_por_la_puerta()'::regprocedure
      and tgenabled='O') then
    raise exception 'Falta la protección vigente de la marca demo';
  end if;
end;
$preflight$;

-- Un NULL nunca permite evadir cobertura: solo es_demo=true queda excluido.
-- INVOKER, privado y sin EXECUTE de API. Los RPC conservan su autorización.
create function private.cartera_f5_fuentes_reales()
returns table (
  fuente_id uuid, inversionista_id uuid, inversion_id uuid, empresa text,
  perfil_id uuid, lead_id uuid, numero text, capital numeric, moneda text,
  estado text, fecha_comercial date, fecha_imputacion date, vence_en date,
  analista_origen_id uuid, es_inicial boolean, es_demo boolean,
  identidad_coherente boolean, creado_en timestamptz
)
language sql stable security invoker set search_path=''
as $f$
  select * from private.cartera_f5_fuentes() f where f.es_demo is not true;
$f$;
revoke all on function private.cartera_f5_fuentes_reales()
  from public,anon,authenticated,service_role;

-- Cambios mínimos sobre definiciones exactas ya verificadas. CREATE OR REPLACE
-- conserva OID, firmas, dueños y ACL. Un cambio concurrente de base aborta todo.
do $lectores$
declare r record; v_antes text; v_despues text; v_acl text;
begin
  for r in select * from (values
    ('private.trg_piloto_f8_control_validar()','4fba28d46a46ac4febb7ff81fbd9ac04'),
    ('crm.cartera_inversionistas_estado_fn()','e1da1dd2f01a85bd3cc70a8e28db651b'),
    ('crm.cartera_inversionistas_fn(integer,integer,text,text,uuid,boolean)','350989c4bde7dc99779f59374a455a3a'),
    ('crm.inversionista_ficha_fn(uuid,integer,integer)','82fe243e7748c392db73f53501ece1e9'),
    ('crm.inversionista_documento_fn(uuid,uuid,uuid)','6139b23100b5004a797b69a50eab1989'),
    ('private.postventa_fuente(uuid,uuid,text)','f66eb77a61942a617f2f84b17845c85d'),
    ('crm.postventa_vencimientos_fn(text,integer)','191d24569c9248cb336aa1b475714062')
  ) v(firma,huella) loop
    v_antes:=pg_get_functiondef(to_regprocedure(r.firma));
    if md5(v_antes) is distinct from r.huella then
      raise exception 'La base cambió: revisar % antes de excluir demos',r.firma;
    end if;
    select proacl::text into v_acl from pg_proc where oid=to_regprocedure(r.firma);
    v_despues:=replace(v_antes,'private.cartera_f5_fuentes()',
      'private.cartera_f5_fuentes_reales()');
    if v_despues=v_antes then raise exception 'Falta el lector esperado en %',r.firma; end if;
    execute v_despues;
    if (select proacl::text from pg_proc where oid=to_regprocedure(r.firma)) is distinct from v_acl then
      raise exception 'Los permisos cambiaron en %',r.firma;
    end if;
  end loop;
end;
$lectores$;

-- La excepción de perfiles cliente sin inversiones sigue siendo válida, pero
-- no permite reintroducir una persona cuya única historia económica es demo.
-- Para detectar historia demo se consideran TODOS los extremos de esa fuente,
-- incluso demos con enlaces contradictorios o con identidad fusionada.
do $personas$
declare v_antes text; v_despues text; v_ancla text; v_reemplazo text;
begin
  v_antes:=pg_get_functiondef('private.cartera_f5_personas_visibles()'::regprocedure);
  if md5(v_antes)<>'2fa1627bf8f36e731756e0502136549f' then
    raise exception 'La base cambió: revisar personas visibles antes de excluir demos';
  end if;
  v_ancla:='), fuentes as materialized (select * from private.cartera_f5_fuentes()),';
  v_reemplazo:=$sql$), fuentes as materialized (select * from private.cartera_f5_fuentes_reales()),
  demos as materialized (select * from private.cartera_f5_fuentes() where es_demo is true),
  con_historia as materialized (
    select private.inversionista_canonica(i.id) id
      from demos f join crm.inversionistas i on i.perfil_id=f.perfil_id
    union select private.inversionista_canonica(iv.inversionista_id)
      from demos f join crm.inversiones iv on iv.id=f.inversion_id
    union select private.inversionista_canonica(ce.inversionista_id)
      from demos f join crm.cierres_externos ce on ce.id=f.fuente_id
      where ce.inversionista_id is not null
    union select private.inversionista_canonica(l.inversionista_id)
      from demos f join crm.leads l on l.id=f.lead_id
      where l.inversionista_id is not null
    union select private.inversionista_canonica(il.inversionista_id)
      from demos f join crm.inversionista_leads il on il.lead_id=f.lead_id
  ),$sql$;
  if strpos(v_antes,v_ancla)=0 then raise exception 'Falta el ancla de fuentes en personas'; end if;
  v_despues:=replace(v_antes,v_ancla,v_reemplazo);
  v_ancla:=$sql$or exists (select 1 from crm.inversionistas h
          join public.perfiles p on p.id=h.perfil_id and p.rol='cliente'
          where private.inversionista_canonica(h.id)=i.id))$sql$;
  v_reemplazo:=$sql$or (not exists(select 1 from con_historia h where h.id=i.id)
          and exists (select 1 from crm.inversionistas h
            join public.perfiles p on p.id=h.perfil_id and p.rol='cliente'
            where private.inversionista_canonica(h.id)=i.id)))$sql$;
  if strpos(v_despues,v_ancla)=0 then raise exception 'Falta el ancla de perfiles sin inversiones'; end if;
  execute replace(v_despues,v_ancla,v_reemplazo);
end;
$personas$;

-- El lector bruto sigue disponible para conciliación administrativa y F7.
-- No se toca ninguna fila de contratos, cierres, identidades, Auth o auditoría.
do $postflight$
declare r record;
begin
  if md5(pg_get_functiondef('private.cartera_f5_fuentes()'::regprocedure))
      <>'94fa33cfcca657f70a1a94f98c3bf482' then
    raise exception 'Se alteró el censo histórico';
  end if;
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname !~ '^pg_' and n.nspname<>'information_schema'
        and p.prosrc ~ '(?i)\mcartera_f5_fuentes"?[[:space:]]*\('
        and p.oid not in ('private.cartera_f5_fuentes_reales()'::regprocedure,
          'private.cartera_f5_personas_visibles()'::regprocedure,
          'private.metricas_f7_fuentes()'::regprocedure)) then
    raise exception 'Queda un consumidor sin revisar del censo histórico';
  end if;
  -- Vistas (incluidas materializadas), policies y cuerpos SQL ATOMIC registran
  -- dependencias de catálogo. Las funciones con cuerpos de texto se cubren arriba.
  if exists(select 1 from pg_depend d
      where d.refclassid='pg_proc'::regclass
        and d.refobjid='private.cartera_f5_fuentes()'::regprocedure
        and d.classid in ('pg_rewrite'::regclass,'pg_policy'::regclass,'pg_proc'::regclass)) then
    raise exception 'Queda una dependencia de catálogo sin revisar del censo histórico';
  end if;
  -- La reversa solo acepta estas definiciones: comprobarlas antes del COMMIT.
  for r in select * from (values
    ('private.trg_piloto_f8_control_validar()','47585a27b991a442bb09b3477be5f224'),
    ('crm.cartera_inversionistas_estado_fn()','83575873409d51508753fa6405ffcc92'),
    ('crm.cartera_inversionistas_fn(integer,integer,text,text,uuid,boolean)','e02e89b5a920c8388d77a01c07f13198'),
    ('crm.inversionista_ficha_fn(uuid,integer,integer)','8068f1491852e2c64260b359183fd92b'),
    ('crm.inversionista_documento_fn(uuid,uuid,uuid)','18db225353031f1afc67a8263c281494'),
    ('private.postventa_fuente(uuid,uuid,text)','07fb5ace10e00eeedd123306d791d086'),
    ('crm.postventa_vencimientos_fn(text,integer)','d8d3aa51705748888e5dfffc347f98ee'),
    ('private.cartera_f5_personas_visibles()','f32a1baf67372df496388508a724e6bb')
  ) v(firma,huella) loop
    if md5(pg_get_functiondef(to_regprocedure(r.firma))) is distinct from r.huella then
      raise exception 'La definición final de % no coincide con la reversa ensayada',r.firma;
    end if;
  end loop;
  if has_function_privilege('anon','private.cartera_f5_fuentes_reales()','EXECUTE')
    or has_function_privilege('authenticated','private.cartera_f5_fuentes_reales()','EXECUTE')
    or has_function_privilege('service_role','private.cartera_f5_fuentes_reales()','EXECUTE') then
    raise exception 'El lector privado no debe ser accesible por API';
  end if;
end;
$postflight$;
commit;
