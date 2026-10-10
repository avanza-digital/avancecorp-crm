#!/usr/bin/env python3
"""Sincroniza el DO de 3B y su comparador/reversa en los ensayos. --verificar no escribe."""
import argparse
import hashlib
from pathlib import Path

CARPETA = Path(__file__).resolve().parent
MIGRACION = CARPETA.parents[1] / 'migrations/20261009234500_crm_facturacion_lista_operaciones.sql'
HUELLAS = {
    'private.inversionista_canonica': '34702897135078893b7d3a726b0c1816',
    'crm.facturacion_diaria_fn': '3753d03552e26eb7e61117a3baab6f78',
    'private.facturacion_operaciones': '5d63cb537b0b286ad47feb7f5b26d161',
    'private.facturacion_operaciones_visibles': '17c2ca27996adad88f685896915953e3',
    'private.cliente_ids_visibles_crm': '6e3e3442103b216116a263ae6342e852',
    'private.vendedor_ids_visibles': '85544c70a0920f3a7a1b5da06935f236',
    'private.es_lector_global': 'c8be602f84348a0125617995802db618',
    'private.rol_crm': '99827f3fe2fbc3cfae5668c30015c758',
    'crm.cierres_externos_fn': '67f5f9c020ea6395da20444911bd303b',
    'private.analista_efectivo_cierre': '2cf2201f8a01c381a7756293fbdadd46',
    'crm.cartera_inversionistas_filtrada_fn': '79aac4ba40c5ca7b2be8614e845ff301',
    'private.cartera_f5_listar': '33d7d57b097787cf649ca84649bb721a',
}


def entre(texto, nombre):
    inicio, fin = f'-- INICIO {nombre}\n', f'-- FIN {nombre}\n'
    assert texto.count(inicio) == texto.count(fin) == 1, nombre
    assert texto.index(inicio) < texto.index(fin), f'{nombre}: marcadores invertidos'
    return texto.split(inicio)[1].split(fin)[0]


def sustituir(texto, nombre, nuevo):
    viejo = entre(texto, nombre)
    return texto.replace(f'-- INICIO {nombre}\n{viejo}-- FIN {nombre}\n',
                         f'-- INICIO {nombre}\n{nuevo}-- FIN {nombre}\n')


def principal():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verificar', action='store_true')
    args = parser.parse_args()
    for nombre, huella in HUELLAS.items():
        assert hashlib.md5((CARPETA / 'vivo' / f'{nombre}.sql').read_bytes()).hexdigest() == huella, nombre
    migracion = MIGRACION.read_text()
    reversa = (CARPETA / 'reversa.sql').read_text()
    nueva_reversa = sustituir(reversa, 'HUELLAS', entre(migracion, 'HUELLAS'))
    salidas = {CARPETA / 'reversa.sql': nueva_reversa}
    for nombre in ('ensayo-sintetico.sql', 'ensayo-produccion.sql', 'medir.sql'):
        ruta = CARPETA / nombre
        contenido = sustituir(ruta.read_text(), 'MIGRACION', entre(migracion, 'TRANSACCION'))
        if nombre == 'ensayo-sintetico.sql':
            contenido = sustituir(contenido, 'COMPARADOR SINTETICO', entre(migracion, 'COMPARADOR'))
            contenido = sustituir(contenido, 'REVERSA', entre(nueva_reversa, 'TRANSACCION'))
        salidas[ruta] = contenido
    for ruta, contenido in salidas.items():
        if args.verificar:
            assert ruta.read_text() == contenido, f'{ruta.name}: copia desincronizada'
        else:
            ruta.write_text(contenido)
    print('PASS: cuerpos vivos, DO de migración, comparador y reversa sincronizados')


if __name__ == '__main__':
    principal()
