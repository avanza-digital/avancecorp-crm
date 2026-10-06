import { act, render, screen, waitFor } from '@testing-library/react'
import { expect, it, vi } from 'vitest'
import { AreaConsultaGerencia } from './area-consulta-gerencia'
import { ConsultaGerenciaContext, type ConsultaGerenciaContextValue } from './consulta-context'

it('devuelve el foco a la cabecera si desapareció el aviso y sólo cambia la señal de carga terminada', async () => {
  const contexto: ConsultaGerenciaContextValue = {
    consulta: { gestionAnalista: null, administrarMetasPeriodo: null, rendimientoEquipo: null, rendimientoOrden: 'cupos',
      comparacionAbierta: false, comparacionIds: ['', ''], ranking: 'conversion', horizonteAltas: 6, analistaId: null, volverARanking: false, abrirDetalle: false },
    setConsulta: vi.fn(), posiciones: { current: new Map([['alertas', { scrollTop: 0, focoId: 'aviso-retirado' }]]) },
  }
  const escena = (lista: boolean) => <ConsultaGerenciaContext value={contexto}><AreaConsultaGerencia vista="alertas">
    <section data-consulta-lista={lista}><h2 id="alertas-encabezado" tabIndex={-1}>Señales de gestión</h2></section>
  </AreaConsultaGerencia></ConsultaGerenciaContext>
  const vista = render(escena(false))
  await act(() => new Promise<void>(resolver => requestAnimationFrame(() => resolver())))
  expect(screen.getByRole('heading')).not.toHaveFocus()
  vista.rerender(escena(true))
  await waitFor(() => expect(screen.getByRole('heading')).toHaveFocus())
})
