#!/usr/bin/env python3
"""Mutantes de la vista previa del mes (20261017211313): por cada defensa, una versión de la función VIVA que la neutraliza.
probar.sh la instala al principio de cada corrida (batería entera de la Fase 1 y pruebas de la vista previa, las dos en
ROLLBACK). Antes, una corrida BASE sin mutante tiene que pasar (si no, el ensayo no vale y se aborta). MUERTO = probar.sh
sale con 1 (una ASERCIÓN de la batería lo detectó); SOBREVIVE = sale con 0; ERROR DE ENSAYO = cualquier otra salida
(conexión, contraseña, un mutante que no instala, un error que no es una aserción); NO SE PUDO INSTALAR = el ancla no
aparece exactamente una vez. Todo lo que no es MUERTO cuenta en contra: sale con código 1.

  python3 -I mutantes.py            # banco reemplazo-inv-db con la Fase 1 y esta migración aplicadas
"""
import os
import subprocess
import sys
import tempfile

AQUI = os.path.dirname(os.path.abspath(__file__))
CONTENEDOR = os.environ.get('BANCO_CONTENEDOR', 'reemplazo-inv-db')


def funcion_viva(firma):
    r = subprocess.run(['docker', 'exec', '-i', CONTENEDOR, 'psql', '-U', 'postgres', '-d', 'postgres', '-qAt', '-c',
                        f"set search_path = ''; select pg_catalog.pg_get_functiondef('{firma}'::regprocedure)"],
                       capture_output=True, text=True, check=True)
    return r.stdout.rstrip() + ';\n'


DIA = funcion_viva('private.reemplazo_dia_registro_venta(uuid)')
FECHA = funcion_viva('private.reemplazo_fecha_comercial(uuid,date)')
CUOTAS = funcion_viva('private.contrato_tiene_cuotas_pagadas(uuid)')
PUERTA = funcion_viva('crm.reemplazar_inversion_vista_previa_fn(uuid,date,uuid)')

# (nombre, base, [(antes, después), ...]) — cada «antes» debe aparecer EXACTAMENTE una vez.
MUTANTES = [
    ('día de la venta sin la cadena de copias', DIA, [(
        "(select (ie.snapshot #>> '{reemplazo,dia_registro_venta}')::date from crm.inversiones_eliminadas ie\n"
        "      where ie.reemplazada_por = p_fuente order by ie.es_conversion desc, ie.eliminado_en desc, ie.id desc limit 1),",
        "null::date,")]),
    ('día de la venta sin preferir la copia de una venta', DIA, [("order by ie.es_conversion desc,", "order by ie.es_conversion asc,")]),
    ('fecha sin conservar la corrección de Gerencia', FECHA, [(
        "then least(p_fecha_inicio, d.dia) else c.fecha_cierre_comercial end,",
        "then least(p_fecha_inicio, d.dia) else least(p_fecha_inicio, d.dia) end,")]),
    ('fecha sin el día de la venta', FECHA, [("then least(p_fecha_inicio, d.dia) else", "then p_fecha_inicio else")]),
    ('cuotas pagadas: la regla siempre dice que no', CUOTAS, [("  select exists (select 1 from public.cronograma_pagos cp where cp.contrato_id = p_contrato",
                                                            "  select false and exists (select 1 from public.cronograma_pagos cp where cp.contrato_id = p_contrato")]),
    ('previa sin avisar las cuotas pagadas', PUERTA, [("    'cuotas_pagadas', private.contrato_tiene_cuotas_pagadas(v_orig.id));", "    'cuotas_pagadas', false);")]),
    ('previa sin exigir admin del portal', PUERTA, [("  if v_roles ->> 'portal' is null then\n", "  if false then\n")]),
    ('previa sin mirar la membresía revocada', PUERTA, [("  if private.membresia_crm_revocada() then", "  if false then")]),
    ('previa sin exigir el mismo cliente', PUERTA, [("    if v_cons.cliente_id is distinct from v_orig.cliente_id then", "    if false then")]),
    ('previa sin rechazar la misma inversión', PUERTA, [("    if v_cons.id = v_orig.id then", "    if false then")]),
    ('previa sin la fecha de la que se conserva', PUERTA, [("    v_fi := v_cons.fecha_inicio;", "    v_fi := p_fecha_inicio;")]),
    ('previa sin exigir la fecha de inicio', PUERTA, [("    if p_fecha_inicio is null or not pg_catalog.isfinite(p_fecha_inicio) then", "    if false then")]),
    ('previa sin rechazar fechas infinitas', PUERTA, [("    if p_fecha_inicio is null or not pg_catalog.isfinite(p_fecha_inicio) then", "    if p_fecha_inicio is null then")]),
    ('previa con «cambia de mes» al revés', PUERTA, [("    'cambia_mes', pg_catalog.date_trunc('month', v_res.fecha_comercial::timestamp)\n                  is distinct from",
                                                   "    'cambia_mes', pg_catalog.date_trunc('month', v_res.fecha_comercial::timestamp)\n                  is not distinct from")]),
    ('previa con «fecha corregida» al revés', PUERTA, [("    'fecha_corregida', v_res.fuente_cierre_comercial not in ('registro', 'fecha_inicio_inferida'),",
                                                     "    'fecha_corregida', v_res.fuente_cierre_comercial in ('registro', 'fecha_inicio_inferida'),")]),
    ('previa que escribe', PUERTA, [(
        "  select * into v_res from private.reemplazo_fecha_comercial(p_fuente_id, v_fi);",
        "  update crm.equipo e set activo = e.activo where e.perfil_id = v_uid;\n"
        "  select * into v_res from private.reemplazo_fecha_comercial(p_fuente_id, v_fi);")]),
]


def main():
    base = subprocess.run(['bash', os.path.join(AQUI, 'probar.sh')], env={k: v for k, v in os.environ.items() if k != 'MUTANTE_SQL'},
                          capture_output=True, text=True)
    if base.returncode != 0:
        print(f'ENSAYO INVÁLIDO: la corrida base (sin mutante) no pasa (salida {base.returncode}):')
        print(base.stdout + base.stderr)
        sys.exit(2)
    print('  base sin mutante: PASS')
    vivos = 0
    for nombre, base, cambios in MUTANTES:
        ddl = base
        instalable = True
        for antes, despues in cambios:
            if ddl.count(antes) != 1:
                instalable = False
                break
            ddl = ddl.replace(antes, despues)
        if not instalable:
            print(f'  NO SE PUDO INSTALAR  {nombre} (el ancla no aparece exactamente una vez)')
            vivos += 1
            continue
        with tempfile.NamedTemporaryFile('w', suffix='.sql', delete=False, encoding='utf-8') as f:
            f.write(ddl)
            ruta = f.name
        try:
            r = subprocess.run(['bash', os.path.join(AQUI, 'probar.sh')], env={**os.environ, 'MUTANTE_SQL': ruta},
                               capture_output=True, text=True)
        finally:
            os.unlink(ruta)
        if r.returncode == 0:
            print(f'  SOBREVIVE            {nombre}')
            vivos += 1
        elif r.returncode == 1:
            causa = next((l for l in r.stdout.splitlines() if 'FALLA' in l), '→').split('→', 1)[1].strip()[:150]
            print(f'  MUERTO               {nombre}  ← {causa}')
        else:
            causa = next((l for l in r.stdout.splitlines() if 'ERROR DE ENSAYO' in l), (r.stdout + r.stderr).strip()[:150])
            print(f'  ERROR DE ENSAYO      {nombre} (salida {r.returncode})  ← {causa.strip()[:150]}')
            vivos += 1
    print(f'{len(MUTANTES) - vivos}/{len(MUTANTES)} mutantes muertos')
    sys.exit(1 if vivos else 0)


if __name__ == '__main__':
    main()
