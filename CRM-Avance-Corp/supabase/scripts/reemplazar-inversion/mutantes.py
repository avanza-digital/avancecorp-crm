#!/usr/bin/env python3
"""Mutantes de «Reemplazar inversión» (20261017162053): por cada defensa, una versión de la función que la neutraliza.
Cada mutante se instala DENTRO de la transacción de la batería (test-reemplazar-inversion.sql) y se deshace con ella.
Veredicto por mutante: MUERTO (la batería falla, la defensa está probada), SOBREVIVE (la batería pasa: la defensa NO está
probada) o NO SE PUDO INSTALAR (el reemplazo no aparece exactamente una vez, o el DDL falla: cuenta como vivo).
Sale con código 1 si queda alguno vivo.

  python3 -I mutantes.py            # banco reemplazo-inv-db con la migración aplicada
"""
import os
import re
import subprocess
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.abspath(os.path.join(AQUI, '..', '..'))
MIGRACION = os.path.join(RAIZ, 'migrations', '20261017162053_crm_reemplazar_inversion.sql')
BATERIA = os.path.join(AQUI, 'test-reemplazar-inversion.sql')
CONTENEDOR = os.environ.get('BANCO_CONTENEDOR', 'reemplazo-inv-db')
def clave_del_banco():
    # La contraseña del banco local NO va en el repo: BANCO_PGPASSWORD, o la de conexion.env (fuera del repo).
    if os.environ.get('BANCO_PGPASSWORD'):
        return os.environ['BANCO_PGPASSWORD']
    ruta = os.path.join(os.environ.get('BANCO_DIR', os.path.expanduser('~/dev/banco-reemplazar-inversion')), 'conexion.env')
    for linea in open(ruta, encoding='utf-8'):
        if linea.startswith('PGPASSWORD='):
            return linea.split('=', 1)[1].strip()
    sys.exit('Falta BANCO_PGPASSWORD (o conexion.env en BANCO_DIR)')


CLAVE = clave_del_banco()
PASS_FIJO = 'PASS reemplazar_inversion: 45 bloques'


def psql(sql, usuario='supabase_admin'):
    r = subprocess.run(['docker', 'exec', '-i', '-e', f'PGPASSWORD={CLAVE}', CONTENEDOR, 'psql', '-U', usuario, '-h',
                        '127.0.0.1', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-qAt', '-f', '-'],
                       input=sql, capture_output=True, text=True)
    return r.stdout + r.stderr


def funcion_de_migracion(nombre):
    texto = open(MIGRACION, encoding='utf-8').read()
    m = re.search(r'create function ' + re.escape(nombre) + r'\(.*?\n\$function\$;\n', texto, re.S)
    assert m, nombre
    return 'create or replace function' + m.group(0)[len('create function'):]


def funcion_viva(firma):
    return psql(f"set search_path = ''; select pg_catalog.pg_get_functiondef('{firma}'::regprocedure);", 'postgres').rstrip() + ';\n'


NUCLEO = funcion_de_migracion('private.reemplazar_inversion_avance')
PUERTA = funcion_de_migracion('crm.reemplazar_inversion_fn')
PUERTA_EXISTENTE = funcion_de_migracion('crm.reemplazar_inversion_por_existente_fn')
SIN_PORTAL_PUERTA = [("  if v_roles ->> 'portal' is null then\n    raise exception 'Una inversión de Avance la reemplaza un admin del portal'",
                      "  if false then\n    raise exception 'Una inversión de Avance la reemplaza un admin del portal'")]
CANDADO = funcion_viva('private.trg_contratos_observar_rentabilidad()')

# (nombre, base, [(antes, después), ...]) — cada «antes» debe aparecer EXACTAMENTE una vez.
MUTANTES = [
    ('sin sello de mes', NUCLEO, [("  if exists (select 1 from crm.periodos_cerrados pc where pc.periodo >= v_periodos[1])",
                                   "  if false and exists (select 1 from crm.periodos_cerrados pc where pc.periodo >= v_periodos[1])")]),
    ('sin «detrás del último sello»', NUCLEO, [("pc.periodo >= v_periodos[1]", "pc.periodo = any (v_periodos)"),
                                              ("s.periodo >= v_periodos[1]", "s.periodo = any (v_periodos)")]),
    ('sin el detector de las anulaciones', NUCLEO, [("if v_venta.p_desconocido or v_venta.p_sellado then", "if false then")]),
    ('sin el plazo antes de borrar', NUCLEO, [("  if v_mueve_venta and v_acr.estado = 'acreditada'\n     and pg_catalog.clock_timestamp()",
                                              "  if false and v_mueve_venta and v_acr.estado = 'acreditada'\n     and pg_catalog.clock_timestamp()")]),
    ('sin la red final de la conversión', NUCLEO, [("    if v_acr2.id is distinct from v_acr.id or v_acr2.fuente_tipo is distinct from 'contrato'",
                                                    "    if false and (v_acr2.id is distinct from v_acr.id or v_acr2.fuente_tipo is distinct from 'contrato'"),
                                                   ("       or v_acr2.periodo_comercial is distinct from pg_catalog.date_trunc('month', v_fecha_cc::timestamp)::date then",
                                                    "       or v_acr2.periodo_comercial is distinct from pg_catalog.date_trunc('month', v_fecha_cc::timestamp)::date) then")]),
    ('sin «no crear acreditación nueva»', NUCLEO, [("  if v_lead is not null and not v_mueve_venta\n     and exists",
                                                    "  if false and v_lead is not null and not v_mueve_venta\n     and exists")]),
    ('sin Gerencia para la venta de un lead', NUCLEO, [("    if not v_gerencia then\n      raise exception 'Esta inversión es la venta de un lead: solo gerencia puede reemplazarla' using errcode = '42501';\n    end if;\n    if v_lead is null then",
                                                        "    if false then\n      raise exception 'Esta inversión es la venta de un lead: solo gerencia puede reemplazarla' using errcode = '42501';\n    end if;\n    if v_lead is null then")]),
    ('sin admin del portal (puerta y núcleo)', [(PUERTA, SIN_PORTAL_PUERTA), (NUCLEO, [("  if v_portal is null then\n    raise exception 'Una inversión de Avance la reemplaza un admin del portal' using errcode = '42501';\n  end if;\n  v_no :=",
                                       "  if false then\n    raise exception 'Una inversión de Avance la reemplaza un admin del portal' using errcode = '42501';\n  end if;\n  v_no :=")])]),
    ('sin rechazar la membresía revocada (puerta nueva)', PUERTA, [("  if private.membresia_crm_revocada() then", "  if false then")]),
    ('sin rechazar la membresía revocada (quedarme con la otra)', PUERTA_EXISTENTE, [("  if private.membresia_crm_revocada() then", "  if false then")]),
    ('sin «mismo cliente»', NUCLEO, [("       and p_contrato ? 'cliente_id' then", "       and false then")]),
    ('sin «mismo analista» al conservar', NUCLEO, [("if v_cons.analista_cierre_id is distinct from v_orig.analista_cierre_id then", "if false then")]),
    ('sin conservar el día de la venta', NUCLEO, [("    v_fecha_cc := least(v_fi, v_dia_registro);",
                                                   "    v_fecha_cc := least(v_fi, (now() at time zone 'America/Lima')::date);")]),
    ('sin la cadena de reemplazos', NUCLEO, [("    (select (ie.snapshot #>> '{reemplazo,dia_registro_venta}')::date from crm.inversiones_eliminadas ie\n      where ie.reemplazada_por = p_fuente",
                                              "    (select null::date from crm.inversiones_eliminadas ie\n      where ie.reemplazada_por = p_fuente")]),
    ('sin la marca de primera conversión', NUCLEO, [("  if coalesce(v_primera, false) then", "  if false then")]),
    ('sin idempotencia', NUCLEO, [("    if v_previo.id is not null and v_previo.reemplazada_por is not null then", "    if false then")]),
    ('reintento sin Gerencia para una venta', NUCLEO, [("      if v_previo.es_conversion and not v_gerencia then", "      if false then")]),
    ('reintento sin comparar datos', NUCLEO, [("if v_previo.snapshot #>> '{reemplazo,huella_pedido}' is distinct from v_huella_pedido then", "if false then")]),
    ('sin rechazar la conservada en eliminación', NUCLEO, [("    if private.contrato_en_eliminacion(p_conservar) then", "    if false then")]),
    ('sin rechazar la venta acreditada a otra inversión', NUCLEO, [("    if v_acr.id is not null and (v_acr.fuente_tipo, v_acr.fuente_id) is distinct from ('contrato'::text, p_fuente) then",
                                                                     "    if false then")]),
    ('sin la válvula del re-enlace', NUCLEO, [("    perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);\n    update crm.leads l set contrato_id = v_nuevo",
                                               "    update crm.leads l set contrato_id = v_nuevo")]),
    ('sin diferir el candado de tasa', NUCLEO, [("  set constraints public.trg_contratos_zz_observar_rentabilidad immediate;\n  set constraints public.trg_contratos_zz_observar_rentabilidad deferred;\n",
                                                 "  set constraints public.trg_contratos_zz_observar_rentabilidad immediate;\n")]),
    ('sin rechazar las cuotas pagadas', NUCLEO, [("             and (cp.estado in ('pagado', 'trasladado') or cp.monto_pagado is not null)) then",
                                                  "             and false) then")]),
    ('sin Gerencia para el origen confirmado', NUCLEO, [("  if v_origen_conf.id is not null and not v_gerencia then", "  if false then")]),
    ('sin pasar el origen confirmado', NUCLEO, [("  if v_origen_conf.id is not null and not exists (select 1 from crm.origenes_capital_confirmados o",
                                                 "  if false and not exists (select 1 from crm.origenes_capital_confirmados o")]),
    ('sin exigir un duplicado igual', NUCLEO, [("        v_orig.fecha_vencimiento, v_orig.modalidad, v_orig.tipo_interes) then",
                                                "        v_orig.fecha_vencimiento, v_orig.modalidad, v_orig.tipo_interes) and false then")]),
    ('conservar con el día de la duplicada', NUCLEO, [("    v_fi := v_cons.fecha_inicio;\n  end if;",
                                                       "    v_fi := v_cons.fecha_inicio;\n    v_dia_registro := (v_cons.creado_en at time zone 'America/Lima')::date;\n  end if;")]),
    ('sin pasar la fecha comercial a la inversión', NUCLEO, [("    update crm.inversiones i set fecha_comercial = v_fecha_cc where", "    update crm.inversiones i set fecha_comercial = i.fecha_comercial where")]),
    ('sin pasar los cotitulares', NUCLEO, [("    if not (p_contrato ? 'titulares') and v_titulares is not null then", "    if false then")]),
    # Solo el IMMEDIATE (el DEFERRED se queda): así no cae antes en C20 y llega a C33 (Codex r3, P2).
    ('sin juzgar la tasa de la fuente antes de borrarla', NUCLEO, [("  set constraints public.trg_contratos_zz_observar_rentabilidad immediate;\n  set constraints public.trg_contratos_zz_observar_rentabilidad deferred;\n",
                                                                    "  set constraints public.trg_contratos_zz_observar_rentabilidad deferred;\n")]),
    ('sin comparar los cotitulares al conservar', NUCLEO, [("                from public.contrato_titulares t where t.contrato_id = p_fuente) x) then",
                                                          "                from public.contrato_titulares t where t.contrato_id = p_fuente) x) and false then")]),
    ('reintento sin Gerencia por el origen confirmado', NUCLEO, [("      if coalesce((v_previo.snapshot #>> '{reemplazo,origen_confirmado}')::boolean, false) and not v_gerencia then", "      if false then")]),
    ('sin rechazar el lead enlazado a otra inversión', NUCLEO, [("    if (select l.contrato_id from crm.leads l where l.id = v_lead) is not null then", "    if false then")]),
    ('cadena: sin preferir la copia de la venta', NUCLEO, [("order by ie.es_conversion desc, ie.eliminado_en desc", "order by ie.es_conversion asc, ie.eliminado_en desc")]),
    ('candado: sin la condición de producto', CANDADO, [("\n                  and private.rentabilidad_condicion_declarada((a.snapshot #>> '{contrato,producto_condicion_id}')::uuid)\n                      is not distinct from private.rentabilidad_condicion_declarada(v_c.producto_condicion_id));", ");")]),
    ('cotitulares sin ordenar', NUCLEO, [("    if (select coalesce(pg_catalog.array_agg(x.k order by x.k), '{}')", "    if (select coalesce(pg_catalog.array_agg(x.k), '{}')")]),
    ('sin dejar pasar el lead ya enlazado a la conservada', NUCLEO, [("     and (p_conservar is null or (select l.contrato_id from crm.leads l where l.id = v_lead) is distinct from p_conservar) then", " then")]),
    ('rol de la copia sin el origen confirmado', NUCLEO, [("  v_rol := case when v_es_conversion or v_origen_conf.id is not null then", "  v_rol := case when v_es_conversion then")]),
    ('copia sin recordar el origen confirmado', NUCLEO, [("      'origen_confirmado', v_origen_conf.id is not null));", "      'origen_confirmado', false));")]),
    ('candado: sin la excepción de enforcement', CANDADO, [("elsif v_c.tasa_anual > v_base and v_reemplazo_misma_huella then", "elsif false then")]),
    ('candado: herencia sin exigir la misma intención', CANDADO, [("elsif v_c.tasa_anual > v_base and v_reemplazo_misma_huella then",
                                                                   "elsif v_c.tasa_anual > v_base and v_reemplazo_tasa then")]),
    ('candado: sin la excepción de observación', CANDADO, [("case when v_reemplazo_tasa then v_c.tasa_anual else 0 end", "0")]),
    ('candado: sin comparar con la tasa del eliminado', CANDADO, [("\n                  and (a.snapshot #>> '{contrato,tasa_anual}')::numeric = v_c.tasa_anual);", ");")]),
]


def cuerpo_bateria():
    t = open(BATERIA, encoding='utf-8').read()
    t = t.replace('\\set ON_ERROR_STOP on\nbegin;\n', '', 1)
    assert t.rstrip().endswith('rollback;')
    return t.rstrip()[:-len('rollback;')]


def main():
    base = cuerpo_bateria()
    vivos = 0
    for entrada in MUTANTES:
        nombre = entrada[0]
        partes = entrada[1] if len(entrada) == 2 else [(entrada[1], entrada[2])]
        ddls = []
        instalable = True
        for cuerpo, cambios in partes:
            ddl = cuerpo
            for antes, despues in cambios:
                if ddl.count(antes) != 1:
                    instalable = False
                    break
                ddl = ddl.replace(antes, despues)
            ddls.append(ddl)
        ddl = '\n'.join(ddls)
        if not instalable:
            print(f'  NO SE PUDO INSTALAR  {nombre} (el ancla no aparece exactamente una vez)')
            vivos += 1
            continue
        sql = '\\set ON_ERROR_STOP on\nbegin;\n' + ddl + '\n\\echo MUTANTE_INSTALADO\n' + base + 'rollback;\n'
        salida = psql(sql)
        if 'MUTANTE_INSTALADO' not in salida:
            print(f'  NO SE PUDO INSTALAR  {nombre}: {salida.strip().splitlines()[-1][:160] if salida.strip() else ""}')
            vivos += 1
        elif PASS_FIJO in salida:
            print(f'  SOBREVIVE            {nombre}')
            vivos += 1
        else:
            causa = next((l for l in salida.splitlines() if 'ERROR' in l), '').split('ERROR:')[-1].strip()[:140]
            print(f'  MUERTO               {nombre}  ← {causa}')
    print(f'{len(MUTANTES) - vivos}/{len(MUTANTES)} mutantes muertos')
    sys.exit(1 if vivos else 0)


if __name__ == '__main__':
    main()
