// Tipos de dominio del traspaso del panel del ANALISTA al CRM (clientes del
// portal + contratos). Viven en su propio módulo — NO en tipos.ts — para que el
// mundo "leads" (tipos.ts) y el mundo "clientes/contratos del portal" no se
// mezclen: este archivo espeja tablas de `public` (dueño: el portal), tipos.ts
// espeja el esquema `crm`.
import type { Moneda } from './format'
import type { CategoriaContrato, ModalidadContrato, TipoCuota, TipoInteres } from './cronograma'
import type { TipoDocumento } from './documento'

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
 * Detalle COMPLETO de public.perfiles para corregir a un cliente: identidad +
 * las 14 columnas bancarias (cuenta PEN = columnas base, cuenta USD = sufijo
 * _usd, independientes — regla del portal 2026-06-09) + los metadatos de la
 * ventana de 5 h (creado_en/creado_por). La RLS perfiles_analista_select ya
 * limita la lectura a la cartera del analista.
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
