import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import { RegistroPaginaV2Schema, cursorSiguiente, etiquetaGestion, filasCsvRegistro, registroCoherente, type RegistroItem } from './gestion-diaria'
import { ResumenGestionesSchema, CitasClientesSchema, citasClientesCoherentes, type CitasClientes } from './gestiones-clientes'
import { IdentidadClienteSchema } from './sujeto-gestion'
const persona = '22222222-2222-4222-8222-222222222222'
const autor = '11111111-1111-4111-8111-111111111111'
const t = '2026-10-05T15:00:00.000001Z'
const identidad = { sujeto_tipo: 'inversionista' as const, sujeto_id: persona, sujeto_nombre: 'Cliente de prueba', inversionista_id: persona, perfil_id: null, identidad_visible: true }
const item: RegistroItem = { ...identidad, id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', origen: 'postventa', lead_id: null, lead_nombre: null, lead_etapa: null,
  etapa_en_ese_momento: null, tipo: 'reunion_realizada', detalle: 'Asistió y recibió la propuesta.', metadata: { resultado_reunion: 'propuesta', estado: 'completada' },
  creado_por: autor, autor_nombre: 'Analista', creado_en: t }
const pagina = { version: 2 as const, generado_en: t, desde: '2026-10-05', hasta: '2026-10-05', zona: 'America/Lima' as const, limite: 26, items: [item] }
const filtros = { dia: pagina.desde, analistaIds: null, pestana: 'todo' as const, etapa: null }
const cero = { gestiones: 0, llamadas: 0, contestadas: 0, entrevistas: 0, ultima_llamada_en: null }
const clientes = { ...cero, gestiones: 3, llamadas: 2, contestadas: 1, entrevistas: 1, ultima_llamada_en: t }
const desglose = { leads: cero, clientes, total: clientes }
const resumen = { version: 1, desde: pagina.desde, hasta: pagina.hasta, zona: 'America/Lima', generado_en: t, totales: desglose, analistas: [{ id: autor, nombre: 'Analista', metricas: desglose }] }

describe('Gestiones de clientes: identidad, resultado y conteos', () => {
  it('acepta un cliente sin lead y exporta autor y resultado comercial íntegro', () => {
    expect(v.safeParse(RegistroPaginaV2Schema, pagina).success).toBe(true)
    expect(filasCsvRegistro([item]).filas[0]).toEqual(['2026-10-05', '10:00', 'Analista', 'Cliente de prueba', 'Clientes', null, null, 'Entrevista realizada', 'Asistió y recibió la propuesta.', 'propuesta'])
  })
  it('rechaza un cliente presentado como lead y una identidad oculta que conserva un enlace', () => {
    expect(v.safeParse(RegistroPaginaV2Schema, { ...pagina, items: [{ ...item, lead_id: persona }] }).success).toBe(false)
    expect(v.safeParse(IdentidadClienteSchema, { ...identidad, identidad_visible: false }).success).toBe(false)
    expect(v.safeParse(RegistroPaginaV2Schema, { ...pagina, items: [{ ...item, sujeto_id: null, inversionista_id: null, identidad_visible: false }] }).success).toBe(false)
  })
  it('una fila redactada conserva el resultado, sin identidad ni detalle privado', () => {
    const redactada = { ...item, sujeto_id: null, inversionista_id: null, sujeto_nombre: 'Cliente fuera de tu cartera', identidad_visible: false, detalle: null }
    expect(v.safeParse(RegistroPaginaV2Schema, { ...pagina, items: [redactada] }).success).toBe(true)
    expect(v.safeParse(RegistroPaginaV2Schema, { ...pagina, items: [{ ...redactada, metadata: { tarea_id: persona } }] }).success).toBe(false)
  })
  it('un cierre histórico sin resultado no dice que contestó', () => {
    expect(etiquetaGestion({ ...item, tipo: 'llamada_realizada', metadata: { resultado: 'sin_resultado' } })).toBe('Llamada sin resultado')
    expect(etiquetaGestion({ ...item, tipo: 'nota', metadata: { estado: 'no_show' } })).toBe('No asistió')
  })
  it('no admite totales incompletos o inconsistentes con sus autores', () => {
    expect(v.safeParse(ResumenGestionesSchema, resumen).success).toBe(true)
    expect(v.safeParse(ResumenGestionesSchema, { ...resumen, totales: { total: clientes } }).success).toBe(false)
    expect(v.safeParse(ResumenGestionesSchema, { ...resumen, analistas: [] }).success).toBe(false)
    expect(v.safeParse(ResumenGestionesSchema, { ...resumen, totales: { ...desglose, total: { ...clientes, contestadas: 3 } } }).success).toBe(false)
  })
  it('el cursor separa dos fuentes con el mismo uuid y timestamp, conservando microsegundos', () => {
    const perfil = { ...item, origen: 'perfil' as const }
    expect(cursorSiguiente([perfil])).toMatchObject({ antes_origen: 'perfil', antes_de: t, antes_id: item.id })
    expect(registroCoherente(pagina, filtros, cursorSiguiente([perfil]), 26)).toBe(true)
    expect(registroCoherente(pagina, filtros, cursorSiguiente([item]), 26)).toBe(false)
    expect(registroCoherente({ ...pagina, items: [item, { ...item, creado_en: '2026-10-05T15:00:00.000002Z' }] }, filtros, null, 26)).toBe(false)
  })
  it('respeta filtros de cartera, autor y la medianoche de Lima', () => {
    expect(registroCoherente(pagina, { ...filtros, cartera: 'leads' }, null, 26)).toBe(false)
    expect(registroCoherente(pagina, { ...filtros, cartera: 'clientes' }, null, 26)).toBe(true)
    expect(registroCoherente(pagina, { ...filtros, analistaIds: [persona] }, null, 26)).toBe(false)
    expect(registroCoherente({ ...pagina, items: [{ ...item, creado_en: '2026-10-06T04:59:59.999999Z' }] }, filtros, null, 26)).toBe(true)
    expect(registroCoherente({ ...pagina, items: [{ ...item, creado_en: '2026-10-06T05:00:00Z' }] }, filtros, null, 26)).toBe(false)
  })
})

it('Citas rechaza un total falso, una cita fuera del mes o un cursor que salta filas', () => {
  const citas: CitasClientes = { version: 1, desde: '2026-10-01', hasta: '2026-10-31', generado_en: t, limite: 25,
    resumen: { total: 1, pendientes: 0, entrevistas: 1, no_asistio: 0, reprogramadas: 0, canceladas: 0 }, hay_mas: false, siguiente_cursor: null,
    items: [{ ...identidad, id: item.id, vence_en: t, estado: 'completada', confirmada_en: null, resultado_reunion: 'propuesta', vendedor_id: autor, vendedor_nombre: 'Analista' }] }
  const valida = (p: CitasClientes) => citasClientesCoherentes(p, citas.desde, citas.hasta, [autor], null)
  expect(valida(citas)).toBe(true)
  expect(valida({ ...citas, resumen: { ...citas.resumen, total: 2 } })).toBe(false)
  expect(valida({ ...citas, items: [{ ...citas.items[0]!, vence_en: '2026-11-01T05:00:00Z' }] })).toBe(false)
  expect(valida({ ...citas, items: [{ ...citas.items[0]!, vendedor_id: persona }] })).toBe(false)
  const sinResponsable = { ...citas, items: [{ ...citas.items[0]!, vendedor_id: null, vendedor_nombre: 'Sin responsable' }] }
  expect(v.safeParse(CitasClientesSchema, sinResponsable).success).toBe(true)
  expect(citasClientesCoherentes(sinResponsable, citas.desde, citas.hasta, null, null)).toBe(true)
  expect(valida(sinResponsable)).toBe(false)
  expect(valida({ ...citas, hay_mas: true, siguiente_cursor: { despues_de: t, despues_id: persona } })).toBe(false)
})
