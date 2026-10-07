import type { Route } from '@playwright/test'

/** Actualiza fixtures de captación conservando sus filas y filtros de negocio. */
export function responderRegistroV2(route: Route, opciones: Parameters<Route['fulfill']>[0]) {
  const p = opciones.json as { version?: number; items?: Record<string, unknown>[] } | undefined
  if (!p || !Array.isArray(p.items) || p.version !== 1) return route.fulfill(opciones)
  return route.fulfill({ ...opciones, json: { ...p, version: 2, items: p.items.map(i => ({ ...i,
    origen: 'lead', sujeto_tipo: 'lead', sujeto_id: i['lead_id'], sujeto_nombre: i['lead_nombre'],
    inversionista_id: null, perfil_id: null, identidad_visible: true,
  })) } })
}
