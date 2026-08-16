import * as v from 'valibot'
import { CrmApiError, nuloExplicito, sinIndefinidos } from './crm-api'
import { sb, type ClienteCrm } from '@/lib/supabase'
import { registrarError } from '@/lib/observabilidad'
import {
  ConfiguracionMetasSchema,
  payloadPublicacionMetas,
  RespuestaPublicacionMetasSchema,
  type ConfiguracionMetas,
  type PublicacionMetas,
} from '@/lib/metas-versionadas'
import {
  ConfiguracionProductosSchema,
  ProductoCondicionSeleccionSchema,
  ResultadoArchivoProductoSchema,
  ResultadoCierreLegacyProductosSchema,
  ResultadoVersionProductoSchema,
  type CondicionProductoInput,
  type ConfiguracionProductos,
  type ProductoCondicionSeleccion,
  type ResultadoArchivoProducto,
  type ResultadoVersionProducto,
} from '@/lib/productos-inversion'
import {
  ConfiguracionSlaSchema,
  EstadosSlaLeadsSchema,
  MetricasSlaSchema,
  RespuestaPublicacionSlaSchema,
  type ConfiguracionSla,
  type EstadoSlaLead,
  type MetricasSla,
  type PublicacionSla,
} from '@/lib/sla-versionado'
import {
  ImpactoDesactivacionUsuarioSchema,
  ResultadoEdgeUsuariosSchema,
  ResultadoJerarquiaSchema,
  ResultadoMembresiaSchema,
  ResultadoPerfilActualizadoSchema,
  ResultadoRolUsuarioSchema,
  UsuarioAdministrableSchema,
  type ActualizarUsuarioInput,
  type CrearCandidatoUsuarioInput,
  type ImpactoDesactivacionUsuario,
  type ResultadoEdgeUsuarios,
  type ResultadoAltaUsuario,
  type ResultadoRecuperacionUsuario,
  type UsuarioAdministrable,
} from '@/lib/usuarios-config'
import type { Rol } from '@/lib/roles'

type ErrorPostgrest = {
  code?: string | null
  message?: string | null
  details?: string | null
}

function cliente(): ClienteCrm {
  if (sb) return sb
  const error = new CrmApiError('Supabase no está configurado.', 'SUPABASE_NOT_CONFIGURED')
  registrarError('crm.config.cliente_no_disponible', error)
  throw error
}

function errorConfiguracion(error: ErrorPostgrest, contexto: string): CrmApiError {
  const codigoPg = error.code ?? ''
  let codigo = 'CONFIG_ERROR'
  let mensaje = 'No se pudo completar la operación.'

  if (codigoPg === '40001' || codigoPg === '23505') {
    codigo = 'CONFLICTO_CONFIG'
    mensaje = 'La configuración cambió en otra sesión. Recarga antes de continuar.'
  } else if (codigoPg === '42501' || codigoPg === 'PGRST301') {
    codigo = 'SIN_PERMISO'
    mensaje = 'No tienes permiso para esa acción.'
  } else if (codigoPg === 'P0002') {
    codigo = 'NO_ENCONTRADO'
    mensaje = 'El registro ya no existe o dejó de estar disponible.'
  } else if (codigoPg === '22023' || codigoPg === '23514' || codigoPg === 'P0001') {
    codigo = 'REGLA_SERVIDOR'
    // Estas funciones solo emiten mensajes de negocio controlados y sin PII.
    mensaje = error.message?.trim() || 'El cambio no cumple las reglas del CRM.'
  }

  const fallo = new CrmApiError(mensaje, codigo)
  registrarError(contexto, fallo, { pg: codigoPg })
  return fallo
}

function errorContrato(contexto: string): CrmApiError {
  const fallo = new CrmApiError(
    'El servidor devolvió una respuesta incompatible. Actualiza la aplicación e inténtalo otra vez.',
    'CONTRATO_CONFIG_INVALIDO',
  )
  registrarError(contexto, fallo)
  return fallo
}

function parsear<TSchema extends v.BaseSchema<unknown, unknown, v.BaseIssue<unknown>>>(
  schema: TSchema,
  data: unknown,
  contexto: string,
): v.InferOutput<TSchema> {
  const resultado = v.safeParse(schema, data)
  if (!resultado.success) throw errorContrato(contexto)
  return resultado.output
}

function requestId(): string {
  return crypto.randomUUID()
}

function lanzarAbortSiCorresponde(signal?: AbortSignal): void {
  if (!signal?.aborted) return
  throw signal.reason instanceof Error
    ? signal.reason
    : new DOMException('La solicitud fue cancelada.', 'AbortError')
}

async function mensajeEdge(error: unknown): Promise<string | null> {
  try {
    const response = (error as { context?: Response }).context
    if (!response || typeof response.clone !== 'function') return null
    const body = await response.clone().json() as { error?: unknown }
    return typeof body.error === 'string' ? body.error : null
  } catch {
    return null
  }
}

// ── Usuarios y jerarquía ────────────────────────────────────────────────────

export async function listarUsuariosAdministrables(
  busqueda = '',
  limite = 50,
  desde = 0,
  signal?: AbortSignal,
): Promise<UsuarioAdministrable[]> {
  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('usuarios_administrables_fn', sinIndefinidos({
    p_busqueda: busqueda.trim() || undefined,
    p_limite: limite,
    p_desde: desde,
  }))
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw errorConfiguracion(error, 'crm.config.usuarios.listado_fallido')
  return parsear(v.array(UsuarioAdministrableSchema), data ?? [], 'crm.config.usuarios.contrato_invalido')
}

/** Catálogo completo para selectores de supervisor y reemplazo. La RPC limita
 * cada página a 100; aquí se recorren todas para no esconder destinos válidos
 * cuando el equipo crezca. */
export async function listarCatalogoUsuariosAdministrables(
  signal?: AbortSignal,
): Promise<UsuarioAdministrable[]> {
  const resultado: UsuarioAdministrable[] = []
  let desde = 0
  let total = Number.POSITIVE_INFINITY
  while (resultado.length < total) {
    const pagina = await listarUsuariosAdministrables('', 100, desde, signal)
    if (pagina.length === 0) break
    total = pagina[0]?.total ?? 0
    resultado.push(...pagina)
    desde += pagina.length
  }
  return resultado
}

export async function crearCandidatoUsuario(
  input: CrearCandidatoUsuarioInput,
): Promise<ResultadoAltaUsuario> {
  const { data, error } = await cliente().functions.invoke('crm-usuarios', {
    body: {
      accion: 'crear_candidato',
      request_id: requestId(),
      correo: input.correo,
      nombre_completo: input.nombre_completo,
      tipo_documento: input.tipo_documento,
      documento: input.documento,
      telefono: input.telefono ?? null,
      whatsapp: input.whatsapp ?? null,
      cargo: input.cargo ?? null,
    },
  })
  if (error) {
    const mensaje = await mensajeEdge(error)
    const fallo = new CrmApiError(mensaje ?? 'No se pudo crear el usuario.', 'USUARIO_EDGE_ERROR')
    registrarError('crm.config.usuarios.alta_fallida', fallo)
    throw fallo
  }
  const resultado: ResultadoEdgeUsuarios = parsear(
    ResultadoEdgeUsuariosSchema,
    data,
    'crm.config.usuarios.alta_contrato_invalido',
  )
  if (resultado.estado === 'recuperacion_enviada') {
    throw errorContrato('crm.config.usuarios.alta_estado_invalido')
  }
  return resultado
}

export async function enviarRecuperacionUsuario(
  perfilId: string,
): Promise<ResultadoRecuperacionUsuario> {
  const { data, error } = await cliente().functions.invoke('crm-usuarios', {
    body: { accion: 'enviar_recuperacion', request_id: requestId(), perfil_id: perfilId },
  })
  if (error) {
    const mensaje = await mensajeEdge(error)
    const fallo = new CrmApiError(mensaje ?? 'No se pudo enviar la recuperación.', 'USUARIO_EDGE_ERROR')
    registrarError('crm.config.usuarios.recuperacion_fallida', fallo)
    throw fallo
  }
  const resultado: ResultadoEdgeUsuarios = parsear(
    ResultadoEdgeUsuariosSchema,
    data,
    'crm.config.usuarios.recuperacion_contrato_invalido',
  )
  if (resultado.estado !== 'recuperacion_enviada') {
    throw errorContrato('crm.config.usuarios.recuperacion_estado_invalido')
  }
  return resultado
}

export async function actualizarUsuarioAdministrable(input: ActualizarUsuarioInput) {
  const { data, error } = await cliente().schema('crm').rpc('actualizar_usuario_administrable_fn', {
    p_perfil_id: input.perfil_id,
    p_nombre_completo: input.nombre_completo,
    p_tipo_documento: input.tipo_documento,
    p_documento: input.documento,
    // SIN default en el catálogo: el null explícito («borrar el dato») viaja.
    p_telefono: nuloExplicito(input.telefono),
    p_whatsapp: nuloExplicito(input.whatsapp),
    p_cargo: nuloExplicito(input.cargo),
    p_version_perfil: input.version_perfil,
    p_idempotencia: requestId(),
  })
  if (error) throw errorConfiguracion(error, 'crm.config.usuarios.edicion_fallida')
  return parsear(ResultadoPerfilActualizadoSchema, data, 'crm.config.usuarios.edicion_contrato_invalido')
}

export async function asignarRolUsuario(input: {
  perfilId: string
  rol: Rol
  versionEquipo: string | null
}) {
  const { data, error } = await cliente().schema('crm').rpc('asignar_rol_usuario_fn', {
    p_perfil_id: input.perfilId,
    p_rol_crm: input.rol,
    p_version_equipo: nuloExplicito(input.versionEquipo),
    p_idempotencia: requestId(),
  })
  if (error) throw errorConfiguracion(error, 'crm.config.usuarios.rol_fallido')
  return parsear(ResultadoRolUsuarioSchema, data, 'crm.config.usuarios.rol_contrato_invalido')
}

export async function actualizarJerarquiaUsuario(input: {
  perfilId: string
  supervisorId: string | null
  versionEquipo: string
}) {
  const { data, error } = await cliente().schema('crm').rpc('actualizar_jerarquia_usuario_fn', {
    p_perfil_id: input.perfilId,
    p_supervisor_id: nuloExplicito(input.supervisorId),
    p_version_equipo: input.versionEquipo,
    p_idempotencia: requestId(),
  })
  if (error) throw errorConfiguracion(error, 'crm.config.usuarios.jerarquia_fallida')
  return parsear(ResultadoJerarquiaSchema, data, 'crm.config.usuarios.jerarquia_contrato_invalido')
}

export async function obtenerImpactoDesactivacion(
  perfilId: string,
): Promise<ImpactoDesactivacionUsuario> {
  const { data, error } = await cliente().schema('crm').rpc('impacto_desactivacion_usuario_fn', {
    p_perfil_id: perfilId,
  })
  if (error) throw errorConfiguracion(error, 'crm.config.usuarios.impacto_fallido')
  return parsear(ImpactoDesactivacionUsuarioSchema, data, 'crm.config.usuarios.impacto_contrato_invalido')
}

export async function fijarMembresiaUsuario(input: {
  perfilId: string
  activo: boolean
  reemplazoId: string | null
  versionEquipo: string
}) {
  const { data, error } = await cliente().schema('crm').rpc('fijar_membresia_activa_fn', {
    p_perfil_id: input.perfilId,
    p_activo: input.activo,
    p_reemplazo_id: nuloExplicito(input.reemplazoId),
    p_version_equipo: input.versionEquipo,
    p_idempotencia: requestId(),
  })
  if (error) throw errorConfiguracion(error, 'crm.config.usuarios.membresia_fallida')
  return parsear(ResultadoMembresiaSchema, data, 'crm.config.usuarios.membresia_contrato_invalido')
}

// ── Productos ────────────────────────────────────────────────────────────────

function condicionesJson(condiciones: CondicionProductoInput[]) {
  return condiciones.map((condicion) => ({
    categoria: condicion.categoria,
    moneda: condicion.moneda,
    plazo_meses: condicion.plazo_meses,
    modalidad: condicion.modalidad,
    tipo_interes: condicion.tipo_interes,
    capital_minimo: condicion.capital_minimo,
    capital_maximo: condicion.capital_maximo,
    tasa_referencia: condicion.tasa_referencia,
    tasa_minima: condicion.tasa_minima ?? condicion.tasa_referencia,
    tasa_maxima: condicion.tasa_maxima ?? condicion.tasa_referencia,
  }))
}

export async function obtenerConfiguracionProductos(signal?: AbortSignal): Promise<ConfiguracionProductos> {
  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('productos_inversion_gestion_fn')
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw errorConfiguracion(error, 'crm.config.productos.lectura_fallida')
  return parsear(ConfiguracionProductosSchema, data, 'crm.config.productos.contrato_invalido')
}

export async function listarProductosSeleccionables(
  signal?: AbortSignal,
): Promise<ProductoCondicionSeleccion[]> {
  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('productos_inversion_seleccion_fn')
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw errorConfiguracion(error, 'crm.productos.selector_fallido')
  return parsear(v.array(ProductoCondicionSeleccionSchema), data ?? [], 'crm.productos.selector_contrato_invalido')
}

export interface CabeceraVersionProductoInput {
  nombre: string
  descripcion: string | null
  vigenteDesde: string
  vigenteHasta: string | null
  condiciones: CondicionProductoInput[]
}

export async function crearProductoInversion(
  input: CabeceraVersionProductoInput & { codigo: string },
): Promise<ResultadoVersionProducto> {
  const { data, error } = await cliente().schema('crm').rpc('crear_producto_inversion', {
    p_codigo: input.codigo,
    p_nombre: input.nombre,
    p_descripcion: nuloExplicito(input.descripcion),
    p_vigente_desde: input.vigenteDesde,
    p_vigente_hasta: nuloExplicito(input.vigenteHasta),
    p_condiciones: condicionesJson(input.condiciones),
  })
  if (error) throw errorConfiguracion(error, 'crm.config.productos.alta_fallida')
  return parsear(ResultadoVersionProductoSchema, data, 'crm.config.productos.alta_contrato_invalido')
}

export async function crearVersionProducto(
  input: CabeceraVersionProductoInput & { productoId: string; expectedRevision: number },
): Promise<ResultadoVersionProducto> {
  const { data, error } = await cliente().schema('crm').rpc('crear_version_producto_inversion', {
    p_producto_id: input.productoId,
    p_expected_revision: input.expectedRevision,
    p_nombre: input.nombre,
    p_descripcion: nuloExplicito(input.descripcion),
    p_vigente_desde: input.vigenteDesde,
    p_vigente_hasta: nuloExplicito(input.vigenteHasta),
    p_condiciones: condicionesJson(input.condiciones),
  })
  if (error) throw errorConfiguracion(error, 'crm.config.productos.version_fallida')
  return parsear(ResultadoVersionProductoSchema, data, 'crm.config.productos.version_contrato_invalido')
}

export async function actualizarBorradorProducto(
  input: CabeceraVersionProductoInput & { versionId: string; expectedRevision: number },
): Promise<ResultadoVersionProducto> {
  const { data, error } = await cliente().schema('crm').rpc('actualizar_borrador_producto_inversion', {
    p_version_id: input.versionId,
    p_expected_revision: input.expectedRevision,
    p_nombre: input.nombre,
    p_descripcion: nuloExplicito(input.descripcion),
    p_vigente_desde: input.vigenteDesde,
    p_vigente_hasta: nuloExplicito(input.vigenteHasta),
    p_condiciones: condicionesJson(input.condiciones),
  })
  if (error) throw errorConfiguracion(error, 'crm.config.productos.borrador_fallido')
  return parsear(ResultadoVersionProductoSchema, data, 'crm.config.productos.borrador_contrato_invalido')
}

export async function publicarVersionProducto(versionId: string, expectedRevision: number) {
  const { data, error } = await cliente().schema('crm').rpc('publicar_version_producto_inversion', {
    p_version_id: versionId,
    p_expected_revision: expectedRevision,
  })
  if (error) throw errorConfiguracion(error, 'crm.config.productos.publicacion_fallida')
  return parsear(ResultadoVersionProductoSchema, data, 'crm.config.productos.publicacion_contrato_invalido')
}

export async function archivarProducto(
  productoId: string,
  expectedRevision: number,
): Promise<ResultadoArchivoProducto> {
  const { data, error } = await cliente().schema('crm').rpc('archivar_producto_inversion', {
    p_producto_id: productoId,
    p_expected_revision: expectedRevision,
  })
  if (error) throw errorConfiguracion(error, 'crm.config.productos.archivo_fallido')
  return parsear(ResultadoArchivoProductoSchema, data, 'crm.config.productos.archivo_contrato_invalido')
}

export async function cerrarCompatibilidadLegacyProductos(expectedRevision: number) {
  const { data, error } = await cliente().schema('crm').rpc('cerrar_altas_legacy_productos', {
    p_expected_revision: expectedRevision,
  })
  if (error) throw errorConfiguracion(error, 'crm.config.productos.cierre_legacy_fallido')
  return parsear(ResultadoCierreLegacyProductosSchema, data, 'crm.config.productos.cierre_legacy_contrato_invalido')
}

// ── Metas ────────────────────────────────────────────────────────────────────

export async function obtenerConfiguracionMetas(
  periodo: string,
  signal?: AbortSignal,
): Promise<ConfiguracionMetas> {
  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('configuracion_metas_fn', { p_periodo: periodo })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw errorConfiguracion(error, 'crm.config.metas.lectura_fallida')
  return parsear(ConfiguracionMetasSchema, data, 'crm.config.metas.contrato_invalido')
}

export async function publicarMetas(input: {
  periodo: string
  expectedRevision: number
  metas: PublicacionMetas
}) {
  const { data, error } = await cliente().schema('crm').rpc('publicar_metas_vendedores', {
    p_periodo: input.periodo,
    p_expected_revision: input.expectedRevision,
    p_metas: input.metas,
  })
  if (error) throw errorConfiguracion(error, 'crm.config.metas.publicacion_fallida')
  const [resultado] = parsear(
    RespuestaPublicacionMetasSchema,
    data,
    'crm.config.metas.publicacion_contrato_invalido',
  )
  if (
    !resultado
    || resultado.periodo !== input.periodo
    || resultado.revision !== input.expectedRevision + 1
  ) {
    throw errorContrato('crm.config.metas.publicacion_contrato_invalido')
  }
  return resultado
}

export function publicacionDesdeConfiguracion(configuracion: ConfiguracionMetas): PublicacionMetas {
  return payloadPublicacionMetas(configuracion)
}

// ── SLA ──────────────────────────────────────────────────────────────────────

export async function obtenerConfiguracionSla(signal?: AbortSignal): Promise<ConfiguracionSla> {
  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('configuracion_sla_fn')
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw errorConfiguracion(error, 'crm.config.sla.lectura_fallida')
  return parsear(ConfiguracionSlaSchema, data, 'crm.config.sla.contrato_invalido')
}

export async function publicarPoliticaSla(input: {
  expectedVersion: number
  vigenteDesde: string | null
  config: PublicacionSla
}) {
  const config = {
    zona_horaria: input.config.zona_horaria,
    tipo_reloj: input.config.tipo_reloj,
    primera_gestion_minutos: input.config.primera_gestion_minutos,
    primer_contacto_minutos: input.config.primer_contacto_minutos,
    etapas: input.config.etapas.map((regla) => ({
      etapa: regla.etapa,
      maximo_minutos: regla.maximo_minutos,
    })),
  }
  const { data, error } = await cliente().schema('crm').rpc('publicar_politica_sla', {
    p_expected_version: input.expectedVersion,
    p_vigente_desde: nuloExplicito(input.vigenteDesde),
    p_config: config,
  })
  if (error) throw errorConfiguracion(error, 'crm.config.sla.publicacion_fallida')
  const [resultado] = parsear(
    RespuestaPublicacionSlaSchema,
    data,
    'crm.config.sla.publicacion_contrato_invalido',
  )
  if (
    !resultado
    || resultado.version !== input.expectedVersion + 1
    || resultado.zona_horaria !== config.zona_horaria
    || resultado.tipo_reloj !== config.tipo_reloj
    || resultado.primera_gestion_minutos !== config.primera_gestion_minutos
    || resultado.primer_contacto_minutos !== config.primer_contacto_minutos
  ) {
    throw errorContrato('crm.config.sla.publicacion_contrato_invalido')
  }
  return resultado
}

export async function obtenerMetricasSla(
  desde: string,
  hasta: string,
  signal?: AbortSignal,
): Promise<MetricasSla> {
  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('metricas_sla_fn', { p_desde: desde, p_hasta: hasta })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw errorConfiguracion(error, 'crm.config.sla.metricas_fallidas')
  return parsear(MetricasSlaSchema, data, 'crm.config.sla.metricas_contrato_invalido')
}

export async function listarEstadoSlaLeads(signal?: AbortSignal): Promise<EstadoSlaLead[]> {
  lanzarAbortSiCorresponde(signal)
  let consulta = cliente().schema('crm').rpc('estado_sla_leads_fn')
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) throw errorConfiguracion(error, 'crm.sla.estado_leads_fallido')
  return parsear(EstadosSlaLeadsSchema, data ?? [], 'crm.sla.estado_leads_contrato_invalido')
}
