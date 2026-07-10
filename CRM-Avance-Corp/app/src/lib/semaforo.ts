// lib/semaforo.ts — Paleta ÚNICA del semáforo comercial (sin verde en el
// chrome; navy queda reservado a ganado/convertido). Fuente única: ninguna
// pantalla debe redeclarar estos hex ni renombrarlos (OK vs AZUL divergían).
export const SEMAFORO = {
  ok: '#2563eb', // azul — en buen camino
  atencion: '#d97706', // ámbar — atención
  critico: '#dc2626', // rojo — crítico
  navy: '#111e3d', // ganado/convertido
  violeta: '#7c3aed', // acento (reunión agendada, podios)
} as const

/** Severidad de la cola de acción → color (rojo crítico · ámbar · azul). */
export const SEV_COLOR: Record<'critica' | 'media' | 'baja', string> = {
  critica: SEMAFORO.critico,
  media: SEMAFORO.atencion,
  baja: SEMAFORO.ok,
}
