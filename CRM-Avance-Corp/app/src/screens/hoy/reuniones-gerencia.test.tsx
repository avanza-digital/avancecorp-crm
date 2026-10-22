import { fireEvent, render, screen, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { metricasReunionesDemo } from '@/lib/demo-inteligencia-comercial'
import { ReunionesGerenciaPanel } from './reuniones-gerencia'

const opcionesGraficos = vi.hoisted(() => new Map<string, { series: { data: unknown[] }[] }>())
vi.mock('@/components/gerencia/echart-lazy', () => ({
  GerenciaEChart: ({ ariaLabel, option }: { ariaLabel: string; option: { series: { data: unknown[] }[] } }) => {
    opcionesGraficos.set(ariaLabel, option)
    return <div role="img" aria-label={ariaLabel} />
  },
}))

describe('resumen de reuniones de Gerencia', () => {
  it('no mezcla un error inicial con el mensaje de reuniones vacías', () => {
    render(
      <ReunionesGerenciaPanel
        datos={undefined}
        cargando={false}
        error="No se pudieron cargar las reuniones."
        modoDemo={false}
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentar={vi.fn()}
      />,
    )

    expect(screen.getByRole('alert')).toHaveTextContent('No se pudieron cargar las citas.')
    expect(screen.queryByText('Aún no hay citas en este período')).not.toBeInTheDocument()
  })

  it('muestra la asistencia real y no el porcentaje de realización', () => {
    render(
      <ReunionesGerenciaPanel
        datos={metricasReunionesDemo('2026-08-01', '2026-08-31')}
        cargando={false}
        error={null}
        modoDemo={false}
        puedeAlternarEjemplo={false}
        onAlternarEjemplo={vi.fn()}
        onReintentar={vi.fn()}
      />,
    )

    const tarjetaAsistencia = screen.getByText('Asistencia').parentElement
    expect(tarjetaAsistencia).not.toBeNull()
    expect(within(tarjetaAsistencia as HTMLElement).getByText('87.9%')).toBeInTheDocument()
    expect(within(tarjetaAsistencia as HTMLElement).queryByText('79.5%')).not.toBeInTheDocument()
  })

  it('expone cancelaciones de asesor y sistema sin recomponer los totales servidos', () => {
    const datos = metricasReunionesDemo('2026-09-01', '2026-09-04')
    datos.resumen = { ...datos.resumen, pactadas: 28, debieron_ocurrir: 28, realizadas: 5, no_concretadas: 17, no_show: 16, canceladas: 1, canceladas_sistema: 4, reprogramadas: 0, reprogramadas_vencidas: 0, canceladas_sistema_vencidas: 4, divisor_realizacion: 24, divisor_asistencia: 21, pendientes_cierre: 2, programadas_futuras: 0, pct_realizacion: 20.8, pct_asistencia: 23.8 }
    datos.responsables = []
    render(<ReunionesGerenciaPanel datos={datos} cargando={false} error={null} modoDemo={false} puedeAlternarEjemplo={false} onAlternarEjemplo={vi.fn()} onReintentar={vi.fn()} />)

    const sistema = screen.getByText('Canceladas por sistema').parentElement as HTMLElement
    expect(within(sistema).getByText('4')).toBeInTheDocument()
    expect(within(screen.getByText('No asistieron').closest('[data-gi-kpi]') as HTMLElement).getByText('16')).toBeInTheDocument()
    expect(screen.getByText('20.8%')).toBeInTheDocument()
    expect(screen.getByText('23.8%')).toBeInTheDocument()
    expect(screen.getByText(/las pactadas incluyen las canceladas/i)).toBeInTheDocument()
    // El detalle global de la base, con sus separadores («· 4», no «·4»).
    expect(screen.getByText('28 citas vencidas o ya realizadas · 4 canceladas por sistema · 0 reprogramadas.')).toBeInTheDocument()
  })

  it('muestra el porcentaje servido por modalidad sin la fracción de vencidas brutas', () => {
    const datos = metricasReunionesDemo('2026-09-01', '2026-09-04')
    const modalidad = datos.modalidades.find((fila) => fila.modalidad === 'virtual')!
    delete modalidad.divisor_realizacion
    delete modalidad.canceladas_sistema_vencidas
    delete modalidad.reprogramadas_vencidas
    Object.assign(modalidad, { realizadas: 4, debieron_ocurrir: 21, pct_realizacion: 23.5 })
    render(<ReunionesGerenciaPanel datos={datos} cargando={false} error={null} modoDemo={false} puedeAlternarEjemplo={false} onAlternarEjemplo={vi.fn()} onReintentar={vi.fn()} />)

    const virtual = screen.getByRole('region', { name: 'Resultados de citas Virtual' }) as HTMLElement
    expect(within(virtual).getByText('23.5%')).toBeInTheDocument()
    expect(within(virtual).getByText('4 realizadas')).toBeInTheDocument()
    expect(within(virtual).getByText('Base y exclusiones no disponibles.')).toBeInTheDocument()
    expect(within(virtual).queryByText('4 de 21')).not.toBeInTheDocument()
    expect(screen.getByText(/Citas realizadas sobre citas vencidas o ya realizadas, excluyendo/)).toBeInTheDocument()
  })

  it.each([
    ['virtual', 'Virtual'],
    ['presencial', 'Presencial'],
    ['sin_clasificar', 'Sin clasificar'],
  ] as const)('explica la base servida de %s sin usar las pactadas ni vencidas brutas', (modalidad, nombre) => {
    const datos = metricasReunionesDemo('2026-09-01', '2026-09-04')
    datos.modalidades = [{
      ...datos.modalidades[0]!, modalidad, pactadas: 24, debieron_ocurrir: 21, realizadas: 4,
      divisor_realizacion: 17, canceladas_sistema_vencidas: 4, reprogramadas_vencidas: 0,
      pct_realizacion: 23.5,
    }]
    render(<ReunionesGerenciaPanel datos={datos} cargando={false} error={null} modoDemo={false} puedeAlternarEjemplo={false} onAlternarEjemplo={vi.fn()} onReintentar={vi.fn()} />)

    const tarjeta = screen.getByRole('region', { name: `Resultados de citas ${nombre}` }) as HTMLElement
    expect(within(tarjeta).getByText('23.5%')).toBeInTheDocument()
    expect(within(tarjeta).getByText('4 realizadas de 17 computables')).toBeInTheDocument()
    expect(within(tarjeta).getByText('Excluidas: 4 canceladas por sistema · 0 reprogramadas')).toBeInTheDocument()
    expect(within(tarjeta).queryByText(/de (21|24) computables/)).not.toBeInTheDocument()
    expect(within(tarjeta).queryByText('Base y exclusiones no disponibles.')).not.toBeInTheDocument()
    expect(opcionesGraficos.get('Comparación de citas pactadas y realizadas por modalidad')?.series.map((serie) => serie.data)).toEqual([[24], [4]])
  })

  it('distingue las reprogramadas excluidas de su total y no recalcula el porcentaje', () => {
    const datos = metricasReunionesDemo('2026-09-01', '2026-09-04')
    Object.assign(datos.modalidades[0]!, {
      realizadas: 4, debieron_ocurrir: 21, reprogramadas: 5, canceladas: 3,
      divisor_realizacion: 16, canceladas_sistema_vencidas: 4, reprogramadas_vencidas: 1,
      // Valor centinela: la tarjeta presenta el porcentaje servido, no otra fórmula.
      pct_realizacion: 24.9,
    })
    render(<ReunionesGerenciaPanel datos={datos} cargando={false} error={null} modoDemo={false} puedeAlternarEjemplo={false} onAlternarEjemplo={vi.fn()} onReintentar={vi.fn()} />)

    const tarjeta = screen.getByRole('region', { name: 'Resultados de citas Virtual' }) as HTMLElement
    expect(within(tarjeta).getByText('24.9%')).toBeInTheDocument()
    expect(within(tarjeta).getByText('4 realizadas de 16 computables')).toBeInTheDocument()
    expect(within(tarjeta).getByText('Excluidas: 4 canceladas por sistema · 1 reprogramadas')).toBeInTheDocument()
    expect(within(tarjeta).queryByText('25%')).not.toBeInTheDocument()
  })

  it.each(['divisor_realizacion', 'canceladas_sistema_vencidas', 'reprogramadas_vencidas'] as const)(
    'no completa con cero ni reconstruye el detalle cuando falta %s',
    (campo) => {
      const datos = metricasReunionesDemo('2026-09-01', '2026-09-04')
      const modalidad = datos.modalidades[0]!
      Object.assign(modalidad, {
        realizadas: 4, debieron_ocurrir: 21, divisor_realizacion: 17,
        canceladas_sistema_vencidas: 4, reprogramadas_vencidas: 0, pct_realizacion: 23.5,
      })
      delete modalidad[campo]
      render(<ReunionesGerenciaPanel datos={datos} cargando={false} error={null} modoDemo={false} puedeAlternarEjemplo={false} onAlternarEjemplo={vi.fn()} onReintentar={vi.fn()} />)

      const tarjeta = screen.getByRole('region', { name: 'Resultados de citas Virtual' }) as HTMLElement
      expect(within(tarjeta).getByText('23.5%')).toBeInTheDocument()
      expect(within(tarjeta).getByText('4 realizadas')).toBeInTheDocument()
      expect(within(tarjeta).getByText('Base y exclusiones no disponibles.')).toBeInTheDocument()
      expect(within(tarjeta).queryByText(/computables|Excluidas:/)).not.toBeInTheDocument()
    },
  )

  it('muestra una base cero sin convertir el porcentaje null en cero', () => {
    const datos = metricasReunionesDemo('2026-09-01', '2026-09-04')
    Object.assign(datos.modalidades[0]!, {
      realizadas: 0, divisor_realizacion: 0, canceladas_sistema_vencidas: 4,
      reprogramadas_vencidas: 2, pct_realizacion: null,
    })
    render(<ReunionesGerenciaPanel datos={datos} cargando={false} error={null} modoDemo={false} puedeAlternarEjemplo={false} onAlternarEjemplo={vi.fn()} onReintentar={vi.fn()} />)

    const tarjeta = screen.getByRole('region', { name: 'Resultados de citas Virtual' }) as HTMLElement
    expect(within(tarjeta).getByText('—')).toBeInTheDocument()
    expect(within(tarjeta).getByText('0 realizadas · sin citas computables')).toBeInTheDocument()
    expect(within(tarjeta).getByText('Excluidas: 4 canceladas por sistema · 2 reprogramadas')).toBeInTheDocument()
    expect(within(tarjeta).queryByText('0%')).not.toBeInTheDocument()
  })

  it('conserva cero por ciento cuando hay base real y cero realizadas', () => {
    const datos = metricasReunionesDemo('2026-09-01', '2026-09-04')
    Object.assign(datos.modalidades[0]!, {
      realizadas: 0, divisor_realizacion: 7, canceladas_sistema_vencidas: 0,
      reprogramadas_vencidas: 0, pct_realizacion: 0,
    })
    render(<ReunionesGerenciaPanel datos={datos} cargando={false} error={null} modoDemo={false} puedeAlternarEjemplo={false} onAlternarEjemplo={vi.fn()} onReintentar={vi.fn()} />)

    const tarjeta = screen.getByRole('region', { name: 'Resultados de citas Virtual' }) as HTMLElement
    expect(within(tarjeta).getByText('0%')).toBeInTheDocument()
    expect(within(tarjeta).getByText('0 realizadas de 7 computables')).toBeInTheDocument()
    expect(within(tarjeta).getByText('Excluidas: 0 canceladas por sistema · 0 reprogramadas')).toBeInTheDocument()
  })

  it('conserva null en el gráfico y distingue ausencia de base de cero real', () => {
    const datos = metricasReunionesDemo('2026-09-01', '2026-09-04')
    datos.origenes = [
      { ...datos.origenes[0]!, origen: 'Sin muestra', conversion_contrato_pct: null },
      { ...datos.origenes[0]!, origen: 'Cero real', conversion_contrato_pct: 0 },
    ]
    render(<ReunionesGerenciaPanel datos={datos} cargando={false} error={null} modoDemo={false} puedeAlternarEjemplo={false} onAlternarEjemplo={vi.fn()} onReintentar={vi.fn()} />)

    expect(opcionesGraficos.get('Cierres posteriores a citas por origen')?.series[0]?.data).toEqual([0, null])
    expect(screen.getByText('Sin muestra: — (sin base para calcular)')).toBeInTheDocument()
    expect(screen.queryByText('Cero real: — (sin base para calcular)')).not.toBeInTheDocument()
  })

  it('concilia los totales históricos sin eliminar citas de responsables fuera del desglose', () => {
    const datos = metricasReunionesDemo('2026-08-01', '2026-08-31')
    datos.resumen.pactadas += 4
    datos.resumen.realizadas += 1
    render(<ReunionesGerenciaPanel datos={datos} cargando={false} error={null} modoDemo={false} puedeAlternarEjemplo={false} onAlternarEjemplo={vi.fn()} onReintentar={vi.fn()} />)

    const fuera = screen.getByRole('row', { name: 'Fuera del desglose actual 4 1 0 —' })
    expect(fuera).toBeInTheDocument()
    expect(screen.getByRole('row', { name: 'Total del período 86 59 3 —' })).toBeInTheDocument()
  })

  it('separa vencidas sin resultado y reprogramadas y acota las próximas al período', () => {
    const datos = metricasReunionesDemo('2026-09-01', '2026-09-07')
    datos.resumen.reprogramadas = 2
    datos.resumen.pendientes_cierre = 7
    render(<ReunionesGerenciaPanel datos={datos} cargando={false} error={null} modoDemo={false} puedeAlternarEjemplo={false} onAlternarEjemplo={vi.fn()} onReintentar={vi.fn()} />)

    const reprogramadas = screen.getByText('Reprogramadas').closest('[data-gi-kpi]') as HTMLElement
    expect(within(reprogramadas).getByText('2')).toBeInTheDocument()
    expect(within(reprogramadas).queryByText(/sin resultado|vencidas/)).not.toBeInTheDocument()
    expect(screen.getByText('Vencidas sin resultado').parentElement).toHaveTextContent('7')
    expect(screen.getByText('6 próximas dentro del período')).toBeInTheDocument()
    const hero = screen.getByText('Realización de citas').closest('[data-gi-hero]') as HTMLElement
    expect(within(hero).getByText('80.6%')).toBeInTheDocument()
    expect(within(hero).queryByText('87.9%')).not.toBeInTheDocument()
    expect(within(hero).getByText('58 de 72 citas computables')).toBeInTheDocument()
  })

  it('explica el porcentaje por analista con la base servida, sin inferirla de las pactadas', () => {
    const datos = metricasReunionesDemo('2026-09-01', '2026-09-07')
    Object.assign(datos.responsables[0]!, {
      nombre: 'Analista de prueba', pactadas: 5, realizadas: 2, debieron_ocurrir: 4,
      divisor_realizacion: 3, canceladas_sistema_vencidas: 1,
      canceladas_ajenas_vencidas: 0, reprogramadas_vencidas: 0, programadas_futuras: 1,
      pct_realizacion: 66.7,
    })
    render(<ReunionesGerenciaPanel datos={datos} cargando={false} error={null} modoDemo={false} puedeAlternarEjemplo={false} onAlternarEjemplo={vi.fn()} onReintentar={vi.fn()} />)

    const fila = screen.getByRole('rowheader', { name: 'Analista de prueba' }).closest('tr') as HTMLElement
    expect(within(fila).getByText('66.7%')).toBeInTheDocument()
    expect(within(fila).getByText('2 de 3 computables')).toBeInTheDocument()
    expect(within(fila).getByText(/1 canceladas por sistema/)).toHaveTextContent('1 próximas dentro del período')
    expect(within(fila).queryByText('40%')).not.toBeInTheDocument()
  })

  it('no inventa una base cuando llega un contrato anterior', () => {
    const datos = metricasReunionesDemo('2026-09-01', '2026-09-07')
    delete datos.resumen.divisor_realizacion
    delete datos.responsables[0]!.divisor_realizacion
    delete datos.conversion.leads_con_cierre_previo
    render(<ReunionesGerenciaPanel datos={datos} cargando={false} error={null} modoDemo={false} puedeAlternarEjemplo={false} onAlternarEjemplo={vi.fn()} onReintentar={vi.fn()} />)

    expect(screen.getByText('58 realizadas · base no disponible')).toBeInTheDocument()
    const fila = screen.getByRole('rowheader', { name: 'Andrea Salas' }).closest('tr') as HTMLElement
    expect(within(fila).getByText('Base no disponible')).toBeInTheDocument()
    expect(screen.getByText('El detalle de cierres anteriores no está disponible.')).toBeInTheDocument()
  })

  it('muestra el cierre previo aparte sin convertirlo en cierre posterior ni sumar su capital', () => {
    const datos = metricasReunionesDemo('2026-09-01', '2026-09-07')
    datos.conversion = { ...datos.conversion, leads_reunidos: 7, clientes: 0, contratos: 0, conversion_cliente_pct: 0, conversion_contrato_pct: 0, leads_con_cierre_previo: 1, capital_pen: 0, capital_usd: 0 }
    datos.generado_en = '2026-09-08T00:00:00Z'
    render(<ReunionesGerenciaPanel datos={datos} cargando={false} error={null} modoDemo={false} puedeAlternarEjemplo={false} onAlternarEjemplo={vi.fn()} onReintentar={vi.fn()} />)

    const panel = screen.getByRole('heading', { name: 'Cierres posteriores a citas' }).closest('section') as HTMLElement
    expect(within(panel).getByText('0 de 7 prospectos atendidos')).toBeInTheDocument()
    expect(within(panel).getByText(/Con cierre anterior a la hora programada/)).toHaveTextContent('1. Se muestran aparte.')
    expect(within(panel).getByText(/Seguimiento al/)).toHaveTextContent('7 set. 2026')
    expect(screen.queryByText('Terminan en cliente')).not.toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Resultado registrado de la cita' })).toBeInTheDocument()
    expect(screen.getAllByText('Capital asociado a estos cierres')).toHaveLength(2)
    expect(screen.getAllByText('Acumulado, sin recorte por fecha.')).toHaveLength(2)
  })
})


describe('F2: evidencia, estados y navegación de Citas', () => {
  const props = { cargando: false, error: null, modoDemo: false, puedeAlternarEjemplo: false, onAlternarEjemplo: vi.fn(), onReintentar: vi.fn() }
  it('presenta cuatro indicadores principales y lleva el foco a sus responsables', () => {
    render(<ReunionesGerenciaPanel {...props} datos={metricasReunionesDemo('2026-09-01', '2026-09-05')} />)
    expect(document.querySelectorAll('[data-gi-hero] [data-gi-kpi]')).toHaveLength(4)
    expect(screen.getByRole('region', { name: 'Realizadas' })).toHaveTextContent('58')
    expect(screen.getByRole('region', { name: 'Pactadas' })).toHaveTextContent('82')
    fireEvent.click(screen.getByRole('button', { name: 'Ver responsables' }))
    expect(screen.getByRole('region', { name: 'Resultados por analista' })).toHaveFocus()
  })
  it('distingue cero pendiente confirmado de una actualización fallida con datos anteriores', () => {
    const datos = metricasReunionesDemo('2026-09-01', '2026-09-05')
    datos.resumen.pendientes_cierre = 0
    datos.responsables.forEach((fila) => { fila.pendientes_cierre = 0 })
    const { rerender } = render(<ReunionesGerenciaPanel {...props} datos={datos} />)
    expect(screen.getByText('Sin citas vencidas sin resultado')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Ver responsables' })).not.toBeInTheDocument()
    rerender(<ReunionesGerenciaPanel {...props} datos={datos} error="Fallo al actualizar" />)
    expect(screen.getByText('Revisión de citas no disponible')).toBeInTheDocument()
    expect(screen.queryByText('Sin citas vencidas sin resultado')).not.toBeInTheDocument()
    expect(screen.getByRole('status')).toHaveTextContent('última respuesta del 01 set. 2026 al 05 set. 2026')
    expect(screen.getByRole('region', { name: 'Realizadas' })).toHaveTextContent('58')
  })
  it('una respuesta ausente no afirma que no hay citas y permite reintentar', () => {
    const reintentar = vi.fn()
    render(<ReunionesGerenciaPanel {...props} datos={undefined} onReintentar={reintentar} />)
    expect(screen.getByRole('status')).toHaveTextContent('Datos de citas no disponibles')
    expect(screen.queryByText('Aún no hay citas en este período')).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(reintentar).toHaveBeenCalledOnce()
  })
  it('los valores accesibles de los gráficos conservan los datos servidos', () => {
    render(<ReunionesGerenciaPanel {...props} datos={metricasReunionesDemo('2026-09-01', '2026-09-05')} />)
    fireEvent.click(screen.getByText('Ver valores por modalidad'))
    const tabla = screen.getByRole('table', { name: 'Valores de citas por modalidad', hidden: true })
    expect(within(tabla).getByText('49')).toBeInTheDocument()
    expect(within(tabla).getByText('37')).toBeInTheDocument()
    expect(within(tabla).getByText('33')).toBeInTheDocument()
    expect(within(tabla).getByText('21')).toBeInTheDocument()
  })
})

describe('D-43: el analista dado de baja sigue en el desglose con la marca «de baja»', () => {
  const props = { cargando: false, error: null, modoDemo: false, puedeAlternarEjemplo: false, onAlternarEjemplo: vi.fn(), onReintentar: vi.fn() }
  /** La respuesta del servidor con el 2.12: el analista dado de baja, dentro del desglose y marcado. */
  const conBaja = () => {
    const datos = metricasReunionesDemo('2026-09-01', '2026-09-07')
    return { ...datos, responsables: datos.responsables.map((fila) => (fila.nombre === 'Camila Rojas' ? { ...fila, de_baja: true as const } : fila)) }
  }

  it('con bajas: la fila del analista de baja dice «de baja» (tabla y móvil) y el desglose cuadra con el total', () => {
    render(<ReunionesGerenciaPanel {...props} datos={conBaja()} />)

    const fila = screen.getByRole('rowheader', { name: /^Camila Rojas\s*de baja$/ }).closest('tr') as HTMLElement
    expect(within(fila).getByText('de baja')).toHaveAttribute('title', expect.stringMatching(/dado de baja/i))
    expect(within(fila).getByText('26')).toBeInTheDocument()
    // Los activos, sin marca y con su nombre accesible de siempre.
    expect(screen.getByRole('rowheader', { name: 'Andrea Salas' })).toBeInTheDocument()
    expect(screen.getByRole('rowheader', { name: 'Luis Mendoza' })).toBeInTheDocument()
    // Móvil: la misma marca, solo en su fila.
    const lista = screen.getByRole('list', { name: 'Citas por analista' })
    const tarjeta = within(lista).getByText('Camila Rojas').closest('li') as HTMLElement
    expect(within(tarjeta).getByText('de baja')).toBeInTheDocument()
    expect(within(lista).getAllByText('de baja')).toHaveLength(1)
    // Cuadra: nada «fuera del desglose» y el total, el de siempre.
    expect(screen.queryByRole('row', { name: /Fuera del desglose actual/ })).not.toBeInTheDocument()
    expect(screen.queryByText(/Fuera del desglose actual/)).not.toBeInTheDocument()
    expect(screen.getByRole('row', { name: 'Total del período 82 58 3 —' })).toBeInTheDocument()
    // La marca se explica en texto, no solo con un tooltip.
    expect(screen.getByText(/Los marcados «de baja» ya no están en el equipo/)).toBeInTheDocument()
  })

  it('sin bajas: ninguna fila dice «de baja» y no se explica la marca', () => {
    render(<ReunionesGerenciaPanel {...props} datos={metricasReunionesDemo('2026-09-01', '2026-09-07')} />)

    expect(screen.queryByText('de baja')).not.toBeInTheDocument()
    expect(screen.queryByText(/Los marcados «de baja»/)).not.toBeInTheDocument()
    expect(screen.getByRole('rowheader', { name: 'Camila Rojas' })).toBeInTheDocument()
    expect(screen.getByRole('row', { name: 'Total del período 82 58 3 —' })).toBeInTheDocument()
  })

  it('antes del 2.12 sus citas iban a «Fuera del desglose actual»; con el analista dentro y marcado, el desglose cuadra', () => {
    const antes = metricasReunionesDemo('2026-09-01', '2026-09-07')
    antes.responsables = antes.responsables.filter((fila) => fila.nombre !== 'Camila Rojas')
    const { unmount } = render(<ReunionesGerenciaPanel {...props} datos={antes} />)
    expect(screen.getByRole('row', { name: 'Fuera del desglose actual 26 15 1 —' })).toBeInTheDocument()
    unmount()

    render(<ReunionesGerenciaPanel {...props} datos={conBaja()} />)
    expect(screen.queryByRole('row', { name: /Fuera del desglose actual/ })).not.toBeInTheDocument()
    expect(screen.getByRole('rowheader', { name: /^Camila Rojas\s*de baja$/ })).toBeInTheDocument()
  })
})

describe('D-46 y D-47: el suspendido sale marcado y la fila «Otros» completa el desglose', () => {
  const props = { cargando: false, error: null, modoDemo: false, puedeAlternarEjemplo: false, onAlternarEjemplo: vi.fn(), onReintentar: vi.fn() }
  /** La respuesta del servidor con el 2.12: Luis suspendido en el Portal y las citas de Camila (otro rol) en «Otros». */
  const conSuspendidoYOtros = () => {
    const datos = metricasReunionesDemo('2026-09-01', '2026-09-07')
    return {
      ...datos,
      responsables: datos.responsables.map((fila) =>
        fila.nombre === 'Luis Mendoza' ? { ...fila, suspendido: true as const }
          : fila.nombre === 'Camila Rojas'
            ? { ...fila, responsable_id: null, nombre: 'Otros', rol: null, supervisor_id: null, supervisor_nombre: '—', otros: true as const }
            : fila),
    }
  }

  it('el suspendido dice «suspendido» (tabla y móvil), con el color de «Suspendido en Portal», y se explica', () => {
    render(<ReunionesGerenciaPanel {...props} datos={conSuspendidoYOtros()} />)

    const fila = screen.getByRole('rowheader', { name: /^Luis Mendoza\s*suspendido$/ }).closest('tr') as HTMLElement
    const marca = within(fila).getByText('suspendido')
    expect(marca).toHaveAttribute('title', expect.stringMatching(/suspendido en el Portal/i))
    expect(marca.style.getPropertyValue('--c')).toBe('var(--destructive)')
    expect(within(fila).getByText('27')).toBeInTheDocument()
    const lista = screen.getByRole('list', { name: 'Citas por analista' })
    expect(within(lista).getAllByText('suspendido')).toHaveLength(1)
    expect(screen.getByText(/Los marcados «suspendido» están suspendidos en el Portal/)).toBeInTheDocument()
    expect(screen.queryByText('de baja')).not.toBeInTheDocument()
  })

  it('«Otros» es la última fila, sin supervisor y con sus cifras; el desglose suma el total y no queda nada «fuera»', () => {
    render(<ReunionesGerenciaPanel {...props} datos={conSuspendidoYOtros()} />)

    const otros = screen.getByRole('rowheader', { name: 'Otros' }).closest('tr') as HTMLElement
    const cuerpo = otros.closest('tbody') as HTMLElement
    expect(within(cuerpo).getAllByRole('row').at(-1)).toBe(otros)
    expect(within(otros).getAllByRole('cell')[0]).toHaveTextContent('—')
    expect(within(otros).getByText('26')).toBeInTheDocument()
    expect(within(otros).getByText('15')).toBeInTheDocument()
    expect(within(otros).getByRole('rowheader')).toHaveAttribute('title', expect.stringMatching(/sin responsable/i))
    // Cuadra: nada «fuera del desglose» y el total, el de siempre.
    expect(screen.queryByText(/Fuera del desglose actual/)).not.toBeInTheDocument()
    expect(screen.getByRole('row', { name: 'Total del período 82 58 3 —' })).toBeInTheDocument()
    expect(screen.getByText(/«Otros» reúne las citas sin responsable y las de quienes no son analistas ni supervisores/)).toBeInTheDocument()
    // Móvil: «Otros» también es la última tarjeta.
    const lista = screen.getByRole('list', { name: 'Citas por analista' })
    expect(within(lista).getAllByRole('listitem').at(-1)).toHaveTextContent(/^Otros/)
  })

  it('la respuesta de antes: ni «suspendido» ni «Otros» ni sus explicaciones', () => {
    render(<ReunionesGerenciaPanel {...props} datos={metricasReunionesDemo('2026-09-01', '2026-09-07')} />)

    expect(screen.queryByText('suspendido')).not.toBeInTheDocument()
    expect(screen.queryByRole('rowheader', { name: 'Otros' })).not.toBeInTheDocument()
    expect(screen.queryByText(/«Otros» reúne/)).not.toBeInTheDocument()
    expect(screen.queryByText(/Los marcados «suspendido»/)).not.toBeInTheDocument()
    expect(screen.getByRole('rowheader', { name: 'Luis Mendoza' })).toBeInTheDocument()
  })
})
