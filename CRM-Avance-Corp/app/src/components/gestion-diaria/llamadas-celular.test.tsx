// La pestaña «Llamadas del celular» (F4-b): qué muestra de cada llamada y qué avisa al elegir. Presentacional: los
// datos y las acciones son dobles; la búsqueda de «Elegir el lead» es la real del receptor, en modo demo.
import { describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import type { FilaBandeja, ResueltaHoy } from '@/lib/llamadas-celular'
import type { Lead } from '@/lib/tipos'
import { LlamadasCelular, type LlamadasCelularProps } from './llamadas-celular'

const AHORA = Date.parse('2026-10-05T15:58:00Z') // 10:58 en Lima
const fila = (id: string, extra: Partial<FilaBandeja> = {}): FilaBandeja => ({
  evento_id: id, evento_origen_id: 'C1-1791226920', recibido_en: '2026-10-05T15:42:11Z', ocurrio_en: '2026-10-05T15:42:00Z',
  numero: '+51987654322', direccion: 'saliente', estado_tecnico: 'conectada', duracion_seg: 95, identificacion: 'identificado',
  atencion: 'requiere_resultado', lead_id: 'l2', lead_nombre: 'MARÍA LÓPEZ CASTRO', analista_id: 'a1', es_propia: true, ...extra,
})
const resuelta: ResueltaHoy = {
  evento_id: 'r1', resuelto_en: '2026-10-05T14:04:00Z', recibido_en: '2026-10-05T14:00:11Z', ocurrio_en: '2026-10-05T14:00:00Z', numero: '+51911223344',
  atencion: 'registrado', lead_id: 'l15', lead_nombre: 'TERESA GONZALES PAZ', analista_id: 'a1', es_propia: true, etiqueta: 'C1',
  actividad_id: 'act', resultado: 'agendo_reunion', deshecho: false, via: 'al_colgar', motivo_descarte: null, motivo_descarte_detalle: null,
}
const LEAD_DEMO = { id: 'l7', nombre_completo: 'LUIS TORRES', telefono: '+51987654330', telefono_alternativo: null, etapa: 'nuevo', activo: true } as unknown as Lead

function montar(extra: Partial<LlamadasCelularProps> = {}) {
  const props: LlamadasCelularProps = {
    pendientes: [fila('e1'), fila('e2', { identificacion: 'ambiguo', atencion: 'por_revisar', lead_id: null, lead_nombre: null, numero: '+51987654330' })],
    resueltas: [resuelta],
    ahora: AHORA,
    busqueda: { demo: true, leadsLocales: [LEAD_DEMO] },
    onRegistrar: vi.fn(), onElegirLead: vi.fn(), onDescartar: vi.fn(), onAbrirFicha: vi.fn(),
    ...extra,
  }
  render(<LlamadasCelular {...props} />)
  return props
}
const filaDe = (texto: RegExp) => screen.getAllByRole('listitem').find((li) => texto.test(li.textContent ?? ''))!

describe('LlamadasCelular', () => {
  it('pendientes: quién, qué pide, cuándo y la acción que toca; la ambigua no dice cuántos leads', () => {
    montar()
    expect(screen.getByRole('button', { name: 'Pendientes · 2', pressed: true })).toBeInTheDocument()
    const maria = filaDe(/MARÍA LÓPEZ/)
    expect(within(maria).getByText('Pide resultado')).toBeInTheDocument()
    expect(within(maria).getByText('Llamaste a las 10:42 · hace 16 min · +51 987 654 322')).toBeInTheDocument()
    expect(within(maria).getByRole('button', { name: 'Registrar resultado' })).toBeInTheDocument()
    const ambigua = filaDe(/\+51 987 654 330/)
    expect(within(ambigua).getByText('Por revisar')).toBeInTheDocument()
    expect(within(ambigua).getByText(/más de un lead podría tener este número/)).toBeInTheDocument()
    expect(within(ambigua).getByRole('button', { name: 'Elegir el lead' })).toBeInTheDocument()
    expect(within(ambigua).queryByRole('button', { name: 'Registrar resultado' })).not.toBeInTheDocument()
  })

  it('«Registrar resultado» y el nombre del lead avisan a la pantalla', async () => {
    const user = userEvent.setup()
    const props = montar()
    await user.click(within(filaDe(/MARÍA LÓPEZ/)).getByRole('button', { name: 'Registrar resultado' }))
    expect(props.onRegistrar).toHaveBeenCalledWith(expect.objectContaining({ evento_id: 'e1', evento_origen_id: 'C1-1791226920' }))
    await user.click(screen.getByRole('button', { name: 'MARÍA LÓPEZ CASTRO' }))
    expect(props.onAbrirFicha).toHaveBeenCalledWith('l2')
  })

  it('descartar: los motivos de la lista cerrada; «otro» exige escribirlo; cancelar devuelve el foco', async () => {
    const user = userEvent.setup()
    const props = montar()
    const maria = filaDe(/MARÍA LÓPEZ/)
    await user.click(within(maria).getByRole('button', { name: 'Descartar' }))
    const panel = within(maria).getByRole('group', { name: '¿Por qué la descartas?' })
    await waitFor(() => expect(within(panel).getByRole('button', { name: 'Llamada personal' })).toHaveFocus())
    await user.click(within(panel).getByRole('button', { name: 'Cancelar' }))
    await waitFor(() => expect(within(maria).getByRole('button', { name: 'Descartar' })).toHaveFocus())
    expect(props.onDescartar).not.toHaveBeenCalled()

    await user.click(within(maria).getByRole('button', { name: 'Descartar' }))
    await user.click(within(maria).getByRole('button', { name: 'Otro motivo' }))
    const confirmar = within(maria).getByRole('button', { name: 'Descartar' })
    expect(confirmar).toBeDisabled()
    await user.type(within(maria).getByRole('textbox', { name: 'Escribe el motivo' }), 'Era mi primo')
    await user.click(confirmar)
    expect(props.onDescartar).toHaveBeenCalledWith(expect.objectContaining({ evento_id: 'e1' }), 'otro', 'Era mi primo')

    await user.click(within(maria).getByRole('button', { name: 'Descartar' }))
    await user.click(within(maria).getByRole('button', { name: 'Número de prueba' }))
    expect(props.onDescartar).toHaveBeenLastCalledWith(expect.objectContaining({ evento_id: 'e1' }), 'numero_de_prueba', null)
  })

  it('elegir el lead: la búsqueda del receptor precargada con los dígitos; al elegir, avisa con el lead', async () => {
    const user = userEvent.setup()
    const props = montar()
    const ambigua = filaDe(/\+51 987 654 330/)
    await user.click(within(ambigua).getByRole('button', { name: 'Elegir el lead' }))
    const campo = within(ambigua).getByRole('searchbox', { name: 'Buscar lead por nombre, teléfono o DNI' })
    expect(campo).toHaveValue('987654330')
    await user.clear(campo)
    await user.type(campo, 'luis')
    await user.click(within(ambigua).getByRole('button', { name: 'Buscar' }))
    await user.click(await within(ambigua).findByRole('button', { name: /LUIS TORRES/ }))
    expect(props.onElegirLead).toHaveBeenCalledWith(expect.objectContaining({ evento_id: 'e2' }), LEAD_DEMO)
  })

  it('«Qué pasó hoy»: el resultado y cómo se resolvió', async () => {
    const user = userEvent.setup()
    montar()
    await user.click(screen.getByRole('button', { name: 'Qué pasó hoy · 1' }))
    expect(screen.getByRole('button', { name: 'Qué pasó hoy · 1', pressed: true })).toBeInTheDocument()
    const teresa = filaDe(/TERESA/)
    expect(within(teresa).getByText('Agendó cita')).toBeInTheDocument()
    expect(within(teresa).getByText(/Registrada al colgar: el celular abrió la encuesta · llamada a las 09:00/)).toBeInTheDocument()
  })

  it('vacías: lo dicen en vez de quedar en blanco', async () => {
    const user = userEvent.setup()
    montar({ pendientes: [], resueltas: [] })
    expect(screen.getByText('Nada pendiente')).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Qué pasó hoy · 0' }))
    expect(screen.getByText('Todavía nada resuelto hoy')).toBeInTheDocument()
  })

  it('la que llegó tarde lo dice y marca cuánto lleva', () => {
    montar({ pendientes: [fila('e3', { ocurrio_en: '2026-10-04T23:05:00Z', recibido_en: '2026-10-05T12:00:00Z' })] })
    const fila3 = filaDe(/MARÍA LÓPEZ/)
    expect(within(fila3).getByText('Lleva 16 h')).toBeInTheDocument()
    expect(within(fila3).getByText(/El aviso llegó a las 07:00: el celular estuvo sin señal/)).toBeInTheDocument()
  })
})
