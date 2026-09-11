"""Pruebas offline del generador usando definiciones locales; no abre conexiones."""
import copy
import json
import sys
from pathlib import Path
from generar_consulta import generar

definiciones = json.loads(Path(sys.argv[1]).read_text())
for postflight in [False, True]:
    sql = generar(definiciones, '2026-09-11', ['2026-08-01', '2026-09-01'], postflight)
    assert 'repeatable read read only' in sql
    assert "set local search_path='';" in sql
    assert sql.rstrip().endswith('rollback;')
    assert ('with g6_contexto' in sql) is not postflight
    assert '__HUELLAS__' not in sql

alteradas = copy.deepcopy(definiciones)
next(f for f in alteradas if f['firma'] == 'crm.metricas_multiempresa_fn(date)')['definicion'] += ' '
for datos, meses in [(definiciones, ['2026-10-01']), (definiciones, ['2026-09-02']),
                      (alteradas, ['2026-09-01'])]:
    try:
        generar(datos, '2026-09-11', meses)
    except ValueError:
        pass
    else:
        raise AssertionError('El generador aceptó un corte o cuerpo inválido')
print('PASS: dos modalidades de solo lectura y tres entradas inválidas rechazadas')
