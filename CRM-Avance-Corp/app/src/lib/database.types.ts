// Tipos de la base de datos para el cliente Supabase (formato `gen types`).
//
// ORIGEN: derivado a mano de la migración canónica del esquema
// `supabase/migrations/20260709000001_cimientos_crm.sql` (2026-07-10), porque
// la CLI exige `supabase login` interactivo. Cuando haya token, regenerar con:
//   npm run gen:types   (usa el project-id del portal: dctqcbznekcyxhjujuci)
// y este archivo se sobreescribe completo.
//
// `public.perfiles` es un SUBCONJUNTO deliberado: solo las columnas que el CRM
// lee (la tabla completa la define el portal). Insert/Update son `never` en
// las tablas que el CRM tiene PROHIBIDO escribir desde el navegador.
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

type RolCrmDb = 'vendedor' | 'supervisor' | 'gerencia'
type EtapaDb = 'nuevo' | 'contactado' | 'reunion_agendada' | 'propuesta_enviada' | 'convertido' | 'descartado'
type OrigenDb = 'referido' | 'web' | 'whatsapp' | 'campania' | 'oficina' | 'otro'
type MotivoDescarteDb = 'sin_interes' | 'sin_fondos' | 'competencia' | 'no_responde' | 'datos_invalidos' | 'otro'
type MonedaDb = 'PEN' | 'USD'
type CategoriaInteresDb = 'nuevo' | 'renovacion' | 'upgrade'
type TipoActividadDb =
  | 'llamada_realizada'
  | 'llamada_no_contestada'
  | 'whatsapp_enviado'
  | 'whatsapp_recibido'
  | 'reunion_realizada'
  | 'nota'
  | 'cambio_etapa'
  | 'reasignacion'
  | 'conversion'

export interface Database {
  public: {
    Tables: {
      /** Subconjunto: solo lo que el CRM lee. El portal es dueño de la tabla. */
      perfiles: {
        Row: {
          id: string
          nombre_completo: string | null
          rol: string
          activo: boolean
        }
        Insert: never // el CRM jamás escribe perfiles desde el navegador
        Update: never
        Relationships: []
      }
    }
    Views: Record<string, never>
    Functions: Record<string, never>
    Enums: Record<string, never>
    CompositeTypes: Record<string, never>
  }
  crm: {
    Tables: {
      equipo: {
        Row: {
          perfil_id: string
          rol_crm: RolCrmDb
          supervisor_id: string | null
          activo: boolean
          creado_por: string | null
          creado_en: string
          actualizado_en: string
        }
        Insert: never // altas/bajas de equipo van por RPC/edge, no desde el CRM
        Update: never
        Relationships: []
      }
      leads: {
        Row: {
          id: string
          nombre_completo: string
          telefono: string
          correo: string | null
          dni: string | null
          distrito: string | null
          origen: OrigenDb
          etapa: EtapaDb
          motivo_descarte: MotivoDescarteDb | null
          monto_estimado: number | null // numeric(12,2) — PostgREST puede serializar string
          moneda: MonedaDb
          categoria_interes: CategoriaInteresDb | null
          vendedor_id: string | null
          asignado_supervisor_id: string | null
          perfil_id: string | null
          contrato_id: string | null
          convertido_en: string | null
          nota: string | null
          activo: boolean
          creado_por: string | null
          creado_en: string
          actualizado_en: string
        }
        Insert: {
          id?: string
          nombre_completo: string
          telefono: string
          correo?: string | null
          dni?: string | null
          distrito?: string | null
          origen?: OrigenDb
          etapa?: EtapaDb
          motivo_descarte?: MotivoDescarteDb | null
          monto_estimado?: number | null
          moneda?: MonedaDb
          categoria_interes?: CategoriaInteresDb | null
          vendedor_id?: string | null
          asignado_supervisor_id?: string | null
          nota?: string | null
          activo?: boolean
          creado_por?: string | null
        }
        Update: {
          nombre_completo?: string
          telefono?: string
          correo?: string | null
          dni?: string | null
          distrito?: string | null
          origen?: OrigenDb
          etapa?: EtapaDb
          motivo_descarte?: MotivoDescarteDb | null
          monto_estimado?: number | null
          moneda?: MonedaDb
          categoria_interes?: CategoriaInteresDb | null
          vendedor_id?: string | null
          asignado_supervisor_id?: string | null
          nota?: string | null
          activo?: boolean
        }
        Relationships: []
      }
      actividades: {
        Row: {
          id: string
          lead_id: string
          tipo: TipoActividadDb
          detalle: string | null
          metadata: Json
          creado_por: string | null
          creado_en: string
        }
        Insert: {
          id?: string
          lead_id: string
          tipo: TipoActividadDb
          detalle?: string | null
          metadata?: Json
          creado_por?: string | null
        }
        Update: never // timeline inmutable (sin UPDATE/DELETE para clientes API)
        Relationships: []
      }
    }
    Views: Record<string, never>
    Functions: Record<string, never>
    Enums: Record<string, never>
    CompositeTypes: Record<string, never>
  }
}
