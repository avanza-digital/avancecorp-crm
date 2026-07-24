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
type OrigenDb =
  | 'referido'
  | 'landing'
  | 'formulario'
  | 'oficina'
  | 'otro'
  | 'web'
  | 'campania'
  | 'whatsapp'
type MotivoDescarteDb = 'sin_interes' | 'sin_fondos' | 'competencia' | 'no_responde' | 'datos_invalidos' | 'pide_credito' | 'otro'
// C1-bis: veredicto del clasificador de crédito (trigger en el INSERT, inmutable).
type ClasificacionAutoDb = 'posible_credito'
type MonedaDb = 'PEN' | 'USD'
// CHECK leads_genero_valido: binario (sexo del documento), nullable.
type GeneroDb = 'F' | 'M'
type CategoriaInteresDb = 'nuevo' | 'renovacion' | 'upgrade'
// CHECKs de crm.tareas (20260718180001).
type TipoTareaDb = 'llamada' | 'whatsapp' | 'reunion' | 'tarea'
type EstadoTareaDb = 'pendiente' | 'completada' | 'cancelada' | 'no_show'
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
          capacidad_leads_objetivo: number | null
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
          genero: GeneroDb | null
          fecha_nacimiento: string | null // date ISO 'YYYY-MM-DD' (sin hora)
          // Capa legal (20260718180001): "No Insista" + registro de consentimiento.
          no_contactar: boolean
          consentimiento_en: string | null
          consentimiento_fuente: string | null
          distrito: string | null
          origen: OrigenDb
          etapa: EtapaDb
          motivo_descarte: MotivoDescarteDb | null
          monto_estimado: number // numeric + CHECK de rango/2 decimales; PostgREST puede serializar string
          moneda: MonedaDb
          categoria_interes: CategoriaInteresDb | null
          vendedor_id: string | null
          asignado_supervisor_id: string | null
          perfil_id: string | null
          contrato_id: string | null
          convertido_en: string | null
          nota: string | null
          // C1-bis (20260723120000): marca del clasificador + sello del descarte.
          // Las tres las gobierna el trigger zz_sello_descarte: lo que mande el
          // cliente API se ignora (por eso no aparecen en Insert/Update).
          clasificacion_auto: ClasificacionAutoDb | null
          descartado_en: string | null
          descartado_por: string | null
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
          genero?: GeneroDb | null
          fecha_nacimiento?: string | null
          no_contactar?: boolean
          consentimiento_en?: string | null
          consentimiento_fuente?: string | null
          distrito?: string | null
          origen?: OrigenDb
          etapa?: EtapaDb
          motivo_descarte?: MotivoDescarteDb | null
          monto_estimado: number
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
          genero?: GeneroDb | null
          fecha_nacimiento?: string | null
          no_contactar?: boolean
          consentimiento_en?: string | null
          consentimiento_fuente?: string | null
          distrito?: string | null
          origen?: OrigenDb
          etapa?: EtapaDb
          motivo_descarte?: MotivoDescarteDb | null
          monto_estimado?: number
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
      /** Agenda comercial (20260718180001): FUTURO mutable. "Vencida" se DERIVA
       *  (pendiente + vence_en < now). La tenencia la fija el trigger desde el
       *  lead (el payload no manda). Completar/no_show van SOLO por la RPC
       *  cerrar_tarea; el UPDATE directo solo cancela o reprograma. */
      tareas: {
        Row: {
          id: string
          lead_id: string | null
          perfil_id: string | null
          vendedor_id: string | null
          asignado_supervisor_id: string | null
          tipo: TipoTareaDb
          titulo: string
          nota: string | null
          vence_en: string
          duracion_min: number | null
          estado: EstadoTareaDb
          resultado_actividad_id: string | null
          reagendada_de: string | null
          confirmada_en: string | null
          reprogramaciones: number
          activo: boolean
          creado_por: string | null
          creado_en: string
          actualizado_en: string
        }
        Insert: {
          id?: string
          lead_id?: string | null
          perfil_id?: string | null
          tipo: TipoTareaDb
          titulo: string
          nota?: string | null
          vence_en: string
          duracion_min?: number | null
          creado_por?: string | null
        }
        Update: {
          titulo?: string
          nota?: string | null
          vence_en?: string // reprogramar: el trigger incrementa reprogramaciones
          duracion_min?: number | null
          estado?: EstadoTareaDb // solo 'cancelada' pasa el trigger sin la RPC
          confirmada_en?: string | null
          activo?: boolean
        }
        Relationships: []
      }
      /** Suscripción ICS (20260718120243): token secreto por miembro para el
       *  feed de su agenda (edge crm-agenda-ics). RLS: SOLO la fila propia —
       *  un token ajeno permitiría espiar la agenda de otro fuera del CRM.
       *  Rotar el token invalida el enlace anterior; sin DELETE. */
      agenda_ics: {
        Row: {
          perfil_id: string
          token: string
          creado_en: string
          rotado_en: string | null
        }
        Insert: {
          perfil_id: string
          token?: string
        }
        Update: {
          token?: string
          rotado_en?: string | null
        }
        Relationships: []
      }
      /** Metas comerciales del mes (20260719120000): UNA fila por (mes, rol);
       *  capital SIEMPRE en PEN. Lectura por RLS (árbol comercial + lector
       *  global); escritura SOLO por la RPC fijar_objetivos (gerencia). */
      objetivos: {
        Row: {
          id: string
          periodo: string
          rol: 'vendedor' | 'supervisor' | 'gerencia'
          capital_objetivo: number | string
          ventas_objetivo: number
          conversion_objetivo: number | string
          actualizado_por: string | null
          creado_en: string
          actualizado_en: string
        }
        Insert: never // escritura solo vía RPC fijar_objetivos
        Update: never
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
          /** text — el CHECK vive en public.perfiles ('DNI'|'CE'|'PASAPORTE'). */
          tipo_documento: string
          dni: string | null
          correo: string | null
          telefono: string | null
          asesor_perfil_id: string | null
          /** Con asesor_perfil_id NULL, el creador es el dueño de cartera (regla del servidor). */
          creado_por: string | null
          activo: boolean
          creado_en: string
        }
        Relationships: []
      }
      /** Contratos con nombre del cliente, YA scopeados por rol del CRM
       *  (gerencia=todo, supervisor=subárbol, vendedor=su cartera). Molde de
       *  clientes_basicos: la RLS directa de public.contratos no cubre a la
       *  supervisión. */
      contratos_cartera: {
        Row: {
          id: string
          numero_contrato: string
          cliente_id: string
          cliente_nombre: string | null
          asesor_perfil_id: string | null
          capital: number | string
          moneda: string
          tasa_anual: number | string
          modalidad: string
          tipo_interes: string
          categoria: string | null
          estado: string
          fecha_inicio: string
          fecha_vencimiento: string
          notas_internas: string | null
          creado_por: string | null
          creado_en: string
        }
        Relationships: []
      }
    }
    Functions: {
      /** Cierre atómico de una tarea: resultado al log inmutable + siguiente
       *  opcional, en una transacción (SECURITY DEFINER, ámbito adentro). */
      cerrar_tarea: {
        Args: {
          p_tarea_id: string
          p_estado: 'completada' | 'no_show' | 'cancelada'
          p_resultado_tipo?: string | null
          p_resultado_detalle?: string | null
          p_siguiente?: Record<string, unknown> | null
        }
        Returns: {
          ok: boolean
          tarea_id: string
          actividad_id: string | null
          siguiente_id: string | null
        }
      }
      cronograma_contrato_fn: {
        Args: { p_contrato_id: string }
        Returns: {
          id: string
          numero_cuota: number
          fecha_programada: string
          monto_programado: number | string
          estado: string
          tipo: string
          fecha_pago_real: string | null
          monto_pagado: number | string | null
        }[]
      }
      titulares_contrato_fn: {
        Args: { p_contrato_id: string }
        Returns: {
          id: string
          orden: number
          nombre_completo: string
          tipo_documento: string
          documento: string
        }[]
      }
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
      actualizar_capacidad_leads_objetivo: {
        Args: { p_analista_id: string; p_capacidad_leads_objetivo: number | null }
        Returns: { perfil_id: string; capacidad_leads_objetivo: number | null }[]
      }
      /** Gerencia fija las metas del mes por rol (upsert atómico; roles
       *  parciales permitidos). Devuelve las filas del periodo completo. */
      fijar_objetivos: {
        Args: {
          p_periodo: string
          p_objetivos: Record<string, Record<string, number>>
        }
        Returns: {
          id: string
          periodo: string
          rol: 'vendedor' | 'supervisor' | 'gerencia'
          capital_objetivo: number | string
          ventas_objetivo: number
          conversion_objetivo: number | string
          actualizado_por: string | null
          creado_en: string
          actualizado_en: string
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
      metricas_distribucion_leads_fn: {
        Args: { p_desde: string; p_hasta: string }
        Returns: Json
      }
      metricas_distribucion_leads_v2_fn: {
        Args: { p_desde: string; p_hasta: string }
        Returns: Json
      }
      // Fase F — agenda del equipo (JSON V1 atómico; contrato en
      // lib/metricas-agenda.ts).
      metricas_agenda_fn: {
        Args: { p_desde: string; p_hasta: string }
        Returns: Json
      }
      // ── C1: reparto de la cola global por el coordinador. Las tres son
      //    SECURITY DEFINER con gate propio (coordinador|gerencia): el
      //    coordinador NO ve crm.leads por RLS. La cola se proyecta SIN PII
      //    de contacto — no hay teléfono, correo ni DNI en el contrato. ─────
      // C1-bis (v2): + marca del clasificador y comentario del cliente
      //    REDACTADO (correo/celular/documento ocultos) y trunco a 400.
      leads_por_repartir: {
        Args: Record<string, never>
        Returns: {
          id: string
          nombre_completo: string
          distrito: string | null
          origen: OrigenDb
          categoria_interes: CategoriaInteresDb | null
          monto_estimado: number // numeric — PostgREST puede serializar string
          moneda: MonedaDb
          creado_en: string
          clasificacion_auto: ClasificacionAutoDb | null
          comentario: string | null
        }[]
      }
      supervisores_para_reparto: {
        Args: Record<string, never>
        Returns: {
          perfil_id: string
          nombre: string
          activo: boolean
          bandeja_pendiente: number
        }[]
      }
      /** Mueve un lead de la cola global a la bandeja de un supervisor
       *  (asignado_supervisor_id; vendedor_id sigue null). Re-valida
       *  no_contactar con SQLSTATE propio P0429 (Ley 29571). */
      repartir_lead: {
        Args: { p_lead: string; p_supervisor: string }
        Returns: Json
      }
      // ── C1-bis: descarte de la cola global (el código marca, Rosa cierra).
      //    SQLSTATE: 42501 rol · 22023 argumento · P0002 fuera de cola/carrera. ─
      /** Cierra un lead de la COLA GLOBAL con motivo obligatorio. Idempotente
       *  para el mismo actor+motivo (`ya_estaba: true`). La nota se appendea
       *  (`· DESCARTE: …`), nunca se pisa. No toca activo ni tenencia. */
      descartar_lead: {
        Args: { p_lead: string; p_motivo: MotivoDescarteDb; p_nota?: string | null }
        Returns: Json
      }
      /** Deshace un descarte PROPIO de las últimas 24 h si el lead sigue sin
       *  dueño: reabre en 'nuevo' (el guard incrementa ciclo_actual). Choque
       *  con el índice único de teléfono/DNI vivo llega como 22023. */
      deshacer_descarte: {
        Args: { p_lead: string }
        Returns: Json
      }
    }
    Enums: Record<string, never>
    CompositeTypes: Record<string, never>
  }
}
