// Tipos de dominio del traspaso del panel del ANALISTA al CRM (clientes del
// portal + contratos). Viven en su propio módulo — NO en tipos.ts — para que el
// mundo "leads" (tipos.ts) y el mundo "clientes/contratos del portal" no se
// mezclen: este archivo espeja tablas de `public` (dueño: el portal), tipos.ts
// espeja el esquema `crm`.
import type { Moneda } from './format'
import type { CategoriaContrato, ModalidadContrato, TipoCuota, TipoInteres } from './cronograma'
import type { TipoDocumento } from './documento'

/** Respuesta existente de crm.resumen_cartera_clientes_fn, sin fórmulas UI. */
export interface ResumenCarteraClientes {
  version: 1
  generado_en: string
  zona: 'America/Lima'
  dias_alarma_renovacion: 30
  clientes: { en_gestion: number; de_baja: number; con_capital: number; sin_asesor: number }
  capital_activo: { pen: number; usd: number }
  contratos: { por_estado: Record<string, number>; por_vencer_30: number; por_vencer_30_de_baja: number }
}

/** Fila de la vista crm.clientes_basicos (ya scopeada por rol del CRM). */
export interface ClienteBasico {
  id: string
  nombres: string | null
  apellidos: string | null
  nombre_completo: string
  /** Un tipo NUEVO en el portal degrada tolerante a 'DNI' en la frontera (no tira la fila). */
  tipo_documento: TipoDocumento
  dni: string | null
  correo: string | null
  telefono: string | null
  asesor_perfil_id: string | null
  /** Quién registró al cliente — con asesor_perfil_id NULL define el dueño de cartera (regla del servidor). */
  creado_por: string | null
  activo: boolean
  creado_en: string // ISO
}

/**
 * Identidad y contacto autorizados para la Ficha 360. Esta frontera no
 * contiene domicilio ni banca; esos datos siguen gobernados por las
 * capacidades específicas que devuelve el servidor.
 */
export type ClienteFichaComercial = Pick<
  ClienteBasico,
  | 'id'
  | 'nombres'
  | 'apellidos'
  | 'nombre_completo'
  | 'tipo_documento'
  | 'dni'
  | 'correo'
  | 'telefono'
  | 'asesor_perfil_id'
  | 'activo'
  | 'creado_en'
>

/**
 * Detalle comercial scopeado por `crm.cliente_detalle_fn`: identidad, los
 * metadatos de la ventana de 5 h y, solo cuando `banca_visible` es true, las
 * 14 columnas bancarias. `cuentas_bancarias_visibles` gobierna por separado
 * el ledger: un cliente inactivo puede conservar la banca histórica embebida
 * sin abrir una RPC que exige cartera activa. Directorio recibe ambas cerradas.
 */
export interface ClienteDetalle {
  id: string
  nombre_completo: string
  nombres: string | null
  apellidos: string | null
  tipo_documento: TipoDocumento
  dni: string | null
  correo: string | null
  telefono: string | null
  domicilio: string | null
  asesor_perfil_id: string | null
  creado_por: string | null
  creado_en: string // ISO — de aquí sale la cuenta regresiva de lib/ventana
  /** Capacidad calculada por el servidor; nunca se infiere del rol en el front. */
  banca_visible: boolean
  /** Capacidad exacta para consultar `crm.cuentas_bancarias_cliente_fn`. */
  cuentas_bancarias_visibles: boolean
  // Cuenta en SOLES (PEN)
  banco: string | null
  tipo_cuenta: string | null
  numero_cuenta: string | null
  cci: string | null
  titular_distinto: boolean
  beneficiario_nombre: string | null
  beneficiario_dni: string | null
  // Cuenta en DÓLARES (USD)
  banco_usd: string | null
  tipo_cuenta_usd: string | null
  numero_cuenta_usd: string | null
  cci_usd: string | null
  titular_distinto_usd: boolean
  beneficiario_nombre_usd: string | null
  beneficiario_dni_usd: string | null
}

/**
 * Cuenta que la RPC `crm.cuentas_bancarias_cliente_fn` permite elegir para un
 * contrato nuevo. `cuenta_id=null` identifica el slot PEN/USD vigente de
 * public.perfiles: al guardar, el servidor crea su versión histórica.
 */
export interface DatosCuentaPagoContrato {
  banco: string
  tipo_cuenta: 'ahorros' | 'corriente'
  numero_cuenta: string
  cci: string
  titular_distinto: boolean
  beneficiario_nombre: string | null
  beneficiario_dni: string | null
}

export interface CuentaBancariaSeleccionable extends DatosCuentaPagoContrato {
  cuenta_id: string | null
  moneda: Moneda
  origen: 'perfil' | 'contrato'
  es_cuenta_perfil: boolean
  creada_en: string | null
}

/** Selección discriminada que acepta la RPC atómica de alta de contrato. */
export type CuentaPagoContratoInput =
  | { tipo: 'perfil'; cuenta_esperada: DatosCuentaPagoContrato }
  | { tipo: 'existente'; cuenta_id: string }
  | ({ tipo: 'nueva' } & DatosCuentaPagoContrato)

/** Estados del ciclo de vida de public.contratos (espejo del CHECK del portal). */
export const ESTADOS_CONTRATO = ['activo', 'vencido', 'renovado', 'retirado'] as const
export type EstadoContrato = (typeof ESTADOS_CONTRATO)[number]

/** Fila de public.contratos con el nombre del cliente embebido (lista "Mis contratos"). */
export interface ContratoRow {
  id: string
  numero_contrato: string
  cliente_id: string
  /** Del embed cliente:perfiles(nombre_completo); null si la RLS no dejó verlo. */
  cliente_nombre: string | null
  capital: number
  moneda: Moneda
  tasa_anual: number
  modalidad: ModalidadContrato
  tipo_interes: TipoInteres
  categoria: CategoriaContrato | null
  estado: EstadoContrato
  fecha_inicio: string // YYYY-MM-DD
  fecha_vencimiento: string // YYYY-MM-DD
  /** YYYY-MM-DD — cuándo se VENDIÓ. Es el mes por el que se paga la cuota y por
   *  el que «Mi cartera» reparte sus bloques. NO es un instante: no lleva huso. */
  fecha_cierre_comercial: string
  notas_internas: string | null
  creado_por: string | null
  creado_en: string // ISO — ventana de 5 h para "Corregir"
  /** Condición/version inmutable que originó los términos del contrato. */
  producto_condicion_id: string
  producto_id: string
  producto_codigo: string
  producto_version_id: string
  producto_version: number
  producto_nombre: string
  producto_version_estado: 'borrador' | 'publicada' | 'retirada'
}

/** Operación comercial confirmada sobre un cliente existente. La fila congela
 * al analista que administraba la cartera en ese momento y mantiene PEN/USD
 * separados. Las renovaciones históricas de agosto pueden venir sin desglose:
 * se muestra como pendiente, nunca como capital adicional 0 inventado. */
export interface OperacionCartera {
  id: string
  cliente_id: string
  vendedor_id: string
  tipo: 'renovacion' | 'upgrade'
  contrato_origen_id: string | null
  contrato_nuevo_id: string
  fecha_operacion: string
  periodo: string
  moneda: Moneda
  capital_renovado: number | null
  capital_adicional: number | null
  elegible_conversion: boolean
  desglose_completo: boolean
  fuente: 'flujo_cartera' | 'backfill_agosto_2026'
  creado_por: string
  creado_en: string
}

/** Rastro postventa generado al cerrar una tarea cuyo sujeto es un cliente. Se
 * mantiene fuera del timeline de leads para no alterar SLA ni etapas. */
export interface ActividadCliente {
  id: string
  cliente_id: string
  /** Responsable del hecho; puede ser null en una reasignación de sistema. */
  vendedor_id: string | null
  tarea_id: string | null
  tipo:
    | 'llamada_realizada'
    | 'llamada_no_contestada'
    | 'whatsapp_enviado'
    | 'whatsapp_recibido'
    | 'reunion_realizada'
    | 'nota'
    | 'reasignacion'
  detalle: string | null
  creado_por: string | null
  creado_en: string
}

/** Estados de cuota de public.cronograma_pagos ('trasladado' = capital roleado, JAMÁS mora). */
export const ESTADOS_CUOTA = ['pendiente', 'pagado', 'vencido', 'trasladado'] as const
export type EstadoCuota = (typeof ESTADOS_CUOTA)[number]

/** Cuota del cronograma tal como la ve el detalle (solo lectura en el CRM). */
export interface Cuota {
  id: string
  numero_cuota: number
  fecha_programada: string // YYYY-MM-DD
  monto_programado: number
  estado: EstadoCuota
  tipo: TipoCuota
  fecha_pago_real: string | null
  monto_pagado: number | null
}

/**
 * Co-titular tal como VIAJA al servidor dentro de p_contrato.titulares (espejo
 * de normalizarTitulares del portal): sin `orden` — lo deriva la RPC del índice.
 */
export interface TitularInput {
  nombre_completo: string
  tipo_documento: TipoDocumento
  documento: string
}

/** Co-titular tal como se LEE de public.contrato_titulares (cuentas mancomunadas, máx 5). */
export interface Titular extends TitularInput {
  orden: number
}

/** Tope de co-titulares por contrato — espejo de MAX_TITULARES de titulares-core.js. */
export const MAX_TITULARES = 5
