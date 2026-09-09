import { apiUrl } from './banco-local.mjs';
import assert from 'node:assert/strict';
import { crearHandlerContratoPdfV2, normalizarUrlFirmadaV2 } from '../../functions/crm-contrato-pdf-v2/handler.ts';
import { http } from './banco-local.mjs';

// Deno expone self; el bundle vendorizado espera ese global también en este
// arnés Node. No se modifica el renderer ni su bundle de producción.
globalThis.self ??= globalThis;
const { renderizarContratoPdfV2 } = await import('../../functions/crm-contrato-pdf-v2/renderer.ts');

export const pdfBucket = 'contratos-generados';
const origen = apiUrl;
const respuestaBackend = r => r.ok ? { data: r.data, error: null } : { data: null,
  error: { ...r.data, statusCode: Number(r.data?.statusCode ?? r.status) } };
const rutaObjeto = path => `/storage/v1/object/${pdfBucket}/${path}`;

// El handler y el renderer son los archivos reales de la aplicación. Los
// adaptadores hablan por HTTP con Auth, PostgREST y Storage del banco. Los
// puntos de fallo envuelven respuestas reales sin fabricar estados en SQL.
export function pdfEnBanco(interceptar = async (_paso, ejecutar) => ejecutar(), storageReal) {
  const paso = (nombre, ejecutar) => interceptar(nombre, ejecutar);
  return crearHandlerContratoPdfV2({
    crearActor(token) {
      return {
        async verificarSesion() {
          const r = await http('/auth/v1/user', { method: 'GET', token });
          return r.ok ? { id: r.data.id } : null;
        },
        async rpc(nombre, argumentos) {
          return respuestaBackend(await http(`/rest/v1/rpc/${nombre}`, { token, body: argumentos,
            headers: { 'Content-Profile': 'crm', 'Accept-Profile': 'crm' } }));
        },
      };
    },
    async rpcAdmin(nombre, argumentos) {
      return paso(nombre, async () => respuestaBackend(await http(`/rest/v1/rpc/${nombre}`, {
        admin: true, body: argumentos, headers: { 'Content-Profile': 'crm', 'Accept-Profile': 'crm' },
      })));
    },
    renderizar(snapshot, renderizadoEn) {
      return paso('renderizar', () => renderizarContratoPdfV2(snapshot, renderizadoEn));
    },
    storage: {
      subir(path, blob) {
        return paso('subir', async () => storageReal ? storageReal.subir(path, blob) : respuestaBackend(await http(rutaObjeto(path), {
          admin: true, rawBody: blob, headers: { 'Content-Type': 'application/pdf', 'x-upsert': 'false' },
        })));
      },
      descargar(path) {
        return paso('descargar', async () => {
          if (storageReal) return storageReal.descargar(path);
          const r = await http(rutaObjeto(path), { method: 'GET', admin: true, binary: true });
          return r.ok ? { data: new Blob([r.data], { type: 'application/pdf' }), error: null }
            : { ...respuestaBackend(r), data: null };
        });
      },
      firmar(path, segundos, solicitud) {
        return paso('firmar', async () => {
          if (storageReal) return storageReal.firmar(path, segundos, solicitud);
          const r = await http(`/storage/v1/object/sign/${pdfBucket}/${path}`, {
            admin: true, body: { expiresIn: segundos },
          });
          const url = r.ok ? normalizarUrlFirmadaV2(`${origen}/storage/v1${r.data.signedURL}`, origen, path) : null;
          return { url, error: r.ok ? null : respuestaBackend(r).error };
        });
      },
      eliminar() { throw new Error('El ensayo PDF F5 no elimina contratos ni objetos'); },
    },
  });
}

export async function pedirPdf(handler, token, contratoId, action = 'ensure') {
  const r = await handler(new Request(`${origen}/functions/v1/crm-contrato-pdf-v2`, {
    method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ action, contratoId }),
  }));
  return { status: r.status, ok: r.ok, data: await r.json() };
}

export async function descargarFirmado(url) {
  const destino = new URL(url);
  assert.equal(destino.origin, origen, 'Descarga fuera del banco local');
  assert(destino.pathname.startsWith(`/storage/v1/object/sign/${pdfBucket}/`));
  const r = await fetch(destino, { signal: AbortSignal.timeout(30_000) });
  assert.equal(r.status, 200, 'Descarga firmada no disponible');
  const bytes = Buffer.from(await r.arrayBuffer());
  assert.equal(bytes.subarray(0, 5).toString(), '%PDF-');
  return bytes;
}
