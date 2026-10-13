#!/usr/bin/env python3
"""Genera el registrador de 20261013145852_crm_realizacion_cuenta_anticipada (supabase_migrations.schema_migrations).

`supabase db query --linked --file` NO registra la migración: este archivo se corre DESPUÉS de aplicarla, por la misma vía. Formato de la
casa (el de los registradores del grupo A, `supabase/scripts/anular-venta-mes-sellado/generar_registrador.py`): exige el ESTADO que deja
la migración —de `private.metricas_reuniones_implementacion(date,date)`: cuerpo, definición entera, ficha, ACL efectiva y comentario; la
huella re-sellada de su exención analítica, el sello coincidente con la lista y el censo reconociéndola—, cada valor leído aquí del
POSTFLIGHT de la migración (tiene que aparecer exactamente una vez o el generador aborta); se niega si el mismo NOMBRE ya está registrado
con otra versión (p. ej. 20261007205643, la fecha antigua) o la versión con otro contenido. Idempotente; statements = el archivo entero,
incrustado UNA sola vez en una tabla temporal `on commit drop`.

Uso:  python3 generar_registrador.py     (escribe registrar/20261013145852.sql junto a este script)
"""
import hashlib
import pathlib
import re

AQUI = pathlib.Path(__file__).resolve().parent
MIGRACIONES = AQUI.parent.parent / "migrations"
SALIDA = AQUI / "registrar"

VERSION = "20261013145852"
NOMBRE = "crm_realizacion_cuenta_anticipada"
TABLA = f"registro_{VERSION}"

archivo = MIGRACIONES / f"{VERSION}_{NOMBRE}.sql"
texto = archivo.read_text(encoding="utf-8")
for etiqueta in ("$mig$", "$chk$", "$post$"):
    assert etiqueta not in texto, f"{archivo.name} contiene {etiqueta}: cambiar la etiqueta del dólar-quote del registrador"
assert "\r" not in texto and "\x00" not in texto, f"{archivo.name} tiene CR o NUL"
md5 = hashlib.md5(texto.encode("utf-8")).hexdigest()
postflight = texto[texto.index("do $postflight$"):texto.index("$postflight$;")]


def unica(patron, fuente, que):
    """El grupo de `patron`, que tiene que aparecer EXACTAMENTE una vez en `fuente`."""
    halladas = re.findall(patron, fuente)
    assert len(halladas) == 1, f"{que}: {len(halladas)} apariciones (se esperaba 1)"
    return halladas[0]


def literal(valor):
    return "'" + valor.replace("'", "''") + "'"


PROSRC = unica(r"if v_prosrc is distinct from '([0-9a-f]{32})' then\n\s+raise exception 'POSTFLIGHT realizacion_cuenta_anticipada: el cuerpo aplicado",
               postflight, "cuerpo nuevo (postflight)")
DEF = unica(r"if v_def is distinct from '([0-9a-f]{32})' then\n\s+raise exception 'POSTFLIGHT realizacion_cuenta_anticipada: la definición aplicada",
            postflight, "definición nueva (postflight)")
EXENCION = unica(r"is distinct from '([0-9a-f]{32})' then\n\s+raise exception 'POSTFLIGHT realizacion_cuenta_anticipada: la huella de la exención",
                 postflight, "huella re-sellada de la exención (postflight)")
COMENTARIO = unica(r"if obj_description\(v_objeto::regprocedure, 'pg_proc'\) is distinct from\n\s+'((?:[^']|'')*)' then\n\s+raise exception "
                   r"'POSTFLIGHT realizacion_cuenta_anticipada: el comentario nuevo no quedó'", postflight, "comentario nuevo (postflight)").replace("''", "'")
FICHA = ("and p.proowner = 'postgres'::regrole::oid and p.prosecdef and p.provolatile = 's'\n         and p.proconfig = array['search_path=\"\"'])")
assert postflight.count(FICHA) == 1, "la ficha (postflight) no aparece exactamente una vez"
for rol in ("anon", "authenticated", "service_role"):
    assert postflight.count(f"has_function_privilege('{rol}', v_objeto, 'EXECUTE')") == 1, rol
assert postflight.count("is distinct from private.huella_exenciones_analitica_lc()") == 1, "sello (postflight)"
assert postflight.count("where c.objeto = v_objeto and c.declarada and c.huella_ok") == 1, "censo (postflight)"

OBJETO = "to_regprocedure('private.metricas_reuniones_implementacion(date,date)')"
CONDICIONES = [
    ("private.metricas_reuniones_implementacion: cuerpo, md5(prosrc) " + PROSRC[:8] + "… (postflight)",
     f"(select md5(p.prosrc) from pg_proc p where p.oid = {OBJETO}) = '{PROSRC}'"),
    ("private.metricas_reuniones_implementacion: definición entera, md5(pg_get_functiondef) " + DEF[:8] + "… (postflight)",
     f"(select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = {OBJETO}) = '{DEF}'"),
    ("private.metricas_reuniones_implementacion: ficha (dueño postgres, security definer, STABLE, search_path vacío)",
     f"(select p.proowner = 'postgres'::regrole::oid and p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=\"\"']\n"
     f"       from pg_proc p where p.oid = {OBJETO})"),
    ("private.metricas_reuniones_implementacion: ACL efectiva (nadie salvo el dueño; ni anon, ni authenticated, ni service_role)",
     f"(select not exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a\n"
     f"                     where a.grantee <> 'postgres'::regrole::oid)\n"
     f"         and not has_function_privilege('anon', p.oid, 'EXECUTE')\n"
     f"         and not has_function_privilege('authenticated', p.oid, 'EXECUTE')\n"
     f"         and not has_function_privilege('service_role', p.oid, 'EXECUTE')\n"
     f"       from pg_proc p where p.oid = {OBJETO})"),
    ("private.metricas_reuniones_implementacion: comentario (el que fija la migración)",
     f"obj_description({OBJETO}, 'pg_proc') = {literal(COMENTARIO)}"),
    ("exención analítica: huella re-sellada " + EXENCION[:8] + "… (postflight)",
     f"(select e.huella from private.analitica_leads_citas_exenciones e where e.objeto = 'private.metricas_reuniones_implementacion(date,date)') = '{EXENCION}'"),
    ("sello de la lista de exenciones coincidente",
     "(select s.sello from private.analitica_lc_sello s where s.id) = private.huella_exenciones_analitica_lc()"),
    ("censo analítico: reconoce la exención re-sellada",
     "exists (select 1 from private.contadores_crudos_leads_citas() c\n"
     "         where c.objeto = 'private.metricas_reuniones_implementacion(date,date)' and c.declarada and c.huella_ok)"),
]
for nombre, _ in CONDICIONES:
    assert "'" not in nombre and "$" not in nombre, nombre
filas = ",\n".join(f"  ({i}, '{nombre}',\n   {expresion})" for i, (nombre, expresion) in enumerate(CONDICIONES, 1))

sql = f"""-- REGISTRO en supabase_migrations.schema_migrations de {VERSION}_{NOMBRE} (bloque 2.2, grupo B).
-- GENERADO por generar_registrador.py: no editar a mano. `db query --linked --file` NO registra: correr DESPUÉS de aplicar la
-- migración, por la misma vía. Desde `CRM-Avance-Corp/`, en este orden (el Director lo ensaya antes en la branch):
--   1. supabase db query --linked --file supabase/migrations/{VERSION}_{NOMBRE}.sql
--   2. supabase db query --linked --file supabase/scripts/metricas-reuniones-realizacion/registrar/{VERSION}.sql
-- Por `db query --linked` no llegan los NOTICE; llega la última fila (va tras el COMMIT):
-- registrado = sin error y la fila «{VERSION} | {md5}».
-- Un error = no registró nada (todo va en una transacción).
-- Idempotente (correrlo dos veces deja una sola fila). Se NIEGA, sin escribir nada, si:
--   · el estado instalado no es el que deja la migración: de private.metricas_reuniones_implementacion(date,date), cuerpo
--     ({PROSRC}), definición entera ({DEF}), ficha, ACL efectiva y comentario; la huella
--     re-sellada de su exención ({EXENCION}); el sello de la lista; el censo analítico;
--   · el nombre {NOMBRE} ya está registrado con OTRA versión (p. ej. 20261007205643, su fecha antigua);
--   · la versión {VERSION} ya está registrada con otro nombre u otro contenido.
-- statements = el archivo entero (md5 {md5}),
-- incrustado UNA sola vez en la tabla temporal pg_temp.{TABLA} (on commit drop).
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('{NOMBRE}_registro'));
create temp table {TABLA} on commit drop as
select $mig$"""
sql += texto
sql += f"""$mig$::text as contenido;
create temp table {TABLA}_condiciones on commit drop as
select c.orden, c.condicion, c.cumple from (values
{filas}
) as c(orden, condicion, cumple);
do $chk$
declare
  v_md5    text;
  v_fallan text;
  v_otras  text;
begin
  select md5(r.contenido) into v_md5 from pg_temp.{TABLA} r;
  if v_md5 is distinct from '{md5}' then
    raise exception 'REGISTRO: el archivo incrustado no es el de la migración (md5 %, esperado {md5})', v_md5;
  end if;
  select string_agg(c.orden || '. ' || c.condicion, '; ' order by c.orden) into v_fallan
    from pg_temp.{TABLA}_condiciones c where c.cumple is not true;
  if v_fallan is not null then
    raise exception 'REGISTRO: la migración {VERSION} no está aplicada o su estado no es el que deja (no se cumple: %); no se registra', v_fallan;
  end if;
  select string_agg(s.version, ', ' order by s.version) into v_otras
    from supabase_migrations.schema_migrations s where s.name = '{NOMBRE}' and s.version <> '{VERSION}';
  if v_otras is not null then
    raise exception 'REGISTRO: el nombre {NOMBRE} ya está registrado con otra versión (%): no se registra dos veces la misma migración', v_otras;
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations s cross join pg_temp.{TABLA} r
             where s.version = '{VERSION}' and (coalesce(s.name, '') <> '{NOMBRE}' or s.statements is distinct from array[r.contenido])) then
    raise exception 'REGISTRO: la versión {VERSION} ya está registrada con otro nombre u otro contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
select '{VERSION}', '{NOMBRE}', array[r.contenido] from pg_temp.{TABLA} r
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
-- Última fila, tras el COMMIT, para que `db query` muestre algo.
select '{VERSION}' as version_registrada, '{md5}' as md5_del_archivo;
"""
SALIDA.mkdir(exist_ok=True)
(SALIDA / f"{VERSION}.sql").write_text(sql, encoding="utf-8")
print(f"{VERSION}.sql  md5 del archivo {md5} · {len(CONDICIONES)} condiciones · función {PROSRC}/{DEF} · exención {EXENCION}")
