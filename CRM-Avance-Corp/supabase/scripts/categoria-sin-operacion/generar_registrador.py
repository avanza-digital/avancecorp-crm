#!/usr/bin/env python3
"""Genera el registrador de 20261009180000_crm_categoria_sin_operacion_solo_nuevo (supabase_migrations.schema_migrations).

`supabase db query --linked --file` NO registra la migración: este archivo se corre DESPUÉS de aplicarla. Mismo formato que
el de 20261009120000 (supabase/scripts/categoria-por-operacion/generar_registrador.py). Idempotente; se niega si la guarda
no tiene el cuerpo que deja la migración (md5 de prosrc, calculado aquí del propio archivo) o si la versión ya está
registrada con otro nombre u otro contenido. statements = el archivo entero de la migración.

Uso:  python3 generar_registrador.py     (escribe registrar/20261009180000.sql junto a este script)
"""
import hashlib
import pathlib

AQUI = pathlib.Path(__file__).resolve().parent
MIGRACIONES = AQUI.parent.parent / "migrations"
SALIDA = AQUI / "registrar"

VERSION = "20261009180000"
NOMBRE = "crm_categoria_sin_operacion_solo_nuevo"

SALIDA.mkdir(exist_ok=True)
archivo = MIGRACIONES / f"{VERSION}_{NOMBRE}.sql"
texto = archivo.read_text(encoding="utf-8")
assert "$mig$" not in texto, f"{archivo.name} contiene $mig$"
md5 = hashlib.md5(texto.encode("utf-8")).hexdigest()
# El cuerpo de la guarda tal como lo guarda Postgres (prosrc = lo que va entre los dos $guarda$).
inicio = texto.index("as $guarda$") + len("as $guarda$")
cuerpo = texto[inicio:texto.index("$guarda$;", inicio)]
md5_cuerpo = hashlib.md5(cuerpo.encode("utf-8")).hexdigest()
assert texto.count(md5_cuerpo) == 2, "la migración tiene que citar la huella de su cuerpo en el preflight y en el postflight"
# Condición SQL que prueba que la migración está aplicada: la guarda con el cuerpo nuevo y su trigger habilitado.
CONDICION = f"""exists (select 1 from pg_proc p
                 where p.oid = to_regprocedure('private.trg_contrato_categoria_por_operacion()')
                   and md5(p.prosrc) = '{md5_cuerpo}')
    and exists (select 1 from pg_trigger t where t.tgrelid = 'public.contratos'::regclass
                 and t.tgname = 'trg_contratos_01_categoria_por_operacion' and t.tgenabled = 'O')"""
sql = f"""-- REGISTRO en supabase_migrations.schema_migrations de {VERSION}_{NOMBRE}.
-- GENERADO por generar_registrador.py: no editar a mano. `db query --linked --file` NO registra: correr DESPUÉS de aplicar la
-- migración. Idempotente; se niega si la guarda no tiene el cuerpo nuevo (md5 de prosrc {md5_cuerpo}), o si la versión ya
-- está registrada con otro nombre u otro contenido. statements = el archivo entero (md5 {md5}).
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
print(f"{VERSION}.sql  md5 del archivo {md5} · md5 del cuerpo de la guarda {md5_cuerpo}")
