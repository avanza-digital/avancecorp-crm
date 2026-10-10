#!/usr/bin/env python3
"""Escribe registrar.sql con el texto EXACTO de la migración 3B. --verificar no escribe."""
import argparse
import hashlib
import re
from pathlib import Path

CARPETA = Path(__file__).resolve().parent
VERSION, NOMBRE = '20261009234500', 'crm_facturacion_lista_operaciones'
MIGRACION = CARPETA.parents[1] / 'migrations' / f'{VERSION}_{NOMBRE}.sql'
REGISTRAR = CARPETA / 'registrar.sql'
ETIQUETA = f'$migracion_{VERSION}$'


def huellas(texto):
    inicio, fin = '-- INICIO HUELLAS\n', '-- FIN HUELLAS\n'
    assert texto.count(inicio) == texto.count(fin) == 1, 'marcadores de huellas ambiguos'
    assert texto.index(inicio) < texto.index(fin), 'marcadores de huellas invertidos'
    bloque = texto.split(inicio)[1].split(fin)[0]
    filas = re.findall(r"\('([^']+)', '([^']+)'", bloque)
    assert len(filas) == 2 and all(re.fullmatch('[0-9a-f]{32}|PENDIENTE_MEDIR_EN_BANCO', h) for _, h in filas), 'huellas inválidas'
    firma = '(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)'
    assert {f for f, _ in filas} == {
        'private.facturacion_lista' + firma, 'crm.listar_operaciones_facturacion_fn' + firma,
    }, 'firmas 3B inválidas (dias después de hasta; sin_analista después de analistas)'
    # Los marcadores producen un registrador que FALLA cerrado, nunca un registro anticipado.
    return filas + [
        ('private.facturacion_operaciones(timestamptz,timestamptz)', '5d63cb537b0b286ad47feb7f5b26d161'),
        ('private.facturacion_operaciones_visibles(timestamptz,timestamptz)', '17c2ca27996adad88f685896915953e3'),
        ('crm.facturacion_diaria_fn(date)', '3753d03552e26eb7e61117a3baab6f78'),
    ]


def registrar(texto):
    assert ETIQUETA not in texto
    valores = ',\n'.join(f"    ('{firma}', '{huella}')" for firma, huella in huellas(texto))
    return f"""-- REGISTRO en supabase_migrations.schema_migrations de {VERSION}_{NOMBRE}.
-- Correr DESPUÉS de aplicar la migración, por la misma vía. Idempotente; se niega si alguna de las cinco funciones
-- no tiene la huella esperada tras aplicar o si la versión ya está registrada con otro nombre.
-- Generado por generar-registrar.py: md5 del texto de la migración {hashlib.md5(texto.encode()).hexdigest()}.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('{NOMBRE}'));
do $chk$
declare
  v_fila record;
  v_md5 text;
begin
  for v_fila in select * from (values
{valores}
  ) esperadas(firma, huella) loop
    select md5(pg_get_functiondef(p.oid)) into v_md5 from pg_proc p where p.oid = to_regprocedure(v_fila.firma);
    if v_md5 is distinct from v_fila.huella then
      raise exception 'REGISTRO: % no tiene la huella esperada (%); aplica primero {VERSION}', v_fila.firma, v_md5;
    end if;
  end loop;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '{VERSION}' and coalesce(name, '') <> '{NOMBRE}') then
    raise exception 'REGISTRO: la versión {VERSION} ya está registrada con otro nombre';
  end if;
  -- Un registro con OTRO texto no se pisa en silencio (el insert de abajo no hace nada si la versión existe).
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '{VERSION}' and (cardinality(statements) is distinct from 1
               or md5(statements[1]) is distinct from '{hashlib.md5(texto.encode()).hexdigest()}')) then
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
    esperado = registrar(texto)
    if args.verificar:
        assert REGISTRAR.read_text() == esperado, 'registrar.sql no corresponde a la migración'
    else:
        REGISTRAR.write_text(esperado)
    print(f'PASS: registrar.sql = texto de la migración (md5 {hashlib.md5(texto.encode()).hexdigest()})')


if __name__ == '__main__':
    principal()
