#!/usr/bin/env python3
"""Genera registrar.sql y reversa.sql de la migración «Retirar y Cambiar cuenta solo READ COMMITTED».
Fuente única: la migración (huellas nuevas y cabeceras) y piezas-anteriores.json (los cuerpos EXACTOS que
tenían los dos núcleos antes, con su huella viva del 02/10/2026). Ninguno de los dos derivados se edita a mano.
  python3 supabase/scripts/cuentas-pago-negativa/generar-derivados.py              # escribe
  python3 supabase/scripts/cuentas-pago-negativa/generar-derivados.py --verificar  # falla si están viejos
"""
import hashlib, io, json, os, sys

AQUI = os.path.dirname(os.path.abspath(__file__))
P = json.load(io.open(os.path.join(AQUI, "piezas-anteriores.json"), encoding="utf-8"))
VER, NOMBRE = P["VER"], P["NOMBRE"]
MIG = f"{VER}_{NOMBRE}.sql"
mig = io.open(os.path.join(AQUI, "..", "..", "migrations", MIG), encoding="utf-8").read()
md5 = lambda s: hashlib.md5(s.encode("utf-8")).hexdigest()
PIEZAS = [P["retirar"], P["cambiar"]]
for p in PIEZAS:
    assert md5(p["viejo"]) == p["vivo"] and md5(p["nuevo"]) == p["h_nuevo"], "piezas-anteriores.json no cuadra"
    assert p["h_nuevo"] in mig and p["vivo"] in mig, "la migración no lleva las huellas esperadas"

def exige(clave, etiqueta, cuando):
    return "\n".join(f"""  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('{p['firma']}')) is distinct from '{p[clave]}' then
    raise exception '{etiqueta}: {p['nombre']} no tiene el cuerpo esperado ({cuando}); no se toca nada';
  end if;""" for p in PIEZAS)

REGISTRAR = f"""-- REGISTRO en supabase_migrations.schema_migrations de {MIG}.
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración. Idempotente; se niega si
-- los cuerpos vivos no son los de la migración, o si la versión ya está registrada con otro contenido.
-- GENERADO por generar-derivados.py. statements = el archivo entero (md5 {md5(mig)}).
begin;
set local lock_timeout = '5s';
select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('{NOMBRE}_registro'));
do $chk$
begin
{exige('h_nuevo', 'REGISTRO', 'la migración no está aplicada; aplícala primero')}
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '{VER}' and (coalesce(name, '') <> '{NOMBRE}' or statements is distinct from array[$mig${mig}$mig$])) then
    raise exception 'REGISTRO: la versión {VER} ya está registrada con otro nombre u otro contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('{VER}', '{NOMBRE}', array[$mig${mig}$mig$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '{VER}' and name = '{NOMBRE}' and cardinality(statements) = 1
                   and md5(statements[1]) = '{md5(mig)}') then
    raise exception 'REGISTRO: la fila {VER} / {NOMBRE} no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: {VER} / {NOMBRE} (1 sentencia: el archivo entero)';
end $post$;
commit;
"""

def crear_viejo(p):
    return p["cab"] + p["viejo"] + "$function$;"

REVERSA = f"""-- REVERSA de {MIG}. GENERADA por generar-derivados.py (no se edita a mano).
-- Repone en los dos núcleos los cuerpos EXACTOS que tenían antes (huellas {PIEZAS[0]['vivo']} y
-- {PIEZAS[1]['vivo']}), deja el comentario sin la frase añadida y borra la fila del registro. Se niega si los
-- cuerpos vivos no son los de la migración (alguien tocó algo después) o si no va en READ COMMITTED.
-- No toca vínculos, retiros, cambios, grants ni nada más. Solo Miguel, con autorización expresa.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
do $pre$
begin
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'REVERSA SOLO_READ_COMMITTED: la transacción debe ir en READ COMMITTED (va en %)',
      pg_catalog.current_setting('transaction_isolation');
  end if;
{exige('h_nuevo', 'REVERSA SOLO_READ_COMMITTED', 'no es el de la migración')}
end $pre$;

{crear_viejo(PIEZAS[0])}

{crear_viejo(PIEZAS[1])}

do $post$
declare
  v_f record;
begin
{exige('vivo', 'REVERSA SOLO_READ_COMMITTED', 'no quedó el anterior')}
  for v_f in select * from (values ('{PIEZAS[0]['firma']}'), ('{PIEZAS[1]['firma']}')) as f(firma) loop
    execute pg_catalog.format('comment on function %s is %L', v_f.firma,
      pg_catalog.rtrim(pg_catalog.replace(coalesce(pg_catalog.obj_description(pg_catalog.to_regprocedure(v_f.firma), 'pg_proc'), ''),
        ' Solo admite READ COMMITTED (0A000 en cualquier otro modo; {VER}).', '')));
    if not exists (select 1 from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure(v_f.firma)
                   and p.prosecdef and p.proconfig @> array['search_path=""'])
       or not pg_catalog.has_function_privilege('authenticated', v_f.firma, 'EXECUTE') then
      raise exception 'REVERSA SOLO_READ_COMMITTED: % perdió DEFINER, search_path o el permiso de authenticated', v_f.firma;
    end if;
  end loop;
  if pg_catalog.to_regclass('supabase_migrations.schema_migrations') is not null then
    execute 'delete from supabase_migrations.schema_migrations where version = ' || pg_catalog.quote_literal('{VER}');
  end if;
end $post$;
select 'REVERTIDA_SOLO_READ_COMMITTED' as resultado;
commit;
"""

DERIVADOS = {"registrar.sql": REGISTRAR, "reversa.sql": REVERSA}
if "--verificar" in sys.argv:
    viejos = [n for n, t in DERIVADOS.items() if not os.path.exists(os.path.join(AQUI, n)) or io.open(os.path.join(AQUI, n), encoding="utf-8").read() != t]
    if viejos:
        print("derivados VIEJOS:", ", ".join(viejos)); sys.exit(1)
    print(f"derivados al día (migración md5 {md5(mig)})"); sys.exit(0)
for n, t in DERIVADOS.items():
    io.open(os.path.join(AQUI, n), "w", encoding="utf-8").write(t)
print("escritos:", ", ".join(DERIVADOS), f"(migración md5 {md5(mig)})")
