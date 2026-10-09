#!/usr/bin/env python3
"""Genera únicamente las dos RPC desde vivo/; --verificar no escribe; --medicion emite SQL para banco."""
import argparse
import hashlib
from pathlib import Path
import re

CARPETA = Path(__file__).resolve().parent
MIGRACION = CARPETA.parents[1] / 'migrations/20261009223000_crm_jerarquia_evento_en_toda_via.sql'
HUELLAS = {
    'crm.actualizar_jerarquia_usuario_fn': '79c43d9888cf0d54b92eb26e8b46c3af',
    'crm.registrar_vendedor_usuario_fn': 'c3b73f85fdd791534d6edcc5015b14ff',
    'crm.fijar_membresia_activa_fn': '9be9925a221e64119b21e0f6a299ceb9',
    'private.registrar_evento_usuario': '8c423da784e0ff61e7eb91c896d851f2',
    'crm.facturacion_diaria_fn': '4b11e1da336f2f296c81f064ce30e35b',
}
RPC = tuple(HUELLAS)[:2]
INICIO = '  -- INICIO CUERPOS GENERADOS\n'
FIN = '  -- FIN CUERPOS GENERADOS\n'


def exigir(condicion, mensaje):
    if not condicion:
        raise ValueError(mensaje)


def sustituir(texto, anterior, nuevo):
    exigir(texto.count(anterior) == 1, f'Patrón debe aparecer una vez: {anterior!r}')
    return texto.replace(anterior, nuevo, 1)


def cuerpos():
    originales = {}
    for nombre, huella in HUELLAS.items():
        contenido = (CARPETA / 'vivo' / (nombre + '.sql')).read_bytes()
        exigir(hashlib.md5(contenido).hexdigest() == huella, f'Huella viva divergente: {nombre}')
        if nombre in RPC:
            originales[nombre] = contenido.decode('utf-8')
    nuevos = originales.copy()
    guc = """  -- El trigger consume esta idempotencia solo para este perfil, dentro de la transacción.
  perform pg_catalog.set_config('crm.evento_jerarquia_idempotencia', p_idempotencia::text, true);
  perform pg_catalog.set_config('crm.evento_jerarquia_objetivo', p_perfil_id::text, true);

"""
    nombre = RPC[0]
    nuevos[nombre] = sustituir(nuevos[nombre], '  update crm.equipo e\n', guc + '  update crm.equipo e\n')
    nuevos[nombre] = sustituir(nuevos[nombre], """  perform private.registrar_evento_usuario(
    'jerarquia_actualizada', p_perfil_id,
    pg_catalog.jsonb_build_object(
      'supervisor_anterior', v_supervisor_anterior,
      'supervisor_nuevo', p_supervisor_id
    ),
    p_idempotencia
  );

""", '')
    nombre = RPC[1]
    nuevos[nombre] = sustituir(nuevos[nombre], '  insert into crm.equipo (\n', guc + '  insert into crm.equipo (\n')
    nuevos[nombre] = sustituir(nuevos[nombre], """  perform private.registrar_evento_usuario(
    'jerarquia_actualizada', p_perfil_id,
    pg_catalog.jsonb_build_object(
      'supervisor_anterior', null, 'supervisor_nuevo', p_supervisor_id
    ),
    p_idempotencia
  );
""", '')
    for nombre in RPC:
        exigir(nuevos[nombre].split('AS $function$')[0] == originales[nombre].split('AS $function$')[0],
               f'Firma/atributos modificados: {nombre}')
        # Toda la autoridad, las búsquedas de repetición y los retornos tempranos quedan al byte.
        prefijo = originales[nombre].split('  update crm.equipo e\n' if nombre == RPC[0]
                                             else '  insert into crm.equipo (\n')[0]
        exigir(nuevos[nombre].startswith(prefijo), f'Precondiciones modificadas: {nombre}')
    return originales, nuevos


def bloque(definiciones):
    return ''.join('  execute $def$\n' + cuerpo + '$def$;\n\n' for cuerpo in definiciones.values())


def principal():
    argumentos = argparse.ArgumentParser(description=__doc__)
    modos = argumentos.add_mutually_exclusive_group()
    modos.add_argument('--verificar', action='store_true')
    modos.add_argument('--medicion', action='store_true')
    opciones = argumentos.parse_args()
    originales, nuevos = cuerpos()
    if opciones.medicion:
        texto = MIGRACION.read_text()
        definiciones = re.findall(r'  execute \$(nuevas|def)\$\n(.*?)\$\1\$;', texto, re.S)
        exigir(len(definiciones) == 4, 'Se esperan exactamente cuatro funciones para medir')
        exigir([cuerpo for etiqueta, cuerpo in definiciones if etiqueta == 'def'] == list(nuevos.values()),
               'Primero sincronizar/verificar los cuerpos')
        print("""-- SOLO medición en banco vacío. No aplica la migración ni salta su POSTFLIGHT.
begin;
do $guardia$
begin
  if current_user <> 'postgres' or exists (select 1 from public.contratos) then
    raise exception 'MEDICIÓN: requiere postgres y banco vacío, nunca producción';
  end if;
end $guardia$;""")
        for _, cuerpo in definiciones:
            print(cuerpo + ';')
        firmas = [re.search(r'FUNCTION ([^(]+)', cuerpo)[1] for _, cuerpo in definiciones]
        valores = ', '.join("('" + nombre + "')" for nombre in firmas)
        print("""select p.oid::regprocedure as firma, md5(pg_get_functiondef(p.oid)) as huella
from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
join (values """ + valores + """) f(nombre) on n.nspname || '.' || p.proname = f.nombre
order by p.oid::regprocedure::text;
rollback;""")
        return
    for ruta, definiciones in ((MIGRACION, nuevos), (CARPETA / 'reversa.sql', originales)):
        texto = ruta.read_text()
        exigir(texto.count(INICIO) == 1 and texto.count(FIN) == 1, f'Marcadores divergentes: {ruta}')
        antes, resto = texto.split(INICIO)
        contenido, despues = resto.split(FIN)
        esperado = bloque(definiciones)
        if opciones.verificar:
            exigir(contenido == esperado, f'Cuerpos divergentes: {ruta}')
        else:
            ruta.write_text(antes + INICIO + esperado + FIN + despues)
        print(f'PASS: {ruta.name}: dos cuerpos exactos; cinco huellas vivas verificadas')
    migracion = MIGRACION.read_text()
    reversa = (CARPETA / 'reversa.sql').read_text()
    for nombre in ('CATÁLOGO ESPERADO', 'VALIDACIÓN DE ESTADO'):
        inicio = '-- INICIO ' + nombre
        fin = '-- FIN ' + nombre
        # El texto entre marcadores incluye las huellas que Claude medirá: no fijarlas aquí.
        exigir(migracion.split(inicio)[1].split(fin)[0] == reversa.split(inicio)[1].split(fin)[0],
               f'Migración/reversa discrepan en {nombre}')
    print('PASS: catálogo y validación de estado idénticos en migración y reversa')


if __name__ == '__main__':
    principal()
