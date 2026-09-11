#!/usr/bin/env python3
"""Crea un comparativo privado y autónomo a partir de la captura G6 verificada."""
import argparse
import hashlib
import json
from pathlib import Path


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--lectura', type=Path, required=True)
    p.add_argument('--verificacion', type=Path, required=True)
    p.add_argument('--postflight', type=Path, required=True)
    p.add_argument('--custodia', type=Path, required=True)
    p.add_argument('--revision', required=True)
    p.add_argument('--salida', type=Path, required=True)
    a = p.parse_args()
    e = json.loads(a.lectura.read_text())
    v = json.loads(a.verificacion.read_text())
    post = json.loads(a.postflight.read_text())
    custodia = json.loads(a.custodia.read_text())
    huella = hashlib.sha256(a.lectura.read_bytes()).hexdigest()
    if v['estado'] != 'PARIDAD_TECNICA_PASS' or v['capturadoEn'] != e['capturado_en'] or v.get('capturaSha256') != huella:
        raise ValueError('El informe exige verificación positiva de este mismo corte.')
    if (custodia['estado'] != 'CUSTODIA_PASS' or custodia.get('capturaSha256') != huella
            or custodia.get('postflightSha256') != hashlib.sha256(a.postflight.read_bytes()).hexdigest()):
        raise ValueError('La custodia debe corresponder exactamente a estos dos archivos.')
    if e['bandera_real'] or e['banderas'] != post['banderas']:
        raise ValueError('Estado de banderas inesperado.')
    for foto in e['fotos_selladas']:
        actual = next(f for f in post['fotos_selladas'] if f['periodo'] == foto['periodo'])
        if any(actual[k] != foto[k] for k in ['huella_periodo', 'huella_filas', 'filas']):
            raise ValueError('La foto sellada cambió.')
    meses = []
    for m in e['meses']:
        i = m['informe']
        meses.append({
            'mes': m['mes'], 'hasta': m['hasta'], 'sellado': i['mes_sellado'],
            'capital': i['conciliacion'], 'tipos': i['tipos_capital'],
            'conversion': i['conversion'], 'conversionOficial': m['conversion_publicada']['total'],
            'cobertura': m['cobertura_capital'],
            'atribucion': [{k: f[k] for k in ['empresa', 'moneda', 'analista_nombre', 'operaciones', 'capital']}
                           for f in i['atribucion']],
            'operaciones': [{k: f[k] for k in ['referencia', 'empresa', 'moneda', 'capital',
                              'tipo', 'fecha', 'analista', 'en_roster', 'identidad_estado']}
                            for f in m['detalle_operaciones']],
        })
    datos = {
        'captura': e['capturado_en'], 'sha256': huella,
        'meses': meses, 'verificacion': v, 'personas': e['personas_referencia'],
        'vencimientos': e['vencimientos_referencia'], 'oportunidades': e['oportunidades_referencia'],
        'pendientes': [{k: f[k] for k in ['referencia', 'nombre', 'empresa', 'fecha', 'moneda', 'capital']}
                       for f in e['pendientes_identidad']],
        'revision': a.revision,
    }
    # No permite que un nombre o referencia cierre el bloque script.
    seguro = json.dumps(datos, ensure_ascii=False).replace('<', '\\u003c').replace('\u2028', '\\u2028').replace('\u2029', '\\u2029')
    html = Path(__file__).with_name('informe.html.in').read_text().replace('__DATOS_G6__', seguro)
    a.salida.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    a.salida.write_text(html)
    a.salida.chmod(0o600)
    print('Comparativo privado creado:', a.salida)


if __name__ == '__main__':
    main()
