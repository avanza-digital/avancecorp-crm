-- Aprobado por Miguel: nombres de clientes en Facturación para Coordinación, solo lectura.
-- Añade dos funciones. No modifica RPC v1, RLS, tablas, fórmulas ni permisos de escritura.
-- Backend primero: v1 conserva su contrato para las pestañas ya abiertas; el frontend nuevo usa v2.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '30s';
do $nuevos$
declare r record;
begin
  for r in select * from (values
    ('private.facturacion_lista_nombres(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)', '1f611c3a29e3c5594d6baa8243c56700'),
    ('crm.listar_operaciones_facturacion_v2_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)', '65b5ac0014d67b23024fe3208fb05b50')
  ) f(firma,huella) loop
    if (select md5(prosrc) from pg_proc where oid=to_regprocedure(r.firma)) is distinct from r.huella then
      raise exception 'Facturación nombres: cuerpo v2 inesperado en %',r.firma;
    end if;
  end loop;
end $nuevos$;
do $originales$
declare r record;
begin
  for r in select * from (values
    ('private.facturacion_lista(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)', 'f98f0bea3397cb7f054e4f25b6ae5cb8'),
    ('crm.listar_operaciones_facturacion_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)', '3b84fe0660b2257398edfd835828f3eb')
  ) f(firma,huella) loop
    if md5(pg_get_functiondef(to_regprocedure(r.firma))) is distinct from r.huella then
      raise exception 'Facturación nombres: función publicada cambió en %; se deshace todo',r.firma;
    end if;
  end loop;
end $originales$;
drop function crm.listar_operaciones_facturacion_v2_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer);
drop function private.facturacion_lista_nombres(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer);
commit;
