// La ficha de la base para Supervisión y Gerencia (F4, decisión 5 de Miguel): CONSULTA —datos e historial— sin
// registrar intentos, sin reactivar, sin marcar «No contactar» y sin botones de llamar; si el lead está vetado, la
// marca completa y «Quitar No contactar» (D5) con motivo ≥ 5 y el aviso de que se levanta para la persona entera.
// Los textos no hablan de «tu base». La ficha del analista no cambia (ficha-base.test.tsx).
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import type { FilaBaseGestion } from '@/lib/base-gestion'

const toastSuccess = vi.fn()
const toastInfo = vi.fn()
vi.mock('sonner', () => ({ toast: { success: toastSuccess, info: toastInfo, error: vi.fn() } }))
vi.mock('@/lib/store-context', () => ({ useCRMData: () => ({ recargar: vi.fn(async () => true) }), usePanelesActions: () => ({ abrirLead: vi.fn() }) }))

const levantar = { mutateAsync: vi.fn(), isPending: false }
const intento = { mutateAsync: vi.fn(), isPending: false }
vi.mock('@/data/crm-queries', () => ({
  useRegistrarIntentoBase: () => intento,
  useReactivarLeadBase: () => ({ mutateAsync: vi.fn(), isPending: false }),
  useMarcarNoContactarBase: () => ({ mutateAsync: vi.fn(), isPending: false }),
  useLevantarNoContactarBase: () => levantar,
}))
vi.mock('@/data/use-actividades-de-lead', () => ({
  useActividadesDeLead: () => ({ items: [], hayMas: false, cargando: false, cargandoMas: false, error: null, cargarMas: vi.fn(), reintentar: vi.fn() }),
}))

const { CrmApiError } = await import('@/data/crm-api')
const { FichaBase } = await import('./ficha-base')

const FILA: FilaBaseGestion = {
  lead_id: 'lead-1', nombre_completo: 'ROSA QUISPE', telefono: '+51987654321', distrito: 'Surco', origen: 'landing',
  categoria_interes: null, monto_estimado: 10000, moneda: 'PEN', motivo_descarte: 'no_responde',
  descartado_en: '2026-09-25T15:00:00Z', dias_desde_descarte: 7, etapa_maxima: 'contactado', intentos: 1,
  ultimo_resultado: 'no_contesto', ultimo_intento_en: '2026-09-30T15:00:00Z', proxima_llamada_en: null,
  rellamada_hoy: false, enfriado_hasta: null, ciclo_n: 1, vendedor_id: 'v1', gestiona: 'ANA', recibido_en: '2026-08-15T15:00:00Z',
}
const VETADA: FilaBaseGestion = { ...FILA, no_contactar: true, no_contactar_en: '2026-09-28T16:00:00Z', no_contactar_motivo: 'Pidió que no lo llamen más', no_contactar_por: 'ANA PÉREZ' }

function abrir(fila: FilaBaseGestion, { demo = false } = {}) {
  return render(<FichaBase fila={fila} demo={demo} puedeMarcar={false} onCerrar={vi.fn()} modo="supervision" />)
}
const ficha = () => screen.getByRole('dialog', { name: 'ROSA QUISPE' })

beforeEach(() => { levantar.mutateAsync.mockReset().mockResolvedValue({ leadsAfectados: 3 }) })
afterEach(() => vi.clearAllMocks())

describe('consulta (Supervisión y Gerencia)', () => {
  it('datos e historial, SIN registrar intento, sin reactivar, sin marcar y sin llamar', () => {
    abrir(FILA)
    const dialogo = ficha()
    expect(within(dialogo).getByRole('heading', { name: 'Datos' })).toBeInTheDocument()
    expect(within(dialogo).getByRole('region', { name: 'Gestiones del lead' })).toBeInTheDocument()
    expect(within(dialogo).queryByRole('form', { name: '¿Qué pasó con la llamada?' })).toBeNull()
    expect(within(dialogo).queryByRole('button', { name: /Reactivar/ })).toBeNull()
    expect(within(dialogo).queryByRole('button', { name: /No contactar/ })).toBeNull()
    expect(within(dialogo).queryByRole('button', { name: /Llamar/ })).toBeNull()
    expect(within(dialogo).queryByRole('button', { name: /Quitar/ })).toBeNull()
    expect(within(dialogo).getByText(/Ficha de consulta: los intentos y la reactivación los registra ANA/)).toBeInTheDocument()
    // Sin «tu base» ni «tu cartera»: no es la base del supervisor.
    expect(dialogo.textContent).not.toMatch(/tu base|tu cartera/)
  })

  it('lead vetado: la marca con cuándo, motivo y quién, y «Quitar No contactar» en el pie', () => {
    abrir(VETADA)
    const dialogo = ficha()
    const marca = within(dialogo).getByRole('heading', { name: /No contactar · Ley 29571/ }).closest('section')!
    expect(within(marca).getByText('Pidió que no lo llamen más')).toBeInTheDocument()
    expect(within(marca).getByText('ANA PÉREZ')).toBeInTheDocument()
    expect(within(dialogo).getByText('No contactar', { selector: '.ac-chip' })).toBeInTheDocument()
    expect(within(dialogo).getByRole('button', { name: /Quitar «No contactar»/ })).toBeInTheDocument()
    expect(within(dialogo).getByText('Se levanta para la persona y todos sus leads.')).toBeInTheDocument()
  })

  it('la marca que vino de otro lead de la persona se dice así', () => {
    abrir({ ...VETADA, no_contactar_en: null, no_contactar_motivo: null, no_contactar_por: null })
    expect(within(ficha()).getByText('La marca viene de otro lead de la misma persona.')).toBeInTheDocument()
  })

  it('«Quitar No contactar» avisa que se levanta para la persona entera, exige motivo ≥ 5 y confirma cuántos leads se liberaron', async () => {
    const usuario = userEvent.setup()
    abrir(VETADA)
    await usuario.click(within(ficha()).getByRole('button', { name: /Quitar «No contactar»/ }))
    const dialogo = screen.getByRole('dialog', { name: 'Quitar «No contactar» a ROSA QUISPE' })
    expect(within(dialogo).getByText(/Se levanta para la persona y todos sus leads/)).toBeInTheDocument()
    const motivo = within(dialogo).getByLabelText('Motivo')
    await usuario.type(motivo, 'abc')
    await usuario.click(within(dialogo).getByRole('button', { name: 'Quitar la marca' }))
    expect(levantar.mutateAsync).not.toHaveBeenCalled()
    expect(motivo).toHaveAttribute('aria-invalid', 'true')
    await usuario.clear(motivo)
    await usuario.type(motivo, ' Volvió a pedir información ')
    await usuario.click(within(dialogo).getByRole('button', { name: 'Quitar la marca' }))
    expect(levantar.mutateAsync).toHaveBeenCalledWith({ leadId: 'lead-1', motivo: ' Volvió a pedir información ' })
    expect(toastSuccess).toHaveBeenCalledWith('«No contactar» quitado: los 3 leads de la persona pueden volver a llamarse')
    expect(screen.queryByRole('dialog', { name: /Quitar «No contactar»/ })).toBeNull()
    // El botón «Quitar» desaparece con la marca: el foco va al cerrar de la ficha, no se pierde.
    await vi.waitFor(() => expect(screen.getByRole('button', { name: 'Cerrar la ficha' })).toHaveFocus())
  })

  it('42501 «pídelo a Gerencia» se muestra en el diálogo (no culpa al motivo) y no cierra', async () => {
    const usuario = userEvent.setup()
    levantar.mutateAsync.mockRejectedValue(new CrmApiError('La persona tiene leads fuera de tu equipo: pídelo a Gerencia.', 'SIN_PERMISO'))
    abrir(VETADA)
    await usuario.click(within(ficha()).getByRole('button', { name: /Quitar «No contactar»/ }))
    const dialogo = screen.getByRole('dialog', { name: 'Quitar «No contactar» a ROSA QUISPE' })
    await usuario.type(within(dialogo).getByLabelText('Motivo'), 'Volvió a pedir información')
    await usuario.click(within(dialogo).getByRole('button', { name: 'Quitar la marca' }))
    expect(within(dialogo).getByRole('alert')).toHaveTextContent('La persona tiene leads fuera de tu equipo: pídelo a Gerencia.')
    expect(within(dialogo).getByLabelText('Motivo')).not.toHaveAttribute('aria-invalid')
    expect(toastSuccess).not.toHaveBeenCalled()
  })

  it('en la demo no se quita nada', async () => {
    const usuario = userEvent.setup()
    abrir(VETADA, { demo: true })
    await usuario.click(within(ficha()).getByRole('button', { name: /Quitar «No contactar»/ }))
    const dialogo = screen.getByRole('dialog', { name: 'Quitar «No contactar» a ROSA QUISPE' })
    await usuario.type(within(dialogo).getByLabelText('Motivo'), 'Volvió a pedir información')
    await usuario.click(within(dialogo).getByRole('button', { name: 'Quitar la marca' }))
    expect(levantar.mutateAsync).not.toHaveBeenCalled()
    expect(toastInfo).toHaveBeenCalledWith('En la demo no se quita la marca')
  })
})

describe('el analista sigue igual', () => {
  it('sin `modo`, la ficha registra intentos y no ofrece quitar la marca', () => {
    render(<FichaBase fila={FILA} demo={false} puedeMarcar={false} onCerrar={vi.fn()} />)
    expect(within(ficha()).getByRole('form', { name: '¿Qué pasó con la llamada?' })).toBeInTheDocument()
    expect(within(ficha()).getByRole('button', { name: /Reactivar/ })).toBeInTheDocument()
    expect(within(ficha()).queryByRole('button', { name: /Quitar/ })).toBeNull()
  })
})
