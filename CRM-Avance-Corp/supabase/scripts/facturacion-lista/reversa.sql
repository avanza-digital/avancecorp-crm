-- Reversa 3B, ANTES de la reversa 3A. Solo piezas conocidas, sin CASCADE.
begin;
set transaction isolation level repeatable read;
set local lock_timeout = '10s';
set local statement_timeout = '120s';
-- INICIO TRANSACCION
do $reversa$
declare
  v_funcion record;
  v_puerta oid := to_regprocedure('crm.listar_operaciones_facturacion_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)');
  v_nucleo oid := to_regprocedure('private.facturacion_lista(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)');
  v_catalogo record;
begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where ((n.nspname = 'private' and p.proname = 'facturacion_lista')
        or (n.nspname = 'crm' and p.proname = 'listar_operaciones_facturacion_fn'))
      and p.oid is distinct from to_regprocedure(n.nspname || '.' || p.proname ||
        '(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)')) then
    raise exception 'REVERSA 3B: firma anterior o sobrecarga inesperada; usar su kit conocido';
  end if;
  if v_puerta is null and v_nucleo is null then
    raise notice 'REVERSA 3B ya completa';
    return;
  end if;
  if (v_puerta is not null and v_nucleo is not null) is not true then
    raise exception 'REVERSA 3B: instalación parcial; revisar a mano';
  end if;
  -- Las dependencias SQL en texto no están en pg_depend. Complemento al DROP sin CASCADE.
  if (not exists (select 1 from pg_proc p
    where (p.prosrc ~* 'crm\.listar_operaciones_facturacion_fn\s*\(')
       or (p.prosrc ~* 'private\.facturacion_lista\s*\(' and p.oid <> v_puerta))) is not true then
    raise exception 'REVERSA 3B: otra función usa la puerta o el núcleo; revertir primero ese consumidor';
  end if;
  drop table if exists pg_temp.f3b_funciones;
  create temporary table f3b_funciones (
    firma text primary key, nueva text, definidor boolean, lenguaje text, acl text, dependencia boolean
  ) on commit drop;
-- INICIO HUELLAS
  insert into pg_temp.f3b_funciones values
    ('private.facturacion_lista(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)', 'e8c3178b74ec5718e87b5b5fc697e1fd', false, 'plpgsql', '{postgres=X/postgres}', false),
    ('crm.listar_operaciones_facturacion_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)', '3b84fe0660b2257398edfd835828f3eb', true, 'sql', '{postgres=X/postgres,authenticated=X/postgres}', false);
-- FIN HUELLAS
  for v_funcion in select * from pg_temp.f3b_funciones loop
    select md5(pg_get_functiondef(p.oid)) as huella, pg_get_userbyid(p.proowner) as dueno,
      p.proacl::text as acl, p.prosecdef as definidor, p.provolatile as volatilidad,
      l.lanname as lenguaje, p.proconfig as configuracion
    into v_catalogo from pg_proc p join pg_language l on l.oid = p.prolang
    where p.oid = to_regprocedure(v_funcion.firma);
    if (v_catalogo.huella = v_funcion.nueva and v_catalogo.dueno = 'postgres'
        and v_catalogo.acl = v_funcion.acl and v_catalogo.definidor = v_funcion.definidor
        and v_catalogo.volatilidad = 's' and v_catalogo.lenguaje = v_funcion.lenguaje
        and cardinality(v_catalogo.configuracion) = 1
        and v_catalogo.configuracion[1] in ('search_path=', 'search_path=""')) is not true then
      raise exception 'REVERSA 3B: huella/contrato inesperado en %: %', v_funcion.firma, row_to_json(v_catalogo);
    end if;
  end loop;
  drop function crm.listar_operaciones_facturacion_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer);
  drop function private.facturacion_lista(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer);
  if (to_regprocedure('crm.listar_operaciones_facturacion_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)') is null
      and to_regprocedure('private.facturacion_lista(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)') is null) is not true then
    raise exception 'REVERSA 3B: quedaron piezas instaladas';
  end if;
  raise notice 'REVERSA 3B PASS: dos funciones retiradas; la 3A queda intacta';
end $reversa$;
-- FIN TRANSACCION
commit;
