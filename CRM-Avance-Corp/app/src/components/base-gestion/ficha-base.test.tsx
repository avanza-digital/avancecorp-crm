// La ficha del lead de la base (F2) como la usa el analista: registra el intento (atajos, nota, rellamada con
// fecha), el mismo envío reusa su operación, los desenlaces que sacan al lead de la base cierran la ficha y lo
// dicen, Reactivar y «No contactar» confirman, y el historial se recorre entero con buscador.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import type { FilaBaseGestion } from '@/lib/base-gestion'
import type { Actividad } from '@/lib/tipos'

const toastSuccess = vi.fn()
const toastInfo = vi.fn()
vi.mock('sonner', () => ({ toast: { success: toastSuccess, info: toastInfo, error: vi.fn() } }))

const recargar = vi.fn(async () => true)
const abrirLead = vi.fn()
vi.mock('@/lib/store-context', () => ({ useCRMData: () => ({ recargar }), usePanelesActions: () => ({ abrirLead }) }))

const intento = { mutateAsync: vi.fn(), isPending: false }
const reactivar = { mutateAsync: vi.fn(), isPending: false }
const noContactar = { mutateAsync: vi.fn(), isPending: false }
vi.mock('@/data/crm-queries', () => ({
  useRegistrarIntentoBase: () => intento,
  useReactivarLeadBase: () => reactivar,
  useMarcarNoContactarBase: () => noContactar,
}))

let HIST: { items: Actividad[]; hayMas: boolean; cargando: boolean; cargandoMas: boolean; error: unknown; cargarMas: () => void; reintentar: () => void }
vi.mock('@/data/use-actividades-de-lead', () => ({ useActividadesDeLead: () => HIST }))

const { CrmApiError } = await import('@/data/crm-api')
const { FichaBase } = await import('./ficha-base')

const FILA: FilaBaseGestion = {
  lead_id: 'lead-1', nombre_completo: 'ROSA QUISPE', telefono: '+51987654321', distrito: 'Surco', origen: 'landing',
  categoria_interes: null, monto_estimado: 10000, moneda: 'PEN', motivo_descarte: 'no_responde',
  descartado_en: '2026-09-25T15:00:00Z', dias_desde_descarte: 7, etapa_maxima: 'contactado', intentos: 1,
  ultimo_resultado: 'no_contesto', ultimo_intento_en: '2026-09-30T15:00:00Z', proxima_llamada_en: null,
  rellamada_hoy: false, enfriado_hasta: null, ciclo_n: 1, vendedor_id: 'v1', gestiona: 'ANA', recibido_en: '2026-08-15T15:00:00Z',
}

function act(id: string, sobre: Partial<Actividad> = {}): Actividad {
  return { id, lead_id: 'lead-1', tipo: 'nota', detalle: null, autor_nombre: 'ANA PÉREZ', creado_en: '2026-09-30T15:00:00Z', ...sobre }
}

const RESPUESTA = { ok: true as const, replay: false, intento_n: 2, etapa: 'descartado', reactivado: false, enfriado_hasta: null, proxima_llamada_en: null }
const onCerrar = vi.fn()

function abrir(sobre: Partial<FilaBaseGestion> = {}, demo = false) {
  return render(<FichaBase fila={{ ...FILA, ...sobre }} demo={demo} puedeMarcar={false} onCerrar={onCerrar} />)
}
const formulario = () => screen.getByRole('form', { name: 'Registrar el intento' })

beforeEach(() => {
  HIST = { items: [], hayMas: false, cargando: false, cargandoMas: false, error: null, cargarMas: vi.fn(), reintentar: vi.fn() }
  intento.mutateAsync.mockReset().mockResolvedValue(RESPUESTA)
  reactivar.mutateAsync.mockReset().mockResolvedValue({ replay: false, etapa: 'contactado', ciclo_n: 2 })
  noContactar.mutateAsync.mockReset().mockResolvedValue(undefined)
})
afterEach(() => vi.clearAllMocks())

describe('cabecera', () => {
  it('dice quién es y en qué está: mes, motivo, etapa máxima, intentos y próxima llamada', () => {
    abrir()
    const dialogo = screen.getByRole('dialog', { name: 'ROSA QUISPE' })
    expect(within(dialogo).getByText('Agosto 2026')).toBeInTheDocument()
    expect(within(dialogo).getByText('No responde')).toBeInTheDocument()
    expect(within(dialogo).getByText('1 de 3')).toBeInTheDocument()
    expect(within(dialogo).getByText('Sin agendar')).toBeInTheDocument()
  })
})

describe('registrar el intento', () => {
  it('el atajo elige el resultado, la nota viaja y el formulario se limpia', async () => {
    const usuario = userEvent.setup()
    abrir()
    await usuario.click(within(formulario()).getByText('No contestó'))
    await usuario.keyboard('5')
    expect(within(formulario()).getByRole('radio', { name: /Número errado/ })).toBeChecked()
    await usuario.type(within(formulario()).getByLabelText(/Nota/), 'sonó ocupado')
    await usuario.click(within(formulario()).getByRole('button', { name: 'Guardar intento' }))
    expect(intento.mutateAsync).toHaveBeenCalledWith({ operacionId: expect.any(String), leadId: 'lead-1', resultado: 'numero_errado', nota: 'sonó ocupado', proximaLlamada: null })
    expect(toastSuccess).toHaveBeenCalledWith('Intento 2 registrado')
    expect(within(formulario()).getByLabelText(/Nota/)).toHaveValue('')
    expect(within(formulario()).getByRole('radio', { name: /Número errado/ })).not.toBeChecked()
  })

  it('al abrir, el foco empieza en el primer resultado: los atajos funcionan de entrada', async () => {
    const usuario = userEvent.setup()
    abrir()
    await vi.waitFor(() => expect(within(formulario()).getByRole('radio', { name: /No contestó/ })).toHaveFocus())
    await usuario.keyboard('3')
    expect(within(formulario()).getByRole('radio', { name: /agendó cita/ })).toBeChecked()
  })

  it('«Guardar» sin resultado dice qué falta, lo asocia al grupo y lleva el foco al primer resultado', async () => {
    const usuario = userEvent.setup()
    abrir()
    await usuario.click(within(formulario()).getByRole('button', { name: 'Guardar intento' }))
    const aviso = screen.getByRole('alert')
    expect(aviso).toHaveTextContent('Elige qué pasó en la llamada (teclas 1–7).')
    const grupo = within(formulario()).getByRole('group', { name: /Qué pasó en la llamada/ })
    expect(grupo).toHaveAttribute('aria-invalid', 'true')
    expect(grupo).toHaveAttribute('aria-describedby', aviso.id)
    expect(within(formulario()).getByRole('radio', { name: /No contestó/ })).toHaveFocus()
    expect(intento.mutateAsync).not.toHaveBeenCalled()
  })

  it('en la nota, los dígitos son texto (no atajos)', async () => {
    const usuario = userEvent.setup()
    abrir()
    await usuario.click(within(formulario()).getByText('No contestó'))
    await usuario.type(within(formulario()).getByLabelText(/Nota/), 'llamar a las 3')
    expect(within(formulario()).getByRole('radio', { name: /No contestó/ })).toBeChecked()
  })

  it('el reintento del MISMO contenido reusa su operación (replay); si cambia lo que se manda, otra', async () => {
    const usuario = userEvent.setup()
    intento.mutateAsync.mockRejectedValueOnce(new CrmApiError('Sin conexión', 'RED')).mockRejectedValueOnce(new CrmApiError('Sin conexión', 'RED'))
    abrir()
    await usuario.click(within(formulario()).getByText('No contestó'))
    await usuario.click(within(formulario()).getByRole('button', { name: 'Guardar intento' }))
    expect(screen.getByRole('alert')).toHaveTextContent('Sin conexión')
    await usuario.click(within(formulario()).getByRole('button', { name: 'Guardar intento' }))
    await usuario.type(within(formulario()).getByLabelText(/Nota/), 'x')
    await usuario.click(within(formulario()).getByRole('button', { name: 'Guardar intento' }))
    const ids = intento.mutateAsync.mock.calls.map((c) => (c[0] as { operacionId: string }).operacionId)
    expect(ids[0]).toBe(ids[1])
    expect(ids[2]).not.toBe(ids[1])
  })

  it('«volver a llamar» pide fecha y hora dentro de 10 días y las manda en hora de Lima', async () => {
    const usuario = userEvent.setup()
    abrir()
    await usuario.click(within(formulario()).getByText('Contestó · volver a llamar'))
    const fecha = within(formulario()).getByLabelText('Fecha de la próxima llamada')
    await usuario.clear(fecha)
    await usuario.type(fecha, '2099-01-01')
    await usuario.click(within(formulario()).getByRole('button', { name: 'Guardar intento' }))
    expect(screen.getByRole('alert')).toHaveTextContent('como máximo a 10 días')
    expect(fecha).toHaveAttribute('aria-invalid', 'true')
    expect(fecha).toHaveAttribute('aria-describedby', screen.getByRole('alert').id)
    expect(intento.mutateAsync).not.toHaveBeenCalled()
    const manana = new Date(Date.now() + 86_400_000).toLocaleDateString('en-CA', { timeZone: 'America/Lima' })
    await usuario.clear(fecha)
    await usuario.type(fecha, manana)
    await usuario.click(within(formulario()).getByRole('button', { name: 'Guardar intento' }))
    expect(intento.mutateAsync).toHaveBeenCalledWith(expect.objectContaining({ resultado: 'volver_a_llamar', proximaLlamada: new Date(`${manana}T10:00:00-05:00`).toISOString() }))
  })

  it('con el tercero sin cita ni rellamada avisa del descanso antes de guardar', async () => {
    const usuario = userEvent.setup()
    abrir({ intentos: 2 })
    expect(screen.queryByText(/descansará 30 días/)).toBeNull()
    await usuario.click(within(formulario()).getByText('No contestó'))
    const aviso = screen.getByText(/descansará 30 días/)
    expect(aviso.parentElement).toHaveAttribute('aria-live', 'polite')
    expect(within(formulario()).getByRole('button', { name: 'Guardar intento' })).toHaveAttribute('aria-describedby', aviso.id)
    await usuario.click(within(formulario()).getByText('Contestó · volver a llamar'))
    expect(screen.queryByText(/descansará 30 días/)).toBeNull()
  })

  it('«agendó cita»: la ficha se cierra, la cartera se recarga y el aviso ofrece abrir su ficha', async () => {
    const usuario = userEvent.setup()
    intento.mutateAsync.mockResolvedValue({ ...RESPUESTA, reactivado: true, etapa: 'contactado' })
    abrir()
    await usuario.click(within(formulario()).getByText('Contestó · agendó cita'))
    await usuario.click(within(formulario()).getByRole('button', { name: 'Guardar intento' }))
    expect(onCerrar).toHaveBeenCalled()
    expect(recargar).toHaveBeenCalled()
    expect(toastSuccess).toHaveBeenCalledWith(expect.stringContaining('volvió a tu cartera'), expect.objectContaining({ action: expect.objectContaining({ label: 'Abrir su ficha' }) }))
    const opciones = toastSuccess.mock.calls[0]?.[1] as { action?: { onClick: () => void } } | undefined
    opciones?.action?.onClick()
    expect(abrirLead).toHaveBeenCalledWith('lead-1')
  })

  it('el tercer intento que lo pone a descansar cierra la ficha y dice hasta cuándo', async () => {
    const usuario = userEvent.setup()
    intento.mutateAsync.mockResolvedValue({ ...RESPUESTA, intento_n: 3, enfriado_hasta: '2026-11-02' })
    abrir({ intentos: 2 })
    await usuario.click(within(formulario()).getByText('No contestó'))
    await usuario.click(within(formulario()).getByRole('button', { name: 'Guardar intento' }))
    expect(onCerrar).toHaveBeenCalled()
    expect(toastInfo).toHaveBeenCalledWith(expect.stringContaining('descansa hasta el 02/11/2026'))
  })

  it('en la demo no se escribe nada', async () => {
    const usuario = userEvent.setup()
    abrir({}, true)
    await usuario.click(within(formulario()).getByText('No contestó'))
    await usuario.click(within(formulario()).getByRole('button', { name: 'Guardar intento' }))
    expect(intento.mutateAsync).not.toHaveBeenCalled()
    expect(toastInfo).toHaveBeenCalledWith('En la demo los intentos no se guardan')
  })
})

describe('otras acciones', () => {
  it('Reactivar confirma, vuelve a la cartera y cierra la ficha', async () => {
    const usuario = userEvent.setup()
    abrir()
    await usuario.click(screen.getByRole('button', { name: 'Reactivar' }))
    const dialogo = screen.getByRole('dialog', { name: '¿Reactivar a ROSA QUISPE?' })
    await usuario.type(within(dialogo).getByLabelText(/Nota/), 'volvió a interesarse')
    await usuario.click(within(dialogo).getByRole('button', { name: 'Reactivar' }))
    expect(reactivar.mutateAsync).toHaveBeenCalledWith({ operacionId: expect.any(String), leadId: 'lead-1', nota: 'volvió a interesarse' })
    expect(onCerrar).toHaveBeenCalled()
    expect(recargar).toHaveBeenCalled()
  })

  it('«No contactar» exige el motivo y después saca el lead de la base', async () => {
    const usuario = userEvent.setup()
    abrir()
    await usuario.click(screen.getByRole('button', { name: 'No contactar' }))
    const dialogo = screen.getByRole('dialog', { name: 'Marcar «No contactar» a ROSA QUISPE' })
    await usuario.click(within(dialogo).getByRole('button', { name: 'Marcar «No contactar»' }))
    expect(within(dialogo).getByRole('alert')).toHaveTextContent('Escribe el motivo (mínimo 5 caracteres)')
    expect(within(dialogo).getByLabelText('Motivo')).toHaveAttribute('aria-invalid', 'true')
    expect(within(dialogo).getByLabelText('Motivo')).toHaveAccessibleDescription(/Ley 29571.*Obligatorio · mínimo 5 caracteres/)
    expect(noContactar.mutateAsync).not.toHaveBeenCalled()
    await usuario.type(within(dialogo).getByLabelText('Motivo'), 'pidió que no lo llamen más')
    await usuario.click(within(dialogo).getByRole('button', { name: 'Marcar «No contactar»' }))
    expect(noContactar.mutateAsync).toHaveBeenCalledWith({ leadId: 'lead-1', motivo: 'pidió que no lo llamen más' })
    expect(onCerrar).toHaveBeenCalled()
    expect(toastInfo).toHaveBeenCalledWith(expect.stringContaining('salió de tu base'))
  })
})

describe('historial', () => {
  it('se recorre hasta el final sin que nadie pulse «cargar más»', () => {
    HIST = { ...HIST, items: [act('a1')], hayMas: true }
    abrir()
    expect(HIST.cargarMas).toHaveBeenCalled()
  })

  it('el buscador filtra sin tildes ni mayúsculas y dice cuando nada coincide', async () => {
    const usuario = userEvent.setup()
    HIST = {
      ...HIST,
      items: [
        act('a1', { detalle: 'Pidió que lo llamen después del almuerzo' }),
        act('a2', { tipo: 'llamada_no_contestada', metadata: { evento: 'intento_base', intento_n: 1, resultado: 'no_contesto' } }),
      ],
    }
    abrir()
    const lista = () => within(screen.getByRole('region', { name: 'Gestiones del lead' })).getByRole('list')
    expect(within(lista()).getAllByRole('listitem')).toHaveLength(2)
    expect(screen.getByRole('heading', { name: /Historial \(2 gestiones\)/ })).toBeInTheDocument()
    await usuario.type(screen.getByLabelText('Buscar en el historial'), 'DESPUES')
    expect(within(lista()).getAllByRole('listitem')).toHaveLength(1)
    await usuario.clear(screen.getByLabelText('Buscar en el historial'))
    await usuario.type(screen.getByLabelText('Buscar en el historial'), 'zzz')
    expect(screen.getByText('Nada del historial coincide con «zzz».')).toBeInTheDocument()
  })

  it('si falla, lo dice y ofrece reintentar', async () => {
    const usuario = userEvent.setup()
    HIST = { ...HIST, error: new Error('x') }
    abrir()
    expect(screen.getByRole('alert')).toHaveTextContent('No se pudo cargar el historial.')
    await usuario.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(HIST.reintentar).toHaveBeenCalled()
  })
})
