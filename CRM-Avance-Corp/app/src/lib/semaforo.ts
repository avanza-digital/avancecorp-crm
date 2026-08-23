// lib/semaforo.ts — Paleta ÚNICA del semáforo comercial (sin verde en el
// chrome; navy queda reservado a ganado/convertido). Fuente única: ninguna
// pantalla debe redeclarar estos hex ni renombrarlos (OK vs AZUL divergían).
//
// PRESUPUESTO DE COLOR (decisión de Miguel 2026-08-23, nota del vault
// «Fundamentos UX del CRM»):
// · ROJO = requiere intervención HOY; si nadie actúa, el riesgo aumenta.
//   Máximo UN grupo rojo por tipo de decisión, siempre con una acción al lado.
// · ÁMBAR = precaución, revisión esta semana. Máximo DOS grupos ámbar
//   visibles por tarjeta; el resto se agrupa o queda tras expansión.
// · La severidad original NUNCA se rebaja: se agrupa, y el grupo hereda la
//   más alta de sus miembros.
// · AZUL = acción y continuidad (no celebra filas «al día»); VIOLETA es
//   categórico (reuniones, podios), jamás severidad; NEUTRO = sin señal.
// · El color nunca va solo: siempre acompañado de texto y forma (tira de
//   3 px, punto, chip). Lo que está al día se pinta de gris o se colapsa.
export const SEMAFORO = {
  ok: '#2563eb', // azul — en buen camino
  atencion: '#d97706', // ámbar — atención
  critico: '#dc2626', // rojo — crítico
  navy: '#111e3d', // ganado/convertido
  violeta: '#7c3aed', // acento (reunión agendada, podios)
  // Neutro: NO forma parte del semáforo, se usa para «no hay señal que medir».
  // Sin él, quien no tiene ni un lead se pinta igual que quien está al día.
  neutro: '#8b95a7',
} as const

/** Severidad de la cola de acción → color (rojo crítico · ámbar · azul). */
export const SEV_COLOR: Record<'critica' | 'media' | 'baja', string> = {
  critica: SEMAFORO.critico,
  media: SEMAFORO.atencion,
  baja: SEMAFORO.ok,
}
