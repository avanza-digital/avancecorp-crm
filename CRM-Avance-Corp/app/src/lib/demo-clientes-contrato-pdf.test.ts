import { describe, expect, it } from 'vitest'
import {
  CLIENTES_DEMO,
  CUENTAS_CLIENTES_DEMO,
  DATOS_PDF_DEMO,
  IDENTIDADES_PDF_DEMO,
} from './demo-clientes'

describe('datos demo para el contrato PDF', () => {
  it('conserva la mancomunación internamente pero identifica un titular principal', () => {
    const datos = DATOS_PDF_DEMO['dc-ct-c']

    expect(datos?.titular.nombreCompleto).toBe('GLADYS PILAR YUPANQUI ROJAS')
    expect(datos?.titular.domicilio).toContain('Lima')
    expect(datos?.cotitulares).toHaveLength(2)
  })

  it('ofrece identidad legal con domicilio para cada cliente que puede contratar', () => {
    for (const cliente of CLIENTES_DEMO) {
      const identidad = IDENTIDADES_PDF_DEMO[cliente.id]
      expect(identidad?.titular.nombreCompleto).toBe(cliente.nombre_completo)
      expect(identidad?.titular.domicilio).toContain('Lima')
      expect(identidad?.analista.nombreCompleto).toBe('VENDEDOR UNO')
    }
  })

  it('precarga las cuentas por moneda sin depender de una consulta remota', () => {
    expect(CUENTAS_CLIENTES_DEMO['dc-cli-1']?.PEN[0]).toMatchObject({
      banco: 'BCP',
      moneda: 'PEN',
      es_cuenta_perfil: true,
    })
    expect(CUENTAS_CLIENTES_DEMO['dc-cli-1']?.USD).toEqual([])
    expect(CUENTAS_CLIENTES_DEMO['dc-cli-2']?.USD[0]).toMatchObject({
      banco: 'Interbank',
      moneda: 'USD',
    })
  })
})
