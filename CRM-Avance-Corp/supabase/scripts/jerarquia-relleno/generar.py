#!/usr/bin/env python3
"""Escribe ensayo-produccion.sql y registrar.sql a partir del texto EXACTO de la migración. --verificar no escribe."""
import argparse
import hashlib
from pathlib import Path

CARPETA = Path(__file__).resolve().parent
VERSION, NOMBRE = '20261010150451', 'crm_jerarquia_relleno_carmen_jorge'
MIGRACION = CARPETA.parents[1] / 'migrations' / f'{VERSION}_{NOMBRE}.sql'
ENSAYO = CARPETA / 'ensayo-produccion.sql'
REGISTRAR = CARPETA / 'registrar.sql'
ANCLA = "set local statement_timeout = '120s';\n"
LINEA_ENSAYO = "set local crm.relleno_jerarquia_ensayo = 'on';\n"
CABECERA_ENSAYO = (
    f'-- ENSAYO DE PRODUCCIÓN de {VERSION}_{NOMBRE}: la migración entera, que acaba SIEMPRE en error y lo deshace todo.\n'
    '-- Resultado correcto: «ENSAYO RELLENO PASS: … — SE DESHACE TODO». Cualquier otro error es un fallo.\n'
    '-- Generado por generar.py (no editar a mano).\n'
)
ETIQUETA = f'$migracion_{VERSION}$'
SISTEMA = 'f6d2941b-2e93-4c81-9a27-0c5e786b104d'
IDEMPOTENCIAS = ('df2577aa-0315-43ad-8d28-cc1fce382b61', '8ea032ed-da1e-48f1-b75c-52f6afaaf3e5')
PARES = (('0eeb8c64-25e4-418b-b5d5-e07b06758b5e', IDEMPOTENCIAS[0]), ('cc8b660a-49e9-49b2-a939-c12b5078911b', IDEMPOTENCIAS[1]))
ANTES, DESPUES = 'ebb19751-5976-4446-91ec-03382247d8b8', 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127'
TS = '2026-08-29 17:56:38.8714+00'


def ensayo(texto):
    assert texto.count(ANCLA) == 1, 'ancla del ensayo ambigua'
    assert LINEA_ENSAYO not in texto
    generado = CABECERA_ENSAYO + texto.replace(ANCLA, ANCLA + LINEA_ENSAYO)
    # Quitar lo añadido devuelve la migración al byte: el ensayo prueba exactamente lo que se aplicará.
    assert generado[len(CABECERA_ENSAYO):].replace(LINEA_ENSAYO, '', 1) == texto
    return generado


def registrar(texto):
    assert ETIQUETA not in texto
    for idem in IDEMPOTENCIAS:
        assert texto.count(idem) == 1, f'idempotencia {idem} ausente o repetida en la migración'
    for valor in (*(p for par in PARES for p in par), ANTES, DESPUES, TS):
        assert valor in texto, f'{valor} no está en la migración'
    md5 = hashlib.md5(texto.encode()).hexdigest()
    pares = ', '.join(f"('{o}'::uuid, '{i}'::uuid)" for o, i in PARES)
    return f"""-- REGISTRO en supabase_migrations.schema_migrations de {VERSION}_{NOMBRE}.
-- Correr DESPUÉS de aplicar la migración, por la misma vía. Idempotente; se niega si los dos eventos del relleno no
-- están exactos o si la versión ya está registrada con otro nombre u otro texto. Si algo corta entre la migración y
-- este registro: la migración repetida dice «ya aplicado» y este registro se puede correr otra vez.
-- Generado por generar.py: md5 del texto de la migración {md5}.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('{NOMBRE}'));
do $chk$
begin
  -- Los dos eventos EXACTOS (mismos campos que comprueba la migración al repetirse), no solo dos con su idempotencia.
  if (select count(*) from crm.usuario_eventos ue
      where ue.actor_id = '{SISTEMA}' and ue.accion = 'jerarquia_actualizada'
        and ue.detalle ->> 'via' = 'relleno'
        and ue.detalle ->> 'supervisor_anterior' = '{ANTES}'
        and ue.detalle ->> 'supervisor_nuevo' = '{DESPUES}'
        and ue.creado_en = '{TS}'
        and (ue.objetivo_id, ue.idempotencia) in ({pares})) <> 2 then
    raise exception 'REGISTRO: faltan los dos eventos del relleno; aplica primero {VERSION}';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '{VERSION}' and coalesce(name, '') <> '{NOMBRE}') then
    raise exception 'REGISTRO: la versión {VERSION} ya está registrada con otro nombre';
  end if;
  -- Un registro con OTRO texto no se pisa en silencio (el insert de abajo no hace nada si la versión existe).
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '{VERSION}' and (cardinality(statements) is distinct from 1
               or md5(statements[1]) is distinct from '{md5}')) then
    raise exception 'REGISTRO: la versión {VERSION} ya está registrada con OTRO texto; revisar a mano';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('{VERSION}', '{NOMBRE}', array[{ETIQUETA}{texto}{ETIQUETA}])
on conflict (version) do nothing;
select version, name, md5(statements[1]) as md5_texto from supabase_migrations.schema_migrations where version = '{VERSION}';
commit;
"""


def principal():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verificar', action='store_true')
    args = parser.parse_args()
    texto = MIGRACION.read_text()
    salidas = {ENSAYO: ensayo(texto), REGISTRAR: registrar(texto)}
    if args.verificar:
        malos = [p.name for p, contenido in salidas.items() if not p.exists() or p.read_text() != contenido]
        if malos:
            raise SystemExit(f'FAIL: desactualizados {malos}; correr generar.py')
        print(f'PASS: ensayo y registro al día (md5 del texto {hashlib.md5(texto.encode()).hexdigest()})')
        return
    for ruta, contenido in salidas.items():
        ruta.write_text(contenido)
    print(f'escritos {[p.name for p in salidas]}')


if __name__ == '__main__':
    principal()
