import type { Page } from '@playwright/test'
import { leadReal, montarBackendReal, UID } from './_helpers'
import muestraSql from '../src/data/sla-operacion-sql.test.fixture.json' with { type: 'json' }

export type PedidoCola = {
  p_cursor: { inicio: number } | null
  p_limite: number
  p_senal: string
  p_etapa?: string
  p_analista_id?: string
}

export async function montarColaEquipo(page: Page, rolCrm: 'gerencia' | 'supervisor' | 'vendedor', cantidad = 14) {
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
  await page.route('**/rest/v1/rpc/cola_accion_v2_fn', async (route) => {
    const args = route.request().postDataJSON() as PedidoCola
    pedidos.push(args)
    const ambito = filas.filter((fila) => (!args.p_etapa || fila.lead.etapa === args.p_etapa)
      && (!args.p_analista_id || fila.lead.analista_id === args.p_analista_id))
    const filtradas = args.p_senal === 'todas' ? ambito : ambito.filter((fila) => fila.senales[args.p_senal as keyof typeof fila.senales])
    const inicio = args.p_cursor?.inicio ?? 0
    const items = filtradas.slice(inicio, inicio + args.p_limite)
    const hayMas = inicio + items.length < filtradas.length
    const totales = Object.fromEntries(Object.keys(filas[0]!.senales).map((senal) => [senal,
      ambito.filter((fila) => fila.senales[senal as keyof typeof fila.senales]).length]))
    await route.fulfill({ json: { ...muestraSql.cola, calculado_en: calculado, limite: args.p_limite,
      // La RPC aplica DEFAULT NULL a argumentos omitidos y devuelve ambas claves.
      filtros: { senal: args.p_senal, etapa: args.p_etapa ?? null, analista_id: args.p_analista_id ?? null },
      total_items: filtradas.length, rango: { desde: items.length ? inicio + 1 : 0, hasta: inicio + items.length },
      hay_mas: hayMas, cursor_siguiente: hayMas ? { inicio: inicio + items.length } : null,
      totales, items,
    } })
  })
  return { pedidos, analistaUno, analistaDos, analistaAjeno }
}
