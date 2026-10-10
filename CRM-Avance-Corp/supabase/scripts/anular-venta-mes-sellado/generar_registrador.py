#!/usr/bin/env python3
"""Genera el registrador de 20261009210000_crm_anular_venta_mes_sellado (supabase_migrations.schema_migrations).

`supabase db query --linked --file` NO registra la migración: este archivo se corre DESPUÉS de aplicarla. Formato de la casa
(el de 20261009180000, supabase/scripts/categoria-sin-operacion/generar_registrador.py) con dos cambios de F4.1-A ronda 5
(Codex r2 R2-2, auditor de permisos r2 P3-1):

  1. Exige el ESTADO COMPLETO que deja la migración, no solo sus cuerpos: de las dos puertas (`crm.anular_cierre_avance`,
     `crm.anular_cierre_externo`) y del detector (`private.mes_sellado_de_venta`), cuerpo (`md5(prosrc)`), definición entera
     (`md5(pg_get_functiondef)`), ficha (dueño, `prosecdef`, `search_path`; del detector, además volátil y `record`), ACL efectiva
     y comentario; y el ledger contra el que se auditó (`private.conversion_episodios` y `private.conversion_cierres`, por
     `md5(prosrc)`, la misma forma que su preflight): con el ledger anterior (`e3d278a1…`, el del 2.6 previo a F4.2-bis) se niega.
     Cada valor se lee aquí de su fuente —el postflight y el preflight de la migración, sus `comment on function` y, para la
     definición entera de las puertas, el preflight de la reversa del ensayo (lo que dejó la migración)— y tiene que aparecer
     exactamente una vez, o el generador aborta.
  2. Se niega también si el mismo NOMBRE ya está registrado con OTRA versión (p. ej. la de las rondas 1 a 3, 20261009160000).

Y lleva el archivo de la migración incrustado UNA sola vez (en una tabla temporal `on commit drop`), no dos.
Idempotente; statements = el archivo entero de la migración, en una sola sentencia.

Uso:  python3 generar_registrador.py     (escribe registrar/20261009210000.sql junto a este script)
"""
import hashlib
import pathlib
import re

AQUI = pathlib.Path(__file__).resolve().parent
MIGRACIONES = AQUI.parent.parent / "migrations"
SALIDA = AQUI / "registrar"

VERSION = "20261009210000"
NOMBRE = "crm_anular_venta_mes_sellado"
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


def comentario(firma):
    """El texto de `comment on function <firma> is '…';` de la migración (exactamente uno)."""
    crudo = unica(r"\ncomment on function " + re.escape(firma) + r" is\n  '((?:[^']|'')*)';\n", texto, f"comentario de {firma}")
    return crudo.replace("''", "'")


def huellas_del_postflight(mensaje):
    return unica(r"if v_pa is distinct from '([0-9a-f]{32})'\n\s+or v_pe is distinct from '([0-9a-f]{32})' then\n"
                 r"\s+raise exception 'POSTFLIGHT anular_venta_mes_sellado: " + re.escape(mensaje), texto, f"postflight «{mensaje}»")


PUERTA_AVANCE, PUERTA_EXTERNO = huellas_del_postflight("el cuerpo de una puerta no es el ensayado")
DETECTOR_PROSRC, DETECTOR_DEF = huellas_del_postflight("el detector no es el ensayado")
DEF_AVANCE = unica(r"md5\(pg_get_functiondef\('crm\.anular_cierre_avance\(uuid,text\)'::regprocedure\)\)\n\s+is distinct from "
                   r"'([0-9a-f]{32})'", preflight_reversa, "definición de la puerta Avance en la reversa")
DEF_EXTERNO = unica(r"md5\(pg_get_functiondef\('crm\.anular_cierre_externo\(uuid,text\)'::regprocedure\)\)\n\s+is distinct from "
                    r"'([0-9a-f]{32})'", preflight_reversa, "definición de la puerta externa en la reversa")
# La ficha auditada de las puertas (preflight, paso 2): la que el postflight exige que `create or replace` no mueva.
ACL_PUERTAS = unica(r"is distinct from (array\['authenticated:EXECUTE:false', 'postgres:EXECUTE:false'\]) then\n\s+raise exception "
                    r"'PREFLIGHT anular_venta_mes_sellado: la ficha de % no es la auditada", texto, "ACL auditada de las puertas")
FICHA_PUERTAS = ("and p.proowner = 'postgres'::regrole::oid\n           and p.prosecdef\n           "
                 "and p.proconfig = array['search_path=\"\"'])")
assert texto.count(FICHA_PUERTAS) == 1, "la ficha auditada de las puertas (preflight, paso 2) no aparece exactamente una vez"
# La ficha del detector (postflight).
FICHA_DETECTOR = ("and p.proowner = 'postgres'::regrole::oid\n         and not p.prosecdef\n         and p.provolatile = 'v'\n"
                  "         and p.prorettype = 'record'::regtype\n         and p.proconfig = array['search_path=\"\"'])")
assert texto.count(FICHA_DETECTOR) == 1, "la ficha del detector (postflight) no aparece exactamente una vez"
for rol in ("authenticated", "anon", "service_role"):
    assert texto.count(f"has_function_privilege('{rol}', 'private.mes_sellado_de_venta(uuid)'::regprocedure, 'EXECUTE')") == 1, rol
# El ledger contra el que se auditó el detector (preflight 3c, F4.2-bis).
LEDGER_EPISODIOS = unica(r"if v_huella is distinct from '([0-9a-f]{32})' then\n\s+raise exception 'PREFLIGHT anular_venta_mes_sellado: "
                         r"private\.conversion_episodios no es la versión auditada", texto, "ledger conversion_episodios")
LEDGER_CIERRES = unica(r"if v_huella is distinct from '([0-9a-f]{32})' then\n\s+raise exception 'PREFLIGHT anular_venta_mes_sellado: "
                       r"private\.conversion_cierres no es la versión auditada", texto, "ledger conversion_cierres")
COMENTARIO_AVANCE = comentario("crm.anular_cierre_avance(uuid, text)")
COMENTARIO_EXTERNO = comentario("crm.anular_cierre_externo(uuid, text)")
COMENTARIO_DETECTOR = comentario("private.mes_sellado_de_venta(uuid)")
# Y las mismas huellas son las que la reversa del ensayo exige como «lo que dejó la migración».
for huella in (PUERTA_AVANCE, PUERTA_EXTERNO, DEF_AVANCE, DEF_EXTERNO, DETECTOR_PROSRC, DETECTOR_DEF):
    assert huella in preflight_reversa, f"{huella} no está en el preflight de la reversa"

AVANCE = "to_regprocedure('crm.anular_cierre_avance(uuid,text)')"
EXTERNO = "to_regprocedure('crm.anular_cierre_externo(uuid,text)')"
DETECTOR = "to_regprocedure('private.mes_sellado_de_venta(uuid)')"
EPISODIOS = ("to_regprocedure('private.conversion_episodios(timestamp with time zone,timestamp with time zone,date,boolean,"
             "uuid[],numeric)')")
CIERRES = ("to_regprocedure('private.conversion_cierres(timestamp with time zone,timestamp with time zone,date,boolean,uuid[],"
           "numeric,uuid[])')")


def acl(oid):
    return (f"(select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text "
            f"order by a.grantee::regrole::text)\n       from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, "
            f"acldefault('f', p.proowner))) a where p.oid = {oid})")


# Cada condición: (texto para el mensaje, expresión booleana). Todas tienen que dar true; NULL (función ausente) es un no.
CONDICIONES = [
    ("crm.anular_cierre_avance: cuerpo, md5(prosrc) " + PUERTA_AVANCE[:8] + "… (postflight)",
     f"(select md5(p.prosrc) from pg_proc p where p.oid = {AVANCE}) = '{PUERTA_AVANCE}'"),
    ("crm.anular_cierre_avance: definición entera, md5(pg_get_functiondef) " + DEF_AVANCE[:8] + "… (la que deja; reversa)",
     f"(select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = {AVANCE}) = '{DEF_AVANCE}'"),
    ("crm.anular_cierre_avance: ficha (dueño postgres, security definer, search_path vacío)",
     f"(select p.proowner = 'postgres'::regrole::oid and p.prosecdef and p.proconfig = array['search_path=\"\"']\n"
     f"       from pg_proc p where p.oid = {AVANCE})"),
    ("crm.anular_cierre_avance: ACL efectiva (EXECUTE solo authenticated y el dueño, sin opción de concesión)",
     f"{acl(AVANCE)} = {ACL_PUERTAS}"),
    ("crm.anular_cierre_avance: comentario (el que fija la migración)",
     f"obj_description({AVANCE}, 'pg_proc') = {literal(COMENTARIO_AVANCE)}"),
    ("crm.anular_cierre_externo: cuerpo, md5(prosrc) " + PUERTA_EXTERNO[:8] + "… (postflight)",
     f"(select md5(p.prosrc) from pg_proc p where p.oid = {EXTERNO}) = '{PUERTA_EXTERNO}'"),
    ("crm.anular_cierre_externo: definición entera, md5(pg_get_functiondef) " + DEF_EXTERNO[:8] + "… (la que deja; reversa)",
     f"(select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = {EXTERNO}) = '{DEF_EXTERNO}'"),
    ("crm.anular_cierre_externo: ficha (dueño postgres, security definer, search_path vacío)",
     f"(select p.proowner = 'postgres'::regrole::oid and p.prosecdef and p.proconfig = array['search_path=\"\"']\n"
     f"       from pg_proc p where p.oid = {EXTERNO})"),
    ("crm.anular_cierre_externo: ACL efectiva (EXECUTE solo authenticated y el dueño, sin opción de concesión)",
     f"{acl(EXTERNO)} = {ACL_PUERTAS}"),
    ("crm.anular_cierre_externo: comentario (el que fija la migración)",
     f"obj_description({EXTERNO}, 'pg_proc') = {literal(COMENTARIO_EXTERNO)}"),
    ("private.mes_sellado_de_venta: cuerpo, md5(prosrc) " + DETECTOR_PROSRC[:8] + "… (postflight)",
     f"(select md5(p.prosrc) from pg_proc p where p.oid = {DETECTOR}) = '{DETECTOR_PROSRC}'"),
    ("private.mes_sellado_de_venta: definición entera, md5(pg_get_functiondef) " + DETECTOR_DEF[:8] + "… (postflight)",
     f"(select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = {DETECTOR}) = '{DETECTOR_DEF}'"),
    ("private.mes_sellado_de_venta: ficha (dueño postgres, SECURITY INVOKER, volátil, record, search_path vacío)",
     f"(select p.proowner = 'postgres'::regrole::oid and not p.prosecdef and p.provolatile = 'v'\n"
     f"         and p.prorettype = 'record'::regtype and p.proconfig = array['search_path=\"\"']\n"
     f"       from pg_proc p where p.oid = {DETECTOR})"),
    ("private.mes_sellado_de_venta: ACL efectiva (nadie salvo el dueño; ni authenticated, ni anon, ni service_role)",
     f"(select not exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a\n"
     f"                     where a.grantee <> 'postgres'::regrole::oid)\n"
     f"         and not has_function_privilege('authenticated', p.oid, 'EXECUTE')\n"
     f"         and not has_function_privilege('anon', p.oid, 'EXECUTE')\n"
     f"         and not has_function_privilege('service_role', p.oid, 'EXECUTE')\n"
     f"       from pg_proc p where p.oid = {DETECTOR})"),
    ("private.mes_sellado_de_venta: comentario (el que fija la migración)",
     f"obj_description({DETECTOR}, 'pg_proc') = {literal(COMENTARIO_DETECTOR)}"),
    ("ledger: private.conversion_episodios, md5(prosrc) " + LEDGER_EPISODIOS[:8] + "… (preflight; F4.2-bis)",
     f"(select md5(p.prosrc) from pg_proc p where p.oid = {EPISODIOS}) = '{LEDGER_EPISODIOS}'"),
    ("ledger: private.conversion_cierres, md5(prosrc) " + LEDGER_CIERRES[:8] + "… (preflight)",
     f"(select md5(p.prosrc) from pg_proc p where p.oid = {CIERRES}) = '{LEDGER_CIERRES}'"),
]
for nombre, _ in CONDICIONES:
    assert "'" not in nombre and "$" not in nombre, nombre
filas = ",\n".join(f"  ({i}, '{nombre}',\n   {expresion})" for i, (nombre, expresion) in enumerate(CONDICIONES, 1))

sql = f"""-- REGISTRO en supabase_migrations.schema_migrations de {VERSION}_{NOMBRE} (bloque 2.6 del grupo A).
-- GENERADO por generar_registrador.py: no editar a mano. `db query --linked --file` NO registra: correr DESPUÉS de aplicar la
-- migración, por la misma vía. Desde `CRM-Avance-Corp/`, en este orden (el Director lo ensaya antes en la branch):
--   1. supabase db query --linked --file supabase/migrations/{VERSION}_{NOMBRE}.sql
--   2. supabase db query --linked --file supabase/scripts/anular-venta-mes-sellado/registrar/{VERSION}.sql
--   (después, el 2.3: 20261009210100 y su registrador, supabase/scripts/numero-contrato-servidor/registrar/20261009210100.sql)
-- Por `db query --linked` no llegan los NOTICE; llega la última fila (va tras el COMMIT, como en las migraciones de la casa):
-- registrado = sin error y la fila «{VERSION} | {md5}».
-- Un error = no registró nada (todo va en una transacción).
-- Idempotente (correrlo dos veces deja una sola fila). Se NIEGA, sin escribir nada, si:
--   · el estado instalado no es el que deja la migración: de las dos puertas y del detector private.mes_sellado_de_venta(uuid),
--     cuerpo, definición entera, ficha (dueño, security definer/invoker, search_path), ACL efectiva y comentario; o el ledger no es
--     el de F4.2-bis (private.conversion_episodios {LEDGER_EPISODIOS},
--     private.conversion_cierres {LEDGER_CIERRES}): con el 2.6 anterior (df101234…, ledger e3d278a1…) las puertas y
--     el detector son los mismos, pero este registrador se niega;
--   · el nombre {NOMBRE} ya está registrado con OTRA versión (p. ej. 20261009160000, la de las rondas 1 a 3);
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
print(f"{VERSION}.sql  md5 del archivo {md5} · {len(CONDICIONES)} condiciones · puertas {PUERTA_AVANCE}/{DEF_AVANCE} y "
      f"{PUERTA_EXTERNO}/{DEF_EXTERNO} · detector {DETECTOR_PROSRC}/{DETECTOR_DEF} · ledger {LEDGER_EPISODIOS} y {LEDGER_CIERRES}")
