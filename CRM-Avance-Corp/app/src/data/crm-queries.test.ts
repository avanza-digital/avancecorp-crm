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
  useResumenCarteraClientes,
} from './crm-queries'

/** QueryClient limpio por test + wrapper del provider (sin red: ver abajo). */
function arnes() {
  const cliente = new QueryClient()
  const wrapper = ({ children }: { children: ReactNode }) =>
    createElement(QueryClientProvider, { client: cliente }, children)
  return { cliente, wrapper }
}

describe('claves de la caché de cartera (contrato con las invalidaciones)', () => {
  it('el resumen financiero separa actor, no consulta en demo y caduca con métricas', async () => {
    const { cliente, wrapper } = arnes()
    renderHook(() => useResumenCarteraClientes(false, 'gerencia-1'), { wrapper })
    const clave = crmQueryKeys.resumenCarteraClientes('gerencia-1')
    expect(clave).not.toEqual(crmQueryKeys.resumenCarteraClientes('gerencia-2'))
    expect(clave).toEqual(['crm', 'metricas', 'cartera-clientes', 'gerencia-1'])
    expect(cliente.getQueryState(clave)?.fetchStatus).toBe('idle')
    await cliente.invalidateQueries({ queryKey: crmQueryKeys.metricas() })
    expect(cliente.getQueryState(clave)?.isInvalidated).toBe(true)
  })
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

  // Pipeline, 01/10/2026: «Nuevo» y «Gestionado» son la MISMA etapa y el mismo
  // analista. Si la gestión no formara parte de la clave compartirían caché y
  // las dos columnas pintarían la misma lista. Y las dos cuelgan de leads():
  // es el prefijo que el store invalida tras cada mutación, y por eso un
  // intento registrado mueve la tarjeta de una columna a la otra sin recargar.
  it('la gestión separa la caché de «Nuevo» y «Gestionado», y las dos caducan con leads()', async () => {
    const nuevo = crmQueryKeys.carteraPagina('nuevo', 'v-1', '', true, null, null, 'todos', 'todas', false, 'sin_gestion')
    const gestionado = crmQueryKeys.carteraPagina('nuevo', 'v-1', '', true, null, null, 'todos', 'todas', false, 'con_gestion')
    const etapaEntera = crmQueryKeys.carteraPagina('nuevo', 'v-1', '', true)

    // Literal A PROPÓSITO: el penúltimo componente es la gestión y el último el
    // potencial (Leads); `null` = sin recorte.
    expect(gestionado).toEqual([
      'crm', 'leads', 'cartera-pagina', 'nuevo', 'v-1', '', true, null, null, 'todos', 'todas', false, 'con_gestion', null,
    ])
    expect(etapaEntera.at(-2)).toBeNull()
    expect(etapaEntera.at(-1)).toBeNull()
    expect(new Set([nuevo, gestionado, etapaEntera].map((clave) => JSON.stringify(clave))).size).toBe(3)

    const { cliente } = arnes()
    for (const clave of [nuevo, gestionado, etapaEntera]) cliente.setQueryData(clave, { pages: [], pageParams: [] })
    await cliente.invalidateQueries({ queryKey: crmQueryKeys.leads() })
    for (const clave of [nuevo, gestionado, etapaEntera]) expect(cliente.getQueryState(clave)?.isInvalidated).toBe(true)
  })

  // Leads, 01/10/2026: filtrar por potencial es otra lista. Sin el potencial en
  // la clave, elegir «Tibio» serviría de caché la lista sin filtro.
  it('el potencial separa la caché de cada nivel y de la lista sin filtro', () => {
    const base = ['todas', 'todos', '', true, null, null, 'todos', 'todas', false, null] as const
    const sinFiltro = crmQueryKeys.carteraPagina(...base)
    const claves = [sinFiltro, ...(['frio', 'tibio', 'estrella', 'sin_marca'] as const).map((p) => crmQueryKeys.carteraPagina(...base, p))]
    expect(new Set(claves.map((clave) => JSON.stringify(clave))).size).toBe(5)
    expect(crmQueryKeys.carteraPagina(...base, 'tibio').at(-1)).toBe('tibio')
    expect(sinFiltro.at(-1)).toBeNull()
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
