import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import type { DetalleCierresCoordinacion } from '@/lib/conversion-cierres-coordinacion'
import { ConversionCierresCoordinacion } from './conversion-cierres-coordinacion'

const { cargar } = vi.hoisted(() => ({ cargar: vi.fn() }))
vi.mock('@/data/crm-api', () => ({ conversionCierresCoordinacion: cargar }))
const id = '20000000-0000-4000-8000-000000000001'
const consulta = { modo: 'mes' as const, mes: '2026-10' }
const props = { analista: { analista_id: id, nombre: 'ANALISTA UNO' }, consulta, desde: '2026-10-01', hasta: '2026-10-31', onCerrar: vi.fn() }
const fila = { nombre: 'CLIENTE REFERIDO MANUAL', origen: 'referido', fecha: '2026-10-01', registro: 'manual' as const, aporte: 1 }
const respuesta = (cambio: Partial<DetalleCierresCoordinacion> = {}): DetalleCierresCoordinacion => ({
  version: 1, analista_id: id, desde: props.desde, hasta: props.hasta, disponible: true,
  total: 2, pagina: 0, por_pagina: 20, filas: [fila, { nombre: 'CLIENTE FORMULARIO', origen: 'formulario', fecha: '2026-10-07', registro: 'sistema', aporte: 1 }], ...cambio,
})
beforeEach(() => { cargar.mockReset(); cargar.mockResolvedValue(respuesta()); props.onCerrar.mockClear() })

describe('detalle de cierres de Coordinación', () => {
  it('muestra referido manual y formulario automático con fecha y aporte, sin enlace a ficha', async () => {
    render(<ConversionCierresCoordinacion {...props} />)
    expect(await screen.findByText('CLIENTE REFERIDO MANUAL')).toBeVisible()
    expect(screen.getByText('Registro manual')).toBeVisible()
    expect(screen.getByText('Referido · 01/10/2026')).toBeVisible()
    expect(screen.getByText('CLIENTE FORMULARIO')).toBeVisible()
    expect(screen.getByText('Registro del sistema')).toBeVisible()
    expect(screen.queryByRole('link')).not.toBeInTheDocument()
    expect(cargar).toHaveBeenCalledWith(id, consulta, 0, expect.any(AbortSignal))
  })
  it('declara que la foto sellada no conserva clientes', async () => {
    cargar.mockResolvedValue(respuesta({ disponible: false, total: 0, filas: [] }))
    render(<ConversionCierresCoordinacion {...props} />)
    expect(await screen.findByText(/Su foto conserva las cifras/)).toBeVisible()
    expect(screen.queryByRole('list')).not.toBeInTheDocument()
  })
  it('muestra el vacío real sin fabricar cierres', async () => {
    cargar.mockResolvedValue(respuesta({ total: 0, filas: [] }))
    render(<ConversionCierresCoordinacion {...props} />)
    expect(await screen.findByText(/No hay cierres acreditados/)).toBeVisible()
  })
  it('permite reintentar un fallo y enfoca el resultado', async () => {
    cargar.mockRejectedValueOnce(new Error('No se pudieron cargar los cierres.'))
    render(<ConversionCierresCoordinacion {...props} />)
    await userEvent.click(await screen.findByRole('button', { name: /Reintentar/ }))
    expect(await screen.findByText('CLIENTE REFERIDO MANUAL')).toBeVisible()
    await waitFor(() => expect(document.activeElement).toContainElement(screen.getByText('CLIENTE REFERIDO MANUAL')))
  })
  it('pagina sin acumular clientes ni cambiar de analista', async () => {
    cargar.mockResolvedValueOnce(respuesta({ total: 21, filas: Array.from({ length: 20 }, (_, n) => ({ ...fila, nombre: `CIERRE ${n}` })) }))
    cargar.mockResolvedValueOnce(respuesta({ total: 21, pagina: 1, filas: [{ ...fila, nombre: 'ULTIMO CIERRE' }] }))
    render(<ConversionCierresCoordinacion {...props} />)
    await userEvent.click(await screen.findByRole('button', { name: 'Siguiente' }))
    expect(await screen.findByText('ULTIMO CIERRE')).toBeVisible()
    expect(screen.queryByText('CIERRE 0')).not.toBeInTheDocument()
    expect(cargar).toHaveBeenLastCalledWith(id, consulta, 1, expect.any(AbortSignal))
  })
  it('aborta la consulta al desmontar e ignora su respuesta tardía', async () => {
    let resolver!: (valor: DetalleCierresCoordinacion) => void
    cargar.mockReturnValue(new Promise((resolve) => { resolver = resolve }))
    const { unmount } = render(<ConversionCierresCoordinacion {...props} />)
    const signal = cargar.mock.calls[0]![3] as AbortSignal
    unmount()
    expect(signal.aborted).toBe(true)
    resolver(respuesta())
    expect(screen.queryByText('CLIENTE REFERIDO MANUAL')).not.toBeInTheDocument()
  })
})
