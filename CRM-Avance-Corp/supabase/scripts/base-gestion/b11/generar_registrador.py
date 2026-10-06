#!/usr/bin/env python3
"""Genera supabase/scripts/base-gestion/registrar/20261006042144.sql a partir del archivo FINAL de la migración.

`supabase db query --linked --file` NO registra la versión en supabase_migrations.schema_migrations: el registrador se
corre DESPUÉS de aplicar (mismo formato que los de B7–B10: statements = el archivo entero, en una sola sentencia).
Uso: python3 supabase/scripts/base-gestion/b11/generar_registrador.py
"""
import hashlib, os
AQUI = os.path.dirname(os.path.abspath(__file__))
VERSION, NOMBRE = '20261006042144', 'crm_bases_cargadas_conversion'
mig = open(os.path.join(AQUI, '..', '..', '..', 'migrations', f'{VERSION}_{NOMBRE}.sql'), encoding='utf-8').read()
assert '$mig$' not in mig, 'la migración contiene $mig$: cambiar la etiqueta del dólar-quote'
assert '$chk$' not in mig, 'la migración contiene $chk$: la primera copia va dentro de do $chk$'
md5 = hashlib.md5(mig.encode('utf-8')).hexdigest()
sql = f"""-- REGISTRO en supabase_migrations.schema_migrations de {VERSION}_{NOMBRE}.
-- GENERADO por b11/generar_registrador.py: no editar a mano. `db query --linked --file` NO registra: correr DESPUÉS de
-- aplicar la migración. Idempotente; se niega si los objetos no están, o si la versión ya está registrada con otro nombre u
-- otro contenido. Mismo formato que los registradores de B7–B10. statements = el archivo entero (md5 {md5}).
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('{NOMBRE}_registro'));
do $chk$
begin
  if (
    to_regprocedure('private.conversion_origen_con_cierre(text)') is not null
    and pg_get_function_result(to_regprocedure('private.conversion_divisor_empresa(date,date)')) like '%cierres_base_cargada integer)'
    and pg_get_function_result(to_regprocedure('private.conversion_divisor_empresa_totales(date,date)')) like '%cierres_base_cargada integer)'
    and (select p.prosrc like '%''base_cargada'', v_totales.cierres_base_cargada%' from pg_proc p
          where p.oid = to_regprocedure('crm.conversion_divisor_coordinacion_fn(date,date,date)'))
  ) is not true then
    raise exception 'REGISTRO: la migración {VERSION} no está aplicada; aplícala primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '{VERSION}' and (coalesce(name, '') <> '{NOMBRE}' or statements is distinct from array[$mig${mig}$mig$])) then
    raise exception 'REGISTRO: la versión {VERSION} ya está registrada con otro nombre o contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('{VERSION}', '{NOMBRE}', array[$mig${mig}$mig$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '{VERSION}' and name = '{NOMBRE}' and cardinality(statements) = 1
                   and md5(statements[1]) = '{md5}') then
    raise exception 'REGISTRO: la fila {VERSION} / {NOMBRE} no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: {VERSION} / {NOMBRE} (1 sentencia: el archivo entero)';
end $post$;
commit;
"""
salida = os.path.join(AQUI, '..', 'registrar', f'{VERSION}.sql')
open(salida, 'w', encoding='utf-8').write(sql)
print('escrito', os.path.normpath(salida), 'md5 de la migración', md5)
