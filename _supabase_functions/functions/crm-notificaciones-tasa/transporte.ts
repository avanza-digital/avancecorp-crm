import webpush from 'npm:web-push@3.6.7';
import { endpointValido, type Suscripcion } from './handler.ts';

export function crearTransporte(
  vapid: { subject: string; publicKey: string; privateKey: string },
  solicitar: typeof fetch = fetch,
) {
  return async (s: Suscripcion, mensaje: Record<string, unknown>, ttl: number, tema: string): Promise<number> => {
    if (!endpointValido(s.endpoint)) throw new Error('Destino inválido');
    const peticion = webpush.generateRequestDetails({
      endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth },
    }, JSON.stringify(mensaje), { vapidDetails: vapid, TTL: ttl, topic: tema, urgency: 'high' });
    const respuesta = await solicitar(peticion.endpoint, {
      method: 'POST', headers: peticion.headers, body: peticion.body,
      redirect: 'error', signal: AbortSignal.timeout(8000),
    });
    await respuesta.body?.cancel();
    return respuesta.status;
  };
}
