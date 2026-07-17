// Helpers PUROS de la pantalla Clientes (screens/clientes.tsx): regla de
// cartera por fila, búsqueda normalizada, filtro por asesor, recorte de ámbito
// del demo y paginación client-side. Viven aparte de la pantalla para poder
// probarlos sin montar React (clientes-vista.test.ts).

/** Tamaño de página de la cartera de clientes (mismo criterio que cartera.tsx). */
export const CLIENTES_POR_PAGINA = 50

/** Minúsculas y sin acentos (es-PE) para comparar texto — patrón norm() del topbar. */
export function normalizar(s: string): string {
  return s
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
}

/** Lo mínimo de una fila que necesita la regla de cartera (subset de ClienteBasico). */
export interface FilaCartera {
  asesor_perfil_id: string | null
  creado_por: string | null
}

/**
 * Dueño de cartera de la fila — ESPEJO EXACTO de la regla del servidor
 * (crear_contrato y perfiles_analista_update): manda asesor_perfil_id y, solo
 * si es NULL, hereda quien registró al cliente (creado_por).
 */
export function duenoDeCartera(fila: FilaCartera): string | null {
  return fila.asesor_perfil_id ?? fila.creado_por
}

/**
 * ¿La fila es de MI cartera? Es el gate POR FILA de "Corregir" y "+ Contrato":
 * el flag global puede_contratar NO alcanza — el servidor exige cartera fila a
 * fila, y ofrecer el botón para recibir "Solo puedes crear contratos para
 * clientes de tu cartera" es exactamente el bug que esta regla corrige (mismo
 * patrón que el bug del convertir).
 */
export function esMiCliente(fila: FilaCartera, miId: string | null | undefined): boolean {
  return miId != null && miId !== '' && duenoDeCartera(fila) === miId
}

/** Campos de un cliente sobre los que busca/filtra la pantalla. */
export interface ClienteBuscable extends FilaCartera {
  nombre_completo: string
  dni: string | null
  correo: string | null
  telefono: string | null
}

/** 'todos' | 'sin_asesor' | perfil_id de un miembro del roster. */
export type FiltroAsesor = string

/**
 * Búsqueda (nombre/documento/correo/teléfono, insensible a mayúsculas y
 * acentos) + filtro por asesor. El filtro compara contra el DUEÑO de cartera
 * (asesor o, sin asesor, el creador) — lo mismo que muestra la columna Asesor,
 * para que filtrar nunca contradiga lo que se ve. El teléfono también matchea
 * por solo-dígitos ('987 120' encuentra '+51987120345').
 */
export function filtrarClientes<T extends ClienteBuscable>(
  clientes: T[],
  q: string,
  fAsesor: FiltroAsesor,
  /**
   * perfil_id del roster visible. La columna Asesor pinta '—' cuando el dueño
   * NO resuelve contra el roster (p.ej. un cliente dado de alta por un admin
   * del portal, que no es fuerza comercial): 'Sin asesor' debe atrapar TAMBIÉN
   * esas filas, o dos '—' idénticos se comportarían distinto al filtrar
   * (hallazgo de revisión 2026-07-16).
   */
  rosterIds?: ReadonlySet<string>,
): T[] {
  const nq = normalizar(q.trim())
  const dq = nq.replace(/\D/g, '') // versión solo-dígitos para teléfono
  return clientes.filter((c) => {
    const dueno = duenoDeCartera(c)
    const duenoVisible = dueno != null && (rosterIds == null || rosterIds.has(dueno))
    if (fAsesor === 'sin_asesor') {
      if (duenoVisible) return false
    } else if (fAsesor !== 'todos' && dueno !== fAsesor) {
      return false
    }
    if (!nq) return true
    if (normalizar(c.nombre_completo).includes(nq)) return true
    // El documento puede ser alfanumérico (pasaporte): normalizar cubre may/min.
    if (c.dni != null && normalizar(c.dni).includes(nq)) return true
    if (c.correo != null && normalizar(c.correo).includes(nq)) return true
    if (c.telefono != null) {
      if (normalizar(c.telefono).includes(nq)) return true
      if (dq !== '' && c.telefono.replace(/\D/g, '').includes(dq)) return true
    }
    return false
  })
}

/**
 * Recorte de ámbito para la cartera DEMO. En la ruta real este recorte lo hace
 * el SERVIDOR (la vista crm.clientes_basicos ya llega scopeada por rol); el
 * demo no tiene servidor y lo espeja aquí: gerencia/directorio (esGlobal) ven
 * todo, el resto ve las filas cuyo dueño de cartera está en su equipo visible
 * (yo + mis vendedores).
 */
export function carteraDelAmbito<T extends FilaCartera>(
  clientes: T[],
  idsVisibles: ReadonlySet<string>,
  esGlobal: boolean,
): T[] {
  if (esGlobal) return clientes
  return clientes.filter((c) => {
    const dueno = duenoDeCartera(c)
    return dueno != null && idsVisibles.has(dueno)
  })
}

export interface Paginado<T> {
  visibles: T[]
  paginas: number // mínimo 1 (una "página vacía" para el estado sin items)
  paginaActual: number // ya clampeada a [0, paginas-1]
}

/**
 * Paginación client-side (mismo patrón que cartera.tsx). `pagina` fuera de
 * rango se clampea — al filtrar puede quedar apuntando a una página que ya no
 * existe y la pantalla no debe quedarse en blanco.
 */
export function paginar<T>(items: T[], pagina: number, porPagina = CLIENTES_POR_PAGINA): Paginado<T> {
  const paginas = Math.max(1, Math.ceil(items.length / porPagina))
  const paginaActual = Math.min(Math.max(pagina, 0), paginas - 1)
  const visibles = items.slice(paginaActual * porPagina, (paginaActual + 1) * porPagina)
  return { visibles, paginas, paginaActual }
}
