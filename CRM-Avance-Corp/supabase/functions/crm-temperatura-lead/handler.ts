// Núcleo verificable sin red ni credenciales de la temperatura del lead.
// Toma leads pendientes, le pregunta al modelo externo qué tan cerca está cada
// persona de invertir y devuelve el juicio a la base. La clave del modelo NUNCA
// pasa por aquí: `preguntar` llega ya construida desde `index.ts`.
type Json = Record<string, unknown>;

export type Tomada = { lead_id: string; historial: string | null; reserva: string };
export type Juicio = {
  nivel: number;
  probabilidades: Record<string, number>;
  confianza: number;
  modelo: string;
};
export type Dependencias = {
  configurado: boolean;
  verificarCron: (firma: string, instante: string) => Promise<boolean>;
  tomar: (limite: number) => Promise<Tomada[]>;
  confirmar: (
    leadId: string,
    reserva: string,
    juicio: Juicio | null,
    huella: string | null,
    error: string | null,
  ) => Promise<unknown>;
  preguntar: (historial: string) => Promise<Juicio>;
  huella: (texto: string) => Promise<string>;
  lote?: number;
};

/** Los CUATRO niveles tal y como se midieron el 20/09 (AUC 0.84 sobre 45 leads
 *  reales). Cambiarlos invalida la medición: se vuelve a medir antes de tocarlos. */
export const NIVELES: readonly string[] = [
  'Nunca se logro hablar con la persona, o dijo que no le interesa invertir, o el numero esta equivocado',
  'Se hablo con la persona pero no mostro interes claro ni quedo en un siguiente paso',
  'Mostro interes y quedo en algo concreto, pero todavia sin fecha ni monto',
  'Esta por cerrar: dio una fecha de visita firme, un monto, o pidio el contrato',
];

export const INSTRUCCIONES =
  'Un analista de una financiera peruana gestiona a esta persona para que invierta su dinero a plazo fijo. '
  + 'El historial son las notas que el analista escribio tras cada intento de contacto. '
  + 'Segun ese historial, que tan cerca esta esta persona de invertir?';

/** Un fallo del proveedor se resume en un código corto: nunca se guarda el
 *  cuerpo de la respuesta, que podría arrastrar la petición entera. */
export function codigoDeError(e: unknown): string {
  if (e instanceof RespuestaHttp) return `http_${e.codigo}`;
  if (e instanceof Error && e.name === 'TimeoutError') return 'timeout';
  if (e instanceof Error && e.message === 'respuesta_invalida') return 'respuesta_invalida';
  return 'error_desconocido';
}

export class RespuestaHttp extends Error {
  constructor(public codigo: number) {
    super(`http_${codigo}`);
    this.name = 'RespuestaHttp';
  }
}

/** Valida la forma de lo que devuelve el modelo antes de dejarlo entrar a la
 *  base: un `score` fuera de rango o no numérico ordenaría «Mi día» al revés. */
export function leerJuicio(cuerpo: unknown): Juicio {
  const raiz = cuerpo as { answers?: { temperatura?: Json }; model?: unknown } | null;
  const r = raiz?.answers?.temperatura;
  const nivel = r?.['score'];
  const confianza = r?.['confidence'];
  const probabilidades = r?.['probabilities'];
  if (typeof nivel !== 'number' || !Number.isFinite(nivel) || nivel < 0 || nivel > 3) {
    throw new Error('respuesta_invalida');
  }
  if (typeof confianza !== 'number' || !Number.isFinite(confianza) || confianza < 0 || confianza > 1) {
    throw new Error('respuesta_invalida');
  }
  if (typeof probabilidades !== 'object' || probabilidades === null) throw new Error('respuesta_invalida');
  const modelo = typeof raiz?.model === 'string' && raiz.model ? raiz.model : 'jev-desconocido';
  return { nivel, confianza, probabilidades: probabilidades as Record<string, number>, modelo };
}

export function crearHandler(d: Dependencias) {
  return async (req: Request): Promise<Response> => {
    const headers = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' };
    const respuesta = (estado: number, cuerpo: Json) =>
      new Response(JSON.stringify(cuerpo), { status: estado, headers });
    if (req.method !== 'POST') return respuesta(405, { error: 'Método no admitido' });

    const firma = req.headers.get('x-cron-firma');
    const instante = req.headers.get('x-cron-instante');
    if (!firma || !instante || !await d.verificarCron(firma, instante)) {
      return respuesta(401, { error: 'No autorizado' });
    }
    // Sin clave configurada no se toma nada: la cola espera intacta en vez de
    // quemar los ocho intentos de cada lead contra un 401 del proveedor.
    if (!d.configurado) return respuesta(200, { procesados: 0, motivo: 'sin_configurar' });

    const pendientes = await d.tomar(d.lote ?? 10);
    let listos = 0;
    let fallidos = 0;
    for (const p of pendientes) {
      const historial = (p.historial ?? '').trim();
      if (!historial) {
        await d.confirmar(p.lead_id, p.reserva, null, null, 'sin_historial');
        fallidos += 1;
        continue;
      }
      try {
        const juicio = await d.preguntar(historial);
        await d.confirmar(p.lead_id, p.reserva, juicio, await d.huella(historial), null);
        listos += 1;
      } catch (e) {
        await d.confirmar(p.lead_id, p.reserva, null, null, codigoDeError(e));
        fallidos += 1;
      }
    }
    return respuesta(200, { procesados: pendientes.length, listos, fallidos });
  };
}
