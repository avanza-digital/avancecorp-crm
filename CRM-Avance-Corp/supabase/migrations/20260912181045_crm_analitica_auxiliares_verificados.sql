-- Gobernanza: inventario completo, auxiliares verificados y techo de métricas.
-- No cambia las seis funciones operativas/comerciales auditadas ni ningún dato.
-- Requiere primero 20260912151320_crm_citas_consulta_nucleos.sql.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
lock table private.analitica_leads_citas_exenciones,private.analitica_leads_citas_tope,
  private.analitica_lc_sello in share row exclusive mode;
create temporary table analitica_aux_preflight on commit drop as
select (select to_jsonb(t) from private.analitica_leads_citas_tope t where id) as tope,
  (select jsonb_agg(to_jsonb(e) order by objeto) from private.analitica_leads_citas_exenciones e
    where objeto not in ('crm.historial_decisiones_tasa_gerencia_fn(integer,text,text,integer,timestamp with time zone,uuid)','private.inversion_historica_estado(text,uuid)','private.inversion_historica_aplicar(uuid,jsonb)','crm.metricas_multiempresa_fn(date)','crm.cierres_externos_fn(date)','private.metricas_conversiones_implementacion(date,date,text)')) as otras;
do $preflight$
declare r record;
begin
  if to_regprocedure('private.auxiliares_analitica_lc_auditados()') is not null then
    raise exception 'Clasificación de auxiliares ya existente: revisar el estado antes de instalar';
  end if;
  if (select md5(prosrc) from pg_proc where oid='private.assert_analitica_leads_citas()'::regprocedure)
    is distinct from '82054fbecde2262939221c633442fd49' then
    raise exception 'Se requiere el gate exacto de la migración de Citas validada';
  end if;
  if (select md5(pg_get_functiondef('private.contadores_crudos_leads_citas()'::regprocedure)))
    <> '34e0ae16a95912e5a5eedd4da845e288' then raise exception 'El censo cambió'; end if;
  if (select count(*) from private.contadores_crudos_leads_citas())<>34
    or (select tope from private.analitica_leads_citas_tope where id)<>30 then
    raise exception 'Inventario o techo diferentes a la base revisada (34/30)';
  end if;
  if (select sello from private.analitica_lc_sello where id)
    is distinct from private.huella_exenciones_analitica_lc() then raise exception 'Sello previo inválido'; end if;
  for r in select * from (values
    ('crm.cierres_externos_fn(date)','c46cc5e818295f375671127d03516dd3','{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.metricas_conversiones_implementacion(date,date,text)','a7bbf47ebc9e03a1ec67cf4088152382','{postgres=X/postgres}'),
    ('crm.historial_decisiones_tasa_gerencia_fn(integer,text,text,integer,timestamp with time zone,uuid)','b6d363f5c5d3520d6876a708b80a0589','{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.inversion_historica_estado(text,uuid)','2b57432c993eaa8e1599bf874427b743','{postgres=X/postgres}'),
    ('private.inversion_historica_aplicar(uuid,jsonb)','a33595d4ac8c2c12ad6fcf9463db605e','{postgres=X/postgres}'),
    ('crm.metricas_multiempresa_fn(date)','4ab8a07f4794c015c4bb7264206dafcf','{postgres=X/postgres,authenticated=X/postgres}')
  ) revisados(firma,huella,permisos) loop
    if not exists(select 1 from pg_proc p where p.oid=to_regprocedure(r.firma)
      and md5(pg_get_functiondef(p.oid))=r.huella
      and p.proowner='postgres'::regrole and p.proacl::text=r.permisos) then
      raise exception 'Cambió una función revisada o sus permisos: %',r.firma;
    end if;
  end loop;
  if (select huella from private.analitica_leads_citas_exenciones where objeto='crm.cierres_externos_fn(date)')
       is distinct from '9cf31d2ee85bd5e0af19ae77fd187187'
    or (select huella from private.analitica_leads_citas_exenciones where objeto='private.metricas_conversiones_implementacion(date,date,text)')
       is distinct from '235f0ae12fdc2d7ab9029056786eab76' then
    raise exception 'Las declaraciones previas difieren de las versiones auditadas';
  end if;
end $preflight$;
CREATE OR REPLACE FUNCTION private.auxiliares_analitica_lc_auditados()
 RETURNS TABLE(objeto text, razon text, vigente boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- Cuatro falsos positivos revisados, cerrados a definición, propietario y ACL.
  -- La lista no acepta parámetros ni se administra mediante una tabla/API.
  with revisados(objeto, definicion_md5, permisos, razon) as (
    values
      ('crm.historial_decisiones_tasa_gerencia_fn(integer,text,text,integer,timestamp with time zone,uuid)', 'b6d363f5c5d3520d6876a708b80a0589', '[["authenticated","EXECUTE",false],["postgres","EXECUTE",false]]'::jsonb, 'Auxiliar de solicitudes de tasa: cuenta solicitudes y páginas; crm.leads sólo aporta el nombre del solicitante. No cuenta leads ni citas.'),
      ('private.inversion_historica_estado(text,uuid)', '2b57432c993eaa8e1599bf874427b743', '[["postgres","EXECUTE",false]]'::jsonb, 'Conciliación administrativa de identidad: lee un lead concreto y cuenta titulares de la inversión; no calcula métricas de leads/citas.'),
      ('private.inversion_historica_aplicar(uuid,jsonb)', 'a33595d4ac8c2c12ad6fcf9463db605e', '[["postgres","EXECUTE",false]]'::jsonb, 'Mantenimiento administrativo: cuenta entradas JSON para impedir duplicados y bloquea leads asociados; no calcula métricas de leads/citas.'),
      ('crm.metricas_multiempresa_fn(date)', '4ab8a07f4794c015c4bb7264206dafcf', '[["authenticated","EXECUTE",false],["postgres","EXECUTE",false]]'::jsonb, 'Métricas de capital e identidades: conversión desde conversion_episodios; crm.leads sólo aplica el veto No contactar. No reconstruye conteos crudos de leads/citas.')
  )
  select r.objeto,r.razon,coalesce(
    md5(pg_get_functiondef(p.oid))=r.definicion_md5
    and p.proowner='postgres'::regrole
    and (select jsonb_agg(jsonb_build_array(a.grantee::regrole::text,a.privilege_type,a.is_grantable)
      order by a.grantee::regrole::text,a.privilege_type,a.is_grantable)
      from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a)=r.permisos,
    false) as vigente
  from revisados r left join pg_proc p on p.oid=to_regprocedure(r.objeto)
  order by r.objeto;
$function$
;
alter function private.auxiliares_analitica_lc_auditados() owner to postgres;
revoke all on function private.auxiliares_analitica_lc_auditados() from public,anon,authenticated,service_role;
grant execute on function private.auxiliares_analitica_lc_auditados() to postgres;
insert into private.analitica_leads_citas_exenciones(objeto,tipo,huella,razon)
select a.objeto,'funcion',md5(regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')),a.razon
from private.auxiliares_analitica_lc_auditados() a join pg_proc p on p.oid=to_regprocedure(a.objeto);
-- Derivas identificadas byte a byte con la migración F4 publicada del 08/09.
-- Cierres: fecha de imputación, identidad actual para teléfono y cierre sin lead.
-- Conversiones: imputación de cooperativa y sólo cierre inicial como rastro.
update private.analitica_leads_citas_exenciones e
set huella=md5(regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')),
  razon=e.razon || case when e.objeto='crm.cierres_externos_fn(date)'
    then ' F4 publicada: período por fecha de imputación, cierres independientes del lead y teléfono vivo restringido a la relación canónica actual. Cálculos y permisos conservados.'
    else ' F4 publicada: contratos cooperativos por fecha de imputación y rastro por cierre inicial. Conserva los núcleos de conversión, citas y capital y sus fórmulas.' end
from pg_proc p where p.oid=to_regprocedure(e.objeto)
  and e.objeto in ('crm.cierres_externos_fn(date)','private.metricas_conversiones_implementacion(date,date,text)');
update private.analitica_lc_sello set sello=private.huella_exenciones_analitica_lc(),sellado_en=now() where id;
CREATE OR REPLACE FUNCTION private.assert_analitica_leads_citas()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_sin text; v_cad text; v_n integer; v_tope integer; v_total integer; v_auxiliares integer;
begin

  -- El inventario sigue completo. Sólo cuatro definiciones auxiliares conocidas
  -- se descuentan del techo; una deriva de cuerpo/owner/ACL invalida el gate.
  if not exists(select 1 from pg_proc p
    where p.oid=to_regprocedure('private.auxiliares_analitica_lc_auditados()')
      and md5(pg_get_functiondef(p.oid))='e43357800b6d79050c7ca7af6c6844b8'
      and p.proowner='postgres'::regrole
      and (select jsonb_agg(jsonb_build_array(a.grantee::regrole::text,a.privilege_type,a.is_grantable)
        order by a.grantee::regrole::text,a.privilege_type,a.is_grantable)
        from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a)
        ='[["postgres","EXECUTE",false]]'::jsonb) then
    raise exception 'La clasificación fija de auxiliares cambió o tiene permisos indebidos';
  end if;
  if (select array_agg(objeto order by objeto) from private.auxiliares_analitica_lc_auditados())
    is distinct from array['crm.historial_decisiones_tasa_gerencia_fn(integer,text,text,integer,timestamp with time zone,uuid)','crm.metricas_multiempresa_fn(date)','private.inversion_historica_aplicar(uuid,jsonb)','private.inversion_historica_estado(text,uuid)']::text[] then
    raise exception 'El conjunto de auxiliares difiere de las cuatro identidades revisadas';
  end if;
  if exists(select 1 from private.auxiliares_analitica_lc_auditados() a
    where not a.vigente or not exists(select 1 from private.contadores_crudos_leads_citas() c
      where c.objeto=a.objeto and c.declarada and c.huella_ok)) then
    raise exception 'Un auxiliar auditado cambió, desapareció o perdió su declaración vigente';
  end if;
  -- Las lecturas acotadas comparten los núcleos, pero tampoco son puertas API.
  if to_regprocedure('private.citas_episodios(timestamptz,timestamptz,timestamptz,uuid[])') is null
    or to_regprocedure('private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])') is null then
    raise exception 'Desapareció una lectura acotada de los núcleos de Citas/Conversión';
  end if;
  if exists (
    select 1 from pg_proc p
    cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
    where p.oid in (
      'private.citas_episodios(timestamptz,timestamptz,timestamptz,uuid[])'::regprocedure,
      'private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])'::regprocedure)
      and a.grantee<>'postgres'::regrole::oid
  ) then raise exception 'Una lectura acotada de Citas/Conversión tiene EXECUTE fuera de postgres'; end if;
  select string_agg(tipo || ' ' || objeto, ', ' order by objeto)
    into v_sin from private.contadores_crudos_leads_citas() where not declarada;
  if v_sin is not null then
    raise exception 'Contadores crudos de leads/citas SIN declarar: %. O beben del nucleo, o se declaran con su razon.', v_sin;
  end if;

  select string_agg(tipo || ' ' || objeto, ', ' order by objeto)
    into v_cad from private.contadores_crudos_leads_citas() where declarada and not huella_ok;
  if v_cad is not null then
    raise exception 'Contadores exentos cuyo cuerpo CAMBIO desde que se declararon (la razon caduco): %', v_cad;
  end if;

  select count(*) into v_total from private.contadores_crudos_leads_citas();
  select count(*) into v_auxiliares from private.auxiliares_analitica_lc_auditados();
  v_n:=v_total-v_auxiliares;
  -- Anti-vacuidad: el tope es techo, no suelo. Un censo que devuelve 0 filas es
  -- una regresion del propio censo, no un exito.
  if v_n = 0 then
    raise exception 'El censo devolvio 0 contadores: eso es una regresion del censo, no la meta';
  end if;
  select tope into v_tope from private.analitica_leads_citas_tope where id;
  if v_tope is null then raise exception 'No hay tope fijado'; end if;
  if v_n > v_tope then
    raise exception 'Los contadores crudos subieron de % a %: el trinquete solo deja bajar.', v_tope, v_n;
  end if;

  -- El sello de la lista: si alguien la relavo sin re-sellar, rojo.
  if (select sello from private.analitica_lc_sello where id)
     is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'La lista de exenciones cambio sin re-sellarse en una migracion';
  end if;

  -- Los candados del tope tienen que seguir puestos y ACTIVOS: sin esto, un
  -- despliegue privilegiado podria deshabilitar el trigger, subir el tope y
  -- dejar el gate verde.
  if (select count(*) from pg_trigger t
       where t.tgrelid = 'private.analitica_leads_citas_tope'::regclass
         and t.tgname in ('trg_analitica_lc_tope_solo_baja','trg_analitica_lc_tope_no_truncar')
         and t.tgenabled in ('O','A')) <> 2 then
    raise exception 'Los candados del tope no estan puestos o no estan activos';
  end if;

  -- Los dos nucleos tienen que seguir vivos y con su forma.
  if to_regprocedure('private.citas_episodios(timestamptz,timestamptz,timestamptz)') is null then
    raise exception 'El nucleo de citas desaparecio';
  end if;
  if to_regprocedure('private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)') is null then
    raise exception 'El nucleo de leads desaparecio';
  end if;
  -- Y la pantalla de reuniones tiene que seguir bebiendo del de citas - mirado
  -- SIN comentarios (un `-- citas_episodios` de senuelo no vale).
  if not exists (
    select 1 from pg_proc p
     where p.oid = 'private.metricas_reuniones_implementacion(date,date)'::regprocedure
       and regexp_replace(regexp_replace(p.prosrc,'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')
           ~ '\mcitas_episodios\s*\('
  ) then
    raise exception 'La pantalla de reuniones dejo de beber del nucleo de citas';
  end if;

  -- El nucleo devuelve FILAS de toda la empresa (DEFINER): cada llamador tiene
  -- que estar DECLARADO en las exenciones (su declaracion es su puerta escrita).
  if exists (
    select 1 from pg_proc p
     where p.prokind in ('f','p')
       and p.oid <> coalesce(to_regprocedure('private.citas_episodios(timestamptz,timestamptz,timestamptz)'),0)
       and p.oid <> coalesce(to_regprocedure('private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)'),0)
       and p.oid <> coalesce(to_regprocedure('private.assert_analitica_leads_citas()'),0)
       and p.oid <> coalesce(to_regprocedure('private.contadores_crudos_leads_citas()'),0)
       and regexp_replace(regexp_replace(coalesce(p.prosrc,''),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')
           ~ '\m(citas_episodios|conversion_cierres)\s*\('
       and not exists (select 1 from private.analitica_leads_citas_exenciones e
                        where e.objeto = p.oid::regprocedure::text)
  ) then
    raise exception 'Hay un consumidor de citas_episodios o conversion_cierres SIN declarar: los nucleos sirven filas de toda la empresa y cada llamador declara su puerta';
  end if;

  -- El ACL del nucleo, exacto: solo postgres (el mismo patron que
  -- conversion_episodios y capital_episodios). Un grant posterior es rojo.
  if exists (
    select 1 from pg_proc p
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     where p.oid = 'private.citas_episodios(timestamptz,timestamptz,timestamptz)'::regprocedure
       and a.grantee <> 'postgres'::regrole::oid
  ) then
    raise exception 'citas_episodios tiene EXECUTE para alguien mas que postgres';
  end if;

  return 'OK: ' || v_total || ' candidatos declarados y con huella vigente; ' || v_n || ' sujetos al techo ' || v_tope || ', ' || v_auxiliares || ' auxiliares verificados, 0 sin declarar';
end;
$function$
;
do $postflight$
begin
  perform private.assert_analitica_leads_citas();
  if (select tope from analitica_aux_preflight) is distinct from
      (select to_jsonb(t) from private.analitica_leads_citas_tope t where id)
    or (select otras from analitica_aux_preflight) is distinct from
      (select jsonb_agg(to_jsonb(e) order by objeto) from private.analitica_leads_citas_exenciones e
       where objeto not in ('crm.historial_decisiones_tasa_gerencia_fn(integer,text,text,integer,timestamp with time zone,uuid)','private.inversion_historica_estado(text,uuid)','private.inversion_historica_aplicar(uuid,jsonb)','crm.metricas_multiempresa_fn(date)','crm.cierres_externos_fn(date)','private.metricas_conversiones_implementacion(date,date,text)')) then
    raise exception 'La migración alteró el techo u otras declaraciones';
  end if;
end $postflight$;
commit;
