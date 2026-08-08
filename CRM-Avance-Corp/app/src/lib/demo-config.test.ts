import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import {
  catalogoUsuariosAdministrablesDemo,
  configuracionMetasDemo,
  configuracionProductosDemo,
  configuracionSlaDemo,
  metricasSlaDemo,
  productosSeleccionablesDemo,
  usuariosAdministrablesDemo,
} from './demo-config'
import { ConfiguracionMetasSchema } from './metas-versionadas'
import {
  ConfiguracionProductosSchema,
  ProductoCondicionSchema,
  ProductoCondicionSeleccionSchema,
} from './productos-inversion'
import { ConfiguracionSlaSchema, MetricasSlaSchema } from './sla-versionado'
import { UsuarioAdministrableSchema } from './usuarios-config'

describe('fixtures de Configuración demo', () => {
  it('cumplen los mismos contratos estrictos que las respuestas reales', () => {
    expect(v.safeParse(v.array(UsuarioAdministrableSchema), catalogoUsuariosAdministrablesDemo()).success).toBe(true)
    expect(v.safeParse(ConfiguracionProductosSchema, configuracionProductosDemo()).success).toBe(true)
    expect(v.safeParse(v.array(ProductoCondicionSeleccionSchema), productosSeleccionablesDemo()).success).toBe(true)
    expect(v.safeParse(ConfiguracionMetasSchema, configuracionMetasDemo('2026-08-01')).success).toBe(true)
    expect(v.safeParse(ConfiguracionSlaSchema, configuracionSlaDemo()).success).toBe(true)
    expect(v.safeParse(MetricasSlaSchema, metricasSlaDemo('2026-08-01', '2026-08-31')).success).toBe(true)
  })

  it('pagina y filtra usuarios manteniendo un total coherente', () => {
    const pagina = usuariosAdministrablesDemo('', 3, 3)
    expect(pagina).toHaveLength(3)
    expect(new Set(pagina.map((fila) => fila.total))).toEqual(new Set([9]))

    const sinTilde = usuariosAdministrablesDemo('maria', 25, 0)
    expect(sinTilde.map((fila) => fila.nombre_completo)).toEqual(['MARÍA SALAZAR'])
    expect(sinTilde[0]?.total).toBe(1)
  })

  it('deriva el selector solo de condiciones activas de versiones publicadas', () => {
    const configuracion = configuracionProductosDemo()
    const selector = productosSeleccionablesDemo()
    const idsPublicados = new Set(
      configuracion.productos.flatMap((producto) =>
        producto.versiones
          .filter((version) => version.estado === 'publicada')
          .flatMap((version) => version.condiciones.filter((condicion) => condicion.activa).map((condicion) => condicion.id)),
      ),
    )
    const idsBorrador = new Set(
      configuracion.productos.flatMap((producto) =>
        producto.versiones
          .filter((version) => version.estado === 'borrador')
          .flatMap((version) => version.condiciones.map((condicion) => condicion.id)),
      ),
    )

    expect(new Set(selector.map((fila) => fila.condicion_id))).toEqual(idsPublicados)
    expect(selector.some((fila) => idsBorrador.has(fila.condicion_id))).toBe(false)
    expect(new Set(selector.map((fila) => fila.moneda))).toEqual(new Set(['PEN', 'USD']))
  })

  it('rechaza interés compuesto fuera de modalidad anual o de años completos', () => {
    const base = configuracionProductosDemo().productos
      .flatMap((producto) => producto.versiones)
      .flatMap((version) => version.condiciones)
      .find((condicion) => condicion.tipo_interes === 'compuesto')
    expect(base).toBeDefined()
    if (!base) throw new Error('Falta fixture compuesto')
    expect(v.safeParse(ProductoCondicionSchema, {
      ...base,
      modalidad: 'trimestral',
    }).success).toBe(false)
    expect(v.safeParse(ProductoCondicionSchema, {
      ...base,
      plazo_meses: 18,
    }).success).toBe(false)
  })

  it('devuelve copias aisladas para que una pantalla no contamine otra consulta', () => {
    const primera = configuracionProductosDemo()
    primera.productos[0]!.codigo = 'ALTERADO-EN-PANTALLA'

    expect(configuracionProductosDemo().productos[0]?.codigo).toBe('CRECIMIENTO-12')
  })
})
