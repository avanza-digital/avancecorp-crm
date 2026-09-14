"""Genera SQL privado revisable. No tiene conexión de base de datos ni ejecuta SQL."""
import argparse
from hashlib import sha256
import json
import os
from pathlib import Path
import re
from uuid import UUID, uuid4


CAMPOS_FUENTE = ('fuente_id', 'empresa', 'perfil_id', 'lead_id', 'numero', 'capital',
                 'moneda', 'estado', 'fecha_comercial', 'fecha_imputacion', 'vence_en',
                 'analista_origen_id', 'es_demo')
CAMPOS_PERFIL = ('id', 'rol', 'tipo_documento', 'dni', 'activo', 'asesor_perfil_id')
CAMPOS_LEAD = ('id', 'dni', 'perfil_id', 'activo', 'etapa', 'no_contactar', 'vendedor_id')


def exigir(condicion, mensaje):
    if not condicion:
        raise ValueError(mensaje)


def preparar_lote(revision, procedencia, confirmacion, evidencia_sha256, lote_id=None):
    """Acepta únicamente la forma del lote revisado: 9 Avance + 1 Qorilazo."""
    exigir(revision['transaccion_solo_lectura'] == 'on', 'La fotografía debe ser de solo lectura')
    reales = [c for c in revision['casos'] if not c['es_demo']]
    exigir(len(reales) == 10 and len({c['fuente_id'] for c in reales}) == 10,
           'Se necesitan diez fuentes reales distintas')
    exigir(sum(c['empresa'] == 'avance' for c in reales) == 9
           and sum(c['empresa'] == 'qorilazo' for c in reales) == 1,
           'El lote no coincide con nueve contratos Avance y un cierre Qorilazo')
    exigir(confirmacion['respuesta_literal'] == 'sii son la misma',
           'Falta la correspondencia multirrol confirmada')
    exigir(re.fullmatch(r'[0-9a-f]{64}', evidencia_sha256), 'Huella de evidencia inválida')
    personas = []
    procesadas = set()
    fuentes = sorted(({k: c[k] for k in CAMPOS_FUENTE} for c in reales), key=lambda c: c['fuente_id'])
    for c in reales:
        origen = c['perfil_id'] if c['empresa'] == 'avance' else c['fuente_id']
        if origen in procesadas:
            continue
        procesadas.add(origen)
        exigir(c['tipo_documento'] == 'DNI' and re.fullmatch(r'[0-9]{8}', c['doc_norm']),
               'El lote revisado requiere DNI de ocho dígitos')
        exigir(not c['inversionista_id'] and not c['inversion_id']
               and not c['identificadores_mismo_documento'], 'Existe una identidad previa no revisada')
        multirrol = c['perfil_id'] == confirmacion['perfil_cliente']
        perfiles = sorted(({k: p[k] for k in CAMPOS_PERFIL} for p in c['perfiles_mismo_documento']),
                          key=lambda p: p['id'])
        if c['empresa'] == 'avance':
            exigir(len(perfiles) == (2 if multirrol else 1), 'Colisión de perfiles no revisada')
            exigir(c['perfil']['rol'] == 'cliente' and c['perfil']['activo'], 'El origen debe ser cliente activo')
            exigir(not c['leads_relacionados'] and not c['cierres_mismo_documento'],
                   'El perfil tiene otra fuente relacionada que debe revisarse')
            if multirrol:
                exigir({p['id'] for p in perfiles} == {confirmacion['perfil_cliente'], confirmacion['perfil_analista']},
                       'Las cuentas no coinciden con la confirmación')
                exigir(next(p for p in perfiles if p['id'] == confirmacion['perfil_analista'])['rol'] == 'analista',
                       'La segunda cuenta no conserva el rol de analista')
            responsable = c['perfil']['asesor_perfil_id']
            lead = None
        else:
            exigir(not perfiles and len(c['leads_relacionados']) == 1, 'Cierre con otra identidad candidata')
            lead_original = c['leads_relacionados'][0]
            exigir(lead_original['id'] == c['lead_id'] and not lead_original['dni']
                   and not lead_original['perfil_id'] and not lead_original['inversionista_id']
                   and not lead_original['puentes'] and not lead_original['no_contactar']
                   and lead_original['activo'] and lead_original['etapa'] == 'convertido',
                   'El lead no coincide con el convertido sin DNI revisado')
            lead = {k: lead_original[k] for k in CAMPOS_LEAD}
            responsable = c['cierre']['vendedor_id']
        prueba = next(p for p in procedencia['personas'] if p['id'] == origen)
        exigir(prueba['responsable_activo'] and prueba['responsable_id'] == responsable,
               'Responsable original no vigente o distinto')
        exigir(not prueba['titulares_mismo_documento'], 'Coincidencia documental en titulares no revisada')
        auditorias = prueba['auditoria_documento']
        exigir(len(auditorias) == 1 and auditorias[0]['operacion'] == 'INSERT'
               and auditorias[0]['documento_coincide'], 'La captura documental original debe revisarse')
        exigir(prueba['creador_rol'] == 'analista', 'La procedencia registrada no coincide con el censo')
        mapa = c['revision_f2']
        if mapa:
            exigir(multirrol and mapa['clase'] == 'E' and not mapa['inversionista_id'],
                   'Revisión F2 distinta de la confirmada')
            mapa = {k: v for k, v in mapa.items() if k not in ('id', 'creado_en', 'actualizado_en')}
        ids_fuentes = sorted(x['fuente_id'] for x in reales
                             if (x['perfil_id'] if x['empresa'] == 'avance' else x['fuente_id']) == origen)
        personas.append(dict(
            origen=origen, fuente='perfil' if c['empresa'] == 'avance' else 'cierre',
            perfil_id=c['perfil_id'], lead_id=c['lead_id'], tipo_documento='DNI', documento=c['doc_norm'],
            responsable_id=responsable, multirrol=multirrol, mapa_previo=mapa, lead=lead,
            perfiles_coincidentes=perfiles,
            cierres_coincidentes=sorted(x['id'] for x in c['cierres_mismo_documento']),
            leads_coincidentes=sorted(x['id'] for x in c['leads_relacionados']),
            fuentes_ids=ids_fuentes,
            procedencia=dict(auditoria_id=auditorias[0]['id'], creador_registrado=prueba['creador_registrado'],
                             canal='cierre_auditado' if c['empresa'] != 'avance' else 'perfil_auditado_sin_actor_jwt'),
        ))
    exigir(len(personas) == 7 and sum(p['multirrol'] for p in personas) == 1, 'Deben ser siete personas y un caso multirrol')
    exigir(len({p['documento'] for p in personas}) == 7, 'El lote contiene documentos repetidos entre personas')
    lote_id = str(UUID(lote_id)) if lote_id else str(uuid4())
    return dict(version=1, lote_id=lote_id, operacion='aplicar', evidencia_sha256=evidencia_sha256,
                conformidad_multirrol='misma_persona_confirmada', personas=personas, fuentes=fuentes)


def renderizar(lote, operacion='aplicar', confirmar=False):
    exigir(operacion in ('aplicar', 'revertir'), 'Operación desconocida')
    datos = dict(lote, operacion=operacion)
    literal = "'" + json.dumps(datos, ensure_ascii=False, separators=(',', ':')).replace("'", "''") + "'"
    plantilla = Path(__file__).with_name('completar.sql.in').read_text()
    exigir(plantilla.count('__LOTE_JSON__') == 1 and plantilla.count('__FIN_TRANSACCION__') == 1,
           'Plantilla inválida')
    return plantilla.replace('__FIN_TRANSACCION__', 'commit' if confirmar else 'rollback').replace('__LOTE_JSON__', literal)


def escribir_privado(ruta, texto):
    descriptor = os.open(ruta, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(descriptor, 'w', encoding='utf-8') as f:
        f.write(texto)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('revision', type=Path)
    parser.add_argument('procedencia', type=Path)
    parser.add_argument('confirmacion', type=Path)
    parser.add_argument('destino', type=Path)
    args = parser.parse_args()
    contenido = [p.read_bytes() for p in (args.revision, args.procedencia, args.confirmacion)]
    huella = sha256(b'\n'.join(contenido)).hexdigest()
    lote = preparar_lote(*(json.loads(c) for c in contenido), huella)
    args.destino.mkdir(mode=0o700, parents=True, exist_ok=False)
    escribir_privado(args.destino / 'lote-privado.json', json.dumps(lote, indent=2, ensure_ascii=False) + '\n')
    archivos = {'lote-privado.json': sha256((args.destino / 'lote-privado.json').read_bytes()).hexdigest()}
    for nombre, operacion, confirmar in (
        ('ensayo-transaccional.sql', 'aplicar', False),
        ('aplicar-propuesta.sql', 'aplicar', True),
        ('reversa-propuesta.sql', 'revertir', True),
    ):
        texto = renderizar(lote, operacion, confirmar)
        escribir_privado(args.destino / nombre, texto)
        archivos[nombre] = sha256(texto.encode()).hexdigest()
    escribir_privado(args.destino / 'integridad.json', json.dumps(archivos, indent=2) + '\n')
    print('Propuesta privada generada: siete identidades, diez fuentes. No se ejecutó SQL.')


if __name__ == '__main__':
    main()
