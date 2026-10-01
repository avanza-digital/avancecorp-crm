// Cola de hoy · potencial del lead. Solo las filas de LEAD llevan marca: las de
// cliente no tienen `lead_id`. El hook de datos se sustituye: se prueba lo que
// la cola PINTA con la bandera apagada, encendida sin marcas y con marcas.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, within } from '@testing-library/react'
import type { FilaDiaria } from '@/lib/gestion-diaria-analista'
import type { PotencialLead } from '@/lib/potencial'

let POTENCIAL: { habilitada: boolean; porLead: Map<string, PotencialLead> } = { habilitada: false, porLead: new Map() }
const PEDIDOS: string[][] = []
vi.mock('@/data/potencial-queries', () => ({
  usePotencialLeads: (ids: readonly string[]) => { PEDIDOS.push([...ids]); return POTENCIAL },
}))

const { ColaDeHoy } = await import('./cola-de-hoy')

const ESTRELLA = '11111111-1111-4111-8111-111111111111'
const SIN_MARCA = '22222222-2222-4222-8222-222222222222'
const TAREA = '33333333-3333-4333-8333-333333333333'
const AHORA = Date.parse('2026-10-01T15:00:00Z')

function filaLead(leadId: string, nombre: string): FilaDiaria {
  return {
    tipo: 'lead', clave: `lead:${leadId}`, lead_id: leadId, nombre_completo: nombre, grupo: 'primera_atencion',
    referencia_en: '2026-10-01T16:00:00Z', severidad: 'media', etapa: 'nuevo', tarea_id: null, senal: null,
  }
}
const FILA_CLIENTE: FilaDiaria = {
  tipo: 'cliente', clave: `tarea:${TAREA}`, lead_id: null, nombre_completo: 'CLIENTE DE CARTERA', grupo: 'tarea_hoy',
  referencia_en: '2026-10-01T18:00:00Z', severidad: 'baja', etapa: null, tarea_id: TAREA, senal: null,
  perfil_id: null, inversionista_id: null,
}
const FILAS = [filaLead(ESTRELLA, 'GLORIA NAVARRO'), filaLead(SIN_MARCA, 'ROSA QUISPE'), FILA_CLIENTE]

function marca(leadId: string, nivel: PotencialLead['nivel']): PotencialLead {
  return {
    lead_id: leadId, nivel, origen: nivel ? 'manual' : null, nivel_marcado: nivel, marcado_en: nivel ? '2026-09-29T15:00:00Z' : null,
    dias_sin_gestion: nivel ? 1 : null, baja_a: null, baja_el: null, puede_marcar: true,
  }
}

const onElegir = vi.fn()
function montar(elegido: string | null = null) {
  render(
    <ColaDeHoy
      idBase="gd" filtro="todo" onFiltro={() => {}} pagina={0} onPagina={() => {}} elegido={elegido} onElegir={onElegir}
      ahora={AHORA} cargando={false} colaCaida={false} sinConversacionDias={7}
      pestanas={[
        { clave: 'primera_atencion', etiqueta: 'Sin primer intento', ayuda: '', total: 2, filas: FILAS.slice(0, 2) },
        { clave: 'tarea_vencida', etiqueta: 'Vencidas', ayuda: '', total: 0, filas: [] },
        { clave: 'tarea_hoy', etiqueta: 'Hoy', ayuda: '', total: 1, filas: [FILA_CLIENTE] },
        { clave: 'sin_conversacion', etiqueta: 'Sin conversación', ayuda: '', total: 0, filas: [] },
      ]}
    />,
  )
}
const filaDe = (nombre: string): HTMLElement => {
  const boton = screen.getByText(nombre).closest('button')
  if (!boton) throw new Error(`Sin fila para ${nombre}`)
  return boton
}

beforeEach(() => { PEDIDOS.length = 0; onElegir.mockClear() })

describe('Cola de hoy · potencial del lead', () => {
  it('ESTADO DE PRODUCCIÓN (potencial apagado): las filas se ven igual que antes', () => {
    POTENCIAL = { habilitada: false, porLead: new Map() }
    montar()
    expect(screen.getAllByRole('listitem')).toHaveLength(3)
    expect(screen.queryByTitle(/^Potencial:/)).not.toBeInTheDocument()
    expect(document.querySelector('[data-potencial]')).toBeNull()
  })

  it('ESTADO DE PRODUCCIÓN (encendido, ningún lead marcado): sin chips ni franjas', () => {
    POTENCIAL = { habilitada: true, porLead: new Map([[ESTRELLA, marca(ESTRELLA, null)], [SIN_MARCA, marca(SIN_MARCA, null)]]) }
    montar()
    expect(screen.queryByTitle(/^Potencial:/)).not.toBeInTheDocument()
    expect(document.querySelector('[data-potencial]')).toBeNull()
  })

  it('pregunta solo por las filas de lead: las de cliente no llevan potencial', () => {
    POTENCIAL = { habilitada: false, porLead: new Map() }
    montar()
    expect(PEDIDOS.at(-1)).toEqual([ESTRELLA, SIN_MARCA])
  })

  it('con marca: chip junto al nombre y franja en la fila; las demás quedan limpias', () => {
    POTENCIAL = { habilitada: true, porLead: new Map([[ESTRELLA, marca(ESTRELLA, 'estrella')], [SIN_MARCA, marca(SIN_MARCA, null)]]) }
    montar()
    const estrella = filaDe('GLORIA NAVARRO')
    expect(estrella).toHaveAttribute('data-potencial', 'estrella')
    const chip = within(estrella).getByTitle('Potencial: Estrella')
    expect(chip.previousElementSibling).toHaveTextContent('GLORIA NAVARRO')
    expect(filaDe('ROSA QUISPE')).not.toHaveAttribute('data-potencial')
    expect(filaDe('CLIENTE DE CARTERA')).not.toHaveAttribute('data-potencial')
  })

  it('la fila con marca sigue siendo el mismo botón: elegirla y `aria-current` no cambian', () => {
    POTENCIAL = { habilitada: true, porLead: new Map([[ESTRELLA, marca(ESTRELLA, 'estrella')]]) }
    montar(`lead:${ESTRELLA}`)
    const estrella = filaDe('GLORIA NAVARRO')
    expect(estrella).toHaveAttribute('aria-current', 'true')
    fireEvent.click(estrella)
    expect(onElegir).toHaveBeenCalledWith(FILAS[0])
    // El foco dorado sigue al cursor sin tocar React.
    vi.spyOn(estrella, 'getBoundingClientRect').mockReturnValue({ left: 0, top: 0, width: 400, height: 62 } as DOMRect)
    fireEvent.pointerMove(estrella, { clientX: 80, clientY: 30 })
    expect(estrella.style.getPropertyValue('--pot-mx')).toBe('80px')
  })
})
