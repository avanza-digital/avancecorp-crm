-- Eliminación puntual solicitada expresamente por Miguel el 25/09/2026.
-- Sólo la identidad exacta y sin referencias de negocio; cualquier diferencia
-- aborta la transacción. Usa la purga auditada ya instalada, sin cambiar permisos.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
set local row_security=off;
do $operacion$
declare
  v_id constant uuid := 'f1d1645d-d586-4279-b72c-b64045e72263';
  v_nombre constant text := 'ALVARO LEOMAR CCAHUANA ALHUIRCA';
  v_fk record;
  v_existe boolean;
  v_purgas_antes bigint;
begin
  if not (select rolsuper or rolbypassrls from pg_roles where rolname=current_user) then
    raise exception 'La comprobación completa requiere un operador sin filtrado RLS';
  end if;
  if exists (
    select 1 from pg_constraint c
    where c.contype='f' and c.confrelid in
      ('public.perfiles'::regclass,'crm.equipo'::regclass,'auth.users'::regclass)
      and (array_length(c.conkey,1)<>1 or c.confkey<>array[(select attnum from pg_attribute
        where attrelid=c.confrelid and attname=case when c.confrelid='crm.equipo'::regclass then 'perfil_id' else 'id' end)]::smallint[])
  ) then raise exception 'Hay referencias de estructura no contemplada'; end if;
  perform pg_advisory_xact_lock(hashtextextended('crm.equipo.usuarios_jerarquia',0));
  perform 1 from auth.users where id=v_id for update;
  if not found then raise exception 'La cuenta esperada no existe'; end if;
  perform 1 from public.perfiles where id=v_id and nombre_completo=v_nombre and rol='comercial' for update;
  if not found then raise exception 'La identidad o el rol no coincide'; end if;
  perform 1 from crm.equipo where perfil_id=v_id and rol_crm='vendedor' for update;
  if not found then raise exception 'La membresía esperada no coincide'; end if;
  -- Las FK impiden que entren referencias nuevas mientras conservamos los locks.
  -- No se permite borrar ni desatribuir seguimiento, actividad, venta o cartera.
  for v_fk in
    select n.nspname as esquema,t.relname as tabla,a.attname as columna
    from pg_constraint c join pg_class t on t.oid=c.conrelid
      join pg_namespace n on n.oid=t.relnamespace
      join pg_attribute a on a.attrelid=c.conrelid and a.attnum=c.conkey[1]
    where c.contype='f' and c.confrelid in
      ('public.perfiles'::regclass,'crm.equipo'::regclass,'auth.users'::regclass)
      and array_length(c.conkey,1)=1
      and not (n.nspname='auth')
      and not (c.conrelid='public.perfiles'::regclass and a.attname='id')
      and not (c.conrelid='crm.equipo'::regclass and a.attname='perfil_id')
    order by n.nspname,t.relname,a.attname
  loop
    execute format('select exists(select 1 from %I.%I where %I=$1)',v_fk.esquema,v_fk.tabla,v_fk.columna)
      into v_existe using v_id;
    if v_existe then
      raise exception 'La cuenta tiene dependencias en %.%; transferir o revisar antes de eliminar',v_fk.esquema,v_fk.tabla;
    end if;
  end loop;
  if exists(select 1 from storage.objects where owner_id=v_id::text) then
    raise exception 'La cuenta conserva archivos propios; transferir antes de eliminar';
  end if;
  select count(*) into v_purgas_antes from private.membresias_purgadas where perfil_id=v_id;
  perform crm.purgar_membresia_crm(v_id,
    'Eliminación definitiva solicitada expresamente por Miguel el 25/09/2026; analista sin seguimientos, actividades, leads, tareas, clientes ni referencias de negocio.');
  delete from auth.users where id=v_id;
  if exists(select 1 from public.perfiles where id=v_id)
    or exists(select 1 from crm.equipo where perfil_id=v_id)
    or exists(select 1 from auth.users where id=v_id)
    or (select count(*) from private.membresias_purgadas where perfil_id=v_id)<>v_purgas_antes+1 then
    raise exception 'La eliminación no quedó completa y auditada';
  end if;
end $operacion$;
commit;
