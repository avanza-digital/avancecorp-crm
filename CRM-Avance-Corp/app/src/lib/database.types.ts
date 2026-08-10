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
import type {
  EstadoTarea as EstadoTareaDb,
  ModalidadReunion as ModalidadReunionDb,
  MotivoNoRealizada as MotivoNoRealizadaDb,
  RespuestaReprogramarReunion,
  ResultadoReunion as ResultadoReunionDb,
  TipoTarea as TipoTareaDb,
} from './tipos'

export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

type RolCrmDb = 'vendedor' | 'supervisor' | 'gerencia' | 'directorio' | 'coordinador'
type TipoDocumentoDb = 'DNI' | 'CE' | 'PASAPORTE'
type EstadoContratoDb = 'activo' | 'vencido' | 'renovado' | 'retirado'
type ModalidadContratoDb = 'mensual' | 'trimestral' | 'semestral' | 'anual'
type TipoInteresDb = 'simple' | 'compuesto'
// Mismos literales que CategoriaInteresDb pero es OTRO dominio (contratos.categoria
// del portal, no crm.leads.categoria_interes) — se mantienen separados a propósito.
type CategoriaContratoDb = 'nuevo' | 'renovacion' | 'upgrade'
type EstadoProductoVersionDb = 'borrador' | 'publicada' | 'retirada'
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
type DisponibilidadLeadDb =
  | { estado: 'libre' }
  | { estado: 'en_bolsa' }
  | { estado: 'tomado'; vendedor: string | null; tenencia_desde: string | null }
  | {
      estado: 'enfriamiento'
      motivo_descarte: MotivoDescarteDb
      disponible_desde: string
      descartado_por: string | null
    }
  | { estado: 'ya_es_cliente'; asesor: string }
  | { estado: 'no_contactar' }
  | { estado: 'error'; detalle: 'telefono_invalido' }
type ResultadoCreacionLeadAtomicaDb =
  | { estado: 'creado'; lead_id: string }
  | DisponibilidadLeadDb
// C1-bis: veredicto del clasificador de crédito (trigger en el INSERT, inmutable).
type ClasificacionAutoDb = 'posible_credito'
type MonedaDb = 'PEN' | 'USD'
// CHECK leads_genero_valido: binario (sexo del documento), nullable.
type GeneroDb = 'F' | 'M'
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
          producto_condicion_id: string
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
          // El reloj del ASESOR (20260725012707): instante en que el vendedor
          // ACTUAL recibió el lead; null fuera de tenencia operativa. Igual que
          // los sellos del descarte, lo gobierna un trigger
          // (zzz_tenencia_desde) y por eso NO aparece en Insert/Update: lo que
          // mande el cliente API se descarta. `creado_en` es el reloj del
          // CLIENTE; este es el que mide al asesor.
          tenencia_desde: string | null
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
          modalidad_reunion: ModalidadReunionDb | null
          ubicacion_reunion: string | null
          enlace_reunion: string | null
          resultado_reunion: ResultadoReunionDb | null
          motivo_no_realizada: MotivoNoRealizadaDb | null
          detalle_cierre_reunion: string | null
          resultado_actividad_id: string | null
          reagendada_de: string | null
          confirmada_en: string | null
          reprogramaciones: number
          activo: boolean
          /** Autoría de la cancelación (20260726161945): 'asesor' = una persona
           *  la anuló por la RPC; 'sistema' = la canceló el trigger al cerrarse
           *  el lead, o un proceso sin sesión. SOLO LECTURA desde el front: la
           *  sellan los BEFORE triggers y por eso NO está en Insert ni Update —
           *  mandarla en el payload es un no-op silencioso. Un CHECK
           *  bicondicional garantiza que toda cancelada la lleva y ninguna
           *  no-cancelada la tiene. */
          cancelada_por: 'asesor' | 'sistema' | null
          /** QUIÉN firmó la anulación (20260727): el perfil que llamó a la RPC.
           *  null cuando cancelada_por = 'sistema' — ahí no hay persona a la que
           *  atribuir. SOLO LECTURA, igual que la columna de arriba y por lo
           *  mismo. Se compara contra vendedor_id para saber si la anulación fue
           *  PROPIA (pesa en el % de esa persona) o AJENA —su jefe— que NO pesa.
           *  Sin FK a public.perfiles a propósito: con on delete set null, dar
           *  de baja a un supervisor movería hacia atrás el % de sus vendedores. */
          cancelada_por_id: string | null
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
          modalidad_reunion?: ModalidadReunionDb | null
          ubicacion_reunion?: string | null
          enlace_reunion?: string | null
          creado_por?: string | null
        }
        Update: {
          titulo?: string
          nota?: string | null
          vence_en?: string // reprogramar: el trigger incrementa reprogramaciones
          modalidad_reunion?: ModalidadReunionDb | null
          ubicacion_reunion?: string | null
          enlace_reunion?: string | null
          // NINGÚN cierre pasa ya por aquí. Hasta 20260726161945 'cancelada' era
          // el único que se colaba sin la RPC — un vendedor podía vaciarse la
          // agenda por PATCH sin quedar etiquetado y saltándose el retroceso de
          // etapa. Ahora los tres estados de cierre exigen crm.cerrar_tarea().
          estado?: EstadoTareaDb
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
      /** Versiones bancarias inmutables por cliente. El navegador no accede a
       * la tabla: lista/crea exclusivamente mediante RPCs gateadas. */
      cuentas_bancarias: {
        Row: {
          id: string
          cliente_id: string
          moneda: MonedaDb
          banco: string
          tipo_cuenta: 'ahorros' | 'corriente'
          numero_cuenta: string
          cci: string
          titular_distinto: boolean
          beneficiario_nombre: string | null
          beneficiario_dni: string | null
          activa: boolean
          origen: 'perfil' | 'contrato'
          creado_por: string | null
          creado_en: string
          desactivada_por: string | null
          desactivada_en: string | null
        }
        Insert: never
        Update: never
        Relationships: []
      }
      /** Enlace histórico de una sola cuenta de pago por contrato. */
      contrato_cuentas_pago: {
        Row: {
          id: string
          contrato_id: string
          cuenta_bancaria_id: string
          creado_por: string | null
          creado_en: string
        }
        Insert: never
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
          producto_condicion_id: string
          producto_id: string
          producto_codigo: string
          producto_version_id: string
          producto_version: number
          producto_nombre: string
          producto_version_estado: EstadoProductoVersionDb
        }
        Relationships: []
      }
    }
    Functions: {
      /** Corrección acotada de clientes por Gerencia; no abre UPDATE crudo
       * sobre identidad, rol, estado, asesor ni autoría del perfil. */
      actualizar_cliente_gerencia: {
        Args: {
          p_cliente_id: string
          p_patch: Json
        }
        Returns: boolean
      }
      /** Cuentas activas compatibles + slot legacy vigente del perfil. */
      cuentas_bancarias_cliente_fn: {
        Args: { p_cliente_id: string; p_moneda: MonedaDb }
        Returns: {
          cuenta_id: string | null
          moneda: MonedaDb
          banco: string
          tipo_cuenta: 'ahorros' | 'corriente'
          numero_cuenta: string
          cci: string
          titular_distinto: boolean
          beneficiario_nombre: string | null
          beneficiario_dni: string | null
          origen: 'perfil' | 'contrato'
          es_cuenta_perfil: boolean
          creada_en: string | null
        }[]
      }
      /** Alta atómica: versiona/reutiliza la cuenta y delega el contrato al
       * motor public.crear_contrato dentro de la misma transacción. */
      crear_contrato_con_cuenta: {
        Args: {
          p_contrato: Record<string, unknown>
          p_cronograma: Record<string, unknown>[]
          p_cuenta: Record<string, unknown>
        }
        Returns: {
          id: string
          numero_contrato: string
          cuenta_bancaria_id: string
        }
      }
      /** Alta catalogada sin cuenta: fija la condición en la misma transacción. */
      crear_contrato_producto: {
        Args: {
          p_producto_condicion_id: string
          p_contrato: Record<string, unknown>
          p_cronograma: Record<string, unknown>[]
        }
        Returns: Json
      }
      /** Alta catalogada + cuenta bancaria atómica. */
      crear_contrato_con_cuenta_producto: {
        Args: {
          p_producto_condicion_id: string
          p_contrato: Record<string, unknown>
          p_cronograma: Record<string, unknown>[]
          p_cuenta: Record<string, unknown>
        }
        Returns: Json
      }
      /** Conserva la RPC pública de corrección y bloquea cambios de moneda que
       * dejarían incoherente una cuenta contractual ya fijada. */
      actualizar_contrato_con_cuenta: {
        Args: {
          p_id: string
          p_contrato: Record<string, unknown>
          p_cronograma: Record<string, unknown>[]
        }
        Returns: undefined
      }
      /** Corrección catalogada sin administración de cuenta. */
      actualizar_contrato_producto: {
        Args: {
          p_id: string
          p_producto_condicion_id: string
          p_contrato: Record<string, unknown>
          p_cronograma: Record<string, unknown>[]
        }
        Returns: Json
      }
      /** Corrección catalogada preservando la cuenta contractual. */
      actualizar_contrato_con_cuenta_producto: {
        Args: {
          p_id: string
          p_producto_condicion_id: string
          p_contrato: Record<string, unknown>
          p_cronograma: Record<string, unknown>[]
        }
        Returns: Json
      }
      /** Resolución administrativa usada por Pagos/Excel; no hay fallback en
       * la RPC: la UI lo aplica únicamente a contratos legacy sin enlace. */
      cuentas_pago_contratos_fn: {
        Args: { p_contrato_ids: string[] }
        Returns: {
          contrato_id: string
          cuenta_bancaria_id: string
          moneda: MonedaDb
          banco: string
          tipo_cuenta: 'ahorros' | 'corriente'
          numero_cuenta: string
          cci: string
          titular_distinto: boolean
          beneficiario_nombre: string | null
          beneficiario_dni: string | null
        }[]
      }
      /** Acceso propio canónico: distingue membresía ausente de revocación
       * explícita aunque RLS oculte ambas filas al cliente. */
      mi_acceso_fn: {
        Args: Record<string, never>
        Returns: {
          estado: 'miembro' | 'global' | 'revocado' | 'no_enrolado'
          perfil_id: string
          rol_crm?: string
          rol_portal?: string
          nombre_completo?: string | null
          puede_listar_usuarios?: boolean
          puede_administrar_usuarios?: boolean
          puede_organizar_jerarquia?: boolean
          puede_administrar_roles?: boolean
        }
      }
      /** Directorio operacional. Gerencia recibe PII necesaria para gestionar;
       * Superadmin-only recibe una proyección mínima para asignar roles. */
      usuarios_administrables_fn: {
        Args: { p_busqueda?: string | null; p_limite?: number; p_desde?: number }
        Returns: {
          perfil_id: string
          nombre_completo: string
          tipo_documento: string | null
          documento: string | null
          correo: string | null
          telefono: string | null
          whatsapp: string | null
          cargo: string | null
          tipo_cuenta: 'solo_crm' | 'compartida_portal'
          estado: 'pendiente_rol' | 'inactivo_crm' | 'activo' | 'suspendido_portal'
          rol_crm: RolCrmDb | null
          supervisor_id: string | null
          activo_crm: boolean | null
          activo_portal: boolean
          version_perfil: string | null
          version_equipo: string | null
          total: number
        }[]
      }
      actualizar_usuario_administrable_fn: {
        Args: {
          p_perfil_id: string
          p_nombre_completo: string
          p_tipo_documento: string
          p_documento: string
          p_telefono: string | null
          p_whatsapp: string | null
          p_cargo: string | null
          p_version_perfil: string
          p_idempotencia: string
        }
        Returns: Json
      }
      asignar_rol_usuario_fn: {
        Args: {
          p_perfil_id: string
          p_rol_crm: RolCrmDb
          p_version_equipo: string | null
          p_idempotencia: string
        }
        Returns: Json
      }
      actualizar_jerarquia_usuario_fn: {
        Args: {
          p_perfil_id: string
          p_supervisor_id: string | null
          p_version_equipo: string
          p_idempotencia: string
        }
        Returns: Json
      }
      impacto_desactivacion_usuario_fn: {
        Args: { p_perfil_id: string }
        Returns: Json
      }
      fijar_membresia_activa_fn: {
        Args: {
          p_perfil_id: string
          p_activo: boolean
          p_reemplazo_id: string | null
          p_version_equipo: string
          p_idempotencia: string
        }
        Returns: Json
      }
      productos_inversion_gestion_fn: {
        Args: Record<string, never>
        Returns: Json
      }
      productos_inversion_seleccion_fn: {
        Args: Record<string, never>
        Returns: {
          condicion_id: string
          producto_id: string
          producto_codigo: string
          producto_revision: number
          version_id: string
          numero_version: number
          version_nombre: string
          vigente_desde: string
          vigente_hasta: string | null
          categoria: CategoriaContratoDb
          moneda: MonedaDb
          plazo_meses: number
          modalidad: ModalidadContratoDb
          tipo_interes: TipoInteresDb
          capital_minimo: number | string
          capital_maximo: number | string
          tasa_referencia: number | string
          tasa_minima: number | string
          tasa_maxima: number | string
        }[]
      }
      crear_producto_inversion: {
        Args: {
          p_codigo: string
          p_nombre: string
          p_descripcion: string | null
          p_vigente_desde: string
          p_vigente_hasta: string | null
          p_condiciones: Json
        }
        Returns: Json
      }
      crear_version_producto_inversion: {
        Args: {
          p_producto_id: string
          p_expected_revision: number
          p_nombre: string
          p_descripcion: string | null
          p_vigente_desde: string
          p_vigente_hasta: string | null
          p_condiciones: Json
        }
        Returns: Json
      }
      actualizar_borrador_producto_inversion: {
        Args: {
          p_version_id: string
          p_expected_revision: number
          p_nombre: string
          p_descripcion: string | null
          p_vigente_desde: string
          p_vigente_hasta: string | null
          p_condiciones: Json
        }
        Returns: Json
      }
      publicar_version_producto_inversion: {
        Args: { p_version_id: string; p_expected_revision: number }
        Returns: Json
      }
      archivar_producto_inversion: {
        Args: { p_producto_id: string; p_expected_revision: number }
        Returns: Json
      }
      cerrar_altas_legacy_productos: {
        Args: { p_expected_revision: number }
        Returns: Json
      }
      configuracion_metas_fn: {
        Args: { p_periodo: string }
        Returns: Json
      }
      publicar_metas_vendedores: {
        Args: { p_periodo: string; p_expected_revision: number; p_metas: Json }
        Returns: {
          id: string
          periodo: string
          revision: number
          revision_anterior_id: string | null
          publicada_por: string
          publicada_en: string
        }[]
      }
      cumplimiento_metas_fn: {
        Args: { p_periodo: string }
        Returns: Json
      }
      configuracion_sla_fn: {
        Args: Record<string, never>
        Returns: Json
      }
      publicar_politica_sla: {
        Args: { p_expected_version: number; p_vigente_desde: string | null; p_config: Json }
        Returns: {
          id: string
          version: number
          version_anterior_id: string | null
          vigente_desde: string
          zona_horaria: 'America/Lima'
          tipo_reloj: 'corrido'
          primera_gestion_minutos: number
          primer_contacto_minutos: number
          publicada_por: string | null
          publicada_en: string
        }[]
      }
      metricas_sla_fn: {
        Args: { p_desde: string; p_hasta: string }
        Returns: Json
      }
      estado_sla_leads_fn: {
        Args: Record<string, never>
        Returns: {
          lead_id: string
          ciclo_politica_id: string
          ciclo_politica_version: number
          primera_gestion_limite_en: string
          primera_gestion_en: string | null
          primer_contacto_limite_en: string
          primer_contacto_en: string | null
          ciclo_aproximado: boolean
          asignacion_id: string | null
          asignacion_politica_id: string | null
          asignacion_politica_version: number | null
          asignacion_primera_gestion_limite_en: string | null
          asignacion_primera_gestion_en: string | null
          asignacion_primer_contacto_limite_en: string | null
          asignacion_primer_contacto_en: string | null
          etapa_politica_id: string | null
          etapa_politica_version: number | null
          etapa: Exclude<EtapaDb, 'convertido' | 'descartado'> | null
          etapa_iniciada_en: string | null
          etapa_limite_en: string | null
          etapa_objetivo_minutos: number | null
          etapa_aproximada: boolean | null
        }[]
      }
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
      cerrar_reunion: {
        Args: {
          p_tarea_id: string
          p_estado: 'completada' | 'no_show' | 'cancelada'
          p_resultado_reunion?: ResultadoReunionDb | null
          p_motivo_no_realizada?: MotivoNoRealizadaDb | null
          p_detalle?: string | null
          p_siguiente?: Record<string, unknown> | null
        }
        Returns: Json
      }
      reprogramar_reunion: {
        Args: { p_tarea_id: string; p_vence_en: string; p_nueva_id?: string | null }
        Returns: RespuestaReprogramarReunion
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
      /** P-047/P-048: consulta previa, sin escritura, para decidir si un
       *  teléfono o DNI puede entrar como lead. Es una ayuda de UX; la garantía
       *  del alta manual vive en `crear_lead_si_disponible`. */
      verificar_disponibilidad_lead: {
        Args: { p_telefono: string; p_dni?: string | null }
        Returns: DisponibilidadLeadDb
      }
      /** Alta autoritativa P-048. El servidor normaliza y bloquea las llaves
       *  del contacto, revalida P-047 y hace el INSERT en la misma transacción. */
      crear_lead_si_disponible: {
        Args: {
          p_nombre_completo: string
          p_telefono: string
          p_origen: OrigenDb
          p_monto_estimado: number
          p_moneda: MonedaDb
          p_id?: string | null
          p_correo?: string | null
          p_dni?: string | null
          p_genero?: GeneroDb | null
          p_fecha_nacimiento?: string | null
          p_distrito?: string | null
          p_etapa?: Exclude<EtapaDb, 'convertido' | 'descartado'>
          p_categoria_interes?: CategoriaInteresDb | null
          p_vendedor_id?: string | null
          p_nota?: string | null
        }
        Returns: ResultadoCreacionLeadAtomicaDb
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
      metricas_conversiones_fn: {
        Args: { p_desde: string; p_hasta: string }
        Returns: Json
      }
      // Decisión #10 (b2): ranking de conversión RECALCULADO sobre el ámbito del
      // actor. Supervisor = su subárbol recursivo; gerencia y lector = la empresa;
      // el resto recibe 42501. El payload lo valida
      // `lib/metricas-conversiones-equipo.ts` con su propio esquema: el de la
      // global exige cinco agregados empresa-wide que esta RPC no calcula.
      metricas_conversiones_equipo_fn: {
        Args: { p_desde: string; p_hasta: string }
        Returns: Json
      }
      metricas_reuniones_fn: {
        Args: { p_desde: string; p_hasta: string }
        Returns: Json
      }
      // ── F1 tanda 1: métricas agregadas en el servidor (JSON v1 con
      //    version/generado_en; la ventana de convertidos de 45 días viaja
      //    como ventana_convertidos_dias). Los contratos Valibot llegan con
      //    los hooks de pantalla (tandas F1 siguientes). ─────────────────────
      resumen_cartera_fn: {
        Args: Record<string, never>
        Returns: Json
      }
      cola_accion_fn: {
        Args: { p_limite?: number }
        Returns: Json
      }
      metricas_vendedores_fn: {
        Args: Record<string, never>
        Returns: Json
      }
      series_comerciales_fn: {
        Args: { p_meses?: number }
        Returns: Json
      }
      // ── F1 tanda 2: cierre del servidor de métricas. resumen_reparto_fn
      //    lleva gate propio (coordinador|gerencia; 42501 para el resto,
      //    lector global incluido). Sin PII: solo agregados. ────────────────
      resumen_tareas_fn: {
        Args: Record<string, never>
        Returns: Json
      }
      resumen_cartera_clientes_fn: {
        Args: Record<string, never>
        Returns: Json
      }
      resumen_reparto_fn: {
        Args: Record<string, never>
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
      // ── C1-ter: la pestaña "Descartados" del coordinador. Solo LECTURA;
      //    descartes de coordinador/gerencia sobre la cola global, 30 días,
      //    tope 200, más nuevos primero. comentario del cliente y nota_descarte
      //    de Rosa REDACTADOS y truncados a 400 por separado. ─────────────────
      leads_descartados: {
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
          nota_descarte: string | null
          motivo_descarte: MotivoDescarteDb | null
          descartado_en: string
          descartado_por_nombre: string
          es_mio: boolean
          puede_deshacer: boolean
        }[]
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
