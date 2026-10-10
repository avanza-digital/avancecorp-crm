// «Eliminar inversión» cuando la venta cambia mientras se elimina (PT409).
//
// Bloque 2.6 (20261009210000): si la inversión es la conversión de un lead, la eliminación la anula primero; si la
// acreditación de esa venta cambia mientras la anulación espera el cerrojo de su mes, el servidor responde PT409 y no
// elimina nada. Basta con reintentar, y el diálogo tiene que decirlo con un texto claro, no con el crudo del servidor
// («La acreditacion cambio durante la anulacion…»). Aquí corren el diálogo y la traducción de `crm-api` REALES; solo se
// sustituye el cliente de Supabase.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { eliminarInversion } from '@/data/crm-api'
import type { InversionFuente } from '@/lib/inversionistas'
import { inversionF5 } from '@/test/fixtures/f5'
import { InversionEliminar } from './inversion-eliminar'

const mock = vi.hoisted(() => ({ rpc: vi.fn() }))
vi.mock('@/lib/supabase', () => ({ sb: { schema: () => ({ rpc: (...args: unknown[]) => mock.rpc(...args) }) } }))

const MOTIVO = 'Se registró dos veces por error'

describe('Eliminar inversión: la venta cambió mientras se eliminaba (PT409)', () => {
  beforeEach(() => {
    vi.spyOn(console, 'error').mockImplementation(() => {})
  })

  it('dice con un texto claro que se reintente, no el texto crudo del servidor, y no cierra el diálogo', async () => {
    mock.rpc.mockResolvedValue({
      data: null,
      error: { code: 'PT409', message: 'La acreditacion cambio durante la anulacion; vuelve a intentar', details: null, hint: null },
    })
    const onCerrar = vi.fn()
    const onConfirmar = async (i: InversionFuente, motivo: string) => { await eliminarInversion(i.fuente_id, motivo) }
    render(<InversionEliminar inversion={inversionF5} onConfirmar={onConfirmar} onCerrar={onCerrar} />)
    const user = userEvent.setup()

    await user.type(screen.getByLabelText('Motivo de la eliminación'), MOTIVO)
    await user.type(screen.getByLabelText('Escribe ELIMINAR para confirmar'), 'ELIMINAR')
    await user.click(screen.getByRole('button', { name: 'Eliminar inversión' }))

    expect(await screen.findByRole('alert')).toHaveTextContent('La venta cambió mientras eliminabas la inversión. Vuelve a intentarlo.')
    expect(screen.queryByText(/La acreditacion cambio/)).not.toBeInTheDocument()
    expect(mock.rpc).toHaveBeenCalledExactlyOnceWith('eliminar_inversion_fn', { p_fuente_id: inversionF5.fuente_id, p_motivo: MOTIVO })
    expect(onCerrar).not.toHaveBeenCalled()
    // El motivo sigue escrito: reintentar es un clic.
    expect(screen.getByLabelText('Motivo de la eliminación')).toHaveValue(MOTIVO)
  })
})
