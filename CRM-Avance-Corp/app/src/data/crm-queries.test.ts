// Pineo del CONTRATO entre hooks e invalidaciones: la clave con la que
// useContratos/useClientes registran su query DEBE ser exactamente
// crmQueryKeys.contratos()/clientes(), porque la pantalla Clientes invalida con
// esas claves tras crear un contrato. Una clave desalineada NO falla ruidoso:
// solo deja data vieja en silencio — por eso se pinea aquí (y el flujo cruzado
// completo se cubre en e2e/contratos.spec.ts).
import { createElement, type ReactNode } from 'react'
import { renderHook } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { describe, expect, it } from 'vitest'
import {
  crmQueryKeys,
  INTERVALO_REVALIDACION_CARTERA_MS,
  useActividadesCliente,
  useClienteDetalle,
  useClienteFichaComercial,
  useClientes,
  useCronograma,
  useContrato,
  useContratos,
  useCuentasBancariasCliente,
  useOperacionesCartera,
  useTitulares,
} from './crm-queries'

/** QueryClient limpio por test + wrapper del provider (sin red: ver abajo). */
function arnes() {
  const cliente = new QueryClient()
  const wrapper = ({ children }: { children: ReactNode }) =>
    createElement(QueryClientProvider, { client: cliente }, children)
  return { cliente, wrapper }
}

describe('claves de la caché de cartera (contrato con las invalidaciones)', () => {
  it('crmQueryKeys.contratos()/clientes() son las claves literales pactadas', () => {
    // Literales A PROPÓSITO: cambiar la forma de la clave rompe a quien invalida.
    expect(crmQueryKeys.contratos()).toEqual(['crm', 'contratos'])
    expect(crmQueryKeys.clientes()).toEqual(['crm', 'clientes'])
  })

  it('useContratos registra su query EXACTAMENTE bajo crmQueryKeys.contratos()', () => {
    const { cliente, wrapper } = arnes()
    // habilitada=false (el modo demo real): la query queda registrada en la
    // caché SIN disparar ningún fetch — justo lo que este pineo necesita.
    renderHook(() => useContratos(false), { wrapper })
    const query = cliente.getQueryCache().find({ queryKey: crmQueryKeys.contratos(), exact: true })
    const opciones = query?.options as {
      refetchInterval?: number
      refetchIntervalInBackground?: boolean
    }
    expect(query).toBeDefined()
    expect(opciones.refetchInterval).toBe(INTERVALO_REVALIDACION_CARTERA_MS)
    expect(opciones.refetchIntervalInBackground).toBe(false)
    expect(
      cliente
        .getQueryCache()
        .getAll()
        .map((q) => q.queryKey),
    ).toEqual([['crm', 'contratos']])
  })

  it('useClientes registra su query EXACTAMENTE bajo crmQueryKeys.clientes()', () => {
    const { cliente, wrapper } = arnes()
    renderHook(() => useClientes(false), { wrapper })
    expect(cliente.getQueryCache().find({ queryKey: crmQueryKeys.clientes(), exact: true })).toBeDefined()
    expect(
      cliente
        .getQueryCache()
        .getAll()
        .map((q) => q.queryKey),
    ).toEqual([['crm', 'clientes']])
  })

  it('renovaciones y aumentos se vuelven a confirmar cada minuto mientras la cartera está abierta', () => {
    const { cliente, wrapper } = arnes()
    renderHook(() => useOperacionesCartera(false), { wrapper })
    const query = cliente.getQueryCache().find({ queryKey: crmQueryKeys.operacionesCartera(), exact: true })
    const opciones = query?.options as {
      refetchInterval?: number
      refetchIntervalInBackground?: boolean
    }

    expect(query).toBeDefined()
    expect(opciones.refetchInterval).toBe(INTERVALO_REVALIDACION_CARTERA_MS)
    expect(opciones.refetchIntervalInBackground).toBe(false)
  })

  // Las claves de detalle cuelgan del PREFIJO de su lista a propósito: la
  // invalidación jerárquica de contratos() tras corregir cubre lista +
  // cronograma + titulares de una pasada (el wrapper de actualizar_contrato REGENERA el
  // cronograma y puede reemplazar co-titulares) — pineadas como literales.
  it('cronograma/titulares/fichas/detalle/cuentas viven bajo el prefijo de su lista', () => {
    expect(crmQueryKeys.cronograma('ct-1')).toEqual(['crm', 'contratos', 'ct-1', 'cronograma'])
    expect(crmQueryKeys.titulares('ct-1')).toEqual(['crm', 'contratos', 'ct-1', 'titulares'])
    expect(crmQueryKeys.clienteFichaComercial('cli-1')).toEqual(['crm', 'clientes', 'cli-1', 'ficha-comercial'])
    expect(crmQueryKeys.clienteDetalle('cli-1')).toEqual(['crm', 'clientes', 'cli-1', 'detalle'])
    expect(crmQueryKeys.cuentasBancarias('cli-1', 'USD')).toEqual([
      'crm',
      'clientes',
      'cli-1',
      'cuentas-bancarias',
      'USD',
    ])
  })

  it('useClienteFichaComercial registra una caché propia y no reutiliza el detalle de Corregir', () => {
    const { cliente, wrapper } = arnes()
    renderHook(() => useClienteFichaComercial('cli-1', false), { wrapper })

    expect(
      cliente
        .getQueryCache()
        .getAll()
        .map((q) => q.queryKey),
    ).toEqual([['crm', 'clientes', 'cli-1', 'ficha-comercial']])
    expect(
      cliente.getQueryCache().find({ queryKey: crmQueryKeys.clienteDetalle('cli-1'), exact: true }),
    ).toBeUndefined()
    expect(INTERVALO_REVALIDACION_CARTERA_MS).toBe(60_000)
  })

  it('purga inmediatamente los datos sensibles al desmontar', () => {
    const { cliente, wrapper } = arnes()
    renderHook(() => useClienteDetalle('cli-1', false), { wrapper })
    renderHook(() => useActividadesCliente('cli-1', false), { wrapper })
    renderHook(() => useCuentasBancariasCliente('cli-1', 'PEN', false), { wrapper })
    renderHook(() => useCronograma('ct-1', false), { wrapper })
    renderHook(() => useTitulares('ct-1', false), { wrapper })

    expect(
      cliente.getQueryCache().find({ queryKey: crmQueryKeys.clienteDetalle('cli-1'), exact: true })?.options.gcTime,
    ).toBe(0)
    expect(
      cliente.getQueryCache().find({ queryKey: crmQueryKeys.actividadesCliente('cli-1'), exact: true }),
    ).toBeDefined()
    const cuentas = cliente.getQueryCache().find({
      queryKey: crmQueryKeys.cuentasBancarias('cli-1', 'PEN'),
      exact: true,
    })
    expect(cuentas?.options.gcTime).toBe(0)
    expect(
      cliente.getQueryCache().find({ queryKey: crmQueryKeys.cronograma('ct-1'), exact: true })?.options.gcTime,
    ).toBe(0)
    expect(
      cliente.getQueryCache().find({ queryKey: crmQueryKeys.titulares('ct-1'), exact: true })?.options.gcTime,
    ).toBe(0)
  })

  // Las métricas del ÁMBITO OPERATIVO (F1/F1b) cuelgan de su propio prefijo:
  // el puente transitorio del store y la pantalla de reparto invalidan POR
  // PREFIJO, así que la forma literal de la clave es contrato, no detalle.
  it('las métricas del ámbito operativo cuelgan de metricas-ambito', () => {
    expect(crmQueryKeys.metricasAmbito()).toEqual(['crm', 'metricas-ambito'])
    expect(crmQueryKeys.resumenCartera()).toEqual(['crm', 'metricas-ambito', 'resumen-cartera'])
    expect(crmQueryKeys.metricasVendedores()).toEqual(['crm', 'metricas-ambito', 'metricas-vendedores'])
    expect(crmQueryKeys.resumenReparto()).toEqual(['crm', 'metricas-ambito', 'resumen-reparto'])
  })

  it('useContrato NO inventa clave: registra bajo crmQueryKeys.contratos() (select por id)', () => {
    const { cliente, wrapper } = arnes()
    renderHook(() => useContrato('ct-1', false), { wrapper })
    // La misma clave que la tabla: abrir el detalle no duplica la lista en
    // caché y cualquier invalidación de contratos() lo refresca también.
    expect(
      cliente
        .getQueryCache()
        .getAll()
        .map((q) => q.queryKey),
    ).toEqual([['crm', 'contratos']])
  })
})
