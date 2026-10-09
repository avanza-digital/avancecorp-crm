#!/usr/bin/env python3
"""Genera siete cuerpos y sincroniza ensayos; --verificar no escribe; --medicion emite SQL con ROLLBACK."""
import argparse
import hashlib
import json
from pathlib import Path
import re

CARPETA = Path(__file__).resolve().parent
RAIZ = CARPETA.parents[2]
HUELLAS = {
    'private.capital_episodios': 'c9e58c1da9dd7a5d52991c9e47dc19d5',
    'private.conversion_episodios': 'a0f6bab39ae1f046aa4b919ea9ce78ea',
    'private.metricas_cartera_por_vendedor': 'c1a0bab01e474af758f0feff8819414f',
    'crm.altas_nuevas_por_analista_fn': 'ac3136ea697cc25fc7263cb8b23ad8f8',
    'private.contratos_afectados_por_anulacion': 'efbe1fbb1ceb1a1bb8b5d5c03baf3897',
    'crm.atribucion_contrato_fn': '02ad7d7247859fcf9e2c1ece9e2bc22e',
    'crm.cierres_externos_fn': 'd44dec0ba4b92ecd1991a7ff204dc57e',
    'private.cartera_f5_fuentes': 'fa15f7765d0892c790c7a4b6822e756e',
    'private.analista_atribuido_cadena': '3c9cec305b014ad8c933df25057d3e8b',
}


def sustituir(texto, anterior, nuevo, cantidad=1):
    assert texto.count(anterior) == cantidad, (anterior, texto.count(anterior), cantidad)
    return texto.replace(anterior, nuevo)


def cuerpos():
    originales = {}
    for nombre, huella in HUELLAS.items():
        contenido = (CARPETA / 'vivo' / (nombre + '.sql')).read_bytes()
        assert hashlib.md5(contenido).hexdigest() == huella, nombre
        originales[nombre] = contenido.decode()
    originales.pop('private.analista_atribuido_cadena')
    # contratos_afectados_por_anulacion NO se reescribe (decisión de Claude PRIMARY, 09/10): decide qué contratos
    # produjo un cierre anulado y compara con la FOTO histórica del crédito (acreditado_a); con la regla de baja un
    # alta anulada de un inactivo dejaría de excluirse y se contaría al heredero. Su huella se verifica, nada más.
    originales.pop('private.contratos_afectados_por_anulacion')
    nuevos = originales.copy()
    patron = r'coalesce\(private\.analista_atribuido_cadena\(([^()]+)\),\s*([^()]+)\)'
    for nombre, cantidad in (
        ('private.capital_episodios', 6), ('private.conversion_episodios', 2),
        ('private.metricas_cartera_por_vendedor', 2), ('crm.altas_nuevas_por_analista_fn', 1),
    ):
        nuevos[nombre], encontrados = re.subn(patron, r'private.analista_efectivo_contrato(\1, \2)', nuevos[nombre])
        assert encontrados == cantidad, (nombre, encontrados)
    nombre = 'private.capital_episodios'
    nuevos[nombre] = sustituir(nuevos[nombre], 'ce.vendedor_id', 'private.analista_efectivo_cierre(ce.id)', 3)
    # capital_episodios: el analista efectivo se calcula UNA vez por fila (función en el FROM, lateral) y se reusa en
    # la columna, en en_roster y en el filtro del ámbito. Antes la expresión se evaluaba dos o tres veces por fila
    # (medido 09/10 en producción: setiembre 14,4 → 23,9 ms con la expresión repetida). Una función escalar en el
    # FROM devuelve exactamente UNA fila por entrada: no cambia la multiplicidad (el oráculo lo comprueba).
    nombre = 'private.capital_episodios'
    nuevos[nombre] = sustituir(nuevos[nombre],
        '  from public.contratos c\n  where not c.es_demo',
        '  from public.contratos c\n  cross join lateral private.analista_efectivo_contrato(c.id, c.analista_cierre_id) as ef(analista_id)\n  where not c.es_demo')
    nuevos[nombre] = sustituir(nuevos[nombre], 'private.analista_efectivo_contrato(c.id, c.analista_cierre_id),', 'ef.analista_id,')
    nuevos[nombre] = sustituir(nuevos[nombre], 'and mv.vendedor_id = private.analista_efectivo_contrato(c.id, c.analista_cierre_id)', 'and mv.vendedor_id = ef.analista_id')
    nuevos[nombre] = sustituir(nuevos[nombre], 'and (p_global or private.analista_efectivo_contrato(c.id, c.analista_cierre_id) = any(p_visibles))', 'and (p_global or ef.analista_id = any(p_visibles))')
    nuevos[nombre] = sustituir(nuevos[nombre],
        '  join public.contratos c on c.id = o.contrato_nuevo_id and not c.es_demo\n',
        '  join public.contratos c on c.id = o.contrato_nuevo_id and not c.es_demo\n  cross join lateral private.analista_efectivo_contrato(o.contrato_nuevo_id, o.vendedor_id) as ef(analista_id)\n')
    nuevos[nombre] = sustituir(nuevos[nombre], 'private.analista_efectivo_contrato(o.contrato_nuevo_id, o.vendedor_id),', 'ef.analista_id,')
    nuevos[nombre] = sustituir(nuevos[nombre], 'and mv.vendedor_id = private.analista_efectivo_contrato(o.contrato_nuevo_id, o.vendedor_id)', 'and mv.vendedor_id = ef.analista_id')
    nuevos[nombre] = sustituir(nuevos[nombre], 'and (p_global or private.analista_efectivo_contrato(o.contrato_nuevo_id, o.vendedor_id) = any(p_visibles))', 'and (p_global or ef.analista_id = any(p_visibles))')
    nuevos[nombre] = sustituir(nuevos[nombre],
        '  left join crm.leads l on l.id = ce.lead_id\n',
        '  left join crm.leads l on l.id = ce.lead_id\n  cross join lateral private.analista_efectivo_cierre(ce.id) as ef(analista_id)\n')
    nuevos[nombre] = sustituir(nuevos[nombre], '    private.analista_efectivo_cierre(ce.id),\n', '    ef.analista_id,\n')
    nuevos[nombre] = sustituir(nuevos[nombre], 'and mv.vendedor_id = private.analista_efectivo_cierre(ce.id)', 'and mv.vendedor_id = ef.analista_id')
    nuevos[nombre] = sustituir(nuevos[nombre], 'and (p_global or private.analista_efectivo_cierre(ce.id) = any(p_visibles))', 'and (p_global or ef.analista_id = any(p_visibles))')
    assert 'analista_efectivo_contrato' in nuevos[nombre] and nuevos[nombre].count('ef.analista_id') == 9
    nombre = 'crm.atribucion_contrato_fn'
    nuevos[nombre] = sustituir(nuevos[nombre],
        "-- 'adoptada' = ademas la atribucion difiere del analista que la proceso.",
        "-- 'adoptada' = la cadena difiere del analista que la proceso y sigue siendo la atribucion efectiva.")
    nuevos[nombre] = sustituir(nuevos[nombre],
        'and ef.analista_id is distinct from c.analista_cierre_id,',
        'and ef.analista_id <> c.analista_cierre_id\n'
        '                        and efectivo.analista_id = ef.analista_id,')
    nuevos[nombre] = sustituir(nuevos[nombre],
        "'analista_id',     coalesce(ef.analista_id, c.analista_cierre_id),\n            'analista_nombre', coalesce(pef.nombre_completo, pa.nombre_completo)",
        "'heredada', efectivo.analista_id is distinct from coalesce(ef.analista_id, c.analista_cierre_id),\n            'analista_id',     efectivo.analista_id,\n            'analista_nombre', pef.nombre_completo")
    nuevos[nombre] = sustituir(nuevos[nombre],
        '          left join public.perfiles pef on pef.id = ef.analista_id',
        '          cross join lateral (select private.analista_efectivo_contrato(c.id, c.analista_cierre_id) as analista_id) efectivo\n          left join public.perfiles pef on pef.id = efectivo.analista_id')
    nombre = 'crm.cierres_externos_fn'
    # Las dos listas y el desglose calculan el efectivo UNA vez por fila.
    nuevos[nombre] = sustituir(nuevos[nombre],
        '        select *\n        from crm.cierres_externos ce0\n',
        '        select ce0.*, ef.analista_id as vendedor_efectivo_id\n'
        '        from crm.cierres_externos ce0\n'
        '        cross join lateral private.analista_efectivo_cierre(ce0.id) as ef(analista_id)\n', 2)
    nuevos[nombre] = sustituir(nuevos[nombre],
        'ce0.vendedor_id = any(v_visibles)', 'ef.analista_id = any(v_visibles)', 2)
    nuevos[nombre] = sustituir(nuevos[nombre],
        "'vendedor_id', ce.vendedor_id,", "'vendedor_id', ce.vendedor_efectivo_id,", 2)
    nuevos[nombre] = sustituir(nuevos[nombre],
        '        select ce.vendedor_id, p.nombre_completo as nombre,',
        '        select ce.vendedor_efectivo_id as vendedor_id, p.nombre_completo as nombre,')
    nuevos[nombre] = sustituir(nuevos[nombre],
        '        from crm.cierres_externos ce\n        left join public.perfiles p on p.id = ce.vendedor_id',
        '        from (\n'
        '          select ce0.*, ef.analista_id as vendedor_efectivo_id\n'
        '          from crm.cierres_externos ce0\n'
        '          cross join lateral private.analista_efectivo_cierre(ce0.id) as ef(analista_id)\n'
        '        ) ce\n        left join public.perfiles p on p.id = ce.vendedor_id')
    nuevos[nombre] = sustituir(nuevos[nombre],
        'left join public.perfiles p on p.id = ce.vendedor_id',
        'left join public.perfiles p on p.id = ce.vendedor_efectivo_id', 3)
    nuevos[nombre] = sustituir(nuevos[nombre],
        'group by ce.vendedor_id, p.nombre_completo, ce.cooperativa, ce.moneda',
        'group by ce.vendedor_efectivo_id, p.nombre_completo, ce.cooperativa, ce.moneda')
    # El cuarto filtro pertenece a por_empresa; los otros tres son conteos/totales.
    antes_empresa, empresa = nuevos[nombre].split("    'por_empresa', coalesce((")
    antes_empresa = sustituir(antes_empresa, 'ce.vendedor_id = any(v_visibles)',
        'private.analista_efectivo_cierre(ce.id) = any(v_visibles)', 3)
    empresa = sustituir(empresa, 'ce.vendedor_id = any(v_visibles)',
        'ce.vendedor_efectivo_id = any(v_visibles)')
    nuevos[nombre] = antes_empresa + "    'por_empresa', coalesce((" + empresa
    # No cambia la lectura/restricción del teléfono vivo ni el contrato del payload.
    telefonos = r"'telefono', case.*?then l.telefono end,"
    assert re.findall(telefonos, nuevos[nombre], re.S) == re.findall(telefonos, originales[nombre], re.S)
    assert nuevos[nombre].count('limit 200') == 2
    nombre = 'private.cartera_f5_fuentes'
    # Camino rápido (medido 09/10: la versión por fila llevaba la cartera de 12,7 a 30,7 ms en producción): un mapa
    # de los dados de baja calculado UNA vez por llamada, como los otros dos mapas; solo esas filas buscan heredero.
    nuevos[nombre] = sustituir(nuevos[nombre],
        "  atrib_map as (select coalesce(jsonb_object_agg(raiz::text, analista_cierre_id::text), '{}'::jsonb) as m from atrib)\n",
        "  atrib_map as (select coalesce(jsonb_object_agg(raiz::text, analista_cierre_id::text), '{}'::jsonb) as m from atrib),\n"
        "  bajas_map as (select coalesce(jsonb_object_agg(e.perfil_id::text, true), '{}'::jsonb) as m\n"
        "    from crm.equipo e where private.analista_dado_de_baja(e.perfil_id))\n")
    atrib = 'coalesce((((select m from atrib_map)->>c.id::text)::uuid),c.analista_cierre_id)'
    nuevos[nombre] = sustituir(nuevos[nombre], atrib,
        'case when (select m from bajas_map) ? ' + atrib + '::text\n'
        '      then private.heredero_de_baja(' + atrib + ',\n'
        '        (select cliente.asesor_perfil_id from public.perfiles cliente where cliente.id = c.cliente_id))\n'
        '      else ' + atrib + ' end')
    nuevos[nombre] = sustituir(nuevos[nombre], 'ce.vendedor_id,ce.es_cierre_inicial',
        'case when (select m from bajas_map) ? ce.vendedor_id::text\n'
        '      then private.analista_efectivo_cierre(ce.id) else ce.vendedor_id end,ce.es_cierre_inicial')
    # La cabecera de pg_get_functiondef conserva firma, lenguaje y atributos.
    for nombre, nuevo in nuevos.items():
        assert nuevo.split('AS $function$')[0] == originales[nombre].split('AS $function$')[0]
    nombre = 'private.conversion_episodios'
    assert originales[nombre].split("select 'operacion'::text")[0] == nuevos[nombre].split("select 'operacion'::text")[0]
    return originales, nuevos


def bloque(definiciones):
    return ''.join('  execute $def$\n' + cuerpo + '$def$;\n\n' for cuerpo in definiciones.values())


def principal():
    argumentos = argparse.ArgumentParser(description=__doc__)
    modos = argumentos.add_mutually_exclusive_group()
    modos.add_argument('--verificar', action='store_true')
    modos.add_argument('--medicion', action='store_true')
    opciones = argumentos.parse_args()
    verificar = opciones.verificar
    originales, nuevos = cuerpos()
    exencion = json.loads((CARPETA / 'vivo/exencion-cierres-externos.json').read_text())
    assert hashlib.md5(exencion['razon'].encode()).hexdigest() == exencion['md5_razon']
    if opciones.medicion:
        migracion = (RAIZ / 'supabase/migrations/20261009200000_crm_baja_analista_heredero.sql').read_text()
        definiciones = re.findall(r'  execute \$(nuevas|def)\$\n(.*?)\$\1\$;', migracion, re.S)
        assert len(definiciones) == 11
        assert [cuerpo for etiqueta, cuerpo in definiciones if etiqueta == 'def'] == list(nuevos.values())
        print("""-- Generado para medir en el banco; nunca producción. No omite el POSTFLIGHT de la migración.
begin;
do $guardia$
begin
  if (current_user = 'postgres' and current_setting('app.settings.jwt_secret', true)
      = 'super-secret-jwt-token-with-at-least-32-characters-long') is not true then
    raise exception 'MEDICIÓN: solo postgres en banco LOCAL de Docker';
  end if;
end $guardia$;""")
        for _, cuerpo in definiciones:
            print(cuerpo + ';')
        print("""revoke execute on function private.analista_dado_de_baja(uuid), private.heredero_de_baja(uuid,uuid),
  private.analista_efectivo_contrato(uuid,uuid), private.analista_efectivo_cierre(uuid)
  from public, anon, authenticated, service_role;""")
        nombres = list(nuevos) + ['private.analista_dado_de_baja', 'private.heredero_de_baja', 'private.analista_efectivo_contrato', 'private.analista_efectivo_cierre']
        valores = ',\n'.join("('" + nombre + "')" for nombre in nombres)
        print("""select p.oid::regprocedure as firma, md5(pg_get_functiondef(p.oid)) as huella,
  pg_get_userbyid(p.proowner) as dueno, p.proacl, p.prosecdef, p.provolatile, p.proconfig
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
join (values """ + valores + """) esperadas(nombre) on n.nspname || '.' || p.proname = esperadas.nombre
order by p.oid::regprocedure::text;
rollback;""")
        return
    for ruta, definiciones in (
        (RAIZ / 'supabase/migrations/20261009200000_crm_baja_analista_heredero.sql', nuevos),
        (CARPETA / 'reversa.sql', originales),
    ):
        texto = ruta.read_text()
        assert '$razon_viva$' + exencion['razon'] + '$razon_viva$' in texto, f'Razón viva divergente: {ruta}'
        assert exencion['huella'] in texto and exencion['md5_razon'] in texto
        inicio = '  -- INICIO CUERPOS GENERADOS\n'
        fin = '  -- FIN CUERPOS GENERADOS\n'
        antes, resto = texto.split(inicio)
        contenido, despues = resto.split(fin)
        esperado = bloque(definiciones)
        if verificar:
            assert contenido == esperado, f'Cuerpos divergentes: {ruta}'
        else:
            ruta.write_text(antes + inicio + esperado + fin + despues)
        print(f'PASS: {ruta.name}: siete cuerpos, firmas y huellas de origen verificadas')
    # Conservar las cabeceras y bloques propios de los ensayos. La medición intercala
    # su bloque «antes» justo delante del DO; al retirarlo queda la migración al byte.
    migracion = (RAIZ / 'supabase/migrations/20261009200000_crm_baja_analista_heredero.sql').read_text()
    assert migracion.endswith('commit;\n')
    sin_commit = migracion.removesuffix('commit;\n')
    for archivo, marcador_final in (
        ('ensayo-produccion.sql', 'do $ensayo$'),
        ('medir-produccion.sql', "select pg_temp.baja_medir('despues');"),
    ):
        ruta = CARPETA / archivo
        texto = ruta.read_text()
        cabecera = texto[:texto.index('-- Baja de analista:')]
        final = texto[texto.index(marcador_final):]
        contenido = sin_commit
        if archivo == 'medir-produccion.sql':
            antes = texto[texto.index('create or replace function pg_temp.baja_medir'):texto.index('do $mig$')]
            contenido = sustituir(contenido, 'do $mig$', antes + 'do $mig$')
        esperado = cabecera + contenido + final
        if verificar:
            assert texto == esperado, f'Migración divergente: {ruta}'
        else:
            ruta.write_text(esperado)
        print(f'PASS: {archivo}: migración al byte y bloques propios conservados')
    print('PASS: cadena, piernas de leads, anulación y teléfono intactos; atribución efectiva en cooperativas')


if __name__ == '__main__':
    principal()
