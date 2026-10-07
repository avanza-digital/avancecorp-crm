// Contrato del registro crudo: forma de la página (fail-closed), pestañas →
// tipos, sonda de «hay más», cursor keyset y el espejo demo con el MISMO orden
// que el servidor (creado_en desc, id asc). Lo que se protege es que la pantalla
// no distinga demo de real y que un payload fuera de contrato no se pinte.
import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import {
  RegistroPaginaSchema, cursorSiguiente, filasCsvRegistro, horaDeItem, limiteConSonda, paginaVisible,
  registroDesdeDemo, tiposDePestana, tonoDeTipo, type RegistroItem,
} from './gestion-diaria'
import type { Actividad, Miembro } from './tipos'

const item = (n: number, extra: Partial<RegistroItem> = {}): RegistroItem => ({
  id: `a${n}`, lead_id: 'l1', lead_nombre: 'LEAD UNO', lead_etapa: 'contactado', etapa_en_ese_momento: 'nuevo',
  tipo: 'llamada_realizada', detalle: 'Contestó, volver a llamar', metadata: {}, creado_por: 'u1', autor_nombre: 'ANALISTA UNO',
  creado_en: `2026-09-19T15:${String(n).padStart(2, '0')}:00.000Z`, ...extra,
})

describe('pestañas → tipos', () => {
  it('llamadas acota a los dos tipos de llamada; todo no manda filtro', () => {
    expect(tiposDePestana('llamadas')).toEqual(['llamada_realizada', 'llamada_no_contestada'])
    expect(tiposDePestana('whatsapp')).toEqual(['whatsapp_enviado', 'whatsapp_recibido'])
    expect(tiposDePestana('notas')).toEqual(['nota'])
    expect(tiposDePestana('todo')).toBeNull()
  })
  it('el tono acompaña al texto: contestó = ok, no contestó = atención, lo demás neutro', () => {
    expect(tonoDeTipo('llamada_realizada')).toBe('ok')
    expect(tonoDeTipo('llamada_no_contestada')).toBe('atencion')
    expect(tonoDeTipo('nota')).toBe('neutro')
  })
})

describe('contrato de la página', () => {
  const pagina = { version: 1, generado_en: '2026-09-19T18:00:00Z', desde: '2026-09-19', hasta: '2026-09-19', zona: 'America/Lima', limite: 26, items: [item(1)] }
  it('acepta la forma del servidor y tolera metadata con claves futuras', () => {
    const r = v.safeParse(RegistroPaginaSchema, { ...pagina, items: [item(1, { metadata: { evento: 'resultado_llamada', resultado: 'volver_a_llamar' } })] })
    expect(r.success).toBe(true)
  })
  it.each([
    ['sin zona Lima', { ...pagina, zona: 'UTC' }],
    ['versión desconocida', { ...pagina, version: 99 }],
    ['tipo fuera del catálogo', { ...pagina, items: [item(1, { tipo: 'fax' as never })] }],
    ['sin autor', { ...pagina, items: [{ ...item(1), autor_nombre: undefined }] }],
  ])('rechaza %s', (_n, payload) => {
    expect(v.safeParse(RegistroPaginaSchema, payload).success).toBe(false)
  })
})

describe('sonda y cursor', () => {
  it('pide limite+1 y recorta: 26 filas con límite 25 = hay más; 25 = no', () => {
    expect(limiteConSonda(25)).toBe(26)
    const veintiseis = Array.from({ length: 26 }, (_, i) => item(i))
    expect(paginaVisible(veintiseis, 25)).toMatchObject({ hayMas: true })
    expect(paginaVisible(veintiseis, 25).items).toHaveLength(25)
    expect(paginaVisible(veintiseis.slice(0, 25), 25).hayMas).toBe(false)
  })
  it('el cursor es la última fila visible (creado_en + id); sin filas no hay cursor', () => {
    expect(cursorSiguiente([item(3), item(2)])).toEqual({ antes_de: item(2).creado_en, antes_id: 'a2' })
    expect(cursorSiguiente([])).toBeNull()
  })
  it('la hora se pinta en Lima', () => {
    expect(horaDeItem({ creado_en: '2026-09-19T15:07:00.000Z' })).toBe('10:07')
    expect(horaDeItem({ creado_en: 'no-es-fecha' })).toBe('—')
  })
})

describe('espejo demo', () => {
  const equipo: Miembro[] = [
    { perfil_id: 'd-v1', nombre_completo: 'ANALISTA UNO', rol_crm: 'vendedor', supervisor_id: 'd-s1', activo: true },
    { perfil_id: 'd-v2', nombre_completo: 'ANALISTA DOS', rol_crm: 'vendedor', supervisor_id: 'd-s1', activo: true },
  ]
  const leads = new Map([
    ['l1', { nombre_completo: 'LEAD UNO', etapa: 'contactado', activo: true }],
    ['l2', { nombre_completo: 'LEAD DOS', etapa: 'nuevo', activo: true }],
    ['l3', { nombre_completo: 'LEAD BORRADO', etapa: 'nuevo', activo: false }],
  ])
  const acts: Actividad[] = [
    { id: 'x1', lead_id: 'l1', tipo: 'llamada_realizada', detalle: 'ok', autor_nombre: 'ANALISTA UNO', creado_en: '2026-09-19T14:00:00.000Z' },
    { id: 'x2', lead_id: 'l2', tipo: 'llamada_no_contestada', detalle: null, autor_nombre: 'ANALISTA DOS', creado_en: '2026-09-19T16:00:00.000Z' },
    { id: 'x0', lead_id: 'l1', tipo: 'nota', detalle: 'nota', autor_nombre: 'ANALISTA UNO', creado_en: '2026-09-19T16:00:00.000Z' },
    { id: 'x3', lead_id: 'l3', tipo: 'llamada_realizada', detalle: 'lead borrado', autor_nombre: 'ANALISTA UNO', creado_en: '2026-09-19T17:00:00.000Z' },
    { id: 'x4', lead_id: 'l1', tipo: 'llamada_realizada', detalle: 'ayer', autor_nombre: 'ANALISTA UNO', creado_en: '2026-09-18T17:00:00.000Z' },
  ]
  it('acota al día Lima, a la pestaña, al analista y a leads activos; ordena creado_en desc, id asc', () => {
    const todo = registroDesdeDemo(acts, leads, equipo, { dia: '2026-09-19', analistaIds: null, pestana: 'todo', etapa: null }, null, 26)
    expect(todo.items.map((i) => i.id)).toEqual(['x0', 'x2', 'x1'])
    const llamadas = registroDesdeDemo(acts, leads, equipo, { dia: '2026-09-19', analistaIds: ['d-v1'], pestana: 'llamadas', etapa: null }, null, 26)
    expect(llamadas.items.map((i) => i.id)).toEqual(['x1'])
    expect(llamadas.items[0]?.creado_por).toBe('d-v1')
    const nuevos = registroDesdeDemo(acts, leads, equipo, { dia: '2026-09-19', analistaIds: null, pestana: 'todo', etapa: 'nuevo' }, null, 26)
    expect(nuevos.items.map((i) => i.id)).toEqual(['x2'])
  })
  it('respeta el cursor y la sonda como el servidor', () => {
    const primera = registroDesdeDemo(acts, leads, equipo, { dia: '2026-09-19', analistaIds: null, pestana: 'todo', etapa: null }, null, 2)
    expect(primera.items.map((i) => i.id)).toEqual(['x0', 'x2'])
    const segunda = registroDesdeDemo(acts, leads, equipo, { dia: '2026-09-19', analistaIds: null, pestana: 'todo', etapa: null }, cursorSiguiente(primera.items), 2)
    expect(segunda.items.map((i) => i.id)).toEqual(['x1'])
  })
})

describe('CSV', () => {
  it('lleva el texto íntegro y el resultado tipificado cuando existe', () => {
    const { cabecera, filas } = filasCsvRegistro([item(1, { metadata: { resultado: 'volver_a_llamar' } }), item(2, { detalle: null })])
    expect(cabecera).toContain('Detalle')
    expect(filas[0]).toEqual(['2026-09-19', '10:01', 'ANALISTA UNO', 'LEAD UNO', 'Leads', 'Nuevo', 'Contactado', 'Contestó', 'Contestó, volver a llamar', 'volver_a_llamar'])
    expect(filas[1]?.[9]).toBeNull()
    expect(filas[1]?.[8]).toBeNull()
  })
})
