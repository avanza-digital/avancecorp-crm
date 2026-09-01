// Modelo puro de la ficha comercial 360. Reúne en una sola fuente las reglas
// de alcance, escritura y continuidad comercial para que la tabla y la ficha
// no terminen ofreciendo acciones distintas sobre el mismo cliente.
import { fechaLima } from './agenda-derivada'
import type { GrupoCartera } from './cartera-vista'
import type { ContratoRow } from './clientes-tipos'
import { can, puedeEscribir, type Rol } from './roles'
import type { Miembro, Tarea } from './tipos'

export interface ResolverContextoFichaClienteInput {
  grupo: GrupoCartera
  equipo: readonly Miembro[]
  yoId: string | null | undefined
  rol: Rol | null | undefined
  /** Autoridad contractual que llega del Portal para esta sesión. */
  puedeContratar: boolean
}

/** Fotografía de alcance y capacidad al abrir una ficha de cliente. */
export interface ContextoFichaCliente {
  clienteId: string
  analistaNombre: string | null
  /** Puede abrir y leer la ficha; no implica permiso para cambiar datos. */
  consultable: boolean
  /** Puede consultar datos bancarios del cliente; Directorio queda excluido. */
  puedeVerCuentas: boolean
  /** Puede iniciar contacto externo desde la ficha; Directorio solo audita. */
  puedeContactar: boolean
  /** Puede planificar seguimiento comercial sobre una fila activa. */
  gestionable: boolean
  /** Puede registrar, aumentar o renovar una inversión sobre una fila activa. */
  accionable: boolean
  /** El cliente cumple las precondiciones comerciales para operar. */
  operable: boolean
  motivoNoOperable: string | null
  /** Gerencia puede corregir sin la ventana temporal del analista. */
  edicionGlobal: boolean
}

/**
 * Resuelve por separado lectura, escritura y operabilidad. Esta separación es
 * deliberada: Directorio puede consultar toda la cartera, pero nunca escribir.
 */
export function resolverContextoFichaCliente({
  grupo,
  equipo,
  yoId,
  rol,
  puedeContratar,
}: ResolverContextoFichaClienteInput): ContextoFichaCliente {
  const { cliente } = grupo
  const analistaId = cliente.asesor_perfil_id
  // La fuente canónica del servidor conserva el fallback histórico: mientras
  // no exista una asignación explícita, quien registró al cliente mantiene la
  // cartera. La ficha debe usar el mismo dueño efectivo que la lista.
  const responsableId = analistaId ?? cliente.creado_por
  const dentroDelAmbito =
    can(rol, 'verTodo') ||
    // `vendedor` es el identificador técnico legado del rol; la interfaz y el
    // dominio lo presentan siempre como Analista.
    (rol === 'vendedor' && yoId != null && yoId !== '' && responsableId === yoId) ||
    // La lista del supervisor ya viene recortada por clientes_basicos_fn. No
    // reconstruimos aquí el subárbol con el roster operativo porque ese roster
    // excluye analistas inactivos que el supervisor aún debe poder consultar y
    // reasignar. La RPC de la ficha vuelve a validar el alcance en el servidor.
    rol === 'supervisor'
  const consultable = can(rol, 'verCartera') && dentroDelAmbito
  const puedeVerCuentas =
    consultable && cliente.activo && (rol === 'vendedor' || rol === 'supervisor' || rol === 'gerencia')
  const puedeContactar =
    consultable && cliente.activo && (rol === 'vendedor' || rol === 'supervisor' || rol === 'gerencia')
  const escrituraHabilitada = puedeEscribir(rol)
  const analista = analistaId ? equipo.find((miembro) => miembro.perfil_id === analistaId) : undefined
  const responsable = responsableId ? equipo.find((miembro) => miembro.perfil_id === responsableId) : undefined
  const analistaActivo =
    responsableId != null &&
    (responsable == null
      ? responsableId === yoId
      : responsable.activo && (responsable.rol_crm === 'vendedor' || responsable.rol_crm === 'supervisor'))
  const operable = cliente.activo && analistaActivo
  const motivoNoOperable = !cliente.activo
    ? 'Este cliente está dado de baja. Solicita su reactivación para continuar.'
    : !analistaActivo
      ? 'Este cliente no tiene un analista disponible. Solicita su asignación para continuar.'
      : null

  return {
    clienteId: cliente.id,
    analistaNombre: analista?.nombre_completo ?? (analistaId ? 'No disponible' : null),
    consultable,
    puedeVerCuentas,
    puedeContactar,
    gestionable: consultable && escrituraHabilitada && cliente.activo,
    accionable: consultable && escrituraHabilitada && puedeContratar && cliente.activo,
    operable,
    motivoNoOperable,
    edicionGlobal: consultable && escrituraHabilitada && puedeContratar && can(rol, 'verTodo'),
  }
}

export interface ContratoVistaCliente360 {
  contrato: ContratoRow
  /** Ya llegó la fecha final en Lima y el ciclo del contrato admite renovación. */
  renovable: boolean
}

export interface VistaCliente360 {
  /** Capital vigente separado por moneda: estos importes nunca se suman. */
  capitalVigente: {
    PEN: number
    USD: number
  }
  contratosActivos: number
  tieneCapital: boolean
  proximoVencimiento: string | null
  hoyLima: string
  tareasPendientes: Tarea[]
  proximaTarea: Tarea | null
  contratos: ContratoVistaCliente360[]
}

function instanteDeTarea(tarea: Tarea): number | null {
  const instante = Date.parse(tarea.vence_en)
  return Number.isFinite(instante) ? instante : null
}

function compararTareasPorVencimiento(a: Tarea, b: Tarea): number {
  const instanteA = instanteDeTarea(a)
  const instanteB = instanteDeTarea(b)
  if (instanteA != null && instanteB != null && instanteA !== instanteB) {
    return instanteA - instanteB
  }
  if (instanteA != null && instanteB == null) return -1
  if (instanteA == null && instanteB != null) return 1
  return a.vence_en.localeCompare(b.vence_en) || a.id.localeCompare(b.id)
}

function fechaCalendarioValidaEnLima(fecha: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(fecha)) return false
  // Medianoche de Lima expresada en UTC. Comparar el resultado evita aceptar
  // fechas que Date normaliza en silencio, por ejemplo 2026-02-31.
  const instante = Date.parse(`${fecha}T05:00:00.000Z`)
  return Number.isFinite(instante) && fechaLima(instante) === fecha
}

function contratoRenovable(contrato: ContratoRow, hoyLima: string): boolean {
  const estadoAdmiteRenovacion = contrato.estado === 'activo' || contrato.estado === 'vencido'
  return (
    estadoAdmiteRenovacion &&
    fechaCalendarioValidaEnLima(contrato.fecha_vencimiento) &&
    contrato.fecha_vencimiento <= hoyLima
  )
}

/**
 * Destaca primero una renovación que ya requiere atención; si no existe,
 * muestra el vencimiento futuro más cercano de una inversión vigente.
 */
function vencimientoDestacado(contratos: readonly ContratoRow[], hoyLima: string): string | null {
  const fechas = contratos
    .filter(
      (contrato) =>
        (contrato.estado === 'activo' || contrato.estado === 'vencido') &&
        fechaCalendarioValidaEnLima(contrato.fecha_vencimiento),
    )
    .map((contrato) => contrato.fecha_vencimiento)
  const pendientes = fechas.filter((fecha) => fecha <= hoyLima).sort((a, b) => b.localeCompare(a))
  if (pendientes[0]) return pendientes[0]
  return fechas.filter((fecha) => fecha > hoyLima).sort((a, b) => a.localeCompare(b))[0] ?? null
}

/**
 * Construye la vista comercial sin mutar el grupo ni la agenda recibida.
 * Conserva PEN/USD separados, deja solo tareas vivas de este cliente, ordena
 * la más urgente primero y decide renovaciones con el día calendario de Lima.
 */
export function construirVistaCliente360(
  grupo: GrupoCartera,
  tareas: readonly Tarea[],
  ahora: number,
): VistaCliente360 {
  const hoyLima = fechaLima(ahora)
  const tareasPendientes = tareas
    .filter(
      (tarea) =>
        tarea.perfil_id === grupo.cliente.id &&
        tarea.estado === 'pendiente' &&
        tarea.activo &&
        instanteDeTarea(tarea) != null,
    )
    .sort(compararTareasPorVencimiento)

  return {
    capitalVigente: {
      PEN: grupo.capitalActivoPen,
      USD: grupo.capitalActivoUsd,
    },
    contratosActivos: grupo.contratosActivos,
    tieneCapital: grupo.tieneCapital,
    proximoVencimiento: vencimientoDestacado(grupo.contratos, hoyLima),
    hoyLima,
    tareasPendientes,
    proximaTarea: tareasPendientes[0] ?? null,
    contratos: grupo.contratos.map((contrato) => ({
      contrato,
      renovable: contratoRenovable(contrato, hoyLima),
    })),
  }
}
