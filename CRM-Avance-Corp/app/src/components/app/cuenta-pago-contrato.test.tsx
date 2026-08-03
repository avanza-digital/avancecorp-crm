import { describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { CuentaPagoContrato, type CuentaPagoContratoProps } from './cuenta-pago-contrato'
import { CUENTA_NUEVA, claveCuenta } from '@/lib/cuentas-bancarias-contrato'
import { SECCION_BANCARIA_VACIA } from '@/lib/cliente-form-logica'
import type { CuentaBancariaSeleccionable } from '@/lib/clientes-tipos'

const PERFIL: CuentaBancariaSeleccionable = {
  cuenta_id: null,
  moneda: 'PEN',
  banco: 'BCP',
  tipo_cuenta: 'ahorros',
  numero_cuenta: '191000001234',
  cci: '00112233445566778899',
  titular_distinto: false,
  beneficiario_nombre: null,
  beneficiario_dni: null,
  origen: 'perfil',
  es_cuenta_perfil: true,
  creada_en: null,
}

function props(overrides: Partial<CuentaPagoContratoProps> = {}): CuentaPagoContratoProps {
  return {
    moneda: 'PEN',
    cuentas: [PERFIL],
    seleccion: '',
    nueva: { ...SECCION_BANCARIA_VACIA },
    cargando: false,
    error: false,
    reintentando: false,
    deshabilitado: false,
    onSeleccion: vi.fn(),
    onNueva: vi.fn(),
    onReintentar: vi.fn(),
    ...overrides,
  }
}

describe('CuentaPagoContrato', () => {
  it('expone un grupo accesible, enmascara los datos y permite elegir una cuenta', async () => {
    const user = userEvent.setup()
    const onSeleccion = vi.fn()
    render(<CuentaPagoContrato {...props({ onSeleccion })} />)

    expect(screen.getByRole('group', { name: 'Cuenta de pago del contrato' })).toBeInTheDocument()
    expect(screen.getByText(/•••• 1234/)).toBeInTheDocument()
    expect(screen.getByText(/CCI •••• 8899/)).toBeInTheDocument()
    expect(screen.getAllByRole('radio').every((radio) => radio.hasAttribute('required'))).toBe(true)

    await user.click(screen.getByRole('radio', { name: /BCP/ }))
    expect(onSeleccion).toHaveBeenCalledWith(claveCuenta(PERFIL))
  })

  it('permite recorrer el grupo con flechas de teclado', async () => {
    const user = userEvent.setup()
    const onSeleccion = vi.fn()
    render(<CuentaPagoContrato {...props({ onSeleccion })} />)

    const primera = screen.getByRole('radio', { name: /BCP/ })
    primera.focus()
    await user.keyboard('[ArrowDown]')

    expect(onSeleccion).toHaveBeenCalledWith(CUENTA_NUEVA)
  })

  it('durante la carga no ofrece destinos y anuncia el estado', () => {
    render(<CuentaPagoContrato {...props({ cargando: true, cuentas: [] })} />)

    expect(screen.getByText('Cargando cuentas bancarias…')).toBeInTheDocument()
    expect(screen.queryByRole('radio')).not.toBeInTheDocument()
  })

  it('el error bloquea la selección, permite reintentar y devuelve el foco al recuperarse', async () => {
    const user = userEvent.setup()
    const onReintentar = vi.fn()
    const { rerender } = render(
      <CuentaPagoContrato {...props({ error: true, cuentas: [], onReintentar })} />,
    )

    const alerta = screen.getByRole('alert')
    expect(alerta).toHaveTextContent(/No se pudieron cargar las cuentas/)
    await user.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(onReintentar).toHaveBeenCalledTimes(1)

    rerender(<CuentaPagoContrato {...props({ error: false, cuentas: [PERFIL], onReintentar })} />)
    await waitFor(() => expect(screen.getByRole('radio', { name: /BCP/ })).toHaveFocus())
  })

  it('sin cuentas guía al alta inline y marca sus campos como requeridos', () => {
    render(
      <CuentaPagoContrato {...props({ cuentas: [], seleccion: CUENTA_NUEVA })} />,
    )

    expect(screen.getByText(/todavía no tiene una cuenta completa/)).toBeInTheDocument()
    expect(screen.getByRole('radio', { name: 'Añadir una cuenta nueva' })).toBeChecked()
    expect(screen.getByLabelText('Banco')).toHaveAttribute('aria-required', 'true')
    expect(screen.getByLabelText('N° de cuenta')).toHaveAttribute('aria-required', 'true')
    expect(screen.getByLabelText(/CCI/)).toHaveAttribute('aria-required', 'true')
  })

  it('propaga el estado deshabilitado a todos los controles', () => {
    render(<CuentaPagoContrato {...props({ deshabilitado: true })} />)

    for (const radio of screen.getAllByRole('radio')) expect(radio).toBeDisabled()
  })
})
