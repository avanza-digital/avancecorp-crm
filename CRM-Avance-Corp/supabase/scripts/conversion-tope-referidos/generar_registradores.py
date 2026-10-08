#!/usr/bin/env python3
"""Genera los registradores de las dos migraciones del tope de referidos (supabase_migrations.schema_migrations).

`supabase db query --linked --file` NO registra la migración: estos archivos se corren DESPUÉS de aplicarla, mismo formato que los
registradores de Bases cargadas (supabase/scripts/base-gestion/registrar/). Idempotentes; se niegan si los objetos no están o si la
versión ya está registrada con otro nombre u otro contenido. statements = el archivo entero de la migración.

Uso:  python3 generar_registradores.py     (escribe registrar/<version>.sql junto a este script)
"""
import hashlib
import pathlib

AQUI = pathlib.Path(__file__).resolve().parent
MIGRACIONES = AQUI.parent.parent / "migrations"
SALIDA = AQUI / "registrar"

# version, nombre, condición SQL que prueba que la migración está aplicada
MIGS = [
    (
        "20261007160937",
        "crm_conversion_tope_referidos",
        """to_regprocedure('private.tope_referidos_conversion(date)') is not null
    and to_regprocedure('private.conversion_origen_base_tope(text)') is not null
    and exists (select 1 from information_schema.columns
                 where table_schema = 'crm' and table_name = 'periodos_cerrados' and column_name = 'tope_referidos_pct')
    and exists (select 1 from information_schema.columns
                 where table_schema = 'crm' and table_name = 'conversion_pesos' and column_name = 'tope_referidos_pct')""",
    ),
    (
        "20261007203000",
        "crm_conversion_tope_referidos_origen",
        """to_regprocedure('private.referidos_aporte_por_analista(timestamptz,timestamptz,date,boolean,uuid[],numeric)') is not null
    and (select p.prosrc like '%referidos_aporte%' from pg_proc p
          where p.oid = to_regprocedure('crm.cerrar_periodo(date)'))""",
    ),
]

SALIDA.mkdir(exist_ok=True)
for version, nombre, condicion in MIGS:
    archivo = MIGRACIONES / f"{version}_{nombre}.sql"
    texto = archivo.read_text(encoding="utf-8")
    assert "$mig$" not in texto, f"{archivo.name} contiene $mig$"
    md5 = hashlib.md5(texto.encode("utf-8")).hexdigest()
    sql = f"""-- REGISTRO en supabase_migrations.schema_migrations de {version}_{nombre}.
-- GENERADO por generar_registradores.py: no editar a mano. `db query --linked --file` NO registra: correr DESPUÉS de aplicar la
-- migración. Idempotente; se niega si los objetos no están, o si la versión ya está registrada con otro nombre u otro contenido.
-- statements = el archivo entero (md5 {md5}).
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('{nombre}_registro'));
do $chk$
begin
  if (
    {condicion}
  ) is not true then
    raise exception 'REGISTRO: la migración {version} no está aplicada; aplícala primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '{version}' and (coalesce(name, '') <> '{nombre}' or statements is distinct from array[$mig$"""
    sql += texto
    sql += f"""$mig$])) then
    raise exception 'REGISTRO: la versión {version} ya está registrada con otro nombre u otro contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('{version}', '{nombre}', array[$mig$"""
    sql += texto
    sql += f"""$mig$])
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
    (SALIDA / f"{version}.sql").write_text(sql, encoding="utf-8")
    print(f"{version}.sql  md5 del archivo {md5}")
