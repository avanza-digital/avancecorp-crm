import { describe, expect, it, vi } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import type { AlertaCRM } from '@/lib/alertas'
import type { EstadoAlertasCRM } from '@/lib/alertas-context'
import type { Rol } from '@/lib/roles'

const reintentar = vi.fn()
let ESTADO: EstadoAlertasCRM = {
  alertas: [],
  rol: 'vendedor',
  cargando: false,
  errores: [],
  generadoEn: '2026-08-06T17:35:00.000Z',
  reintentar,
}

vi.mock('@/lib/alertas-context', () => ({
  useAlertasCRM: () => ESTADO,
}))

const { Alertas } = await import('./alertas')

function alerta(over: Partial<AlertaCRM> = {}): AlertaCRM {
  return {
    id: 'tarea_vencida:lead-1',
    tipo: 'tarea_vencida',
    severidad: 'critica',
    alcance: 'personal',
    titulo: 'Tarea vencida',
    detalle: '«Llamar al cliente» venció hace 1 día.',
    responsableId: 'v1',
    responsable: 'Ana Vendedora',
    valor: 24,
    destino: {
      vista: 'agenda',
      leadId: 'lead-1',
      etiqueta: 'Abrir en Agenda',
    },
    ...over,
  }
}

function montar({
  rol = 'vendedor',
  alertas = [],
  cargando = false,
  errores = [],
}: {
  rol?: Rol
  alertas?: AlertaCRM[]
  cargando?: boolean
  errores?: string[]
} = {}) {
  reintentar.mockReset()
  ESTADO = {
    alertas,
    rol,
    cargando,
    errores,
    generadoEn: '2026-08-06T17:35:00.000Z',
    reintentar,
  }
  return render(<Alertas />)
}

describe('Alertas — responsabilidad por rol', () => {
  it.each([
    ['vendedor', 'Mis pendientes actuales', 'Tu acción'],
    ['supervisor', 'Excepciones del equipo', 'Tu intervención'],
    ['gerencia', 'Señales de gestión', 'Tu decisión'],
  ] as const)('presenta a %s únicamente su nivel de responsabilidad', (rol, titulo, alcance) => {
    montar({ rol })

    expect(screen.getByRole('heading', { name: titulo })).toBeVisible()
    expect(screen.getByText(alcance)).toBeVisible()
  })

  it('lleva cada pendiente al caso exacto que lo resuelve', () => {
    montar({ alertas: [alerta()] })

    expect(screen.getByRole('link', { name: 'Abrir en Agenda: Tarea vencida' })).toHaveAttribute(
      'href',
      '#/agenda/lead/lead-1',
    )
    expect(screen.getByText('Responsable: Ana Vendedora')).toBeVisible()
  })

  it('filtra por prioridad, tipo y texto sin perder el total activo', async () => {
    const user = userEvent.setup()
    montar({
      rol: 'supervisor',
      alertas: [
        alerta(),
        alerta({
          id: 'sin_proxima_accion:vendedor:v2',
          tipo: 'sin_proxima_accion',
          severidad: 'atencion',
          alcance: 'equipo',
          titulo: 'Vendedor con leads sin próxima acción',
          detalle: 'Bruno tiene 3 leads sin una próxima acción registrada.',
          responsableId: 'v2',
          responsable: 'Bruno Supervisor',
          valor: 3,
          destino: { vista: 'equipo', etiqueta: 'Ver equipo' },
        }),
      ],
    })

    await user.click(screen.getByRole('button', { name: 'Atención: 1' }))
    expect(screen.queryByRole('heading', { name: 'Tarea vencida' })).not.toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Vendedor con leads sin próxima acción' })).toBeVisible()
    expect(screen.getByRole('status')).toHaveTextContent('1 pendiente activo de 2')

    await user.selectOptions(screen.getByRole('combobox', { name: 'Filtrar por tipo' }), 'sin_proxima_accion')
    await user.type(screen.getByRole('searchbox', { name: 'Buscar pendiente' }), 'bruno')
    const lista = screen.getByRole('list', { name: 'Pendientes activos' })
    expect(within(lista).getAllByRole('listitem')).toHaveLength(1)
  })

  it('distingue carga, error y ausencia real de pendientes', () => {
    const carga = montar({ cargando: true })
    expect(screen.getByRole('status', { name: 'Cargando pendientes' })).toBeInTheDocument()
    carga.unmount()

    const error = montar({ errores: ['No se pudo calcular la conversión actual.'] })
    expect(screen.getByRole('alert')).toHaveTextContent('No se pudo calcular la conversión actual.')
    error.unmount()

    montar({ rol: 'supervisor' })
    expect(screen.getByText('Nada pendiente')).toBeVisible()
    expect(screen.getByText('Tu equipo no tiene excepciones que requieran intervención.')).toBeVisible()
  })
})
