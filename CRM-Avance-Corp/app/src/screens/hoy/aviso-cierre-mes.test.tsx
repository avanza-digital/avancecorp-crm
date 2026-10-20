import { fireEvent, render, screen } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const dobles = vi.hoisted(() => ({
  cierreEstado: {} as Record<string, unknown>,
  cierreHabilitada: undefined as boolean | undefined,
  yo: { id: '11111111-1111-4111-8111-111111111111', rol: 'gerencia', demo: false } as {
    id: string
    rol: string
    demo: boolean
  },
}))

vi.mock('@/data/crm-queries', () => ({
  useCierreMesEstado: (habilitada: boolean) => {
    dobles.cierreHabilitada = habilitada
    return dobles.cierreEstado
  },
}))

// Sesión real por defecto: el panel se apaga solo en demo, desde dentro.
vi.mock('@/lib/auth-context', () => ({
  useAuth: () => ({ yo: dobles.yo }),
}))

const { AvisoCierreMesPanel } = await import('./aviso-cierre-mes')

/** Payloads VERBATIM del generador de fixtures (los mismos de cierre-de-mes.test.ts). */
function estado(pendiente: Record<string, unknown> | null) {
  return {
    data: {
      hoy: '2026-08-15',
      zona: 'America/Lima',
      version: 1,
      pendiente,
      generado_en: '2026-08-15T20:34:50.843856-05:00',
      mes_en_curso: { mes: '2026-08', cierra_el: '2026-09-10', mes_nombre: 'agosto' },
      ultimo_cerrado: null,
    },
    isError: false,
  }
}

beforeEach(() => {
  dobles.cierreEstado = estado(null)
  dobles.cierreHabilitada = undefined
  dobles.yo = { id: '11111111-1111-4111-8111-111111111111', rol: 'gerencia', demo: false }
})

describe('AvisoCierreMesPanel', () => {
  it('sin mes pendiente no pinta nada', () => {
    const { container } = render(<AvisoCierreMesPanel />)
    expect(container).toBeEmptyDOMElement()
  })

  it('en ventana: el aviso, sin rol de alarma', () => {
    dobles.cierreEstado = estado({
      mes: '2026-07',
      estado: 'en_ventana',
      cierra_el: '2026-08-10',
      mes_nombre: 'julio',
      dias_para_cierre: 5,
    })
    render(<AvisoCierreMesPanel />)

    expect(screen.getByText('julio se cierra el 10 ago. 2026')).toBeInTheDocument()
    expect(screen.getByText(/Quedan 5 días de ajuste/)).toBeInTheDocument()
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
  })

  it.each([false, true])('atascado: la alarma permanece visible, compacto=%s', (compacto) => {
    dobles.cierreEstado = estado({
      mes: '2026-06',
      estado: 'atascado',
      cierra_el: '2026-07-10',
      mes_nombre: 'junio',
      dias_para_cierre: 0,
    })
    render(<AvisoCierreMesPanel compacto={compacto} />)

    const alarma = screen.getByRole('alert')
    expect(alarma).toHaveTextContent('El cierre de junio está atascado')
    expect(alarma).toHaveTextContent(/Debió sellarse el 10 jul\. 2026/)
  })

  it('el aviso compacto abre el detalle, cierra con Escape o fuera y devuelve el foco', () => {
    dobles.cierreEstado = estado({
      mes: '2026-09', estado: 'en_ventana', cierra_el: '2026-10-22',
      mes_nombre: 'setiembre', dias_para_cierre: 2,
    })
    render(<AvisoCierreMesPanel compacto />)
    const boton = screen.getByRole('button', { name: 'Cierre de setiembre: 22 oct.' })
    expect(boton).toHaveAttribute('aria-expanded', 'false')
    expect(screen.queryByText(/Quedan 2 días de ajuste/)).not.toBeInTheDocument()
    fireEvent.click(boton)
    expect(screen.getByRole('region', { name: 'setiembre se cierra el 22 oct. 2026' }))
      .toHaveTextContent(/Quedan 2 días de ajuste/)
    fireEvent.keyDown(document, { key: 'Escape' })
    expect(boton).toHaveFocus()
    expect(boton).toHaveAttribute('aria-expanded', 'false')
    fireEvent.click(boton)
    fireEvent.click(screen.getByRole('button', { name: 'Cerrar detalle del cierre' }))
    expect(boton).toHaveFocus()
    fireEvent.click(boton)
    fireEvent.pointerDown(document.body)
    expect(boton).toHaveAttribute('aria-expanded', 'false')
  })

  it('el día del cierre muestra hoy y conserva la explicación al abrir', () => {
    dobles.cierreEstado = estado({
      mes: '2026-09', estado: 'hoy', cierra_el: '2026-10-22',
      mes_nombre: 'setiembre', dias_para_cierre: 0,
    })
    render(<AvisoCierreMesPanel compacto />)
    fireEvent.click(screen.getByRole('button', { name: 'Cierre de setiembre: hoy' }))
    expect(screen.getByText(/El ciclo automático pasa a las 09:20 de Lima/)).toBeVisible()
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
  })

  it('en DEMO no consulta ni pinta: el demo es hermético y esta maquinaria es real', () => {
    dobles.yo = { id: '11111111-1111-4111-8111-111111111111', rol: 'gerencia', demo: true }
    const { container } = render(<AvisoCierreMesPanel />)

    expect(dobles.cierreHabilitada).toBe(false)
    expect(container).toBeEmptyDOMElement()
  })

  it('el banner es SOLO de gerencia: otro rol ni consulta ni pinta (decisión pre-release)', () => {
    // Quien no puede actuar sobre el ciclo no recibe su aviso; el permiso del
    // coordinador en el servidor es para sus pantallas de metas, no para esto.
    dobles.yo = { id: '22222222-2222-4222-8222-222222222222', rol: 'supervisor', demo: false }
    dobles.cierreEstado = estado({
      mes: '2026-06',
      estado: 'atascado',
      cierra_el: '2026-07-10',
      mes_nombre: 'junio',
      dias_para_cierre: 0,
    })
    const { container } = render(<AvisoCierreMesPanel />)

    expect(dobles.cierreHabilitada).toBe(false)
    expect(container).toBeEmptyDOMElement()
  })

  it('si el estado no responde, no hay banner (advisory, fail-open)', () => {
    dobles.cierreEstado = { data: undefined, isError: true }
    const { container } = render(<AvisoCierreMesPanel />)
    expect(container).toBeEmptyDOMElement()
  })
})
