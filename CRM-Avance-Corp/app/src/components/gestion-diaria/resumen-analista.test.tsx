// El resumen del analista en el panel del supervisor (diseño 27/09/2026): el
// aviso de lo vencido lleva a Pendientes, los 4 cuadros (Pendientes en lugar de
// WhatsApp), «Sin muestra» dicho con útiles y mínimo, el desglose por hora solo
// si se confirma y lo que el diseño no dibuja, conservado.
import { describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, within } from '@testing-library/react'
import { ResumenAnalista } from './resumen-analista'
import { filaEquipoPrueba } from '@/lib/gestion-diaria-equipo.fixture'
import type { FilaEquipoPresentada } from '@/lib/gestion-diaria-equipo'

const AHORA = Date.parse('2026-09-21T21:30:00Z')
const fila = (cambios: Parameters<typeof filaEquipoPrueba>[0] = {}) => filaEquipoPrueba(cambios) as FilaEquipoPresentada
const conLlamadas = fila({
  nombre_completo: 'KAREN DÍAZ', tareas_pendientes: 5, tareas_vencidas: 4, requiere_atencion: true,
  motivos_atencion: ['tarea_vencida', 'sin_llamar_2h'], llamadas_por_lead: 1.5, citas_hoy: 2,
  marcador: { ...filaEquipoPrueba().marcador, llamadas: 12, utiles: 11, contestadas: 2, tasa_contacto_pct: 18, nivel: 'bajo',
    leads_tocados: 8, citas_agendadas: 1, primera_llamada_en: '2026-09-21T13:10:00Z', ultima_llamada_en: '2026-09-21T21:05:00Z',
    por_hora: [{ hora: 9, llamadas: 5, contestadas: 1 }, { hora: 16, llamadas: 7, contestadas: 1 }] },
})

function montar(f: FilaEquipoPresentada, esHoy = true) {
  const abrirLlamadas = vi.fn()
  const abrirPendientes = vi.fn()
  render(<ResumenAnalista fila={f} dia="2026-09-21" minimo={5} esHoy={esHoy} ahora={AHORA} abrirLlamadas={abrirLlamadas} abrirPendientes={abrirPendientes} />)
  return { abrirLlamadas, abrirPendientes }
}

describe('ResumenAnalista', () => {
  it('el aviso de vencidas abre Pendientes SOLO vencidas y los demás motivos se dicen aparte', () => {
    const { abrirPendientes } = montar(conLlamadas)
    fireEvent.click(screen.getByRole('button', { name: '4 tareas vencidas' }))
    expect(abrirPendientes).toHaveBeenCalledWith(true)
    expect(within(screen.getByRole('list', { name: 'Otros motivos de atención' })).getByText('Más de 2 h sin llamar en la jornada')).toBeInTheDocument()
  })
  it('los 4 cuadros: Llamadas, Contacto, Citas agendadas y Pendientes (no WhatsApp), con sus accesos', () => {
    const { abrirLlamadas, abrirPendientes } = montar(conLlamadas)
    const terminos = screen.getAllByRole('term').slice(0, 4).map((t) => t.textContent)
    expect(terminos).toEqual(['Llamadas', 'Contacto', 'Citas agendadas', 'Pendientes'])
    expect(screen.queryByText('WhatsApp')).not.toBeInTheDocument()
    expect(screen.getByText('18 %')).toBeInTheDocument()
    expect(screen.getByText('Bajo')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Ver llamadas del día de KAREN DÍAZ' }))
    expect(abrirLlamadas).toHaveBeenCalledTimes(1)
    fireEvent.click(screen.getByRole('button', { name: 'Ver pendientes de KAREN DÍAZ' }))
    expect(abrirPendientes).toHaveBeenCalledWith(false)
  })
  it('sin muestra suficiente lo dice con útiles y mínimo, nunca como una tasa evaluada', () => {
    montar(fila({ marcador: { ...filaEquipoPrueba().marcador, llamadas: 3, utiles: 3, contestadas: 2, tasa_contacto_pct: 67, nivel: null } }))
    expect(screen.getByText('Sin muestra suficiente · 3 útiles · mínimo 5')).toBeInTheDocument()
    expect(screen.queryByText('67 %')).not.toBeInTheDocument()
  })
  it('las barras llevan «hace X» solo hoy; en otra fecha, solo la hora', () => {
    montar(conLlamadas)
    expect(screen.getByText('Última llamada 16:05 · hace 25 min')).toBeInTheDocument()
  })
  it('en una fecha pasada no dice «hace»', () => {
    montar(conLlamadas, false)
    expect(screen.getByText('Última llamada 16:05')).toBeInTheDocument()
  })
  it('un desglose por hora que no cuadra NO se dibuja con ceros', () => {
    montar(fila({ marcador: { ...conLlamadas.marcador, por_hora: [{ hora: 9, llamadas: 1, contestadas: 0 }] } }))
    expect(screen.getByRole('status')).toHaveTextContent('No se pudo confirmar el desglose por hora')
  })
  it('sin llamadas no pinta barras vacías y no lo presenta como ausencia', () => {
    montar(fila())
    expect(screen.getByText('No hay llamadas registradas ese día. Esto no indica ausencia ni descarta otras gestiones.')).toBeInTheDocument()
  })
  it('conserva lo que el diseño no dibuja: leads distintos, llamadas por lead, primera llamada y citas del día', () => {
    montar(conLlamadas)
    const datos = screen.getByLabelText('Más datos del día')
    for (const [titulo, valor] of [['Leads distintos', '8'], ['Llamadas por lead', '1.5'], ['Primera llamada', '08:10'], ['Citas pendientes del día', '2']] as const) {
      const termino = within(datos).getByText(titulo)
      expect(termino.nextElementSibling).toHaveTextContent(valor)
    }
  })
  it('dice el día consultado y el total de gestiones de la foto (Codex, 27/09)', () => {
    montar(fila({ gestiones_hoy: 7 }))
    expect(screen.getByText('7 gestiones · 21 de setiembre de 2026 · Lima')).toBeInTheDocument()
  })
  it('sin número confirmado, «Tareas vencidas» sigue dicho entre los motivos', () => {
    montar(fila({ tareas_vencidas: 0, requiere_atencion: true, motivos_atencion: ['tarea_vencida'] }))
    expect(within(screen.getByRole('list', { name: 'Otros motivos de atención' })).getByText('Tareas vencidas')).toBeInTheDocument()
  })
})

describe('G4b: «Citas agendadas» abre su lista', () => {
  it('con abrirCitas, el cuadro lleva «Ver citas»; sin él, no ofrece un enlace muerto', () => {
    const abrirCitas = vi.fn()
    const { unmount } = render(<ResumenAnalista fila={conLlamadas} dia="2026-09-21" minimo={5} esHoy ahora={AHORA} abrirLlamadas={vi.fn()} abrirCitas={abrirCitas} />)
    fireEvent.click(screen.getByRole('button', { name: 'Ver citas agendadas de KAREN DÍAZ' }))
    expect(abrirCitas).toHaveBeenCalledOnce()
    unmount()
    montar(conLlamadas)
    expect(screen.queryByRole('button', { name: /^Ver citas/ })).not.toBeInTheDocument()
  })
})
