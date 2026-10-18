"""Consulta v2: nombres en el reporte, independiente del permiso de ficha."""
from pathlib import Path
import hashlib
import json
import re

BASE = Path(__file__).resolve().parent
MIGRACION = BASE.parents[1] / 'migrations/20261013154615_crm_facturacion_nombres_coordinacion.sql'
catalogo = json.loads((BASE / 'vivo/catalogo.json').read_text())
originales = {f['firma']: f for f in catalogo}
firma_lista = 'private.facturacion_lista(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)'
firma_puerta = 'crm.listar_operaciones_facturacion_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)'
assert set(originales) == {firma_lista, firma_puerta}


def cambiar(texto, anterior, nuevo):
    assert texto.count(anterior) == 1, (anterior, texto.count(anterior))
    return texto.replace(anterior, nuevo)


def cuerpo(texto):
    return re.search(r'AS \$function\$(.*?)\$function\$', texto, re.S).group(1)


def md5(texto):
    return hashlib.md5(texto.encode()).hexdigest()


lista = originales[firma_lista]['definicion']
lista = cambiar(lista, 'CREATE OR REPLACE FUNCTION private.facturacion_lista(',
                'CREATE FUNCTION private.facturacion_lista_nombres(')
lista = lista.replace('v_solo_cifras', 'v_reporte_coordinacion')
argumentos = 'p_desde, p_hasta, p_dias, p_analistas, p_sin_analista, p_equipo, p_sin_equipo, p_tipos, p_moneda, p_pagina, p_tamano'
lista = cambiar(lista, 'begin\n  if p_desde',
                'begin\n  -- Los demás roles conservan exactamente el núcleo publicado.\n'
                '  if not v_reporte_coordinacion then\n'
                f'    return private.facturacion_lista({argumentos});\n'
                '  end if;\n  if p_desde')
lista = cambiar(lista, "'cliente_nombre', case when not d.visible then 'Cliente de otro equipo'",
                "'cliente_nombre', case when not d.visible and not v_reporte_coordinacion then 'Cliente de otro equipo'")
lista = cambiar(lista, "    ) || case when not d.visible then '{}'::jsonb else",
                "    ) || case when v_reporte_coordinacion then jsonb_build_object('nombre_visible', true) else '{}'::jsonb end\n"
                "      || case when not d.visible then '{}'::jsonb else")
puerta = originales[firma_puerta]['definicion']
puerta = cambiar(puerta, 'CREATE OR REPLACE FUNCTION crm.listar_operaciones_facturacion_fn(',
                 'CREATE FUNCTION crm.listar_operaciones_facturacion_v2_fn(')
puerta = cambiar(puerta, 'select private.facturacion_lista(', 'select private.facturacion_lista_nombres(')
puerta = cambiar(puerta, 'p_pagina, p_tamano);', "p_pagina, p_tamano) || '{\"version\":2}'::jsonb;")
nuevos = {firma_lista.replace('facturacion_lista(', 'facturacion_lista_nombres('): lista,
          firma_puerta.replace('facturacion_fn(', 'facturacion_v2_fn('): puerta}


def guarda_originales():
    valores = ',\n'.join(f"    ('{firma}', '{md5(f['definicion'])}')" for firma, f in originales.items())
    return f"""do $originales$
declare r record;
begin
  for r in select * from (values
{valores}
  ) f(firma,huella) loop
    if md5(pg_get_functiondef(to_regprocedure(r.firma))) is distinct from r.huella then
      raise exception 'Facturación nombres: función publicada cambió en %; se deshace todo',r.firma;
    end if;
  end loop;
end $originales$;
"""


def guarda_nuevos():
    valores = ',\n'.join(f"    ('{firma}', '{md5(cuerpo(texto))}')" for firma, texto in nuevos.items())
    return f"""do $nuevos$
declare r record;
begin
  for r in select * from (values
{valores}
  ) f(firma,huella) loop
    if (select md5(prosrc) from pg_proc where oid=to_regprocedure(r.firma)) is distinct from r.huella then
      raise exception 'Facturación nombres: cuerpo v2 inesperado en %',r.firma;
    end if;
  end loop;
end $nuevos$;
"""


cabecera = """-- Aprobado por Miguel: nombres de clientes en Facturación para Coordinación, solo lectura.
-- Añade dos funciones. No modifica RPC v1, RLS, tablas, fórmulas ni permisos de escritura.
-- Backend primero: v1 conserva su contrato para las pestañas ya abiertas; el frontend nuevo usa v2.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '30s';
"""
ausentes = "do $ausentes$ begin\n" + '\n'.join(
    f"  if to_regprocedure('{firma}') is not null then raise exception 'Facturación nombres: {firma} ya existe'; end if;"
    for firma in nuevos) + '\nend $ausentes$;\n'
privada, publica = nuevos
permisos = f"""alter function {privada} owner to postgres;
alter function {publica} owner to postgres;
revoke all on function {privada} from public,anon,authenticated,service_role;
revoke all on function {publica} from public,anon,authenticated,service_role;
grant execute on function {publica} to authenticated;
comment on function {privada} is 'Facturación v2: Coordinación activa recibe nombres exclusivamente para reporte, visible=false y sin identificadores de clientes. Otros roles delegan al núcleo v1.';
comment on function {publica} is 'Lista de operaciones v2. Mismos filtros y cifras; nombres para Coordinación sin permiso de ficha ni escrituras. v1 permanece compatible.';
do $acl$
begin
  if has_function_privilege('authenticated','{privada}','execute')
     or has_function_privilege('anon','{publica}','execute')
     or has_function_privilege('service_role','{publica}','execute')
     or not has_function_privilege('authenticated','{publica}','execute')
     or (select prosecdef or provolatile<>'s' or proconfig is distinct from array['search_path=""']::text[]
         from pg_proc where oid=to_regprocedure('{privada}'))
     or (select not prosecdef or provolatile<>'s' or proconfig is distinct from array['search_path=""']::text[]
         from pg_proc where oid=to_regprocedure('{publica}')) then
    raise exception 'Facturación nombres: ACL o atributos inesperados';
  end if;
end $acl$;
"""
MIGRACION.write_text(cabecera + guarda_originales() + ausentes + lista + ';\n' + puerta + ';\n'
                     + permisos + guarda_nuevos() + guarda_originales() + 'commit;\n')
(BASE / 'reversa.sql').write_text(cabecera + guarda_nuevos() + guarda_originales()
    + f'drop function {publica};\ndrop function {privada};\ncommit;\n')
print('Generadas migración y reversa: dos funciones nuevas, v1 intacta')
