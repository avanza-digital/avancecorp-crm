// Núcleo verificable sin red ni credenciales. Los mensajes no incluyen datos financieros.
type Json = Record<string, unknown>;
export type Suscripcion = { endpoint: string; p256dh: string; auth: string; solicitud_id?: string; vence_en?: string };
export type Dependencias = {
  clavePublica: string;
  configurado: boolean;
  permitirLocal?: boolean;
  verificarCron: (firma: string, instante: string) => Promise<boolean>;
  estadoUsuario: (token: string, endpoint: string | null) => Promise<unknown>;
  pruebaUsuario: (token: string, id: string) => Promise<Suscripcion>;
  tomar: () => Promise<{ id: string; reserva: string }[]>;
  materializar: (id: string, reserva: string) => Promise<Suscripcion | null>;
  confirmar: (id: string, reserva: string, resultado: string, codigo: number | null) => Promise<unknown>;
  enviar: (suscripcion: Suscripcion, mensaje: Json, ttl: number, tema: string) => Promise<number>;
  ahora?: () => number;
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function endpointValido(endpoint: string): boolean {
  try {
    const url = new URL(endpoint);
    return endpoint.length <= 2048 && !endpoint.includes('\\') && url.protocol === 'https:' && !url.username && !url.password && !url.port && !url.hash
      && /^(fcm\.googleapis\.com|([a-z0-9-]+\.)+push\.apple\.com|updates\.push\.services\.mozilla\.com|[a-z0-9-]+\.notify\.windows\.com)$/.test(url.hostname)
      && /^https:\/\/[^/]+\/[A-Za-z0-9_/?=&%+.,:~!$()*;-]+$/.test(endpoint);
  } catch { return false; }
}

export function resultadoHttp(codigo: number): string {
  if (codigo >= 200 && codigo < 300) return 'enviado';
  if (codigo === 404 || codigo === 410) return 'invalido';
  return codigo === 408 || codigo === 429 || codigo >= 500 ? 'reintentar' : 'fallido';
}

export function crearHandler(d: Dependencias) {
  return async (req: Request): Promise<Response> => {
    const origen = req.headers.get('origin');
    const origenValido = !origen || origen === 'https://crm.miavance.com'
      || (d.permitirLocal && /^http:\/\/(localhost|127\.0\.0\.1):\d+$/.test(origen));
    const headers = {
      'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Vary': 'Origin',
      ...(origen && origenValido ? { 'Access-Control-Allow-Origin': origen } : {}),
      'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-cron-firma, x-cron-instante',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
    };
    const respuesta = (estado: number, cuerpo: Json) => new Response(JSON.stringify(cuerpo), { status: estado, headers });
    if (!origenValido) return respuesta(403, { error: 'Origen no autorizado' });
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers });
    if (req.method !== 'POST') return respuesta(405, { error: 'Método no admitido' });
    let cuerpo: Json;
    try {
      const lector = req.body?.getReader();
      const partes: Uint8Array<ArrayBuffer>[] = [];
      let longitud = 0;
      if (lector) for (;;) {
        const { done, value } = await lector.read();
        if (done) break;
        longitud += value.byteLength;
        if (longitud > 4096) { await lector.cancel(); return respuesta(413, { error: 'Petición demasiado grande' }); }
        partes.push(new Uint8Array(value));
      }
      const texto = await new Blob(partes).text();
      cuerpo = JSON.parse(texto);
      if (!cuerpo || Array.isArray(cuerpo) || typeof cuerpo !== 'object') throw new Error();
    } catch { return respuesta(400, { error: 'Petición inválida' }); }
    try {
      if (cuerpo.accion === 'procesar') {
        const firma = req.headers.get('x-cron-firma');
        const instante = req.headers.get('x-cron-instante');
        if (!firma || !/^[a-f0-9]{64}$/.test(firma) || !instante || !/^\d{10}$/.test(instante)
          || !await d.verificarCron(firma, instante)) return respuesta(401, { error: 'No autorizado' });
        if (!d.configurado) return respuesta(503, { error: 'Envío todavía no disponible' });
        const lote = await d.tomar();
        let enviados = 0;
        let sinConfirmar = 0;
        // Grupos de tres: el lote completo permanece dentro de su reserva de dos minutos.
        for (let inicio = 0; inicio < lote.length; inicio += 3) {
          await Promise.all(lote.slice(inicio, inicio + 3).map(async ({ id, reserva }) => {
            let resultado = 'reintentar';
            let codigo: number | null = null;
            try {
              const s = await d.materializar(id, reserva);
              if (!s) resultado = 'cancelado';
              else if (!endpointValido(s.endpoint) || !s.solicitud_id || !UUID.test(s.solicitud_id)) resultado = 'fallido';
              else {
                const ttl = Math.min(86400, Math.floor((Date.parse(s.vence_en ?? '') - (d.ahora?.() ?? Date.now())) / 1000));
                if (!Number.isFinite(ttl) || ttl <= 0) resultado = 'cancelado';
                else {
                  codigo = await d.enviar(s, {
                    title: 'Nueva solicitud de tasa',
                    body: 'Tienes una solicitud pendiente de aprobación. Toca para revisarla.',
                    solicitudId: s.solicitud_id,
                    tag: `tasa-${s.solicitud_id}`,
                  }, ttl, s.solicitud_id.replaceAll('-', ''));
                  resultado = resultadoHttp(codigo);
                }
              }
            } catch { /* La reserva y el reintento conservan el trabajo sin exponer endpoints. */ }
            try { if (await d.confirmar(id, reserva, resultado, codigo) !== true) sinConfirmar++; }
            catch { sinConfirmar++; }
            if (resultado === 'enviado') enviados++;
          }));
        }
        return respuesta(sinConfirmar ? 503 : 200, { procesados: lote.length, enviados, sinConfirmar });
      }
      if (cuerpo.accion !== 'configuracion' && cuerpo.accion !== 'prueba') return respuesta(400, { error: 'Acción no admitida' });
      const token = req.headers.get('authorization')?.match(/^Bearer (\S+)$/i)?.[1];
      if (!token) return respuesta(401, { error: 'Inicia sesión' });
      const endpoint = typeof cuerpo.endpoint === 'string' ? cuerpo.endpoint : null;
      if (endpoint && !endpointValido(endpoint)) return respuesta(400, { error: 'Suscripción inválida' });
      // La RPC valida la identidad, la membresía viva y auth.sessions.
      const estado = await d.estadoUsuario(token, endpoint) as Json;
      if (cuerpo.accion === 'configuracion') return respuesta(200, {
        ...estado, configurado: d.configurado && estado.configurado === true,
        clavePublica: d.clavePublica,
      });
      if (!d.configurado || estado.configurado !== true) return respuesta(503, { error: 'Envío todavía no disponible' });
      if (typeof cuerpo.dispositivoId !== 'string' || !UUID.test(cuerpo.dispositivoId)) return respuesta(400, { error: 'Dispositivo inválido' });
      const s = await d.pruebaUsuario(token, cuerpo.dispositivoId);
      if (!endpointValido(s.endpoint)) return respuesta(400, { error: 'Suscripción inválida' });
      const codigo = await d.enviar(s, {
        title: 'Avisos de tasa activados',
        body: 'Este teléfono puede recibir tus solicitudes de tasa.', tag: 'tasa-prueba',
      }, 60, 'tasa-prueba');
      return resultadoHttp(codigo) === 'enviado'
        ? respuesta(200, { enviado: true })
        : respuesta(502, { error: 'No pudimos enviar la prueba. Vuelve a activar los avisos.' });
    } catch (error) {
      const codigo = typeof error === 'object' && error ? (error as { code?: string }).code : null;
      if (codigo === '42501' || codigo === 'PGRST301' || codigo === 'PGRST303') return respuesta(403, { error: 'Tu sesión no tiene permiso para estos avisos' });
      if (codigo === 'P0429') return respuesta(429, { error: 'Espera un minuto antes de otra prueba' });
      return respuesta(503, { error: 'No pudimos conectar los avisos. Intenta nuevamente.' });
    }
  };
}
