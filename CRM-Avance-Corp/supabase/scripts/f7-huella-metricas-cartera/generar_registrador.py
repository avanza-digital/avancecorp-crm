#!/usr/bin/env python3
"""Genera registrar.sql: registra 20261013233000_crm_f7_redeclarar_huella_metricas_cartera en supabase_migrations.schema_migrations.
`db query --linked --file` NO registra; esto se corre DESPUÉS de aplicar la migración, por la misma vía. Uso (desde CRM-Avance-Corp/):
  python3 -I supabase/scripts/f7-huella-metricas-cartera/generar_registrador.py"""
import hashlib, os
V, N = '20261013233000', 'crm_f7_redeclarar_huella_metricas_cartera'
base = os.path.dirname(os.path.abspath(__file__))
mig = os.path.join(base, '..', '..', 'migrations', '%s_%s.sql' % (V, N))
c = open(mig, encoding='utf-8').read()
assert '$mig$' not in c
m = hashlib.md5(c.encode('utf-8')).hexdigest()
out = f"""-- REGISTRO en supabase_migrations.schema_migrations de {V}_{N} (F7: re-declarar la huella de crm.metricas_cartera_fn).
-- GENERADO por generar_registrador.py: no editar a mano. Desde `CRM-Avance-Corp/`, en este orden:
--   1. supabase db query --linked --file supabase/migrations/{V}_{N}.sql
--   2. supabase db query --linked --file supabase/scripts/f7-huella-metricas-cartera/registrar.sql
-- Registrado = sin error y la última fila «{V} | {m}». Un error = no registró nada (una transacción).
-- Idempotente. Se NIEGA, sin escribir, si la migración no está aplicada (huella del libro F7 distinta de 869853c2…), si el nombre
-- ya está con otra versión o si la versión ya está con otro nombre u otro contenido. statements = el archivo entero (md5 {m}).
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('{N}_registro'));
create temp table registro_{V} on commit drop as
select $mig${c}$mig$::text as contenido;
do $chk$
declare v_otras text;
begin
  if md5((select contenido from pg_temp.registro_{V})) is distinct from '{m}' then
    raise exception 'REGISTRO: el contenido incrustado no es el archivo de la migración';
  end if;
  if (select huella_md5 from private.f7_piezas_en_observacion where firma = 'crm.metricas_cartera_fn(date)')
     is distinct from '869853c25e903fe2f79245b8176c09b9' then
    raise exception 'REGISTRO: la migración {V} no está aplicada (la huella del libro F7 de crm.metricas_cartera_fn no es 869853c2…): no se registra';
  end if;
  select string_agg(s.version, ', ' order by s.version) into v_otras
    from supabase_migrations.schema_migrations s where s.name = '{N}' and s.version <> '{V}';
  if v_otras is not null then
    raise exception 'REGISTRO: el nombre {N} ya está registrado con otra versión (%)', v_otras;
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations s cross join pg_temp.registro_{V} r
             where s.version = '{V}' and (coalesce(s.name, '') <> '{N}' or s.statements is distinct from array[r.contenido])) then
    raise exception 'REGISTRO: la versión {V} ya está registrada con otro nombre u otro contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
select '{V}', '{N}', array[r.contenido] from pg_temp.registro_{V} r
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '{V}' and name = '{N}' and cardinality(statements) = 1 and md5(statements[1]) = '{m}') then
    raise exception 'REGISTRO: la fila {V} / {N} no quedó como se esperaba';
  end if;
end $post$;
commit;
-- Última fila, tras el COMMIT, para que `db query` muestre algo.
select '{V}' as version_registrada, '{m}' as md5_del_archivo;
"""
open(os.path.join(base, 'registrar.sql'), 'w', encoding='utf-8').write(out)
print('registrar.sql generado; md5 del archivo de la migración', m)
