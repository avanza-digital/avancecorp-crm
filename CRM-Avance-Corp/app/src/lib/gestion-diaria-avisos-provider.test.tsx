import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, fireEvent, render, screen } from '@testing-library/react'
import { avisosFixture } from './gestion-diaria-avisos.fixture'

const dobles = vi.hoisted(() => ({ datos: null as unknown, presentar: vi.fn(), actuar: vi.fn(), refetch: vi.fn(), error: null as unknown }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: { id: '00000000-0000-4000-8000-000000000001', rol: 'supervisor' } }) }))
vi.mock('@/data/gestion-diaria-seguimiento-api', () => ({ presentarCorte: dobles.presentar }))
vi.mock('@/components/gestion-diaria/alertas-del-dia', () => ({ AlertasDelDia: () => <p>Otros pendientes confirmados</p> }))
vi.mock('@/data/gestion-diaria-seguimiento-queries', () => ({ useAvisosCortes: () => ({
  datos: dobles.error ? null : dobles.datos, habilitada: true,
  consulta: { dataUpdatedAt: 1, isPending: false, error: dobles.error, refetch: dobles.refetch },
  accion: { isPending: false, mutateAsync: dobles.actuar },
}) }))
const { GestionDiariaAvisosProvider } = await import('./gestion-diaria-avisos-provider')
const { AvisosEquipo } = await import('@/components/gestion-diaria/avisos-equipo')
const avanzar = async (ms = 2100) => { await act(async () => { await vi.advanceTimersByTimeAsync(ms) }) }
const montar = () => render(<GestionDiariaAvisosProvider><label>Escribir nota<textarea /></label><button>Terminar nota</button></GestionDiariaAvisosProvider>)
beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setInterval', 'clearInterval', 'performance'] })
  vi.clearAllMocks()
  dobles.datos = avisosFixture()
  dobles.error = null
  dobles.presentar.mockResolvedValue(avisosFixture().alertas[0])
  dobles.refetch.mockImplementation(async () => ({ data: dobles.datos, error: dobles.error }))
  dobles.actuar.mockResolvedValue(avisosFixture())
})
afterEach(() => { vi.useRealTimers() })

describe('popup de cortes del supervisor', () => {
  it('un error de presentación no oculta pendientes y Actualizar recupera aunque el canal se pause', async () => {
    dobles.presentar.mockRejectedValueOnce(new Error('Respuesta perdida'))
    const vista = render(<GestionDiariaAvisosProvider><AvisosEquipo /></GestionDiariaAvisosProvider>)
    await avanzar()
    expect(screen.getByText(/No se pudo abrir el aviso emergente/)).toBeVisible()
    expect(screen.getByText('Otros pendientes confirmados')).toBeVisible()
    const foto = avisosFixture()
    foto.avisos_habilitados = false
    foto.alertas[0]!.puede_presentar = false
    dobles.datos = foto
    vista.rerender(<GestionDiariaAvisosProvider><AvisosEquipo /></GestionDiariaAvisosProvider>)
    await act(async () => { fireEvent.click(screen.getByRole('button', { name: 'Actualizar avisos' })) })
    expect(screen.queryByText(/No se pudo abrir el aviso emergente/)).not.toBeInTheDocument()
    expect(screen.getByText(/Gerencia ha pausado/)).toBeVisible()
    expect(screen.getByText('Otros pendientes confirmados')).toBeVisible()
  })
  it('retira el popup al cerrar la jornada aunque el siguiente refresco aún no llegue', async () => {
    const foto = avisosFixture()
    foto.generado_en = '2026-09-22T22:59:55Z'
    dobles.datos = foto
    dobles.presentar.mockResolvedValue(foto.alertas[0])
    montar()
    await avanzar()
    expect(screen.getByRole('dialog')).toBeVisible()
    await avanzar(3000)
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(dobles.actuar).not.toHaveBeenCalled()
  })
  it('retira el popup si pasan 90 segundos sin confirmar datos frescos', async () => {
    montar()
    await avanzar()
    expect(screen.getByRole('dialog')).toBeVisible()
    await avanzar(90_000)
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })
  it('espera a terminar de escribir, reclama la entrega y no reconoce al cerrar', async () => {
    montar()
    screen.getByRole('textbox').focus()
    fireEvent.input(screen.getByRole('textbox'), { target: { value: 'Nota en curso' } })
    await avanzar()
    expect(dobles.presentar).not.toHaveBeenCalled()
    screen.getByRole('button', { name: 'Terminar nota' }).focus()
    await avanzar()
    expect(screen.getByRole('dialog')).toHaveAccessibleName('Primer corte de llamadas')
    expect(screen.getByText('Analista de prueba')).toBeVisible()
    fireEvent.click(screen.getByRole('button', { name: 'Cerrar sin reconocer' }))
    await avanzar()
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(dobles.presentar).toHaveBeenCalledOnce()
    expect(dobles.actuar).not.toHaveBeenCalled()
  })
  it('espera mientras existe otro diálogo', async () => {
    montar()
    const otro = document.createElement('div')
    otro.setAttribute('role', 'dialog')
    document.body.append(otro)
    await avanzar()
    expect(dobles.presentar).not.toHaveBeenCalled()
    otro.remove()
    await avanzar()
    expect(dobles.presentar).toHaveBeenCalledOnce()
  })
  it('otra sesión que ya reclamó la entrega impide el popup local', async () => {
    dobles.presentar.mockResolvedValue(null)
    montar()
    await avanzar()
    expect(dobles.refetch).toHaveBeenCalledOnce()
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })
  it('no presenta si se reconoce desde otro dispositivo durante la petición', async () => {
    dobles.refetch.mockImplementation(async () => {
      const actualizado = avisosFixture()
      actualizado.alertas[0]!.estado = 'reconocido'
      return { data: actualizado, error: null }
    })
    montar()
    await avanzar()
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })
  it('un resultado ambiguo reintenta con la misma clave de entrega', async () => {
    dobles.presentar.mockRejectedValueOnce(new Error('Respuesta perdida'))
    montar()
    await avanzar()
    await avanzar(31_000)
    expect(dobles.presentar).toHaveBeenCalledTimes(2)
    expect(dobles.presentar.mock.calls[1]).toEqual(dobles.presentar.mock.calls[0])
    expect(screen.getByRole('dialog')).toBeVisible()
  })
  it('recupera su reserva si se abre un editor durante la petición, sin reclamar otra entrega', async () => {
    let resolver!: (value: ReturnType<typeof avisosFixture>['alertas'][number]) => void
    dobles.presentar.mockImplementationOnce(() => new Promise((resolve) => { resolver = resolve }))
    dobles.refetch.mockImplementation(async () => {
      const foto = avisosFixture()
      foto.alertas[0]!.puede_presentar = false
      dobles.datos = foto
      return { data: foto, error: null }
    })
    const vista = montar()
    await avanzar()
    screen.getByRole('textbox').focus()
    await act(async () => { resolver(avisosFixture().alertas[0]!); await Promise.resolve() })
    vista.rerender(<GestionDiariaAvisosProvider><label>Escribir nota<textarea /></label><button>Terminar nota</button></GestionDiariaAvisosProvider>)
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    screen.getByRole('button', { name: 'Terminar nota' }).focus()
    await avanzar()
    expect(dobles.presentar.mock.calls[1]).toEqual(dobles.presentar.mock.calls[0])
    expect(screen.getByRole('dialog')).toBeVisible()
  })
  it('un fallo al reconocer conserva el popup y reintenta la misma solicitud', async () => {
    dobles.actuar.mockRejectedValueOnce(new Error('Sin conexión'))
    montar()
    await avanzar()
    await act(async () => { fireEvent.click(screen.getByRole('button', { name: 'Lo estoy atendiendo' })) })
    expect(screen.getByRole('alert')).toBeVisible()
    expect(screen.getByRole('dialog')).toBeVisible()
    await act(async () => { fireEvent.click(screen.getByRole('button', { name: 'Lo estoy atendiendo' })) })
    expect(dobles.actuar.mock.calls[1]).toEqual(dobles.actuar.mock.calls[0])
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })
  it('un error de actualización retira la foto antigua', async () => {
    const vista = montar()
    await avanzar()
    dobles.error = new Error('Permiso revocado')
    vista.rerender(<GestionDiariaAvisosProvider><button>Inicio</button></GestionDiariaAvisosProvider>)
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })
})
