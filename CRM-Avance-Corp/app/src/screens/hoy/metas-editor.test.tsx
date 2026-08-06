import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { objetivosCero } from '@/lib/objetivos'
import type { Miembro } from '@/lib/tipos'
import { MetasEditor } from './metas-editor'

const EQUIPO = [
  { perfil_id: 's1', nombre_completo: 'Supervisora Uno', rol_crm: 'supervisor', activo: true },
  { perfil_id: 'v1', nombre_completo: 'Ana Torres', rol_crm: 'vendedor', supervisor_id: 's1', activo: true },
] satisfies Miembro[]

describe('editor de metas', () => {
  it('muestra solo monto y conversión, y separa miles mientras se escribe', () => {
    const guardar = vi.fn(() => ({ ok: true }))
    render(
      <MetasEditor
        objetivos={objetivosCero()}
        equipo={EQUIPO}
        demo={false}
        onGuardar={guardar}
      />,
    )

    expect(screen.queryByText('Cierres')).not.toBeInTheDocument()
    const monto = screen.getByLabelText('Monto objetivo de Ana Torres')
    fireEvent.change(monto, { target: { value: '1500000' } })
    expect(monto).toHaveValue((1_500_000).toLocaleString('es-PE'))

    fireEvent.change(screen.getByLabelText('Conversión objetivo de Ana Torres'), {
      target: { value: '27.5' },
    })
    fireEvent.click(screen.getByRole('button', { name: 'Guardar metas individuales' }))

    expect(guardar).toHaveBeenCalledWith({
      v1: {
        vendedorId: 'v1',
        supervisorId: 's1',
        capitalObjetivo: 1_500_000,
        ventasObjetivo: 0,
        conversionObjetivo: 27.5,
      },
    })
  })

  it('resincroniza los campos cuando el store revierte una meta rechazada', () => {
    const guardar = vi.fn(() => ({ ok: true }))
    const objetivosIniciales = objetivosCero()
    objetivosIniciales.porVendedor.v1 = {
      vendedorId: 'v1',
      supervisorId: 's1',
      capitalObjetivo: 900_000,
      ventasObjetivo: 0,
      conversionObjetivo: 20,
    }
    const { rerender } = render(
      <MetasEditor
        objetivos={objetivosIniciales}
        equipo={EQUIPO}
        demo={false}
        onGuardar={guardar}
      />,
    )

    fireEvent.change(screen.getByLabelText('Monto objetivo de Ana Torres'), {
      target: { value: '1500000' },
    })
    fireEvent.change(screen.getByLabelText('Conversión objetivo de Ana Torres'), {
      target: { value: '31' },
    })

    const objetivosServidor = objetivosCero()
    objetivosServidor.porVendedor.v1 = {
      vendedorId: 'v1',
      supervisorId: 's1',
      capitalObjetivo: 750_000,
      ventasObjetivo: 0,
      conversionObjetivo: 18,
    }
    rerender(
      <MetasEditor
        objetivos={objetivosServidor}
        equipo={EQUIPO}
        demo={false}
        onGuardar={guardar}
      />,
    )

    expect(screen.getByLabelText('Monto objetivo de Ana Torres')).toHaveValue(
      (750_000).toLocaleString('es-PE'),
    )
    expect(screen.getByLabelText('Conversión objetivo de Ana Torres')).toHaveValue(18)
    expect(guardar).not.toHaveBeenCalled()
  })
})
