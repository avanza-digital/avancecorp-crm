import type { Page } from '@playwright/test'
import { leadReal, montarBackendReal, UID, type BackendReal } from './_helpers'
import muestraSql from '../src/data/sla-operacion-sql.test.fixture.json' with { type: 'json' }
import muestraV3 from '../src/data/sla-operacion-cola-v3-sql.test.fixture.json' with { type: 'json' }

/**
 * Una página con la forma de la v2 llevada a la de la v3, que es la que leen
 * todas las colas del front desde el 29/09/2026: `version: 3`,
 * `totales.clientes` y cada lead con su `clave` y su `sujeto`, como los añade
 * `crm.cola_accion_v3_fn`. Las tareas de clientes que ya vengan en forma v3
 * pasan tal cual.
 */
export function aColaV3<T extends { items: ReadonlyArray<Record<string, unknown>>; totales?: Record<string, number> }>(pagina: T) {
  const clientes = pagina.items.filter((i) => i['lead_id'] === null).length
  return {
    ...pagina,
    version: 3,
    totales: { ...(pagina.totales ?? {}), clientes: pagina.totales?.['clientes'] ?? clientes },
    items: pagina.items.map((i) => (i['lead_id'] === null || i['clave'] !== undefined ? i : {
      ...i, clave: `lead:${String(i['lead_id'])}`,
      sujeto: { tipo: 'lead', id: i['lead_id'], nombre: (i['lead'] as { nombre_completo: string }).nombre_completo },
    })),
  }
}

/** Una tarea de CLIENTE para las colas simuladas (forma v3 exacta). */
export type ClienteCola = { tarea: string; nombre: string; inversionista_id: string | null; perfil_id: string | null; vencida: boolean; responsable?: string }
function itemCliente(c: ClienteCola, referencia: string) {
  return {
    clave: `tarea:${c.tarea}`, tarea_id: c.tarea, lead_id: null, lead: null, estado: null,
    bucket: c.vencida ? 'tarea_vencida' : 'tarea_hoy', severidad: c.vencida ? 'critica' : 'media', prioridad: c.vencida ? 20 : 30,
    referencia_en: referencia,
    senales: { pendientes: c.vencida, tareas_vencidas: c.vencida, primera_atencion: false, seguimientos_pendientes: false, revisiones: false, datos_incompletos: false, por_repartir: false },
    sujeto: { tipo: 'cliente', perfil_id: c.perfil_id, inversionista_id: c.inversionista_id, nombre: c.nombre },
  }
}

export type PedidoCola = {
  p_cursor: { inicio: number } | null
  p_limite: number
  p_senal: string
  p_etapa?: string
  p_analista_id?: string
}

export async function montarColaEquipo(page: Page, rolCrm: 'gerencia' | 'supervisor' | 'vendedor', cantidad = 14, clientes: ClienteCola[] = []) {
  const analistaUno = 'aaaaaaaa-0000-4000-8000-000000000001'
  const analistaDos = 'aaaaaaaa-0000-4000-8000-000000000002'
  const analistaAjeno = 'aaaaaaaa-0000-4000-8000-000000000003'
  const equipoVisible = [
    { perfil_id: analistaUno, nombre_completo: 'Analista Norte Uno', rol_crm: 'vendedor', supervisor_id: UID, activo: true },
    { perfil_id: analistaDos, nombre_completo: 'Analista Norte Dos', rol_crm: 'vendedor', supervisor_id: UID, activo: true },
    ...(rolCrm === 'gerencia' ? [{ perfil_id: analistaAjeno, nombre_completo: 'Analista Sur', rol_crm: 'vendedor', supervisor_id: null, activo: true }] : []),
  ]
  const cartera = Array.from({ length: cantidad }, (_, i) => leadReal({
    id: `cccccccc-0000-4000-8000-${String(i + 1).padStart(12, '0')}`,
    nombre_completo: `OPORTUNIDAD ${i < 12 ? 'NORTE' : 'SUR'} ${String(i + 1).padStart(2, '0')}`,
    vendedor_id: rolCrm === 'vendedor' ? UID : i < 6 ? analistaUno : i < 12 ? analistaDos : analistaAjeno,
    fueraDelBoot: i >= 100,
    etapa: i % 4 < 2 ? 'contactado' : 'propuesta_enviada',
  }))
  // La respuesta simula el ámbito de la RPC, no autorización en el navegador.
  // El banco SQL prueba RLS: aquí comprobamos que la UI conserva sus filas y
  // envía filtros al servidor sin sustituirlos por una búsqueda del store.
  const visibles = rolCrm === 'gerencia' ? cartera : cartera.slice(0, 12)
  await montarBackendReal(page, { rolCrm, leads: visibles })
  await page.route('**/rest/v1/rpc/equipo_visible_fn', (route) => route.fulfill({ json: [
    { perfil_id: UID, nombre_completo: 'Responsable del equipo', rol_crm: rolCrm, supervisor_id: null, activo: true },
    ...equipoVisible,
  ] }))
  const calculado = '2026-09-07T12:00:00.000Z'
  const filas = visibles.map((lead, i) => {
    const original = muestraSql.cola.items[0]!
    const revision = i % 2 === 0
    return {
      ...original, lead_id: lead.id,
      bucket: i % 3 === 0 ? 'primera_atencion' : i % 3 === 1 ? 'tarea_vencida' : 'seguimiento',
      severidad: i % 3 === 0 ? 'critica' : 'media', prioridad: 10 + i,
      referencia_en: calculado,
      lead: { id: lead.id, nombre_completo: lead.nombre_completo, etapa: lead.etapa,
        analista_id: lead.vendedor_id, analista_nombre: lead.vendedor_id === UID ? 'Analista de prueba' : equipoVisible.find((miembro) => miembro.perfil_id === lead.vendedor_id)!.nombre_completo },
      senales: { pendientes: true, primera_atencion: i % 3 === 0, tareas_vencidas: i % 3 === 1,
        seguimientos_pendientes: i % 3 === 2, revisiones: revision, datos_incompletos: false, por_repartir: false },
      estado: { ...original.estado, lead_id: lead.id,
        compromiso: i % 5 === 4 ? original.estado.compromiso : { tarea: null, validez: 'sin_tarea', hasta_en: null, cobertura_activa: false },
        etapa: { ...original.estado.etapa,
        revision_requerida: revision, motivos_revision: revision ? ['limite_operativo_agotado'] : [] } },
    }
  })
  // Caso histórico como el que motivó aclarar los textos: seguimiento, etapa
  // y Agenda tienen fechas distintas. La UI debe explicar cada una por separado.
  const ejemplo = filas[0]!.estado
  ejemplo.seguimiento = { ...ejemplo.seguimiento, limite_en: '2026-09-07T04:03:00Z', vencido: true, accion_pendiente: true }
  ejemplo.compromiso = {
    tarea: { id: 'eeeeeeee-0000-4000-8000-000000000001', tipo: 'llamada', vence_en: '2026-08-31T15:00:00Z', reprogramaciones: 0 },
    validez: 'valido', cobertura_activa: false, hasta_en: '2026-08-31T19:00:00Z',
  }
  ejemplo.avisos = [...ejemplo.avisos, { ...ejemplo.avisos[0]!, id: 'revision-ejemplo', bucket: 'revision_comercial', tarea_id: null }]
  ejemplo.etapa = { ...ejemplo.etapa,
    limite_original_en: '2026-09-01T15:00:00Z', limite_prorrogado_en: '2026-09-01T15:00:00Z',
    limite_operativo_en: '2026-09-01T15:00:00Z', techo_en: '2026-09-02T16:21:00Z',
    prorrogas_usadas: 0,
  }
  await page.route('**/rest/v1/rpc/estado_sla_leads_v2_fn', async (route) => {
    const args = route.request().postDataJSON() as { p_lead_ids: string[] }
    await route.fulfill({ json: { ...muestraSql.estado, calculado_en: calculado,
      filas: args.p_lead_ids.map((id) => filas.find((fila) => fila.lead_id === id)?.estado ?? { ...muestraSql.estado.filas[0], lead_id: id }) } })
  })
  const pedidos: PedidoCola[] = []
  await page.route('**/rest/v1/rpc/cola_accion_v3_fn', async (route) => {
    const args = route.request().postDataJSON() as PedidoCola
    pedidos.push(args)
    // Clientes con la regla del servidor: `p_etapa` los excluye, `p_analista_id` filtra a su responsable.
    const deClientes = args.p_etapa ? [] : clientes
      .filter((c) => !args.p_analista_id || c.responsable === args.p_analista_id)
      .map((c) => itemCliente(c, calculado))
    const ambito = [...filas.filter((fila) => (!args.p_etapa || fila.lead.etapa === args.p_etapa)
      && (!args.p_analista_id || fila.lead.analista_id === args.p_analista_id)), ...deClientes]
    const filtradas = args.p_senal === 'todas' ? ambito : ambito.filter((fila) => fila.senales[args.p_senal as keyof typeof fila.senales])
    const inicio = args.p_cursor?.inicio ?? 0
    const items = filtradas.slice(inicio, inicio + args.p_limite)
    const hayMas = inicio + items.length < filtradas.length
    const totales = { ...Object.fromEntries(Object.keys(filas[0]!.senales).map((senal) => [senal,
      ambito.filter((fila) => fila.senales[senal as keyof typeof fila.senales]).length])), clientes: deClientes.length }
    await route.fulfill({ json: aColaV3({ ...muestraSql.cola, calculado_en: calculado, limite: args.p_limite,
      // La RPC aplica DEFAULT NULL a argumentos omitidos y devuelve ambas claves.
      filtros: { senal: args.p_senal, etapa: args.p_etapa ?? null, analista_id: args.p_analista_id ?? null },
      total_items: filtradas.length, rango: { desde: items.length ? inicio + 1 : 0, hasta: inicio + items.length },
      hay_mas: hayMas, cursor_siguiente: hayMas ? { inicio: inicio + items.length } : null,
      totales, items,
    }) })
  })
  return { pedidos, analistaUno, analistaDos, analistaAjeno }
}

export type PedidoColaDia = PedidoCola & { p_cursor: Record<string, unknown> | null }

/** Próxima medianoche de Lima (UTC−5, sin horario de verano) desde un instante. */
export function finDelDiaLima(desde: number): number {
  const d = new Date(desde - 5 * 3_600_000)
  d.setUTCHours(24, 0, 0, 0)
  return d.getTime() + 5 * 3_600_000
}

/**
 * Cola del DÍA v3 (`cola_accion_v3_fn`) y día del analista para la sesión real
 * del vendedor `UID`. Los leads salen de la plantilla REAL capturada en el banco
 * (`sla-operacion-cola-v3-sql.test.fixture.json`) y las tareas de CLIENTES se
 * calculan en cada lectura desde `backend.tareas` con la regla del servidor
 * (pendientes y activas del analista, vencidas o de hoy en Lima): si la UI
 * cierra una con `cerrar_tarea`, la siguiente lectura ya no la trae. La
 * respuesta hace ECO de los argumentos. No acredita RLS: eso lo hace el banco.
 */
export async function montarColaDiaV3(page: Page, backend: BackendReal, leadsVencidos: { id: string; nombre_completo: string; etapa: string }[]) {
  const pedidos: PedidoColaDia[] = []
  const plantillaLead = muestraV3.items.find((i) => i.lead_id !== null)!
  await page.route('**/rest/v1/rpc/cola_accion_v3_fn', async (route) => {
    const args = route.request().postDataJSON() as PedidoColaDia
    pedidos.push(args)
    const ahora = Date.now()
    const fin = finDelDiaLima(ahora)
    const leads = leadsVencidos.map((l, i) => ({ ...plantillaLead, lead_id: l.id, clave: `lead:${l.id}`,
      sujeto: { tipo: 'lead', id: l.id, nombre: l.nombre_completo },
      referencia_en: new Date(ahora - (i + 30) * 3_600_000).toISOString(),
      lead: { ...plantillaLead.lead, id: l.id, nombre_completo: l.nombre_completo, etapa: l.etapa, analista_id: UID },
      estado: { ...plantillaLead.estado, lead_id: l.id } }))
    const clientes = backend.tareas
      .filter((t) => t.lead_id == null && (t.perfil_id != null || t.inversionista_id != null) && t.estado === 'pendiente'
        && t.activo !== false && t.vendedor_id === UID && Date.parse(String(t.vence_en)) < fin)
      .sort((a, b) => String(a.vence_en).localeCompare(String(b.vence_en)))
      .map((t) => {
        const vencida = Date.parse(String(t.vence_en)) <= ahora
        return { clave: `tarea:${String(t.id)}`, tarea_id: t.id, lead_id: null, lead: null, estado: null,
          bucket: vencida ? 'tarea_vencida' : 'tarea_hoy', severidad: vencida ? 'critica' : 'media', prioridad: vencida ? 20 : 30,
          referencia_en: t.vence_en,
          senales: { pendientes: vencida, tareas_vencidas: vencida, primera_atencion: false, seguimientos_pendientes: false,
            revisiones: false, datos_incompletos: false, por_repartir: false },
          sujeto: { tipo: 'cliente', perfil_id: t.perfil_id ?? null, inversionista_id: t.inversionista_id ?? null, nombre: String(t['nombre_cliente'] ?? 'CLIENTE') } }
      })
    const items = [...leads, ...clientes].slice(0, args.p_limite)
    await route.fulfill({ json: { ...muestraV3, calculado_en: new Date(ahora).toISOString(), proximo_cambio_en: null,
      filtros: { senal: args.p_senal, etapa: args.p_etapa ?? null, analista_id: args.p_analista_id ?? null }, limite: args.p_limite,
      total_items: items.length, rango: { desde: items.length ? 1 : 0, hasta: items.length }, hay_mas: false, cursor_siguiente: null,
      totales: { ...muestraV3.totales, clientes: clientes.length, tareas_vencidas: items.filter((i) => i.senales.tareas_vencidas).length },
      items } })
  })
  await page.route('**/rest/v1/rpc/gestion_diaria_analista_fn', async (route) => {
    const ahora = Date.now()
    const dia = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Lima' }).format(new Date(ahora))
    await route.fulfill({ json: { version: 1, generado_en: new Date(ahora).toISOString(), dia, zona: 'America/Lima', analista_id: UID,
      umbrales: { version: 1, bien_min_pct: 45, atencion_min_pct: 25, minimo_llamadas_utiles: 5 }, sin_conversacion_dias: 7,
      marcador: { llamadas: 0, contestadas: 0, utiles: 0, tasa_contacto_pct: null, nivel: null, leads_tocados: 0, citas_agendadas: 0,
        primera_llamada_en: null, ultima_llamada_en: null, por_resultado: {}, por_hora: [] },
      compromisos: [], compromisos_total: 0, cartera: [], cartera_truncada: false, descartados: [] } })
  })
  return { pedidos }
}
