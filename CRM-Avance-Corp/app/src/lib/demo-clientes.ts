// Fixtures DEMO del panel del ANALISTA (Clientes + Contratos) — el escaparate
// que Miguel enseña sin tocar producción. Hermano de lib/demo.ts (el mundo de
// leads), pero para el mundo "clientes/contratos del portal".
//
// POR QUÉ vive aparte y se carga por import() dinámico gated:
//   1. AISLAMIENTO DE PROD (regla de oro): una sesión demo NO tiene Supabase.
//      Estos datos alimentan la UI en demo para que NUNCA se llame a la API real
//      (ni listar, ni detalle, ni crear). El detalle recibe el cronograma por
//      prop precargada (ContratoDetalle.datos) → cero red.
//   2. NO ENTRA AL BUNDLE DE PROD: las pantallas hacen `import('@/lib/demo-clientes')`
//      bajo el guard literal `import.meta.env.DEV && VITE_ENABLE_DEMO==='true'`
//      (mismo patrón que store.tsx con demo.ts) → Rolldown elimina el chunk en
//      cualquier build de producción. Por eso estos nombres ficticios jamás
//      aparecen en dist/assets.
//
// FECHAS RELATIVAS a Date.now() a propósito: nada de fechas absolutas que
// caduquen. El reloj de la ventana de 5 h (lib/ventana) corre de verdad sobre
// estos creado_en, y los cronogramas se anclan a "hoy" al cargar el módulo.
//
// Nombres/documentos: inconfundiblemente PERUANOS y DE MENTIRA (mismo estilo
// que demo.ts). El documento del CE/pasaporte viaja en la columna `dni`
// (grandfathering del portal: `dni` guarda el documento sea cual sea su tipo).
import type { ClienteBasico, ContratoRow, Cuota, EstadoCuota, Titular } from './clientes-tipos'
import {
  formatDateLocal,
  generarCronograma,
  vencimientoDesdePlazo,
  type CuotaCronograma,
} from './cronograma'

// ── Helpers de fecha relativa (Date.now() = app code permitido) ────────────────
/** ISO de hace N horas — para creado_en dentro/fuera de la ventana de 5 h. */
const haceHoras = (h: number) => new Date(Date.now() - h * 3_600_000).toISOString()
/** ISO de hace N días. */
const haceDias = (d: number) => new Date(Date.now() - d * 86_400_000).toISOString()
/** 'YYYY-MM-DD' (local) desplazado `meses` y `dias` respecto de hoy — ancla los
 *  cronogramas a "hoy" sin fechas absolutas (cuotas pasadas = pagadas/vencidas,
 *  futuras = pendientes, siempre coherentes con el día en que se abre el demo). */
function fechaLocalDesplazada(meses: number, dias: number): string {
  const hoy = new Date()
  return formatDateLocal(new Date(hoy.getFullYear(), hoy.getMonth() + meses, hoy.getDate() + dias))
}
/** 'YYYY-MM-DD' (local) del día fijo `dia` del mes desplazado `meses`. El
 *  compuesto EXIGE aniversario exacto (aniosExactos); un día que existe en TODO
 *  mes (15) evita que la normalización de fin de mes rompa el par inicio/fin
 *  cuando el demo se abre un día 29-31. */
function fechaLocalMesDia(meses: number, dia: number): string {
  const hoy = new Date()
  return formatDateLocal(new Date(hoy.getFullYear(), hoy.getMonth() + meses, dia))
}

// El asesor dueño de la cartera demo = VENDEDOR UNO (d-v1, la sesión demo de
// vendedor): así, con yo.id='d-v1', los contratos salen como "míos" y el botón
// Corregir se ve (vivo o bloqueado según la ventana), igual que en la ruta real.
const ASESOR_DEMO = 'd-v1'

// ── 5 clientes: 2 con ventana de corrección VIVA, 3 vencida (uno CE, uno PASAPORTE)
export const CLIENTES_DEMO: ClienteBasico[] = [
  {
    id: 'dc-cli-1',
    nombres: 'ROSA MERCEDES',
    apellidos: 'AGUILAR VENTURA',
    nombre_completo: 'ROSA MERCEDES AGUILAR VENTURA',
    dni: '46801357', // DNI (8 dígitos)
    correo: 'rosa.aguilar@correo.pe',
    telefono: '+51987120345',
    asesor_perfil_id: ASESOR_DEMO,
    activo: true,
    creado_en: haceHoras(1), // ventana VIVA (quedan ~4 h)
  },
  {
    id: 'dc-cli-2',
    nombres: 'JAVIER ERNESTO',
    apellidos: 'MEZA COLLANTES',
    nombre_completo: 'JAVIER ERNESTO MEZA COLLANTES',
    dni: '43217985', // DNI
    correo: 'javier.meza@correo.pe',
    telefono: '+51987654109',
    asesor_perfil_id: ASESOR_DEMO,
    activo: true,
    creado_en: haceHoras(3), // ventana VIVA (quedan ~2 h)
  },
  {
    id: 'dc-cli-3',
    nombres: 'NADIA SOLEDAD',
    apellidos: 'CHOQUE MAMANI',
    nombre_completo: 'NADIA SOLEDAD CHOQUE MAMANI',
    dni: '001987654', // Carné de Extranjería (9 dígitos) en la columna `dni`
    correo: 'nadia.choque@correo.pe',
    telefono: '+51965321478',
    asesor_perfil_id: ASESOR_DEMO,
    activo: true,
    creado_en: haceDias(2), // ventana VENCIDA
  },
  {
    id: 'dc-cli-4',
    nombres: 'BRUNO ALEXIS',
    apellidos: 'FONSECA IPARRAGUIRRE',
    nombre_completo: 'BRUNO ALEXIS FONSECA IPARRAGUIRRE',
    dni: 'PE1548792', // Pasaporte (alfanumérico) en la columna `dni`
    correo: 'bruno.fonseca@correo.pe',
    telefono: '+51944870231',
    asesor_perfil_id: ASESOR_DEMO,
    activo: true,
    creado_en: haceDias(15), // ventana VENCIDA
  },
  {
    id: 'dc-cli-5',
    nombres: 'GLADYS PILAR',
    apellidos: 'YUPANQUI ROJAS',
    nombre_completo: 'GLADYS PILAR YUPANQUI ROJAS',
    dni: '40928175', // DNI
    correo: 'gladys.yupanqui@correo.pe',
    telefono: '+51932014876',
    asesor_perfil_id: ASESOR_DEMO,
    activo: true,
    creado_en: haceDias(40), // ventana VENCIDA
  },
]

// ── Contratos: numeración estilo '2026-01-0009xx'. Solo el A tiene la ventana
//    de 5 h VIVA (para que 'Corregir' se vea habilitado); B y C, vencida. ────────

// A — mensual SIMPLE activo: 12 cuotas (3 pagadas, 1 vencida por fecha, resto pendientes).
const INICIO_A = fechaLocalDesplazada(-4, -15)
const CONTRATO_A: ContratoRow = {
  id: 'dc-ct-a',
  numero_contrato: '2026-01-000901',
  cliente_id: 'dc-cli-1',
  cliente_nombre: 'ROSA MERCEDES AGUILAR VENTURA',
  capital: 30000,
  moneda: 'PEN',
  tasa_anual: 12,
  modalidad: 'mensual',
  tipo_interes: 'simple',
  categoria: 'nuevo',
  estado: 'activo',
  fecha_inicio: INICIO_A,
  fecha_vencimiento: vencimientoDesdePlazo(INICIO_A, 12),
  notas_internas: 'Cliente puntual; domicilia el pago los primeros días del mes.',
  creado_por: ASESOR_DEMO,
  creado_en: haceHoras(2), // ventana VIVA → Corregir habilitado
}

// B — COMPUESTO: intereses al vencimiento (devolución) + retorno del capital (2 filas).
const CONTRATO_B: ContratoRow = {
  id: 'dc-ct-b',
  numero_contrato: '2026-01-000902',
  cliente_id: 'dc-cli-2',
  cliente_nombre: 'JAVIER ERNESTO MEZA COLLANTES',
  capital: 50000,
  moneda: 'USD',
  tasa_anual: 8,
  modalidad: 'anual', // en compuesto la modalidad no aplica (capitaliza anual)
  tipo_interes: 'compuesto',
  categoria: 'renovacion',
  estado: 'activo',
  fecha_inicio: fechaLocalMesDia(-3, 15),
  fecha_vencimiento: fechaLocalMesDia(9, 15), // inicio + 1 año exacto (aniosExactos=1)
  notas_internas: 'Renovación en dólares; capitaliza al año.',
  creado_por: ASESOR_DEMO,
  creado_en: haceDias(3), // ventana VENCIDA → Corregir bloqueado
}

// C — mancomunada: 2 co-titulares. Trimestral simple, 4 cuotas + retorno.
const INICIO_C = fechaLocalDesplazada(-7, 0)
const CONTRATO_C: ContratoRow = {
  id: 'dc-ct-c',
  numero_contrato: '2026-01-000903',
  cliente_id: 'dc-cli-5',
  cliente_nombre: 'GLADYS PILAR YUPANQUI ROJAS',
  capital: 80000,
  moneda: 'PEN',
  tasa_anual: 10,
  modalidad: 'trimestral',
  tipo_interes: 'simple',
  categoria: 'upgrade',
  estado: 'activo',
  fecha_inicio: INICIO_C,
  fecha_vencimiento: vencimientoDesdePlazo(INICIO_C, 12),
  notas_internas: 'Cuenta mancomunada con dos co-titulares (cónyuges).',
  creado_por: ASESOR_DEMO,
  creado_en: haceDias(20), // ventana VENCIDA → Corregir bloqueado
}

export const CONTRATOS_DEMO: ContratoRow[] = [CONTRATO_A, CONTRATO_B, CONTRATO_C]

// ── Cronogramas coherentes con lib/cronograma (se usa el generador REAL) ────────
// materializar() convierte las filas 'pendiente' del generador en cuotas con
// estado/pago de demo, según la regla por índice de cada contrato.
function materializar(
  filas: CuotaCronograma[],
  prefijo: string,
  regla: (fila: CuotaCronograma, i: number) => EstadoCuota,
): Cuota[] {
  return filas.map((f, i) => {
    const estado = regla(f, i)
    const pagada = estado === 'pagado'
    return {
      id: `${prefijo}-c${f.numero_cuota}`,
      numero_cuota: f.numero_cuota,
      fecha_programada: f.fecha_programada,
      monto_programado: f.monto_programado,
      estado,
      tipo: f.tipo,
      // El pago real cae el mismo día programado (fecha ya en el pasado).
      fecha_pago_real: pagada ? f.fecha_programada : null,
      monto_pagado: pagada ? f.monto_programado : null,
    }
  })
}

/** Cronograma por contrato_id — lo consume el detalle demo (ContratoDetalle.datos). */
export const CRONOGRAMAS_DEMO: Record<string, Cuota[]> = {
  // A: 12 cuotas → #1-3 pagadas, #4 vencida (pasada sin pagar), #5-12 pendientes; retorno pendiente.
  [CONTRATO_A.id]: materializar(
    generarCronograma(CONTRATO_A.capital, CONTRATO_A.tasa_anual, CONTRATO_A.fecha_inicio, CONTRATO_A.fecha_vencimiento, 'mensual', 'simple'),
    'dc-ct-a',
    (f, i) => (f.tipo === 'retorno' ? 'pendiente' : i < 3 ? 'pagado' : i === 3 ? 'vencido' : 'pendiente'),
  ),
  // B: compuesto → devolución de intereses + retorno del capital, ambos pendientes (aún no vence).
  [CONTRATO_B.id]: materializar(
    generarCronograma(CONTRATO_B.capital, CONTRATO_B.tasa_anual, CONTRATO_B.fecha_inicio, CONTRATO_B.fecha_vencimiento, 'anual', 'compuesto'),
    'dc-ct-b',
    () => 'pendiente',
  ),
  // C: trimestral → #1 pagada, #2 vencida, #3-4 pendientes; retorno pendiente.
  [CONTRATO_C.id]: materializar(
    generarCronograma(CONTRATO_C.capital, CONTRATO_C.tasa_anual, CONTRATO_C.fecha_inicio, CONTRATO_C.fecha_vencimiento, 'trimestral', 'simple'),
    'dc-ct-c',
    (f, i) => (f.tipo === 'retorno' ? 'pendiente' : i === 0 ? 'pagado' : i === 1 ? 'vencido' : 'pendiente'),
  ),
}

/** Co-titulares por contrato_id — solo el contrato C es mancomunado (2 titulares). */
export const TITULARES_DEMO: Record<string, Titular[]> = {
  [CONTRATO_C.id]: [
    { nombre_completo: 'GLADYS PILAR YUPANQUI ROJAS', tipo_documento: 'DNI', documento: '40928175', orden: 1 },
    { nombre_completo: 'CÉSAR AUGUSTO ROMERO DELGADO', tipo_documento: 'DNI', documento: '41563209', orden: 2 },
  ],
}
