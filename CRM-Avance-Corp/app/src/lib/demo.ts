// Datos DEMO para explorar la interfaz sin backend (mientras F0 no está aplicada
// o para mostrar el CRM sin tocar datos reales). Se activan desde el login.
// El store (lib/store.tsx) siembra desde aquí y persiste en sessionStorage.
//
// F1c: ~20 leads con volumen para los 3 vendedores, parkeados con
// asignado_supervisor_id (bandeja del supervisor) y actividades escalonadas
// (0.2–10 días) para que colaDe/estancados/semáforos (lib/inteligencia.ts)
// produzcan señal en TODOS los roles. La cola y el ranking ya NO viven aquí:
// se computan con colaDe() y metricasPorVendedor().
import type { Actividad, Lead, Miembro, Tarea } from './tipos'
import {
  agregarCumplimientos,
  agregarObjetivos,
  periodoLima,
  type CumplimientoMetasJerarquico,
  type CumplimientoVendedor,
  type ObjetivoVendedor,
  type ObjetivosJerarquicos,
} from './objetivos'

export const EQUIPO_DEMO: Miembro[] = [
  { perfil_id: 'd-ger', nombre_completo: 'GERENCIA DEMO', rol_crm: 'gerencia', supervisor_id: null, activo: true },
  { perfil_id: 'd-sup1', nombre_completo: 'SUPERVISOR UNO', rol_crm: 'supervisor', supervisor_id: null, activo: true },
  { perfil_id: 'd-sup2', nombre_completo: 'SUPERVISOR DOS', rol_crm: 'supervisor', supervisor_id: null, activo: true },
  { perfil_id: 'd-v1', nombre_completo: 'VENDEDOR UNO', rol_crm: 'vendedor', supervisor_id: 'd-sup1', activo: true },
  { perfil_id: 'd-v2', nombre_completo: 'VENDEDOR DOS', rol_crm: 'vendedor', supervisor_id: 'd-sup1', activo: true },
  { perfil_id: 'd-v3', nombre_completo: 'VENDEDOR TRES', rol_crm: 'vendedor', supervisor_id: 'd-sup2', activo: true },
]

/** ISO de hace N días (acepta fracciones: hace(0.5) = hace 12 h). */
export const hace = (dias: number) => new Date(Date.now() - dias * 86_400_000).toISOString()

// 20 leads. Teléfonos ÚNICOS +519########, DNIs únicos de 8 dígitos.
// Reparto: d-v1 → l1,l2,l8,l9,l12,l15,l16,l17 · d-v2 → l3,l6,l10,l18,l19 ·
// d-v3 → l4,l7,l13,l20 · parkeados (vendedor_id null): l5,l11 → d-sup1 y l14 → d-sup2.
// Señal esperada de la cola (ver reglas en lib/inteligencia.ts):
//   sin_responder: l15 (1.4d), l18 (2.2d) — nuevos SIN actividad
//   propuesta_sin_respuesta: l17 (6d), l4 (6d) — propuesta sin movimiento ≥5d
//   seguimiento: l16 (4d), l3 (3.4d), l20 (8d) — contactado/reunión sin act ≥3d
//   por_repartir: l5, l11, l14 — parkeados en bandeja de supervisor
//   estancados (≥7d): l20 (8d), l14 (7.2d)
export const LEADS_DEMO: Lead[] = [
  // ── VENDEDOR UNO (d-v1) ── 6 abiertos · 1 convertido · 1 descartado
  { id: 'l1', genero: 'M', nombre_completo: 'JUAN PÉREZ ROJAS', telefono: '+51987654321', etapa: 'nuevo', origen: 'referido', monto_estimado: 15000, moneda: 'PEN', categoria_interes: 'nuevo', vendedor_id: 'd-v1', vendedor_nombre: 'VENDEDOR UNO', creado_en: hace(0.3), activo: true, distrito: 'Miraflores', nota: 'Referido por PEDRO SÁNCHEZ VEGA' },
  { id: 'l2', genero: 'F', nombre_completo: 'MARÍA LÓPEZ CASTRO', telefono: '+51987654322', correo: 'maria.lopez@gmail.com', etapa: 'contactado', origen: 'landing', monto_estimado: 30000, moneda: 'PEN', categoria_interes: 'nuevo', vendedor_id: 'd-v1', vendedor_nombre: 'VENDEDOR UNO', creado_en: hace(2), activo: true, dni: '45871236', distrito: 'San Isidro' },
  { id: 'l8', genero: 'F', nombre_completo: 'ELENA VARGAS RÍOS', telefono: '+51987654328', etapa: 'descartado', origen: 'web', monto_estimado: 5000, moneda: 'PEN', categoria_interes: null, vendedor_id: 'd-v1', vendedor_nombre: 'VENDEDOR UNO', creado_en: hace(9), activo: true, motivo_descarte: 'sin_fondos', nota: 'Retomará en unos meses, cuando venda un terreno' },
  { id: 'l9', genero: 'M', nombre_completo: 'JORGE CHÁVEZ PAREDES', telefono: '+51998812345', correo: 'jchavezp@outlook.com', etapa: 'convertido', origen: 'referido', monto_estimado: 25000, moneda: 'USD', categoria_interes: 'renovacion', vendedor_id: 'd-v1', vendedor_nombre: 'VENDEDOR UNO', creado_en: hace(18), activo: true, dni: '41236587', distrito: 'San Borja' },
  { id: 'l12', genero: 'F', nombre_completo: 'PATRICIA FERNÁNDEZ SOTO', telefono: '+51954321876', correo: 'pfernandezsoto@gmail.com', etapa: 'propuesta_enviada', origen: 'formulario', monto_estimado: 15000, moneda: 'USD', categoria_interes: 'upgrade', vendedor_id: 'd-v1', vendedor_nombre: 'VENDEDOR UNO', creado_en: hace(5), activo: true, dni: '46752198', nota: 'Evalúa la propuesta en dólares con su esposo' },
  { id: 'l15', genero: 'F', nombre_completo: 'TERESA GONZALES PAZ', telefono: '+51911223344', etapa: 'nuevo', origen: 'landing', monto_estimado: 20000, moneda: 'PEN', categoria_interes: 'nuevo', vendedor_id: 'd-v1', vendedor_nombre: 'VENDEDOR UNO', creado_en: hace(1.4), activo: true, distrito: 'Surquillo' }, // SIN actividad → sin_responder crítica
  { id: 'l16', genero: 'M', nombre_completo: 'FERNANDO QUIROZ BEDOYA', telefono: '+51922334455', correo: 'fquirozb@gmail.com', etapa: 'contactado', origen: 'campania', monto_estimado: 45000, moneda: 'PEN', categoria_interes: 'renovacion', vendedor_id: 'd-v1', vendedor_nombre: 'VENDEDOR UNO', creado_en: hace(6), activo: true, dni: '42718395' }, // última act hace 4d → seguimiento
  { id: 'l17', genero: 'F', nombre_completo: 'GLORIA NAVARRO IBÁÑEZ', telefono: '+51933445566', etapa: 'propuesta_enviada', origen: 'referido', monto_estimado: 65000, moneda: 'PEN', categoria_interes: 'nuevo', vendedor_id: 'd-v1', vendedor_nombre: 'VENDEDOR UNO', creado_en: hace(9), activo: true, dni: '44561287', distrito: 'San Miguel', nota: 'Pidió tiempo para revisar la propuesta con su contador' }, // última act hace 6d → propuesta_sin_respuesta

  // ── VENDEDOR DOS (d-v2) ── 3 abiertos · 1 convertido · 1 descartado
  { id: 'l3', genero: 'M', nombre_completo: 'CARLOS RUIZ MENDOZA', telefono: '+51987654323', etapa: 'reunion_agendada', origen: 'oficina', monto_estimado: 10000, moneda: 'USD', categoria_interes: 'upgrade', vendedor_id: 'd-v2', vendedor_nombre: 'VENDEDOR DOS', creado_en: hace(4), activo: true, dni: '40125879' }, // última act hace 3.4d → seguimiento
  { id: 'l6', genero: 'F', nombre_completo: 'ROSA DÍAZ HUAMÁN', telefono: '+51987654326', etapa: 'contactado', origen: 'referido', monto_estimado: 22000, moneda: 'PEN', categoria_interes: 'nuevo', vendedor_id: 'd-v2', vendedor_nombre: 'VENDEDOR DOS', creado_en: hace(3), activo: true, distrito: 'La Molina' },
  { id: 'l10', genero: 'F', nombre_completo: 'CARMEN SALAZAR TICONA', telefono: '+51976543210', etapa: 'descartado', origen: 'whatsapp', monto_estimado: 12000, moneda: 'PEN', categoria_interes: null, vendedor_id: 'd-v2', vendedor_nombre: 'VENDEDOR DOS', creado_en: hace(11), activo: true, motivo_descarte: 'no_responde' },
  { id: 'l18', genero: 'M', nombre_completo: 'OMAR VILLANUEVA REYES', telefono: '+51944556677', etapa: 'nuevo', origen: 'formulario', monto_estimado: 12000, moneda: 'PEN', categoria_interes: 'nuevo', vendedor_id: 'd-v2', vendedor_nombre: 'VENDEDOR DOS', creado_en: hace(2.2), activo: true, distrito: 'Breña' }, // SIN actividad → sin_responder crítica
  { id: 'l19', genero: 'F', nombre_completo: 'DIANA PONCE ARELLANO', telefono: '+51955667788', correo: 'dponcea@gmail.com', etapa: 'convertido', origen: 'oficina', monto_estimado: 40000, moneda: 'PEN', categoria_interes: 'nuevo', vendedor_id: 'd-v2', vendedor_nombre: 'VENDEDOR DOS', creado_en: hace(15), activo: true, dni: '40987123' },

  // ── VENDEDOR TRES (d-v3) ── 3 abiertos · 1 convertido
  { id: 'l4', genero: 'F', nombre_completo: 'ANA TORRES QUISPE', telefono: '+51987654324', correo: 'anatorresq@hotmail.com', etapa: 'propuesta_enviada', origen: 'landing', monto_estimado: 50000, moneda: 'PEN', categoria_interes: 'renovacion', vendedor_id: 'd-v3', vendedor_nombre: 'VENDEDOR TRES', creado_en: hace(8), activo: true, dni: '43619258', distrito: 'Santiago de Surco', nota: 'Cliente del portal; renueva y quiere subir el monto' }, // última act hace 6d → propuesta_sin_respuesta
  { id: 'l7', genero: 'M', nombre_completo: 'PEDRO SÁNCHEZ VEGA', telefono: '+51987654327', correo: 'psanchezv@gmail.com', etapa: 'convertido', origen: 'oficina', monto_estimado: 80000, moneda: 'PEN', categoria_interes: 'nuevo', vendedor_id: 'd-v3', vendedor_nombre: 'VENDEDOR TRES', creado_en: hace(12), activo: true, dni: '09845671', distrito: 'San Borja' },
  { id: 'l13', genero: 'M', nombre_completo: 'MIGUEL CASTILLO RAMOS', telefono: '+51943218765', etapa: 'reunion_agendada', origen: 'formulario', monto_estimado: 35000, moneda: 'PEN', categoria_interes: 'nuevo', vendedor_id: 'd-v3', vendedor_nombre: 'VENDEDOR TRES', creado_en: hace(2), activo: true, distrito: 'Jesús María' },
  { id: 'l20', genero: 'M', nombre_completo: 'HUGO ESPINOZA CÁRDENAS', telefono: '+51966778899', etapa: 'contactado', origen: 'otro', monto_estimado: 28000, moneda: 'PEN', categoria_interes: 'upgrade', vendedor_id: 'd-v3', vendedor_nombre: 'VENDEDOR TRES', creado_en: hace(10), activo: true, distrito: 'Pueblo Libre' }, // última act hace 8d → seguimiento + estancado

  // ── Parkeados (vendedor_id null) en bandeja de supervisor ──
  { id: 'l5', genero: 'M', nombre_completo: 'LUIS GARCÍA FLORES', telefono: '+51987654325', etapa: 'nuevo', origen: 'landing', monto_estimado: 1000, moneda: 'PEN', categoria_interes: null, vendedor_id: null, vendedor_nombre: null, asignado_supervisor_id: 'd-sup1', creado_en: hace(1), activo: true },
  { id: 'l11', genero: 'M', nombre_completo: 'RICARDO MAMANI CONDORI', telefono: '+51965432187', etapa: 'nuevo', origen: 'formulario', monto_estimado: 8000, moneda: 'PEN', categoria_interes: 'nuevo', vendedor_id: null, vendedor_nombre: null, asignado_supervisor_id: 'd-sup1', creado_en: hace(0.5), activo: true, distrito: 'Los Olivos' },
  { id: 'l14', genero: 'F', nombre_completo: 'SOFÍA HERRERA LUNA', telefono: '+51932187654', etapa: 'contactado', origen: 'otro', monto_estimado: 60000, moneda: 'PEN', categoria_interes: 'renovacion', vendedor_id: null, vendedor_nombre: null, asignado_supervisor_id: 'd-sup2', creado_en: hace(8), activo: true, nota: 'Contacto de feria inmobiliaria; pendiente asignar vendedor' }, // última act hace 7.2d → por_repartir + estancado
]

// Timeline demo — coherente con la etapa de cada lead y ESCALONADO (0.2–10 días
// hacia atrás en los abiertos) para alimentar colaDe/estancados/semáforos.
// Los tipos automáticos (cambio_etapa / reasignacion / conversion) son
// históricos: en runtime SOLO los emite el store al mutar.
// OJO: l5, l11, l15 y l18 NO tienen actividades a propósito (señal de cola).
export const ACTIVIDADES_DEMO: Actividad[] = [
  // l1 — nuevo (con actividad fresca → NO entra a la cola)
  { id: 'act01', lead_id: 'l1', tipo: 'nota', detalle: 'Referido por PEDRO SÁNCHEZ; llamar mañana temprano', autor_nombre: 'VENDEDOR UNO', creado_en: hace(0.1) },
  // l2 — contactado (movido hace 1.2d → fresco)
  { id: 'act02', lead_id: 'l2', tipo: 'cambio_etapa', detalle: 'Nuevo → Contactado', autor_nombre: 'VENDEDOR UNO', creado_en: hace(1.6) },
  { id: 'act03', lead_id: 'l2', tipo: 'llamada_realizada', detalle: 'Primer contacto: interesada en el fondo en soles', autor_nombre: 'VENDEDOR UNO', creado_en: hace(1.55) },
  { id: 'act04', lead_id: 'l2', tipo: 'whatsapp_enviado', detalle: 'Se envió el brochure institucional', autor_nombre: 'VENDEDOR UNO', creado_en: hace(1.2) },
  // l3 — reunión agendada, última act hace 3.4d → seguimiento
  { id: 'act05', lead_id: 'l3', tipo: 'cambio_etapa', detalle: 'Nuevo → Contactado', autor_nombre: 'VENDEDOR DOS', creado_en: hace(3.8) },
  { id: 'act06', lead_id: 'l3', tipo: 'whatsapp_recibido', detalle: 'Pidió reunión presencial en la oficina', autor_nombre: 'VENDEDOR DOS', creado_en: hace(3.6) },
  { id: 'act07', lead_id: 'l3', tipo: 'cambio_etapa', detalle: 'Contactado → Reunión agendada', autor_nombre: 'VENDEDOR DOS', creado_en: hace(3.4) },
  // l4 — propuesta enviada hace 6d sin movimiento → propuesta_sin_respuesta
  { id: 'act08', lead_id: 'l4', tipo: 'cambio_etapa', detalle: 'Nuevo → Contactado', autor_nombre: 'VENDEDOR TRES', creado_en: hace(7.5) },
  { id: 'act09', lead_id: 'l4', tipo: 'cambio_etapa', detalle: 'Contactado → Reunión agendada', autor_nombre: 'VENDEDOR TRES', creado_en: hace(7) },
  { id: 'act10', lead_id: 'l4', tipo: 'reunion_realizada', detalle: 'Reunión en oficina: renueva y quiere subir el monto', autor_nombre: 'VENDEDOR TRES', creado_en: hace(6.2) },
  { id: 'act11', lead_id: 'l4', tipo: 'cambio_etapa', detalle: 'Reunión agendada → Propuesta enviada', autor_nombre: 'VENDEDOR TRES', creado_en: hace(6) },
  // l6 — contactado hace 2.2d → todavía fresco (contraejemplo de la cola)
  { id: 'act12', lead_id: 'l6', tipo: 'llamada_no_contestada', detalle: null, autor_nombre: 'VENDEDOR DOS', creado_en: hace(2.6) },
  { id: 'act13', lead_id: 'l6', tipo: 'cambio_etapa', detalle: 'Nuevo → Contactado', autor_nombre: 'VENDEDOR DOS', creado_en: hace(2.2) },
  // l7 — convertido (histórico)
  { id: 'act14', lead_id: 'l7', tipo: 'cambio_etapa', detalle: 'Nuevo → Contactado', autor_nombre: 'VENDEDOR UNO', creado_en: hace(11) },
  { id: 'act15', lead_id: 'l7', tipo: 'reasignacion', detalle: 'VENDEDOR UNO → VENDEDOR TRES', autor_nombre: 'SUPERVISOR DOS', creado_en: hace(10.5) },
  { id: 'act16', lead_id: 'l7', tipo: 'reunion_realizada', detalle: 'Cerró condiciones: S/ 80,000 a 24 meses', autor_nombre: 'VENDEDOR TRES', creado_en: hace(9) },
  { id: 'act17', lead_id: 'l7', tipo: 'conversion', detalle: 'Contrato firmado — alta en el portal (demo)', autor_nombre: 'VENDEDOR TRES', creado_en: hace(7) },
  // l8 — descartado (sin fondos)
  { id: 'act18', lead_id: 'l8', tipo: 'cambio_etapa', detalle: 'Nuevo → Contactado', autor_nombre: 'VENDEDOR UNO', creado_en: hace(8.4) },
  { id: 'act19', lead_id: 'l8', tipo: 'llamada_realizada', detalle: 'Le interesa pero no tiene liquidez este trimestre', autor_nombre: 'VENDEDOR UNO', creado_en: hace(7.5) },
  { id: 'act20', lead_id: 'l8', tipo: 'cambio_etapa', detalle: 'Contactado → Descartado · Motivo: Sin fondos', autor_nombre: 'VENDEDOR UNO', creado_en: hace(7) },
  // l9 — convertido (histórico)
  { id: 'act21', lead_id: 'l9', tipo: 'cambio_etapa', detalle: 'Nuevo → Contactado', autor_nombre: 'VENDEDOR UNO', creado_en: hace(17) },
  { id: 'act22', lead_id: 'l9', tipo: 'reunion_realizada', detalle: 'Confirmó renovación por US$ 25,000', autor_nombre: 'VENDEDOR UNO', creado_en: hace(15.5) },
  { id: 'act23', lead_id: 'l9', tipo: 'conversion', detalle: 'Renovación US$ 25,000 confirmada (demo)', autor_nombre: 'VENDEDOR UNO', creado_en: hace(14) },
  // l10 — descartado (no responde)
  { id: 'act24', lead_id: 'l10', tipo: 'llamada_no_contestada', detalle: 'Tercer intento sin respuesta', autor_nombre: 'VENDEDOR DOS', creado_en: hace(9.5) },
  { id: 'act25', lead_id: 'l10', tipo: 'cambio_etapa', detalle: 'Nuevo → Descartado · Motivo: No responde', autor_nombre: 'VENDEDOR DOS', creado_en: hace(8.5) },
  // l12 — propuesta enviada hace 3.2d → aún NO vence (contraejemplo)
  { id: 'act26', lead_id: 'l12', tipo: 'cambio_etapa', detalle: 'Nuevo → Contactado', autor_nombre: 'VENDEDOR UNO', creado_en: hace(4.6) },
  { id: 'act27', lead_id: 'l12', tipo: 'whatsapp_enviado', detalle: 'Propuesta en USD enviada por WhatsApp y correo', autor_nombre: 'VENDEDOR UNO', creado_en: hace(3.3) },
  { id: 'act28', lead_id: 'l12', tipo: 'cambio_etapa', detalle: 'Contactado → Propuesta enviada', autor_nombre: 'VENDEDOR UNO', creado_en: hace(3.2) },
  // l13 — reunión agendada, actividad fresca
  { id: 'act29', lead_id: 'l13', tipo: 'llamada_realizada', detalle: 'Coordinó reunión para el jueves', autor_nombre: 'VENDEDOR TRES', creado_en: hace(1.5) },
  { id: 'act30', lead_id: 'l13', tipo: 'cambio_etapa', detalle: 'Nuevo → Contactado', autor_nombre: 'VENDEDOR TRES', creado_en: hace(1.45) },
  { id: 'act31', lead_id: 'l13', tipo: 'cambio_etapa', detalle: 'Contactado → Reunión agendada', autor_nombre: 'VENDEDOR TRES', creado_en: hace(0.5) },
  // l14 — parkeado de d-sup2, sin movimiento hace 7.2d → por_repartir + estancado
  { id: 'act32', lead_id: 'l14', tipo: 'cambio_etapa', detalle: 'Nuevo → Contactado', autor_nombre: 'SUPERVISOR DOS', creado_en: hace(7.5) },
  { id: 'act33', lead_id: 'l14', tipo: 'nota', detalle: 'Contacto de feria inmobiliaria; pendiente asignar vendedor', autor_nombre: 'SUPERVISOR DOS', creado_en: hace(7.2) },
  // l16 — contactado, última act hace 4d → seguimiento
  { id: 'act34', lead_id: 'l16', tipo: 'cambio_etapa', detalle: 'Nuevo → Contactado', autor_nombre: 'VENDEDOR UNO', creado_en: hace(5) },
  { id: 'act35', lead_id: 'l16', tipo: 'llamada_realizada', detalle: 'Quiere renovar; pidió simulación con el nuevo tarifario', autor_nombre: 'VENDEDOR UNO', creado_en: hace(4) },
  // l17 — propuesta enviada hace 6d sin respuesta → propuesta_sin_respuesta
  { id: 'act36', lead_id: 'l17', tipo: 'cambio_etapa', detalle: 'Nuevo → Contactado', autor_nombre: 'VENDEDOR UNO', creado_en: hace(8) },
  { id: 'act37', lead_id: 'l17', tipo: 'whatsapp_enviado', detalle: 'Propuesta de S/ 65,000 enviada por WhatsApp', autor_nombre: 'VENDEDOR UNO', creado_en: hace(6.5) },
  { id: 'act38', lead_id: 'l17', tipo: 'cambio_etapa', detalle: 'Contactado → Propuesta enviada', autor_nombre: 'VENDEDOR UNO', creado_en: hace(6) },
  // l19 — convertido (histórico)
  { id: 'act39', lead_id: 'l19', tipo: 'cambio_etapa', detalle: 'Nuevo → Contactado', autor_nombre: 'VENDEDOR DOS', creado_en: hace(14) },
  { id: 'act40', lead_id: 'l19', tipo: 'reunion_realizada', detalle: 'Firmó en oficina: S/ 40,000 a 18 meses', autor_nombre: 'VENDEDOR DOS', creado_en: hace(12) },
  { id: 'act41', lead_id: 'l19', tipo: 'conversion', detalle: 'Contrato firmado — alta en el portal (demo)', autor_nombre: 'VENDEDOR DOS', creado_en: hace(10) },
  // l20 — contactado, sin movimiento hace 8d → seguimiento + estancado
  { id: 'act42', lead_id: 'l20', tipo: 'cambio_etapa', detalle: 'Nuevo → Contactado', autor_nombre: 'VENDEDOR TRES', creado_en: hace(9) },
  { id: 'act43', lead_id: 'l20', tipo: 'llamada_realizada', detalle: 'Evalúa subir su contrato actual; quedó en avisar', autor_nombre: 'VENDEDOR TRES', creado_en: hace(8) },
]

// Tareas de agenda demo (espejo de crm.tareas) — lead_ids vigentes y con señal
// para TODOS los roles: l2/l17 son de d-v1 (la sesión demo de vendedor), l3 de
// d-v2 y l4 de d-v3. Las horas son RELATIVAS al reloj para que el semáforo demo
// siempre muestre una vencida, cosas de hoy y una de mañana.
const enHoras = (h: number) => new Date(Date.now() + h * 3_600_000).toISOString()

export const TAREAS_DEMO: Tarea[] = [
  { id: 't-d1', lead_id: 'l2', vendedor_id: 'd-v1', tipo: 'whatsapp', titulo: 'WhatsApp — MARÍA LÓPEZ CASTRO', vence_en: enHoras(-3), estado: 'pendiente', reprogramaciones: 0, activo: true, creado_en: hace(2) },
  { id: 't-d2', lead_id: 'l3', vendedor_id: 'd-v2', tipo: 'reunion', titulo: 'Reunión — CARLOS RUIZ MENDOZA', vence_en: enHoras(2), duracion_min: 60, estado: 'pendiente', reprogramaciones: 0, activo: true, creado_en: hace(3) },
  { id: 't-d3', lead_id: 'l4', vendedor_id: 'd-v3', tipo: 'llamada', titulo: 'Llamada de seguimiento — ANA TORRES', vence_en: enHoras(5), estado: 'pendiente', reprogramaciones: 1, activo: true, creado_en: hace(1) },
  { id: 't-d4', lead_id: 'l17', vendedor_id: 'd-v1', tipo: 'llamada', titulo: 'Responder propuesta — GLORIA NAVARRO', vence_en: enHoras(7), estado: 'pendiente', reprogramaciones: 0, activo: true, creado_en: hace(1) },
  { id: 't-d5', lead_id: 'l4', vendedor_id: 'd-v3', tipo: 'tarea', titulo: 'Preparar propuesta — ANA TORRES QUISPE', vence_en: enHoras(26), estado: 'pendiente', reprogramaciones: 0, activo: true, creado_en: hace(1) },
]

// SPARKS_DEMO (series de sparklines) se eliminó en F1b tanda 2 junto con
// StoreDataApi.series: no tenía consumidores. Si una pantalla vuelve a
// necesitar series en demo, el plan F1 manda un fixture RPC-shaped estático
// POR MONEDA (espejo de series_comerciales_fn), no este formato.

// Fixture explícito del modelo versionado: seis dimensiones por vendedor.
// Los agregados de supervisor/empresa se derivan igual que en producción.
function metaDemo(
  vendedorId: string,
  nombre: string,
  supervisorId: string,
  supervisorNombre: string,
  pen: readonly [number, number, number],
  usd: readonly [number, number, number],
  conversionObjetivo: number,
): ObjetivoVendedor {
  const categorias = ['nuevo', 'renovacion', 'upgrade'] as const
  return {
    vendedorId,
    nombre,
    supervisorId,
    supervisorNombre,
    conversionObjetivo,
    detalles: categorias.flatMap((categoria, indice) => [
      { categoria, moneda: 'PEN' as const, capitalObjetivo: pen[indice] ?? 0, contratosObjetivo: pen[indice] ? 1 : 0 },
      { categoria, moneda: 'USD' as const, capitalObjetivo: usd[indice] ?? 0, contratosObjetivo: usd[indice] ? 1 : 0 },
    ]),
  }
}

const METAS_VENDEDORES_DEMO = {
  'd-v1': metaDemo('d-v1', 'VENDEDOR UNO', 'd-sup1', 'SUPERVISOR UNO', [150_000, 60_000, 40_000], [25_000, 10_000, 5_000], 25),
  'd-v2': metaDemo('d-v2', 'VENDEDOR DOS', 'd-sup1', 'SUPERVISOR UNO', [180_000, 70_000, 50_000], [30_000, 12_000, 8_000], 28),
  'd-v3': metaDemo('d-v3', 'VENDEDOR TRES', 'd-sup2', 'SUPERVISOR DOS', [270_000, 110_000, 70_000], [45_000, 15_000, 10_000], 30),
} satisfies Record<string, ObjetivoVendedor>

const METAS_DEMO_FILAS = Object.values(METAS_VENDEDORES_DEMO)
export const METAS_DEMO: ObjetivosJerarquicos = {
  periodo: periodoLima(Date.now()),
  revision: 1,
  publicadaEn: '2026-08-01T14:00:00.000Z',
  vendedor: METAS_VENDEDORES_DEMO['d-v1'],
  supervisor: agregarObjetivos(METAS_DEMO_FILAS.filter((meta) => meta.supervisorId === 'd-sup1')),
  gerencia: agregarObjetivos(METAS_DEMO_FILAS),
  porVendedor: METAS_VENDEDORES_DEMO,
}

function cumplimientoDemo(
  meta: ObjetivoVendedor,
  capitalRealPen: readonly [number, number, number],
  capitalRealUsd: readonly [number, number, number],
  convertidos: number,
  resueltos: number,
): CumplimientoVendedor {
  return {
    ...meta,
    conversionReal: resueltos > 0 ? Math.round((10_000 * convertidos) / resueltos) / 100 : null,
    convertidos,
    // Mundo demo sin referidos ponderados: el numerador coincide con los
    // convertidos enteros (el mismo fallback pre-B que aplica crm-api).
    numerador: convertidos,
    resueltos,
    detalles: meta.detalles.map((detalle) => {
      const indice = ['nuevo', 'renovacion', 'upgrade'].indexOf(detalle.categoria)
      const capitalReal = detalle.moneda === 'PEN'
        ? (capitalRealPen[indice] ?? 0)
        : (capitalRealUsd[indice] ?? 0)
      const contratosReal = capitalReal > 0 ? 1 : 0
      return {
        ...detalle,
        capitalReal,
        capitalCumplimientoPct: detalle.capitalObjetivo > 0
          ? Math.round((10_000 * capitalReal) / detalle.capitalObjetivo) / 100
          : null,
        contratosReal,
        contratosCumplimientoPct: detalle.contratosObjetivo > 0
          ? Math.round((10_000 * contratosReal) / detalle.contratosObjetivo) / 100
          : null,
      }
    }),
  }
}

const CUMPLIMIENTO_VENDEDORES_DEMO = {
  'd-v1': cumplimientoDemo(METAS_VENDEDORES_DEMO['d-v1'], [120_000, 40_000, 0], [20_000, 0, 0], 3, 8),
  'd-v2': cumplimientoDemo(METAS_VENDEDORES_DEMO['d-v2'], [90_000, 50_000, 20_000], [10_000, 8_000, 0], 4, 10),
  'd-v3': cumplimientoDemo(METAS_VENDEDORES_DEMO['d-v3'], [210_000, 70_000, 50_000], [35_000, 12_000, 4_000], 5, 13),
} satisfies Record<string, CumplimientoVendedor>

const CUMPLIMIENTO_DEMO_FILAS = Object.values(CUMPLIMIENTO_VENDEDORES_DEMO)
export const CUMPLIMIENTO_METAS_DEMO: CumplimientoMetasJerarquico = {
  periodo: METAS_DEMO.periodo,
  revision: 1,
  publicadaEn: METAS_DEMO.publicadaEn,
  // El demo enseña el mes VIVO: la clave viaja y dice «sin sellar».
  cierre: { cerrado: false },
  fuentesReales: {
    capitalYContratos: 'contratos_confirmados',
    conversion: 'leads_resueltos',
  },
  vendedor: CUMPLIMIENTO_VENDEDORES_DEMO['d-v1'],
  supervisor: agregarCumplimientos(CUMPLIMIENTO_DEMO_FILAS.filter((fila) => fila.supervisorId === 'd-sup1')),
  gerencia: agregarCumplimientos(CUMPLIMIENTO_DEMO_FILAS),
  porVendedor: CUMPLIMIENTO_VENDEDORES_DEMO,
}
