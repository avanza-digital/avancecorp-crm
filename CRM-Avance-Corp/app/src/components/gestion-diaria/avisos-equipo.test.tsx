import { beforeEach, describe, expect, it, vi } from 'vitest'
import { act, fireEvent, render, screen, within, waitFor } from '@testing-library/react'
import * as v from 'valibot'
import { GestionDiariaAvisosContext, type AvisosGestionDiaria } from '@/lib/gestion-diaria-avisos-context'
import { AlertasCRMContext, type EstadoAlertasCRM } from '@/lib/alertas-context'
import { alertaDiariaAAlertaCRM } from '@/lib/gestion-diaria-alertas'
import { DiaEquipoSchema } from '@/lib/gestion-diaria-equipo'
import { AvisosCortesSchema } from '@/lib/gestion-diaria-avisos'
import { idH4, jornadaH4 } from '@/lib/gestion-diaria-h4.fixture'
import type { DiaEquipoHook } from '@/data/gestion-diaria-equipo-queries'
import { AvisosEquipo } from './avisos-equipo'
import { FranjaCortesSupervisor } from './franja-cortes-supervisor'

let contexto: AvisosGestionDiaria, otros: EstadoAlertasCRM, consulta: DiaEquipoHook
const abrir = vi.fn(), navegar = vi.fn()
function Vista() {
  return <GestionDiariaAvisosContext.Provider value={contexto}><AlertasCRMContext.Provider value={otros}>
    <FranjaCortesSupervisor consulta={consulta} abrir={abrir} />
    <AvisosEquipo consulta={consulta} abrirAnalista={abrir} alNavegar={navegar} />
  </AlertasCRMContext.Provider></GestionDiariaAvisosContext.Provider>
}
beforeEach(() => {
  vi.clearAllMocks()
  const f = jornadaH4()
  expect(v.safeParse(DiaEquipoSchema, f.equipo).success).toBe(true)
  expect(v.safeParse(AvisosCortesSchema, f.avisos).success).toBe(true)
  contexto = { datos: f.avisos, error: null, cargando: false, ocupada: false, registroPedido: null,
    actuar: vi.fn(), recargar: vi.fn(), abrirRegistro: vi.fn(), consumirRegistro: vi.fn() }
  otros = { alertas: f.avisos.diarias!.alertas.map((g) => alertaDiariaAAlertaCRM(g, f.avisos.supervisor_id)),
    pendientes: 1, pospuestas: 0, rol: 'supervisor', cargando: false, errores: [], generadoEn: f.avisos.generado_en,
    reintentar: vi.fn(), reconocer: vi.fn() }
  consulta = { dia: f.equipo, cargando: false, enVuelo: false, error: null, recargar: vi.fn() }
})
describe('H4: cortes y otros avisos conectados', () => {
  it('H5: sesión sin avisos disponibles no presenta un fallo ni un reintento inútil', () => {
    contexto = { ...contexto, datos: null, error: null, cargando: false }
    render(<Vista />)
    fireEvent.click(screen.getByRole('tab', { name: 'Otros pendientes' }))
    expect(screen.getByText('Los otros pendientes no están disponibles en esta sesión.')).toBeVisible()
    expect(screen.queryByText(/No pudimos confirmar/)).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Actualizar otros pendientes' })).not.toBeInTheDocument()
  })
  it('H5: la carga inicial de otros pendientes no ofrece un reintento', () => {
    contexto = { ...contexto, datos: null, error: null, cargando: true }
    render(<Vista />)
    fireEvent.click(screen.getByRole('tab', { name: 'Otros pendientes' }))
    expect(screen.getByText('Consultando otros pendientes del equipo…')).toBeVisible()
    expect(screen.queryByRole('button', { name: 'Actualizar otros pendientes' })).not.toBeInTheDocument()
  })
  it('franja muestra primer corte evaluado y segundo programado; cifras/personas bajo demanda', () => {
    render(<Vista />)
    const franja = screen.getByRole('region', { name: 'Estado de cortes y avisos' })
    expect(franja).toHaveTextContent('11:30 Evaluado · 1 bajo el mínimo')
    expect(franja).toHaveTextContent('16:00 Programado')
    expect(franja).toHaveTextContent('Otros sin reconocer: 1')
    fireEvent.click(within(franja).getByRole('button', { name: 'Cortes y avisos' })); expect(abrir).toHaveBeenCalledOnce()
    const resultados = screen.getByRole('region', { name: 'Resultados de los cortes' })
    const primer = resultados.querySelector('details')!
    expect(primer).not.toHaveAttribute('open')
    fireEvent.click(primer.querySelector('summary')!)
    expect(primer).toHaveAttribute('open')
    expect(primer).toHaveTextContent('1 cumplidos · 1 recuperados · 1 sin cartera abierta')
    expect(primer).toHaveTextContent('Recuperado · 1 llamadas al corte · mínimo 3 · 4 en recuperación')
    fireEvent.click(within(primer).getByRole('button', { name: 'Ver llamadas de CARLA H4' }))
    expect(abrir).toHaveBeenLastCalledWith(idH4(4))
  })
  it.each(['desactivados', 'no_laborable'] as const)('%s procede de la política, sin horarios inventados', (estado) => {
    consulta.dia!.cortes = { ...consulta.dia!.cortes!, estado, equipo: [], inicio_jornada: null, fin_jornada: null, primer_corte_en: null, segundo_corte_en: null }
    contexto.datos = { ...contexto.datos!, estado_cortes: estado, alertas: [] }
    render(<Vista />)
    const franja = screen.getByRole('region', { name: 'Estado de cortes y avisos' })
    expect(franja).toHaveTextContent(estado === 'desactivados' ? 'Cortes desactivados' : 'Día no laborable')
    expect(franja).not.toHaveTextContent('11:30')
    expect(screen.queryByText(/No hay cortes con pendientes/)).not.toBeInTheDocument()
  })
  it('sábado conserva un corte, fin de jornada y mínimo recibidos', () => {
    const c = consulta.dia!.cortes!
    c.segundo_corte_en = null; c.fin_jornada = '2026-09-24T13:00:00-05:00'
    c.equipo.forEach((p) => { p.segundo_corte = null })
    render(<Vista />)
    expect(screen.getByText(/Jornada de 09:00 a 13:00. Un corte previsto/)).toBeVisible()
    expect(screen.queryByText('Segundo corte · 16:00')).not.toBeInTheDocument()
  })
  it('ausencia del contrato no se presenta como desactivado o cero', () => {
    delete consulta.dia!.cortes; render(<Vista />)
    expect(screen.getByRole('region', { name: 'Estado de cortes y avisos' })).toHaveTextContent('Sin detalle de cortes')
    expect(screen.getByText(/Esto no confirma que estén desactivados/)).toBeVisible()
  })
  it('error del resumen conserva los avisos autorizados y sus acciones', () => {
    consulta.error = new Error('red'); render(<Vista />)
    expect(screen.getByRole('region', { name: 'Estado de cortes y avisos' })).toHaveTextContent('Cortes no disponibles')
    fireEvent.click(screen.getByRole('button', { name: 'Actualizar cortes' })); expect(consulta.recargar).toHaveBeenCalledOnce()
    fireEvent.click(screen.getByRole('button', { name: 'Ver registro de ANA H4' }))
    expect(contexto.abrirRegistro).toHaveBeenCalledWith(contexto.datos!.alertas[0], idH4(2))
  })
  it('error de avisos mantiene resultados de cortes y muestra el fallo de otros pendientes', () => {
    contexto = { ...contexto, datos: null, error: new Error('revocado') }; render(<Vista />)
    expect(screen.getByRole('region', { name: 'Resultados de los cortes' })).toBeVisible()
    expect(screen.queryByRole('button', { name: 'Lo estoy atendiendo' })).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('tab', { name: 'Otros pendientes' }))
    expect(screen.getByText(/No pudimos confirmar los otros pendientes/)).toBeVisible()
    expect(screen.queryByText(/No hay otros avisos visibles/)).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Actualizar otros pendientes' })); expect(otros.reintentar).toHaveBeenCalledOnce()
  })
  it('lista accesible al fallar popup; pausa del canal no retira resultados', () => {
    contexto.errorPresentacion = new Error('red'); contexto.datos!.avisos_habilitados = false
    contexto.datos!.alertas[0]!.puede_posponer = false; render(<Vista />)
    expect(screen.getByText(/Puedes atender los pendientes desde esta lista/)).toBeVisible()
    expect(screen.getByText(/Gerencia ha pausado/)).toBeVisible()
    expect(screen.queryByRole('button', { name: 'Posponer 1 hora' })).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Lo estoy atendiendo' })).toBeEnabled()
  })
  it('acción espera confirmación, no se repite y conserva el error para reintentar', async () => {
    let resolver!: () => void
    vi.mocked(contexto.actuar).mockImplementationOnce(() => new Promise((r) => { resolver = r }))
    const vista = render(<Vista />)
    const boton = screen.getByRole('button', { name: 'Posponer 1 hora' }); boton.focus(); fireEvent.click(boton); fireEvent.click(boton)
    expect(contexto.actuar).toHaveBeenCalledTimes(1)
    expect(screen.getByText('Confirmando en el servidor…')).toBeVisible()
    const aviso = contexto.datos!.alertas[0]!
    aviso.estado = 'pospuesto'; aviso.puede_posponer = false; aviso.pospuesto_hasta = '2026-09-24T13:00:00-05:00'
    vista.rerender(<Vista />)
    await act(async () => { resolver() })
    await waitFor(() => expect(screen.getByText(/Pospuesto hasta las 13:00/)).toHaveFocus())
    expect(screen.queryByRole('button', { name: 'Posponer 1 hora' })).not.toBeInTheDocument()
    vi.mocked(contexto.actuar).mockRejectedValueOnce(new Error('red'))
    const reconocer = screen.getByRole('button', { name: 'Lo estoy atendiendo' }); reconocer.focus(); fireEvent.click(reconocer)
    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('No se pudo confirmar'))
    expect(reconocer).toHaveFocus(); expect(reconocer).toBeEnabled()
  })
  it('reconocimiento confirmado desde otra sesión conserva el resultado y retira acciones', () => {
    const vista = render(<Vista />); const aviso = contexto.datos!.alertas[0]!
    aviso.estado = 'reconocido'; aviso.reconocido_en = contexto.datos!.generado_en
    vista.rerender(<Vista />)
    expect(screen.getByText(/Reconocido; el resultado del corte se conserva/)).toBeVisible()
    expect(screen.queryByRole('button', { name: 'Lo estoy atendiendo' })).not.toBeInTheDocument()
  })
  it('otros avisos mantienen errores, pospuestos, navegación y la misma lista de la campana', () => {
    otros.pospuestas = 2; render(<Vista />)
    fireEvent.click(screen.getByRole('tab', { name: 'Otros pendientes' }))
    expect(screen.getByText('Tareas vencidas · 1')).toBeVisible()
    expect(screen.getByText(/2 avisos pospuestos/)).toBeVisible()
    fireEvent.click(screen.getByRole('button', { name: 'Ver pendientes' }))
    expect(navegar).toHaveBeenCalledOnce(); expect(window.location.hash).toBe('#/seguimiento')
  })
  it('un error del libro no se convierte en vacío confirmado', () => {
    otros.alertas = []; otros.errores = ['No se pudo consultar el libro.']; render(<Vista />)
    fireEvent.click(screen.getByRole('tab', { name: 'Otros pendientes' }))
    expect(screen.getByRole('alert')).toHaveTextContent('No se pudo consultar el libro')
    expect(screen.queryByText(/No hay otros avisos visibles/)).not.toBeInTheDocument()
  })
  it('sin detalle diario opcional conserva los pendientes compartidos con campana', () => {
    delete contexto.datos!.diarias; delete contexto.datos!.contexto
    delete otros.alertas[0]!.diaria
    render(<Vista />)
    expect(screen.getByRole('region', { name: 'Estado de cortes y avisos' })).toHaveTextContent('Otros sin reconocer: 1')
    fireEvent.click(screen.getByRole('tab', { name: 'Otros pendientes' }))
    expect(screen.getByText('Tareas vencidas · 1')).toBeVisible()
    expect(screen.queryByText(/No pudimos confirmar los otros pendientes/)).not.toBeInTheDocument()
    expect(screen.queryByText(/Han registrado llamadas/)).not.toBeInTheDocument()
  })
  it('mantiene el contador confirmado durante refresco; un error lo retira', () => {
    const vista = render(<Vista />)
    otros = { ...otros, cargando: true }
    vista.rerender(<Vista />)
    const franja = screen.getByRole('region', { name: 'Estado de cortes y avisos' })
    expect(franja).toHaveTextContent('Otros sin reconocer: 1')
    expect(franja).not.toHaveTextContent('Actualizando otros avisos')
    otros = { ...otros, cargando: false, errores: ['Libro sin confirmar'] }
    vista.rerender(<Vista />)
    expect(franja).toHaveTextContent('Otros avisos sin confirmar')
    expect(franja).not.toHaveTextContent('Otros sin reconocer: 1')
  })
})
