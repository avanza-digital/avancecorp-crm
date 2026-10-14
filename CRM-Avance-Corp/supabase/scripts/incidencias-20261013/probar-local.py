#!/usr/bin/env python3
"""Ensayo transaccional: banco local preparado, nunca producción.

Uso: python3 probar-local.py CONTENEDOR crm_incidencias_verificadas
Requiere las dos correcciones instaladas y fixtures CRM preexistentes.
"""
import json
from pathlib import Path
import subprocess
import sys

KIT = Path(__file__).resolve().parent
MIGRACIONES = KIT.parents[1] / 'migrations'
if len(sys.argv) != 3 or not sys.argv[2].startswith('crm_incidencias_'):
    raise SystemExit(__doc__)


def ejecutar(sql):
    return subprocess.run(
        ['docker', 'exec', '-i', sys.argv[1], 'psql', '-X', '-U', 'postgres',
         '-d', sys.argv[2], '-v', 'ON_ERROR_STOP=1'],
        input=sql, text=True, capture_output=True, check=False,
    )


def transaccion(sql):
    return sql.replace('\nbegin;\n', '\n', 1).rsplit('\ncommit;', 1)[0]


casos = []


def probar(nombre, sql, error=None):
    resultado = ejecutar('begin;\n' + sql + '\nrollback;\n')
    if error is None:
        assert resultado.returncode == 0, (nombre, resultado.stderr)
    else:
        assert resultado.returncode != 0 and error in resultado.stderr, (nombre, resultado.stderr)
    casos.append(nombre)
    print('PASS:', nombre)


f7 = transaccion((MIGRACIONES / '20261014001044_crm_f7_redeclarar_huella_metricas_cartera.sql').read_text())
sla = transaccion((MIGRACIONES / '20261014001346_crm_sla_agrupar_tareas_por_lead.sql').read_text())
previa = """
alter table private.f7_piezas_en_observacion disable trigger trg_f7_obs_00_solo_crece;
update private.f7_piezas_en_observacion set huella_md5='0b4ede547cf7079be1e56073311453b3'
 where firma='crm.metricas_cartera_fn(date)';
alter table private.f7_piezas_en_observacion enable trigger trg_f7_obs_00_solo_crece;
"""
probar('F7 repara solo la huella, conserva cierre y reactiva candado', previa + f7)
probar('F7 rechaza repetición', f7, 'alguien ya la toco')
probar('F7 rechaza apertura de ACL', previa + 'grant execute on function crm.metricas_cartera_fn(date) to anon;\n' + f7, 'SE REABRIO')
probar('F7 rechaza cambio de atributos', previa + 'alter function crm.metricas_cartera_fn(date) security invoker;\n' + f7, 'DEFINICION completa')
probar('F7 rechaza otra pieza derivada', previa + """
alter table private.f7_piezas_en_observacion disable trigger trg_f7_obs_00_solo_crece;
update private.f7_piezas_en_observacion set huella_md5=repeat('0',32)
 where firma=(select firma from private.f7_piezas_en_observacion
 where firma<>'crm.metricas_cartera_fn(date)' and estado in ('observacion','cerrada_permanente') limit 1);
alter table private.f7_piezas_en_observacion enable trigger trg_f7_obs_00_solo_crece;
""" + f7, 'pieza(s) MAS')
# Mutantes del vigilante solo dentro del rollback: ejercen las ramas de rechazo.
probar('F7 rechaza vigilante ya verde', previa + """
create or replace function private.assert_f7_piezas_cerradas() returns text
language plpgsql as $f$ begin return 'OK'; end $f$;
""" + f7, 'ya esta VERDE')
probar('F7 rechaza causa distinta del vigilante', previa + """
create or replace function private.assert_f7_piezas_cerradas() returns text
language plpgsql as $f$ begin raise exception 'F7: causa distinta sintética'; end $f$;
""" + f7, 'rojo por OTRA causa')
probar('SLA rechaza repetición', sla, 'definición previa distinta')
anterior = (KIT / 'sla-anterior.sql').read_text()
probar('SLA rechaza apertura de ACL', anterior + '\ngrant execute on function private.sla_operacion_leads(uuid[],boolean,uuid[],timestamptz) to anon;\n' + sla, 'propietario o ACL previos distintos')
reversa = (KIT / 'reversa-sla.sql').read_text().replace('begin;\n', '', 1).rsplit('\ncommit;', 1)[0]
probar('SLA reversa exacta y reaplicación', reversa + '\n' + sla)
for archivo in ['casos-limite.sql', 'oraculo.sql', 'rpc-paridad.sql']:
    resultado = ejecutar((KIT / archivo).read_text())
    assert resultado.returncode == 0, (archivo, resultado.stderr)
    casos.append(archivo)
    print(resultado.stdout)
    print('PASS:', archivo)
print(json.dumps({'pruebas': len(casos), 'pass': len(casos), 'casos': casos}, ensure_ascii=False))
