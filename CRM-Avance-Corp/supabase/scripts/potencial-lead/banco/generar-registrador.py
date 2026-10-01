#!/usr/bin/env python3
"""Genera el registrador de una migración aplicada con `db query --linked --file` (que NO registra).

  python3 banco/generar-registrador.py <version> <nombre> <salida.sql> <comprobación>...

Cada <comprobación> es una expresión de to_regprocedure/to_regclass que debe NO ser nula para dar
la migración por aplicada. El registrador lleva el archivo entero como única sentencia y su md5: si
la migración cambia, hay que volver a generarlo (los ciclos del banco comprueban que coinciden).
"""
import hashlib, io, os, sys

version, nombre, salida, *existen = sys.argv[1:]
aqui = os.path.dirname(os.path.abspath(__file__))
mig = io.open(os.path.join(aqui, "..", "..", "..", "migrations", f"{version}_{nombre}.sql"), encoding="utf-8").read()
assert "$mig$" not in mig, "la migración contiene el delimitador $mig$"
assert existen, "falta al menos una comprobación de objetos"
md5 = hashlib.md5(mig.encode("utf-8")).hexdigest()
condiciones = "\n    and ".join(f"{e} is not null" for e in existen)
texto = f"""-- REGISTRO en supabase_migrations.schema_migrations de {version}_{nombre}.
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración. Idempotente; se niega si
-- los objetos no están, o si la versión ya está registrada con otro nombre u otro contenido.
-- Generado con banco/generar-registrador.py. statements = el archivo entero (md5 {md5}).
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('{nombre}_registro'));
do $chk$
begin
  if (
    {condiciones}
  ) is not true then
    raise exception 'REGISTRO: la migración {version} no está aplicada; aplícala primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '{version}' and (coalesce(name, '') <> '{nombre}' or statements is distinct from array[$mig${mig}$mig$])) then
    raise exception 'REGISTRO: la versión {version} ya está registrada con otro nombre o contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('{version}', '{nombre}', array[$mig${mig}$mig$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '{version}' and name = '{nombre}' and cardinality(statements) = 1
                   and md5(statements[1]) = '{md5}') then
    raise exception 'REGISTRO: la fila {version} / {nombre} no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: {version} / {nombre} (1 sentencia: el archivo entero)';
end $post$;
commit;
"""
io.open(salida, "w", encoding="utf-8").write(texto)
print(f"{os.path.basename(salida)}: md5 de la migración {md5}")
