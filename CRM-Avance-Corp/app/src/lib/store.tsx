// Store DEMO del CRM (F1b) — fuente de verdad de leads/actividades en memoria,
// sembrada desde lib/demo.ts y persistida en sessionStorage. JAMÁS escribe en
// Supabase. Write-gating con doble defensa: la UI oculta acciones y el store
// re-valida CADA mutación (toast.error + no-op si el rol no puede escribir).
// Debe montarse DENTRO de AuthProvider (usa useAuth para el gating y el autor).
import { useCallback, useEffect, useMemo, useRef, useState, type JSX, type ReactNode } from 'react'
import { toast } from 'sonner'
import { crmQueryKeys } from '@/data/crm-queries'
import { queryClient } from './query-client'
import { useAuth } from './auth-context'
import { INFO_COOPERATIVA, type Cooperativa } from './cierres-externos'
import type { CierreEstado } from './cierre-estado'
import { administraSoloRolesCrm, can, puedeEscribir } from './roles'
import {
  ETAPA_INFO,
  MOTIVOS_DESCARTE,
  TERMINALES_K,
  TIPOS_AUTO_K,
  TIPOS_CONTACTO_K,
  type Actividad,
  type CategoriaInteres,
  esTipoTarea,
  type Etapa,
  type EtapaActiva,
  type Genero,
  type Lead,
  type ModalidadReunion,
  type MotivoNoRealizada,
  type ResultadoReunion,
  type Tarea,
  type Miembro,
  type MotivoDescarte,
  type Origen,
  type TipoActividad,
  type TipoActividadManual,
} from './tipos'
import { esAbierto } from './inteligencia'
import { avancePorContacto, avancePorReunion, retrocesoPorAnularReunion } from './avance-automatico'
import { MOTIVOS_CON_EVIDENCIA, vetoNoResponde } from './descarte-evidencia'
import { agendaDeTareas, type EventoAgenda } from './agenda-derivada'
import { validarReunionOperativa, type ReunionOperativaInvalida } from './reunion-operativa'
import type { Moneda } from './format'
import { DEMO_HABILITADO } from './config'
import { validarCamposLead, type CampoLead, type CodigoValidacion } from './validacion'
import { registrarError } from './observabilidad'
import { PanelActionsContext, PanelStateContext, StoreDataContext, StoreEstadoContext } from './store-context'
import {
  actualizarLead,
  CrmApiError,
  insertarActividad,
  insertarLead,
  insertarTarea,
  actualizarTarea,
  cerrarReunion,
  cerrarTarea,
  listarActividadesDelAmbito,
  listarEquipo,
  listarLeadsDelAmbito,
  obtenerCumplimientoMetas,
  obtenerMetasDelMes,
  listarTareasDelAmbito,
  reprogramarReunion,
} from '@/data/crm-api'
import {
  cumplimientoDesdeRpc,
  objetivosCero,
  objetivosDesdeConfiguracion,
  periodoLima,
  type CumplimientoMetasJerarquico,
  type ObjetivoComercial,
  type ObjetivosPorRol,
  type ObjetivosPorVendedor,
} from './objetivos'
import { presentarDisponibilidadLead } from './disponibilidad-lead'

/**
 * Estado de la CARGA remota (solo sesión real). La app lo usa para decidir
 * entre splash, pantalla de error con reintento y el workspace: sin esto, un
 * fallo de red pintaba el CRM VACÍO como si "no hubiera leads" (hallazgo de la
 * revisión adversarial). En demo siempre es inerte (cargando/error = false).
 */
export interface StoreEstado {
  cargando: boolean
  error: boolean
  reintentar: () => void
}

/**
 * Presupuesto de la carga inicial de la sesión real. Un fetch que se CUELGA no
 * rechaza nunca: sin este límite el asesor se queda para siempre mirando
 * «Preparando tu información…», y un spinner eterno es peor que un error porque
 * no ofrece salida. Al vencer se abortan los fetch y se muestra el estado
 * accionable de error + reintentar. Holgado a propósito: el arranque real
 * (leads + equipo + actividades + tareas + metas) puede tardar varios segundos
 * en 4G, así que esto NO recorta la carga normal.
 */
export const LIMITE_CARGA_REAL_MS = 20_000

// v2: F1c re-siembra (20 leads + asignado_supervisor_id) — la clave vieja se ignora.
const CLAVE = 'ac-crm-demo-datos-v2'

/** Códigos de fallo de una mutación (además de los de validación de campos). */
export type CodigoMut =
  | CodigoValidacion
  | 'sin_permiso'
  | 'fuente_no_habilitada'
  | 'no_encontrado'
  | 'duplicado_telefono'
  | 'duplicado_dni'
  | 'etapa_terminal_al_nacer'
  | 'lead_cerrado'
  | 'cerrar_con_flujo'
  | 'solo_reabrir_descartado'
  | 'sin_analista'
  | 'vendedor_no_encontrado'
  | 'vendedor_fuera_ambito'
  | 'solo_autoasignar'
  | 'tipo_actividad_reservado'
  | 'resultado_obligatorio'
  | 'modalidad_reunion_obligatoria'
  | 'destino_reunion_obligatorio'
  | 'enlace_reunion_invalido'
  | 'sin_permiso_reasignar'
  // Anulación de un cierre en cooperativa (espejo de los rechazos del servidor).
  | 'motivo_requerido'
  | 'ya_anulado'
  // Anulación de un cierre de AVANCE (espejo de `crm.anular_cierre_avance`).
  | 'cierre_en_cooperativa'
  | 'sin_cierre'

/**
 * Resultado de una mutación. `error` es el mensaje es-PE listo para mostrar;
 * `codigo` identifica el fallo de forma estable y `campo` (si aplica) ancla el
 * error a un campo del formulario — la UI NUNCA debe adivinar por regex sobre
 * el texto del mensaje.
 */
export interface ResultadoMut {
  ok: boolean
  error?: string
  codigo?: CodigoMut
  campo?: CampoLead
}

/**
 * Confirmación asíncrona de una escritura real. El store conserva su contrato
 * síncrono para validar y aplicar el espejo optimista, pero los flujos que no
 * pueden anunciar éxito antes del commit (como el alta de un lead) esperan
 * esta promesa. Nunca rechaza: el error ya sale sanitizado para la interfaz.
 */
export interface ResultadoPersistencia {
  ok: boolean
  error?: string
  codigo?: string
}

/**
 * Alta optimista de una tarea. El store real entrega `persistido` junto al id:
 * quien vaya a anunciar un éxito definitivo debe esperar esa confirmación y no
 * confundir el espejo local con un commit del servidor.
 *
 * Los campos quedan opcionales por compatibilidad con consumidores históricos
 * que solo necesitan validación síncrona; el provider real siempre devuelve los
 * tres campos de confirmación cuando `ok` es true.
 */
export type ResultadoCrearTarea = ResultadoMut & {
  id?: string
  avance?: EtapaActiva
  persistido?: Promise<ResultadoPersistencia>
}

/**
 * Un id de alta solo puede existir acompañado por la confirmación del commit.
 * El tipo impide que otro provider represente «creado» sin `persistido`.
 */
export type ResultadoCrearLead =
  | (ResultadoMut & { id?: never; persistido?: never })
  | (ResultadoMut & { id: string; persistido: Promise<ResultadoPersistencia> })

export interface NuevoLeadInput {
  nombre_completo: string
  telefono: string
  correo?: string | null
  dni?: string | null
  genero?: Genero | null
  fecha_nacimiento?: string | null
  distrito?: string | null
  origen: Origen
  etapa?: EtapaActiva // default 'nuevo' — un lead NUNCA nace terminal
  monto_estimado: number
  moneda: Moneda
  categoria_interes?: CategoriaInteres | null
  vendedor_id?: string | null
  nota?: string | null
}

/** Alta de tarea de agenda (quick-add del drawer / futuro + Nueva). */
interface NuevaTareaBase {
  tipo: string // esTipoTarea hace el narrow
  titulo: string
  vence_en: string // ISO
  nota?: string | null
  duracion_min?: number | null
  modalidad_reunion?: ModalidadReunion | null
  ubicacion_reunion?: string | null
  enlace_reunion?: string | null
}

/** Exactamente un sujeto, igual que CHECK tareas_un_solo_sujeto. */
export type NuevaTareaInput = NuevaTareaBase &
  ({ lead_id: string; perfil_id?: never } | { perfil_id: string; lead_id?: never })

/** Cierre de una tarea de agenda (motor Fase B): resultado 1-tap + siguiente. */
export interface CompletarTareaInput {
  tarea_id: string
  estado: 'completada' | 'no_show'
  resultado_tipo?: TipoActividadManual | null
  resultado_detalle?: string | null
  resultado_reunion?: Exclude<ResultadoReunion, 'sin_clasificar'> | null
  motivo_no_realizada?: MotivoNoRealizada | null
  siguiente?: {
    tipo: string
    titulo: string
    vence_en: string
    modalidad_reunion?: ModalidadReunion | null
    ubicacion_reunion?: string | null
    enlace_reunion?: string | null
  } | null
}

/** Cambios editables de la ficha (espejo del contrato F1b). */
export type CambiosLead = Partial<
  Pick<
    Lead,
    | 'nombre_completo'
    | 'telefono'
    | 'correo'
    | 'monto_estimado'
    | 'moneda'
    | 'categoria_interes'
    | 'origen'
    | 'nota'
    | 'dni'
    | 'distrito'
    | 'genero'
    | 'fecha_nacimiento'
  >
>

/**
 * Ámbito por rol (espejo de la RLS jerárquica de F0 — contrato F1c).
 * TODAS las pantallas (y la búsqueda del topbar) deben leer de aquí en vez
 * del `leads` global:
 *  - vendedor: leads con vendedor_id === yo.id
 *  - supervisor: los suyos + los de sus vendedores + parkeados con
 *    asignado_supervisor_id === yo.id (vendedor_id null)
 *  - gerencia y directorio: todos
 */
export interface Ambito {
  leads: Lead[] // recortado por rol
  vendedores: Miembro[] // vendedores visibles/filtrables (supervisor: los suyos; gerencia/directorio: todos)
  esGlobal: boolean // true para gerencia/directorio
}

// El contrato de display vive en lib/agenda-derivada (timestamp→label, Lima);
// se re-exporta para no romper a los consumidores históricos del store.
export type { EventoAgenda }

// El contrato de metas vive en lib/objetivos. Las metas de supervisor y
// empresa se derivan siempre desde las filas individuales versionadas.
export type { ObjetivoComercial, ObjetivosPorRol, ObjetivosPorVendedor }

/** Foto DEMO de un cierre en cooperativa (espejo mínimo de crm.cierres_externos). */
export interface CierreExternoDemo {
  /** Identidad propia: sin ella no se puede corregir ni anular en demo, y las
   * dos acciones de gerencia quedarían sin ensayar en el mundo de práctica. */
  cierreId: string
  leadId: string
  cooperativa: Cooperativa
  monto: number
  /** Siempre 'PEN': en cooperativas solo se invierte en soles. */
  moneda: Moneda
  nombre: string
  telefono: string
  numeroTransaccion: string
  creadoEn: string
  /** Quién cobra el cierre (foto del analista del lead al convertir). */
  vendedorId: string
  vendedorNombre: string | null
  /** Anulado por gerencia: deja de contar, pero la fila se sigue viendo. */
  anuladoEn: string | null
  motivoAnulacion: string | null
}

export interface StoreDataApi {
  leads: Lead[] // todos, activos y terminales (legacy — preferir `ambito`)
  equipo: Miembro[]
  ambito: Ambito
  agenda: EventoAgenda[]
  objetivos: ObjetivosPorRol
  /**
   * ¿Falló la LECTURA de las metas del mes? Cuando es `true`, los ceros de
   * `objetivos` NO son un dato: no sabemos si gerencia fijó metas o no.
   *
   * El consumidor (la franja de meta en Hoy) DEBE mirarlo antes de decir «Meta
   * mensual por definir»: afirmar ausencia cuando lo que hubo fue un error de
   * red le hace creer al asesor que nadie fijó su meta. Con `true` el copy
   * honesto es «No pudimos cargar tu meta del mes» + reintentar (`recargar()`).
   */
  objetivosError: boolean
  /**
   * Resultado mensual autoritativo de `crm.cumplimiento_metas_fn`: capital y
   * contratos confirmados (PEN/USD y categoría preservados), más conversión
   * sobre la cohorte de leads resueltos del periodo.
   */
  cumplimientoMetas: CumplimientoMetasJerarquico | null
  /** Falló el cálculo confirmado; nunca se reemplaza por pipeline abierto. */
  cumplimientoMetasError: boolean
  // Crudas, para lib/inteligencia (colaDe, estancados…). OJO: es el timeline
  // GLOBAL sin recorte (la RLS actividades_select SÍ recorta a leads visibles):
  // toda lista visible al usuario debe cruzarse con ambito.leads, nunca
  // iterarse directo — salvo el lector global (directorio).
  actividades: Actividad[]
  // Timeline YA recortado a los leads del ámbito (espejo de actividades_select).
  // Para cualquier lista visible al usuario, PREFERIR esto sobre `actividades`:
  // el recorte lo garantiza el store, no la disciplina de cada pantalla.
  actividadesDelAmbito: Actividad[]
  lead(id: string): Lead | undefined
  actividadesDe(leadId: string): Actividad[] // orden desc por creado_en
  // Mutaciones — TODAS write-gated dentro del store
  // Agenda (crm.tareas): la fuente de verdad son las TAREAS; `agenda` es su
  // vista de display derivada (labels Lima). tareasDe alimenta el drawer.
  tareas: Tarea[]
  tareasDe(leadId: string): Tarea[] // pendientes del lead, orden por vence_en
  tareasDeCliente?(perfilId: string): Tarea[] // postventa, misma agenda
  /** `avance` = etapa a la que subió el lead SOLO por agendar esta tarea
   *  (espejo de `trg_zz_tareas_avance_etapa`: una reunión futura con quien ya
   *  se trabajó sube a `reunion_agendada`). Se DEVUELVE, como en
   *  `registrarActividad` y `completarTarea`, porque la UI tiene que cantarlo:
   *  agendar desde la ficha movía el lead de etapa EN SILENCIO y el asesor veía
   *  saltar el stepper sin saber quién lo tocó. */
  crearTarea(input: NuevaTareaInput): ResultadoCrearTarea
  /** Cierra por la RPC atómica (resultado→log + siguiente encadenada). En
   *  llamadas COMPLETADAS el resultado es obligatorio (patrón Outreach). */
  /** `avance` = etapa a la que subió SOLO el lead por este cierre (el contacto
   *  registrado o la reunión encadenada). La UI lo dice en voz alta: un cambio
   *  de etapa silencioso asusta más que ayuda.
   *
   *  `persistido` = promesa de la escritura REAL (ver `persistir`): resuelve
   *  `true` cuando la RPC ya commiteó en el servidor y `false` si la rechazó.
   *  La necesita quien encadene otra escritura detrás del cierre y cuyo orden
   *  en el SERVIDOR no sea negociable (ver `cerrarPorNoResponde` en
   *  components/app/cerrar-tarea.tsx: descartar el lead cancela sus tareas
   *  pendientes por trigger, así que el cierre tiene que haber commiteado
   *  antes). En demo resuelve `true` de inmediato. */
  completarTarea(input: CompletarTareaInput): ResultadoMut & {
    siguiente_id?: string
    avance?: EtapaActiva
    persistido?: Promise<boolean>
  }
  /** Reprogramar = mover vence_en de una PENDIENTE (el contador lo lleva el trigger). */
  reprogramarTarea(id: string, venceEn: string): ResultadoMut
  /** Anti no-show: el cliente respondió al recordatorio confirmando la cita. */
  confirmarTarea(id: string): ResultadoMut
  /** ANULAR — el cuarto verbo de una tarea: «esto ya no hace falta».
   *  Ni cierra con resultado, ni reprograma, ni confirma. NO escribe actividad
   *  de contacto (ver la implementación: cualquier fila de trabajo comercial en
   *  el timeline movería el reloj de la cola). Solo tareas PENDIENTES; una
   *  cerrada es inmutable.
   *
   *  `retroceso` = etapa a la que BAJÓ el lead por esta anulación (espejo de
   *  `private.retroceso_por_anular_reunion`: anular la última reunión viva sin
   *  reagendar devuelve el lead a `contactado`, o a `nuevo` si nunca hubo
   *  contacto real). Se DEVUELVE por la misma razón que `avance` en los otros
   *  tres escritores: mover la etapa en silencio asusta más que ayuda. */
  anularTarea(
    id: string,
    cierreReunion?: { motivo: MotivoNoRealizada; detalle?: string | null },
  ): ResultadoMut & { retroceso?: EtapaActiva }
  crearLead(input: NuevoLeadInput): ResultadoCrearLead
  editarLead(id: string, cambios: CambiosLead): ResultadoMut
  /** `capital` (opcional) viaja EN LA MISMA escritura que la etapa: pasar a
   *  "Propuesta enviada" es el momento de fijar lo que de verdad se propuso, y
   *  partirlo en dos updates dejaría el lead avanzado con la cifra vieja si el
   *  segundo falla. PEN y USD JAMÁS se suman: la moneda viaja con el monto. */
  cambiarEtapa(id: string, etapa: EtapaActiva, capital?: { monto_estimado: number; moneda: Moneda }): ResultadoMut
  descartar(id: string, motivo: MotivoDescarte, nota?: string): ResultadoMut
  convertir(id: string): ResultadoMut
  /** Cierre en COOPERATIVA (Qorilazo/Prodelco) — SOLO demo: marca convertido y
   *  guarda la foto local para que Mi cartera derive su sección. En real este
   *  camino se veta (la ficha llama a crm.convertir_lead_externo, que deja la
   *  foto de verdad; marcar la etapa por aquí dejaría un convertido sin cierre
   *  y la P4 del servidor lo rechazaría). */
  convertirExterno(
    id: string,
    datos: {
      cooperativa: Cooperativa
      monto: number
      numeroTransaccion: string
    },
  ): ResultadoMut
  /** Anulación de gerencia — SOLO demo (en real es crm.anular_cierre_externo).
   *  Deja de contar en cuota y conversión, con motivo; el lead NO se reabre y la
   *  fila se sigue viendo, marcada. De una sola dirección, igual que el servidor. */
  anularCierreExterno(cierreId: string, motivo: string): ResultadoMut
  /** Anulación de gerencia sobre un cierre de AVANCE — SOLO demo (en real es
   *  `crm.anular_cierre_avance`). Va por LEAD y no por cierre porque en Avance no
   *  hay fila de cierre: el cierre ES el lead convertido. Mismas negativas que el
   *  servidor, incluida la del cierre en cooperativa, que tiene su propia RPC. */
  anularCierreAvance(leadId: string, motivo: string): ResultadoMut
  /** Fotos DEMO de cierres en coops (en real siempre []: la RPC es la fuente). */
  cierresExternos: CierreExternoDemo[]
  /** El estado del cierre por lead, DERIVADO del mundo demo y en la MISMA forma
   *  que devuelve `crm.cierres_estado_fn`. Que las dos fuentes tengan una sola
   *  forma es lo que permite que la ficha y la cartera no sepan en qué mundo
   *  están: si el demo tuviera forma propia, cada pantalla tendría dos caminos y
   *  uno de los dos envejecería sin que nadie lo notara. */
  cierresEstado: CierreEstado[]
  reabrir(id: string): ResultadoMut
  /** `avance` = etapa a la que subió SOLO el lead por este contacto (ver
   *  lib/avance-automatico.ts). La UI lo usa para decirlo en voz alta: un
   *  cambio de etapa silencioso asusta más que ayuda. */
  registrarActividad(id: string, tipo: TipoActividadManual, detalle?: string): ResultadoMut & { avance?: EtapaActiva }
  reasignar(id: string, vendedorId: string | null): ResultadoMut
  // Refresco explícito desde el servidor (tras un flujo async que NO pasa por el
  // camino optimista: p. ej. la conversión lead→cliente vía edge). En demo es no-op.
  recargar(): Promise<boolean>
}

export interface PanelesState {
  leadAbiertoId: string | null
  nuevoLeadAbierto: boolean
  etapaInicial: EtapaActiva
  /** Teléfono precargado en el alta por el atajo «Verificar disponibilidad»
   *  del buscador (plan «lead libre», F1); null = alta en blanco. */
  telefonoInicial: string | null
}

export interface PanelesActions {
  abrirLead(id: string): void
  abrirNuevoLead(etapa?: EtapaActiva, telefonoInicial?: string): void
  cerrarPaneles(): void
}

interface Datos {
  leads: Lead[]
  actividades: Actividad[]
}

const EQUIPO_VACIO: Miembro[] = []
const OBJETIVOS_VACIOS: ObjetivosPorRol = objetivosCero()

interface Auxiliares {
  equipo: Miembro[]
  objetivos: ObjetivosPorRol
  /** true si la LECTURA de metas falló: los ceros de `objetivos` no son un dato. */
  objetivosError: boolean
  cumplimientoMetas: CumplimientoMetasJerarquico | null
  cumplimientoMetasError: boolean
}

const AUXILIARES_VACIOS: Auxiliares = {
  equipo: EQUIPO_VACIO,
  objetivos: OBJETIVOS_VACIOS,
  objetivosError: false,
  cumplimientoMetas: null,
  cumplimientoMetasError: false,
}

function datosVacios(): Datos {
  return { leads: [], actividades: [] }
}

// ── Helpers puros ─────────────────────────────────────────────────────────────

interface CamposReunionTarea {
  modalidad_reunion: ModalidadReunion | null
  ubicacion_reunion: string | null
  enlace_reunion: string | null
}

type EntradaReunionTarea = Pick<NuevaTareaInput, 'modalidad_reunion' | 'ubicacion_reunion' | 'enlace_reunion'>

type ReunionTareaPreparada = { ok: true; campos: CamposReunionTarea } | { ok: false; resultado: ResultadoMut }

const CAMPOS_SIN_REUNION: CamposReunionTarea = {
  modalidad_reunion: null,
  ubicacion_reunion: null,
  enlace_reunion: null,
}

/** Adapta el error del dominio al contrato estable que consumen las pantallas. */
function aResultadoReunionInvalida(error: ReunionOperativaInvalida): ResultadoMut {
  return { ok: false, codigo: error.codigo, error: error.error }
}

/**
 * Frontera única de escritura para los datos operativos de una reunión.
 * También limpia campos incompatibles para que demo, optimista y servidor
 * reciban exactamente la misma representación.
 */
function prepararReunionTarea(tipo: string, input: EntradaReunionTarea): ReunionTareaPreparada {
  if (tipo !== 'reunion') return { ok: true, campos: CAMPOS_SIN_REUNION }

  const reunion = validarReunionOperativa({
    modalidad: input.modalidad_reunion,
    ubicacion: input.ubicacion_reunion,
    enlace: input.enlace_reunion,
  })
  if (!reunion.ok) {
    return { ok: false, resultado: aResultadoReunionInvalida(reunion) }
  }

  return {
    ok: true,
    campos: {
      modalidad_reunion: reunion.modalidad,
      ubicacion_reunion: reunion.ubicacion,
      enlace_reunion: reunion.enlace,
    },
  }
}

/** ISO canónico compartido por alta, encadenamiento y reprogramación. */
function normalizarFechaTarea(venceEn: string): string | null {
  const ms = Date.parse(venceEn)
  return Number.isFinite(ms) ? new Date(ms).toISOString() : null
}

type ResultadoPersistenciaFallida = ResultadoPersistencia & {
  ok: false
  error: string
}

/** Traducción única de rechazos remotos; nunca expone errores crudos. */
function aResultadoPersistenciaFallida(causa: unknown): ResultadoPersistenciaFallida {
  const esErrorApi = causa instanceof CrmApiError
  const error = esErrorApi && causa.code !== 'POSTGREST_ERROR' ? causa.message : 'No se pudo guardar el cambio'
  return {
    ok: false,
    error,
    ...(esErrorApi && causa.code ? { codigo: causa.code } : {}),
  }
}

type SiguienteCierre = Exclude<Parameters<typeof cerrarTarea>[0]['siguiente'], undefined>

interface CierreTareaServidor {
  tarea: Pick<Tarea, 'id' | 'tipo' | 'lead_id' | 'perfil_id'>
  estado: CompletarTareaInput['estado'] | 'cancelada'
  resultadoTipo: TipoActividadManual | null
  resultadoDetalle: string | null
  resultadoReunion: Exclude<ResultadoReunion, 'sin_clasificar'> | null
  motivoNoRealizada: MotivoNoRealizada | null
  detalleReunion: string | null
  siguiente: SiguienteCierre
}

/** Selecciona una sola vez el contrato/RPC de cierre según el tipo de tarea. */
function ejecutarCierreTarea(input: CierreTareaServidor): Promise<void> {
  // cerrar_reunion sigue siendo el motor especializado del mundo LEAD. Para
  // clientes se usa cerrar_tarea: ese RPC escribe actividades_cliente y
  // conserva la clasificación sin contaminar etapas/SLA de leads.
  if (input.tarea.tipo === 'reunion' && input.tarea.lead_id) {
    return cerrarReunion({
      tarea_id: input.tarea.id,
      estado: input.estado,
      resultado_reunion: input.resultadoReunion,
      motivo_no_realizada: input.motivoNoRealizada,
      detalle: input.detalleReunion,
      siguiente: input.siguiente,
    }).then(() => undefined)
  }

  return cerrarTarea({
    tarea_id: input.tarea.id,
    estado: input.estado,
    resultado_tipo: input.resultadoTipo,
    // En reuniones este mismo campo alimenta tanto el detalle del timeline
    // como detalle_cierre_reunion. Importa especialmente al cancelar: allí no
    // hay resultado de actividad, pero sí puede haber explicación comercial.
    resultado_detalle: input.tarea.tipo === 'reunion' ? input.detalleReunion : input.resultadoDetalle,
    ...(input.tarea.tipo === 'reunion'
      ? {
          resultado_reunion: input.resultadoReunion,
          motivo_no_realizada: input.motivoNoRealizada,
        }
      : {}),
    siguiente: input.siguiente,
  }).then(() => undefined)
}

function uid(): string {
  try {
    return crypto.randomUUID()
  } catch {
    // La identidad optimista también es la llave idempotente de las RPC. Aun
    // en navegadores antiguos debe conservar formato UUID para viajar al
    // servidor; un id local ad-hoc produciría un alta confirmada imposible de
    // reconciliar si la respuesta usa otro identificador.
    const bytes = new Uint8Array(16)
    try {
      crypto.getRandomValues(bytes)
    } catch {
      for (let i = 0; i < bytes.length; i += 1) {
        bytes[i] = Math.floor(Math.random() * 256)
      }
    }
    bytes[6] = (bytes[6]! & 0x0f) | 0x40
    bytes[8] = (bytes[8]! & 0x3f) | 0x80
    const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('')
    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
  }
}

/** ¿El id local es un UUID válido para persistirlo tal cual en el servidor? */
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/**
 * Dedup vivo: teléfono/DNI no pueden repetirse entre leads abiertos. El índice
 * es GLOBAL (espejo del unique index parcial), pero el NOMBRE del lead en
 * conflicto solo se revela si el actor puede verlo (`visibles`) — sin esto, un
 * vendedor podía sondear teléfonos/DNIs ajenos y cosechar nombres de leads
 * fuera de su ámbito (fuga de PII detectada por los tests de auditoría).
 */
function conflictoDedup(
  leads: Lead[],
  telefono: string,
  dni: string | null | undefined,
  exceptoId?: string,
  visibles?: ReadonlySet<string>,
): ResultadoMut | null {
  const abiertos = leads.filter((l) => esAbierto(l) && l.id !== exceptoId)
  const nombreSeguro = (l: Lead): string | null => (visibles?.has(l.id) ? l.nombre_completo : null)
  const porTel = abiertos.find((l) => l.telefono === telefono)
  if (porTel) {
    const nombre = nombreSeguro(porTel)
    return {
      ok: false,
      codigo: 'duplicado_telefono',
      campo: 'telefono',
      error: nombre
        ? `Ese teléfono ya pertenece a un lead abierto: ${nombre}`
        : 'Ese teléfono ya pertenece a otro lead abierto de la empresa',
    }
  }
  if (dni) {
    const porDni = abiertos.find((l) => l.dni === dni)
    if (porDni) {
      const nombre = nombreSeguro(porDni)
      return {
        ok: false,
        codigo: 'duplicado_dni',
        campo: 'dni',
        error: nombre
          ? `Ese DNI ya pertenece a un lead abierto: ${nombre}`
          : 'Ese DNI ya pertenece a otro lead abierto de la empresa',
      }
    }
  }
  return null
}

function cargarDatos(semilla: Datos): Datos {
  try {
    const crudo = sessionStorage.getItem(CLAVE)
    if (crudo) {
      const d = JSON.parse(crudo) as Datos
      if (Array.isArray(d?.leads) && Array.isArray(d?.actividades)) return d
    }
  } catch {
    /* sesión privada o JSON corrupto → siembra fresca */
  }
  return structuredClone(semilla)
}

// ── Provider ──────────────────────────────────────────────────────────────────

export function StoreProvider({ children }: { children: ReactNode }): JSX.Element {
  const { yo } = useAuth()
  const demoSolicitado = DEMO_HABILITADO && yo?.demo === true
  // Sesión autenticada real (no demo): la capa de datos lee del servidor y la
  // RLS del esquema crm decide el ámbito; el navegador nunca recorta seguridad.
  const sesionReal = !!yo && yo.demo !== true
  const soloRoles = administraSoloRolesCrm(yo)
  // El store local solo contiene datos ficticios durante una sesión demo
  // explícita. Una sesión real nunca recibe ni persiste PII de demostración.
  const [datos, setDatos] = useState<Datos>(datosVacios)
  const [auxiliares, setAuxiliares] = useState<Auxiliares>(AUXILIARES_VACIOS)
  // Tareas de agenda (crm.tareas): pendientes del ámbito. Igual que leads:
  // optimista local + resync tras cada mutación real.
  const [tareas, setTareas] = useState<Tarea[]>([])
  // Cierres en coops del MODO DEMO (la sección «En cooperativas» de Mi cartera
  // los deriva). En real ni se llena: esa pantalla bebe de la RPC.
  const [cierresExternosDemo, setCierresExternosDemo] = useState<CierreExternoDemo[]>([])
  // Anulaciones de cierres de AVANCE del MODO DEMO. Van por lead porque en
  // Avance no hay fila de cierre que anular: el cierre es el lead convertido.
  const [anuladosAvanceDemo, setAnuladosAvanceDemo] = useState<{ leadId: string; anuladoEn: string; motivo: string }[]>(
    [],
  )
  const [demoListo, setDemoListo] = useState(false)
  const [realListo, setRealListo] = useState(false)
  const [errorReal, setErrorReal] = useState(false)
  // Reintento manual desde la pantalla de error: cambiar este contador vuelve a
  // disparar el efecto de carga (misma sesión, otra época).
  const [intentoReal, setIntentoReal] = useState(0)
  const demoActivo = demoSolicitado && demoListo
  const realActivo = sesionReal && realListo
  const equipo = auxiliares.equipo

  // Época de la sesión/carga: se incrementa en CADA corrida del efecto de datos
  // (login, cambio de usuario, logout, reintento). Toda resincronización captura
  // su época y descarta el resultado si la época ya cambió — así una resync
  // rezagada de A no repuebla el store de B tras un cambio de sesión (fuga de PII
  // que detectó la revisión adversarial), ni pisa datos de una recarga posterior.
  const epocaRef = useRef(0)

  // Paneles globales
  const [leadAbiertoId, setLeadAbiertoId] = useState<string | null>(null)
  const [nuevoLeadAbierto, setNuevoLeadAbierto] = useState(false)
  const [etapaInicial, setEtapaInicial] = useState<EtapaActiva>('nuevo')
  const [telefonoInicial, setTelefonoInicial] = useState<string | null>(null)

  const abrirLead = useCallback((id: string) => {
    setNuevoLeadAbierto(false)
    setLeadAbiertoId(id)
  }, [])
  const abrirNuevoLead = useCallback((etapa?: EtapaActiva, telefono?: string) => {
    setLeadAbiertoId(null)
    setEtapaInicial(etapa ?? 'nuevo')
    // El atajo del buscador llega con el teléfono ya tecleado; el alta normal
    // abre en blanco — el valor se fija en CADA apertura para que un atajo no
    // herede el teléfono del anterior.
    setTelefonoInicial(telefono ?? null)
    setNuevoLeadAbierto(true)
  }, [])
  const cerrarPaneles = useCallback(() => {
    setLeadAbiertoId(null)
    setNuevoLeadAbierto(false)
  }, [])

  const panelState = useMemo<PanelesState>(
    () => ({
      leadAbiertoId,
      nuevoLeadAbierto,
      etapaInicial,
      telefonoInicial,
    }),
    [leadAbiertoId, nuevoLeadAbierto, etapaInicial, telefonoInicial],
  )

  const panelActions = useMemo<PanelesActions>(
    () => ({
      abrirLead,
      abrirNuevoLead,
      cerrarPaneles,
    }),
    [abrirLead, abrirNuevoLead, cerrarPaneles],
  )

  // Carga de la sesión REAL. La RLS del esquema crm decide el ámbito; el
  // vendedor_nombre se resuelve con el roster (crm.leads solo guarda el id).
  const cargarReal = useCallback(
    async (signal?: AbortSignal) => {
      const periodoMetas = periodoLima(Date.now())
      if (soloRoles) {
        return {
          miembros: [] as Miembro[],
          actividades: [] as Actividad[],
          tareas: [] as Tarea[],
          objetivos: objetivosCero(periodoMetas),
          objetivosError: false,
          cumplimientoMetas: null,
          cumplimientoMetasError: false,
          leads: [] as Lead[],
        }
      }
      // El coordinador (C1) es OFF-ROSTER: no tiene cartera ni panel de equipo, y
      // su pantalla usa supervisores_para_reparto (no `ambito.equipo`). Se omite
      // listarEquipo porque equipo_visible_fn puede RAISE para su rol y el
      // Promise.all sin catch tumbaría su boot entero. Los demás fetches son
      // seguros: leen por RLS con ámbito ∅ → [] (la RLS filtra, no lanza).
      const esCoordinador = yo?.rol === 'coordinador'
      // Gerencia también opera la cartera completa: necesita las mismas fuentes
      // transaccionales que el resto del equipo además de sus RPC de inteligencia.
      // La RLS conserva el alcance real y excluye los soft-deletes.
      // Configuración y cumplimiento son auxiliares independientes: una caída
      // no puede convertirse en «sin meta» ni en resultados confirmados en cero.
      let objetivosError = false
      let cumplimientoMetasError = false
      const [leads, miembros, actividades, tareasAmbito, configuracionMetas, cumplimientoRpc] = await Promise.all([
        listarLeadsDelAmbito(signal),
        esCoordinador ? Promise.resolve<Miembro[]>([]) : listarEquipo(signal),
        listarActividadesDelAmbito(signal),
        listarTareasDelAmbito(signal),
        obtenerMetasDelMes(periodoMetas, signal).catch((error: unknown) => {
          registrarError('crm.metas.configuracion_boot_degradada', error)
          objetivosError = true
          return null
        }),
        obtenerCumplimientoMetas(periodoMetas, signal).catch((error: unknown) => {
          registrarError('crm.metas.cumplimiento_boot_degradado', error)
          cumplimientoMetasError = true
          return null
        }),
      ])
      let cumplimientoCoherente = cumplimientoRpc
      if (cumplimientoCoherente && !configuracionMetas) {
        // Sin la revisión de objetivos no hay denominador confiable para mostrar
        // el cumplimiento. Se conserva el error de configuración y se oculta el
        // numerador para que ningún ranking lo presente como «sin meta».
        cumplimientoCoherente = null
        cumplimientoMetasError = true
      } else if (
        cumplimientoCoherente &&
        configuracionMetas &&
        (cumplimientoCoherente.periodo !== configuracionMetas.periodo ||
          cumplimientoCoherente.revision !== configuracionMetas.revision)
      ) {
        registrarError(
          'crm.metas.revisiones_inconsistentes',
          new Error('Configuración y cumplimiento pertenecen a revisiones distintas'),
        )
        cumplimientoCoherente = null
        cumplimientoMetasError = true
      }
      const nombrePorId = new Map(miembros.map((m) => [m.perfil_id, m.nombre_completo]))
      return {
        miembros,
        actividades,
        tareas: tareasAmbito,
        objetivos: configuracionMetas
          ? objetivosDesdeConfiguracion(configuracionMetas, yo?.id)
          : objetivosCero(periodoMetas),
        objetivosError,
        cumplimientoMetas: cumplimientoCoherente ? cumplimientoDesdeRpc(cumplimientoCoherente, yo?.id) : null,
        cumplimientoMetasError,
        leads: leads.map((l) => ({
          ...l,
          vendedor_nombre: l.vendedor_id ? (nombrePorId.get(l.vendedor_id) ?? null) : null,
        })),
      }
    },
    [soloRoles, yo?.id, yo?.rol],
  )

  // Tras cada mutación real (éxito o rechazo) el SERVIDOR es la verdad: se
  // recargan leads/actividades/equipo para reflejar triggers y RLS (y, en un
  // rechazo, deshacer el espejo optimista). Devuelve `true` solo si el resultado
  // se APLICÓ (misma época): el llamador usa eso para no mentir en el toast de
  // rollback cuando el servidor está inalcanzable.
  const resincronizarReal = useCallback(async (): Promise<boolean> => {
    const miEpoca = epocaRef.current
    // Puente de coherencia F1 (TRANSITORIO hasta F3): mientras las mutaciones
    // pasen por el store, cada resincronización invalida por prefijo las
    // métricas del ámbito servidas por RPC — sin esto, crear o mover un lead
    // dejaría los tiles de Cartera/Pipeline contando el mundo de ANTES de la
    // escritura. Se dispara también en el resync de un rollback (costo: un
    // refetch de más en un caso raro; mentir en un tile sería peor).
    void queryClient.invalidateQueries({
      queryKey: crmQueryKeys.metricasAmbito(),
    })
    // F2: la tabla de Cartera ya NO se pinta desde este store — la sirve
    // `cartera_pagina_fn` por cursor. Sin esta segunda invalidación, crear o
    // mover un lead actualizaría los tiles y dejaría las FILAS de abajo en la
    // foto anterior. Invalidar (no refetch): un remonte dentro del staleTime
    // serviría la página rancia desde caché.
    void queryClient.invalidateQueries({ queryKey: crmQueryKeys.leads() })
    try {
      const {
        leads,
        actividades,
        miembros,
        tareas: tareasServidor,
        objetivos,
        objetivosError,
        cumplimientoMetas,
        cumplimientoMetasError,
      } = await cargarReal()
      // La sesión cambió (logout/otro usuario/recarga) mientras viajaba: se
      // descarta en vez de repoblar el store de otra sesión.
      if (epocaRef.current !== miEpoca) return false
      setDatos({ leads, actividades })
      setTareas(tareasServidor)
      setAuxiliares((prev) => ({
        ...prev,
        equipo: miembros,
        objetivos,
        objetivosError,
        cumplimientoMetas,
        cumplimientoMetasError,
      }))
      return true
    } catch (error: unknown) {
      registrarError('crm.resincronizacion_fallida', error)
      return false
    }
  }, [cargarReal])

  useEffect(() => {
    let cancelado = false
    const control = new AbortController()
    // Nueva corrida del efecto = nueva época: invalida cualquier resync en vuelo.
    epocaRef.current += 1
    setDemoListo(false)
    setRealListo(false)
    setErrorReal(false)

    // Sesión DEMO (solo DEV con flag). La condición usa flags de Vite directos
    // para que Rolldown elimine el chunk de fixtures en cualquier build de prod.
    if (demoSolicitado) {
      if (import.meta.env.DEV && import.meta.env.VITE_ENABLE_DEMO === 'true') {
        void import('./demo')
          .then((demo) => {
            if (cancelado) return
            setDatos(
              cargarDatos({
                leads: demo.LEADS_DEMO,
                actividades: demo.ACTIVIDADES_DEMO,
              }),
            )
            setTareas(demo.TAREAS_DEMO)
            setAuxiliares({
              equipo: demo.EQUIPO_DEMO,
              objetivos: demo.METAS_DEMO,
              objetivosError: false, // el demo no lee del servidor: nada que fallar
              cumplimientoMetas: demo.CUMPLIMIENTO_METAS_DEMO,
              cumplimientoMetasError: false,
            })
            setDemoListo(true)
          })
          .catch((error: unknown) => {
            if (cancelado) return
            registrarError('demo.carga_fallida', error)
            setDatos(datosVacios())
            setTareas([])
            setAuxiliares(AUXILIARES_VACIOS)
          })
      }
      return () => {
        cancelado = true
        control.abort()
      }
    }

    // Superadmin Portal sin Gerencia no tiene una sesión operativa: su única
    // superficie es Usuarios/roles. Se marca listo con un store vacío y no se
    // intenta ninguna lectura que el servidor debe negar.
    if (sesionReal && soloRoles) {
      setDatos(datosVacios())
      setTareas([])
      setAuxiliares(AUXILIARES_VACIOS)
      setRealListo(true)
      return () => {
        cancelado = true
        control.abort()
      }
    }

    // Sesión REAL: lee del servidor.
    if (sesionReal) {
      // Un cuelgue (fetch que ni resuelve ni rechaza) NO llega al .catch: sin
      // este reloj el splash se queda para siempre. Al vencer se abortan las
      // peticiones y se cae al MISMO estado accionable que un fallo.
      let agotado = false
      const relojCarga = setTimeout(() => {
        if (cancelado) return
        agotado = true
        registrarError(
          'crm.carga_real_colgada',
          new Error(`La carga inicial del CRM superó ${LIMITE_CARGA_REAL_MS} ms`),
        )
        control.abort() // corta los fetch en vuelo (no dejamos peticiones zombis)
        setDatos(datosVacios())
        setTareas([])
        setAuxiliares(AUXILIARES_VACIOS)
        setErrorReal(true)
      }, LIMITE_CARGA_REAL_MS)

      void cargarReal(control.signal)
        .then(
          ({
            leads,
            actividades,
            miembros,
            tareas: tareasServidor,
            objetivos,
            objetivosError,
            cumplimientoMetas,
            cumplimientoMetasError,
          }) => {
            clearTimeout(relojCarga)
            // `agotado`: una respuesta que llega DESPUÉS del límite ya no puede
            // borrar la pantalla de error que el asesor está viendo.
            if (cancelado || agotado) return
            setDatos({ leads, actividades })
            setTareas(tareasServidor)
            setAuxiliares({
              equipo: miembros,
              objetivos,
              objetivosError,
              cumplimientoMetas,
              cumplimientoMetasError,
            })
            setRealListo(true)
          },
        )
        .catch((error: unknown) => {
          clearTimeout(relojCarga)
          if (cancelado || agotado || control.signal.aborted) return
          registrarError('crm.carga_real_fallida', error)
          // Fallo de la carga inicial: NO se pinta el CRM vacío (parecería "no hay
          // leads"). Se marca error para que la app muestre reintento explícito.
          setDatos(datosVacios())
          setTareas([])
          setAuxiliares(AUXILIARES_VACIOS)
          setErrorReal(true)
        })
      return () => {
        cancelado = true
        clearTimeout(relojCarga)
        control.abort()
      }
    }

    // Ni demo ni sesión real: vacío.
    setDatos(datosVacios())
    setTareas([])
    setAuxiliares(AUXILIARES_VACIOS)
    return () => {
      cancelado = true
      control.abort()
    }
  }, [demoSolicitado, sesionReal, soloRoles, yo?.id, intentoReal, cargarReal])

  // Persistencia demo (solo sessionStorage — jamás Supabase)
  useEffect(() => {
    if (!demoActivo) return
    try {
      sessionStorage.setItem(CLAVE, JSON.stringify(datos))
    } catch {
      /* storage lleno o no disponible: seguimos solo en memoria */
    }
  }, [datos, demoActivo])

  // Ámbito por rol (reglas EXACTAS del contrato F1c — espejo de la RLS F0).
  // useMemo PROPIO con deps [datos, yo]: abrir/cerrar paneles NO debe regenerar
  // las referencias de ambito.leads/vendedores (los useMemo de las pantallas
  // dependen de ellas y recalcularían colaDe/metricasPorVendedor sin motivo).
  const ambito = useMemo<Ambito>(() => {
    const rol = yo?.rol
    const miId = yo?.id ?? null
    if (can(rol, 'verTodo')) {
      // gerencia y directorio: todo el universo + todos los vendedores.
      // Espejo del filtro `activo = true` de leads_select: solo el lector
      // global (directorio) ve los soft-borrados; gerencia NO los ve.
      return {
        leads: rol === 'directorio' ? datos.leads : datos.leads.filter((l) => l.activo),
        vendedores: equipo.filter((m) => m.rol_crm === 'vendedor'),
        esGlobal: true,
      }
    }
    if (rol === 'supervisor' && miId) {
      // OJO espejo: aquí se usan reportes DIRECTOS (EQUIPO_DEMO es plano);
      // la RLS real usa un subárbol RECURSIVO (vendedor_ids_visibles) e
      // incluye parkeados de cualquier miembro del subárbol. Con supervisores
      // anidados este espejo mostraría MENOS que la RLS (infra-inclusivo, sin
      // fuga) — replicar la recursión al portar a datos reales.
      const mios = equipo.filter((m) => m.supervisor_id === miId)
      const ids = new Set<string>([miId, ...mios.map((m) => m.perfil_id)])
      return {
        leads: datos.leads.filter(
          (l) =>
            l.activo &&
            ((l.vendedor_id != null && ids.has(l.vendedor_id)) ||
              (l.vendedor_id == null && l.asignado_supervisor_id === miId)),
        ),
        vendedores: mios,
        esGlobal: false,
      }
    }
    // vendedor — o rol/sesión desconocidos: privilegio mínimo (solo lo propio)
    return {
      leads: miId ? datos.leads.filter((l) => l.activo && l.vendedor_id === miId) : [],
      vendedores: equipo.filter((m) => m.perfil_id === miId),
      esGlobal: false,
    }
  }, [datos, yo, equipo])

  const api = useMemo<StoreDataApi>(() => {
    const rol = yo?.rol
    const autor = yo?.nombre_completo ?? 'DEMO'

    const sinPermiso = (): ResultadoMut => {
      toast.error('Tu rol es de solo lectura — no puedes modificar datos')
      return {
        ok: false,
        codigo: 'sin_permiso',
        error: 'Sin permiso de escritura',
      }
    }

    const bloqueoEscritura = (): ResultadoMut | null => {
      // Demo y sesión real comparten el mismo gate de rol: la RLS + los triggers
      // del esquema crm son la autoridad server-side; el store solo replica el
      // permiso para dar feedback inmediato (doble defensa). `convertir` mantiene
      // su propio veto en real (necesita la RPC privilegiada del bloque 6).
      if (demoActivo || realActivo) return puedeEscribir(rol) ? null : sinPermiso()
      toast.error('La fuente de datos del CRM aún no está habilitada')
      return {
        ok: false,
        codigo: 'fuente_no_habilitada',
        error: 'Fuente de datos no habilitada',
      }
    }

    const noEncontrado = (): ResultadoMut => ({
      ok: false,
      codigo: 'no_encontrado',
      error: 'Lead no encontrado',
    })

    const actividadAuto = (lead_id: string, tipo: TipoActividad, detalle: string | null): Actividad => ({
      id: uid(),
      lead_id,
      tipo,
      detalle,
      autor_nombre: autor,
      creado_en: new Date().toISOString(),
    })

    const aplicar = (id: string, parche: Partial<Lead>, actividad?: Actividad) => {
      setDatos((d) => ({
        leads: d.leads.map((l) => (l.id === id ? { ...l, ...parche } : l)),
        actividades: actividad ? [actividad, ...d.actividades] : d.actividades,
      }))
    }

    // Espejo del USING de leads_update/select: el objetivo de una lectura o
    // mutación debe estar DENTRO del ámbito del actor. Buscar en el universo
    // global permitía a un supervisor mutar leads del otro equipo (hallazgo de
    // los tests de auditoría). Fuera del ámbito → "no encontrado", igual que
    // RLS (0 filas), sin revelar existencia.
    const buscar = (id: string) => ambito.leads.find((l) => l.id === id)

    // Contrato común de los cuatro verbos de agenda: solo una tarea pendiente
    // y activa puede cerrarse, reprogramarse, confirmarse o anularse.
    const buscarTareaPendiente = (id: string) => {
      const tarea = tareas.find((candidata) => candidata.id === id)
      return tarea?.estado === 'pendiente' && tarea.activo ? tarea : undefined
    }

    const miId = yo?.id ?? null

    // Recorte del timeline al ámbito (espejo de actividades_select).
    const idsDelAmbito = new Set(ambito.leads.map((l) => l.id))

    // Espejo del WITH CHECK de leads_insert/leads_update (F0): para supervisor
    // el vendedor destino debe estar dentro de SU subárbol (él mismo o sus
    // vendedores). Gerencia pasa siempre (vendedor_ids_visibles = todos) y el
    // vendedor nunca llega aquí con otro destino (gates de can/reasignar).
    const vendedorFueraDeAmbito = (vendedorId: string | null): boolean =>
      rol === 'supervisor' &&
      vendedorId != null &&
      vendedorId !== miId &&
      !ambito.vendedores.some((m) => m.perfil_id === vendedorId)

    // Persistencia REAL: la mutación ya se aplicó OPTIMISTA en el estado local
    // (contrato síncrono del store); aquí viaja al servidor y, pase lo que
    // pase, se resincroniza — los triggers (cambio_etapa/reasignacion) y la
    // verdad del servidor reemplazan el espejo optimista. Si el servidor la
    // rechaza (dedup global, RLS, regla de trigger): toast + rollback.
    //
    // `persistirConDetalle` NUNCA rechaza: resuelve el resultado sanitizado al
    // confirmar la escritura, no al terminar el resync. `persistir` conserva
    // el contrato booleano histórico para los flujos que solo necesitan
    // encadenar operaciones. En demo ambas variantes resuelven de inmediato.
    const persistirConDetalle = (
      op: () => Promise<void>,
      {
        notificarError = true,
        revertirOptimista,
      }: {
        notificarError?: boolean
        revertirOptimista?: () => void
      } = {},
    ): Promise<ResultadoPersistencia> => {
      if (!realActivo) return Promise.resolve({ ok: true })
      // La operación se inicia en este mismo tick (contrato histórico del
      // store), pero una excepción síncrona también se convierte en rechazo:
      // ninguna mutación debe escapar como unhandled error.
      let escritura: Promise<void>
      try {
        escritura = op()
      } catch (causa: unknown) {
        escritura = Promise.reject(causa)
      }
      return escritura.then(
        () => {
          void resincronizarReal()
          return { ok: true }
        },
        (causa: unknown) => {
          // Variante LOCAL de mensajeDeError (crm-api): además excluye
          // POSTGREST_ERROR — ese mensaje genérico es de LECTURA ("No se pudo
          // cargar…") y confundiría como feedback de una mutación rechazada.
          const resultado = aResultadoPersistenciaFallida(causa)
          const mensaje = resultado.error
          registrarError('crm.mutacion_revertida', causa)
          // El rollback local inmediato evita que un alta rechazada quede
          // visible como un lead fantasma mientras termina la recarga global.
          revertirOptimista?.()
          // El toast NO puede prometer "se restauró" a ciegas: si el resync de
          // rollback también falla (sin conexión), el espejo optimista sigue
          // pintado. Solo se afirma la restauración cuando de verdad se aplicó.
          void resincronizarReal().then((restaurado) => {
            if (!notificarError) return
            toast.error(
              restaurado
                ? `${mensaje} — se restauró el estado anterior`
                : `${mensaje}. Sin conexión con el servidor: recarga la página para ver el estado real.`,
            )
          })
          return resultado
        },
      )
    }

    const persistir = (op: () => Promise<void>): Promise<boolean> =>
      persistirConDetalle(op).then((resultado) => resultado.ok)

    return {
      leads: datos.leads,
      equipo,
      ambito,
      // Vista de display derivada de las tareas pendientes. El "ahora" se toma
      // al recomputar el memo (cada carga/mutación/resync); las pantallas que
      // necesitan reloj vivo (HOY) reordenan con useAhora sobre vence_en.
      agenda: agendaDeTareas(tareas, Date.now()),
      tareas,
      tareasDe: (leadId) =>
        idsDelAmbito.has(leadId)
          ? tareas
              .filter((t) => t.lead_id === leadId && t.estado === 'pendiente' && t.activo)
              .sort((a, b) => a.vence_en.localeCompare(b.vence_en))
          : [],
      tareasDeCliente: (perfilId) =>
        tareas
          .filter((t) => t.perfil_id === perfilId && t.estado === 'pendiente' && t.activo)
          .sort((a, b) => a.vence_en.localeCompare(b.vence_en)),
      objetivos: auxiliares.objetivos,
      objetivosError: auxiliares.objetivosError,
      cumplimientoMetas: auxiliares.cumplimientoMetas,
      cumplimientoMetasError: auxiliares.cumplimientoMetasError,
      actividades: datos.actividades,
      actividadesDelAmbito: datos.actividades.filter((a) => idsDelAmbito.has(a.lead_id)),
      lead: (id) => buscar(id),
      actividadesDe: (leadId) =>
        // Espejo de actividades_select: solo el timeline de leads del ámbito.
        idsDelAmbito.has(leadId)
          ? datos.actividades.filter((a) => a.lead_id === leadId).sort((a, b) => b.creado_en.localeCompare(a.creado_en))
          : [],

      crearTarea: (input) => {
        const bloqueo = bloqueoEscritura()
        if (bloqueo) return bloqueo
        const leadId = input.lead_id ?? null
        const perfilId = input.perfil_id ?? null
        if ((leadId == null) === (perfilId == null)) return noEncontrado()
        const lead = leadId ? buscar(leadId) : undefined
        if (leadId && (!lead || !idsDelAmbito.has(lead.id))) return noEncontrado()
        if (lead && !esAbierto(lead)) {
          return {
            ok: false,
            codigo: 'lead_cerrado',
            error: 'El lead está cerrado — reábrelo para agendar',
          }
        }
        if (!esTipoTarea(input.tipo)) {
          return {
            ok: false,
            codigo: 'tipo_actividad_reservado',
            error: 'Tipo de tarea inválido',
          }
        }
        const titulo = input.titulo.trim()
        if (!titulo || titulo.length > 200) {
          return {
            ok: false,
            codigo: 'nombre_obligatorio',
            error: 'Ponle un título corto a la tarea',
          }
        }
        const venceEn = normalizarFechaTarea(input.vence_en)
        if (!venceEn) {
          return {
            ok: false,
            codigo: 'fecha_nacimiento_invalida',
            error: 'La fecha de la tarea no es válida',
          }
        }
        const reunion = prepararReunionTarea(input.tipo, input)
        if (!reunion.ok) return reunion.resultado
        const id = uid()
        // Tenencia espejo del lead (en real la deriva el trigger; aquí el
        // optimista la copia para que la agenda pinte igual que el servidor).
        const tarea: Tarea = {
          id,
          lead_id: lead?.id ?? null,
          perfil_id: perfilId,
          vendedor_id: lead?.vendedor_id ?? (perfilId ? miId : null),
          asignado_supervisor_id: lead?.asignado_supervisor_id ?? null,
          tipo: input.tipo,
          titulo,
          nota: input.nota?.trim() || null,
          vence_en: venceEn,
          duracion_min: input.duracion_min ?? null,
          estado: 'pendiente',
          ...reunion.campos,
          resultado_reunion: null,
          motivo_no_realizada: null,
          detalle_cierre_reunion: null,
          reprogramaciones: 0,
          activo: true,
          creado_en: new Date().toISOString(),
        }
        setTareas((prev) => [tarea, ...prev])
        // Espejo optimista de `trg_zz_tareas_avance_etapa`: agendar una reunión
        // con quien ya trabajaste sube el lead a `reunion_agendada`. Ver las
        // guardas (y por qué el no-show NO asciende) en lib/avance-automatico.ts.
        const avance = lead
          ? avancePorReunion(
              lead,
              tarea,
              datos.actividades.some((a) => a.lead_id === lead.id && TIPOS_CONTACTO_K.has(a.tipo)),
              Date.now(),
            )
          : null
        if (avance && lead) {
          const actEtapa = actividadAuto(
            lead.id,
            'cambio_etapa',
            `${ETAPA_INFO[lead.etapa].label} → ${ETAPA_INFO[avance].label}`,
          )
          setDatos((d) => ({
            leads: d.leads.map((l) => (l.id === lead.id ? { ...l, etapa: avance } : l)),
            actividades: [actEtapa, ...d.actividades],
          }))
        }
        const persistido = persistirConDetalle(
          () =>
            insertarTarea({
              ...(UUID_RE.test(id) ? { id } : {}),
              ...(lead ? { lead_id: lead.id } : { perfil_id: perfilId! }),
              tipo: tarea.tipo,
              titulo,
              nota: tarea.nota ?? null,
              vence_en: tarea.vence_en,
              duracion_min: tarea.duracion_min ?? null,
              modalidad_reunion: tarea.modalidad_reunion ?? null,
              ubicacion_reunion: tarea.ubicacion_reunion ?? null,
              enlace_reunion: tarea.enlace_reunion ?? null,
              creado_por: miId,
            }),
          {
            // Si RLS o el trigger rechazan el alta, la tarea no puede seguir
            // aparentando que existe mientras termina la resincronización.
            revertirOptimista: () => {
              setTareas((prev) => prev.filter((item) => item.id !== id))
            },
          },
        )
        // El avance viaja al llamador para que lo ANUNCIE (los otros dos
        // escritores ya lo hacían): mover la etapa sin decirlo asusta más que
        // ayuda. `avance` solo puede ser una etapa activa — avancePorReunion
        // nunca devuelve terminales.
        return avance ? { ok: true, id, avance, persistido } : { ok: true, id, persistido }
      },

      completarTarea: (input) => {
        const bloqueo = bloqueoEscritura()
        if (bloqueo) return bloqueo
        const t = buscarTareaPendiente(input.tarea_id)
        if (!t) return noEncontrado()
        const lead = t.lead_id ? buscar(t.lead_id) : undefined
        const resultado = input.resultado_tipo ?? null
        // Doble defensa runtime (los unions TS se borran al compilar).
        if (resultado && TIPOS_AUTO_K.has(resultado)) {
          return {
            ok: false,
            codigo: 'tipo_actividad_reservado',
            error: 'Ese tipo lo genera el sistema',
          }
        }
        // Regla comercial (evidencia Outreach): una LLAMADA completada sin
        // resultado no cuenta — contestó o no contestó, un tap.
        if (t.tipo === 'llamada' && input.estado === 'completada' && !resultado) {
          return {
            ok: false,
            codigo: 'resultado_obligatorio',
            error: 'Registra el resultado de la llamada (contestó / no contestó)',
          }
        }
        if (t.tipo === 'reunion' && input.estado === 'completada' && !input.resultado_reunion) {
          return {
            ok: false,
            codigo: 'resultado_obligatorio',
            error: 'Registra el resultado comercial de la reunión',
          }
        }
        // Tarea SIGUIENTE opcional (la sugerencia del motor, ya editada o no).
        let sigLocal: Tarea | null = null
        if (input.siguiente) {
          if (!lead && !t.perfil_id) return noEncontrado()
          if (lead && !esAbierto(lead)) {
            return {
              ok: false,
              codigo: 'lead_cerrado',
              error: 'El lead está cerrado — la siguiente tarea no aplica',
            }
          }
          if (!esTipoTarea(input.siguiente.tipo)) {
            return {
              ok: false,
              codigo: 'tipo_actividad_reservado',
              error: 'Tipo de la siguiente tarea inválido',
            }
          }
          const tituloSig = input.siguiente.titulo.trim()
          const venceEnSig = normalizarFechaTarea(input.siguiente.vence_en)
          if (!tituloSig || tituloSig.length > 200 || !venceEnSig) {
            return {
              ok: false,
              codigo: 'nombre_obligatorio',
              error: 'La siguiente tarea necesita título y fecha válidos',
            }
          }
          const reunionSiguiente = prepararReunionTarea(input.siguiente.tipo, input.siguiente)
          if (!reunionSiguiente.ok) return reunionSiguiente.resultado
          sigLocal = {
            id: uid(),
            lead_id: lead?.id ?? null,
            perfil_id: t.perfil_id ?? null,
            vendedor_id: lead?.vendedor_id ?? t.vendedor_id ?? null,
            asignado_supervisor_id: lead?.asignado_supervisor_id ?? t.asignado_supervisor_id ?? null,
            tipo: input.siguiente.tipo,
            titulo: tituloSig,
            vence_en: venceEnSig,
            estado: 'pendiente',
            ...reunionSiguiente.campos,
            resultado_reunion: null,
            motivo_no_realizada: null,
            detalle_cierre_reunion: null,
            reagendada_de: input.estado === 'no_show' ? t.id : null,
            reprogramaciones: 0,
            activo: true,
            creado_en: new Date().toISOString(),
          }
        }
        const detalle = input.resultado_detalle?.trim() || null
        // OPTIMISTA: cierre + siguiente + resultado al timeline, todo local ya.
        setTareas((prev) => {
          const marcadas = prev.map((x) =>
            x.id === t.id
              ? {
                  ...x,
                  estado: input.estado,
                  resultado_reunion:
                    t.tipo === 'reunion' && input.estado === 'completada' ? (input.resultado_reunion ?? null) : null,
                  motivo_no_realizada:
                    t.tipo === 'reunion' && input.estado === 'no_show' ? ('cliente_no_asistio' as const) : null,
                  detalle_cierre_reunion: t.tipo === 'reunion' ? detalle : null,
                }
              : x,
          )
          return sigLocal ? [sigLocal, ...marcadas] : marcadas
        })
        // Espejo de los DOS avances automáticos de etapa, en el MISMO orden en
        // que los ejecuta el servidor: `crm.cerrar_tarea` inserta primero la
        // actividad del resultado (→ trg_zz_actividades_avance_etapa) y después
        // la tarea siguiente (→ trg_zz_tareas_avance_etapa). Encadenarlos en ese
        // orden importa: cerrar con "Contestó" y agendar reunión en el mismo
        // gesto lleva el lead de `nuevo` a `contactado` y de ahí a
        // `reunion_agendada`, igual que en el servidor.
        let avanceFinal: EtapaActiva | null = null
        if (t.lead_id && lead) {
          const actos: Actividad[] = []
          let etapaLocal: EtapaActiva | Etapa = lead.etapa
          if (resultado) actos.push(actividadAuto(t.lead_id, resultado, detalle))
          const trasContacto = resultado
            ? avancePorContacto({ etapa: etapaLocal, activo: lead.activo }, resultado)
            : null
          if (trasContacto) {
            actos.push(
              actividadAuto(
                t.lead_id,
                'cambio_etapa',
                `${ETAPA_INFO[etapaLocal].label} → ${ETAPA_INFO[trasContacto].label}`,
              ),
            )
            etapaLocal = trasContacto
          }
          // ¿Hay algún contacto REAL en el timeline? (los 5 tipos, no los 3 de
          // conversación: para agendar basta con haber trabajado el lead). Cuenta
          // el resultado que se acaba de registrar, igual que el EXISTS del
          // trigger, que corre después del INSERT de la actividad.
          const trasReunion = sigLocal
            ? avancePorReunion(
                {
                  etapa: etapaLocal,
                  activo: lead.activo,
                  vendedor_id: lead.vendedor_id ?? null,
                  asignado_supervisor_id: lead.asignado_supervisor_id ?? null,
                },
                sigLocal,
                (resultado != null && TIPOS_CONTACTO_K.has(resultado)) ||
                  datos.actividades.some((a) => a.lead_id === t.lead_id && TIPOS_CONTACTO_K.has(a.tipo)),
                Date.now(),
              )
            : null
          if (trasReunion) {
            actos.push(
              actividadAuto(
                t.lead_id,
                'cambio_etapa',
                `${ETAPA_INFO[etapaLocal].label} → ${ETAPA_INFO[trasReunion].label}`,
              ),
            )
            etapaLocal = trasReunion
          }
          const etapaFinal = etapaLocal
          if (etapaFinal !== lead.etapa && etapaFinal !== 'convertido' && etapaFinal !== 'descartado') {
            avanceFinal = etapaFinal
          }
          if (actos.length > 0) {
            setDatos((d) => ({
              leads:
                etapaFinal !== lead.etapa
                  ? d.leads.map((l) => (l.id === t.lead_id ? { ...l, etapa: etapaFinal } : l))
                  : d.leads,
              // `actos` se construyó en orden cronológico; el timeline pinta el
              // más reciente arriba, así que entra invertido.
              actividades: [...actos.reverse(), ...d.actividades],
            }))
          }
        }
        // REAL: la RPC crm.cerrar_tarea hace las tres escrituras EN UNA
        // transacción (por eso no se usa actualizarTarea+insertarActividad).
        const sig = sigLocal
        // `persistido` se DEVUELVE al llamador: el cierre por «No responde»
        // encadena el descarte detrás de esta promesa (ver cerrar-tarea.tsx).
        const siguientePayload = sig
          ? {
              id: sig.id,
              tipo: sig.tipo,
              titulo: sig.titulo,
              vence_en: sig.vence_en,
              modalidad_reunion: sig.modalidad_reunion ?? null,
              ubicacion_reunion: sig.ubicacion_reunion ?? null,
              enlace_reunion: sig.enlace_reunion ?? null,
            }
          : null
        const persistido = persistir(async () => {
          await ejecutarCierreTarea({
            tarea: t,
            estado: input.estado,
            resultadoTipo: resultado,
            resultadoDetalle: detalle,
            resultadoReunion: input.resultado_reunion ?? null,
            motivoNoRealizada: input.estado === 'no_show' ? 'cliente_no_asistio' : (input.motivo_no_realizada ?? null),
            detalleReunion: detalle,
            siguiente: siguientePayload,
          })
          if (t.perfil_id) {
            await queryClient.invalidateQueries({
              queryKey: crmQueryKeys.actividadesCliente(t.perfil_id),
            })
          }
        })
        return {
          ok: true,
          persistido,
          ...(sigLocal ? { siguiente_id: sigLocal.id } : {}),
          ...(avanceFinal ? { avance: avanceFinal } : {}),
        }
      },

      reprogramarTarea: (id, venceEn) => {
        const bloqueo = bloqueoEscritura()
        if (bloqueo) return bloqueo
        const t = buscarTareaPendiente(id)
        if (!t) return noEncontrado()
        const iso = normalizarFechaTarea(venceEn)
        if (!iso) {
          return {
            ok: false,
            codigo: 'fecha_nacimiento_invalida',
            error: 'La nueva fecha no es válida',
          }
        }
        if (t.tipo === 'reunion') {
          const nuevaId = uid()
          const nueva: Tarea = {
            ...t,
            id: nuevaId,
            vence_en: iso,
            estado: 'pendiente',
            confirmada_en: null,
            reagendada_de: t.id,
            reprogramaciones: t.reprogramaciones + 1,
            resultado_reunion: null,
            motivo_no_realizada: null,
            detalle_cierre_reunion: null,
            creado_en: new Date().toISOString(),
          }
          setTareas((prev) => [
            nueva,
            ...prev.map((x) =>
              x.id === id
                ? {
                    ...x,
                    estado: 'reprogramada' as const,
                    motivo_no_realizada: 'reprogramada' as const,
                    detalle_cierre_reunion: `Reprogramada para ${iso}`,
                  }
                : x,
            ),
          ])
          persistir(() => reprogramarReunion(id, iso, nuevaId).then(() => undefined))
          return { ok: true }
        }
        // Optimista espejo del trigger: mover fecha incrementa el contador y
        // una cita reprogramada pierde su confirmación (hay que reconfirmar).
        setTareas((prev) =>
          prev.map((x) =>
            x.id === id
              ? {
                  ...x,
                  vence_en: iso,
                  reprogramaciones: x.reprogramaciones + 1,
                  confirmada_en: null,
                }
              : x,
          ),
        )
        persistir(() => actualizarTarea(id, { vence_en: iso, confirmada_en: null }))
        return { ok: true }
      },

      confirmarTarea: (id) => {
        const bloqueo = bloqueoEscritura()
        if (bloqueo) return bloqueo
        const t = buscarTareaPendiente(id)
        if (!t) return noEncontrado()
        const iso = new Date().toISOString()
        setTareas((prev) => prev.map((x) => (x.id === id ? { ...x, confirmada_en: iso } : x)))
        persistir(() => actualizarTarea(id, { confirmada_en: iso }))
        return { ok: true }
      },

      // ── ANULAR: el cuarto verbo, el que faltaba ───────────────────────────
      //
      // EL AGUJERO (pedido de Miguel, 2026-07-26, textual: «si agendo una
      // reunión el sistema no me deja cerrar la otra tarea que era una llamada
      // … voy a tener llamadas agendadas innecesarias»). Una tarea pendiente
      // solo podía CERRARSE con resultado, reprogramarse o confirmarse. Cuando
      // el asesor agendaba la reunión, la llamada vieja se quedaba clavada, y
      // para sacarla de su agenda el diálogo de cierre solo le ofrecía
      // «Contestó»/«No contestó»: las dos MENTIRA. Y esa mentira no es barata
      // — entra al log INMUTABLE de `crm.actividades`, cuenta como gestión
      // ante supervisión y «Contestó» encima SUBE la etapa del lead
      // (lib/avance-automatico). El asesor honesto se quedaba con basura en la
      // agenda; el apurado ensuciaba el embudo. Faltaba poder decir «esto ya
      // no aplica» sin afirmar nada sobre el cliente.
      //
      // CERO MIGRACIONES: `crm.cerrar_tarea` acepta `p_estado='cancelada'`
      // desde el plan v2 (20260718180001) y con `p_resultado_tipo` null NO
      // toca `crm.actividades`. Nunca se le puso botón.
      //
      // POR QUÉ NO ESCRIBE ACTIVIDAD DE CONTACTO (y no debe): las filas de
      // trabajo comercial de `crm.actividades` mueven `referenciaEspera`
      // (lib/inteligencia), que es el reloj con el que la cola decide a quién
      // destapar. Anular pasaría por «atendí al cliente» y escondería el lead
      // justo en el instante en que se quedó SIN plan. Sin esa actividad, el
      // lead cae —correctamente— al bucket ámbar «sin próxima acción» y vuelve
      // a la cola. Que anular DESTAPE el lead en vez de taparlo es la propiedad
      // que hace que este botón no se pueda abusar. (El `cambio_etapa` del
      // retroceso sí se escribe, y NO rompe eso: la cola se mide contra el
      // último CONTACTO REAL, y las actividades que emite el sistema quedan
      // fuera por diseño — ver la cabecera de `colaDeAccion`.)
      //
      // LA RENDICIÓN DE CUENTAS NO SE PIERDE, y desde 2026-07-26 es exacta: el
      // UPDATE queda en `audit_log` (trigger de la tabla) y la anulación viaja
      // ETIQUETADA como `cancelada_por = 'asesor'` + FIRMADA con el uuid de
      // quien la ordenó (`cancelada_por_id`, 2026-07-27), separada de las que
      // cancela el sistema al cerrarse un lead. Supervisión ve las tres cuentas
      // por separado en «Agenda del equipo» (screens/hoy/agenda-equipo.tsx), y
      // en el % de una persona solo pesan las que anuló ELLA sobre su propia
      // agenda: ni las del sistema (convertir un lead ya no penaliza) ni las
      // que le anuló un superior (no tuvo control sobre esa tarea — decisión de
      // Miguel). Vaciarse la agenda a fuerza de anular sigue viéndose desde
      // arriba, porque las propias sí cuentan.
      anularTarea: (id, cierreReunion) => {
        const bloqueo = bloqueoEscritura()
        if (bloqueo) return bloqueo
        const t = buscarTareaPendiente(id)
        // Espejo del `for update` de la RPC (activo + pendiente): una tarea ya
        // cerrada es inmutable en el servidor y reintentarlo daría "Tarea no
        // encontrada" DESPUÉS de haberla pintado como anulada.
        if (!t) return noEncontrado()
        if (t.tipo === 'reunion' && !cierreReunion?.motivo) {
          return {
            ok: false,
            codigo: 'resultado_obligatorio',
            error: 'Selecciona por qué no se realizará la reunión',
          }
        }
        setTareas((prev) =>
          prev.map((x) =>
            x.id === id
              ? {
                  ...x,
                  estado: 'cancelada',
                  motivo_no_realizada: t.tipo === 'reunion' ? (cierreReunion?.motivo ?? null) : null,
                  detalle_cierre_reunion: t.tipo === 'reunion' ? cierreReunion?.detalle?.trim() || null : null,
                }
              : x,
          ),
        )
        // Espejo optimista de `private.retroceso_por_anular_reunion` (pedido de Miguel,
        // 2026-07-26: «si se anula la reu y no se reagenda una en ese mismo
        // momento, debería bajar de etapa»). Se calcula con la lista de tareas
        // ANTES del setTareas de arriba —el estado de React no se lee dentro del
        // mismo render— y por eso `retrocesoPorAnularReunion` excluye la tarea
        // en curso por id en vez de fiarse de su estado.
        const lead = t.lead_id ? buscar(t.lead_id) : undefined
        const retroceso = lead
          ? retrocesoPorAnularReunion(
              lead,
              t,
              tareas.filter((x) => x.lead_id === lead.id),
              datos.actividades.filter((a) => a.lead_id === lead.id),
            )
          : null
        if (retroceso && lead) {
          const actEtapa = actividadAuto(
            lead.id,
            'cambio_etapa',
            `${ETAPA_INFO[lead.etapa].label} → ${ETAPA_INFO[retroceso].label}`,
          )
          setDatos((d) => ({
            leads: d.leads.map((l) => (l.id === lead.id ? { ...l, etapa: retroceso } : l)),
            actividades: [actEtapa, ...d.actividades],
          }))
        }
        persistir(() =>
          ejecutarCierreTarea({
            tarea: t,
            estado: 'cancelada',
            resultadoTipo: null,
            resultadoDetalle: null,
            resultadoReunion: null,
            motivoNoRealizada: cierreReunion?.motivo ?? null,
            // El RPC conserva el detalle crudo histórico; el espejo local sigue
            // mostrando su versión recortada, igual que antes del refactor.
            detalleReunion: cierreReunion?.detalle ?? null,
            siguiente: null,
          }),
        )
        return retroceso ? { ok: true, retroceso } : { ok: true }
      },

      crearLead: (input) => {
        const bloqueo = bloqueoEscritura()
        if (bloqueo) return bloqueo
        // En creación ambos campos son obligatorios incluso en runtime. El
        // validador compartido acepta `undefined` a propósito porque también
        // valida PATCHes parciales; por eso este guard vive antes de llamarlo.
        if (input.monto_estimado === undefined) {
          return {
            ok: false,
            codigo: 'monto_invalido',
            campo: 'monto_estimado',
            error: 'El capital estimado es obligatorio y debe ser mayor que 0',
          }
        }
        if (input.moneda === undefined) {
          return {
            ok: false,
            codigo: 'moneda_invalida',
            campo: 'moneda',
            error: 'Selecciona una moneda válida (PEN o USD)',
          }
        }
        // Validación compartida (espejo de los CHECK de crm.leads) — la misma
        // fuente que editarLead y, a futuro, las mutaciones reales de Supabase.
        const v = validarCamposLead({
          nombre_completo: input.nombre_completo,
          telefono: input.telefono,
          dni: input.dni ?? null,
          correo: input.correo ?? null,
          origen: input.origen,
          monto_estimado: input.monto_estimado,
          moneda: input.moneda,
          genero: input.genero ?? null,
          fecha_nacimiento: input.fecha_nacimiento ?? null,
        })
        if (!v.ok) return v
        const nombre = v.valores.nombre_completo ?? ''
        const telefono = v.valores.telefono ?? ''
        const dni = v.valores.dni ?? null
        const genero = v.valores.genero ?? null
        const fechaNacimiento = v.valores.fecha_nacimiento ?? null
        const etapa: EtapaActiva = input.etapa ?? 'nuevo'
        if (TERMINALES_K.has(etapa)) {
          return {
            ok: false,
            codigo: 'etapa_terminal_al_nacer',
            error: 'Un lead no puede nacer en etapa terminal',
          }
        }
        // Espejo de la policy leads_insert: sin can('reasignar') el lead solo
        // puede nacer asignado a uno mismo (parkear es de supervisor/gerencia).
        // El gate de permisos corre ANTES del dedup: sin permiso no hay sondeo.
        if (!can(rol, 'reasignar') && (input.vendedor_id ?? null) !== (yo?.id ?? null)) {
          return {
            ok: false,
            codigo: 'solo_autoasignar',
            error: 'Solo puedes crear leads asignados a ti mismo',
          }
        }
        const choque = conflictoDedup(datos.leads, telefono, dni, undefined, idsDelAmbito)
        if (choque) return choque
        // Resuelve el vendedor SIN tragar ids inválidos (mismo criterio que reasignar()).
        let vendedor_id: string | null = null
        let vendedor_nombre: string | null = null
        if (input.vendedor_id) {
          const m = equipo.find((x) => x.perfil_id === input.vendedor_id)
          if (m) {
            vendedor_id = m.perfil_id
            vendedor_nombre = m.nombre_completo
          } else if (yo && input.vendedor_id === yo.id) {
            // Usuario (demo o sesión real) fuera de EQUIPO_DEMO: se auto-asigna igual.
            vendedor_id = yo.id
            vendedor_nombre = yo.nombre_completo
          } else {
            return {
              ok: false,
              codigo: 'vendedor_no_encontrado',
              error: 'Vendedor no encontrado',
            }
          }
        }
        // Espejo del WITH CHECK de leads_insert: supervisor solo dentro de su equipo.
        if (vendedorFueraDeAmbito(vendedor_id)) {
          return {
            ok: false,
            codigo: 'vendedor_fuera_ambito',
            error: 'Ese vendedor no pertenece a tu equipo',
          }
        }
        const id = uid()
        const lead: Lead = {
          id,
          nombre_completo: nombre,
          telefono,
          correo: v.valores.correo ?? null,
          etapa,
          origen: v.valores.origen ?? input.origen,
          monto_estimado: v.valores.monto_estimado ?? input.monto_estimado,
          moneda: v.valores.moneda ?? input.moneda,
          categoria_interes: input.categoria_interes ?? null,
          vendedor_id,
          vendedor_nombre,
          // Parkeado por un supervisor → queda en SU bandeja (espejo F0: el
          // ámbito jerárquico lo mostrará como "por repartir" de ese supervisor).
          asignado_supervisor_id: vendedor_id == null && rol === 'supervisor' ? miId : null,
          creado_en: new Date().toISOString(),
          activo: true,
          dni,
          genero,
          fecha_nacimiento: fechaNacimiento,
          distrito: input.distrito?.trim() || null,
          nota: input.nota?.trim() || null,
          motivo_descarte: null,
        }
        setDatos((d) => ({ ...d, leads: [lead, ...d.leads] }))
        // El id viaja al servidor (si es UUID) para que el optimista y la fila
        // real sean LA MISMA identidad — un drawer abierto sobrevive al resync.
        const persistido = persistirConDetalle(
          async () => {
            const resultado = await insertarLead({
              ...(UUID_RE.test(id) ? { id } : {}),
              nombre_completo: nombre,
              telefono,
              correo: lead.correo ?? null,
              dni,
              genero,
              fecha_nacimiento: fechaNacimiento,
              distrito: lead.distrito ?? null,
              origen: lead.origen,
              etapa,
              monto_estimado: lead.monto_estimado,
              moneda: lead.moneda,
              categoria_interes: lead.categoria_interes ?? null,
              vendedor_id,
              nota: lead.nota ?? null,
            })
            if (resultado.estado === 'reutilizado') {
              // Resultado FUTURO (F2 del plan «lead libre»): el alta reabrió un
              // lead existente. El servidor de hoy no lo emite; cuando nazca, el
              // manejo real (refrescar ámbito, abrir la ficha reabierta) llega
              // con su fase. Hasta entonces: fail-closed con recarga, jamás
              // fingir que se creó otro lead.
              throw new CrmApiError(
                'El contacto tenía un lead anterior y fue retomado. Recarga para verlo.',
                'CREACION_LEAD_CONTRACT',
              )
            }
            if (resultado.estado !== 'creado') {
              const presentacion = presentarDisponibilidadLead(resultado)
              throw new CrmApiError(
                presentacion.mensaje ?? 'Este contacto no está disponible para un nuevo lead',
                'CONTACTO_NO_DISPONIBLE',
              )
            }
            if (resultado.lead_id !== id) {
              throw new CrmApiError('El servidor confirmó una identidad de lead inesperada.', 'CREACION_LEAD_CONTRACT')
            }
          },
          {
            notificarError: false,
            revertirOptimista: () => {
              setDatos((d) => ({
                ...d,
                leads: d.leads.filter((item) => item.id !== id),
              }))
            },
          },
        )
        return { ok: true, id, persistido }
      },

      editarLead: (id, cambios) => {
        const bloqueo = bloqueoEscritura()
        if (bloqueo) return bloqueo
        const actual = buscar(id)
        if (!actual) return noEncontrado()
        // GUARD DE TERMINAL. Era el ÚNICO escritor de leads sin él (cambiarEtapa,
        // descartar, convertir, reabrir y registrarActividad ya lo tenían), y de
        // esa grieta colgaba una cifra de negocio: cada edición reescribe
        // `actualizado_en`, que era el "mes de cierre" del marcador. Tocar el
        // teléfono de un convertido de agosto le sumaba un cierre a septiembre y
        // se lo quitaba a agosto. El sello propio (`convertido_en`) ya blinda el
        // cálculo, pero un lead cerrado no debe poder editarse igual: su ficha
        // es el acta de lo que pasó.
        if (TERMINALES_K.has(actual.etapa)) {
          return actual.etapa === 'convertido'
            ? {
                ok: false,
                codigo: 'lead_cerrado',
                error: 'Ya es cliente — sus datos se corrigen en la ficha del cliente, no en el lead',
              }
            : {
                ok: false,
                codigo: 'lead_cerrado',
                error: 'El lead está cerrado — reábrelo para editar sus datos',
              }
        }
        // MISMA validación que crearLead (antes: dos copias divergentes; la
        // edición saltaba teléfono/correo/DNI si el texto cambiaba de forma).
        const v = validarCamposLead({
          ...(cambios.nombre_completo !== undefined ? { nombre_completo: cambios.nombre_completo } : {}),
          ...(cambios.telefono !== undefined ? { telefono: cambios.telefono } : {}),
          ...(cambios.dni !== undefined ? { dni: cambios.dni } : {}),
          ...(cambios.correo !== undefined ? { correo: cambios.correo } : {}),
          ...(cambios.origen !== undefined ? { origen: cambios.origen } : {}),
          ...(cambios.monto_estimado !== undefined ? { monto_estimado: cambios.monto_estimado } : {}),
          ...(cambios.moneda !== undefined ? { moneda: cambios.moneda } : {}),
          ...(cambios.genero !== undefined ? { genero: cambios.genero } : {}),
          ...(cambios.fecha_nacimiento !== undefined ? { fecha_nacimiento: cambios.fecha_nacimiento } : {}),
        })
        if (!v.ok) return v
        const parche: CambiosLead = { ...cambios, ...v.valores }
        if (esAbierto(actual)) {
          const tel = parche.telefono ?? actual.telefono
          const dni = parche.dni !== undefined ? parche.dni : (actual.dni ?? null)
          const choque = conflictoDedup(datos.leads, tel, dni, id, idsDelAmbito)
          if (choque) return choque
        }
        aplicar(id, parche)
        persistir(() => actualizarLead(id, parche))
        return { ok: true }
      },

      cambiarEtapa: (id, etapa, capital) => {
        const bloqueo = bloqueoEscritura()
        if (bloqueo) return bloqueo
        const actual = buscar(id)
        if (!actual) return noEncontrado()
        if (TERMINALES_K.has(actual.etapa)) {
          return {
            ok: false,
            codigo: 'lead_cerrado',
            error: 'El lead está cerrado — reábrelo para moverlo de etapa',
          }
        }
        if (TERMINALES_K.has(etapa)) {
          return {
            ok: false,
            codigo: 'cerrar_con_flujo',
            error: 'Usa convertir o descartar para cerrar un lead',
          }
        }
        // El CAPITAL REAL de la propuesta viaja EN LA MISMA ESCRITURA que la
        // etapa, no en una segunda. Con dos `actualizarLead` separados, si la
        // del monto fallaba el lead quedaba en "Propuesta enviada" con la cifra
        // vieja — exactamente el bug que esto viene a corregir, ahora invisible
        // y con todo el mundo creyendo que se arregló.
        let parche: {
          etapa: EtapaActiva
          monto_estimado?: number
          moneda?: Moneda
        } = { etapa }
        if (capital) {
          const v = validarCamposLead({
            monto_estimado: capital.monto_estimado,
            moneda: capital.moneda,
          })
          if (!v.ok) return v
          const { monto_estimado, moneda } = v.valores
          if (monto_estimado == null || moneda == null) {
            return {
              ok: false,
              codigo: 'monto_invalido',
              campo: 'monto_estimado',
              error: 'Capital inválido',
            }
          }
          parche = { etapa, monto_estimado, moneda }
        }
        if (actual.etapa === etapa && !capital) return { ok: true }
        aplicar(
          id,
          parche,
          actual.etapa === etapa
            ? undefined
            : actividadAuto(id, 'cambio_etapa', `${ETAPA_INFO[actual.etapa].label} → ${ETAPA_INFO[etapa].label}`),
        )
        // El trigger del servidor genera la actividad real; el resync la trae.
        persistir(() => actualizarLead(id, parche))
        return { ok: true }
      },

      descartar: (id, motivo, nota) => {
        const bloqueo = bloqueoEscritura()
        if (bloqueo) return bloqueo
        const actual = buscar(id)
        if (!actual) return noEncontrado()
        if (TERMINALES_K.has(actual.etapa))
          return {
            ok: false,
            codigo: 'lead_cerrado',
            error: 'El lead ya está cerrado',
          }
        // «No responde» exige intentos registrados: es una afirmación de hecho
        // sobre el cliente, no una opinión. Doble defensa del gate de la ficha
        // (la UI ya deshabilita la opción); aquí se sostiene aunque alguien
        // llame al store por otra vía. Ver lib/descarte-evidencia.ts para por
        // qué esto NO es un trigger de BD (rompería los descartes de Rosa).
        if (MOTIVOS_CON_EVIDENCIA.has(motivo)) {
          const veto = vetoNoResponde(datos.actividades.filter((a) => a.lead_id === id))
          if (veto) {
            toast.error(veto)
            return { ok: false, codigo: 'sin_permiso', error: veto }
          }
        }
        const labelMotivo = MOTIVOS_DESCARTE.find((m) => m.k === motivo)?.label ?? motivo
        const notaLimpia = nota?.trim() || null
        const detalle = `${ETAPA_INFO[actual.etapa].label} → ${ETAPA_INFO.descartado.label} · Motivo: ${labelMotivo}${notaLimpia ? ` — ${notaLimpia}` : ''}`
        // La nota del descarte queda inmutable en la actividad del timeline;
        // NO pisa la nota original del lead (era destructivo y redundante).
        aplicar(id, { etapa: 'descartado', motivo_descarte: motivo }, actividadAuto(id, 'cambio_etapa', detalle))
        // En real el trigger escribe el cambio_etapa genérico (sin motivo ni
        // nota); la nota libre del descarte se preserva como actividad 'nota'
        // aparte (el motivo ya viaja en la columna motivo_descarte). Son dos
        // escrituras NO atómicas: el update es la acción primaria; si la nota
        // (secundaria) falla DESPUÉS de que el descarte ya persistió, NO se
        // revierte ni se miente con "se restauró" — se avisa puntualmente que la
        // nota no se guardó (el descarte es correcto). La atomicidad real (un
        // RPC crm.descartar_lead) llega con el bloque 6, que ya toca la BD.
        persistir(async () => {
          await actualizarLead(id, {
            etapa: 'descartado',
            motivo_descarte: motivo,
          })
          if (notaLimpia) {
            try {
              await insertarActividad({
                lead_id: id,
                tipo: 'nota',
                detalle: `Descarte · ${labelMotivo} — ${notaLimpia}`,
                creado_por: miId,
              })
            } catch (causa) {
              registrarError('crm.descarte_nota_fallida', causa)
              toast.warning('Lead descartado, pero no se pudo guardar la nota del descarte')
            }
          }
        })
        return { ok: true }
      },

      convertir: (id) => {
        const bloqueo = bloqueoEscritura()
        if (bloqueo) return bloqueo
        const actual = buscar(id)
        if (!actual) return noEncontrado()
        if (TERMINALES_K.has(actual.etapa))
          return {
            ok: false,
            codigo: 'lead_cerrado',
            error: 'El lead ya está cerrado',
          }
        if (!actual.vendedor_id) {
          return {
            ok: false,
            codigo: 'sin_analista',
            error: 'Asigna el lead a un analista antes de convertirlo',
          }
        }
        if (realActivo) {
          // Red de seguridad: en real, convertir NO es marcar la etapa — hay que
          // crear la cuenta del cliente en el portal, y de eso se encarga la edge
          // `crm-convertir-lead` desde la ficha (DialogConvertir). Marcar la etapa
          // por aquí dejaría un "convertido" sin cliente detrás.
          toast.error('Usa "Convertir a cliente" en la ficha del lead')
          return {
            ok: false,
            codigo: 'fuente_no_habilitada',
            error: 'Conversión no disponible por esta vía',
          }
        }
        aplicar(
          id,
          { etapa: 'convertido', motivo_descarte: null },
          actividadAuto(
            id,
            'conversion',
            `Convertido a cliente desde ${ETAPA_INFO[actual.etapa].label}${yo?.demo ? ' (demo)' : ''}`,
          ),
        )
        return { ok: true }
      },

      convertirExterno: (id, datosCierre) => {
        const bloqueo = bloqueoEscritura()
        if (bloqueo) return bloqueo
        const actual = buscar(id)
        if (!actual) return noEncontrado()
        if (TERMINALES_K.has(actual.etapa))
          return {
            ok: false,
            codigo: 'lead_cerrado',
            error: 'El lead ya está cerrado',
          }
        if (!actual.vendedor_id) {
          return {
            ok: false,
            codigo: 'sin_analista',
            error: 'Asigna el lead a un analista antes de convertirlo',
          }
        }
        if (realActivo) {
          // En real la ficha llama a crm.convertir_lead_externo (deja la foto
          // de verdad); marcar la etapa por aquí dejaría un convertido sin
          // cierre detrás — y la P4 del servidor lo rechazaría igual.
          toast.error('Usa "Convertir" en la ficha del lead')
          return {
            ok: false,
            codigo: 'fuente_no_habilitada',
            error: 'Conversión no disponible por esta vía',
          }
        }
        // Capturada ANTES del setState: el narrowing del guard de arriba no
        // sobrevive dentro del callback (es propiedad, no constante).
        const vendedorFoto = actual.vendedor_id
        aplicar(
          id,
          { etapa: 'convertido', motivo_descarte: null },
          actividadAuto(
            id,
            'conversion',
            `Cerrado en ${INFO_COOPERATIVA[datosCierre.cooperativa].nombre}${yo?.demo ? ' (demo)' : ''}`,
          ),
        )
        setCierresExternosDemo((previos) => [
          {
            // En demo no hay servidor que reparta identidades; el lead ya es
            // único por cierre (un cierre externo por lead), así que basta con
            // derivarla de él y queda estable entre renders.
            cierreId: `demo-cx-${id}`,
            leadId: id,
            cooperativa: datosCierre.cooperativa,
            monto: datosCierre.monto,
            moneda: 'PEN',
            nombre: actual.nombre_completo,
            telefono: actual.telefono,
            numeroTransaccion: datosCierre.numeroTransaccion,
            creadoEn: new Date().toISOString(),
            vendedorId: vendedorFoto,
            vendedorNombre: actual.vendedor_nombre ?? null,
            anuladoEn: null,
            motivoAnulacion: null,
          },
          ...previos,
        ])
        return { ok: true }
      },

      anularCierreExterno: (cierreId, motivo) => {
        const bloqueo = bloqueoEscritura()
        if (bloqueo) return bloqueo
        const limpio = motivo.trim()
        if (!limpio) {
          return {
            ok: false,
            codigo: 'motivo_requerido',
            error: 'Escribe el motivo de la anulación',
          }
        }
        const cierre = cierresExternosDemo.find((c) => c.cierreId === cierreId)
        if (!cierre) return noEncontrado()
        if (cierre.anuladoEn) {
          return {
            ok: false,
            codigo: 'ya_anulado',
            error: 'Ese cierre ya estaba anulado',
          }
        }
        // El lead NO se reabre, igual que en el servidor: un convertido es
        // terminal. Lo que se va es el dinero y la conversión.
        setCierresExternosDemo((previos) =>
          previos.map((c) =>
            c.cierreId === cierreId
              ? {
                  ...c,
                  anuladoEn: new Date().toISOString(),
                  motivoAnulacion: limpio,
                }
              : c,
          ),
        )
        return { ok: true }
      },

      anularCierreAvance: (leadId, motivo) => {
        const bloqueo = bloqueoEscritura()
        if (bloqueo) return bloqueo
        const limpio = motivo.trim()
        if (!limpio) {
          return {
            ok: false,
            codigo: 'motivo_requerido',
            error: 'Escribe el motivo de la anulación',
          }
        }
        const lead = buscar(leadId)
        if (!lead) return noEncontrado()
        // Un cierre en cooperativa se anula con su propia acción, que guarda la
        // foto de lo anulado (monto, depósito). Mandarlo por aquí perdería ese
        // rastro — el servidor lo rechaza por lo mismo.
        if (cierresExternosDemo.some((c) => c.leadId === leadId)) {
          return {
            ok: false,
            codigo: 'cierre_en_cooperativa',
            error: 'Ese lead cerró en cooperativa: anúlalo desde la revisión de cierres',
          }
        }
        if (lead.etapa !== 'convertido') {
          return {
            ok: false,
            codigo: 'sin_cierre',
            error: 'Ese lead no tiene ningún cierre que anular',
          }
        }
        if (anuladosAvanceDemo.some((a) => a.leadId === leadId)) {
          return {
            ok: false,
            codigo: 'ya_anulado',
            error: 'Ese cierre ya estaba anulado',
          }
        }
        // El lead NO se reabre, igual que en el servidor: un convertido es
        // terminal. Lo que se va es el mérito, no el cliente.
        setAnuladosAvanceDemo((previos) => [
          ...previos,
          { leadId, anuladoEn: new Date().toISOString(), motivo: limpio },
        ])
        return { ok: true }
      },

      cierresExternos: cierresExternosDemo,

      // DERIVADO, no un segundo almacén: la misma forma que `crm.cierres_estado_fn`
      // para que la ficha y la cartera no tengan que saber en qué mundo están.
      cierresEstado: [
        ...cierresExternosDemo.map((c) => ({
          lead_id: c.leadId,
          canal: 'cooperativa' as const,
          anulado_en: c.anuladoEn,
          motivo: c.motivoAnulacion,
        })),
        ...anuladosAvanceDemo.map((a) => ({
          lead_id: a.leadId,
          canal: 'avance' as const,
          anulado_en: a.anuladoEn,
          motivo: a.motivo,
        })),
      ],

      reabrir: (id) => {
        const bloqueo = bloqueoEscritura()
        if (bloqueo) return bloqueo
        const actual = buscar(id)
        if (!actual) return noEncontrado()
        if (actual.etapa !== 'descartado') {
          return {
            ok: false,
            codigo: 'solo_reabrir_descartado',
            error: 'Solo se puede reabrir un lead descartado',
          }
        }
        const choque = conflictoDedup(datos.leads, actual.telefono, actual.dni ?? null, id, idsDelAmbito)
        if (choque) return choque
        aplicar(
          id,
          { etapa: 'nuevo', motivo_descarte: null },
          actividadAuto(id, 'cambio_etapa', `${ETAPA_INFO.descartado.label} → ${ETAPA_INFO.nuevo.label}`),
        )
        persistir(() => actualizarLead(id, { etapa: 'nuevo', motivo_descarte: null }))
        return { ok: true }
      },

      registrarActividad: (id, tipo, detalle) => {
        const bloqueo = bloqueoEscritura()
        if (bloqueo) return bloqueo
        const actual = buscar(id)
        if (!actual) return noEncontrado()
        // Doble defensa (el tipo TS se borra en runtime): los tipos automáticos
        // los emite SOLO el store, y un lead cerrado no recibe actividad manual.
        if (TIPOS_AUTO_K.has(tipo)) {
          return {
            ok: false,
            codigo: 'tipo_actividad_reservado',
            error: 'Ese tipo de actividad lo genera el sistema — no se registra a mano',
          }
        }
        if (TERMINALES_K.has(actual.etapa)) {
          return {
            ok: false,
            codigo: 'lead_cerrado',
            error: 'El lead está cerrado — reábrelo para registrar actividad',
          }
        }
        const act = actividadAuto(id, tipo, detalle?.trim() || null)
        // AVANCE AUTOMÁTICO DE ETAPA (pedido de Miguel 2026-07-25). La verdad la
        // escribe el trigger `trg_zz_actividades_avance_etapa`; esto es su
        // espejo optimista para que la ficha no pinte "Nuevo" hasta el resync —
        // y la ÚNICA implementación en modo demo, donde `persistir` sale en seco.
        //
        // El front NO persiste la etapa: no hace falta (el trigger la mueve en
        // la misma transacción del INSERT) y sería una carrera. Tampoco persiste
        // la actividad `cambio_etapa`: `actividades_insert` la veta al cliente
        // justamente para que nadie fabrique historia. La fila optimista la
        // reemplaza la real en el resync.
        const avance = avancePorContacto(actual, tipo)
        const actEtapa = avance
          ? actividadAuto(id, 'cambio_etapa', `${ETAPA_INFO[actual.etapa].label} → ${ETAPA_INFO[avance].label}`)
          : null
        setDatos((d) => ({
          leads: avance ? d.leads.map((l) => (l.id === id ? { ...l, etapa: avance } : l)) : d.leads,
          // El `cambio_etapa` va DELANTE: ocurrió después del contacto.
          actividades: actEtapa ? [actEtapa, act, ...d.actividades] : [act, ...d.actividades],
        }))
        persistir(() =>
          insertarActividad({
            lead_id: id,
            tipo,
            detalle: act.detalle,
            creado_por: miId,
          }),
        )
        return avance ? { ok: true, avance } : { ok: true }
      },

      reasignar: (id, vendedorId) => {
        const bloqueo = bloqueoEscritura()
        if (bloqueo) return bloqueo
        if (!can(rol, 'reasignar')) {
          toast.error('No tienes permiso para reasignar leads')
          return {
            ok: false,
            codigo: 'sin_permiso_reasignar',
            error: 'Sin permiso para reasignar',
          }
        }
        const actual = buscar(id)
        if (!actual) return noEncontrado()
        const nuevo = vendedorId ? equipo.find((m) => m.perfil_id === vendedorId) : undefined
        if (vendedorId && !nuevo)
          return {
            ok: false,
            codigo: 'vendedor_no_encontrado',
            error: 'Vendedor no encontrado',
          }
        // Espejo del WITH CHECK de leads_update: supervisor solo dentro de su equipo.
        if (vendedorFueraDeAmbito(vendedorId)) {
          return {
            ok: false,
            codigo: 'vendedor_fuera_ambito',
            error: 'Ese vendedor no pertenece a tu equipo',
          }
        }
        const vendedorDestino = nuevo?.perfil_id ?? null
        const supervisorDestino = nuevo ? null : rol === 'supervisor' ? miId : null
        if (
          (actual.vendedor_id ?? null) === vendedorDestino &&
          (actual.asignado_supervisor_id ?? null) === supervisorDestino
        ) {
          return { ok: true }
        }
        const supervisorAnterior = actual.asignado_supervisor_id
          ? equipo.find((m) => m.perfil_id === actual.asignado_supervisor_id)?.nombre_completo
          : null
        const supervisorNuevo = supervisorDestino
          ? (equipo.find((m) => m.perfil_id === supervisorDestino)?.nombre_completo ??
            (supervisorDestino === yo?.id ? yo.nombre_completo : null))
          : null
        const tenenciaAnterior = actual.vendedor_id
          ? (actual.vendedor_nombre ?? 'Analista sin nombre')
          : actual.asignado_supervisor_id
            ? `Bandeja de ${supervisorAnterior ?? 'supervisor'}`
            : 'Sin asignar'
        const tenenciaNueva = vendedorDestino
          ? (nuevo?.nombre_completo ?? 'Analista sin nombre')
          : supervisorDestino
            ? `Bandeja de ${supervisorNuevo ?? 'supervisor'}`
            : 'Sin asignar'
        aplicar(
          id,
          {
            vendedor_id: vendedorDestino,
            vendedor_nombre: nuevo?.nombre_completo ?? null,
            // Al asignar vendedor sale de la bandeja; al parkear (null) un
            // supervisor lo retiene en la SUYA (gerencia parkea sin bandeja).
            asignado_supervisor_id: supervisorDestino,
          },
          actividadAuto(id, 'reasignacion', `${tenenciaAnterior} → ${tenenciaNueva}`),
        )
        // La actividad real la emite el trigger trg_leads_reasignacion.
        persistir(() =>
          actualizarLead(id, {
            vendedor_id: vendedorDestino,
            asignado_supervisor_id: supervisorDestino,
          }),
        )
        return { ok: true }
      },

      // El flujo de conversión (edge) escribe server-side; aquí se trae la verdad.
      recargar: () => (realActivo ? resincronizarReal() : Promise.resolve(true)),
    }
  }, [
    datos,
    tareas,
    yo,
    ambito,
    demoActivo,
    realActivo,
    equipo,
    auxiliares,
    resincronizarReal,
    cierresExternosDemo,
    anuladosAvanceDemo,
  ])

  // Estado de la carga remota para la app (splash / error+reintento / workspace).
  const estado = useMemo<StoreEstado>(
    () => ({
      // Sesión real que aún no terminó de cargar y no falló: mostrar splash.
      cargando: sesionReal && !realActivo && !errorReal,
      error: sesionReal && errorReal,
      reintentar: () => setIntentoReal((n) => n + 1),
    }),
    [sesionReal, realActivo, errorReal],
  )

  return (
    <StoreDataContext.Provider value={api}>
      <StoreEstadoContext.Provider value={estado}>
        <PanelActionsContext.Provider value={panelActions}>
          <PanelStateContext.Provider value={panelState}>{children}</PanelStateContext.Provider>
        </PanelActionsContext.Provider>
      </StoreEstadoContext.Provider>
    </StoreDataContext.Provider>
  )
}
