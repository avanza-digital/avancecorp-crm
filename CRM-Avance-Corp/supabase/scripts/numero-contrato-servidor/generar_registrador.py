#!/usr/bin/env python3
"""Genera el registrador de 20261009210100_crm_numero_contrato_servidor (supabase_migrations.schema_migrations).

`supabase db query --linked --file` NO registra la migración: este archivo se corre DESPUÉS de aplicarla. Formato de la casa
(el de 20261009180000, supabase/scripts/categoria-sin-operacion/generar_registrador.py) con dos cambios de F4.1-A ronda 5
(Codex r2 R2-2, auditor de permisos r2 P3-1):

  1. Exige el ESTADO COMPLETO que deja la migración en `public.crear_contrato(jsonb,jsonb)`, no solo su cuerpo: cuerpo
     (`md5(prosrc)`, el del postflight), definición entera (`md5(pg_get_functiondef)`, la que exige el preflight de la reversa del
     ensayo como «lo que dejó la migración»), ficha (dueño `postgres`, security definer, `search_path` vacío), ACL efectiva (la
     auditada en el preflight), EXECUTE efectivo (anon SIN, authenticated y service_role CON: el postflight) y comentario (el que
     fija la migración). Cada valor se lee aquí de su fuente y tiene que aparecer exactamente una vez, o el generador aborta.
  2. Se niega también si el mismo NOMBRE ya está registrado con OTRA versión (p. ej. la de las rondas 1 a 3, 20261009160100).

Y lleva el archivo de la migración incrustado UNA sola vez (en una tabla temporal `on commit drop`), no dos.
Idempotente; statements = el archivo entero de la migración, en una sola sentencia.

Uso:  python3 generar_registrador.py     (escribe registrar/20261009210100.sql junto a este script)
"""
import hashlib
import pathlib
import re

AQUI = pathlib.Path(__file__).resolve().parent
MIGRACIONES = AQUI.parent.parent / "migrations"
SALIDA = AQUI / "registrar"

VERSION = "20261009210100"
NOMBRE = "crm_numero_contrato_servidor"
TABLA = f"registro_{VERSION}"

archivo = MIGRACIONES / f"{VERSION}_{NOMBRE}.sql"
texto = archivo.read_text(encoding="utf-8")
for etiqueta in ("$mig$", "$chk$", "$post$"):
    assert etiqueta not in texto, f"{archivo.name} contiene {etiqueta}: cambiar la etiqueta del dólar-quote del registrador"
assert "\r" not in texto and "\x00" not in texto, f"{archivo.name} tiene CR o NUL"
md5 = hashlib.md5(texto.encode("utf-8")).hexdigest()
reversa = (AQUI / "reversa.sql").read_text(encoding="utf-8")
preflight_reversa = reversa[reversa.index("do $preflight$"):reversa.index("$preflight$;")]


def unica(patron, fuente, que):
    """El grupo de `patron`, que tiene que aparecer EXACTAMENTE una vez en `fuente`."""
    halladas = re.findall(patron, fuente)
    assert len(halladas) == 1, f"{que}: {len(halladas)} apariciones (se esperaba 1)"
    return halladas[0]


def literal(valor):
    return "'" + valor.replace("'", "''") + "'"


CUERPO = unica(r"if v_obtenida is distinct from '([0-9a-f]{32})' then\n\s+raise exception 'POSTFLIGHT "
               r"numero_contrato_servidor: el cuerpo de public\.crear_contrato no es el ensayado", texto, "cuerpo en el postflight")
DEFINICION = unica(r"md5\(pg_get_functiondef\('public\.crear_contrato\(jsonb,jsonb\)'::regprocedure\)\)\n\s+is distinct from "
                   r"'([0-9a-f]{32})'", preflight_reversa, "definición en el preflight de la reversa")
assert CUERPO in preflight_reversa, "el cuerpo del postflight no es el que la reversa exige como «lo que dejó la migración»"
ACL = unica(r"is distinct from (array\['authenticated:EXECUTE:false', 'postgres:EXECUTE:false', 'service_role:EXECUTE:false'\]) "
            r"then\n\s+raise exception 'PREFLIGHT numero_contrato_servidor: la ficha de public\.crear_contrato no es la auditada",
            texto, "ACL auditada (preflight)")
FICHA = ("and p.proowner = 'postgres'::regrole::oid and p.prosecdef\n         and p.proconfig = array['search_path=\"\"'])\n"
         "     or has_function_privilege('anon', 'public.crear_contrato(jsonb,jsonb)', 'EXECUTE')\n"
         "     or not has_function_privilege('authenticated', 'public.crear_contrato(jsonb,jsonb)', 'EXECUTE')\n"
         "     or not has_function_privilege('service_role', 'public.crear_contrato(jsonb,jsonb)', 'EXECUTE') then")
assert texto.count(FICHA) == 1, "la ficha y el EXECUTE efectivo del postflight no aparecen exactamente una vez"
COMENTARIO = unica(r"\ncomment on function public\.crear_contrato\(jsonb, jsonb\) is\n  '((?:[^']|'')*)';\n", texto,
                   "comentario de public.crear_contrato").replace("''", "'")

FUNCION = "to_regprocedure('public.crear_contrato(jsonb,jsonb)')"
CONDICIONES = [
    ("public.crear_contrato: cuerpo, md5(prosrc) " + CUERPO[:8] + "… (postflight)",
     f"(select md5(p.prosrc) from pg_proc p where p.oid = {FUNCION}) = '{CUERPO}'"),
    ("public.crear_contrato: definición entera, md5(pg_get_functiondef) " + DEFINICION[:8] + "… (la que deja; reversa)",
     f"(select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = {FUNCION}) = '{DEFINICION}'"),
    ("public.crear_contrato: ficha (dueño postgres, security definer, search_path vacío)",
     f"(select p.proowner = 'postgres'::regrole::oid and p.prosecdef and p.proconfig = array['search_path=\"\"']\n"
     f"       from pg_proc p where p.oid = {FUNCION})"),
    ("public.crear_contrato: ACL efectiva (EXECUTE solo authenticated, service_role y el dueño, sin opción de concesión)",
     f"(select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text "
     f"order by a.grantee::regrole::text)\n       from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, "
     f"acldefault('f', p.proowner))) a where p.oid = {FUNCION}) = {ACL}"),
    ("public.crear_contrato: EXECUTE efectivo (anon SIN; authenticated y service_role CON)",
     f"(select not has_function_privilege('anon', p.oid, 'EXECUTE')\n"
     f"         and has_function_privilege('authenticated', p.oid, 'EXECUTE')\n"
     f"         and has_function_privilege('service_role', p.oid, 'EXECUTE')\n"
     f"       from pg_proc p where p.oid = {FUNCION})"),
    ("public.crear_contrato: comentario (el que fija la migración)",
     f"obj_description({FUNCION}, 'pg_proc') = {literal(COMENTARIO)}"),
]
for nombre, _ in CONDICIONES:
    assert "'" not in nombre and "$" not in nombre, nombre
filas = ",\n".join(f"  ({i}, '{nombre}',\n   {expresion})" for i, (nombre, expresion) in enumerate(CONDICIONES, 1))

sql = f"""-- REGISTRO en supabase_migrations.schema_migrations de {VERSION}_{NOMBRE} (bloque 2.3 del grupo A).
-- GENERADO por generar_registrador.py: no editar a mano. `db query --linked --file` NO registra: correr DESPUÉS de aplicar la
-- migración, por la misma vía. Desde `CRM-Avance-Corp/`, en este orden (el Director lo ensaya antes en la branch), tras el
-- 2.6 y su registrador (supabase/scripts/anular-venta-mes-sellado/registrar/20261009210000.sql):
--   0. (solo lectura) supabase db query --linked --file supabase/scripts/numero-contrato-servidor/candidatos-sonda.sql
--      dice qué pares vendedor–cliente probaría la sonda del postflight y si concluirían.
--   1. supabase db query --linked --file supabase/migrations/{VERSION}_{NOMBRE}.sql
--      Por `db query --linked` el NOTICE de la sonda NO llega: SIN ERROR = LA SONDA RECHAZÓ («RECHAZADO con 22023 y el
--      mensaje fijado»; si acepta, si no concluye con ningún candidato o si no hay candidatos, la migración aborta con un error
--      que lo explica y no aplica nada). Qué candidato concluyó solo se ve en la branch (psql, que sí muestra el NOTICE).
--   2. supabase db query --linked --file supabase/scripts/numero-contrato-servidor/registrar/{VERSION}.sql
-- Por `db query --linked` no llegan los NOTICE; llega la última fila (va tras el COMMIT, como en las migraciones de la casa):
-- registrado = sin error y la fila «{VERSION} | {md5}».
-- Un error = no registró nada (todo va en una transacción).
-- Idempotente (correrlo dos veces deja una sola fila). Se NIEGA, sin escribir nada, si:
--   · el estado instalado de public.crear_contrato(jsonb,jsonb) no es el que deja la migración: cuerpo, definición entera, ficha
--     (dueño, security definer, search_path), ACL efectiva, EXECUTE efectivo (anon sin; authenticated y service_role con) y
--     comentario;
--   · el nombre {NOMBRE} ya está registrado con OTRA versión (p. ej. 20261009160100, la de las rondas 1 a 3);
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
print(f"{VERSION}.sql  md5 del archivo {md5} · {len(CONDICIONES)} condiciones · public.crear_contrato {CUERPO}/{DEFINICION}")
