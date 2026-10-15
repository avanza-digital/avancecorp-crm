#!/usr/bin/env python3
"""Genera el registrador de 20261015000852_crm_plazo_carga_mes (supabase_migrations.schema_migrations).

`supabase db query --linked --file` NO registra la migración: este archivo se corre DESPUÉS de aplicarla. Mismo formato
que los registradores de categoría por operación (supabase/scripts/categoria-por-operacion/generar_registrador.py).
Idempotente; se niega si los objetos no están o si la versión ya está registrada con otro nombre u otro contenido.
statements = el archivo entero de la migración.

Uso:  python3 generar_registrador.py     (escribe registrar/20261015000852.sql junto a este script)
"""
import hashlib
import pathlib

AQUI = pathlib.Path(__file__).resolve().parent
MIGRACIONES = AQUI.parent.parent / "migrations"
SALIDA = AQUI / "registrar"

VERSION = "20261015000852"
NOMBRE = "crm_plazo_carga_mes"
# Condición SQL que prueba que la migración está aplicada: las dos tablas, las dos puertas, el núcleo y el CHECK nuevo.
CONDICION = """to_regclass('crm.plazos_carga_mes') is not null
    and to_regclass('crm.reaperturas_mes') is not null
    and to_regprocedure('crm.fijar_plazo_carga_mes(date,date,text)') is not null
    and to_regprocedure('crm.plazos_carga_mes_fn()') is not null
    and to_regprocedure('private.reabrir_mes(date,text,uuid)') is not null
    and to_regprocedure('private.reapertura_autoriza(date,uuid)') is not null
    and to_regprocedure('private.fijar_plazo_carga(date,date,text,uuid)') is not null
    and exists (select 1 from pg_constraint c where c.conrelid = 'crm.conversion_acreditaciones'::regclass
                 and c.conname = 'conversion_acreditaciones_plazo_minimo_check')"""

SALIDA.mkdir(exist_ok=True)
archivo = MIGRACIONES / f"{VERSION}_{NOMBRE}.sql"
texto = archivo.read_text(encoding="utf-8")
assert "$mig$" not in texto, f"{archivo.name} contiene $mig$"
md5 = hashlib.md5(texto.encode("utf-8")).hexdigest()
sql = f"""-- REGISTRO en supabase_migrations.schema_migrations de {VERSION}_{NOMBRE}.
-- GENERADO por generar_registrador.py: no editar a mano. `db query --linked --file` NO registra: correr DESPUÉS de aplicar la
-- migración. Idempotente; se niega si los objetos no están, o si la versión ya está registrada con otro nombre u otro contenido.
-- statements = el archivo entero (md5 {md5}).
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('{NOMBRE}_registro'));
do $chk$
begin
  if (
    {CONDICION}
  ) is not true then
    raise exception 'REGISTRO: la migración {VERSION} no está aplicada; aplícala primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '{VERSION}' and (coalesce(name, '') <> '{NOMBRE}' or statements is distinct from array[$mig$"""
sql += texto
sql += f"""$mig$])) then
    raise exception 'REGISTRO: la versión {VERSION} ya está registrada con otro nombre u otro contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('{VERSION}', '{NOMBRE}', array[$mig$"""
sql += texto
sql += f"""$mig$])
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
select '{VERSION}' as version_registrada, '{md5}' as md5_del_archivo;
commit;
"""
(SALIDA / f"{VERSION}.sql").write_text(sql, encoding="utf-8")
print(f"{VERSION}.sql  md5 del archivo {md5}")
