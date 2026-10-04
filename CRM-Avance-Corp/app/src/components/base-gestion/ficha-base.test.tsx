// La ficha del lead de la base (F2) como la usa el analista: registra el intento (atajos, nota, rellamada con
// fecha), el mismo envío reusa su operación, los desenlaces que sacan al lead de la base cierran la ficha y lo
// dicen, Reactivar y «No contactar» confirman en el pie, y la actividad se recorre entera con buscador.
// Rediseño del 03/10 (la ficha «como la del CRM»): cabecera con chips, contacto sin WhatsApp, el selector de
// resultado compartido con Gestión Diaria (se contrae al elegir) y la línea de tiempo de la ficha del lead.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act as actuar, fireEvent, render, screen, within } from '@testing-library/react'
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

function abrir(sobre: Partial<FilaBaseGestion> = {}, { demo = false, puedeMarcar = false } = {}) {
  return render(<FichaBase fila={{ ...FILA, ...sobre }} demo={demo} puedeMarcar={puedeMarcar} onCerrar={onCerrar} />)
}
const ficha = () => screen.getByRole('dialog', { name: 'ROSA QUISPE' })
const formulario = () => screen.getByRole('form', { name: '¿Qué pasó con la llamada?' })
const radio = (nombre: RegExp) => within(formulario()).getByRole('radio', { name: nombre })
const regionActividad = () => screen.getByRole('region', { name: 'Gestiones del lead' })

beforeEach(() => {
  HIST = { items: [], hayMas: false, cargando: false, cargandoMas: false, error: null, cargarMas: vi.fn(), reintentar: vi.fn() }
  intento.mutateAsync.mockReset().mockResolvedValue(RESPUESTA)
  reactivar.mutateAsync.mockReset().mockResolvedValue({ replay: false, etapa: 'contactado', ciclo_n: 2 })
  noContactar.mutateAsync.mockReset().mockResolvedValue(undefined)
})
afterEach(() => vi.clearAllMocks())

describe('cabecera', () => {
  it('el nombre del lead es el nombre de la ficha; chips de etapa máxima, origen, mes y descarte; hace cuánto se descartó', () => {
    abrir()
    const dialogo = ficha()
    expect(within(dialogo).getByRole('heading', { level: 2, name: 'ROSA QUISPE' })).toBeInTheDocument()
    expect(within(dialogo).getByText('Etapa máxima · Contactado')).toBeInTheDocument()
    expect(within(dialogo).getByText('LANDING')).toBeInTheDocument()
    expect(within(dialogo).getByText('Agosto 2026')).toBeInTheDocument()
    expect(within(dialogo).getByText('No responde').parentElement).toHaveTextContent('Descarte · No responde')
    expect(within(dialogo).getByText('Hace 7 días')).toBeInTheDocument()
    expect(within(dialogo).getByText('Descartado')).toBeInTheDocument()
  })

  it('los chips se leen con contraste AA: el texto de la etapa en el color de lectura; origen y descarte en gris fuerte', () => {
    abrir()
    const dialogo = ficha()
    const etapa = within(dialogo).getByText('Etapa máxima · Contactado')
    // El tinte y el punto conservan el color de la etapa; el texto no (varias etapas no llegan a 4,5:1 sobre su tinte).
    expect(etapa.style.color).toBe('var(--foreground)')
    expect(etapa.style.getPropertyValue('--c')).not.toBe('var(--foreground)')
    expect(within(dialogo).getByText('LANDING').style.getPropertyValue('--c')).toBe('var(--muted-foreground-strong)')
    expect(within(dialogo).getByText('No responde').closest('.ac-chip')).toHaveStyle({ '--c': 'var(--muted-foreground-strong)' })
  })

  it('sin el mes del servidor no pinta un chip vacío', () => {
    abrir({ recibido_en: null })
    expect(within(ficha()).queryByText('Agosto 2026')).toBeNull()
  })

  it('la X cierra la ficha', async () => {
    const usuario = userEvent.setup()
    abrir()
    await usuario.click(screen.getByRole('button', { name: 'Cerrar la ficha' }))
    expect(onCerrar).toHaveBeenCalled()
  })
})

describe('datos', () => {
  it('teléfono, distrito, intentos, quién gestiona, último resultado y próxima llamada', () => {
    abrir()
    const datos = within(ficha()).getByRole('heading', { name: 'Datos' }).closest('section')!
    expect(within(datos).getByText('987 654 321')).toBeInTheDocument()
    expect(within(datos).getByText('Surco')).toBeInTheDocument()
    expect(within(datos).getByText('1 de 3')).toBeInTheDocument()
    expect(within(datos).getByText('ANA')).toBeInTheDocument()
    expect(within(datos).getByText('No contestó', { exact: false })).toBeInTheDocument()
    expect(within(datos).getByText('Sin agendar')).toBeInTheDocument()
  })

  it('lo que falta se dice (sin teléfono, sin intentos, sin asignar)', () => {
    abrir({ telefono: null, distrito: null, gestiona: null, ultimo_resultado: null, ultimo_intento_en: null, intentos: 0 })
    const datos = within(ficha()).getByRole('heading', { name: 'Datos' }).closest('section')!
    expect(within(datos).getByText('Sin teléfono')).toBeInTheDocument()
    expect(within(datos).getByText('Sin distrito')).toBeInTheDocument()
    expect(within(datos).getByText('Sin asignar')).toBeInTheDocument()
    expect(within(datos).getByText('Sin intentos')).toBeInTheDocument()
    // Sin número utilizable no se ofrece ni llamar ni copiar.
    expect(screen.queryByRole('group', { name: 'Contactar' })).toBeNull()
    expect(screen.getByText('Sin teléfono para contactar')).toBeInTheDocument()
  })
})

describe('contacto', () => {
  it('sin WhatsApp: solo «Llamar» y «Copiar número»', () => {
    abrir()
    const contacto = screen.getByRole('group', { name: 'Contactar' })
    expect(within(contacto).getAllByRole('button').map((b) => b.textContent?.trim())).toEqual(['Llamar', 'Copiar número'])
    expect(within(ficha()).queryByText(/WhatsApp/)).toBeNull()
  })

  it('en la laptop «Llamar» copia el número y lleva el foco al resultado; «Copiar número» solo copia', async () => {
    const usuario = userEvent.setup()
    const copiar = vi.spyOn(navigator.clipboard, 'writeText')
    abrir()
    await usuario.click(screen.getByRole('button', { name: 'Llamar a ROSA QUISPE: copia su número y pasa al resultado' }))
    expect(copiar).toHaveBeenCalledWith('+51987654321')
    await vi.waitFor(() => expect(toastSuccess).toHaveBeenCalledWith('Número copiado: 987 654 321 — márcalo desde tu celular'))
    expect(radio(/No contestó/)).toHaveFocus()
    // El nombre accesible empieza por lo que se ve escrito (WCAG 2.5.3).
    await usuario.click(screen.getByRole('button', { name: 'Copiar número de ROSA QUISPE' }))
    await vi.waitFor(() => expect(toastSuccess).toHaveBeenCalledWith('Número copiado: 987 654 321'))
  })

  it('en el celular «Llamar» abre el marcador', () => {
    abrir({}, { puedeMarcar: true })
    expect(screen.getByRole('link', { name: 'Llamar a ROSA QUISPE' })).toHaveAttribute('href', 'tel:+51987654321')
  })
})

describe('registrar el intento', () => {
  it('el atajo elige el resultado, la nota viaja y el formulario se limpia (vuelven los siete)', async () => {
    const usuario = userEvent.setup()
    abrir()
    expect(within(formulario()).getByText('Será el intento 2 de 3')).toBeInTheDocument()
    await vi.waitFor(() => expect(radio(/No contestó/)).toHaveFocus())
    await usuario.keyboard('5')
    expect(radio(/Número errado/)).toBeChecked()
    await usuario.type(within(formulario()).getByLabelText('Nota de la llamada'), 'sonó ocupado')
    await usuario.click(within(formulario()).getByRole('button', { name: 'Guardar intento' }))
    expect(intento.mutateAsync).toHaveBeenCalledWith({ operacionId: expect.any(String), leadId: 'lead-1', resultado: 'numero_errado', nota: 'sonó ocupado', proximaLlamada: null })
    expect(toastSuccess).toHaveBeenCalledWith('Intento 2 registrado')
    expect(within(formulario()).getByLabelText('Nota de la llamada')).toHaveValue('')
    expect(within(formulario()).getAllByRole('radio')).toHaveLength(7)
    expect(radio(/Número errado/)).not.toBeChecked()
  })

  it('al elegir, la lista se contrae: otro atajo no cambia el resultado hasta «Cambiar resultado»', async () => {
    const usuario = userEvent.setup()
    abrir()
    await usuario.click(within(formulario()).getByText('No contestó'))
    expect(within(formulario()).getAllByRole('radio')).toHaveLength(1)
    expect(radio(/No contestó/)).toBeChecked()
    await usuario.keyboard('5')
    expect(radio(/No contestó/)).toBeChecked()
    expect(within(formulario()).queryByRole('radio', { name: /Número errado/ })).toBeNull()
    const cambiar = within(formulario()).getByRole('button', { name: 'Cambiar resultado' })
    expect(cambiar).toHaveAttribute('aria-expanded', 'false')
    await usuario.click(cambiar)
    expect(within(formulario()).getAllByRole('radio')).toHaveLength(7)
    expect(within(formulario()).getByRole('button', { name: 'Mantener resultado' })).toHaveAttribute('aria-expanded', 'true')
    await usuario.keyboard('5')
    expect(radio(/Número errado/)).toBeChecked()
    expect(within(formulario()).getAllByRole('radio')).toHaveLength(1)
  })

  it('al abrir, el foco empieza en el primer resultado: los atajos funcionan de entrada', async () => {
    const usuario = userEvent.setup()
    abrir()
    await vi.waitFor(() => expect(radio(/No contestó/)).toHaveFocus())
    await usuario.keyboard('3')
    expect(radio(/agendó cita/)).toBeChecked()
  })

  it('«Guardar» sin resultado dice qué falta, lo asocia al grupo y lleva el foco al primer resultado', async () => {
    const usuario = userEvent.setup()
    abrir()
    const guardar = within(formulario()).getByRole('button', { name: 'Guardar intento' })
    expect(guardar).toHaveAttribute('aria-disabled', 'true')
    await usuario.click(guardar)
    const aviso = screen.getByRole('alert')
    expect(aviso).toHaveTextContent('Elige qué pasó en la llamada (teclas 1–7).')
    const grupo = within(formulario()).getByRole('group', { name: /Resultado/ })
    expect(grupo).toHaveAttribute('aria-invalid', 'true')
    expect(grupo.getAttribute('aria-describedby')?.split(' ')).toContain(aviso.id)
    expect(radio(/No contestó/)).toHaveFocus()
    expect(intento.mutateAsync).not.toHaveBeenCalled()
  })

  it('en la nota, los dígitos son texto (no atajos)', async () => {
    const usuario = userEvent.setup()
    abrir()
    await usuario.click(within(formulario()).getByText('No contestó'))
    await usuario.click(within(formulario()).getByRole('button', { name: 'Cambiar resultado' }))
    await usuario.type(within(formulario()).getByLabelText('Nota de la llamada'), 'llamar a las 3')
    expect(radio(/No contestó/)).toBeChecked()
  })

  it('el reintento del MISMO contenido reusa su operación (replay); si cambia lo que se manda, otra', async () => {
    const usuario = userEvent.setup()
    intento.mutateAsync.mockRejectedValueOnce(new CrmApiError('Sin conexión', 'RED')).mockRejectedValueOnce(new CrmApiError('Sin conexión', 'RED'))
    abrir()
    await usuario.click(within(formulario()).getByText('No contestó'))
    await usuario.click(within(formulario()).getByRole('button', { name: 'Guardar intento' }))
    const aviso = screen.getByRole('alert')
    expect(aviso).toHaveTextContent('Sin conexión')
    const guardar = within(formulario()).getByRole('button', { name: 'Guardar intento' })
    expect(guardar).toHaveFocus()
    expect(guardar.getAttribute('aria-describedby')?.split(' ')).toContain(aviso.id)
    await usuario.click(within(formulario()).getByRole('button', { name: 'Guardar intento' }))
    await usuario.type(within(formulario()).getByLabelText('Nota de la llamada'), 'x')
    await usuario.click(within(formulario()).getByRole('button', { name: 'Guardar intento' }))
    const ids = intento.mutateAsync.mock.calls.map((c) => (c[0] as { operacionId: string }).operacionId)
    expect(ids[0]).toBe(ids[1])
    expect(ids[2]).not.toBe(ids[1])
  })

  it('«volver a llamar» pide fecha y hora dentro de 10 días y las manda en hora de Lima', async () => {
    const usuario = userEvent.setup()
    abrir()
    await usuario.click(within(formulario()).getByText('Contestó · volver a llamar'))
    expect(within(formulario()).getByRole('group', { name: 'Cuándo volver a llamar' })).toBeInTheDocument()
    const fecha = within(formulario()).getByLabelText('Fecha')
    expect(fecha).toHaveAccessibleDescription('Como máximo a 10 días desde hoy.')
    await usuario.clear(fecha)
    await usuario.type(fecha, '2099-01-01')
    await usuario.click(within(formulario()).getByRole('button', { name: 'Guardar intento' }))
    const aviso = screen.getByRole('alert')
    expect(aviso).toHaveTextContent('como máximo a 10 días')
    expect(fecha).toHaveAttribute('aria-invalid', 'true')
    expect(fecha.getAttribute('aria-describedby')?.split(' ')).toContain(aviso.id)
    expect(fecha).toHaveFocus()
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
    expect(within(formulario()).getByText('Será el intento 3 de 3')).toBeInTheDocument()
    expect(screen.queryByText(/descansará 30 días/)).toBeNull()
    await usuario.click(within(formulario()).getByText('No contestó'))
    const aviso = screen.getByText(/descansará 30 días/)
    expect(aviso.parentElement).toHaveAttribute('aria-live', 'polite')
    expect(within(formulario()).getByRole('button', { name: 'Guardar intento' })).toHaveAttribute('aria-describedby', aviso.id)
    await usuario.click(within(formulario()).getByRole('button', { name: 'Cambiar resultado' }))
    await usuario.click(within(formulario()).getByText('Contestó · volver a llamar'))
    expect(screen.queryByText(/descansará 30 días/)).toBeNull()
  })

  it('con una rellamada agendada el 3.º no avisa del descanso (D12) y pasado el tope dice «intento 4»', () => {
    abrir({ intentos: 3, proxima_llamada_en: '2026-10-05T15:00:00Z' })
    expect(within(formulario()).getByText('Será el intento 4')).toBeInTheDocument()
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
    abrir({}, { demo: true })
    await usuario.click(within(formulario()).getByText('No contestó'))
    await usuario.click(within(formulario()).getByRole('button', { name: 'Guardar intento' }))
    expect(intento.mutateAsync).not.toHaveBeenCalled()
    expect(toastInfo).toHaveBeenCalledWith('En la demo los intentos no se guardan')
  })
})

describe('pie: No contactar · Reactivar', () => {
  it('van en el pie fijo, «No contactar» a la izquierda y «Reactivar» a la derecha', () => {
    abrir()
    const pie = screen.getByRole('group', { name: 'Acciones del lead' })
    expect(within(pie).getAllByRole('button').map((b) => b.textContent?.trim())).toEqual(['No contactar', 'Reactivar'])
    // Rojo de TEXTO: el de relleno no llega a 4,5:1 sobre el tinte del hover.
    expect(within(pie).getByRole('button', { name: 'No contactar' })).toHaveClass('text-[var(--destructive-text)]')
  })

  it('Reactivar confirma, vuelve a la cartera y cierra la ficha', async () => {
    const usuario = userEvent.setup()
    abrir()
    await usuario.click(screen.getByRole('button', { name: 'Reactivar' }))
    const dialogo = screen.getByRole('dialog', { name: '¿Reactivar a ROSA QUISPE?' })
    // La consecuencia se lee con el campo y con el botón, como en «No contactar».
    expect(within(dialogo).getByLabelText(/Nota/)).toHaveAccessibleDescription(/sale de tu base/)
    expect(within(dialogo).getByRole('button', { name: 'Reactivar' })).toHaveAccessibleDescription(/sale de tu base/)
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

describe('actividad', () => {
  it('se recorre hasta el final sin que nadie pulse «cargar más»', () => {
    HIST = { ...HIST, items: [act('a1')], hayMas: true }
    abrir()
    expect(HIST.cargarMas).toHaveBeenCalled()
  })

  it('la línea de tiempo rotula e ilustra lo propio de la base: intento, reactivación y «No contactar»', () => {
    HIST = {
      ...HIST,
      items: [
        act('a1', { metadata: { evento: 'no_contactar', accion: 'marcar' }, detalle: 'pidió que no lo llamen' }),
        act('a2', { metadata: { evento: 'reactivacion_base' } }),
        act('a3', { tipo: 'llamada_no_contestada', metadata: { evento: 'intento_base', intento_n: 1, resultado: 'no_contesto' } }),
      ],
    }
    abrir()
    const filas = within(within(regionActividad()).getByRole('list')).getAllByRole('listitem')
    expect(filas.map((f) => f.querySelector('p')?.textContent)).toEqual(['Marcado «No contactar»', 'Reactivado desde la base', 'Intento 1 · No contestó'])
    expect(filas[0]?.querySelector('svg')).toHaveClass('lucide-ban')
    expect(filas[1]?.querySelector('svg')).toHaveClass('lucide-archive-restore')
    // Quién lo hizo, como en la ficha del lead.
    expect(filas[0]).toHaveTextContent('ANA PÉREZ ·')
  })

  it('el buscador filtra sin tildes ni mayúsculas, cuenta lo que coincide y dice cuando nada coincide', async () => {
    const usuario = userEvent.setup()
    HIST = {
      ...HIST,
      items: [
        act('a1', { detalle: 'Pidió que lo llamen después del almuerzo' }),
        act('a2', { tipo: 'llamada_no_contestada', metadata: { evento: 'intento_base', intento_n: 1, resultado: 'no_contesto' } }),
      ],
    }
    abrir()
    const lista = () => within(regionActividad()).getByRole('list')
    expect(within(lista()).getAllByRole('listitem')).toHaveLength(2)
    expect(screen.getByRole('heading', { name: 'Actividad (2)' })).toBeInTheDocument()
    await usuario.type(screen.getByLabelText('Buscar en la actividad'), 'DESPUES')
    expect(within(lista()).getAllByRole('listitem')).toHaveLength(1)
    expect(screen.getByRole('heading', { name: 'Actividad (1 de 2)' })).toBeInTheDocument()
    await usuario.clear(screen.getByLabelText('Buscar en la actividad'))
    await usuario.type(screen.getByLabelText('Buscar en la actividad'), 'zzz')
    expect(screen.getByText('Nada de la actividad coincide con «zzz».')).toBeInTheDocument()
  })

  it('sin buscar, una racha de cambios de etapa se agrupa como en la ficha del lead; buscando, va suelta', async () => {
    const usuario = userEvent.setup()
    HIST = {
      ...HIST,
      items: [
        act('e1', { tipo: 'cambio_etapa', detalle: 'Contactado → Descartado' }),
        act('e2', { tipo: 'cambio_etapa', detalle: 'Nuevo → Contactado' }),
      ],
    }
    abrir()
    expect(within(regionActividad()).getByRole('button', { name: 'Ver los 2 cambios de etapa' })).toBeInTheDocument()
    await usuario.type(screen.getByLabelText('Buscar en la actividad'), 'contactado')
    expect(within(regionActividad()).queryByRole('button', { name: /cambios de etapa/ })).toBeNull()
    expect(within(within(regionActividad()).getByRole('list')).getAllByRole('listitem')).toHaveLength(2)
  })

  it('sin gestiones lo dice', () => {
    abrir()
    expect(screen.getByText('Este lead no tiene gestiones registradas.')).toBeInTheDocument()
  })

  it('mientras carga, la lista está ocupada y el encabezado no promete una cifra', () => {
    HIST = { ...HIST, cargando: true }
    abrir()
    expect(within(regionActividad()).getByRole('list')).toHaveAttribute('aria-busy', 'true')
    expect(screen.getByRole('heading', { name: 'Actividad (cargando…)' })).toBeInTheDocument()
  })

  it('si falla, lo dice y ofrece reintentar', async () => {
    const usuario = userEvent.setup()
    HIST = { ...HIST, error: new Error('x') }
    abrir()
    expect(screen.getByRole('alert')).toHaveTextContent('No se pudo cargar el historial.')
    await usuario.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(HIST.reintentar).toHaveBeenCalled()
    // Si el reintento sale bien el botón desaparece: el foco ya está en la región, no en <body>.
    expect(regionActividad()).toHaveFocus()
  })

  it('una sola región nombrada para la actividad («Gestiones del lead»), con el contorno de foco de la casa', () => {
    abrir()
    expect(screen.getAllByRole('region', { name: 'Gestiones del lead' })).toHaveLength(1)
    expect(screen.queryByRole('region', { name: /Actividad/ })).toBeNull()
    expect(regionActividad()).toHaveClass('focus-visible:outline-2', 'focus-visible:outline-ring')
    expect(regionActividad()).not.toHaveClass('outline-none')
  })

  it('el resultado del buscador se anuncia al dejar de escribir (no con cada tecla); la lista se filtra al instante', async () => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] })
    try {
      HIST = {
        ...HIST,
        items: [act('a1', { detalle: 'Pidió que lo llamen después del almuerzo' }), act('a2', { detalle: 'otra cosa' })],
      }
      abrir()
      const estado = within(ficha()).getAllByRole('status').find((p) => p.textContent?.includes('Actividad cargada'))!
      expect(estado).toHaveTextContent('Actividad cargada: 2 gestiones')
      const buscador = screen.getByLabelText('Buscar en la actividad')
      // Una búsqueda que no coincide y, antes de 400 ms, otra que sí: la primera cifra no llega a anunciarse.
      fireEvent.change(buscador, { target: { value: 'zzz' } })
      expect(screen.getByText('Nada de la actividad coincide con «zzz».')).toBeInTheDocument()
      actuar(() => { vi.advanceTimersByTime(300) })
      expect(estado).toHaveTextContent('Actividad cargada: 2 gestiones')
      fireEvent.change(buscador, { target: { value: 'despues' } })
      expect(within(within(regionActividad()).getByRole('list')).getAllByRole('listitem')).toHaveLength(1)
      actuar(() => { vi.advanceTimersByTime(300) })
      expect(estado).toHaveTextContent('Actividad cargada: 2 gestiones')
      actuar(() => { vi.advanceTimersByTime(100) })
      expect(estado).toHaveTextContent('1 de 2 gestiones coinciden')
    } finally {
      vi.useRealTimers()
    }
  })
})
