// Guard de vistas por capacidad — lógica pura, fuera de App.tsx (que solo la
// consume) para no romper el fast-refresh y poder probarla sin montar el árbol.
//
// Doble defensa (patrón VITANOVA): el nav OCULTA lo que can() niega, este guard
// EXPULSA lo que se alcance por URL, y la RLS del esquema crm lo NIEGA en el
// servidor. Regla de oro: lo que can() oculta, la RLS también lo niega.
import { can, type Rol } from '@/lib/roles'
import { esVistaLeads, type Vista } from '@/lib/router'

/**
 * Dónde ATERRIZA un rol: su vista base cuando la pedida no existe o no le
 * corresponde. El coordinador (C1) reparte la cola y no tiene cartera, así que
 * su base es 'repartir'; el resto conserva 'hoy'/'mi-cartera' según el gate.
 */
export function vistaBase(rol: Rol | null | undefined, leadsVisibles: boolean): Vista {
  if (can(rol, 'repartirCola') && !can(rol, 'verCartera')) return 'repartir'
  return leadsVisibles ? 'hoy' : 'mi-cartera'
}

/** Corrige una vista pedida (hash/estado) a una que el rol SÍ puede ver. */
export function sanearVista(
  vista: Vista,
  rol: Rol | null | undefined,
  leadsVisibles: boolean,
): Vista {
  const base = vistaBase(rol, leadsVisibles)
  if (!leadsVisibles && esVistaLeads(vista)) return base
  if (vista === 'config' && !can(rol, 'verConfiguracion')) return base
  if (vista === 'equipo' && !can(rol, 'verEquipo')) return base
  if (vista === 'repartir' && !can(rol, 'repartirCola')) return base
  if (vista === 'mi-cartera' && !can(rol, 'verCartera')) return base
  return vista
}
