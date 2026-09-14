"""Banco SQL sintético cerrado. Nunca acepta URL ni descarga producción."""
import copy
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import subprocess
import time
from uuid import uuid4

from generar import preparar_lote, renderizar

CONTENEDOR = 'supabase_db_avancecorp-f5-bank'
FUENTE = 'multiempresa_f7_20260911'
DESTINO = 'multiempresa_f8_identidades_20260913'
MARCA = 'Banco desechable de identidades F8; solo datos sinteticos'
RAIZ = Path(__file__).resolve().parent


def comando(args, entrada=None, debe_pasar=True):
    p = subprocess.run(['docker', *args], input=entrada, text=True, capture_output=True)
    if debe_pasar and p.returncode:
        raise AssertionError(p.stderr)
    return p


def sql(texto, base=DESTINO, debe_pasar=True):
    return comando(['exec', '-i', CONTENEDOR, 'psql', '-X', '-qAt', '-U', 'postgres',
                    '-d', base, '-v', 'ON_ERROR_STOP=1', '-f', '-'], texto, debe_pasar)


def dato(texto, base=DESTINO):
    return json.loads(sql(texto, base).stdout.strip().splitlines()[-1])


def literal(v):
    if v is None:
        return 'null'
    return "'" + str(v).replace("'", "''") + "'"


def preparar_banco():
    assert sql('select current_database()', FUENTE).stdout.strip() == FUENTE
    existe = sql(f"select coalesce(shobj_description(oid,'pg_database'),'SIN_MARCA') from pg_database where datname={literal(DESTINO)}", 'postgres').stdout.strip()
    if existe:
        assert existe == MARCA, 'Se rehúsa reemplazar una base ajena'
        conexiones = sql(f"select count(*) from pg_stat_activity where datname={literal(DESTINO)}", 'postgres').stdout.strip()
        assert conexiones == '0', 'El banco propio sigue en uso'
        comando(['exec', CONTENEDOR, 'dropdb', '-U', 'postgres', DESTINO])
    dump = '/tmp/f8_identidades_base.dump'
    lista = '/tmp/f8_identidades_restore.list'
    comando(['exec', CONTENEDOR, 'pg_dump', '-Fc', '-U', 'postgres', '-d', FUENTE, '-f', dump])
    toc = comando(['exec', CONTENEDOR, 'pg_restore', '-l', dump]).stdout
    toc = '\n'.join(l for l in toc.splitlines() if ' DEFAULT ACL ' not in l)
    comando(['exec', '-i', CONTENEDOR, 'tee', lista], toc + '\n')
    comando(['exec', CONTENEDOR, 'createdb', '-U', 'postgres', '-T', 'template0', DESTINO])
    sql(f'comment on database {DESTINO} is {literal(MARCA)}', 'postgres')
    comando(['exec', CONTENEDOR, 'pg_restore', '-U', 'postgres', '-d', DESTINO,
             '--no-owner', '-L', lista, dump])
    sql("update crm.multiempresa_flags set activo=false where nombre in ('inversiones_escritura','ficha_360_neutral','postventa_neutral','metricas_multiempresa_sombra')")


def crear_fixture():
    fuentes_base = int(sql('select count(*) from private.cartera_f5_fuentes()').stdout.strip())
    actor = sql("select e.perfil_id from crm.equipo e join public.perfiles p on p.id=e.perfil_id where e.activo and p.activo and e.rol_crm='vendedor' and p.rol='analista' order by e.perfil_id limit 1").stdout.strip()
    assert actor
    perfiles = [str(uuid4()) for _ in range(8)]
    analista = str(uuid4())
    leads = [str(uuid4()), str(uuid4())]
    cierres = [str(uuid4()), 'a112aead-184a-4979-9041-943978fadae4']
    # Las fuentes reales revisadas nacieron antes del encendido F3 (07/09).
    # Solo el fixture reproduce ese estado histórico; el completado exige F3 ON.
    partes = ["begin; set local crm.op_privilegiada='on'; set local crm.marcando_demo='on'; update crm.multiempresa_flags set activo=false where nombre='resolver_en_puertas';"]
    for perfil in perfiles + [analista]:
        partes.append(f"insert into auth.users(id,aud,role,email) values({literal(perfil)},'authenticated','authenticated',{literal('f8-'+perfil+'@fixtures.invalid')});")
    for n, perfil in enumerate(perfiles):
        doc = f'9910100{n+1}' if n < 6 else (None if n == 6 else '1234')
        cambios = dict(id=perfil, nombre_completo=f'CLIENTE SINTETICO F8 {n}', dni=doc,
                       tipo_documento='DNI', correo=f'f8-{perfil}@fixtures.invalid',
                       telefono=f'99800100{n}', activo=True, creado_por=actor, asesor_perfil_id=actor)
        partes.append(f"insert into public.perfiles select (jsonb_populate_record(null::public.perfiles,to_jsonb(p)||{literal(json.dumps(cambios))}::jsonb)).* from public.perfiles p where p.rol='cliente' order by p.id limit 1;")
    cambios = dict(id=analista, nombre_completo='ANALISTA MULTIRROL SINTETICO F8', dni='99101001',
                   correo=f'f8-{analista}@fixtures.invalid', telefono='998001099', activo=True)
    partes.append(f"insert into public.perfiles select (jsonb_populate_record(null::public.perfiles,to_jsonb(p)||{literal(json.dumps(cambios))}::jsonb)).* from public.perfiles p where p.id={literal(actor)};")
    partes.append(f"insert into crm.equipo select (jsonb_populate_record(null::crm.equipo,to_jsonb(e)||jsonb_build_object('perfil_id',{literal(analista)}))).* from crm.equipo e where e.perfil_id={literal(actor)};")
    contratos = []
    for n, cantidad in enumerate((2, 1, 1, 1, 3, 1, 1, 2)):
        for k in range(cantidad):
            contrato = str(uuid4()); contratos.append(contrato)
            cambios = dict(id=contrato, cliente_id=perfiles[n], numero_contrato=f'F8-ID-{n}-{k}',
                           es_demo=n >= 6, categoria='nuevo', producto_condicion_id=None,
                           creado_por=actor, analista_cierre_id=actor, renovado_a_id=None,
                           fecha_cierre_comercial=None, fuente_cierre_comercial='registro')
            partes.append(f"insert into public.contratos select (jsonb_populate_record(null::public.contratos,to_jsonb(c)||{literal(json.dumps(cambios))}::jsonb)).* from public.contratos c where c.categoria='nuevo' order by c.id limit 1;")
    for n in range(2):
        cambios = dict(id=leads[n], nombre_completo=f'CIERRE SINTETICO F8 {n}', dni=None if n == 0 else '99101999',
                       telefono=f'99800200{n}', correo=f'f8-{leads[n]}@fixtures.invalid', activo=True,
                       perfil_id=None, contrato_id=None, inversionista_id=None, etapa='convertido',
                       no_contactar=False, vendedor_id=actor, creado_por=actor)
        partes.append(f"insert into crm.leads select (jsonb_populate_record(null::crm.leads,to_jsonb(l)||{literal(json.dumps(cambios))}::jsonb)).* from crm.leads l where l.etapa='convertido' order by l.id limit 1;")
        cambios = dict(id=cierres[n], lead_id=leads[n], cooperativa='qorilazo', monto=5000,
                       documento_tipo='DNI', documento='99101007' if n == 0 else '99101999',
                       nombre_completo=f'CIERRE SINTETICO F8 {n}', numero_transaccion=f'F8-ID-TRANS-{n}',
                       referencia_externa=f'F8-ID-EXT-{n}', inversionista_id=None, vendedor_id=actor,
                       creado_por=actor, anulado_en=None, anulado_por=None, motivo_anulacion=None,
                       es_cierre_inicial=True, fecha_comercial=None, fecha_imputacion=None,
                       comprobante_objeto_id=None)
        partes.append(f"insert into crm.cierres_externos select (jsonb_populate_record(null::crm.cierres_externos,to_jsonb(c)||{literal(json.dumps(cambios))}::jsonb)).* from crm.cierres_externos c order by c.id limit 1;")
    partes.append(f"select private.f2_mapear('perfil',{literal(perfiles[0])},null,'E','documento compartido con otro perfil (multirrol/colision)','revision');")
    # Reconstruye únicamente la evidencia histórica sintética: el INSERT real
    # revisado precede al enmascaramiento actual de documentos en audit_log.
    # El completado exige ese documento original; no acepta '***' como prueba.
    partes.append(f"update public.audit_log a set data_despues=jsonb_set(a.data_despues,'{{documento}}',to_jsonb(c.documento)) from crm.cierres_externos c where a.fila_id=c.id::text and c.id={literal(cierres[0])} and a.tabla='crm.cierres_externos' and a.operacion='INSERT';")
    # Volumen de lectura comparable con las 598 fuentes del censo productivo;
    # usa personas sintéticas ya enlazadas y no agrega huecos al lote revisado.
    relleno = max(0, 598 - fuentes_base - 14)
    partes.append(f"insert into public.contratos select (jsonb_populate_record(null::public.contratos,to_jsonb(c)||jsonb_build_object('id',gen_random_uuid(),'numero_contrato','F8-VOLUMEN-'||g.n,'es_demo',false,'categoria','nuevo','producto_condicion_id',null,'renovado_a_id',null,'fecha_cierre_comercial',null,'fuente_cierre_comercial','registro'))).* from (select c.* from public.contratos c join crm.inversionistas i on i.perfil_id=c.cliente_id where c.categoria='nuevo' order by c.id limit 1) c cross join generate_series(1,{relleno}) g(n);")
    partes.append("update crm.multiempresa_flags set activo=true where nombre='resolver_en_puertas'; commit;")
    sql('\n'.join(partes))
    revision = dato((RAIZ.parent / 'revision-identidades.sql').read_text())
    assert revision['pendientes_reales'] == 10 and revision['pendientes_demo'] == 4
    procedencia = dict(personas=[])
    vistos = set()
    for c in revision['casos']:
        if c['es_demo']:
            continue
        origen = c['perfil_id'] or c['fuente_id']
        if origen in vistos:
            continue
        vistos.add(origen)
        tabla = 'perfiles' if c['perfil_id'] else 'crm.cierres_externos'
        auditoria = sql(f"select id from public.audit_log where fila_id={literal(origen)} and tabla in ({literal(tabla)},'public.perfiles') and operacion='INSERT' order by ts desc limit 1").stdout.strip()
        assert auditoria
        procedencia['personas'].append(dict(id=origen, responsable_id=actor, responsable_activo=True,
            creador_registrado=actor, creador_rol='analista', titulares_mismo_documento=[],
            auditoria_documento=[dict(id=auditoria, operacion='INSERT', documento_coincide=True)]))
    confirmacion = dict(respuesta_literal='sii son la misma', perfil_cliente=perfiles[0], perfil_analista=analista)
    lote = preparar_lote(revision, procedencia, confirmacion, 'a' * 64)
    return lote, dict(actor=actor, analista=analista, perfiles=perfiles, leads=leads, cierres=cierres)


def conteo():
    return dato("select jsonb_build_object('personas',(select count(*) from crm.inversionistas),'identificadores',(select count(*) from crm.inversionista_identificadores),'reales',(select count(*) from private.cartera_f5_fuentes() where not es_demo and not coalesce(identidad_coherente,false)),'demo',(select count(*) from private.cartera_f5_fuentes() where es_demo and not coalesce(identidad_coherente,false)))")


def huella_fuentes(base=DESTINO):
    return dato("select jsonb_build_object('perfiles',(select md5(jsonb_agg(p order by id)::text) from public.perfiles p),'contratos',(select md5(jsonb_agg(c order by id)::text) from public.contratos c),'cierres',(select md5(jsonb_agg(to_jsonb(c)-'inversionista_id' order by id)::text) from crm.cierres_externos c),'inversiones',(select md5(jsonb_agg(i order by id)::text) from crm.inversiones i),'capital',(select md5(jsonb_agg(to_jsonb(e) order by to_jsonb(e)::text)::text) from private.capital_episodios('-infinity','infinity',true,'{}') e),'auth',(select md5(coalesce(jsonb_agg(u order by id)::text,'')) from auth.users u))", base)


def rechazar(lote, patron):
    resultado = sql(renderizar(lote, confirmar=True), debe_pasar=False)
    assert resultado.returncode != 0 and patron in resultado.stderr, resultado.stderr


def intercambiar_multirrol(lote):
    verdadera = next(p for p in lote['personas'] if p['multirrol'])
    otra = next(p for p in lote['personas'] if not p['multirrol'])
    verdadera['multirrol'] = False
    otra['multirrol'] = True


def ensayar_despues_reversa(lote, ids):
    multirrol = next(p for p in lote['personas'] if p['multirrol'])
    mapa = dato(f"select to_jsonb(m)-'id'-'creado_en'-'actualizado_en' from crm.backfill_multiempresa_mapa m where fuente='perfil' and fila_id={literal(multirrol['origen'])};")
    assert mapa == multirrol['mapa_previo']
    print('PASS: reversa restaura exactamente la revisión F2 multirrol', flush=True)
    documento = next(p['documento'] for p in lote['personas'] if p['fuente'] == 'cierre')
    consulta = f"begin; select private.inversionista_resolver('DNI',{literal(documento)},true,'post-reversa-sintetica'); rollback;"
    assert sql(consulta).stdout.strip()
    print('PASS: índice parcial permite resolver el DNI después de la reversa (ensayo revertido)', flush=True)
    normal = f"begin; update crm.leads set inversionista_id=private.inversionista_resolver('DNI',{literal(documento)},true,'post-reversa-sintetica') where id={literal(ids['leads'][0])}; select to_jsonb(inversionista_id is null) from crm.leads where id={literal(ids['leads'][0])}; rollback;"
    assert dato(normal) is True  # El BEFORE normal conserva el enlace anterior.
    # La escritura ordinaria no permite reapuntar; incluso una futura
    # reparación administrativa debe reconciliar explícitamente el puente viejo.
    cambio = f"begin; set local crm.op_privilegiada='on'; update crm.leads set inversionista_id=private.inversionista_resolver('DNI',{literal(documento)},true,'post-reversa-sintetica') where id={literal(ids['leads'][0])}; select jsonb_build_object('mismo',il.inversionista_id=l.inversionista_id,'rol',il.rol) from crm.leads l join crm.inversionista_leads il on il.lead_id=l.id where l.id={literal(ids['leads'][0])}; rollback;"
    assert dato(cambio) == dict(mismo=False, rol='historico')
    print('PASS: tras reversa el puente histórico exige reconciliación explícita para reenlazar', flush=True)


def rechazar_con_cambio(lote, cambio, patron, operacion='aplicar'):
    # El fallo aborta también el cambio simulado: ninguna prueba deja el banco
    # con documentos, roles o hechos modificados fuera de su transacción.
    cuerpo = renderizar(lote, operacion, True).replace('begin isolation level read committed;', '', 1)
    resultado = sql('begin isolation level read committed;\n' + cambio + '\n' + cuerpo, debe_pasar=False)
    assert resultado.returncode != 0 and patron in resultado.stderr, resultado.stderr


def contratos_visibles(actor):
    return dato(f"begin; set local role authenticated; set local request.jwt.claim.sub={literal(actor)}; select coalesce(jsonb_agg(id order by id),'[]') from public.contratos; rollback;")


def personas_del_lote_visibles(actor, lote):
    # Invoca el núcleo de autorización con claim SINTÉTICO; no es una prueba HTTP.
    etiqueta = 'f8-identidades:' + lote['lote_id']
    return dato(f"begin; set local request.jwt.claim.sub={literal(actor)}; select count(*) from private.cartera_f5_personas_visibles() p join crm.inversionista_identificadores d on d.inversionista_id=p.inversionista_id where d.fuente={literal(etiqueta)}; rollback;")


def probar_carrera():
    preparar_banco()
    lote, _ = crear_fixture()
    antes = conteo(); huella = huella_fuentes()
    escritor = subprocess.Popen(['docker', 'exec', '-i', CONTENEDOR, 'psql', '-X', '-qAt',
        '-U', 'postgres', '-d', DESTINO, '-v', 'ON_ERROR_STOP=1'],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        escritor.stdin.write("begin; set local idle_in_transaction_session_timeout='15s'; "
            "select private.inversionista_resolver('PASAPORTE',"
            + literal(lote['personas'][0]['documento']) + ",true,'carrera-sintetica');\n"
            "select 'ESCRITOR_LISTO';\n")
        escritor.stdin.flush()
        assert escritor.stdout.readline().strip()  # identidad aún sin COMMIT
        assert escritor.stdout.readline().strip() == 'ESCRITOR_LISTO'
        with ThreadPoolExecutor(max_workers=1) as pool:
            aplicador = pool.submit(sql, "set application_name='f8-prueba-carrera';\n"
                + renderizar(lote, confirmar=True), DESTINO, False)
            limite = time.monotonic() + 2
            esperando = False
            while time.monotonic() < limite:
                esperando = dato("select to_jsonb(exists(select 1 from pg_stat_activity where datname=current_database() and application_name='f8-prueba-carrera' and wait_event_type='Lock'))")
                if esperando:
                    break
                time.sleep(0.05)
            escritor.communicate('commit;\n\\q\n', timeout=5)
            resultado = aplicador.result(timeout=10)
            assert esperando, 'La prueba no observó la espera real entre sesiones'
            assert resultado.returncode != 0 and 'ya existente o lote ya aplicado' in resultado.stderr, resultado.stderr
        assert conteo() == dict(antes, personas=antes['personas'] + 1, identificadores=antes['identificadores'] + 1)
        assert huella_fuentes() == huella
        print('PASS: dos sesiones; colisión PASAPORTE concurrente aborta el lote DNI entero', flush=True)
    finally:
        if escritor.poll() is None:
            escritor.communicate('rollback;\n\\q\n', timeout=5)


def main():
    huella_original = huella_fuentes(FUENTE)
    preparar_banco()
    lote, ids = crear_fixture()
    antes = conteo(); huella = huella_fuentes()
    permisos = contratos_visibles(ids['analista'])
    for descripcion, modificar, patron in (
        ('rechaza una preimagen financiera caducada', lambda l: l['fuentes'][0].update(capital=999999), 'fuente económica'),
        ('rechaza otra cuenta con el documento', lambda l: l['personas'][0].update(perfiles_coincidentes=[]), 'conjunto de perfiles'),
        ('exige confirmación multirrol', lambda l: l.update(conformidad_multirrol='pendiente'), 'conformidad multirrol'),
        ('exige la auditoría original del documento', lambda l: l['personas'][0]['procedencia'].update(auditoria_id=str(uuid4())), 'captura documental'),
        ('rechaza conformidad ausente', lambda l: l.pop('conformidad_multirrol'), 'claves o tipos obligatorios del lote'),
        ('rechaza versión ausente', lambda l: l.pop('version'), 'claves o tipos obligatorios del lote'),
        ('rechaza versión nula', lambda l: l.update(version=None), 'lote o aislamiento inválido'),
        ('rechaza conformidad nula', lambda l: l.update(conformidad_multirrol=None), 'conformidad multirrol'),
        ('rechaza multirrol ausente', lambda l: l['personas'][0].pop('multirrol'), 'claves o tipos obligatorios de persona'),
        ('rechaza multirrol nulo', lambda l: l['personas'][0].update(multirrol=None), 'claves o tipos obligatorios de persona'),
        ('rechaza documento duplicado en el lote', lambda l: l['personas'][0].update(documento=l['personas'][1]['documento']), 'deben ser distintos'),
        ('rechaza origen duplicado en el lote', lambda l: l['personas'][0].update(origen=l['personas'][1]['origen']), 'deben ser distintos'),
        ('exige partición exacta de fuentes', lambda l: l['personas'][0]['fuentes_ids'].append(l['fuentes'][0]['fuente_id']), 'no particionan'),
        ('rechaza intercambiar la marca multirrol entre personas', intercambiar_multirrol, 'marca multirrol no corresponde'),
    ):
        candidato = copy.deepcopy(lote); modificar(candidato); rechazar(candidato, patron)
        assert conteo() == antes and huella_fuentes() == huella
        print('PASS:', descripcion, flush=True)
    # renderizar fija la operación; simula además un archivo JSON editado a mano.
    cuerpo = renderizar(lote, confirmar=True).replace('"operacion":"aplicar",', '', 1)
    r = sql(cuerpo, debe_pasar=False)
    assert r.returncode != 0 and 'claves o tipos obligatorios del lote' in r.stderr, r.stderr
    assert conteo() == antes and huella_fuentes() == huella
    print('PASS: operación ausente nunca convierte aplicación en reversa', flush=True)
    candidato = copy.deepcopy(lote)
    candidato['etiqueta_de_prueba'] = "comilla ' y __FIN_TRANSACCION__ y __LOTE_JSON__"
    representacion = renderizar(candidato)
    assert "comilla '' y __FIN_TRANSACCION__ y __LOTE_JSON__" in representacion
    print('PASS: generador conserva texto literal con comillas y marcadores de plantilla', flush=True)
    cierre = next(p for p in lote['personas'] if p['fuente'] == 'cierre')
    for descripcion, cambio, patron in (
        ('rechaza documento original enmascarado', f"update public.audit_log set data_despues=jsonb_set(data_despues,'{{documento}}','\"***\"') where id={literal(cierre['procedencia']['auditoria_id'])};", 'captura documental'),
        ('exige F4 apagada', "update crm.multiempresa_flags set activo=true where nombre='inversiones_escritura';", 'F3 ON y F4-F7 OFF'),
        ('rechaza suplantar un actor humano', f"set local request.jwt.claim.sub={literal(ids['analista'])};", 'sin suplantar'),
    ):
        rechazar_con_cambio(lote, cambio, patron)
        assert conteo() == antes and huella_fuentes() == huella
        print('PASS:', descripcion, flush=True)
    # El ensayo transaccional recorre las escrituras reales y las revierte.
    inicio = time.monotonic()
    sql(renderizar(lote))
    segundos_ensayo = time.monotonic() - inicio
    assert conteo() == antes and huella_fuentes() == huella
    print('PASS: ensayo con ROLLBACK conserva identidades y hechos', flush=True)
    inicio = time.monotonic()
    resultado = dato(renderizar(lote, confirmar=True))
    segundos_aplicacion = time.monotonic() - inicio
    despues = conteo()
    assert despues['personas'] == antes['personas'] + 7
    assert despues['identificadores'] == antes['identificadores'] + 7
    assert despues['reales'] == 0 and despues['demo'] == 4
    assert huella_fuentes() == huella and len(resultado['enlaces']) == 7
    print('PASS: aplica siete identidades, resuelve diez fuentes y conserva cuatro demos', flush=True)
    nuevas = ','.join(literal(e['inversionista']) for e in resultado['enlaces'])
    actividad = dato(f"select jsonb_build_object('gestiones',(select count(*) from crm.inversionista_gestiones where inversionista_id in ({nuevas}) and tipo='responsable' and creado_por is null),'tareas',(select count(*) from crm.tareas where inversionista_id in ({nuevas})))")
    assert actividad == dict(gestiones=7, tareas=0)
    print('PASS: triggers dejan siete gestiones de responsable sin tareas ni actor suplantado', flush=True)
    rechazar(lote, 'ya existente o lote ya aplicado')
    assert conteo() == despues and huella_fuentes() == huella
    print('PASS: reaplicación rechazada sin duplicar', flush=True)
    assert sql(f"select count(*) from crm.inversionistas where perfil_id={literal(ids['analista'])}").stdout.strip() == '0'
    assert sql(f"select rol from public.perfiles where id={literal(ids['analista'])}").stdout.strip() == 'analista'
    print('PASS: cuenta analista sin enlace económico ni cambio de rol', flush=True)
    assert contratos_visibles(ids['analista']) == permisos
    assert personas_del_lote_visibles(ids['analista'], lote) == 0
    assert personas_del_lote_visibles(ids['actor'], lote) == 7
    print('PASS: RLS Portal sin ampliación; núcleo F5 limita las siete personas al responsable', flush=True)
    nueva = resultado['enlaces'][0]['inversionista']
    rechazar_con_cambio(lote,
        f"insert into crm.inversion_titulares(inversion_id,inversionista_id,rol) select id,{literal(nueva)},'cotitular' from crm.inversiones order by id limit 1;",
        'referencia posterior', 'revertir')
    assert conteo() == despues and huella_fuentes() == huella
    print('PASS: reversa bloqueada ante una nueva relación de cotitularidad', flush=True)
    for descripcion, cambio, patron in (
        ('reversa bloqueada si cambió la revisión histórica', f"update crm.backfill_multiempresa_mapa set regla='Cambio posterior sintético' where inversionista_id={literal(nueva)};", 'revisión histórica cambió'),
        ('reversa bloqueada si hubo otra gestión', f"insert into crm.inversionista_gestiones select (jsonb_populate_record(null::crm.inversionista_gestiones,to_jsonb(g)||jsonb_build_object('id',gen_random_uuid()))).* from crm.inversionista_gestiones g where inversionista_id={literal(nueva)} limit 1;", 'actividad posterior'),
    ):
        rechazar_con_cambio(lote, cambio, patron, 'revertir')
        assert conteo() == despues and huella_fuentes() == huella
        print('PASS:', descripcion, flush=True)
    inicio = time.monotonic()
    sql(renderizar(lote, 'revertir', True))
    segundos_reversa = time.monotonic() - inicio
    revertido = conteo()
    assert revertido['reales'] == 10 and revertido['demo'] == 4
    assert revertido['personas'] == despues['personas']
    assert huella_fuentes() == huella
    assert sql("select count(*) from crm.inversionistas where estado='bloqueado' and perfil_id is null and responsable_relacion_id is null").stdout.strip() == '7'
    print('PASS: reversa conserva historia y restaura cobertura previa sin mover dinero', flush=True)
    ensayar_despues_reversa(lote, ids)
    assert conteo() == revertido and huella_fuentes() == huella
    print('Medición local:', json.dumps(dict(fuentes=dato('select count(*) from private.cartera_f5_fuentes()'),
        ensayo_segundos=round(segundos_ensayo, 3), aplicacion_segundos=round(segundos_aplicacion, 3),
        reversa_segundos=round(segundos_reversa, 3))), flush=True)
    probar_carrera()
    assert huella_fuentes(FUENTE) == huella_original
    print('PASS: base sintética original conservada', flush=True)
    print('Banco terminado:', DESTINO, flush=True)


if __name__ == '__main__':
    main()
