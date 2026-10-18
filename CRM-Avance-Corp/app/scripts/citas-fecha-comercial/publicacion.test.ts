import { readFileSync, readdirSync } from 'node:fs'
import { expect, it, vi } from 'vitest'
const mocks = vi.hoisted(() => ({ rpc: vi.fn() }))
vi.mock('@/lib/supabase', () => ({ sb: { schema: () => ({ rpc: mocks.rpc }) } }))
import { cargarCitasGerencia, adaptarGestion, adaptarCitas } from '@/data/citas-gerencia'
import { calcularAvanceCitas } from '@/components/citas/avance'
import { defaults } from '@/components/citas/modelo'

const dir = process.env.CITAS_EVIDENCIA
if (!dir) throw new Error('CITAS_EVIDENCIA requerido')
const archivos = readdirSync(dir).filter(n => /^cloud-citas_.*-\d{2}-[124]\.json$/.test(n))
if (archivos.length !== 12) throw new Error('Se requieren las doce respuestas HTTP del banco propio')
for (const archivo of archivos) it(`HTTP → contrato estricto → pantalla: ${archivo}`, async () => {
  const payload = JSON.parse(readFileSync(`${dir}/${archivo}`, 'utf8'))
  mocks.rpc.mockResolvedValue({ data: payload, error: null })
  const mes = payload.periodo.desde.slice(0, 7)
  const datos = await cargarCitasGerencia(mes)
  const resultado = calcularAvanceCitas(adaptarGestion(datos)!, adaptarCitas(datos), defaults(mes), datos.generado_en, 3.5)
  if (archivo.endsWith('-1.json')) {
    expect(resultado.testigoCuadra).toBe(true)
    expect(resultado.diferenciasTestigo).toEqual([])
    expect(resultado.total.clientesPeriodo).toBe(mes === '2026-09' ? 4 : 1)
    expect(resultado.total.clientes).toBe(mes === '2026-09' ? 2 : 1)
  } else expect(resultado.testigoCuadra).toBe(null)
})
