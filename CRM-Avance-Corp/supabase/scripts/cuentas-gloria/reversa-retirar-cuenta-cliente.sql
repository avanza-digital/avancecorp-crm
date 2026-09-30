-- REVERSA de 20260927012948_crm_retirar_cuenta_cliente (F4).
-- Se NIEGA si ya hay retiros registrados (una cuenta retirada no se reactiva: revertir solo
-- borraría su constancia) o si las piezas vivas no son las ensayadas (huella completa de las 5
-- funciones: cuerpo, DEFINER, search_path, comentario y EXECUTE sin el dueño). No toca la F3.
begin;
set local lock_timeout = '5s';
do $pre$
declare
  v_funciones integer;
  v_huella text;
begin
  if to_regclass('crm.cuentas_bancarias_retiros') is null then
    raise exception 'REVERSA: la F4 no está aplicada';
  end if;
  -- Bloqueo exclusivo antes de mirar: un retiro en curso termina (o espera) y no se pierde su constancia.
  lock table crm.cuentas_bancarias_retiros in access exclusive mode;
  if exists (select 1 from crm.cuentas_bancarias_retiros) then
    raise exception 'REVERSA: ya hay retiros de cuentas registrados; revertir borraría su constancia';
  end if;
  select count(*), pg_catalog.md5(pg_catalog.string_agg(linea, E'\n' order by linea))
    into v_funciones, v_huella
  from (
    select p.oid::regprocedure::text || '|' || pg_catalog.md5(p.prosrc) || '|' || p.prosecdef::text || '|'
           || coalesce(pg_catalog.array_to_string(p.proconfig, ','), '-') || '|'
           || coalesce(pg_catalog.md5(pg_catalog.obj_description(p.oid, 'pg_proc')), '-') || '|'
           || coalesce((select pg_catalog.string_agg(g, ',' order by g)
                        from (select case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end
                                     || ':' || a.privilege_type as g
                              from pg_catalog.aclexplode(p.proacl) a
                              where a.grantee <> p.proowner) acl), '-') as linea
    from pg_catalog.pg_proc p
    where p.oid in (
      select to_regprocedure(f) from pg_catalog.unnest(array[
        'private.trg_retiro_cuenta_inmutable()',
        'private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)',
        'crm.retirar_cuenta_cliente(uuid,uuid,uuid,text,text)',
        'private.retiros_cuentas_cliente_autorizado(uuid)',
        'crm.retiros_cuentas_cliente_fn(uuid)']) f)
  ) s;
  if v_funciones <> 5 or v_huella is distinct from '59937ad4b058238a5a1cf6ba60936644' then
    raise exception 'REVERSA: las piezas vivas no son las de la F4 ensayada (% funciones, huella %); no se toca',
      v_funciones, v_huella;
  end if;
end $pre$;

drop function crm.retiros_cuentas_cliente_fn(uuid);
drop function private.retiros_cuentas_cliente_autorizado(uuid);
drop function crm.retirar_cuenta_cliente(uuid,uuid,uuid,text,text);
drop function private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text);
drop table crm.cuentas_bancarias_retiros;
drop function private.trg_retiro_cuenta_inmutable();

do $chk$
begin
  if to_regclass('crm.cuentas_bancarias_retiros') is not null
     or to_regprocedure('crm.retirar_cuenta_cliente(uuid,uuid,uuid,text,text)') is not null
     or to_regprocedure('private.trg_retiro_cuenta_inmutable()') is not null then
    raise exception 'REVERSA: quedaron piezas de la F4';
  end if;
end $chk$;
notify pgrst, 'reload schema';
commit;
