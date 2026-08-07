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
  requiere_reemplazo: v.boolean(),
})

export const ResultadoPerfilActualizadoSchema = v.strictObject({
  perfil_id: UuidSchema,
  version_perfil: FechaHoraSchema,
  idempotente: v.boolean(),
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
    estado: v.literal('pendiente_rol'),
    perfil_id: UuidSchema,
    recuperacion_enviada: v.boolean(),
  }),
  v.strictObject({
    estado: v.literal('candidato_existente'),
    perfil_id: UuidSchema,
    recuperacion_enviada: v.boolean(),
  }),
  v.strictObject({
    estado: v.literal('recuperacion_enviada'),
    perfil_id: UuidSchema,
  }),
])

export type ImpactoDesactivacionUsuario = v.InferOutput<typeof ImpactoDesactivacionUsuarioSchema>
export type ResultadoEdgeUsuarios = v.InferOutput<typeof ResultadoEdgeUsuariosSchema>
export type ResultadoAltaUsuario = Extract<
  ResultadoEdgeUsuarios,
  { estado: 'pendiente_rol' | 'candidato_existente' }
>
export type ResultadoRecuperacionUsuario = Extract<
  ResultadoEdgeUsuarios,
  { estado: 'recuperacion_enviada' }
>

export interface CrearCandidatoUsuarioInput {
  correo: string
  nombre_completo: string
  tipo_documento: string
  documento: string
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
