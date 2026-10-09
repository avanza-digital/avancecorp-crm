-- REVERSA de 20261009180000_crm_categoria_sin_operacion_solo_nuevo.sql
--
-- Devuelve la guarda private.trg_contrato_categoria_por_operacion() EXACTAMENTE a la de 20261009120000 (con operación, la
-- categoría es la de la operación; sin operación no se restringe) y su comentario. El trigger (y su comentario), la puerta,
-- el núcleo y la sincronización no se tocan (esta migración tampoco los tocó).
-- NO TOCA DATOS: los contratos que quedaron como estaban siguen igual. La fila de supabase_migrations.schema_migrations se
-- conserva (regla de la casa): anotar la reversa en MIGRACIONES.md.
-- ORDEN: si además hay que revertir 20261009120000, esta va ANTES (categoria-por-operacion/reversa.sql comprueba que la
-- guarda es la de 20261009120000 y se niega con la de esta migración).
--
-- SE NIEGA (P0409) si la guarda vigente no es la que dejó 20261009180000 (cuerpo, dueño, seguridad, search_path, permisos),
-- si los 16 triggers de public.contratos no son los medidos o si el trigger de la guarda cambió de forma.
-- Postflight: la guarda vuelve a tener la huella medida en producción el 09/10 antes de 20261009180000
-- (md5 de pg_get_functiondef 8fdd5f1a3d74c073d5fe3327968132b9; prosrc e15e801dd952191be3bae764da3f209f), mismo dueño y
-- permisos, y el comentario de 20261009120000.
-- Transporte: `db query --linked -f` la manda como UN solo mensaje; si algo falla a mitad, no se aplica nada, la conexión
-- se cierra y Postgres suelta la transacción y el candado de sesión de migraciones. Aun así, antes de reintentar, comprobar
-- que ese candado se soltó (consulta a pg_locks en categoria-por-operacion/LEEME.md, «Transporte»).

-- Exclusión de migraciones (el mismo candado que la migración).
begin;
set local lock_timeout = '5s';
select pg_advisory_lock(hashtext('crm_migracion_funciones'));
commit;

begin;
set transaction isolation level read committed;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local quote_all_identifiers = off;
set local search_path = public;   -- las huellas se midieron con public en el search_path

do $preflight$
begin
  if not exists (select 1 from pg_proc p
                  where p.oid = to_regprocedure('private.trg_contrato_categoria_por_operacion()')
                    and md5(p.prosrc) = 'b8f9c14e5da959c6237b2d00df8423ae'
                    and p.proowner = 'postgres'::regrole and p.prosecdef
                    and p.proconfig = array['search_path=""']
                    and p.proacl::text = '{postgres=X/postgres}') then
    raise exception 'REVERSA categoría sin operación: la guarda vigente no es la que dejó 20261009180000; revisar'
      using errcode = 'P0409';
  end if;
  if (select md5(string_agg(t.tgname || '|' || pg_get_triggerdef(t.oid), E'\n' order by t.tgname))
        from pg_trigger t where t.tgrelid = 'public.contratos'::regclass and not t.tgisinternal)
       is distinct from '93a6e99cd87c7add3f3357a937c6ebda'
     or exists (select 1 from pg_trigger t
                 where t.tgrelid = 'public.contratos'::regclass and not t.tgisinternal and t.tgenabled <> 'O')
     or not exists (select 1 from pg_trigger t
                     where t.tgrelid = 'public.contratos'::regclass and t.tgname = 'trg_contratos_01_categoria_por_operacion'
                       and t.tgenabled = 'O' and t.tgtype = 17 and t.tgattr::text = '' and t.tgqual is not null
                       and pg_get_triggerdef(t.oid) like '%WHEN ((old.categoria IS DISTINCT FROM new.categoria))%'
                       and t.tgfoid = 'private.trg_contrato_categoria_por_operacion()'::regprocedure) then
    raise exception 'REVERSA categoría sin operación: los triggers de public.contratos no son los medidos; revisar'
      using errcode = 'P0409';
  end if;
end;
$preflight$;

set local search_path = '';

-- La guarda de 20261009120000, copiada byte a byte de esa migración.
create or replace function private.trg_contrato_categoria_por_operacion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $guarda$
declare
  v_tipo text;
begin
  if new.categoria is not distinct from old.categoria then
    return new;
  end if;
  -- Solo READ COMMITTED, ANTES de buscar la operación: con una foto vieja (REPEATABLE READ o SERIALIZABLE) esta consulta
  -- no vería una operación confirmada después de la foto, y la categoría quedaría distinta de la operación sin aviso.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La categoría de un contrato solo se cambia en una transacción READ COMMITTED'
      using errcode = '25001',
            hint = 'La API ya trabaja en READ COMMITTED. En SQL: BEGIN ISOLATION LEVEL READ COMMITTED.';
  end if;
  select o.tipo into v_tipo from crm.operaciones_cartera o where o.contrato_nuevo_id = new.id;
  if found and new.categoria is distinct from v_tipo then
    raise exception 'La categoría la decide la operación de cartera'
      using errcode = '23514',
            detail = format('El contrato tiene una operación de cartera de tipo %s; su categoría no puede quedar como %s.',
                            v_tipo, coalesce(new.categoria, 'vacía')),
            hint = 'La categoría de un contrato con operación de cartera es la de su operación.';
  end if;
  return new;
end;
$guarda$;

comment on function private.trg_contrato_categoria_por_operacion() is
  'Una categoría solo cambia en READ COMMITTED (25001). Si el contrato tiene operación de cartera, su categoría no puede quedar distinta de la operación (23514 «La categoría la decide la operación de cartera»). Sin operación no restringe (contratos antiguos).';

set local search_path = public;
do $postflight$
begin
  if not exists (select 1 from pg_proc p
                  where p.oid = 'private.trg_contrato_categoria_por_operacion()'::regprocedure
                    and md5(pg_get_functiondef(p.oid)) = '8fdd5f1a3d74c073d5fe3327968132b9'
                    and md5(p.prosrc) = 'e15e801dd952191be3bae764da3f209f'
                    and p.proowner = 'postgres'::regrole and p.prosecdef
                    and p.proconfig = array['search_path=""']
                    and p.proacl::text = '{postgres=X/postgres}') then
    raise exception 'REVERSA categoría sin operación postflight: la guarda no volvió a ser la de 20261009120000';
  end if;
  if obj_description('private.trg_contrato_categoria_por_operacion()'::regprocedure, 'pg_proc') is distinct from
       'Una categoría solo cambia en READ COMMITTED (25001). Si el contrato tiene operación de cartera, su categoría no puede quedar distinta de la operación (23514 «La categoría la decide la operación de cartera»). Sin operación no restringe (contratos antiguos).'
     then
    raise exception 'REVERSA categoría sin operación postflight: el comentario no volvió a ser el de 20261009120000';
  end if;
  if (select md5(string_agg(t.tgname || '|' || pg_get_triggerdef(t.oid), E'\n' order by t.tgname))
        from pg_trigger t where t.tgrelid = 'public.contratos'::regclass and not t.tgisinternal)
       is distinct from '93a6e99cd87c7add3f3357a937c6ebda' then
    raise exception 'REVERSA categoría sin operación postflight: los triggers de public.contratos cambiaron';
  end if;
end;
$postflight$;

select 'REVERSA categoría sin operación: la guarda vuelve a la de 20261009120000' as resultado;
commit;
select pg_advisory_unlock(hashtext('crm_migracion_funciones'));
