export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  crm: {
    Tables: {
      actividades: {
        Row: {
          creado_en: string
          creado_por: string | null
          detalle: string | null
          id: string
          lead_id: string
          metadata: Json
          tipo: string
        }
        Insert: {
          creado_en?: string
          creado_por?: string | null
          detalle?: string | null
          id?: string
          lead_id: string
          metadata?: Json
          tipo: string
        }
        Update: {
          creado_en?: string
          creado_por?: string | null
          detalle?: string | null
          id?: string
          lead_id?: string
          metadata?: Json
          tipo?: string
        }
        Relationships: [
          {
            foreignKeyName: "actividades_lead_id_fkey"
            columns: ["lead_id"]
            isOneToOne: false
            referencedRelation: "leads"
            referencedColumns: ["id"]
          },
        ]
      }
      actividades_cliente: {
        Row: {
          cliente_id: string
          creado_en: string
          creado_por: string | null
          detalle: string | null
          id: string
          tarea_id: string | null
          tipo: string
          vendedor_id: string | null
        }
        Insert: {
          cliente_id: string
          creado_en?: string
          creado_por?: string | null
          detalle?: string | null
          id?: string
          tarea_id?: string | null
          tipo: string
          vendedor_id?: string | null
        }
        Update: {
          cliente_id?: string
          creado_en?: string
          creado_por?: string | null
          detalle?: string | null
          id?: string
          tarea_id?: string | null
          tipo?: string
          vendedor_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "actividades_cliente_tarea_id_fkey"
            columns: ["tarea_id"]
            isOneToOne: true
            referencedRelation: "tareas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "actividades_cliente_vendedor_id_fkey"
            columns: ["vendedor_id"]
            isOneToOne: false
            referencedRelation: "equipo"
            referencedColumns: ["perfil_id"]
          },
        ]
      }
      agenda_ics: {
        Row: {
          creado_en: string
          perfil_id: string
          rotado_en: string | null
          token: string
        }
        Insert: {
          creado_en?: string
          perfil_id: string
          rotado_en?: string | null
          token?: string
        }
        Update: {
          creado_en?: string
          perfil_id?: string
          rotado_en?: string | null
          token?: string
        }
        Relationships: [
          {
            foreignKeyName: "agenda_ics_perfil_id_fkey"
            columns: ["perfil_id"]
            isOneToOne: true
            referencedRelation: "equipo"
            referencedColumns: ["perfil_id"]
          },
        ]
      }
      ajustes_mes_cerrado: {
        Row: {
          capital_pen: number
          capital_usd: number
          creado_en: string
          creado_por: string
          detalle: Json
          id: string
          lead_id: string
          motivo: string
          numerador: number
          pendiente_detalle: Json
          pendiente_numerador: number
          pendiente_pen: number
          pendiente_usd: number
          periodo_origen: string
          saldado_en: string | null
          vendedor_id: string
        }
        Insert: {
          capital_pen?: number
          capital_usd?: number
          creado_en?: string
          creado_por: string
          detalle?: Json
          id?: string
          lead_id: string
          motivo: string
          numerador: number
          pendiente_detalle?: Json
          pendiente_numerador: number
          pendiente_pen?: number
          pendiente_usd?: number
          periodo_origen: string
          saldado_en?: string | null
          vendedor_id: string
        }
        Update: {
          capital_pen?: number
          capital_usd?: number
          creado_en?: string
          creado_por?: string
          detalle?: Json
          id?: string
          lead_id?: string
          motivo?: string
          numerador?: number
          pendiente_detalle?: Json
          pendiente_numerador?: number
          pendiente_pen?: number
          pendiente_usd?: number
          periodo_origen?: string
          saldado_en?: string | null
          vendedor_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ajustes_mes_cerrado_lead_id_fkey"
            columns: ["lead_id"]
            isOneToOne: true
            referencedRelation: "leads"
            referencedColumns: ["id"]
          },
        ]
      }
      alertas_reconocimientos: {
        Row: {
          accion: string
          alerta_id: string
          creado_en: string
          hasta: string | null
          id: string
          miembros: string[]
          perfil_id: string
          secuencia: number
          severidad: string
        }
        Insert: {
          accion: string
          alerta_id: string
          creado_en?: string
          hasta?: string | null
          id?: string
          miembros: string[]
          perfil_id: string
          secuencia?: never
          severidad: string
        }
        Update: {
          accion?: string
          alerta_id?: string
          creado_en?: string
          hasta?: string | null
          id?: string
          miembros?: string[]
          perfil_id?: string
          secuencia?: never
          severidad?: string
        }
        Relationships: []
      }
      cierre_mes_vendedor: {
        Row: {
          ajuste_numerador: number
          ajuste_pen: number
          ajuste_usd: number
          cartera: Json
          cierres_de_arrastre: number
          cierres_no_referidos: number
          cierres_referidos: number
          conversion_objetivo: number
          conversion_pct: number | null
          detalles: Json
          divisor: number
          divisor_aproximado: number
          divisor_por_motivo: Json
          estado: string
          nombre_completo: string
          numerador: number
          periodo: string
          procedencia: Json
          referidos_aporta_pct: number | null
          referidos_dados_de_alta: number
          referidos_recibidos: number
          supervisor_id: string
          supervisor_nombre: string
          vendedor_id: string
        }
        Insert: {
          ajuste_numerador?: number
          ajuste_pen?: number
          ajuste_usd?: number
          cartera?: Json
          cierres_de_arrastre: number
          cierres_no_referidos: number
          cierres_referidos: number
          conversion_objetivo: number
          conversion_pct?: number | null
          detalles?: Json
          divisor: number
          divisor_aproximado?: number
          divisor_por_motivo?: Json
          estado: string
          nombre_completo: string
          numerador: number
          periodo: string
          procedencia?: Json
          referidos_aporta_pct?: number | null
          referidos_dados_de_alta: number
          referidos_recibidos: number
          supervisor_id: string
          supervisor_nombre: string
          vendedor_id: string
        }
        Update: {
          ajuste_numerador?: number
          ajuste_pen?: number
          ajuste_usd?: number
          cartera?: Json
          cierres_de_arrastre?: number
          cierres_no_referidos?: number
          cierres_referidos?: number
          conversion_objetivo?: number
          conversion_pct?: number | null
          detalles?: Json
          divisor?: number
          divisor_aproximado?: number
          divisor_por_motivo?: Json
          estado?: string
          nombre_completo?: string
          numerador?: number
          periodo?: string
          procedencia?: Json
          referidos_aporta_pct?: number | null
          referidos_dados_de_alta?: number
          referidos_recibidos?: number
          supervisor_id?: string
          supervisor_nombre?: string
          vendedor_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "cierre_mes_vendedor_periodo_fkey"
            columns: ["periodo"]
            isOneToOne: false
            referencedRelation: "periodos_cerrados"
            referencedColumns: ["periodo"]
          },
        ]
      }
      cierres_avance_anulados: {
        Row: {
          acreditado_a: string | null
          anulado_en: string
          anulado_por: string
          id: string
          lead_id: string
          motivo: string
        }
        Insert: {
          acreditado_a?: string | null
          anulado_en?: string
          anulado_por: string
          id?: string
          lead_id: string
          motivo: string
        }
        Update: {
          acreditado_a?: string | null
          anulado_en?: string
          anulado_por?: string
          id?: string
          lead_id?: string
          motivo?: string
        }
        Relationships: [
          {
            foreignKeyName: "cierres_avance_anulados_lead_id_fkey"
            columns: ["lead_id"]
            isOneToOne: true
            referencedRelation: "leads"
            referencedColumns: ["id"]
          },
        ]
      }
      cierres_externos: {
        Row: {
          anulado_en: string | null
          anulado_por: string | null
          cooperativa: string
          creado_en: string
          creado_por: string
          documento: string
          documento_tipo: string
          id: string
          lead_id: string
          moneda: string
          monto: number
          motivo_anulacion: string | null
          nombre_completo: string
          nota: string | null
          numero_transaccion: string
          referencia_externa: string | null
          vence_en: string | null
          vendedor_id: string
        }
        Insert: {
          anulado_en?: string | null
          anulado_por?: string | null
          cooperativa: string
          creado_en?: string
          creado_por: string
          documento: string
          documento_tipo: string
          id?: string
          lead_id: string
          moneda: string
          monto: number
          motivo_anulacion?: string | null
          nombre_completo: string
          nota?: string | null
          numero_transaccion: string
          referencia_externa?: string | null
          vence_en?: string | null
          vendedor_id: string
        }
        Update: {
          anulado_en?: string | null
          anulado_por?: string | null
          cooperativa?: string
          creado_en?: string
          creado_por?: string
          documento?: string
          documento_tipo?: string
          id?: string
          lead_id?: string
          moneda?: string
          monto?: number
          motivo_anulacion?: string | null
          nombre_completo?: string
          nota?: string | null
          numero_transaccion?: string
          referencia_externa?: string | null
          vence_en?: string | null
          vendedor_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "cierres_externos_lead_id_fkey"
            columns: ["lead_id"]
            isOneToOne: true
            referencedRelation: "leads"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cierres_externos_vendedor_id_fkey"
            columns: ["vendedor_id"]
            isOneToOne: false
            referencedRelation: "equipo"
            referencedColumns: ["perfil_id"]
          },
        ]
      }
      contrato_cuentas_pago: {
        Row: {
          contrato_id: string
          creado_en: string
          creado_por: string | null
          cuenta_bancaria_id: string
          id: string
        }
        Insert: {
          contrato_id: string
          creado_en?: string
          creado_por?: string | null
          cuenta_bancaria_id: string
          id?: string
        }
        Update: {
          contrato_id?: string
          creado_en?: string
          creado_por?: string | null
          cuenta_bancaria_id?: string
          id?: string
        }
        Relationships: [
          {
            foreignKeyName: "contrato_cuentas_pago_cuenta_bancaria_id_fkey"
            columns: ["cuenta_bancaria_id"]
            isOneToOne: false
            referencedRelation: "cuentas_bancarias"
            referencedColumns: ["id"]
          },
        ]
      }
      conversion_pesos: {
        Row: {
          creado_en: string
          nota: string | null
          peso_referido: number
          vigente_desde: string
        }
        Insert: {
          creado_en?: string
          nota?: string | null
          peso_referido: number
          vigente_desde: string
        }
        Update: {
          creado_en?: string
          nota?: string | null
          peso_referido?: number
          vigente_desde?: string
        }
        Relationships: []
      }
      conversion_reservas: {
        Row: {
          efectos_iniciados_en: string | null
          expira_en: string
          id: string
          lead_id: string
          reservado_en: string
          reservado_por: string
          vence_absoluto_en: string
        }
        Insert: {
          efectos_iniciados_en?: string | null
          expira_en: string
          id?: string
          lead_id: string
          reservado_en?: string
          reservado_por: string
          vence_absoluto_en: string
        }
        Update: {
          efectos_iniciados_en?: string | null
          expira_en?: string
          id?: string
          lead_id?: string
          reservado_en?: string
          reservado_por?: string
          vence_absoluto_en?: string
        }
        Relationships: [
          {
            foreignKeyName: "conversion_reservas_lead_id_fkey"
            columns: ["lead_id"]
            isOneToOne: true
            referencedRelation: "leads"
            referencedColumns: ["id"]
          },
        ]
      }
      cuentas_bancarias: {
        Row: {
          activa: boolean
          banco: string
          beneficiario_dni: string | null
          beneficiario_nombre: string | null
          cci: string
          cliente_id: string
          creado_en: string
          creado_por: string | null
          desactivada_en: string | null
          desactivada_por: string | null
          id: string
          moneda: string
          numero_cuenta: string
          origen: string
          tipo_cuenta: string
          titular_distinto: boolean
        }
        Insert: {
          activa?: boolean
          banco: string
          beneficiario_dni?: string | null
          beneficiario_nombre?: string | null
          cci: string
          cliente_id: string
          creado_en?: string
          creado_por?: string | null
          desactivada_en?: string | null
          desactivada_por?: string | null
          id?: string
          moneda: string
          numero_cuenta: string
          origen: string
          tipo_cuenta: string
          titular_distinto?: boolean
        }
        Update: {
          activa?: boolean
          banco?: string
          beneficiario_dni?: string | null
          beneficiario_nombre?: string | null
          cci?: string
          cliente_id?: string
          creado_en?: string
          creado_por?: string | null
          desactivada_en?: string | null
          desactivada_por?: string | null
          id?: string
          moneda?: string
          numero_cuenta?: string
          origen?: string
          tipo_cuenta?: string
          titular_distinto?: boolean
        }
        Relationships: []
      }
      depositos_reclamados: {
        Row: {
          cierre_id: string
          id: string
          numero_norm: string
          reclamado_en: string
          reclamado_por: string
        }
        Insert: {
          cierre_id: string
          id?: string
          numero_norm: string
          reclamado_en?: string
          reclamado_por: string
        }
        Update: {
          cierre_id?: string
          id?: string
          numero_norm?: string
          reclamado_en?: string
          reclamado_por?: string
        }
        Relationships: [
          {
            foreignKeyName: "depositos_reclamados_cierre_id_fkey"
            columns: ["cierre_id"]
            isOneToOne: false
            referencedRelation: "cierres_externos"
            referencedColumns: ["id"]
          },
        ]
      }
      enfriamiento_politica: {
        Row: {
          actualizado_en: string
          actualizado_por: string | null
          dias: number
          motivo: string
        }
        Insert: {
          actualizado_en?: string
          actualizado_por?: string | null
          dias: number
          motivo: string
        }
        Update: {
          actualizado_en?: string
          actualizado_por?: string | null
          dias?: number
          motivo?: string
        }
        Relationships: []
      }
      equipo: {
        Row: {
          activo: boolean
          actualizado_en: string
          capacidad_leads_objetivo: number | null
          creado_en: string
          creado_por: string | null
          perfil_id: string
          rol_crm: string
          supervisor_id: string | null
        }
        Insert: {
          activo?: boolean
          actualizado_en?: string
          capacidad_leads_objetivo?: number | null
          creado_en?: string
          creado_por?: string | null
          perfil_id: string
          rol_crm: string
          supervisor_id?: string | null
        }
        Update: {
          activo?: boolean
          actualizado_en?: string
          capacidad_leads_objetivo?: number | null
          creado_en?: string
          creado_por?: string | null
          perfil_id?: string
          rol_crm?: string
          supervisor_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "equipo_supervisor_id_fkey"
            columns: ["supervisor_id"]
            isOneToOne: false
            referencedRelation: "equipo"
            referencedColumns: ["perfil_id"]
          },
        ]
      }
      lead_asignacion_sla_hitos: {
        Row: {
          creado_en: string
          id: string
          lead_asignacion_id: string
          primer_contacto_en: string | null
          primera_gestion_en: string | null
        }
        Insert: {
          creado_en?: string
          id?: string
          lead_asignacion_id: string
          primer_contacto_en?: string | null
          primera_gestion_en?: string | null
        }
        Update: {
          creado_en?: string
          id?: string
          lead_asignacion_id?: string
          primer_contacto_en?: string | null
          primera_gestion_en?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "lead_asignacion_sla_hitos_lead_asignacion_id_fkey"
            columns: ["lead_asignacion_id"]
            isOneToOne: true
            referencedRelation: "lead_asignaciones"
            referencedColumns: ["id"]
          },
        ]
      }
      lead_asignaciones: {
        Row: {
          analista_destino_id: string | null
          analista_id: string
          aproximado: boolean
          asignado_en: string
          asignado_por: string | null
          categoria_interes: string | null
          ciclo_n: number
          creado_en: string
          episodio_n: number
          finalizado_en: string | null
          finalizado_por: string | null
          id: string
          lead_id: string
          moneda: string
          monto_estimado: number | null
          motivo_apertura: string
          motivo_cierre: string | null
          motivo_descarte_cierre: string | null
          origen: string
          primer_contacto_limite_en: string
          primera_gestion_limite_en: string
          resultado: string | null
          resultado_en: string | null
          sla_global_aproximado: boolean
          sla_global_iniciado_en: string
          sla_politica_asignacion_id: string
          supervisor_destino_id: string | null
          supervisor_origen_id: string | null
        }
        Insert: {
          analista_destino_id?: string | null
          analista_id: string
          aproximado?: boolean
          asignado_en: string
          asignado_por?: string | null
          categoria_interes?: string | null
          ciclo_n: number
          creado_en?: string
          episodio_n: number
          finalizado_en?: string | null
          finalizado_por?: string | null
          id?: string
          lead_id: string
          moneda: string
          monto_estimado?: number | null
          motivo_apertura: string
          motivo_cierre?: string | null
          motivo_descarte_cierre?: string | null
          origen: string
          primer_contacto_limite_en: string
          primera_gestion_limite_en: string
          resultado?: string | null
          resultado_en?: string | null
          sla_global_aproximado?: boolean
          sla_global_iniciado_en: string
          sla_politica_asignacion_id: string
          supervisor_destino_id?: string | null
          supervisor_origen_id?: string | null
        }
        Update: {
          analista_destino_id?: string | null
          analista_id?: string
          aproximado?: boolean
          asignado_en?: string
          asignado_por?: string | null
          categoria_interes?: string | null
          ciclo_n?: number
          creado_en?: string
          episodio_n?: number
          finalizado_en?: string | null
          finalizado_por?: string | null
          id?: string
          lead_id?: string
          moneda?: string
          monto_estimado?: number | null
          motivo_apertura?: string
          motivo_cierre?: string | null
          motivo_descarte_cierre?: string | null
          origen?: string
          primer_contacto_limite_en?: string
          primera_gestion_limite_en?: string
          resultado?: string | null
          resultado_en?: string | null
          sla_global_aproximado?: boolean
          sla_global_iniciado_en?: string
          sla_politica_asignacion_id?: string
          supervisor_destino_id?: string | null
          supervisor_origen_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "lead_asignaciones_analista_destino_id_fkey"
            columns: ["analista_destino_id"]
            isOneToOne: false
            referencedRelation: "equipo"
            referencedColumns: ["perfil_id"]
          },
          {
            foreignKeyName: "lead_asignaciones_analista_id_fkey"
            columns: ["analista_id"]
            isOneToOne: false
            referencedRelation: "equipo"
            referencedColumns: ["perfil_id"]
          },
          {
            foreignKeyName: "lead_asignaciones_lead_id_fkey"
            columns: ["lead_id"]
            isOneToOne: false
            referencedRelation: "leads"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lead_asignaciones_sla_politica_asignacion_id_fkey"
            columns: ["sla_politica_asignacion_id"]
            isOneToOne: false
            referencedRelation: "sla_politicas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lead_asignaciones_supervisor_destino_id_fkey"
            columns: ["supervisor_destino_id"]
            isOneToOne: false
            referencedRelation: "equipo"
            referencedColumns: ["perfil_id"]
          },
          {
            foreignKeyName: "lead_asignaciones_supervisor_origen_id_fkey"
            columns: ["supervisor_origen_id"]
            isOneToOne: false
            referencedRelation: "equipo"
            referencedColumns: ["perfil_id"]
          },
        ]
      }
      lead_sla_ciclos: {
        Row: {
          aproximado: boolean
          ciclo_n: number
          creado_en: string
          id: string
          iniciado_en: string
          lead_id: string
          politica_id: string
          primer_contacto_en: string | null
          primer_contacto_limite_en: string
          primera_gestion_en: string | null
          primera_gestion_limite_en: string
        }
        Insert: {
          aproximado?: boolean
          ciclo_n: number
          creado_en?: string
          id?: string
          iniciado_en: string
          lead_id: string
          politica_id: string
          primer_contacto_en?: string | null
          primer_contacto_limite_en: string
          primera_gestion_en?: string | null
          primera_gestion_limite_en: string
        }
        Update: {
          aproximado?: boolean
          ciclo_n?: number
          creado_en?: string
          id?: string
          iniciado_en?: string
          lead_id?: string
          politica_id?: string
          primer_contacto_en?: string | null
          primer_contacto_limite_en?: string
          primera_gestion_en?: string | null
          primera_gestion_limite_en?: string
        }
        Relationships: [
          {
            foreignKeyName: "lead_sla_ciclos_lead_id_fkey"
            columns: ["lead_id"]
            isOneToOne: false
            referencedRelation: "leads"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lead_sla_ciclos_politica_id_fkey"
            columns: ["politica_id"]
            isOneToOne: false
            referencedRelation: "sla_politicas"
            referencedColumns: ["id"]
          },
        ]
      }
      lead_sla_etapas: {
        Row: {
          aproximado: boolean
          ciclo_n: number
          creado_en: string
          episodio_n: number
          etapa: string
          finalizado_en: string | null
          id: string
          iniciado_en: string
          lead_id: string
          limite_en: string
          motivo_cierre: string | null
          politica_id: string
        }
        Insert: {
          aproximado?: boolean
          ciclo_n: number
          creado_en?: string
          episodio_n: number
          etapa: string
          finalizado_en?: string | null
          id?: string
          iniciado_en: string
          lead_id: string
          limite_en: string
          motivo_cierre?: string | null
          politica_id: string
        }
        Update: {
          aproximado?: boolean
          ciclo_n?: number
          creado_en?: string
          episodio_n?: number
          etapa?: string
          finalizado_en?: string | null
          id?: string
          iniciado_en?: string
          lead_id?: string
          limite_en?: string
          motivo_cierre?: string | null
          politica_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "lead_sla_etapas_ciclo_fk"
            columns: ["lead_id", "ciclo_n"]
            isOneToOne: false
            referencedRelation: "lead_sla_ciclos"
            referencedColumns: ["lead_id", "ciclo_n"]
          },
          {
            foreignKeyName: "lead_sla_etapas_lead_id_fkey"
            columns: ["lead_id"]
            isOneToOne: false
            referencedRelation: "leads"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lead_sla_etapas_politica_id_fkey"
            columns: ["politica_id"]
            isOneToOne: false
            referencedRelation: "sla_politicas"
            referencedColumns: ["id"]
          },
        ]
      }
      leads: {
        Row: {
          activo: boolean
          actualizado_en: string
          alta_manual: boolean
          asignado_supervisor_id: string | null
          categoria_interes: string | null
          ciclo_actual: number
          clasificacion_auto: string | null
          consentimiento_en: string | null
          consentimiento_fuente: string | null
          contrato_id: string | null
          convertido_en: string | null
          correo: string | null
          creado_en: string
          creado_por: string | null
          descartado_en: string | null
          descartado_por: string | null
          distrito: string | null
          dni: string | null
          etapa: string
          fecha_nacimiento: string | null
          genero: string | null
          id: string
          moneda: string
          monto_estimado: number
          motivo_descarte: string | null
          no_contactar: boolean
          nombre_completo: string
          nota: string | null
          origen: string
          perfil_id: string | null
          sla_global_aproximado: boolean
          sla_global_iniciado_en: string
          telefono: string
          telefono_alternativo: string | null
          telefono_alternativo_crudo: string | null
          tenencia_desde: string | null
          vendedor_id: string | null
        }
        Insert: {
          activo?: boolean
          actualizado_en?: string
          alta_manual?: boolean
          asignado_supervisor_id?: string | null
          categoria_interes?: string | null
          ciclo_actual?: number
          clasificacion_auto?: string | null
          consentimiento_en?: string | null
          consentimiento_fuente?: string | null
          contrato_id?: string | null
          convertido_en?: string | null
          correo?: string | null
          creado_en?: string
          creado_por?: string | null
          descartado_en?: string | null
          descartado_por?: string | null
          distrito?: string | null
          dni?: string | null
          etapa?: string
          fecha_nacimiento?: string | null
          genero?: string | null
          id?: string
          moneda?: string
          monto_estimado: number
          motivo_descarte?: string | null
          no_contactar?: boolean
          nombre_completo: string
          nota?: string | null
          origen?: string
          perfil_id?: string | null
          sla_global_aproximado?: boolean
          sla_global_iniciado_en?: string
          telefono: string
          telefono_alternativo?: string | null
          telefono_alternativo_crudo?: string | null
          tenencia_desde?: string | null
          vendedor_id?: string | null
        }
        Update: {
          activo?: boolean
          actualizado_en?: string
          alta_manual?: boolean
          asignado_supervisor_id?: string | null
          categoria_interes?: string | null
          ciclo_actual?: number
          clasificacion_auto?: string | null
          consentimiento_en?: string | null
          consentimiento_fuente?: string | null
          contrato_id?: string | null
          convertido_en?: string | null
          correo?: string | null
          creado_en?: string
          creado_por?: string | null
          descartado_en?: string | null
          descartado_por?: string | null
          distrito?: string | null
          dni?: string | null
          etapa?: string
          fecha_nacimiento?: string | null
          genero?: string | null
          id?: string
          moneda?: string
          monto_estimado?: number
          motivo_descarte?: string | null
          no_contactar?: boolean
          nombre_completo?: string
          nota?: string | null
          origen?: string
          perfil_id?: string | null
          sla_global_aproximado?: boolean
          sla_global_iniciado_en?: string
          telefono?: string
          telefono_alternativo?: string | null
          telefono_alternativo_crudo?: string | null
          tenencia_desde?: string | null
          vendedor_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "leads_asignado_supervisor_id_fkey"
            columns: ["asignado_supervisor_id"]
            isOneToOne: false
            referencedRelation: "equipo"
            referencedColumns: ["perfil_id"]
          },
          {
            foreignKeyName: "leads_vendedor_id_fkey"
            columns: ["vendedor_id"]
            isOneToOne: false
            referencedRelation: "equipo"
            referencedColumns: ["perfil_id"]
          },
        ]
      }
      meta_periodos: {
        Row: {
          id: string
          periodo: string
          publicada_en: string
          publicada_por: string
          revision: number
          revision_anterior_id: string | null
        }
        Insert: {
          id?: string
          periodo: string
          publicada_en?: string
          publicada_por: string
          revision: number
          revision_anterior_id?: string | null
        }
        Update: {
          id?: string
          periodo?: string
          publicada_en?: string
          publicada_por?: string
          revision?: number
          revision_anterior_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "meta_periodos_revision_anterior_id_fkey"
            columns: ["revision_anterior_id"]
            isOneToOne: false
            referencedRelation: "meta_periodos"
            referencedColumns: ["id"]
          },
        ]
      }
      metas_vendedor: {
        Row: {
          conversion_objetivo: number
          creado_en: string
          id: string
          meta_periodo_id: string
          supervisor_id: string
          vendedor_id: string
        }
        Insert: {
          conversion_objetivo: number
          creado_en?: string
          id?: string
          meta_periodo_id: string
          supervisor_id: string
          vendedor_id: string
        }
        Update: {
          conversion_objetivo?: number
          creado_en?: string
          id?: string
          meta_periodo_id?: string
          supervisor_id?: string
          vendedor_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "metas_vendedor_meta_periodo_id_fkey"
            columns: ["meta_periodo_id"]
            isOneToOne: false
            referencedRelation: "meta_periodos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "metas_vendedor_supervisor_id_fkey"
            columns: ["supervisor_id"]
            isOneToOne: false
            referencedRelation: "equipo"
            referencedColumns: ["perfil_id"]
          },
          {
            foreignKeyName: "metas_vendedor_vendedor_id_fkey"
            columns: ["vendedor_id"]
            isOneToOne: false
            referencedRelation: "equipo"
            referencedColumns: ["perfil_id"]
          },
        ]
      }
      metas_vendedor_detalle: {
        Row: {
          capital_objetivo: number
          categoria: string
          contratos_objetivo: number
          creado_en: string
          id: string
          meta_vendedor_id: string
          moneda: string
        }
        Insert: {
          capital_objetivo: number
          categoria: string
          contratos_objetivo: number
          creado_en?: string
          id?: string
          meta_vendedor_id: string
          moneda: string
        }
        Update: {
          capital_objetivo?: number
          categoria?: string
          contratos_objetivo?: number
          creado_en?: string
          id?: string
          meta_vendedor_id?: string
          moneda?: string
        }
        Relationships: [
          {
            foreignKeyName: "metas_vendedor_detalle_meta_vendedor_id_fkey"
            columns: ["meta_vendedor_id"]
            isOneToOne: false
            referencedRelation: "metas_vendedor"
            referencedColumns: ["id"]
          },
        ]
      }
      objetivos_legacy_archivo: {
        Row: {
          actualizado_en: string
          actualizado_por: string | null
          capital_objetivo: number
          conversion_objetivo: number
          creado_en: string
          id: string
          periodo: string
          rol: string
          ventas_objetivo: number
        }
        Insert: {
          actualizado_en?: string
          actualizado_por?: string | null
          capital_objetivo?: number
          conversion_objetivo?: number
          creado_en?: string
          id?: string
          periodo: string
          rol: string
          ventas_objetivo?: number
        }
        Update: {
          actualizado_en?: string
          actualizado_por?: string | null
          capital_objetivo?: number
          conversion_objetivo?: number
          creado_en?: string
          id?: string
          periodo?: string
          rol?: string
          ventas_objetivo?: number
        }
        Relationships: []
      }
      objetivos_vendedores_legacy_archivo: {
        Row: {
          actualizado_en: string
          actualizado_por: string
          capital_objetivo: number
          conversion_objetivo: number
          creado_en: string
          id: string
          periodo: string
          supervisor_id: string
          vendedor_id: string
          ventas_objetivo: number
        }
        Insert: {
          actualizado_en?: string
          actualizado_por: string
          capital_objetivo?: number
          conversion_objetivo?: number
          creado_en?: string
          id?: string
          periodo: string
          supervisor_id: string
          vendedor_id: string
          ventas_objetivo?: number
        }
        Update: {
          actualizado_en?: string
          actualizado_por?: string
          capital_objetivo?: number
          conversion_objetivo?: number
          creado_en?: string
          id?: string
          periodo?: string
          supervisor_id?: string
          vendedor_id?: string
          ventas_objetivo?: number
        }
        Relationships: [
          {
            foreignKeyName: "objetivos_vendedores_supervisor_id_fkey"
            columns: ["supervisor_id"]
            isOneToOne: false
            referencedRelation: "equipo"
            referencedColumns: ["perfil_id"]
          },
          {
            foreignKeyName: "objetivos_vendedores_vendedor_id_fkey"
            columns: ["vendedor_id"]
            isOneToOne: false
            referencedRelation: "equipo"
            referencedColumns: ["perfil_id"]
          },
        ]
      }
      operaciones_cartera: {
        Row: {
          capital_adicional: number | null
          capital_renovado: number | null
          cliente_id: string
          contrato_nuevo_id: string
          contrato_origen_id: string | null
          creado_en: string
          creado_por: string
          desglose_completo: boolean
          elegible_conversion: boolean
          fecha_operacion: string
          fuente: string
          id: string
          moneda: string
          periodo: string
          tipo: string
          vendedor_id: string
        }
        Insert: {
          capital_adicional?: number | null
          capital_renovado?: number | null
          cliente_id: string
          contrato_nuevo_id: string
          contrato_origen_id?: string | null
          creado_en?: string
          creado_por: string
          desglose_completo?: boolean
          elegible_conversion: boolean
          fecha_operacion: string
          fuente: string
          id?: string
          moneda: string
          periodo: string
          tipo: string
          vendedor_id: string
        }
        Update: {
          capital_adicional?: number | null
          capital_renovado?: number | null
          cliente_id?: string
          contrato_nuevo_id?: string
          contrato_origen_id?: string | null
          creado_en?: string
          creado_por?: string
          desglose_completo?: boolean
          elegible_conversion?: boolean
          fecha_operacion?: string
          fuente?: string
          id?: string
          moneda?: string
          periodo?: string
          tipo?: string
          vendedor_id?: string
        }
        Relationships: []
      }
      periodos_cerrados: {
        Row: {
          automatico: boolean
          cerrado_en: string
          cerrado_por: string | null
          cobertura: Json
          meta_revision: number
          periodo: string
          ponderacion_referido: number
        }
        Insert: {
          automatico?: boolean
          cerrado_en?: string
          cerrado_por?: string | null
          cobertura: Json
          meta_revision: number
          periodo: string
          ponderacion_referido: number
        }
        Update: {
          automatico?: boolean
          cerrado_en?: string
          cerrado_por?: string | null
          cobertura?: Json
          meta_revision?: number
          periodo?: string
          ponderacion_referido?: number
        }
        Relationships: []
      }
      politica_abandono: {
        Row: {
          actualizado_en: string
          actualizado_por: string | null
          dias_abandono: number
          dias_auto_bolsa: number
          singleton: boolean
        }
        Insert: {
          actualizado_en?: string
          actualizado_por?: string | null
          dias_abandono: number
          dias_auto_bolsa: number
          singleton?: boolean
        }
        Update: {
          actualizado_en?: string
          actualizado_por?: string | null
          dias_abandono?: number
          dias_auto_bolsa?: number
          singleton?: boolean
        }
        Relationships: []
      }
      producto_condiciones: {
        Row: {
          activa: boolean
          capital_maximo: number
          capital_minimo: number
          categoria: string | null
          creado_en: string
          creado_por: string | null
          es_legacy: boolean
          fecha_inicio_legacy: string | null
          fecha_vencimiento_legacy: string | null
          id: string
          legacy_contrato_id: string | null
          modalidad: string
          moneda: string
          orden: number
          plazo_meses: number | null
          retirada_en: string | null
          retirada_por: string | null
          tasa_maxima: number
          tasa_minima: number
          tasa_referencia: number
          tipo_interes: string
          version_id: string
        }
        Insert: {
          activa?: boolean
          capital_maximo: number
          capital_minimo: number
          categoria?: string | null
          creado_en?: string
          creado_por?: string | null
          es_legacy?: boolean
          fecha_inicio_legacy?: string | null
          fecha_vencimiento_legacy?: string | null
          id?: string
          legacy_contrato_id?: string | null
          modalidad: string
          moneda: string
          orden: number
          plazo_meses?: number | null
          retirada_en?: string | null
          retirada_por?: string | null
          tasa_maxima: number
          tasa_minima: number
          tasa_referencia: number
          tipo_interes: string
          version_id: string
        }
        Update: {
          activa?: boolean
          capital_maximo?: number
          capital_minimo?: number
          categoria?: string | null
          creado_en?: string
          creado_por?: string | null
          es_legacy?: boolean
          fecha_inicio_legacy?: string | null
          fecha_vencimiento_legacy?: string | null
          id?: string
          legacy_contrato_id?: string | null
          modalidad?: string
          moneda?: string
          orden?: number
          plazo_meses?: number | null
          retirada_en?: string | null
          retirada_por?: string | null
          tasa_maxima?: number
          tasa_minima?: number
          tasa_referencia?: number
          tipo_interes?: string
          version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "producto_condiciones_version_id_fkey"
            columns: ["version_id"]
            isOneToOne: false
            referencedRelation: "producto_versiones"
            referencedColumns: ["id"]
          },
        ]
      }
      producto_versiones: {
        Row: {
          actualizado_en: string
          actualizado_por: string | null
          creado_en: string
          creado_por: string | null
          descripcion: string | null
          estado: string
          id: string
          nombre: string
          numero_version: number
          producto_id: string
          publicada_en: string | null
          publicada_por: string | null
          retirada_en: string | null
          retirada_por: string | null
          revision: number
          vigente_desde: string
          vigente_hasta: string | null
        }
        Insert: {
          actualizado_en?: string
          actualizado_por?: string | null
          creado_en?: string
          creado_por?: string | null
          descripcion?: string | null
          estado?: string
          id?: string
          nombre: string
          numero_version: number
          producto_id: string
          publicada_en?: string | null
          publicada_por?: string | null
          retirada_en?: string | null
          retirada_por?: string | null
          revision?: number
          vigente_desde: string
          vigente_hasta?: string | null
        }
        Update: {
          actualizado_en?: string
          actualizado_por?: string | null
          creado_en?: string
          creado_por?: string | null
          descripcion?: string | null
          estado?: string
          id?: string
          nombre?: string
          numero_version?: number
          producto_id?: string
          publicada_en?: string | null
          publicada_por?: string | null
          retirada_en?: string | null
          retirada_por?: string | null
          revision?: number
          vigente_desde?: string
          vigente_hasta?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "producto_versiones_producto_id_fkey"
            columns: ["producto_id"]
            isOneToOne: false
            referencedRelation: "productos_inversion"
            referencedColumns: ["id"]
          },
        ]
      }
      productos_inversion: {
        Row: {
          actualizado_en: string
          actualizado_por: string | null
          archivado_en: string | null
          archivado_por: string | null
          codigo: string
          creado_en: string
          creado_por: string | null
          es_legacy: boolean
          estado: string
          id: string
          permite_altas_legacy: boolean
          revision: number
        }
        Insert: {
          actualizado_en?: string
          actualizado_por?: string | null
          archivado_en?: string | null
          archivado_por?: string | null
          codigo: string
          creado_en?: string
          creado_por?: string | null
          es_legacy?: boolean
          estado?: string
          id?: string
          permite_altas_legacy?: boolean
          revision?: number
        }
        Update: {
          actualizado_en?: string
          actualizado_por?: string | null
          archivado_en?: string | null
          archivado_por?: string | null
          codigo?: string
          creado_en?: string
          creado_por?: string | null
          es_legacy?: boolean
          estado?: string
          id?: string
          permite_altas_legacy?: boolean
          revision?: number
        }
        Relationships: []
      }
      reasignaciones_analista: {
        Row: {
          analista_a: string
          analista_de: string | null
          contrato_id: string
          id: string
          motivo: string
          reasignado_en: string
          reasignado_por: string
        }
        Insert: {
          analista_a: string
          analista_de?: string | null
          contrato_id: string
          id?: string
          motivo: string
          reasignado_en?: string
          reasignado_por: string
        }
        Update: {
          analista_a?: string
          analista_de?: string | null
          contrato_id?: string
          id?: string
          motivo?: string
          reasignado_en?: string
          reasignado_por?: string
        }
        Relationships: [
          {
            foreignKeyName: "reasignaciones_analista_analista_a_fkey"
            columns: ["analista_a"]
            isOneToOne: false
            referencedRelation: "equipo"
            referencedColumns: ["perfil_id"]
          },
          {
            foreignKeyName: "reasignaciones_analista_analista_de_fkey"
            columns: ["analista_de"]
            isOneToOne: false
            referencedRelation: "equipo"
            referencedColumns: ["perfil_id"]
          },
        ]
      }
      recordatorios_disponibilidad: {
        Row: {
          creado_en: string
          dni: string | null
          id: string
          perfil_id: string
          recordar_en: string
          telefono: string
        }
        Insert: {
          creado_en?: string
          dni?: string | null
          id?: string
          perfil_id: string
          recordar_en: string
          telefono: string
        }
        Update: {
          creado_en?: string
          dni?: string | null
          id?: string
          perfil_id?: string
          recordar_en?: string
          telefono?: string
        }
        Relationships: []
      }
      sla_politica_etapas: {
        Row: {
          etapa: string
          id: string
          maximo_minutos: number
          politica_id: string
        }
        Insert: {
          etapa: string
          id?: string
          maximo_minutos: number
          politica_id: string
        }
        Update: {
          etapa?: string
          id?: string
          maximo_minutos?: number
          politica_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "sla_politica_etapas_politica_id_fkey"
            columns: ["politica_id"]
            isOneToOne: false
            referencedRelation: "sla_politicas"
            referencedColumns: ["id"]
          },
        ]
      }
      sla_politicas: {
        Row: {
          id: string
          primer_contacto_minutos: number
          primera_gestion_minutos: number
          publicada_en: string
          publicada_por: string | null
          tipo_reloj: string
          version: number
          version_anterior_id: string | null
          vigente_desde: string
          zona_horaria: string
        }
        Insert: {
          id?: string
          primer_contacto_minutos: number
          primera_gestion_minutos: number
          publicada_en?: string
          publicada_por?: string | null
          tipo_reloj: string
          version: number
          version_anterior_id?: string | null
          vigente_desde: string
          zona_horaria: string
        }
        Update: {
          id?: string
          primer_contacto_minutos?: number
          primera_gestion_minutos?: number
          publicada_en?: string
          publicada_por?: string | null
          tipo_reloj?: string
          version?: number
          version_anterior_id?: string | null
          vigente_desde?: string
          zona_horaria?: string
        }
        Relationships: [
          {
            foreignKeyName: "sla_politicas_version_anterior_id_fkey"
            columns: ["version_anterior_id"]
            isOneToOne: false
            referencedRelation: "sla_politicas"
            referencedColumns: ["id"]
          },
        ]
      }
      tareas: {
        Row: {
          activo: boolean
          actualizado_en: string
          asignado_supervisor_id: string | null
          cancelada_por: string | null
          cancelada_por_id: string | null
          confirmada_en: string | null
          creado_en: string
          creado_por: string | null
          detalle_cierre_reunion: string | null
          duracion_min: number | null
          enlace_reunion: string | null
          estado: string
          id: string
          lead_id: string | null
          modalidad_reunion: string | null
          motivo_no_realizada: string | null
          nota: string | null
          perfil_id: string | null
          reagendada_de: string | null
          reprogramaciones: number
          resultado_actividad_id: string | null
          resultado_reunion: string | null
          tipo: string
          titulo: string
          ubicacion_reunion: string | null
          vence_en: string
          vendedor_id: string | null
        }
        Insert: {
          activo?: boolean
          actualizado_en?: string
          asignado_supervisor_id?: string | null
          cancelada_por?: string | null
          cancelada_por_id?: string | null
          confirmada_en?: string | null
          creado_en?: string
          creado_por?: string | null
          detalle_cierre_reunion?: string | null
          duracion_min?: number | null
          enlace_reunion?: string | null
          estado?: string
          id?: string
          lead_id?: string | null
          modalidad_reunion?: string | null
          motivo_no_realizada?: string | null
          nota?: string | null
          perfil_id?: string | null
          reagendada_de?: string | null
          reprogramaciones?: number
          resultado_actividad_id?: string | null
          resultado_reunion?: string | null
          tipo: string
          titulo: string
          ubicacion_reunion?: string | null
          vence_en: string
          vendedor_id?: string | null
        }
        Update: {
          activo?: boolean
          actualizado_en?: string
          asignado_supervisor_id?: string | null
          cancelada_por?: string | null
          cancelada_por_id?: string | null
          confirmada_en?: string | null
          creado_en?: string
          creado_por?: string | null
          detalle_cierre_reunion?: string | null
          duracion_min?: number | null
          enlace_reunion?: string | null
          estado?: string
          id?: string
          lead_id?: string | null
          modalidad_reunion?: string | null
          motivo_no_realizada?: string | null
          nota?: string | null
          perfil_id?: string | null
          reagendada_de?: string | null
          reprogramaciones?: number
          resultado_actividad_id?: string | null
          resultado_reunion?: string | null
          tipo?: string
          titulo?: string
          ubicacion_reunion?: string | null
          vence_en?: string
          vendedor_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tareas_asignado_supervisor_id_fkey"
            columns: ["asignado_supervisor_id"]
            isOneToOne: false
            referencedRelation: "equipo"
            referencedColumns: ["perfil_id"]
          },
          {
            foreignKeyName: "tareas_lead_id_fkey"
            columns: ["lead_id"]
            isOneToOne: false
            referencedRelation: "leads"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_reagendada_de_fkey"
            columns: ["reagendada_de"]
            isOneToOne: false
            referencedRelation: "tareas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_resultado_actividad_id_fkey"
            columns: ["resultado_actividad_id"]
            isOneToOne: false
            referencedRelation: "actividades"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_vendedor_id_fkey"
            columns: ["vendedor_id"]
            isOneToOne: false
            referencedRelation: "equipo"
            referencedColumns: ["perfil_id"]
          },
        ]
      }
      usuario_eventos: {
        Row: {
          accion: string
          actor_id: string
          creado_en: string
          detalle: Json
          id: number
          idempotencia: string
          objetivo_id: string | null
        }
        Insert: {
          accion: string
          actor_id: string
          creado_en?: string
          detalle?: Json
          id?: never
          idempotencia: string
          objetivo_id?: string | null
        }
        Update: {
          accion?: string
          actor_id?: string
          creado_en?: string
          detalle?: Json
          id?: never
          idempotencia?: string
          objetivo_id?: string | null
        }
        Relationships: []
      }
      verificaciones_lead: {
        Row: {
          creado_en: string
          dni_consultado: string | null
          id: string
          telefono_consultado: string
          veredicto: string
          verificado_por: string
        }
        Insert: {
          creado_en?: string
          dni_consultado?: string | null
          id?: string
          telefono_consultado: string
          veredicto: string
          verificado_por: string
        }
        Update: {
          creado_en?: string
          dni_consultado?: string | null
          id?: string
          telefono_consultado?: string
          veredicto?: string
          verificado_por?: string
        }
        Relationships: []
      }
    }
    Views: {
      alertas_reconocimientos_vigentes: {
        Row: {
          accion: string | null
          alerta_id: string | null
          creado_en: string | null
          hasta: string | null
          id: string | null
          miembros: string[] | null
          secuencia: number | null
          severidad: string | null
        }
        Relationships: []
      }
      clientes_basicos: {
        Row: {
          activo: boolean | null
          apellidos: string | null
          asesor_perfil_id: string | null
          correo: string | null
          creado_en: string | null
          creado_por: string | null
          dni: string | null
          id: string | null
          nombre_completo: string | null
          nombres: string | null
          telefono: string | null
          tipo_documento: string | null
        }
        Relationships: []
      }
      contratos_cartera: {
        Row: {
          asesor_perfil_id: string | null
          capital: number | null
          categoria: string | null
          cliente_id: string | null
          cliente_nombre: string | null
          creado_en: string | null
          creado_por: string | null
          estado: string | null
          fecha_cierre_comercial: string | null
          fecha_inicio: string | null
          fecha_vencimiento: string | null
          id: string | null
          modalidad: string | null
          moneda: string | null
          notas_internas: string | null
          numero_contrato: string | null
          producto_codigo: string | null
          producto_condicion_id: string | null
          producto_id: string | null
          producto_nombre: string | null
          producto_version: number | null
          producto_version_estado: string | null
          producto_version_id: string | null
          tasa_anual: number | null
          tipo_interes: string | null
        }
        Relationships: []
      }
    }
    Functions: {
      actividades_del_ambito_fn: {
        Args: never
        Returns: {
          autor_nombre: string
          creado_en: string
          detalle: string
          id: string
          lead_id: string
          tipo: string
        }[]
      }
      actualizar_borrador_producto_inversion: {
        Args: {
          p_condiciones: Json
          p_descripcion: string
          p_expected_revision: number
          p_nombre: string
          p_version_id: string
          p_vigente_desde: string
          p_vigente_hasta: string
        }
        Returns: Json
      }
      actualizar_capacidad_leads_objetivo: {
        Args: { p_analista_id: string; p_capacidad_leads_objetivo: number }
        Returns: {
          capacidad_leads_objetivo: number
          perfil_id: string
        }[]
      }
      actualizar_cliente_gerencia: {
        Args: { p_cliente_id: string; p_patch: Json }
        Returns: boolean
      }
      actualizar_cliente_gerencia_con_domicilio: {
        Args: { p_cliente_id: string; p_patch: Json }
        Returns: boolean
      }
      actualizar_contrato_con_cuenta: {
        Args: { p_contrato: Json; p_cronograma: Json; p_id: string }
        Returns: undefined
      }
      actualizar_contrato_con_cuenta_pdf_v3: {
        Args: { p_contrato: Json; p_cronograma: Json; p_id: string }
        Returns: Json
      }
      actualizar_contrato_con_cuenta_producto: {
        Args: {
          p_contrato: Json
          p_cronograma: Json
          p_id: string
          p_producto_condicion_id: string
        }
        Returns: Json
      }
      actualizar_contrato_producto: {
        Args: {
          p_contrato: Json
          p_cronograma: Json
          p_id: string
          p_producto_condicion_id: string
        }
        Returns: Json
      }
      actualizar_jerarquia_usuario_fn: {
        Args: {
          p_idempotencia: string
          p_perfil_id: string
          p_supervisor_id: string
          p_version_equipo: string
        }
        Returns: Json
      }
      actualizar_numero_contrato_pdf_v3: {
        Args: {
          p_categoria?: string
          p_id: string
          p_notas?: string
          p_numero: string
        }
        Returns: Json
      }
      actualizar_usuario_administrable_fn: {
        Args: {
          p_cargo: string
          p_documento: string
          p_idempotencia: string
          p_nombre_completo: string
          p_perfil_id: string
          p_telefono: string
          p_tipo_documento: string
          p_version_perfil: string
          p_whatsapp: string
        }
        Returns: Json
      }
      agenda_ics_feed_fn: {
        Args: { p_desde: string; p_token: string }
        Returns: Json
      }
      agenda_reparto_diaria: {
        Args: { p_desde?: string; p_dias?: number }
        Returns: Json
      }
      altas_nuevas_por_analista_fn: {
        Args: { p_meses?: number }
        Returns: {
          altas: number
          analista_id: string
          analista_nombre: string
          mes: string
        }[]
      }
      anular_cierre_avance: {
        Args: { p_lead_id: string; p_motivo: string }
        Returns: Json
      }
      anular_cierre_externo: {
        Args: { p_cierre_id: string; p_motivo: string }
        Returns: Json
      }
      archivar_producto_inversion: {
        Args: { p_expected_revision: number; p_producto_id: string }
        Returns: Json
      }
      asignar_rol_usuario_fn: {
        Args: {
          p_idempotencia: string
          p_perfil_id: string
          p_rol_crm: string
          p_version_equipo: string
        }
        Returns: Json
      }
      atribucion_contrato_fn: { Args: { p_contrato_id: string }; Returns: Json }
      ayuda_vendedor_inicio: { Args: { p_vista: string }; Returns: Json }
      buscar_candidato_por_correo_fn: {
        Args: { p_correo: string }
        Returns: string
      }
      cartera_pagina_fn: {
        Args: {
          p_antes_de?: string
          p_antes_id?: string
          p_etapa?: string
          p_limite?: number
          p_sin_asignar?: boolean
          p_texto?: string
          p_vendedor_id?: string
        }
        Returns: {
          activo: boolean
          actualizado_en: string
          asignado_supervisor_id: string
          categoria_interes: string
          contrato_id: string
          convertido_en: string
          correo: string
          creado_en: string
          distrito: string
          dni: string
          etapa: string
          fecha_nacimiento: string
          genero: string
          id: string
          moneda: string
          monto_estimado: number
          motivo_descarte: string
          no_contactar: boolean
          nombre_completo: string
          nota: string
          origen: string
          telefono: string
          telefono_alternativo: string
          telefono_alternativo_crudo: string
          tenencia_desde: string
          ultimo_contacto_en: string
          vendedor_id: string
        }[]
      }
      cerrar_altas_legacy_productos: {
        Args: { p_expected_revision: number }
        Returns: Json
      }
      cerrar_periodo: { Args: { p_periodo: string }; Returns: Json }
      cerrar_reunion: {
        Args: {
          p_detalle?: string
          p_estado: string
          p_motivo_no_realizada?: string
          p_resultado_reunion?: string
          p_siguiente?: Json
          p_tarea_id: string
        }
        Returns: Json
      }
      cerrar_tarea: {
        Args: {
          p_estado: string
          p_motivo_no_realizada?: string
          p_resultado_detalle?: string
          p_resultado_reunion?: string
          p_resultado_tipo?: string
          p_siguiente?: Json
          p_tarea_id: string
        }
        Returns: Json
      }
      ciclo_cierre_mes: { Args: never; Returns: Json }
      cierre_mes_estado_fn: { Args: never; Returns: Json }
      cierres_estado_fn: { Args: { p_lead_ids: string[] }; Returns: Json }
      cierres_externos_fn: { Args: { p_periodo: string }; Returns: Json }
      cliente_detalle_fn: {
        Args: { p_cliente_id: string }
        Returns: {
          apellidos: string
          asesor_perfil_id: string
          banca_visible: boolean
          banco: string
          banco_usd: string
          beneficiario_dni: string
          beneficiario_dni_usd: string
          beneficiario_nombre: string
          beneficiario_nombre_usd: string
          cci: string
          cci_usd: string
          correo: string
          creado_en: string
          creado_por: string
          cuentas_bancarias_visibles: boolean
          dni: string
          domicilio: string
          id: string
          nombre_completo: string
          nombres: string
          numero_cuenta: string
          numero_cuenta_usd: string
          telefono: string
          tipo_cuenta: string
          tipo_cuenta_usd: string
          tipo_documento: string
          titular_distinto: boolean
          titular_distinto_usd: boolean
        }[]
      }
      cliente_ficha_fn: {
        Args: { p_cliente_id: string }
        Returns: {
          activo: boolean
          apellidos: string
          asesor_perfil_id: string
          correo: string
          creado_en: string
          dni: string
          id: string
          nombre_completo: string
          nombres: string
          telefono: string
          tipo_documento: string
        }[]
      }
      clientes_basicos_fn: {
        Args: never
        Returns: {
          activo: boolean
          apellidos: string
          asesor_perfil_id: string
          correo: string
          creado_en: string
          creado_por: string
          dni: string
          id: string
          nombre_completo: string
          nombres: string
          telefono: string
          tipo_documento: string
        }[]
      }
      cola_accion_fn: { Args: { p_limite?: number }; Returns: Json }
      completar_domicilio_cliente: {
        Args: { p_cliente_id: string; p_domicilio: string }
        Returns: Json
      }
      configuracion_metas_fn: { Args: { p_periodo: string }; Returns: Json }
      configuracion_sla_fn: { Args: never; Returns: Json }
      consultar_ayuda_vendedor: {
        Args: { p_consulta: string; p_vista: string }
        Returns: Json
      }
      contrato_eliminacion_finalizar: {
        Args: { p_actor_id: string; p_contrato_id: string; p_token: string }
        Returns: Json
      }
      contrato_eliminacion_preparar: {
        Args: { p_actor_id: string; p_contrato_id: string }
        Returns: Json
      }
      contrato_pdf_archivo_fn: {
        Args: { p_contrato_id: string }
        Returns: Json
      }
      contrato_pdf_estado_fn: { Args: { p_contrato_id: string }; Returns: Json }
      contrato_pdf_finalizar: {
        Args: { p_actor_id: string; p_job_id: string; p_lease_token: string }
        Returns: Json
      }
      contrato_pdf_marcar_error: {
        Args: {
          p_actor_id: string
          p_error_codigo: string
          p_job_id: string
          p_lease_token: string
        }
        Returns: Json
      }
      contrato_pdf_marcar_subido: {
        Args: {
          p_actor_id: string
          p_bytes: number
          p_job_id: string
          p_lease_token: string
          p_sha256: string
        }
        Returns: Json
      }
      contrato_pdf_reclamar: {
        Args: {
          p_actor_id: string
          p_contrato_id: string
          p_lease_segundos?: number
        }
        Returns: Json
      }
      contrato_pdf_reservar: {
        Args: { p_actor_id: string; p_contrato_id: string }
        Returns: Json
      }
      contrato_pdf_snapshot_v2: {
        Args: { p_contrato_id: string }
        Returns: Json
      }
      contratos_cartera_fn: {
        Args: never
        Returns: {
          asesor_perfil_id: string
          capital: number
          categoria: string
          cliente_id: string
          cliente_nombre: string
          creado_en: string
          creado_por: string
          estado: string
          fecha_inicio: string
          fecha_vencimiento: string
          id: string
          modalidad: string
          moneda: string
          notas_internas: string
          numero_contrato: string
          producto_codigo: string
          producto_condicion_id: string
          producto_id: string
          producto_nombre: string
          producto_version: number
          producto_version_estado: string
          producto_version_id: string
          tasa_anual: number
          tipo_interes: string
        }[]
      }
      contratos_cartera_v2_fn: {
        Args: never
        Returns: {
          asesor_perfil_id: string
          capital: number
          categoria: string
          cliente_id: string
          cliente_nombre: string
          creado_en: string
          creado_por: string
          estado: string
          fecha_cierre_comercial: string
          fecha_inicio: string
          fecha_vencimiento: string
          id: string
          modalidad: string
          moneda: string
          notas_internas: string
          numero_contrato: string
          producto_codigo: string
          producto_condicion_id: string
          producto_id: string
          producto_nombre: string
          producto_version: number
          producto_version_estado: string
          producto_version_id: string
          tasa_anual: number
          tipo_interes: string
        }[]
      }
      contratos_por_periodo_comercial_fn: {
        Args: { p_periodo: string }
        Returns: Json
      }
      conversion_mensual_fn: { Args: { p_periodo: string }; Returns: Json }
      conversion_mensual_sin_cartera_fn: {
        Args: { p_periodo: string }
        Returns: Json
      }
      convertir_lead: {
        Args: { p_lead_id: string; p_perfil_id: string }
        Returns: Json
      }
      convertir_lead_con_domicilio: {
        Args: { p_domicilio: string; p_lead_id: string; p_perfil_id: string }
        Returns: Json
      }
      convertir_lead_externo: {
        Args: {
          p_cooperativa: string
          p_documento: string
          p_documento_tipo: string
          p_lead_id: string
          p_moneda: string
          p_monto: number
          p_nombre: string
          p_nota?: string
          p_numero_transaccion: string
          p_referencia?: string
          p_vence_en?: string
        }
        Returns: Json
      }
      corregir_cierre_externo: {
        Args: {
          p_cierre_id: string
          p_cooperativa: string
          p_moneda: string
          p_monto: number
          p_nota: string
          p_numero_transaccion: string
          p_referencia: string
          p_vence_en: string
        }
        Returns: Json
      }
      corregir_fecha_cierre_comercial: {
        Args: { p_contrato_id: string; p_fecha: string; p_motivo: string }
        Returns: Json
      }
      crear_contrato_con_cuenta: {
        Args: { p_contrato: Json; p_cronograma: Json; p_cuenta: Json }
        Returns: Json
      }
      crear_contrato_con_cuenta_pdf_v2: {
        Args: { p_contrato: Json; p_cronograma: Json; p_cuenta: Json }
        Returns: Json
      }
      crear_contrato_con_cuenta_producto: {
        Args: {
          p_contrato: Json
          p_cronograma: Json
          p_cuenta: Json
          p_producto_condicion_id: string
        }
        Returns: Json
      }
      crear_contrato_producto: {
        Args: {
          p_contrato: Json
          p_cronograma: Json
          p_producto_condicion_id: string
        }
        Returns: Json
      }
      crear_lead_si_disponible: {
        Args: {
          p_categoria_interes?: string
          p_correo?: string
          p_distrito?: string
          p_dni?: string
          p_etapa?: string
          p_fecha_nacimiento?: string
          p_genero?: string
          p_id?: string
          p_moneda: string
          p_monto_estimado: number
          p_nombre_completo: string
          p_nota?: string
          p_origen: string
          p_telefono: string
          p_telefono_alternativo?: string
          p_vendedor_id?: string
        }
        Returns: Json
      }
      crear_producto_inversion: {
        Args: {
          p_codigo: string
          p_condiciones: Json
          p_descripcion: string
          p_nombre: string
          p_vigente_desde: string
          p_vigente_hasta: string
        }
        Returns: Json
      }
      crear_version_producto_inversion: {
        Args: {
          p_condiciones: Json
          p_descripcion: string
          p_expected_revision: number
          p_nombre: string
          p_producto_id: string
          p_vigente_desde: string
          p_vigente_hasta: string
        }
        Returns: Json
      }
      cronograma_contrato_fn: {
        Args: { p_contrato_id: string }
        Returns: {
          estado: string
          fecha_pago_real: string
          fecha_programada: string
          id: string
          monto_pagado: number
          monto_programado: number
          numero_cuota: number
          tipo: string
        }[]
      }
      cuentas_bancarias_cliente_fn: {
        Args: { p_cliente_id: string; p_moneda: string }
        Returns: {
          banco: string
          beneficiario_dni: string
          beneficiario_nombre: string
          cci: string
          creada_en: string
          cuenta_id: string
          es_cuenta_perfil: boolean
          moneda: string
          numero_cuenta: string
          origen: string
          tipo_cuenta: string
          titular_distinto: boolean
        }[]
      }
      cuentas_pago_contratos_fn: {
        Args: { p_contrato_ids: string[] }
        Returns: {
          banco: string
          beneficiario_dni: string
          beneficiario_nombre: string
          cci: string
          contrato_id: string
          cuenta_bancaria_id: string
          moneda: string
          numero_cuenta: string
          tipo_cuenta: string
          titular_distinto: boolean
        }[]
      }
      cumplimiento_metas_fn: { Args: { p_periodo: string }; Returns: Json }
      cumplimiento_metas_sin_cartera_fn: {
        Args: { p_periodo: string }
        Returns: Json
      }
      datos_legales_contrato_fn: {
        Args: { p_cliente_id: string }
        Returns: Json
      }
      derivar_leads_equipo_fn: {
        Args: { p_asesor_ids: string[]; p_lead_ids: string[] }
        Returns: Json
      }
      descartar_lead: {
        Args: { p_lead: string; p_motivo: string; p_nota?: string }
        Returns: Json
      }
      deshacer_descarte: { Args: { p_lead: string }; Returns: Json }
      destinos_importacion_por_correo_fn: {
        Args: { p_correos: string[] }
        Returns: {
          correo: string
          perfil_id: string
        }[]
      }
      equipo_visible_fn: {
        Args: never
        Returns: {
          activo: boolean
          nombre_completo: string
          perfil_id: string
          rol_crm: string
          supervisor_id: string
        }[]
      }
      estado_sla_leads_fn: {
        Args: never
        Returns: {
          asignacion_id: string
          asignacion_politica_id: string
          asignacion_politica_version: number
          asignacion_primer_contacto_en: string
          asignacion_primer_contacto_limite_en: string
          asignacion_primera_gestion_en: string
          asignacion_primera_gestion_limite_en: string
          ciclo_aproximado: boolean
          ciclo_politica_id: string
          ciclo_politica_version: number
          etapa: string
          etapa_aproximada: boolean
          etapa_iniciada_en: string
          etapa_limite_en: string
          etapa_objetivo_minutos: number
          etapa_politica_id: string
          etapa_politica_version: number
          lead_id: string
          primer_contacto_en: string
          primer_contacto_limite_en: string
          primera_gestion_en: string
          primera_gestion_limite_en: string
        }[]
      }
      existe_cliente_por_dni: { Args: { p_dni: string }; Returns: boolean }
      fijar_membresia_activa_fn: {
        Args: {
          p_activo: boolean
          p_idempotencia: string
          p_perfil_id: string
          p_reemplazo_id: string
          p_version_equipo: string
        }
        Returns: Json
      }
      guardar_agenda_reparto_diaria: {
        Args: { p_fecha: string; p_formulario: string; p_landing: string }
        Returns: Json
      }
      historial_derivaciones: {
        Args: {
          p_actividad_antes?: string
          p_derivado_antes?: string
          p_limite?: number
        }
        Returns: {
          actividad_id: string
          derivado_en: string
          derivado_por_nombre: string
          distrito: string
          etapa_actual: string
          lead_id: string
          moneda: string
          monto_estimado: number
          movimiento: string
          nombre_completo: string
          origen: string
          responsable_anterior: string
          responsable_nuevo: string
        }[]
      }
      impacto_desactivacion_usuario_fn: {
        Args: { p_perfil_id: string }
        Returns: Json
      }
      ingresos_reparto_mes_fn: { Args: { p_mes: string }; Returns: Json }
      leads_descartados: {
        Args: never
        Returns: {
          categoria_interes: string
          clasificacion_auto: string
          comentario: string
          creado_en: string
          descartado_en: string
          descartado_por_nombre: string
          distrito: string
          es_mio: boolean
          id: string
          moneda: string
          monto_estimado: number
          motivo_descarte: string
          nombre_completo: string
          nota_descarte: string
          origen: string
          puede_deshacer: boolean
        }[]
      }
      leads_por_repartir: {
        Args: never
        Returns: {
          categoria_interes: string
          clasificacion_auto: string
          comentario: string
          creado_en: string
          distrito: string
          id: string
          moneda: string
          monto_estimado: number
          nombre_completo: string
          origen: string
        }[]
      }
      marcar_efectos_conversion: { Args: { p_lead_id: string }; Returns: Json }
      metricas_agenda_fn: {
        Args: { p_desde: string; p_hasta: string }
        Returns: Json
      }
      metricas_altas_analista_fn: {
        Args: { p_meses?: number }
        Returns: {
          altas: number
          analista_id: string
          analista_nombre: string
          mes: string
        }[]
      }
      metricas_capital_mes_fn: {
        Args: { p_meses?: number }
        Returns: {
          capital_colocado: number
          categoria: string
          contratos: number
          mes: string
          moneda: string
        }[]
      }
      metricas_cartera_fn: { Args: { p_periodo: string }; Returns: Json }
      metricas_conversiones_equipo_fn: {
        Args: { p_desde: string; p_hasta: string }
        Returns: Json
      }
      metricas_conversiones_fn: {
        Args: { p_desde: string; p_hasta: string; p_origen?: string }
        Returns: Json
      }
      metricas_distribucion_leads_fn: {
        Args: { p_desde: string; p_hasta: string }
        Returns: Json
      }
      metricas_distribucion_leads_v2_fn: {
        Args: { p_desde: string; p_hasta: string }
        Returns: Json
      }
      metricas_distribucion_leads_v3_fn: {
        Args: { p_desde: string; p_hasta: string }
        Returns: Json
      }
      metricas_pagos_mes_fn: {
        Args: { p_meses?: number }
        Returns: {
          cuotas: number
          estado: string
          mes: string
          moneda: string
          monto_pagado: number
          monto_programado: number
          tipo: string
        }[]
      }
      metricas_reuniones_fn: {
        Args: { p_desde: string; p_hasta: string }
        Returns: Json
      }
      metricas_sla_fn: {
        Args: { p_desde: string; p_hasta: string }
        Returns: Json
      }
      metricas_vencimientos_fn: {
        Args: { p_dias?: number }
        Returns: {
          capital_por_vencer: number
          contratos_por_vencer: number
          mes: string
          moneda: string
        }[]
      }
      metricas_vendedores_fn: { Args: never; Returns: Json }
      mi_acceso_fn: { Args: never; Returns: Json }
      normalizar_domicilio_legal: {
        Args: { p_domicilio: string }
        Returns: string
      }
      panel_distribucion_reparto: {
        Args: {
          p_analista?: string
          p_origen?: string
          p_solo_activos?: boolean
          p_supervisor?: string
        }
        Returns: Json
      }
      productos_inversion_gestion_fn: { Args: never; Returns: Json }
      productos_inversion_seleccion_fn: {
        Args: never
        Returns: {
          capital_maximo: number
          capital_minimo: number
          categoria: string
          condicion_id: string
          modalidad: string
          moneda: string
          numero_version: number
          plazo_meses: number
          producto_codigo: string
          producto_id: string
          producto_revision: number
          tasa_maxima: number
          tasa_minima: number
          tasa_referencia: number
          tipo_interes: string
          version_id: string
          version_nombre: string
          vigente_desde: string
          vigente_hasta: string
        }[]
      }
      publicar_metas_vendedores: {
        Args: { p_expected_revision: number; p_metas: Json; p_periodo: string }
        Returns: {
          id: string
          periodo: string
          publicada_en: string
          publicada_por: string
          revision: number
          revision_anterior_id: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "meta_periodos"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      publicar_politica_sla: {
        Args: {
          p_config: Json
          p_expected_version: number
          p_vigente_desde: string
        }
        Returns: {
          id: string
          primer_contacto_minutos: number
          primera_gestion_minutos: number
          publicada_en: string
          publicada_por: string | null
          tipo_reloj: string
          version: number
          version_anterior_id: string | null
          vigente_desde: string
          zona_horaria: string
        }[]
        SetofOptions: {
          from: "*"
          to: "sla_politicas"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      publicar_version_producto_inversion: {
        Args: { p_expected_revision: number; p_version_id: string }
        Returns: Json
      }
      purgar_membresia_crm: {
        Args: { p_motivo: string; p_perfil_id: string }
        Returns: undefined
      }
      registrar_candidato_usuario_fn: {
        Args: {
          p_cargo: string
          p_correo: string
          p_documento: string
          p_idempotencia: string
          p_nombre_completo: string
          p_perfil_id: string
          p_telefono: string
          p_tipo_documento: string
          p_whatsapp: string
        }
        Returns: Json
      }
      registrar_vendedor_usuario_fn: {
        Args: {
          p_cargo: string
          p_correo: string
          p_documento: string
          p_idempotencia: string
          p_nombre_completo: string
          p_perfil_id: string
          p_supervisor_id: string
          p_telefono: string
          p_tipo_documento: string
          p_whatsapp: string
        }
        Returns: Json
      }
      repartir_lead: {
        Args: { p_lead: string; p_supervisor: string }
        Returns: Json
      }
      reporte_derivaciones_coordinacion_fn: {
        Args: { p_desde?: string; p_hasta?: string }
        Returns: Json
      }
      reporte_derivaciones_equipo_fn: {
        Args: { p_desde?: string; p_hasta?: string }
        Returns: Json
      }
      reprogramar_reunion: {
        Args: { p_nueva_id?: string; p_tarea_id: string; p_vence_en: string }
        Returns: Json
      }
      rescatar_descartes: {
        Args: {
          p_analistas_destino: string[]
          p_episodios: string[]
          p_evitar_asesor_origen?: boolean
        }
        Returns: Json
      }
      rescate_descartes_mes: {
        Args: { p_mes: string }
        Returns: {
          asesor_id: string
          asesor_nombre: string
          categoria_interes: string
          descartado_en: string
          distrito: string
          episodio_id: string
          estado: string
          lead_id: string
          moneda: string
          monto_estimado: number
          motivo_descarte: string
          nombre_completo: string
          origen: string
          puede_rescatar: boolean
        }[]
      }
      rescate_descartes_meses: {
        Args: never
        Returns: {
          mes: string
          pendientes: number
          total: number
        }[]
      }
      reservar_conversion_lead: { Args: { p_lead_id: string }; Returns: Json }
      resumen_cartera_clientes_fn: { Args: never; Returns: Json }
      resumen_cartera_fn: { Args: never; Returns: Json }
      resumen_reparto_fn: { Args: never; Returns: Json }
      resumen_tareas_fn: { Args: never; Returns: Json }
      revertir_derivacion_equipo_fn: {
        Args: { p_lead_id: string }
        Returns: Json
      }
      series_comerciales_fn: { Args: { p_meses?: number }; Returns: Json }
      supervisores_para_reparto: {
        Args: never
        Returns: {
          activo: boolean
          bandeja_pendiente: number
          nombre: string
          perfil_id: string
        }[]
      }
      titulares_contrato_fn: {
        Args: { p_contrato_id: string }
        Returns: {
          documento: string
          id: string
          nombre_completo: string
          orden: number
          tipo_documento: string
        }[]
      }
      tomar_lead_libre: {
        Args: { p_dni?: string; p_telefono: string }
        Returns: Json
      }
      usuarios_administrables_fn: {
        Args: { p_busqueda?: string; p_desde?: number; p_limite?: number }
        Returns: {
          activo_crm: boolean
          activo_portal: boolean
          cargo: string
          correo: string
          documento: string
          estado: string
          nombre_completo: string
          perfil_id: string
          rol_crm: string
          supervisor_id: string
          telefono: string
          tipo_cuenta: string
          tipo_documento: string
          total: number
          version_equipo: string
          version_perfil: string
          whatsapp: string
        }[]
      }
      verificar_disponibilidad_lead: {
        Args: { p_dni?: string; p_telefono: string }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      asesores: {
        Row: {
          activo: boolean | null
          actualizado_en: string | null
          cargo: string | null
          correo: string | null
          creado_en: string | null
          id: string
          nombre_completo: string
          telefono: string | null
          whatsapp: string
        }
        Insert: {
          activo?: boolean | null
          actualizado_en?: string | null
          cargo?: string | null
          correo?: string | null
          creado_en?: string | null
          id?: string
          nombre_completo: string
          telefono?: string | null
          whatsapp: string
        }
        Update: {
          activo?: boolean | null
          actualizado_en?: string | null
          cargo?: string | null
          correo?: string | null
          creado_en?: string | null
          id?: string
          nombre_completo?: string
          telefono?: string | null
          whatsapp?: string
        }
        Relationships: []
      }
      audit_log: {
        Row: {
          data_antes: Json | null
          data_despues: Json | null
          fila_id: string | null
          id: string
          operacion: string
          tabla: string
          ts: string
          usuario_id: string | null
        }
        Insert: {
          data_antes?: Json | null
          data_despues?: Json | null
          fila_id?: string | null
          id?: string
          operacion: string
          tabla: string
          ts?: string
          usuario_id?: string | null
        }
        Update: {
          data_antes?: Json | null
          data_despues?: Json | null
          fila_id?: string | null
          id?: string
          operacion?: string
          tabla?: string
          ts?: string
          usuario_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "audit_log_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "perfiles"
            referencedColumns: ["id"]
          },
        ]
      }
      contrato_titulares: {
        Row: {
          contrato_id: string
          creado_en: string
          creado_por: string | null
          documento: string
          id: string
          nombre_completo: string
          orden: number
          tipo_documento: string
        }
        Insert: {
          contrato_id: string
          creado_en?: string
          creado_por?: string | null
          documento: string
          id?: string
          nombre_completo: string
          orden?: number
          tipo_documento?: string
        }
        Update: {
          contrato_id?: string
          creado_en?: string
          creado_por?: string | null
          documento?: string
          id?: string
          nombre_completo?: string
          orden?: number
          tipo_documento?: string
        }
        Relationships: [
          {
            foreignKeyName: "contrato_titulares_contrato_id_fkey"
            columns: ["contrato_id"]
            isOneToOne: false
            referencedRelation: "contratos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contrato_titulares_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "perfiles"
            referencedColumns: ["id"]
          },
        ]
      }
      contratos: {
        Row: {
          actualizado_en: string | null
          analista_cierre_id: string | null
          aviso_venc_30d_enviado_en: string | null
          aviso_venc_7d_enviado_en: string | null
          capital: number
          categoria: string | null
          cerrado_en: string | null
          cerrado_por: string | null
          cliente_id: string
          creado_en: string | null
          creado_por: string | null
          es_demo: boolean
          estado: string
          fecha_cierre_comercial: string
          fecha_inicio: string
          fecha_vencimiento: string
          fuente_cierre_comercial: string
          id: string
          modalidad: string
          moneda: string
          notas_internas: string | null
          numero_contrato: string
          producto_condicion_id: string
          renovado_a_id: string | null
          tasa_anual: number
          tipo_interes: string
        }
        Insert: {
          actualizado_en?: string | null
          analista_cierre_id?: string | null
          aviso_venc_30d_enviado_en?: string | null
          aviso_venc_7d_enviado_en?: string | null
          capital: number
          categoria?: string | null
          cerrado_en?: string | null
          cerrado_por?: string | null
          cliente_id: string
          creado_en?: string | null
          creado_por?: string | null
          es_demo?: boolean
          estado?: string
          fecha_cierre_comercial: string
          fecha_inicio: string
          fecha_vencimiento: string
          fuente_cierre_comercial?: string
          id?: string
          modalidad: string
          moneda?: string
          notas_internas?: string | null
          numero_contrato: string
          producto_condicion_id: string
          renovado_a_id?: string | null
          tasa_anual?: number
          tipo_interes?: string
        }
        Update: {
          actualizado_en?: string | null
          analista_cierre_id?: string | null
          aviso_venc_30d_enviado_en?: string | null
          aviso_venc_7d_enviado_en?: string | null
          capital?: number
          categoria?: string | null
          cerrado_en?: string | null
          cerrado_por?: string | null
          cliente_id?: string
          creado_en?: string | null
          creado_por?: string | null
          es_demo?: boolean
          estado?: string
          fecha_cierre_comercial?: string
          fecha_inicio?: string
          fecha_vencimiento?: string
          fuente_cierre_comercial?: string
          id?: string
          modalidad?: string
          moneda?: string
          notas_internas?: string | null
          numero_contrato?: string
          producto_condicion_id?: string
          renovado_a_id?: string | null
          tasa_anual?: number
          tipo_interes?: string
        }
        Relationships: [
          {
            foreignKeyName: "contratos_cerrado_por_fkey"
            columns: ["cerrado_por"]
            isOneToOne: false
            referencedRelation: "perfiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contratos_cliente_id_fkey"
            columns: ["cliente_id"]
            isOneToOne: false
            referencedRelation: "perfiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contratos_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "perfiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contratos_renovado_a_id_fkey"
            columns: ["renovado_a_id"]
            isOneToOne: false
            referencedRelation: "contratos"
            referencedColumns: ["id"]
          },
        ]
      }
      cronograma_pagos: {
        Row: {
          contrato_id: string
          creado_en: string | null
          estado: string
          fecha_pago_real: string | null
          fecha_programada: string
          id: string
          monto_pagado: number | null
          monto_programado: number
          notif_pago_enviada_en: string | null
          numero_cuota: number
          recordatorio_3d_enviado_en: string | null
          registrado_por: string | null
          tipo: string
        }
        Insert: {
          contrato_id: string
          creado_en?: string | null
          estado?: string
          fecha_pago_real?: string | null
          fecha_programada: string
          id?: string
          monto_pagado?: number | null
          monto_programado: number
          notif_pago_enviada_en?: string | null
          numero_cuota: number
          recordatorio_3d_enviado_en?: string | null
          registrado_por?: string | null
          tipo?: string
        }
        Update: {
          contrato_id?: string
          creado_en?: string | null
          estado?: string
          fecha_pago_real?: string | null
          fecha_programada?: string
          id?: string
          monto_pagado?: number | null
          monto_programado?: number
          notif_pago_enviada_en?: string | null
          numero_cuota?: number
          recordatorio_3d_enviado_en?: string | null
          registrado_por?: string | null
          tipo?: string
        }
        Relationships: [
          {
            foreignKeyName: "cronograma_pagos_contrato_id_fkey"
            columns: ["contrato_id"]
            isOneToOne: false
            referencedRelation: "contratos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cronograma_pagos_registrado_por_fkey"
            columns: ["registrado_por"]
            isOneToOne: false
            referencedRelation: "perfiles"
            referencedColumns: ["id"]
          },
        ]
      }
      documentos: {
        Row: {
          contrato_id: string
          creado_en: string | null
          id: string
          nombre: string
          storage_path: string
          subido_por: string | null
          tipo: string
        }
        Insert: {
          contrato_id: string
          creado_en?: string | null
          id?: string
          nombre: string
          storage_path: string
          subido_por?: string | null
          tipo?: string
        }
        Update: {
          contrato_id?: string
          creado_en?: string | null
          id?: string
          nombre?: string
          storage_path?: string
          subido_por?: string | null
          tipo?: string
        }
        Relationships: [
          {
            foreignKeyName: "documentos_contrato_id_fkey"
            columns: ["contrato_id"]
            isOneToOne: false
            referencedRelation: "contratos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "documentos_subido_por_fkey"
            columns: ["subido_por"]
            isOneToOne: false
            referencedRelation: "perfiles"
            referencedColumns: ["id"]
          },
        ]
      }
      novedades: {
        Row: {
          creado_en: string | null
          destinatario_id: string | null
          enviado_por: string | null
          id: string
          imagen_url: string | null
          leido: boolean | null
          mensaje: string
          titulo: string
        }
        Insert: {
          creado_en?: string | null
          destinatario_id?: string | null
          enviado_por?: string | null
          id?: string
          imagen_url?: string | null
          leido?: boolean | null
          mensaje: string
          titulo: string
        }
        Update: {
          creado_en?: string | null
          destinatario_id?: string | null
          enviado_por?: string | null
          id?: string
          imagen_url?: string | null
          leido?: boolean | null
          mensaje?: string
          titulo?: string
        }
        Relationships: [
          {
            foreignKeyName: "novedades_destinatario_id_fkey"
            columns: ["destinatario_id"]
            isOneToOne: false
            referencedRelation: "perfiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "novedades_enviado_por_fkey"
            columns: ["enviado_por"]
            isOneToOne: false
            referencedRelation: "perfiles"
            referencedColumns: ["id"]
          },
        ]
      }
      novedades_leidas: {
        Row: {
          id: string
          leido_en: string | null
          novedad_id: string
          usuario_id: string
        }
        Insert: {
          id?: string
          leido_en?: string | null
          novedad_id: string
          usuario_id: string
        }
        Update: {
          id?: string
          leido_en?: string | null
          novedad_id?: string
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "novedades_leidas_novedad_id_fkey"
            columns: ["novedad_id"]
            isOneToOne: false
            referencedRelation: "novedades"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "novedades_leidas_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "perfiles"
            referencedColumns: ["id"]
          },
        ]
      }
      perfiles: {
        Row: {
          activo: boolean | null
          actualizado_en: string | null
          apellidos: string | null
          asesor_id: string | null
          asesor_perfil_id: string | null
          banco: string | null
          banco_usd: string | null
          beneficiario_dni: string | null
          beneficiario_dni_usd: string | null
          beneficiario_nombre: string | null
          beneficiario_nombre_usd: string | null
          cargo: string | null
          cci: string | null
          cci_usd: string | null
          correo: string | null
          creado_en: string | null
          creado_por: string | null
          debe_cambiar_password: boolean
          dni: string | null
          domicilio: string | null
          id: string
          nombre_completo: string
          nombres: string | null
          numero_cuenta: string | null
          numero_cuenta_usd: string | null
          pwa_instalada_at: string | null
          rol: string
          telefono: string | null
          tipo_cuenta: string | null
          tipo_cuenta_usd: string | null
          tipo_documento: string
          titular_distinto: boolean
          titular_distinto_usd: boolean
          whatsapp: string | null
        }
        Insert: {
          activo?: boolean | null
          actualizado_en?: string | null
          apellidos?: string | null
          asesor_id?: string | null
          asesor_perfil_id?: string | null
          banco?: string | null
          banco_usd?: string | null
          beneficiario_dni?: string | null
          beneficiario_dni_usd?: string | null
          beneficiario_nombre?: string | null
          beneficiario_nombre_usd?: string | null
          cargo?: string | null
          cci?: string | null
          cci_usd?: string | null
          correo?: string | null
          creado_en?: string | null
          creado_por?: string | null
          debe_cambiar_password?: boolean
          dni?: string | null
          domicilio?: string | null
          id: string
          nombre_completo: string
          nombres?: string | null
          numero_cuenta?: string | null
          numero_cuenta_usd?: string | null
          pwa_instalada_at?: string | null
          rol?: string
          telefono?: string | null
          tipo_cuenta?: string | null
          tipo_cuenta_usd?: string | null
          tipo_documento?: string
          titular_distinto?: boolean
          titular_distinto_usd?: boolean
          whatsapp?: string | null
        }
        Update: {
          activo?: boolean | null
          actualizado_en?: string | null
          apellidos?: string | null
          asesor_id?: string | null
          asesor_perfil_id?: string | null
          banco?: string | null
          banco_usd?: string | null
          beneficiario_dni?: string | null
          beneficiario_dni_usd?: string | null
          beneficiario_nombre?: string | null
          beneficiario_nombre_usd?: string | null
          cargo?: string | null
          cci?: string | null
          cci_usd?: string | null
          correo?: string | null
          creado_en?: string | null
          creado_por?: string | null
          debe_cambiar_password?: boolean
          dni?: string | null
          domicilio?: string | null
          id?: string
          nombre_completo?: string
          nombres?: string | null
          numero_cuenta?: string | null
          numero_cuenta_usd?: string | null
          pwa_instalada_at?: string | null
          rol?: string
          telefono?: string | null
          tipo_cuenta?: string | null
          tipo_cuenta_usd?: string | null
          tipo_documento?: string
          titular_distinto?: boolean
          titular_distinto_usd?: boolean
          whatsapp?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "perfiles_asesor_id_fkey"
            columns: ["asesor_id"]
            isOneToOne: false
            referencedRelation: "asesores"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "perfiles_asesor_perfil_id_fkey"
            columns: ["asesor_perfil_id"]
            isOneToOne: false
            referencedRelation: "perfiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "perfiles_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "perfiles"
            referencedColumns: ["id"]
          },
        ]
      }
      suscripciones_push: {
        Row: {
          activo: boolean
          actualizado_en: string
          auth: string
          cliente_id: string
          creado_en: string
          dispositivo: string | null
          endpoint: string
          id: string
          p256dh: string
          user_agent: string | null
        }
        Insert: {
          activo?: boolean
          actualizado_en?: string
          auth: string
          cliente_id: string
          creado_en?: string
          dispositivo?: string | null
          endpoint: string
          id?: string
          p256dh: string
          user_agent?: string | null
        }
        Update: {
          activo?: boolean
          actualizado_en?: string
          auth?: string
          cliente_id?: string
          creado_en?: string
          dispositivo?: string | null
          endpoint?: string
          id?: string
          p256dh?: string
          user_agent?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "suscripciones_push_cliente_id_fkey"
            columns: ["cliente_id"]
            isOneToOne: false
            referencedRelation: "perfiles"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      _sync_contrato_titulares: {
        Args: { p_contrato_id: string; p_titulares: Json }
        Returns: undefined
      }
      actualizar_contrato: {
        Args: { p_contrato: Json; p_cronograma: Json; p_id: string }
        Returns: Json
      }
      actualizar_contrato_con_cuenta_producto: {
        Args: {
          p_contrato: Json
          p_cronograma: Json
          p_id: string
          p_producto_condicion_id: string
        }
        Returns: Json
      }
      actualizar_contrato_producto: {
        Args: {
          p_contrato: Json
          p_cronograma: Json
          p_id: string
          p_producto_condicion_id: string
        }
        Returns: Json
      }
      actualizar_numero_contrato: {
        Args: {
          p_categoria?: string
          p_id: string
          p_notas?: string
          p_numero: string
        }
        Returns: Json
      }
      admin_pagos_metricas: { Args: never; Returns: Json }
      admin_pagos_resumen: { Args: never; Returns: Json }
      bandeja_actividad: {
        Args: { p_limit?: number; p_offset?: number }
        Returns: {
          actor_id: string
          actor_nombre: string
          data_antes: Json
          data_despues: Json
          id: string
          operacion: string
          tabla: string
          target_label: string
          ts: string
        }[]
      }
      cerrar_contrato: {
        Args: {
          p_contrato_nuevo_id?: string
          p_id: string
          p_resultado: string
        }
        Returns: Json
      }
      contrato_tiene_pagos: {
        Args: { p_contrato_id: string }
        Returns: boolean
      }
      crear_contrato: {
        Args: { p_contrato: Json; p_cronograma: Json }
        Returns: Json
      }
      crear_contrato_producto: {
        Args: {
          p_contrato: Json
          p_cronograma: Json
          p_producto_condicion_id: string
        }
        Returns: Json
      }
      dashboard_admin_metricas: { Args: never; Returns: Json }
      directorio_morosidad: {
        Args: never
        Returns: {
          cliente: string
          dias_vencida: number
          fecha_programada: string
          moneda: string
          monto: number
          numero_contrato: string
          numero_cuota: number
        }[]
      }
      directorio_ranking_analistas: {
        Args: never
        Returns: {
          analista_id: string
          capital_pen: number
          capital_usd: number
          n_clientes: number
          n_contratos: number
          nombre: string
        }[]
      }
      directorio_top_clientes: {
        Args: never
        Returns: {
          capital_pen: number
          capital_usd: number
          cliente_id: string
          nombre: string
        }[]
      }
      es_admin: { Args: never; Returns: boolean }
      es_analista: { Args: never; Returns: boolean }
      es_directorio: { Args: never; Returns: boolean }
      es_gestor_cartera: { Args: never; Returns: boolean }
      es_operaciones: { Args: never; Returns: boolean }
      es_superadmin: { Args: never; Returns: boolean }
      marcar_contrato_demo: {
        Args: { p_contrato_id: string; p_es_demo: boolean; p_motivo: string }
        Returns: Json
      }
      marcar_contratos_vencidos: {
        Args: never
        Returns: {
          cliente_id: string
          id: string
        }[]
      }
      metricas_directorio: { Args: never; Returns: Json }
      mi_rol: { Args: never; Returns: string }
      obtener_mi_asesor: {
        Args: never
        Returns: {
          cargo: string
          correo: string
          nombre_completo: string
          telefono: string
          whatsapp: string
        }[]
      }
      pagos_admin_metricas_globales: { Args: never; Returns: Json }
      pagos_admin_resumen_contratos: {
        Args: {
          p_busqueda?: string
          p_limit?: number
          p_moneda?: string
          p_offset?: number
          p_tab?: string
        }
        Returns: {
          adeudado: number
          capital: number
          cliente_nombre: string
          completo: boolean
          contrato_id: string
          estado_contrato: string
          moneda: string
          numero_contrato: string
          pagadas: number
          pagado_total: number
          pendientes: number
          proxima_cuota_id: string
          proxima_estado_real: string
          proxima_fecha: string
          proxima_monto: number
          proxima_numero: number
          proxima_tipo: string
          total_count: number
          total_cuotas: number
          vencidas: number
        }[]
      }
      productos_inversion_seleccion_fn: {
        Args: { p_contrato_id?: string }
        Returns: {
          capital_maximo: number
          capital_minimo: number
          categoria: string
          condicion_id: string
          es_actual: boolean
          es_legacy: boolean
          modalidad: string
          moneda: string
          numero_version: number
          plazo_meses: number
          producto_codigo: string
          producto_id: string
          producto_revision: number
          seleccionable_nuevo: boolean
          tasa_maxima: number
          tasa_minima: number
          tasa_referencia: number
          tipo_interes: string
          version_estado: string
          version_id: string
          version_nombre: string
          vigente_desde: string
          vigente_hasta: string
        }[]
      }
      puede_ver_contrato: { Args: { p_contrato_id: string }; Returns: boolean }
      reasignar_analista_contrato: {
        Args: { p_analista_id: string; p_contrato_id: string; p_motivo: string }
        Returns: Json
      }
      verificar_cron_secret: { Args: { p_secret: string }; Returns: boolean }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  crm: {
    Enums: {},
  },
  public: {
    Enums: {},
  },
} as const
