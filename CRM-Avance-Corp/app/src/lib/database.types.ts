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
type TipoDocumentoDb = 'DNI' | 'CE' | 'PASAPORTE'
type EstadoContratoDb = 'activo' | 'vencido' | 'renovado' | 'retirado'
type ModalidadContratoDb = 'mensual' | 'trimestral' | 'semestral' | 'anual'
type TipoInteresDb = 'simple' | 'compuesto'
// Mismos literales que CategoriaInteresDb pero es OTRO dominio (contratos.categoria
// del portal, no crm.leads.categoria_interes) — se mantienen separados a propósito.
type CategoriaContratoDb = 'nuevo' | 'renovacion' | 'upgrade'
type EstadoCuotaDb = 'pendiente' | 'pagado' | 'vencido' | 'trasladado'
type TipoCuotaDb = 'cuota' | 'retorno' | 'devolucion'
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
      /** Subconjunto: solo lo que el CRM lee/corrige. El portal es dueño de la tabla. */
      perfiles: {
        Row: {
          id: string
          nombre_completo: string | null
          nombres: string | null
          apellidos: string | null
          rol: string
          activo: boolean
          tipo_documento: TipoDocumentoDb
          dni: string | null
          correo: string | null
          telefono: string | null
          asesor_perfil_id: string | null
          creado_por: string | null
          creado_en: string
          // Cuenta bancaria en SOLES (columnas base) y en DÓLARES (sufijo _usd) —
          // independientes (portal 2026-06-09). Son las "14 bancarias".
          banco: string | null
          tipo_cuenta: string | null
          numero_cuenta: string | null
          cci: string | null
          titular_distinto: boolean
          beneficiario_nombre: string | null
          beneficiario_dni: string | null
          banco_usd: string | null
          tipo_cuenta_usd: string | null
          numero_cuenta_usd: string | null
          cci_usd: string | null
          titular_distinto_usd: boolean
          beneficiario_nombre_usd: string | null
          beneficiario_dni_usd: string | null
        }
        Insert: never // el alta va SIEMPRE por la edge crear-cliente, nunca INSERT directo
        // Corrección del analista vía RLS (ventana de 5 h server-side): solo los
        // campos que el portal deja tocar. OJO: si la ventana venció el UPDATE
        // devuelve 0 filas SIN error — pedir .select('id') y tratar 0 como fallo.
        Update: {
          nombre_completo?: string
          nombres?: string | null
          apellidos?: string | null
          tipo_documento?: TipoDocumentoDb
          dni?: string | null
          telefono?: string | null
          banco?: string | null
          tipo_cuenta?: string | null
          numero_cuenta?: string | null
          cci?: string | null
          titular_distinto?: boolean
          beneficiario_nombre?: string | null
          beneficiario_dni?: string | null
          banco_usd?: string | null
          tipo_cuenta_usd?: string | null
          numero_cuenta_usd?: string | null
          cci_usd?: string | null
          titular_distinto_usd?: boolean
          beneficiario_nombre_usd?: string | null
          beneficiario_dni_usd?: string | null
          actualizado_en?: string
        }
        Relationships: []
      }
      /** Contratos del portal — el CRM solo LEE (crear/corregir van por RPC). */
      contratos: {
        Row: {
          id: string
          numero_contrato: string
          cliente_id: string
          capital: number // numeric(12,2) — PostgREST puede serializar string
          moneda: MonedaDb
          tasa_anual: number
          modalidad: ModalidadContratoDb
          tipo_interes: TipoInteresDb
          categoria: CategoriaContratoDb | null
          estado: EstadoContratoDb
          fecha_inicio: string
          fecha_vencimiento: string
          notas_internas: string | null
          creado_por: string | null
          creado_en: string
        }
        Insert: never // crear_contrato (RPC atómica) es el único camino
        Update: never // actualizar_contrato (RPC) es el único camino
        Relationships: []
      }
      /** Cronograma de cuotas — solo lectura en el CRM (los pagos son del portal). */
      cronograma_pagos: {
        Row: {
          id: string
          contrato_id: string
          numero_cuota: number
          fecha_programada: string
          monto_programado: number
          estado: EstadoCuotaDb
          tipo: TipoCuotaDb
          fecha_pago_real: string | null
          monto_pagado: number | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
      /** Co-titulares (cuentas mancomunadas) — escritura SOLO vía las RPC de contrato. */
      contrato_titulares: {
        Row: {
          id: string
          contrato_id: string
          orden: number
          nombre_completo: string
          tipo_documento: TipoDocumentoDb
          documento: string
          creado_por: string | null
          creado_en: string
        }
        Insert: never
        Update: never
        Relationships: []
      }
    }
    Views: Record<string, never>
    Functions: {
      /** RPC del PORTAL reusada por el CRM al convertir (crea contrato + cronograma
       *  atómico; valida rol/cartera server-side). Firma sin cambios. */
      crear_contrato: {
        Args: { p_contrato: Record<string, unknown>; p_cronograma: Record<string, unknown>[] }
        Returns: { id: string; numero_contrato: string }
      }
      /** RPC del PORTAL para corregir: valida creado_por → 5 h → cartera y regenera
       *  el cronograma conservando cuotas pagadas. TRAMPAS: p_contrato sin
       *  notas_internas las BORRA; 'titulares' presente (incluso []) REEMPLAZA. */
      actualizar_contrato: {
        Args: {
          p_id: string
          p_contrato: Record<string, unknown>
          p_cronograma: Record<string, unknown>[]
        }
        Returns: undefined
      }
    }
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
    Views: {
      /** Cartera de clientes del portal YA scopeada por rol del CRM (la vista
       *  resuelve el ámbito server-side). NO trae bancarios: el detalle para
       *  corregir se lee de public.perfiles directo. */
      clientes_basicos: {
        Row: {
          id: string
          nombres: string | null
          apellidos: string | null
          nombre_completo: string | null
          dni: string | null
          correo: string | null
          telefono: string | null
          asesor_perfil_id: string | null
          activo: boolean
          creado_en: string
        }
        Relationships: []
      }
    }
    Functions: {
      equipo_visible_fn: {
        Args: Record<string, never>
        Returns: {
          perfil_id: string
          nombre_completo: string
          rol_crm: RolCrmDb
          supervisor_id: string | null
          activo: boolean
        }[]
      }
      actividades_del_ambito_fn: {
        Args: Record<string, never>
        Returns: {
          id: string
          lead_id: string
          tipo: TipoActividadDb
          detalle: string | null
          autor_nombre: string
          creado_en: string
        }[]
      }
      // ── Métricas para las gráficas de gerencia (SECURITY DEFINER; el ámbito
      //    lo resuelve el SERVIDOR: gerencia=todo, supervisor=subárbol,
      //    vendedor=él). Los numeric llegan como string por PostgREST y los
      //    bigint como number: los wrappers de crm-api coercionan ambos. ─────
      metricas_capital_mes_fn: {
        Args: { p_meses?: number }
        Returns: {
          mes: string // date del GROUP BY mensual ('YYYY-MM-01')
          moneda: MonedaDb
          categoria: CategoriaContratoDb | null
          contratos: number // bigint
          capital_colocado: number // numeric — PostgREST puede serializar string
        }[]
      }
      metricas_pagos_mes_fn: {
        Args: { p_meses?: number }
        Returns: {
          mes: string
          moneda: MonedaDb
          tipo: TipoCuotaDb
          estado: EstadoCuotaDb
          cuotas: number // bigint
          monto_programado: number // numeric — PostgREST puede serializar string
          monto_pagado: number // numeric — PostgREST puede serializar string
        }[]
      }
      metricas_altas_analista_fn: {
        Args: { p_meses?: number }
        Returns: {
          mes: string
          analista_id: string
          analista_nombre: string
          altas: number // bigint
        }[]
      }
      metricas_vencimientos_fn: {
        Args: { p_dias?: number }
        Returns: {
          mes: string
          moneda: MonedaDb
          contratos_por_vencer: number // bigint
          capital_por_vencer: number // numeric — PostgREST puede serializar string
        }[]
      }
    }
    Enums: Record<string, never>
    CompositeTypes: Record<string, never>
  }
}
