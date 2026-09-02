// Pineo del CONTRATO entre hooks e invalidaciones: la clave con la que
// useContratos/useClientes registran su query DEBE ser exactamente
// crmQueryKeys.contratos()/clientes(), porque la pantalla Clientes invalida con
// esas claves tras crear un contrato. Una clave desalineada NO falla ruidoso:
// solo deja data vieja en silencio — por eso se pinea aquí (y el flujo cruzado
// completo se cubre en e2e/contratos.spec.ts).
import { createElement, type ReactNode } from 'react'
import { act, renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { describe, expect, it, vi } from 'vitest'
import {
  crmQueryKeys,
  useClientes,
  useContrato,
  useContratos,
  useConversionMensual,
  useCierreMesEstado,
  useMetricasConversionesEquipo,
  useMetricasVendedores,
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
    expect(cliente.getQueryCache().find({ queryKey: crmQueryKeys.contratos(), exact: true })).toBeDefined()
    expect(cliente.getQueryCache().getAll().map((q) => q.queryKey)).toEqual([['crm', 'contratos']])
  })

  it('useClientes registra su query EXACTAMENTE bajo crmQueryKeys.clientes()', () => {
    const { cliente, wrapper } = arnes()
    renderHook(() => useClientes(false), { wrapper })
    expect(cliente.getQueryCache().find({ queryKey: crmQueryKeys.clientes(), exact: true })).toBeDefined()
    expect(cliente.getQueryCache().getAll().map((q) => q.queryKey)).toEqual([['crm', 'clientes']])
  })

  // Las claves de detalle cuelgan del PREFIJO de su lista a propósito: la
  // invalidación jerárquica de contratos() tras corregir cubre lista +
  // cronograma + titulares de una pasada (el wrapper de actualizar_contrato REGENERA el
  // cronograma y puede reemplazar co-titulares) — pineadas como literales.
  it('cronograma/titulares/detalle/cuentas viven bajo el prefijo de su lista', () => {
    expect(crmQueryKeys.cronograma('ct-1')).toEqual(['crm', 'contratos', 'ct-1', 'cronograma'])
    expect(crmQueryKeys.titulares('ct-1')).toEqual(['crm', 'contratos', 'ct-1', 'titulares'])
    expect(crmQueryKeys.clienteDetalle('cli-1')).toEqual(['crm', 'clientes', 'cli-1', 'detalle'])
    expect(crmQueryKeys.cuentasBancarias('cli-1', 'USD')).toEqual([
      'crm', 'clientes', 'cli-1', 'cuentas-bancarias', 'USD',
    ])
  })

  // Las métricas del ÁMBITO OPERATIVO (F1/F1b) cuelgan de su propio prefijo:
  // el puente transitorio del store y la pantalla de reparto invalidan POR
  // PREFIJO, así que la forma literal de la clave es contrato, no detalle.
  it('las métricas del ámbito operativo cuelgan de metricas-ambito', () => {
    expect(crmQueryKeys.metricasAmbito()).toEqual(['crm', 'metricas-ambito'])
    expect(crmQueryKeys.resumenCartera()).toEqual(['crm', 'metricas-ambito', 'resumen-cartera'])
    expect(crmQueryKeys.metricasVendedores('2026-09-01')).toEqual([
      'crm', 'metricas-ambito', 'metricas-vendedores', '2026-09-01',
    ])
    expect(crmQueryKeys.resumenReparto()).toEqual(['crm', 'metricas-ambito', 'resumen-reparto'])
  })

  it('abre una foto operativa nueva cuando cambia el mes calendario', () => {
    const { cliente, wrapper } = arnes()
    const { rerender } = renderHook(
      ({ periodo }) => useMetricasVendedores(false, periodo),
      { initialProps: { periodo: '2026-08-01' }, wrapper },
    )

    rerender({ periodo: '2026-09-01' })

    expect(cliente.getQueryCache().getAll().map((query) => query.queryKey)).toEqual([
      ['crm', 'metricas-ambito', 'metricas-vendedores', '2026-08-01'],
      ['crm', 'metricas-ambito', 'metricas-vendedores', '2026-09-01'],
    ])
  })

  it('las fotos de conversión separan período, alcance y actor', () => {
    expect(crmQueryKeys.conversionMensual('2026-08-01', 'propio', 'v-1')).toEqual([
      'crm', 'metricas', 'conversion-mensual', '2026-08-01', 'propio', 'v-1',
    ])
    expect(crmQueryKeys.conversionMensual('2026-08-01', 'equipo', 's-1')).toEqual([
      'crm', 'metricas', 'conversion-mensual', '2026-08-01', 'equipo', 's-1',
    ])
    expect(crmQueryKeys.conversionMensual('2026-08-01', 'global', 'g-ignorado')).toEqual([
      'crm', 'metricas', 'conversion-mensual', '2026-08-01', 'global', null,
    ])
    expect(crmQueryKeys.metricasConversionesEquipo(
      '2026-08-01',
      '2026-08-31',
      'equipo',
      's-1',
    )).toEqual([
      'crm', 'metricas', 'conversiones-equipo',
      '2026-08-01', '2026-08-31', 'equipo', 's-1',
    ])
  })

  it('agenda y reuniones cuelgan de prefijos invalidables sin borrar otras métricas', () => {
    expect(crmQueryKeys.metricasAgendaPrefijo()).toEqual(['crm', 'metricas', 'agenda-equipo'])
    expect(crmQueryKeys.metricasAgenda('2026-08-01', '2026-08-31')).toEqual([
      'crm', 'metricas', 'agenda-equipo', '2026-08-01', '2026-08-31',
    ])
    expect(crmQueryKeys.metricasReunionesPrefijo()).toEqual(['crm', 'metricas', 'reuniones'])
    expect(crmQueryKeys.metricasReuniones('2026-08-01', '2026-08-31')).toEqual([
      'crm', 'metricas', 'reuniones', '2026-08-01', '2026-08-31',
    ])
  })

  it('los hooks registran exactamente las claves dimensionadas aunque estén deshabilitados', () => {
    const { cliente, wrapper } = arnes()
    renderHook(() => useConversionMensual(false, '2026-08-01', 'propio', 'v-1'), { wrapper })
    renderHook(() => useConversionMensual(false, '2026-08-01', 'global', 'g-1'), { wrapper })
    renderHook(() => useMetricasConversionesEquipo(
      false,
      '2026-08-01',
      '2026-08-31',
      'equipo',
      's-1',
    ), { wrapper })

    expect(cliente.getQueryCache().getAll().map((query) => query.queryKey)).toEqual([
      ['crm', 'metricas', 'conversion-mensual', '2026-08-01', 'propio', 'v-1'],
      ['crm', 'metricas', 'conversion-mensual', '2026-08-01', 'global', null],
      [
        'crm', 'metricas', 'conversiones-equipo',
        '2026-08-01', '2026-08-31', 'equipo', 's-1',
      ],
    ])
  })

  it('al detectar un nuevo mes sellado caduca las tres fotos mensuales abiertas', async () => {
    const cliente = new QueryClient({ defaultOptions: { queries: { staleTime: Infinity } } })
    const invalidar = vi.spyOn(cliente, 'invalidateQueries')
    const wrapper = ({ children }: { children: ReactNode }) =>
      createElement(QueryClientProvider, { client: cliente }, children)
    const claveCumplimiento = crmQueryKeys.cumplimientoMetas('2026-08-01', 'g-1')
    const claveConversion = crmQueryKeys.conversionMensual('2026-08-01', 'global')
    const claveCosecha = crmQueryKeys.metricasConversionesEquipo(
      '2026-08-01', '2026-08-31', 'global',
    )
    const claveReuniones = crmQueryKeys.metricasReuniones('2026-08-01', '2026-08-31')
    const base = {
      version: 1 as const,
      generado_en: '2026-09-10T14:25:00Z',
      hoy: '2026-09-10',
      zona: 'America/Lima' as const,
      mes_en_curso: { mes: '2026-09', mes_nombre: 'setiembre', cierra_el: '2026-10-10' },
      pendiente: null,
    }
    cliente.setQueryData(crmQueryKeys.cierreMesEstado(), {
      ...base,
      ultimo_cerrado: null,
    })
    for (const clave of [claveCumplimiento, claveConversion, claveCosecha, claveReuniones]) {
      cliente.setQueryData(clave, { foto: 'abierta' })
    }
    renderHook(() => useCierreMesEstado(true), { wrapper })

    act(() => {
      cliente.setQueryData(crmQueryKeys.cierreMesEstado(), {
        ...base,
        ultimo_cerrado: {
          mes: '2026-08', mes_nombre: 'agosto', cerrado_en: '2026-09-10T14:20:00Z', automatico: true,
        },
      })
    })

    await waitFor(() => expect(cliente.getQueryState(claveCumplimiento)?.isInvalidated).toBe(true))
    expect(cliente.getQueryState(claveConversion)?.isInvalidated).toBe(true)
    expect(cliente.getQueryState(claveCosecha)?.isInvalidated).toBe(true)
    expect(cliente.getQueryState(claveReuniones)?.isInvalidated).toBe(false)
    const clavesInvalidadas = invalidar.mock.calls.map((llamada) => JSON.stringify(llamada[0]?.queryKey))
    const posicionCosecha = clavesInvalidadas.indexOf(
      JSON.stringify(crmQueryKeys.metricasConversionesEquipoPrefijo()),
    )
    expect(posicionCosecha).toBeGreaterThan(clavesInvalidadas.indexOf(
      JSON.stringify(crmQueryKeys.cumplimientoMetasPrefijo()),
    ))
    expect(posicionCosecha).toBeGreaterThan(clavesInvalidadas.indexOf(
      JSON.stringify(crmQueryKeys.conversionMensualPrefijo()),
    ))
  })

  it('también caduca fotos abiertas si el primer estado observado ya viene sellado', async () => {
    const cliente = new QueryClient({ defaultOptions: { queries: { staleTime: Infinity } } })
    const wrapper = ({ children }: { children: ReactNode }) =>
      createElement(QueryClientProvider, { client: cliente }, children)
    const clave = crmQueryKeys.conversionMensual('2026-08-01', 'global')
    cliente.setQueryData(clave, { foto: 'abierta' })
    cliente.setQueryData(crmQueryKeys.cierreMesEstado(), {
      version: 1,
      generado_en: '2026-09-10T14:25:00Z',
      hoy: '2026-09-10',
      zona: 'America/Lima',
      mes_en_curso: { mes: '2026-09', mes_nombre: 'setiembre', cierra_el: '2026-10-10' },
      pendiente: null,
      ultimo_cerrado: {
        mes: '2026-08', mes_nombre: 'agosto', cerrado_en: '2026-09-10T14:20:00Z', automatico: true,
      },
    })

    renderHook(() => useCierreMesEstado(true), { wrapper })

    await waitFor(() => expect(cliente.getQueryState(clave)?.isInvalidated).toBe(true))
  })

  it('useContrato NO inventa clave: registra bajo crmQueryKeys.contratos() (select por id)', () => {
    const { cliente, wrapper } = arnes()
    renderHook(() => useContrato('ct-1', false), { wrapper })
    // La misma clave que la tabla: abrir el detalle no duplica la lista en
    // caché y cualquier invalidación de contratos() lo refresca también.
    expect(cliente.getQueryCache().getAll().map((q) => q.queryKey)).toEqual([['crm', 'contratos']])
  })
})
