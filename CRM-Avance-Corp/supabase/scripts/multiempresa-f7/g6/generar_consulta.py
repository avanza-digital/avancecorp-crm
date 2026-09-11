#!/usr/bin/env python3
"""Genera la lectura G6; no se conecta a una base ni cambia la bandera F7."""
import argparse
import datetime
import hashlib
import json
import re
from pathlib import Path

HUELLAS = {
    'crm.metricas_multiempresa_fn(date)': '4ab8a07f4794c015c4bb7264206dafcf',
    'private.metricas_f7_fuentes()': '260337e6aa59f90ad1c7158123770366',
    'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])': 'c9e58c1da9dd7a5d52991c9e47dc19d5',
    'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)': '8a2549dbfa59c732da04900ed90b6361',
    'private.cartera_f5_fuentes()': '94fa33cfcca657f70a1a94f98c3bf482',
    'private.peso_referido_conversion(date)': '3a80775b21767839e524880d419689f3',
    'crm.metricas_capital_mes_fn(integer)': 'c872d4be13e8284a64e70861318cb9be',
    'crm.conversion_mensual_fn(date)': 'e8b7bbfa62e46bcd5a680a9a5996a8d0',
    'crm.conversion_mensual_sin_cartera_fn(date)': 'e2e2bf8fe3c71620a3db01de3cddc33b',
    'private.inversionista_canonica(uuid)': '34702897135078893b7d3a726b0c1816',
}


def generar(definiciones, hoy, meses, postflight=False):
    hoy = datetime.date.fromisoformat(hoy)
    meses = sorted(set(datetime.date.fromisoformat(m) for m in meses))
    if not meses or any(m.day != 1 or m.year < 2000 or m > hoy for m in meses):
        raise ValueError('Se requieren meses válidos, iniciados en día 1 y no futuros.')
    filas = [f for f in definiciones if f['firma'] == 'crm.metricas_multiempresa_fn(date)']
    if len(filas) != 1:
        raise ValueError('Falta la definición productiva única de F7.')
    fuente = filas[0]['definicion']
    huella = hashlib.md5(fuente.encode()).hexdigest()
    if huella != HUELLAS[filas[0]['firma']] or huella != filas[0]['huella']:
        raise ValueError('La definición F7 no coincide con la instalada y revisada.')
    inicio = '  with fuentes as materialized ('
    fin = ') into v_payload;'
    if fuente.count(inicio) != 1 or fuente.count(fin) != 1:
        raise ValueError('Fronteras de la proyección F7 inesperadas.')
    proyeccion = fuente[fuente.index(inicio):fuente.index(fin) + 1]
    original_sha = hashlib.sha256(proyeccion.encode()).hexdigest()
    variables = {'v_hoy': 'hoy', 'v_mes': 'mes', 'v_hasta': 'hasta',
                 'v_ini': 'ini', 'v_fin': 'fin', 'v_factor': 'factor'}
    # La sustitución solo es válida para este cuerpo fijado e inspeccionado:
    # no contiene estas variables dentro de literales/comentarios SQL.
    # MD5 detecta cambios de pg_get_functiondef; no es una firma de autenticidad.
    for nombre, columna in variables.items():
        proyeccion = re.sub(r'\b' + nombre + r'\b', 'g6_param.' + columna, proyeccion)
    if re.search(r'\bv_\w+\b', proyeccion):
        raise ValueError('Quedó una variable PL/pgSQL sin resolver.')
    plantilla = Path(__file__).with_name('consulta.sql.in').read_text()
    if postflight:
        plantilla = plantilla[:plantilla.index('with g6_contexto')]
        plantilla += 'select (__METADATOS__) as evidencia;\nrollback;\n'
    plantilla = plantilla.replace('__METADATOS__', Path(__file__).with_name('metadatos.sql.in').read_text())
    valores = ',\n'.join(f"('{firma}','{sello}')" for firma, sello in HUELLAS.items())
    reemplazos = {
        '__HUELLAS__': valores,
        '__HOY__': hoy.isoformat(),
        '__MESES__': ','.join(f"(date '{m.isoformat()}')" for m in meses),
        '__PROYECCION_F7__': proyeccion,
        '__SHA_PROYECCION__': original_sha,
        '__MESES_CAPITAL__': str((hoy.year - meses[0].year) * 12 + hoy.month - meses[0].month + 1),
    }
    if int(reemplazos['__MESES_CAPITAL__']) > 60:
        raise ValueError('El comparador publicado permite como máximo 60 meses.')
    for marcador, contenido in reemplazos.items():
        if marcador not in plantilla and not postflight:
            raise ValueError('Marcador ausente: ' + marcador)
        plantilla = plantilla.replace(marcador, contenido)
    if re.search(r'__[A-Z_]+__', plantilla):
        raise ValueError('Quedó un marcador sin sustituir.')
    return plantilla


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--definiciones', type=Path, required=True)
    parser.add_argument('--hoy', required=True)
    parser.add_argument('--mes', action='append', required=True)
    parser.add_argument('--salida', type=Path, required=True)
    parser.add_argument('--postflight', action='store_true', help='Solo custodia posterior, sin cifras ni identidades.')
    args = parser.parse_args()
    consulta = generar(json.loads(args.definiciones.read_text()), args.hoy, args.mes, args.postflight)
    args.salida.write_text(consulta)
    args.salida.chmod(0o600)
    print('Consulta de solo lectura generada; SHA-256:', hashlib.sha256(consulta.encode()).hexdigest())


if __name__ == '__main__':
    main()
