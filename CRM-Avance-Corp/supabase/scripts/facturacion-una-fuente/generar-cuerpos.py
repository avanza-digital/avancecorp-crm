#!/usr/bin/env python3
"""Mueve las CTE vivas; sincroniza migración, reversa y ensayos. --verificar no escribe."""
import argparse
import hashlib
from pathlib import Path

CARPETA = Path(__file__).resolve().parent
CRM = CARPETA.parents[2]
MIGRACION = CRM / 'supabase/migrations/20261009224000_crm_facturacion_una_fuente.sql'
HUELLAS = {
    'crm.facturacion_diaria_fn': '4b11e1da336f2f296c81f064ce30e35b',
    'private.capital_episodios': '2ed07da302e9a1b881a4962724234dd7',
    'private.rol_crm': '99827f3fe2fbc3cfae5668c30015c758',
    'private.es_lector_global': 'c8be602f84348a0125617995802db618',
    'private.vendedor_ids_visibles': '85544c70a0920f3a7a1b5da06935f236',
}
COLUMNAS = ('operacion_id uuid, dia date, fecha timestamp with time zone, tipo text, moneda text, '
            'monto numeric, analista_id uuid, supervisor_id uuid, contrato_id uuid, cierre_externo_id uuid, '
            'cliente_id uuid, lead_id uuid, registrado_por uuid, categoria text, estado text, '
            'anulado boolean, fecha_vencimiento date')


def entre(texto, inicio, fin):
    assert texto.count(inicio) == 1, inicio
    assert texto.count(fin) == 1, fin
    return texto.split(inicio)[1].split(fin)[0]


def sustituir(texto, antes, despues, veces=1):
    assert texto.count(antes) == veces, (antes, texto.count(antes))
    return texto.replace(antes, despues)


def cuerpos():
    vivos = {}
    for nombre, huella in HUELLAS.items():
        contenido = (CARPETA / 'vivo' / (nombre + '.sql')).read_bytes()
        assert hashlib.md5(contenido).hexdigest() == huella, nombre
        vivos[nombre] = contenido.decode()
    vivo = vivos['crm.facturacion_diaria_fn']
    cabecera, resto = vivo.split('AS $function$\n')
    verja = entre(vivo, 'AS $function$\n', ',\n  mes as (')
    mes = '  mes as (' + entre(vivo, '  mes as (', ',\n  episodios as (')
    eventos = '  eventos as (' + entre(vivo, '  eventos as (', '\n  select\n    ep.dia,')
    joins = entre(vivo, '  cross join ambito a\n', '  left join public.perfiles pf')
    caida = entre(vivo, '  -- LOS DOS CAMINOS', '  left join public.perfiles ps')
    recorte = '  -- EL RECORTE' + entre(vivo, '  -- EL RECORTE', '\n  group by ep.dia')
    supervisor = 'coalesce(t.supervisor_id, eq.supervisor_id)'
    cabecera_privada = ('CREATE OR REPLACE FUNCTION private.{nombre}(p_desde timestamp with time zone, '
                       'p_hasta timestamp with time zone)\n RETURNS TABLE(' + COLUMNAS + ')\n'
                       " LANGUAGE sql\n STABLE SECURITY INVOKER\n SET search_path TO ''\nAS $function$\n")
    operaciones = cabecera_privada.format(nombre='facturacion_operaciones') + """  with episodios as (
    select (e.fecha at time zone 'America/Lima')::date as dia, e.*
    from private.capital_episodios(p_desde, p_hasta, true, '{}'::uuid[]) e
    where e.medida = 'stock'
  ),
""" + eventos + """
  select
    coalesce(ep.contrato_id, ep.cierre_externo_id) as operacion_id,
    ep.dia, ep.fecha, ep.tipo, ep.moneda, ep.monto, ep.analista_id,
  -- LOS DOS CAMINOS""" + caida + """    coalesce(t.supervisor_id, eq.supervisor_id) as supervisor_id,
    ep.contrato_id, ep.cierre_externo_id, ep.cliente_id, ep.lead_id,
    ep.registrado_por, ep.categoria, ep.estado, ep.anulado, ep.fecha_vencimiento
  from episodios ep
""" + joins.rstrip('\n') + ';\n$function$\n'
    # Única sustitución del recorte: la expresión ya resuelta se lee por su columna.
    visibles = cabecera_privada.format(nombre='facturacion_operaciones_visibles') + verja + """
  select ep.*
  from (select * from ambito a where a.ok) a
  -- La dependencia de a.ok mantiene el lateral detrás de la verja incluso si
  -- el planificador reordena joins: con cero actores autorizados no se llama.
  cross join lateral private.facturacion_operaciones(
    case when a.ok then p_desde end, p_hasta
  ) ep
""" + sustituir(recorte, supervisor, 'ep.supervisor_id') + ';\n$function$\n'
    seleccion = '  select\n    ep.dia,' + entre(vivo, '  select\n    ep.dia,', '\n  from episodios ep')
    final = '  group by ep.dia' + vivo.split('  group by ep.dia')[1]
    diaria = cabecera + 'AS $function$\n  with\n' + mes + '\n' + sustituir(seleccion, supervisor, 'ep.supervisor_id') + """
  from mes m
  cross join lateral private.facturacion_operaciones_visibles(
    (m.ini::timestamp at time zone 'America/Lima'),
    (((m.ini + interval '1 month')::date)::timestamp at time zone 'America/Lima')
  ) ep
  left join public.perfiles pf on pf.id = ep.analista_id
  left join public.perfiles ps on ps.id = ep.supervisor_id
""" + sustituir(final, supervisor, 'ep.supervisor_id')
    # Los fragmentos de negocio se COPIAN, incluidos sus comentarios y espacios.
    assert eventos in operaciones and joins.rstrip('\n') in operaciones
    assert verja in visibles and mes in diaria
    assert diaria.split('AS $function$')[0] == cabecera
    assert operaciones.count('from private.capital_episodios(') == 1
    assert visibles.count('join lateral private.facturacion_operaciones(') == 1
    assert diaria.count('join lateral private.facturacion_operaciones_visibles(') == 1
    return vivo, [operaciones, visibles, diaria]


def bloque(cuerpos):
    return ''.join('  execute $def$\n' + cuerpo + '$def$;\n\n' for cuerpo in cuerpos)


def sincronizar(ruta, esperado, verificar):
    if verificar:
        assert ruta.read_text() == esperado, f'Divergencia: {ruta}'
    else:
        ruta.write_text(esperado)
    print(f'PASS: {ruta.name}')


def seccion(texto, nombre, contenido):
    inicio, fin = f'-- INICIO {nombre}\n', f'-- FIN {nombre}\n'
    antes, resto = texto.split(inicio)
    _, despues = resto.split(fin)
    return antes + inicio + contenido + fin + despues


def principal():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verificar', action='store_true')
    args = parser.parse_args()
    vivo, nuevos = cuerpos()
    migracion = seccion(MIGRACION.read_text(), 'CUERPOS GENERADOS', bloque(nuevos))
    sincronizar(MIGRACION, migracion, args.verificar)
    reversa_ruta = CARPETA / 'reversa.sql'
    reversa = seccion(reversa_ruta.read_text(), 'CUERPOS GENERADOS', bloque([vivo]))
    # Al medir, Miguel fija las tres huellas SOLO en la migración y regenera.
    manifiesto = entre(migracion, '-- INICIO HUELLAS\n', '-- FIN HUELLAS\n')
    reversa = seccion(reversa, 'HUELLAS', manifiesto)
    sincronizar(reversa_ruta, reversa, args.verificar)
    assert migracion.endswith('commit;\n') and reversa.endswith('commit;\n')
    for nombre in ('ensayo-produccion.sql', 'medir.sql', 'ensayo-sintetico.sql'):
        ruta = CARPETA / nombre
        texto = ruta.read_text()
        # El único BEGIN/COMMIT pertenece al envoltorio. El DO es idéntico.
        central = entre(migracion, '-- INICIO TRANSACCION\n', '-- FIN TRANSACCION\n')
        texto = seccion(texto, 'MIGRACION', central)
        if nombre == 'ensayo-sintetico.sql':
            texto = seccion(texto, 'REVERSA', entre(reversa, '-- INICIO TRANSACCION\n', '-- FIN TRANSACCION\n'))
        sincronizar(ruta, texto, args.verificar)
    print('PASS: cinco huellas vivas; CTE al byte; firma y orden originales; ensayos sincronizados')


if __name__ == '__main__':
    principal()
