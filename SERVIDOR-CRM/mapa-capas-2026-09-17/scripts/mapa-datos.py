#!/usr/bin/env python3
"""Arma CAPAS / SANAS / SALTOS del servidor del CRM a partir de la evidencia viva.
Entradas (misma carpeta): evidencia/*.json (catálogo por CLI), front-graph.json, edge-refs.json.
Salidas: datos.json (para el artifact), evidencia-mapa.json (nivel objeto), y listas por terminal.
"""
import json, re, collections, sys, os
os.chdir(os.path.dirname(os.path.abspath(__file__)))
EV = 'evidencia'
rows = lambda n: json.load(open(f'{EV}/{n}.json'))['rows']
FUNCS, RELS, C1, C2, TRIGS, VISTAS, CRON, FLAGS, POLS, GRANTS, F7, SQL2EDGE = [rows(n) for n in
    ('01_funciones','02_relaciones','03_refs_c1','04_refs_c2','05_triggers','06_vistas','07_cron','08_flags_schemas','09_politicas','10_grants_columnas','11_f7_observacion','13_sql_a_edge')]
FRONT = json.load(open('front-graph.json'))
EDGES_SRC = json.load(open('edge-refs.json'))
PANTALLAS = json.load(open('pantallas.json'))

# ───────────────────────── módulos ─────────────────────────
MODULOS = [
 ('ayuda','Ayuda al vendedor', r'ayuda'),
 ('auditoria','Auditoría, vigías y guardas', r'f7_piezas|f7_obs|^audit_log$|^auditoria_|^vigia_|^assert_|log_audit|trg_config_versionada|^idem_|huella_exenciones|set_actualizado_en_crm|verificar_cron|^enmascarar|^redactar_pii'),
 ('tasa','Tasa y rentabilidad', r'tasa|rentabilidad|push_tasa|dispositivos_push|envios_push'),
 ('postventa','Postventa', r'postventa'),
 ('sla','SLA y cola operativa', r'^sla|_sla|sla_|cola_accion|politica_abandono|abandono|umbral_estancamiento|registrar_actividad_v2|cerrar_tarea_v2|reprogramar_tarea_v2|cerrar_reunion_v2|reprogramar_reunion_v2|prorroga'),
 ('citas','Citas de Gerencia', r'citas|control_citas|metricas_reuniones'),
 ('reparto','Distribución y derivaciones', r'repart|derivac|derivar|distribucion|capacidad_leads|supervisores_para_reparto|panel_distribucion|devolucion_equipo|leads_por_repartir|sanitizar_sujetos|filtrar_desglose|cola_reparto'),
 ('inversiones','Inversiones e identidad', r'inversion|inversionista|fusion|identidad|multiempresa|backfill|^empresas$|piloto_f8|^f4_|^f2_|cartera_f5|personas|responsable_relacion|juicio_|documento_es_de_identidad|coopac|cotitular|tablas_sin_rastro|veredicto_f7|metricas_f7|resolver_en_puertas|ficha_360|alta_cliente_identidad|asegurar_identidad'),
 ('conversion','Conversión y cierres', r'conversion|convertir|cierre|saga_|depositos_reclamados|ajustes_mes|periodos_cerrados|produccion_mes|vendedor_acreditado|analista_atribuido|atribucion|peso_referido|marcar_efectos|persona_en_conversion|saldar_ajustes|registrar_ajuste|ajuste_pendiente|corregir_fecha_cierre|cerrar_periodo|etiqueta_mes'),
 ('contratos','Contratos y capital', r'contrato|cronograma|cuotas|capital|operaciones_cartera|cuentas_bancarias|cuentas_pago|reasignacion|reasignar_analista|titulares|pdf|producto_snapshot|siguiente_numero|periodo_comercial|documental|pagos|vencidos|vencimientos|puede_registrar_ventas|rango_capital|marcar_contrato|numero_contrato|tipo-cambio|tipo_cambio'),
 ('leads','Leads y cartera', r'lead|cartera|descart|rescat|no_contactar|verificaciones|importar|importacion|disponibilidad|reingreso|tenencia|etapa|toma_asienta|tomar|enfriamiento|clasificar_movimiento|inicio_ciclo|bloquear_contactos|telefono|vetad|canonizar_contacto|gestion_contacto|reconocimientos|^hoja'),
 ('agenda','Agenda, tareas y reuniones', r'tarea|reunion|agenda|recordatorio|actividad|ics|calendario|no_show|crear_siguiente|retroceso_por_anular|contacto'),
 ('clientes','Clientes (perfiles)', r'cliente|perfiles|domicilio|correo|documento|asesor|dni|normalizar_nombre|proteger_campos_inmutables|^set_actualizado_en$|bloquear_borrado_domicilio|mi_rol|obtener_mi_asesor|resetear|crear-admin'),
 ('acceso','Usuarios, equipo y permisos', r'equipo|usuario|membresia|jerarquia|^rol_|^es_|^puede_|acceso|lector_global|vendedor_ids_visibles|vendedores_sin_supervisor|candidato|par_autoridad|pares_autoridad|asignar_rol|supervisor|vigencia|validar_datos_usuario|saga_auth|auth_usuario|saga_token|usuario_eventos|purgar_membresia|mi_acceso|password|bandera|puertas_analista|roster'),
 ('metas','Metas y productos', r'meta|objetivo|cumplimiento|producto|catalogo|insertar_condiciones|validar_cabecera_version'),
 ('metricas','Métricas y reportes', r'metricas|series|ranking|dashboard|directorio|facturacion|altas|analitica|contadores_crudos|top_clientes|morosidad|admin_pagos|pagos_admin|resumen_'),
 ('notificaciones','Notificaciones del portal', r'novedades|suscripciones_push|enviar-push|enviar-comunicado|notificar-pagos|diagnostico-push|comunicado'),
 ('otros','Sin módulo', r'.'),
]
MOD_TITULO = {m[0]: m[1] for m in MODULOS}
ORDEN_MOD = [m[0] for m in MODULOS if m[0] != 'otros'] + ['otros']
# orden visual de los módulos en cada banda (recorrido comercial de izquierda a derecha)
ORDEN_VISUAL = ['leads','reparto','agenda','citas','sla','conversion','tasa','contratos','inversiones','postventa','clientes','metas','metricas','acceso','auditoria','ayuda','notificaciones','otros']
EDGE_MOD = {'crear-cliente':'clientes','crear-admin':'acceso','enviar-comunicado':'notificaciones','enviar-push':'notificaciones','diagnostico-push':'notificaciones','resetear-password':'acceso','eliminar-cliente':'clientes','notificar-pagos':'notificaciones','importar-clientes':'clientes','ciclo-contratos':'contratos','crm-convertir-lead':'conversion','crm-tipo-cambio':'contratos','crm-agenda-ics':'agenda','crm-importar-leads':'leads','crm-usuarios':'acceso','crm-contrato-pdf-v2':'contratos','crm-inversion-portal':'inversiones','crm-inversion-documento':'inversiones','crm-notificaciones-tasa':'tasa','corregir-correo-cliente':'clientes'}
EDGE_CRON = {'ciclo-contratos'}   # notificar-pagos también la llama el portal → puerta
CONFIG_TABLES = set('''productos_inversion producto_versiones producto_condiciones sla_politicas sla_politica_etapas sla_politica_etapas_operacion sla_operacion_control meta_periodos metas_vendedor metas_vendedor_detalle politica_rentabilidad politica_abandono enfriamiento_politica control_citas_versiones control_citas_aplicaciones multiempresa_flags empresas equipo agenda_ics piloto_f8_control piloto_f8_miembros objetivos_legacy_archivo objetivos_vendedores_legacy_archivo ayuda_expresiones ayuda_intenciones ayuda_reglas_aclaracion pares_autoridad analista_vigencia_tope analista_vigencia_exenciones analitica_leads_citas_tope analitica_leads_citas_exenciones auditoria_exenciones auditoria_condicionada f7_piezas_en_observacion asesores'''.split())
TRANSVERSALES = {'acceso','auditoria'}

def modulo_de(nombre):
    for mid,_,rx in MODULOS:
        if re.search(rx, nombre): return mid
    return 'otros'

# ───────────────────────── objetos ─────────────────────────
OBJ = {}
F7_ESTADO = {}
for r in F7:
    fq = r['firma'].split('(')[0]
    F7_ESTADO[fq] = r['estado']
for r in RELS:
    fq = r['fq']; sch, nm = fq.split('.',1)
    es_vista = r['relkind'] in ('v','m')
    OBJ[fq] = dict(id=fq, kind='vista' if es_vista else 'tabla', schema=sch, nombre=nm, modulo=modulo_de(nm),
                   capa=3 if es_vista else 1, rls=r['rls'], a_sel=r['a_sel'], a_ins=r['a_ins'], a_upd=r['a_upd'], a_del=r['a_del'],
                   a_col_sel=r['a_col_sel'], anon_sel=r['anon_sel'], policies=r['policies'], reloptions=r.get('reloptions'),
                   config=nm in CONFIG_TABLES, comentario=(r.get('comentario') or '')[:160])
fn_rows = collections.defaultdict(list)
for r in FUNCS: fn_rows[r['fq']].append(r)
for fq, rs in fn_rows.items():
    sch, nm = fq.split('.',1)
    trigger = any(x['ret']=='trigger' for x in rs)
    auth = any(x['auth_exec'] for x in rs); anon = any(x['anon_exec'] for x in rs)
    f7 = F7_ESTADO.get(fq)
    if trigger: capa = 2
    elif sch == 'private': capa = 2
    elif f7 == 'cerrada_permanente': capa = 2   # órgano interno reconocido por F7 (JAMÁS se derriba)
    else: capa = 3
    OBJ[fq] = dict(id=fq, kind='fn', schema=sch, nombre=nm, modulo=modulo_de(nm), capa=capa, trigger=trigger,
                   auth_exec=auth, anon_exec=anon, secdef=any(x['secdef'] for x in rs), lang=rs[0]['lang'], firmas=len(rs),
                   abierta=(auth or anon) and capa==3, f7=f7, comentario=(rs[0].get('comentario') or '')[:160])
EDGE_SLUGS = list(EDGES_SRC.keys())
for slug in EDGE_SLUGS:
    OBJ['edge:'+slug] = dict(id='edge:'+slug, kind='edge', schema='edge', nombre=slug, modulo=EDGE_MOD.get(slug,'otros'),
                             capa=2 if slug in EDGE_CRON else 3, abierta=True, dir=EDGES_SRC[slug]['dir'])
for p in PANTALLAS:
    OBJ['pantalla:'+p['id']] = dict(id='pantalla:'+p['id'], kind='pantalla', nombre=p['titulo'], capa=4, modulo='pantalla', roots=p['roots'], vistas=p.get('vistas'))
ACTORES = {
 'actor:app': dict(nombre='App CRM · sesión, store y avisos', capa=4, desc='Llamadas que hace el armazón de la app (auth, store al arrancar, proveedores de alertas y push) en cualquier pantalla.'),
 'actor:portal': dict(nombre='Portal del cliente (public_html)', capa=4, desc='Front vanilla del portal miavance.com. Solo se inventariaron sus llamadas directas (grep); no se analizó su cadena interna.'),
 'actor:hoja': dict(nombre='Hoja comercial (puente de leads)', capa=4, desc='Google Sheets → Edge crm-importar-leads.'),
 'actor:calendario': dict(nombre='Calendario externo (feed ICS)', capa=4, desc='Google Calendar consume el feed público por token.'),
 'actor:cron': dict(nombre='pg_cron · %d tareas' % len(CRON), capa=2, desc='Reloj interno de Postgres. Se dibuja en la capa Núcleo porque vive dentro de la base.'),
}
for k,v in ACTORES.items(): OBJ[k] = dict(id=k, kind='actor', schema='actor', nombre=v['nombre'], capa=v['capa'], modulo='actor', desc=v['desc'])

# ───────────────────────── aristas objeto: consumidor -> proveedor ─────────────────────────
E = []   # dict(c, p, via, tipo)
DESCONOCIDOS = collections.Counter()
def add(c, p, via, tipo):
    if c == p: return
    if c not in OBJ or p not in OBJ:
        DESCONOCIDOS[(c if c not in OBJ else p, via.split(' ')[0])] += 1; return
    E.append(dict(c=c, p=p, via=via, tipo=tipo))

# 1) cuerpos SQL: tablas por criterio 2 (from/join/into/update/delete), funciones por criterio 1 ∪ 2
c1 = {r['fq']: {x.rsplit(':',1)[0] for x in r['refs'].split(' ')} for r in C1}
c2t = collections.defaultdict(set); c2f = collections.defaultdict(set)
for r in C2:
    for x in r['refs'].split(' '):
        (c2t if x.startswith('T:') else c2f)[r['fq']].add(x[2:])
COMPARACION = dict(tablas_solo_c1=[], funciones_solo_c1=[], funciones_solo_c2=[])
for fq, refs in c1.items():
    if fq not in OBJ: continue
    for ref in refs:
        o = OBJ.get(ref)
        if not o: continue
        if o['kind'] in ('tabla','vista'):
            if ref in c2t.get(fq, ()): add(fq, ref, 'cuerpo SQL (from/join/into/update)', 'sql')
            else: COMPARACION['tablas_solo_c1'].append([fq, ref])
        elif o['kind'] == 'fn':
            if ref in c2f.get(fq, ()): add(fq, ref, 'cuerpo SQL (llamada)', 'sql')
            else: COMPARACION['funciones_solo_c1'].append([fq, ref])   # mención sin paréntesis: mensaje o string, no llamada
for fq, refs in c2f.items():
    for ref in refs:
        if ref in OBJ and ref not in c1.get(fq, ()): COMPARACION['funciones_solo_c2'].append([fq, ref])
# 2) triggers: la tabla alimenta a su función de trigger
for t in TRIGS: add(t['fn'], t['tabla'], 'trigger %s' % t['tgname'], 'trigger')
# 3) vistas: definición → tablas y funciones
for v in VISTAS:
    for m in re.finditer(r'\b(crm|private|public)\.([a-z0-9_]+)', v['def']): add(v['vista'], m.group(1)+'.'+m.group(2), 'definición de la vista', 'vista')
# 4) cron
for j in CRON:
    for m in re.finditer(r'\b(crm|private|public)\.([a-z0-9_]+)\s*\(', j['command']): add('actor:cron', m.group(1)+'.'+m.group(2), 'cron.job %s (%s)' % (j['jobname'], j['schedule']), 'cron')
    for m in re.finditer(r'functions/v1/([a-z0-9-]+)', j['command']): add('actor:cron', 'edge:'+m.group(1), 'cron.job %s (%s) via net.http_post' % (j['jobname'], j['schedule']), 'cron')
# 5) SQL → Edge por HTTP
for r in SQL2EDGE: add(r['fq'], 'edge:'+r['edge'], 'net.http_post desde el cuerpo SQL', 'sql')
# 6) Edge Functions → SQL / tablas / otras edge
EXTRA_EDGE = {'crm-contrato-pdf-v2': [('rpc','crm',n) for n in ('contrato_pdf_reservar','contrato_pdf_reclamar','contrato_pdf_marcar_subido','contrato_pdf_finalizar','contrato_pdf_marcar_error')]}
def resolver(schema, name, kind):
    cands = [schema] if schema else ['public','crm']
    if schema == 'public': cands = ['public','crm']
    for s in cands:
        fq = s+'.'+name
        if fq in OBJ and (OBJ[fq]['kind']=='fn') == (kind=='rpc'): return fq
    return (schema or 'public')+'.'+name
for slug, info in EDGES_SRC.items():
    calls = [(c['kind'], c.get('schema'), c['name'], '%s:%s' % (c['file'], c['line'])) for c in info['calls'] if c['name'] != '<dinámico>' and c['kind'] in ('rpc','table','edge')]
    calls += [(k,s,n,'handler.ts (rpc dinámico por nombre)') for k,s,n in EXTRA_EDGE.get(slug, [])]
    for kind, schema, name, where in calls:
        if kind == 'edge': add('edge:'+slug, 'edge:'+name, 'Edge %s %s' % (slug, where), 'edge')
        else: add('edge:'+slug, resolver(schema, name, kind), 'Edge %s %s (service_role)' % (slug, where), 'edge')
# 7) Front: pantallas y armazón
def front_calls(calls, who):
    for c in calls:
        if c['kind'] == 'storage': continue
        if c['name'] == '<dinámico>':
            if c.get('symbol') == 'listarCarteraPagina':
                for n in ('cartera_filtrada_fn','cartera_pagina_fn'): add(who, 'crm.'+n, 'front %s:%s (rpc condicional)' % (c['file'], c['line']), 'front')
            continue
        if c['kind'] == 'edge': add(who, 'edge:'+c['name'], 'front %s:%s' % (c['file'], c['line']), 'front'); continue
        schema = c.get('schema')
        if not schema and c['file'] == 'data/gestion-inversionista.ts': schema = 'crm'
        add(who, resolver(schema, c['name'], c['kind']), 'front %s:%s' % (c['file'], c['line']), 'front')
for p in FRONT['pantallas']: front_calls(p['calls'], 'pantalla:'+p['id'])
front_calls(FRONT['shell']['calls'], 'actor:app')
add('actor:hoja', 'edge:crm-importar-leads', 'Apps Script de la hoja comercial → Edge', 'externo')
add('actor:calendario', 'edge:crm-agenda-ics', 'Google Calendar → URL del feed', 'externo')
PORTAL = dict(rpc='resolver_tasa_fn obtener_mi_asesor crear_contrato actualizar_contrato_con_cuenta_pdf_v3 productos_inversion_seleccion_fn metricas_directorio directorio_top_clientes directorio_ranking_analistas directorio_morosidad dashboard_admin_metricas cuentas_pago_contratos_fn corregir_documento_cliente_admin_fn contrato_tiene_pagos cerrar_contrato bandeja_actividad admin_pagos_resumen admin_pagos_metricas actualizar_numero_contrato_pdf_v3'.split(),
              tablas='perfiles contratos cronograma_pagos novedades_leidas documentos novedades contrato_titulares comunicados suscripciones_push asesores'.split(),
              edges='corregir-correo-cliente crear-admin crear-cliente crm-contrato-pdf-v2 eliminar-cliente enviar-comunicado importar-clientes notificar-pagos resetear-password'.split())
for n in PORTAL['rpc']: add('actor:portal', resolver(None, n, 'rpc'), 'public_html/js (grep .rpc)', 'front')
for n in PORTAL['tablas']: add('actor:portal', resolver(None, n, 'table'), 'public_html/js (grep .from)', 'front')
for n in PORTAL['edges']: add('actor:portal', 'edge:'+n, 'public_html/js (grep functions/v1)', 'front')
# dedupe
seen = set(); E2 = []
for e in E:
    k = (e['c'], e['p'])
    if k in seen: continue
    seen.add(k); E2.append(e)
E = E2

# ───────────────────────── clasificación ─────────────────────────
consumidores = collections.defaultdict(set); proveedores = collections.defaultdict(set); consumidores_reales = collections.defaultdict(set)
for e in E:
    consumidores[e['p']].add(e['c']); proveedores[e['c']].add(e['p'])
    if e['tipo'] != 'trigger': consumidores_reales[e['p']].add(e['c'])
TRIG_FNS = {t['fn'] for t in TRIGS}
RLS_FNS = set()
for pol in POLS:
    for expr in (pol.get('using_expr') or '', pol.get('check_expr') or ''):
        for m in re.finditer(r'\b(crm|private|public)\.([a-z0-9_]+)\s*\(', expr): RLS_FNS.add(m.group(1)+'.'+m.group(2))
for o in OBJ.values():
    o['usado_en_rls'] = o['id'] in RLS_FNS
    o['huerfano'] = o['kind'] in ('tabla','vista','fn','edge') and not consumidores_reales.get(o['id']) and o['id'] not in TRIG_FNS and o['id'] not in RLS_FNS
def usa_nucleo(c):
    return any(OBJ[p]['capa']==2 and OBJ[p]['kind'] in ('fn','edge') for p in proveedores.get(c, ()))
for e in E:
    c, p = OBJ[e['c']], OBJ[e['p']]
    lc, lp = c['capa'], p['capa']
    if lc == lp: e['clase'] = 'mismo'
    elif lc == lp+1: e['clase'] = 'adyacente'
    elif lc > lp+1: e['clase'] = 'salto'; e['salta'] = lc-lp-1
    else: e['clase'] = 'inversion'; e['salta'] = 0
    sev = None; nota = ''
    if e['clase'] == 'salto':
        if p['kind'] in ('tabla',):
            if c['capa'] == 4:
                sev = 'B' if p['config'] else 'A'; nota = 'la pantalla lee/escribe la tabla directo por PostgREST (RLS %s)' % ('activa' if p['rls'] else 'SIN RLS')
            elif c['kind'] == 'vista':
                inv = 'security_invoker=true' in (p.get('reloptions') or []) or 'security_invoker=true' in (c.get('reloptions') or [])
                sev = 'D' if 'security_invoker=true' in (c.get('reloptions') or []) else 'A'; nota = 'vista de lectura %s' % ('con security_invoker (RLS del lector)' if sev=='D' else 'SIN security_invoker')
            else:
                if p['config']: sev = 'B'; nota = 'catálogo/configuración leído directo'
                elif c['kind'] == 'edge': sev = 'A'; nota = 'Edge con service_role toca la tabla sin núcleo ni RLS'
                elif usa_nucleo(e['c']): sev = 'M'; nota = 'puerta mixta: usa núcleo pero además toca la tabla directo'
                else: sev = 'A'; nota = 'puerta autónoma: toda la lógica vive en la puerta, sin núcleo'
        elif p['capa'] == 2:
            sev = 'A'; nota = 'la pantalla llama al núcleo sin pasar por una puerta'
        else: sev = 'A'
    elif e['clase'] == 'inversion':
        sev = 'D' if c['kind']=='actor' else 'M'; nota = 'inversión: el núcleo depende de una puerta' if c['kind']!='actor' else 'reloj interno que dispara una puerta cerrada'
    e['sev'] = sev; e['nota'] = nota

# ───────────────────────── nodos de grupo ─────────────────────────
def nodo_de(o):
    if o['capa'] == 4 or o['kind']=='actor': return o['id']
    return '%s:%s' % ({1:'t',2:'n',3:'p'}[o['capa']], o['modulo'])
NODOS = {}
for o in OBJ.values():
    nid = nodo_de(o)
    if nid not in NODOS:
        if o['capa']==4 or o['kind']=='actor':
            NODOS[nid] = dict(id=nid, capa=o['capa'], modulo=o['modulo'], titulo=o['nombre'], miembros=[], kind=o['kind'])
        else:
            NODOS[nid] = dict(id=nid, capa=o['capa'], modulo=o['modulo'], titulo=MOD_TITULO[o['modulo']], miembros=[], kind='grupo')
    NODOS[nid]['miembros'].append(o['id'])
for n in NODOS.values():
    ms = [OBJ[m] for m in n['miembros']]
    n['n'] = len(ms)
    n['huerfanos'] = sorted(m['id'] for m in ms if m.get('huerfano'))
    n['huerfano'] = n['kind']=='grupo' and len(n['huerfanos'])==n['n']
    n['resumen'] = collections.Counter(('vista' if m['kind']=='vista' else 'edge' if m['kind']=='edge' else 'trigger' if m.get('trigger') else 'puerta cerrada' if (m['kind']=='fn' and m['capa']==3 and not m.get('abierta')) else 'puerta' if m['capa']==3 and m['kind']=='fn' else m['kind']) for m in ms)
    n['transversal'] = n['capa']==2 and n['modulo'] in TRANSVERSALES
    n['cerradas'] = sorted(m['id'] for m in ms if m['kind']=='fn' and m['capa']==3 and not m.get('abierta'))
    n['f7'] = sorted(m['id'] for m in ms if m.get('f7'))

# ───────────────────────── líneas de grupo ─────────────────────────
SEV_ORD = {'A':0,'M':1,'B':2,'D':3}
lineas = collections.OrderedDict()
for e in E:
    c, p = OBJ[e['c']], OBJ[e['p']]
    nc, np_ = nodo_de(c), nodo_de(p)
    if nc == np_ and e['clase'] in ('mismo',): continue   # dentro del mismo grupo no se dibuja
    k = (np_, nc, e.get('sev'))
    if k not in lineas:
        lineas[k] = dict(origen=np_, destino=nc, sev=e.get('sev'), clase=e['clase'], salta=e.get('salta',0), miembros=[], transversal=NODOS[np_]['transversal'] or NODOS[nc]['transversal'])
    lineas[k]['miembros'].append(dict(p=p['id'], c=c['id'], via=e['via'], nota=e['nota']))
SANAS, SALTOS = [], []
for k, l in lineas.items():
    l['n'] = len(l['miembros'])
    if l['sev'] is None: SANAS.append(l)
    else: SALTOS.append(l)
def orden_nodo(nid):
    n = NODOS[nid]
    return (n['capa'], ORDEN_VISUAL.index(n['modulo']) if n['modulo'] in ORDEN_VISUAL else 99, n['titulo'])
SALTOS.sort(key=lambda l: (SEV_ORD[l['sev']], -l['salta'], orden_nodo(l['origen']), orden_nodo(l['destino'])))
cnt = collections.Counter()
for l in SALTOS:
    cnt[l['sev']] += 1; l['id'] = '%s%d' % (l['sev'], cnt[l['sev']])
    # estado 'corr': todos los consumidores en observación F7 (pendientes de derribo)
    cons = {m['c'] for m in l['miembros']}
    l['estado'] = 'corr' if cons and all(OBJ[c].get('f7')=='observacion' for c in cons) else 'vivo'
    capas_saltadas = []
    if l['clase']=='salto':
        lo, ld = NODOS[l['origen']]['capa'], NODOS[l['destino']]['capa']
        capas_saltadas = [{1:'Tablas',2:'Núcleo',3:'Puerta',4:'Pantalla'}[x] for x in range(lo+1, ld)]
    l['capas_saltadas'] = capas_saltadas
    notas = collections.Counter(m['nota'] for m in l['miembros'])
    l['nota'] = '; '.join('%s (%d)' % (k, v) if len(notas)>1 else k for k, v in notas.most_common())
for l in SANAS: l['id'] = 'S%d' % (SANAS.index(l)+1)

# ───────────────────────── CAPAS ─────────────────────────
CAPAS = []
for capa, titulo in ((1,'Tablas'),(2,'Núcleo'),(3,'Puertas'),(4,'Pantallas')):
    nodos = [n for n in NODOS.values() if n['capa']==capa]
    if capa == 4:
        orden_p = ['pantalla:'+p['id'] for p in PANTALLAS] + ['actor:app','actor:portal','actor:hoja','actor:calendario']
        nodos.sort(key=lambda n: orden_p.index(n['id']) if n['id'] in orden_p else 99)
    else:
        nodos.sort(key=lambda n: (n['kind']=='actor', ORDEN_VISUAL.index(n['modulo']) if n['modulo'] in ORDEN_VISUAL else 99))
    CAPAS.append(dict(id=capa, titulo=titulo, nodos=[n['id'] for n in nodos]))

META = dict(proyecto='dctqcbznekcyxhjujuci', fecha=[r['a'] for r in FLAGS if r['k']=='now'][0], flags={r['a']: r['b']=='true' for r in FLAGS if r['k']=='flag'},
            totales=dict(funciones=len(fn_rows), firmas=len(FUNCS), relaciones=len(RELS), edge=len(EDGE_SLUGS), cron=len(CRON), pantallas=len(PANTALLAS), aristas_objeto=len(E), sanas=len(SANAS), saltos=len(SALTOS), por_sev=dict(cnt)),
            desconocidos=sorted(['%s ← %s ×%d' % (k[0], k[1], v) for k, v in DESCONOCIDOS.items()]),
            comparacion={k: len(v) for k, v in COMPARACION.items()}, comparacion_detalle=COMPARACION,
            private_con_execute=sorted(o['id'] for o in OBJ.values() if o['kind']=='fn' and o['schema']=='private' and o['auth_exec'] and not o['trigger']),
            triggers_en_crm=sorted(o['id'] for o in OBJ.values() if o['kind']=='fn' and o['schema']=='crm' and o['trigger']),
            f7={k: v for k, v in F7_ESTADO.items()})
json.dump(dict(CAPAS=CAPAS, NODOS=NODOS, SANAS=SANAS, SALTOS=SALTOS, META=META), open('datos.json','w'), ensure_ascii=False, indent=0)
json.dump(dict(objetos=OBJ, aristas=E, meta=META), open('evidencia-mapa.json','w'), ensure_ascii=False, indent=0)
OBJ_MIN = {o['id']: dict(k=o['kind'], c=o['capa'], m=o.get('modulo'), a=o.get('abierta'), h=o.get('huerfano'), t=o.get('trigger'), f7=o.get('f7'), cf=o.get('config'), rls=o.get('rls'), cm=(o.get('comentario') or '')[:120], sd=o.get('secdef'), n=o['nombre']) for o in OBJ.values()}
META_MIN = {k: META[k] for k in ('proyecto','fecha','flags','totales','desconocidos','comparacion','private_con_execute','triggers_en_crm')}
json.dump(dict(CAPAS=CAPAS, NODOS=NODOS, SANAS=SANAS, SALTOS=SALTOS, OBJ=OBJ_MIN, META=META_MIN, MODULOS={m[0]: m[1] for m in MODULOS}), open('datos-artifact.json','w'), ensure_ascii=False, separators=(',',':'))

# ───────────────────────── terminal ─────────────────────────
print('== CAPAS (nodos por capa; ✖ = huérfano) ==')
for c in CAPAS:
    print('\n[%d] %s — %d nodos' % (c['id'], c['titulo'], len(c['nodos'])))
    for nid in c['nodos']:
        n = NODOS[nid]
        res = ', '.join('%d %s' % (v, k) for k, v in sorted(n['resumen'].items()))
        print('  %s%-38s %s%s' % ('✖ ' if n['huerfano'] else '  ', n['titulo'], res, ('  · huérfanos: %d' % len(n['huerfanos'])) if n['huerfanos'] else ''))
print('\n== SANAS (%d líneas de grupo, %d aristas objeto) ==' % (len(SANAS), sum(l['n'] for l in SANAS)))
for l in SANAS: print('  %-4s %-28s → %-38s %3d%s' % (l['id'], NODOS[l['origen']]['titulo'][:28], NODOS[l['destino']]['titulo'][:38], l['n'], '  [transversal]' if l['transversal'] else ''))
print('\n== SALTOS (%d) por severidad %s ==' % (len(SALTOS), dict(cnt)))
for l in SALTOS: print('  %-4s %-28s ⇢ %-38s %3d  salta %-14s %s%s' % (l['id'], NODOS[l['origen']]['titulo'][:28], NODOS[l['destino']]['titulo'][:38], l['n'], '+'.join(l['capas_saltadas']) or l['clase'], l['nota'][:90], '  [corr]' if l['estado']=='corr' else ''))
print('\n== META ==', json.dumps({k: v for k, v in META.items() if k in ('totales','comparacion','desconocidos','private_con_execute','triggers_en_crm')}, ensure_ascii=False, indent=1))
