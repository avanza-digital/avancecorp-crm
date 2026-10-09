-- REVERSA (esquema) de 20261009120000_crm_categoria_contrato_por_operacion.sql
--
-- Retira los dos triggers (la prevención en public.contratos y la sincronización en crm.operaciones_cartera), la puerta
-- crm.corregir_categoria_contrato_fn y el núcleo private.fijar_categoria_contrato. Todo lo demás queda como estaba antes
-- de la migración (no tocó ninguna otra pieza).
--
-- NO TOCA DATOS: los contratos que la puerta (o la sincronización) dejaron en 'upgrade'/'renovacion' siguen así, y la
-- bitácora (public.audit_log, crm.ledger_rentabilidad) no se borra nunca. Para devolver los 12 de septiembre a 'nuevo' hay
-- que correr DESPUÉS reversa-datos.sql (solo con su mes abierto). Va en ese orden a propósito: mientras exista la
-- prevención, ninguna vía —tampoco la puerta— puede dejar en 'nuevo' un contrato cuya operación es 'upgrade'.
-- La fila de supabase_migrations.schema_migrations se conserva (regla de la casa): anotar la reversa en MIGRACIONES.md.
--
-- SE NIEGA si lo que hay no es exactamente lo que dejó la migración (cuerpos, triggers) o si otra función llama a la puerta
-- o al núcleo por su nombre (pg_depend no ve las llamadas hechas desde plpgsql).
-- Transporte: `db query --linked -f` la manda como UN solo mensaje; si algo falla a mitad, se corta ahí, la conexión se
-- cierra y Postgres suelta la transacción y el candado de sesión de migraciones (probado en el banco). Aun así, antes de
-- reintentar, comprobar que ese candado se soltó (consulta a pg_locks en LEEME.md, «Transporte»).

-- Exclusión de migraciones (el mismo candado que la migración).
begin;
set local lock_timeout = '5s';
select pg_advisory_lock(hashtext('crm_migracion_funciones'));
commit;

begin;
set transaction isolation level repeatable read;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local search_path = '';

do $preflight$
declare
  r record;
begin
  for r in select * from (values
    ('crm.corregir_categoria_contrato_fn(uuid,text,text)', '343be63ecd244de16ede8bf092d893df'),
    ('private.fijar_categoria_contrato(uuid,text,text,text,uuid)', '09f95007689ce1712ab164b1181f635d'),
    ('private.trg_contrato_categoria_por_operacion()', 'e15e801dd952191be3bae764da3f209f'),
    ('private.trg_operacion_cartera_fija_categoria()', 'ea9e412c6cc2fe5ef60136bca86c927f')
  ) as v(firma, huella) loop
    if not exists (select 1 from pg_catalog.pg_proc p where p.oid = to_regprocedure(r.firma) and md5(p.prosrc) = r.huella) then
      raise exception 'REVERSA categoría: % no es la que dejó la migración (o no existe)', r.firma using errcode = 'P0409';
    end if;
  end loop;
  if not exists (select 1 from pg_catalog.pg_trigger t
                  where t.tgrelid = 'public.contratos'::regclass and t.tgname = 'trg_contratos_01_categoria_por_operacion'
                    and t.tgfoid = 'private.trg_contrato_categoria_por_operacion()'::regprocedure)
     or not exists (select 1 from pg_catalog.pg_trigger t
                     where t.tgrelid = 'crm.operaciones_cartera'::regclass and t.tgname = 'trg_operaciones_cartera_10_fija_categoria'
                       and t.tgfoid = 'private.trg_operacion_cartera_fija_categoria()'::regprocedure) then
    raise exception 'REVERSA categoría: los triggers no son los que dejó la migración' using errcode = 'P0409';
  end if;
  -- Nadie más llama a la puerta ni al núcleo (una llamada desde plpgsql no deja dependencia).
  if exists (select 1 from pg_catalog.pg_proc p
              where (p.prosrc ~* 'corregir_categoria_contrato_fn' or p.prosrc ~* 'fijar_categoria_contrato')
                and p.oid not in ('crm.corregir_categoria_contrato_fn(uuid,text,text)'::regprocedure,
                                  'private.trg_operacion_cartera_fija_categoria()'::regprocedure,
                                  'private.fijar_categoria_contrato(uuid,text,text,text,uuid)'::regprocedure)) then
    raise exception 'REVERSA categoría: otra función llama a la puerta o al núcleo; revisar antes de revertir' using errcode = 'P0409';
  end if;
end;
$preflight$;

drop trigger trg_contratos_01_categoria_por_operacion on public.contratos;
drop trigger trg_operaciones_cartera_10_fija_categoria on crm.operaciones_cartera;
drop function crm.corregir_categoria_contrato_fn(uuid, text, text);
drop function private.trg_operacion_cartera_fija_categoria();
drop function private.trg_contrato_categoria_por_operacion();
drop function private.fijar_categoria_contrato(uuid, text, text, text, uuid);

-- Postflight: no queda nada de la migración y los triggers previos son los de antes (los 15 de R7 y los 2 de la cartera).
set local search_path = public;   -- las huellas de los triggers se midieron con public en el search_path
do $postflight$
begin
  if to_regprocedure('crm.corregir_categoria_contrato_fn(uuid,text,text)') is not null
     or to_regprocedure('private.fijar_categoria_contrato(uuid,text,text,text,uuid)') is not null
     or to_regprocedure('private.trg_operacion_cartera_fija_categoria()') is not null
     or to_regprocedure('private.trg_contrato_categoria_por_operacion()') is not null then
    raise exception 'REVERSA categoría postflight: queda alguna función de la migración';
  end if;
  if (select md5(string_agg(t.tgname || '|' || pg_get_triggerdef(t.oid), E'\n' order by t.tgname))
        from pg_trigger t where t.tgrelid = 'public.contratos'::regclass and not t.tgisinternal)
       is distinct from '7acf3de332dc5c670f013dbc4ee64f6f'
     or (select md5(string_agg(t.tgname || '|' || pg_get_triggerdef(t.oid), E'\n' order by t.tgname))
           from pg_trigger t where t.tgrelid = 'crm.operaciones_cartera'::regclass and not t.tgisinternal)
       is distinct from '442178a6bbfc450b23223d74df6cfb7e' then
    raise exception 'REVERSA categoría postflight: los triggers no volvieron a ser los de antes de la migración';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
select 'REVERSA categoría: esquema revertido' as resultado;
commit;
select pg_advisory_unlock(hashtext('crm_migracion_funciones'));
