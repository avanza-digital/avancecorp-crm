import * as v from 'valibot'
import {
  EnteroNoNegativoRpcSchema,
  FechaHoraSchema,
  UuidSchema,
} from './esquemas-rpc'
import { ROLES } from './roles'

export const ESTADOS_USUARIO_CRM = [
  'pendiente_rol',
  'inactivo_crm',
  'activo',
  'suspendido_portal',
] as const

export const UsuarioAdministrableSchema = v.strictObject({
  perfil_id: UuidSchema,
  nombre_completo: v.string(),
  tipo_documento: v.nullable(v.string()),
  documento: v.nullable(v.string()),
  correo: v.nullable(v.string()),
  telefono: v.nullable(v.string()),
  whatsapp: v.nullable(v.string()),
  cargo: v.nullable(v.string()),
  tipo_cuenta: v.picklist(['solo_crm', 'compartida_portal']),
  estado: v.picklist(ESTADOS_USUARIO_CRM),
  rol_crm: v.nullable(v.picklist(ROLES)),
  supervisor_id: v.nullable(UuidSchema),
  activo_crm: v.nullable(v.boolean()),
  activo_portal: v.boolean(),
  version_perfil: v.nullable(FechaHoraSchema),
  version_equipo: v.nullable(FechaHoraSchema),
  total: EnteroNoNegativoRpcSchema,
})

export type UsuarioAdministrable = v.InferOutput<typeof UsuarioAdministrableSchema>

export const ImpactoDesactivacionUsuarioSchema = v.strictObject({
  perfil_id: UuidSchema,
  subordinados_activos: EnteroNoNegativoRpcSchema,
  leads_abiertos: EnteroNoNegativoRpcSchema,
  leads_en_bandeja: EnteroNoNegativoRpcSchema,
  tareas_pendientes: EnteroNoNegativoRpcSchema,
  clientes_activos: EnteroNoNegativoRpcSchema,
  // F2.b [D-2] (identidad multiempresa): con la bandera encendida el servidor añade las PERSONAS a cargo del saliente
  // (responsable de relación). Opcional: con la bandera apagada la respuesta sigue siendo la de siempre.
  personas_a_cargo: v.optional(EnteroNoNegativoRpcSchema),
  requiere_reemplazo: v.boolean(),
})

export const ResultadoPerfilActualizadoSchema = v.strictObject({
  perfil_id: UuidSchema,
  version_perfil: FechaHoraSchema,
  idempotente: v.boolean(),
})

export const ImpactoEliminacionUsuarioSchema = v.strictObject({
  pendientes: ImpactoDesactivacionUsuarioSchema,
  conserva_historial: v.boolean(),
})
export type ImpactoEliminacionUsuario = v.InferOutput<typeof ImpactoEliminacionUsuarioSchema>

export const ResultadoEliminacionUsuarioSchema = v.strictObject({
  perfil_id: UuidSchema,
  resultado: v.picklist(['eliminado', 'historial_conservado']),
})

export const ResultadoMembresiaSchema = v.strictObject({
  perfil_id: UuidSchema,
  activo_crm: v.boolean(),
  version_equipo: FechaHoraSchema,
  idempotente: v.boolean(),
})

export const ResultadoJerarquiaSchema = v.strictObject({
  perfil_id: UuidSchema,
  supervisor_id: v.nullable(UuidSchema),
  version_equipo: FechaHoraSchema,
  idempotente: v.boolean(),
})

export const ResultadoRolUsuarioSchema = v.strictObject({
  perfil_id: UuidSchema,
  rol_crm: v.picklist(ROLES),
  activo_crm: v.boolean(),
  version_equipo: FechaHoraSchema,
  idempotente: v.boolean(),
})

export const ResultadoEdgeUsuariosSchema = v.variant('estado', [
  v.strictObject({
    estado: v.literal('activo'),
    perfil_id: UuidSchema,
  }),
  v.strictObject({
    estado: v.literal('candidato_existente'),
    perfil_id: UuidSchema,
  }),
])

export type ImpactoDesactivacionUsuario = v.InferOutput<typeof ImpactoDesactivacionUsuarioSchema>
export type ResultadoEdgeUsuarios = v.InferOutput<typeof ResultadoEdgeUsuariosSchema>
export type ResultadoAltaUsuario = Extract<
  ResultadoEdgeUsuarios,
  { estado: 'activo' | 'candidato_existente' }
>

export interface CrearCandidatoUsuarioInput {
  correo: string
  nombre_completo: string
  tipo_documento: string
  documento: string
  supervisor_id: string
  telefono?: string | undefined
  whatsapp?: string | undefined
  cargo?: string | undefined
}

export interface ActualizarUsuarioInput {
  perfil_id: string
  nombre_completo: string
  tipo_documento: string
  documento: string
  telefono: string | null
  whatsapp: string | null
  cargo: string | null
  version_perfil: string
}
