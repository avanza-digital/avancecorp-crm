#!/usr/bin/env python3
"""Mutantes de 20261018032400 (recuperar las cinco ventas recargadas): por cada defensa de la MIGRACIÓN, una versión del
texto que la neutraliza; la batería (probar.sh con MUTANTE_MIGRACION) tiene que tumbarla. Aquí las funciones no existen
hasta que la migración corre, así que se muta el TEXTO de la migración, no una función viva del banco.
Veredicto: MUERTO (probar.sh sale 1: una aserción o una defensa saltó), SOBREVIVE (sale 0: la defensa NO está probada) o
ENSAYO (sale 3, o el ancla no aparece exactamente una vez: cuenta como vivo). Sale con 1 si queda alguno vivo.
Los parches de las cuatro funciones van siempre con la huella del postflight apagada: si no, la huella los mataría a
todos y no se sabría si la prueba de la FUNCIÓN tiene dientes.

  python3 -I mutantes.py            # banco reemplazo-inv-db (misma contraseña que probar.sh)
"""
import os
import subprocess
import sys
import tempfile

import re

AQUI = os.path.dirname(os.path.abspath(__file__))
MIGRACION = os.path.join(AQUI, '..', '..', 'migrations', '20261018032400_crm_recuperar_ventas_recargadas.sql')
PROBAR = os.path.join(AQUI, 'probar.sh')
CONTENEDOR = os.environ.get('BANCO_CONTENEDOR', 'reemplazo-inv-db')


def clave_del_banco():
    if os.environ.get('BANCO_PGPASSWORD'):
        return os.environ['BANCO_PGPASSWORD']
    ruta = os.path.join(os.environ.get('BANCO_DIR', os.path.expanduser('~/dev/banco-reemplazar-inversion')), 'conexion.env')
    for linea in open(ruta, encoding='utf-8'):
        if linea.startswith('PGPASSWORD='):
            return linea.split('=', 1)[1].strip()
    sys.exit('Falta BANCO_PGPASSWORD (o conexion.env en BANCO_DIR)')


def psql(sql):
    r = subprocess.run(['docker', 'exec', '-i', '-e', f'PGPASSWORD={clave_del_banco()}', CONTENEDOR, 'psql', '-U', 'supabase_admin',
                        '-h', '127.0.0.1', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-qAt', '-f', '-'],
                       input=sql, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit('ENSAYO: no se pudieron recalcular las huellas → ' + (r.stderr or r.stdout).strip()[-300:])
    return r.stdout.strip()


def sentencia(texto, inicio, fin):
    i = texto.index(inicio)
    return texto[i:texto.index(fin, i) + len(fin)]


def con_huellas_recalculadas(mutado):
    """Un parche neutralizado cambia el texto de la función y la huella del postflight lo mataría sola. Para saber si la
    prueba de la FUNCIÓN tiene dientes, se fijan en el postflight las huellas de las funciones MUTADAS: se calculan en el
    banco (la tabla + pg_temp.parchar + los cuatro parches del texto mutado) en una transacción que se deshace."""
    tabla = sentencia(mutado, 'create table crm.conversion_ventas_recuperadas (', '\n);\n')
    parchar = sentencia(mutado, 'create function pg_temp.parchar(', '\nend $$;\n')
    llamadas = re.findall(r"select pg_temp\.parchar\(.*?'\]\]\);\n", mutado, re.S)
    assert len(llamadas) == 4, 'ENSAYO: se esperaban cuatro parches en el texto mutado'
    sql = ("begin;\nset local search_path = '';\nset local role postgres;\n" + tabla + parchar + ''.join(llamadas) +
           "select pg_catalog.string_agg(p.oid::regprocedure::text || '=' || md5(pg_catalog.pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)\n"
           "from pg_catalog.pg_proc p where p.oid in ('private.cierre_anulado(uuid)'::regprocedure, 'crm.cierres_estado_fn(uuid[])'::regprocedure,\n"
           "  'crm.altas_nuevas_por_analista_fn(integer)'::regprocedure, 'crm.anular_cierre_avance(uuid,text)'::regprocedure);\nrollback;\n")
    nuevas = dict(par.rsplit('=', 1) for par in psql(sql).splitlines()[-1].split('|'))  # «|»: las firmas llevan comas
    # Solo las huellas DESPUÉS (postflight); las de ANTES (preflight) son las de producción y no cambian.
    corte = mutado.index('do $postflight$')
    cabeza, cola = mutado[:corte], mutado[corte:]
    for firma, huella in nuevas.items():
        patron = re.compile(r"'" + re.escape(firma) + r"=[0-9a-f]{32}(,?)'")
        assert len(patron.findall(cola)) == 1, 'ENSAYO: la huella esperada de ' + firma + ' no aparece exactamente una vez en el postflight'
        cola = patron.sub(lambda m: f"'{firma}={huella}{m.group(1)}'", cola)
    return cabeza + cola


RECALCULAR = ('__RECALCULAR_HUELLAS__', '')  # marca: tras mutar, fijar en el postflight las huellas del texto mutado
HUELLA_OFF = ("raise exception 'POSTFLIGHT recuperar_ventas: una función cambiada no quedó como se ensayó';", 'null;')
CUENTA_OFF = ("raise exception 'POSTFLIGHT recuperar_ventas: una venta recuperada no cuenta exactamente una vez en la conversión';", 'null;')
ANCLA1_OFF = ("(crm.conversion_ventas_recuperadas).\n      and not exists (select 1 from crm.conversion_ventas_recuperadas r where r.cierre_avance_anulado_id = ca.id)\n",
              "(crm.conversion_ventas_recuperadas).\n      and not exists (select 1 from crm.conversion_ventas_recuperadas r where false)\n")


def off(msg):
    return (f"raise exception '{msg}';", 'null;')


def off_caso(msg):
    return (f"raise exception '{msg}', v.caso;", 'null;')


# (nombre, [(antes, después), ...]) — cada «antes» debe aparecer EXACTAMENTE una vez en la migración.
MUTANTES = [
    # ── Preflight ──
    ('preflight: sin exigir el candado de sesión', [off('PREFLIGHT recuperar_ventas: esta sesión no tiene el candado de migraciones')]),
    ('preflight: sin las huellas de las funciones', [off('PREFLIGHT recuperar_ventas: cambió una función que la corrección cambia o llama')]),
    ('preflight: sin los metadatos', [off('PREFLIGHT recuperar_ventas: cambiaron los metadatos de una función que se cambia')]),
    ('preflight: sin «los objetos nuevos ya existen»', [off('PREFLIGHT recuperar_ventas: los objetos nuevos ya existen')]),
    ('preflight: sin «5 casos»', [off('PREFLIGHT recuperar_ventas: se esperaban 5 casos')]),
    ('preflight: sin sellos ni rango de meses', [off('PREFLIGHT recuperar_ventas: un mes de estas ventas ya está sellado o queda fuera de septiembre-octubre')]),
    ('preflight: sin el rango de meses (los sellos quedan)',
     [("                where least(c.periodo, pg_catalog.date_trunc('month', c.fecha_actual::timestamp)::date) < date '2026-09-01') then",
       "                where false) then")]),
    ('preflight: sin validar el lead', [off_caso('PREFLIGHT recuperar_ventas %: el lead no está como se midió (etapa, perfil o enlace)')]),
    ('preflight: sin validar la acreditación', [off_caso('PREFLIGHT recuperar_ventas %: la acreditación no está como se midió')]),
    ('preflight: sin «el contrato borrado existe»', [off_caso('PREFLIGHT recuperar_ventas %: el contrato borrado existe')]),
    ('preflight: sin validar el contrato vivo', [off_caso('PREFLIGHT recuperar_ventas %: el contrato vivo no está como se midió')]),
    ('preflight: sin exigir «nuevo»', [("    if v_ctr.categoria is distinct from 'nuevo' then", "    if false then")]),
    ('preflight: sin «ya es la venta de otro lead»', [off_caso('PREFLIGHT recuperar_ventas %: el contrato vivo ya es la venta de otro lead')]),
    ('preflight: sin «ajuste de mes cerrado»', [off_caso('PREFLIGHT recuperar_ventas %: el lead tiene un ajuste de mes cerrado; requiere revisión')]),
    ('preflight: sin «anulada no declarada»', [off_caso('PREFLIGHT recuperar_ventas %: la venta está anulada y no figura como anulada en los casos')]),
    ('preflight: sin «la anulación exactamente la medida»', [off_caso('PREFLIGHT recuperar_ventas %: la anulación no es exactamente la medida')]),
    ('preflight: sin el plazo de carga', [("    if pg_catalog.clock_timestamp() >= private.conversion_plazo_hasta(v.periodo) then", "    if false then")]),
    ('preflight: sin «la fecha final en el mes»', [off_caso('PREFLIGHT recuperar_ventas %: la fecha final no cae en el mes esperado')]),
    # ── Tabla y triggers ──
    # (Codex 18/10) «sin RLS con el postflight apagado» moría por I5a, no por D2: no probaba nada aparte. Fuera.
    ('tabla: el trigger de inmutabilidad no lanza (devuelve NULL): D2 exige el P0409 en UPDATE, DELETE y TRUNCATE',
     [("  raise exception 'Una venta recuperada no se modifica ni se borra: queda como historia' using errcode = 'P0409';", "  return null;")]),
    ('trigger: sin validar la acreditación',
     [("  if not exists (select 1 from crm.conversion_acreditaciones ca where ca.id = new.acreditacion_id and ca.lead_id = new.lead_id) then", "  if false then")]),
    ('trigger: sin validar la anulación',
     [("  if new.cierre_avance_anulado_id is not null\n     and not exists (select 1 from crm.cierres_avance_anulados a where a.id = new.cierre_avance_anulado_id and a.lead_id = new.lead_id) then",
       "  if false then")]),
    ('trigger: sin validar la copia',
     [("  if new.inversion_eliminada_id is not null\n     and not exists (select 1 from crm.inversiones_eliminadas ie",
       "  if false and not exists (select 1 from crm.inversiones_eliminadas ie")]),
    # ── Las cuatro funciones (siempre con la huella apagada) ──
    ('postflight: sin la huella de las funciones (sola)', [HUELLA_OFF]),
    # Las tres funciones parchadas para la app: con la huella RECALCULADA (no apagada), solo las pruebas D6 pueden matarlos.
    # Los dos de cierre_anulado los mata la red «sigue anulada» del paso 3 (la migración se niega a aplicarse), no D1.
    ('cierre_anulado: ancla 1 sin efecto (anulación), huella apagada: lo atrapa la red «sigue anulada»', [ANCLA1_OFF, HUELLA_OFF]),
    ('cierre_anulado: ancla 2 sin efecto (copia), huella apagada: lo atrapa la red «sigue anulada»',
     [("      and not exists (select 1 from crm.conversion_ventas_recuperadas r where r.inversion_eliminada_id = ie.id)\n",
       "      and not exists (select 1 from crm.conversion_ventas_recuperadas r where false)\n"), HUELLA_OFF]),
    ('cierres_estado_fn: parche sin efecto (huellas recalculadas): lo atrapa D6a',
     [("ya no se muestra como vigente.\n      and not exists (select 1 from crm.conversion_ventas_recuperadas r where r.cierre_avance_anulado_id = ca.id)\n",
       "ya no se muestra como vigente.\n      and not exists (select 1 from crm.conversion_ventas_recuperadas r where false)\n"), RECALCULAR]),
    ('altas_nuevas_por_analista_fn: parche sin efecto (huellas recalculadas): lo atrapa D6b',
     [("    where not exists (select 1 from crm.conversion_ventas_recuperadas r where r.cierre_avance_anulado_id = ca.id)\n",
       "    where not exists (select 1 from crm.conversion_ventas_recuperadas r where false)\n"), RECALCULAR]),
    ('anular_cierre_avance: parche sin efecto (huellas recalculadas): lo atrapa D6c',
     [("  if exists (select 1 from crm.conversion_ventas_recuperadas r\n             where r.lead_id = p_lead_id and r.cierre_avance_anulado_id is not null) then",
       "  if false then"), RECALCULAR]),
    ('anular_cierre_avance: otro mensaje (huellas recalculadas): lo atrapa D6c',
     [("message = ''Esta venta se anuló y después se recuperó: no se vuelve a anular. Para corregir su inversión usa «Reemplazar inversión»'';",
       "message = ''Ese cierre ya estaba anulado'';"), RECALCULAR]),
    # ── Caso por caso ──
    ('recuperar: sin corregir la fecha comercial', [("    if v_ctr.fecha_cierre_comercial is distinct from v.fecha_final then", "    if false then")]),
    ('recuperar: la corrección sin la fuente correccion_manual',
     [("set fecha_cierre_comercial = v.fecha_final, fuente_cierre_comercial = 'correccion_manual'", "set fecha_cierre_comercial = v.fecha_final")]),
    ('recuperar: sin la válvula de corrección del periodo', [("      perform pg_catalog.set_config('crm.correccion_periodo_comercial', 'on', true);\n", "")]),
    ('recuperar: sin pasar la fecha a la inversión',
     [("      update crm.inversiones i set fecha_comercial = v.fecha_final where i.contrato_id = v.recargado and i.fecha_comercial is distinct from v.fecha_final;\n", "")]),
    ('recuperar: sin revalorizar el capital', [("      perform private.materializar_capital_valoraciones_para(1, 'contrato', v.recargado);\n", "")]),
    ('recuperar: sin la válvula del re-enlace',
     [("    perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);\n    update crm.leads l set contrato_id = v.recargado where l.id = v.lead_id;",
       "    update crm.leads l set contrato_id = v.recargado where l.id = v.lead_id;")]),
    ('recuperar: sin el invariante 3d',
     [("    if v_acr2.id is distinct from v.acreditacion_id or v_acr2.fuente_tipo is distinct from 'contrato'",
       "    if false and (v_acr2.id is distinct from v.acreditacion_id or v_acr2.fuente_tipo is distinct from 'contrato'"),
      ("       or v_acr2.periodo_comercial is distinct from v.periodo then", "       or v_acr2.periodo_comercial is distinct from v.periodo) then")]),
    ('recuperar: la nota con otra acción',
     [("pg_catalog.jsonb_build_object('accion', 'recuperacion_venta', 'motivo', v_motivo,", "pg_catalog.jsonb_build_object('accion', 'otra_accion', 'motivo', v_motivo,")]),
    ('recuperar: sin la nota (el INSERT dentro de un «if false»): lo atrapa D8',
     [("    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)\n    values (",
       "    if false then insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)\n    values ("),
      ("      null);\n  end loop;\nend\n$recuperar$;", "      null); end if;\n  end loop;\nend\n$recuperar$;")]),
    # ── Postflight ──
    ('postflight: sin los metadatos', [off('POSTFLIGHT recuperar_ventas: cambiaron dueño, seguridad, volatilidad, configuración o permisos de una función')]),
    ('postflight: sin la tabla (RLS, dueño, políticas, API)', [off('POSTFLIGHT recuperar_ventas: la tabla nueva tiene RLS, es de postgres, sin políticas y sin privilegios para la API')]),
    ('postflight: sin las funciones de los triggers', [off('POSTFLIGHT recuperar_ventas: las funciones de los triggers nuevos son de postgres, INVOKER y sin EXECUTE para la API')]),
    ('postflight: sin «5 filas»', [off('POSTFLIGHT recuperar_ventas: se esperaban 5 ventas recuperadas')]),
    ('postflight: sin «exactamente un cierre»', [CUENTA_OFF]),
    ('postflight: sin «nada más cambió»',
     [("raise exception 'POSTFLIGHT recuperar_ventas: cambiaron % episodios de conversión que no son de las ventas recuperadas', v_distintos;", 'null;')]),
    ('postflight: sin la suma de referidos: lo atrapa I9',
     [off('POSTFLIGHT recuperar_ventas: la suma de referidos de un analista no subió exactamente una cuota por venta recuperada')]),
    ('postflight: compara el aporte individual de los referidos tocados (sin la máscara): la aplicación base aborta',
     [("                then null else e.aporte_numerador end as aporte", "                then e.aporte_numerador else e.aporte_numerador end as aporte"),
      ("                then null else s.aporte_numerador end as aporte", "                then s.aporte_numerador else s.aporte_numerador end as aporte")]),
    ('postflight: «un cierre» exige aporte también al referido: la aplicación base aborta (A queda en 0 por el tope)',
     [("not x.anulado and (x.aporte_numerador > 0 or x.fue_referido)\n                      and x.fecha_numerador >= c.periodo",
       "not x.anulado and x.aporte_numerador > 0\n                      and x.fecha_numerador >= c.periodo")]),
    ('postflight: sin F7', [off('POSTFLIGHT recuperar_ventas: una función cambiada nombra una pieza cerrada de F7')]),
    ('postflight: sin la vigencia del analista', [off('POSTFLIGHT recuperar_ventas: una función cambiada entró al censo de vigencia del analista')]),
    ('postflight: sin el censo analítico', [off('POSTFLIGHT recuperar_ventas: una función cambiada entró al censo analítico')]),
]


def main():
    texto = open(MIGRACION, encoding='utf-8').read()
    filtro = sys.argv[1] if len(sys.argv) > 1 else None  # python3 -I mutantes.py <texto>: solo los mutantes cuyo nombre lo contiene
    seleccion = [m for m in MUTANTES if not filtro or filtro in m[0]]
    vivos = 0
    for nombre, cambios in seleccion:
        mutado = texto
        ancla_mal = None
        recalcular = RECALCULAR in cambios
        for antes, despues in cambios:
            if (antes, despues) == RECALCULAR:
                continue
            if mutado.count(antes) != 1:
                ancla_mal = antes
                break
            mutado = mutado.replace(antes, despues)
        if ancla_mal is not None:
            print(f'  ENSAYO     {nombre}: el ancla no aparece exactamente una vez → {ancla_mal[:70]!r}')
            vivos += 1
            continue
        if recalcular:
            mutado = con_huellas_recalculadas(mutado)
        with tempfile.NamedTemporaryFile('w', suffix='.sql', delete=False, encoding='utf-8') as f:
            f.write(mutado)
            ruta = f.name
        try:
            r = subprocess.run(['bash', PROBAR], env={**os.environ, 'MUTANTE_MIGRACION': ruta}, capture_output=True, text=True)
        finally:
            os.unlink(ruta)
        salida = (r.stdout + r.stderr).strip().splitlines()
        causa = salida[-1] if salida else ''
        if r.returncode == 1:
            print(f'  MUERTO     {nombre}\n             ← {causa}')
        elif r.returncode == 0:
            print(f'  SOBREVIVE  {nombre}')
            vivos += 1
        else:
            print(f'  ENSAYO     {nombre} (probar.sh {r.returncode}) → {causa}')
            vivos += 1
    print(f'{len(seleccion) - vivos}/{len(seleccion)} mutantes muertos')
    sys.exit(1 if vivos else 0)


if __name__ == '__main__':
    main()
