import { describe, expect, it } from 'vitest'
import { etapaVisible } from './use-etapa-visible'
import type { Actividad, Lead } from './tipos'
const lead: Lead = { id: 'l1', nombre_completo: 'PERSONA SINTÉTICA', telefono: '999999999', etapa: 'nuevo',
  origen: 'landing', monto_estimado: 1000, moneda: 'PEN', vendedor_id: 'v1', activo: true,
  creado_en: '2026-10-01T10:00:00Z', tenencia_desde: '2026-10-02T10:00:00Z' }
const gestion: Actividad = { id: 'a1', lead_id: 'l1', tipo: 'llamada_no_contestada', detalle: null,
  creado_en: '2026-10-02T11:00:00Z', autor_nombre: 'ANALISTA' }
describe('rótulo operativo del lead', () => {
  it.each([[true, 'Gestionado'], [false, 'Nuevo'], [null, 'Gestión sin verificar'], [undefined, 'Gestión sin verificar']] as const)(
    'sesión real: %s → %s, sin inferirlo de ultimo_contacto_en', (gestion_vigente, label) => {
      expect(etapaVisible({ ...lead, ...(gestion_vigente === undefined ? {} : { gestion_vigente }), ultimo_contacto_en: '2026-10-03T10:00:00Z' }).label).toBe(label)
    })
  it('demo: refleja registrar, deshacer y reasignar; una nota no cuenta', () => {
    expect(etapaVisible(lead, []).label).toBe('Nuevo')
    expect(etapaVisible(lead, [gestion]).label).toBe('Gestionado')
    expect(etapaVisible(lead, [{ ...gestion, metadata: { deshecho_en: null } }]).label).toBe('Nuevo')
    expect(etapaVisible(lead, [{ ...gestion, tipo: 'nota' }]).label).toBe('Nuevo')
    expect(etapaVisible(lead, [gestion, { ...gestion, id: 'r1', tipo: 'reasignacion', creado_en: '2026-10-03T10:00:00Z' }]).label).toBe('Nuevo')
  })
  it('sin tenencia no marca gestión ni queda indeterminado', () => {
    const sinTenencia = { ...lead }
    delete sinTenencia.tenencia_desde
    expect(etapaVisible(sinTenencia).k).toBe('nuevo')
    expect(etapaVisible({ ...lead, tenencia_desde: null }).k).toBe('nuevo')
    expect(etapaVisible(lead).k).toBe('sin_verificar')
  })
  it('el nuevo estado no sustituye Contactado ni las etapas posteriores', () => {
    expect(etapaVisible({ ...lead, etapa: 'contactado', gestion_vigente: true }).label).toBe('Contactado')
    expect(etapaVisible({ ...lead, etapa: 'convertido', gestion_vigente: true }).label).toBe('Convertido')
    expect(etapaVisible({ ...lead, vendedor_id: null, gestion_vigente: true }).label).toBe('Nuevo')
  })
})
