// Fixtures DEMO del panel del ANALISTA (Clientes + Contratos) — el escaparate
// que Miguel enseña sin tocar producción. Hermano de lib/demo.ts (el mundo de
// leads), pero para el mundo "clientes/contratos del portal".
//
// POR QUÉ vive aparte y se carga por import() dinámico gated:
//   1. AISLAMIENTO DE PROD (regla de oro): una sesión demo NO tiene Supabase.
//      Estos datos alimentan la UI en demo para que NUNCA se llame a la API real
//      (ni listar, ni detalle, ni crear). Las fichas y cronogramas llegan por
//      props precargadas (ClienteDetalle/ContratoDetalle.datos) → cero red.
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
import type {
  ClienteBasico,
  ClienteDetalle,
  ContratoRow,
  CuentaBancariaSeleccionable,
  Cuota,
  EstadoCuota,
  Titular,
} from './clientes-tipos'
import type { ContratoPdfDatos } from './contrato-pdf'
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

// El analista de los CONTRATOS demo = ANALISTA UNO (d-v1, la sesión demo de
// analista): así, con yo.id='d-v1', los contratos salen como "míos" y el botón
// Corregir se ve (vivo o bloqueado según la ventana), igual que en la ruta real.
const ASESOR_DEMO = 'd-v1'

// ── 6 clientes REPARTIDOS entre el equipo demo (asesor_perfil_id/creado_por
//    coherentes con EQUIPO_DEMO de lib/demo.ts) para que cada rol viva la
//    pantalla como en producción:
//    · d-v1 (sesión analista): ROSA y JAVIER con ventana VIVA + GLADYS vencida
//      — los 3 dueños de los contratos demo A/B/C, la narrativa no se rompe.
//    · d-sup1 (sesión supervisor): TERESA propia con ventana VIVA (acciones en
//      SU fila) y el equipo d-v1/d-v2 visible SIN acciones (regla de cartera).
//    · gerencia/directorio: los 6 y columna Analista variada; solo Gerencia opera.
//    Los documentos CE (NADIA) y PASAPORTE (BRUNO) viven en carteras ajenas a
//    d-v1: la sigla se luce en las vistas de supervisión.
export const CLIENTES_DEMO: ClienteBasico[] = [
  {
    id: 'dc-cli-1',
    nombres: 'ROSA MERCEDES',
    apellidos: 'AGUILAR VENTURA',
    nombre_completo: 'ROSA MERCEDES AGUILAR VENTURA',
    tipo_documento: 'DNI',
    dni: '46801357', // DNI (8 dígitos)
    correo: 'rosa.aguilar@correo.pe',
    telefono: '+51987120345',
    asesor_perfil_id: ASESOR_DEMO,
    creado_por: ASESOR_DEMO,
    activo: true,
    creado_en: haceHoras(1), // ventana VIVA (quedan ~4 h)
  },
  {
    id: 'dc-cli-2',
    nombres: 'JAVIER ERNESTO',
    apellidos: 'MEZA COLLANTES',
    nombre_completo: 'JAVIER ERNESTO MEZA COLLANTES',
    tipo_documento: 'DNI',
    dni: '43217985', // DNI
    correo: 'javier.meza@correo.pe',
    telefono: '+51987654109',
    // Sin analista asignado A PROPÓSITO: el dueño de cartera se hereda de
    // creado_por (la rama OR de la regla del servidor también se luce en demo).
    asesor_perfil_id: null,
    creado_por: ASESOR_DEMO,
    activo: true,
    creado_en: haceHoras(3), // ventana VIVA (quedan ~2 h)
  },
  {
    id: 'dc-cli-3',
    nombres: 'NADIA SOLEDAD',
    apellidos: 'CHOQUE MAMANI',
    nombre_completo: 'NADIA SOLEDAD CHOQUE MAMANI',
    tipo_documento: 'CE',
    dni: '001987654', // Carné de Extranjería (9 dígitos) en la columna `dni`
    correo: 'nadia.choque@correo.pe',
    telefono: '+51965321478',
    asesor_perfil_id: 'd-v2', // equipo de d-sup1: el supervisor la ve sin acciones
    creado_por: 'd-v2',
    activo: true,
    creado_en: haceDias(2), // ventana VENCIDA
  },
  {
    id: 'dc-cli-4',
    nombres: 'BRUNO ALEXIS',
    apellidos: 'FONSECA IPARRAGUIRRE',
    nombre_completo: 'BRUNO ALEXIS FONSECA IPARRAGUIRRE',
    tipo_documento: 'PASAPORTE',
    dni: 'PE1548792', // Pasaporte (alfanumérico) en la columna `dni`
    correo: 'bruno.fonseca@correo.pe',
    telefono: '+51944870231',
    asesor_perfil_id: 'd-v3', // equipo de d-sup2: solo gerencia/directorio lo ven
    creado_por: 'd-v3',
    activo: true,
    creado_en: haceDias(15), // ventana VENCIDA
  },
  {
    id: 'dc-cli-5',
    nombres: 'GLADYS PILAR',
    apellidos: 'YUPANQUI ROJAS',
    nombre_completo: 'GLADYS PILAR YUPANQUI ROJAS',
    tipo_documento: 'DNI',
    dni: '40928175', // DNI
    correo: 'gladys.yupanqui@correo.pe',
    telefono: '+51932014876',
    asesor_perfil_id: ASESOR_DEMO, // dueña del contrato C — sigue con d-v1
    creado_por: ASESOR_DEMO,
    activo: true,
    creado_en: haceDias(40), // ventana VENCIDA
  },
  {
    id: 'dc-cli-6',
    nombres: 'TERESA VICTORIA',
    apellidos: 'PAREDES OCHOA',
    nombre_completo: 'TERESA VICTORIA PAREDES OCHOA',
    tipo_documento: 'DNI',
    dni: '43781265', // DNI
    correo: 'teresa.paredes@correo.pe',
    telefono: '+51976403182',
    asesor_perfil_id: 'd-sup1', // cartera PROPIA del supervisor demo (también es analista)
    creado_por: 'd-sup1',
    activo: true,
    creado_en: haceHoras(2), // ventana VIVA → el supervisor ve acciones en SU fila
  },
]

// ── Detalle completo de los clientes demo ────────────────────────────────────
// Las cuentas son enteramente ficticias. La ficha de Mi cartera recibe estas
// filas por prop y deshabilita useClienteDetalle: una sesión demo no consulta
// public.perfiles ni puede mezclar por accidente PII de una caché real.
type DatosBancariosDemo = Pick<
  ClienteDetalle,
  | 'banco'
  | 'tipo_cuenta'
  | 'numero_cuenta'
  | 'cci'
  | 'titular_distinto'
  | 'beneficiario_nombre'
  | 'beneficiario_dni'
  | 'banco_usd'
  | 'tipo_cuenta_usd'
  | 'numero_cuenta_usd'
  | 'cci_usd'
  | 'titular_distinto_usd'
  | 'beneficiario_nombre_usd'
  | 'beneficiario_dni_usd'
>

const BANCARIOS_DEMO_VACIOS: DatosBancariosDemo = {
  banco: null,
  tipo_cuenta: null,
  numero_cuenta: null,
  cci: null,
  titular_distinto: false,
  beneficiario_nombre: null,
  beneficiario_dni: null,
  banco_usd: null,
  tipo_cuenta_usd: null,
  numero_cuenta_usd: null,
  cci_usd: null,
  titular_distinto_usd: false,
  beneficiario_nombre_usd: null,
  beneficiario_dni_usd: null,
}

function detalleClienteDemo(id: string, bancarios: Partial<DatosBancariosDemo>): ClienteDetalle {
  const cliente = CLIENTES_DEMO.find((fila) => fila.id === id)
  if (!cliente) throw new Error(`Fixture de cliente demo inexistente: ${id}`)
  return {
    id: cliente.id,
    nombre_completo: cliente.nombre_completo,
    nombres: cliente.nombres,
    apellidos: cliente.apellidos,
    tipo_documento: cliente.tipo_documento,
    dni: cliente.dni,
    correo: cliente.correo,
    telefono: cliente.telefono,
    domicilio: 'Av. Javier Prado Este 123, San Isidro, Lima',
    asesor_perfil_id: cliente.asesor_perfil_id,
    creado_por: cliente.creado_por,
    creado_en: cliente.creado_en,
    banca_visible: true,
    cuentas_bancarias_visibles: true,
    ...BANCARIOS_DEMO_VACIOS,
    ...bancarios,
  }
}

/** Fichas por cliente_id; todos los documentos y números son de demostración. */
export const DETALLES_CLIENTES_DEMO: Record<string, ClienteDetalle> = {
  'dc-cli-1': detalleClienteDemo('dc-cli-1', {
    banco: 'BCP',
    tipo_cuenta: 'ahorros',
    numero_cuenta: '19100000001234',
    cci: '00219100000000123456',
  }),
  'dc-cli-2': detalleClienteDemo('dc-cli-2', {
    banco_usd: 'Interbank',
    tipo_cuenta_usd: 'ahorros',
    numero_cuenta_usd: '2000000012345',
    cci_usd: '00320000000012345678',
  }),
  'dc-cli-3': detalleClienteDemo('dc-cli-3', {
    banco: 'BBVA',
    tipo_cuenta: 'corriente',
    numero_cuenta: '001100000012345678',
    cci: '01100100000012345678',
    titular_distinto: true,
    beneficiario_nombre: 'MARÍA DEMO QUISPE ROJAS',
    beneficiario_dni: '10000003',
  }),
  'dc-cli-4': detalleClienteDemo('dc-cli-4', {
    banco_usd: 'Scotiabank',
    tipo_cuenta_usd: 'corriente',
    numero_cuenta_usd: '000000123456',
    cci_usd: '00900000000012345678',
  }),
  'dc-cli-5': detalleClienteDemo('dc-cli-5', {
    banco: 'BanBif',
    tipo_cuenta: 'ahorros',
    numero_cuenta: '00000000123456',
    cci: '03800000000012345678',
    titular_distinto: true,
    beneficiario_nombre: 'CÉSAR DEMO ROMERO DELGADO',
    beneficiario_dni: '10000005',
  }),
  'dc-cli-6': detalleClienteDemo('dc-cli-6', {
    banco: 'Banco de la Nación',
    tipo_cuenta: 'ahorros',
    numero_cuenta: '04000000001234',
    cci: '01804000000000123456',
    banco_usd: 'BCP',
    tipo_cuenta_usd: 'ahorros',
    numero_cuenta_usd: '19300000001234',
    cci_usd: '00219300000000123456',
  }),
}

type CuentasClienteDemo = Record<'PEN' | 'USD', CuentaBancariaSeleccionable[]>

function cuentaPerfilDemo(
  cliente: ClienteDetalle,
  moneda: 'PEN' | 'USD',
): CuentaBancariaSeleccionable[] {
  const usd = moneda === 'USD'
  const banco = usd ? cliente.banco_usd : cliente.banco
  const tipoCuenta = usd ? cliente.tipo_cuenta_usd : cliente.tipo_cuenta
  const numeroCuenta = usd ? cliente.numero_cuenta_usd : cliente.numero_cuenta
  const cci = usd ? cliente.cci_usd : cliente.cci
  if (
    !banco ||
    (tipoCuenta !== 'ahorros' && tipoCuenta !== 'corriente') ||
    !numeroCuenta ||
    !cci
  ) {
    return []
  }
  return [{
    cuenta_id: null,
    moneda,
    banco,
    tipo_cuenta: tipoCuenta,
    numero_cuenta: numeroCuenta,
    cci,
    titular_distinto: usd ? cliente.titular_distinto_usd : cliente.titular_distinto,
    beneficiario_nombre: usd ? cliente.beneficiario_nombre_usd : cliente.beneficiario_nombre,
    beneficiario_dni: usd ? cliente.beneficiario_dni_usd : cliente.beneficiario_dni,
    origen: 'perfil',
    es_cuenta_perfil: true,
    creada_en: cliente.creado_en,
  }]
}

/** Cuentas ya precargadas para que ContratoNuevo demo jamás consulte Supabase. */
export const CUENTAS_CLIENTES_DEMO: Record<string, CuentasClienteDemo> = Object.fromEntries(
  Object.entries(DETALLES_CLIENTES_DEMO).map(([clienteId, cliente]) => [
    clienteId,
    {
      PEN: cuentaPerfilDemo(cliente, 'PEN'),
      USD: cuentaPerfilDemo(cliente, 'USD'),
    },
  ]),
)

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
  // Cierre = la MENOR entre inicio y día de registro, igual que el alta real.
  fecha_cierre_comercial: INICIO_A,
  notas_internas: 'Cliente puntual; domicilia el pago los primeros días del mes.',
  creado_por: ASESOR_DEMO,
  creado_en: haceHoras(2), // ventana VIVA → Corregir habilitado
  producto_condicion_id: '10000000-0000-4000-8000-000000000101',
  producto_id: '20000000-0000-4000-8000-000000000101',
  producto_codigo: 'DEMO-RENTA-PEN',
  producto_version_id: '30000000-0000-4000-8000-000000000101',
  producto_version: 1,
  producto_nombre: 'Renta Demo Soles',
  producto_version_estado: 'publicada',
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
  // Cerrado hace 3 MESES y registrado hace 3 días: es el caso que ejercita el
  // aviso «se registraron en otro mes» de la cabecera del bloque.
  fecha_cierre_comercial: fechaLocalMesDia(-3, 15),
  notas_internas: 'Renovación en dólares; capitaliza al año.',
  creado_por: ASESOR_DEMO,
  creado_en: haceDias(3), // ventana VENCIDA → Corregir bloqueado
  producto_condicion_id: '10000000-0000-4000-8000-000000000102',
  producto_id: '20000000-0000-4000-8000-000000000102',
  producto_codigo: 'DEMO-RENTA-USD',
  producto_version_id: '30000000-0000-4000-8000-000000000102',
  producto_version: 1,
  producto_nombre: 'Renta Demo Dólares',
  producto_version_estado: 'publicada',
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
  fecha_cierre_comercial: INICIO_C,
  notas_internas: 'Cuenta mancomunada con dos co-titulares (cónyuges).',
  creado_por: ASESOR_DEMO,
  creado_en: haceDias(20), // ventana VENCIDA → Corregir bloqueado
  producto_condicion_id: '10000000-0000-4000-8000-000000000103',
  producto_id: '20000000-0000-4000-8000-000000000103',
  producto_codigo: 'DEMO-UPGRADE-PEN',
  producto_version_id: '30000000-0000-4000-8000-000000000103',
  producto_version: 2,
  producto_nombre: 'Upgrade Demo',
  producto_version_estado: 'publicada',
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

// ── Fotografía legal para el PDF demo ────────────────────────────────────────
// Domicilios y datos del analista son deliberadamente ficticios. Esta foto se
// entrega al generador; los co-titulares viajan para demostrar que el sistema
// conserva la mancomunación, aunque el PDF imprime y firma SOLO el principal.
const DOMICILIOS_PDF_DEMO: Record<string, string> = {
  'dc-cli-1': 'Av. Los Laureles 456, San Isidro, Lima',
  'dc-cli-2': 'Jr. Las Begonias 789, Santiago de Surco, Lima',
  'dc-cli-3': 'Av. Tahuantinsuyo 245, Independencia, Lima',
  'dc-cli-4': 'Calle Los Nogales 118, San Borja, Lima',
  'dc-cli-5': 'Calle Los Cedros 321, Miraflores, Lima',
  'dc-cli-6': 'Jr. Huallaga 640, Cercado de Lima, Lima',
}

const ANALISTA_PDF_DEMO: ContratoPdfDatos['analista'] = {
  nombreCompleto: 'ANALISTA UNO',
  documento: '10000001',
  celular: '+51 987 654 321',
  correo: 'analista.uno@avancecorp.pe',
}

export type IdentidadPdfDemo = Omit<ContratoPdfDatos, 'contrato'>

/** Identidad legal estable por cliente; los términos nacen recién del formulario confirmado. */
export const IDENTIDADES_PDF_DEMO: Record<string, IdentidadPdfDemo> = Object.fromEntries(
  Object.entries(DETALLES_CLIENTES_DEMO).map(([clienteId, cliente]) => {
    if (!cliente.dni || !cliente.correo) {
      throw new Error(`Fixture legal incompleto para ${clienteId}`)
    }
    return [clienteId, {
      titular: {
        nombreCompleto: cliente.nombre_completo,
        tipoDocumento: cliente.tipo_documento,
        documento: cliente.dni,
        domicilio: DOMICILIOS_PDF_DEMO[clienteId] ?? 'Domicilio ficticio, Lima, Perú',
        correo: cliente.correo,
      },
      analista: ANALISTA_PDF_DEMO,
      cotitulares: [],
    } satisfies IdentidadPdfDemo]
  }),
)

function crearDatosPdfDemo(contrato: ContratoRow): ContratoPdfDatos {
  const identidad = IDENTIDADES_PDF_DEMO[contrato.cliente_id]
  if (!identidad) {
    throw new Error(`Fixture legal incompleto para ${contrato.numero_contrato}`)
  }
  return {
    contrato: {
      numero: contrato.numero_contrato,
      capital: contrato.capital,
      moneda: contrato.moneda,
      porcentaje: contrato.tasa_anual,
      fechaInicio: contrato.fecha_inicio,
      fechaVencimiento: contrato.fecha_vencimiento,
    },
    titular: identidad.titular,
    analista: identidad.analista,
    cotitulares: (TITULARES_DEMO[contrato.id] ?? []).map((titular) => ({
      nombreCompleto: titular.nombre_completo,
      tipoDocumento: titular.tipo_documento,
      documento: titular.documento,
    })),
  }
}

export const DATOS_PDF_DEMO: Record<string, ContratoPdfDatos> = Object.fromEntries(
  CONTRATOS_DEMO.map((contrato) => [contrato.id, crearDatosPdfDemo(contrato)]),
)
