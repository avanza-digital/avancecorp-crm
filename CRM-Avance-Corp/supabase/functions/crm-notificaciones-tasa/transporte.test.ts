import { strict as assert } from 'node:assert';
import { createECDH, randomBytes } from 'node:crypto';
import webpush from 'npm:web-push@3.6.7';
import { crearTransporte } from './transporte.ts';

Deno.test('cifra un Web Push real con VAPID, TTL y destino sin redirecciones', async () => {
  const servidor = webpush.generateVAPIDKeys();
  const dispositivo = createECDH('prime256v1'); dispositivo.generateKeys();
  const s = { endpoint: 'https://fcm.googleapis.com/fcm/send/banco',
    p256dh: dispositivo.getPublicKey().toString('base64url'), auth: randomBytes(16).toString('base64url') };
  let llamada = false;
  const solicitar: typeof fetch = async (entrada, opciones) => {
    llamada = true;
    assert.equal(entrada, s.endpoint); assert.equal(opciones?.redirect, 'error');
    assert.equal(opciones?.method, 'POST'); assert.ok(opciones?.signal);
    const cabeceras = new Headers(opciones?.headers);
    assert.match(cabeceras.get('authorization') ?? '', /^vapid /);
    assert.equal(cabeceras.get('TTL'), '120');
    assert.equal(cabeceras.get('Topic'), 'solicitud-sintetica');
    assert.equal(cabeceras.get('Content-Encoding'), 'aes128gcm');
    assert.ok(!new TextDecoder().decode(opciones?.body as Uint8Array).includes('MENSAJE SINTETICO'));
    return new Response(null, { status: 201 });
  };
  const enviar = crearTransporte({ ...servidor, subject: 'mailto:qa@example.invalid' }, solicitar);
  assert.equal(await enviar(s, { body: 'MENSAJE SINTETICO' }, 120, 'solicitud-sintetica'), 201);
  assert.equal(llamada, true);
});

Deno.test('el transporte rechaza destinos ajenos antes de usar claves o red', async () => {
  let llamadas = 0;
  const enviar = crearTransporte({ subject: '', publicKey: '', privateKey: '' }, async () => { llamadas++; return new Response(); });
  await assert.rejects(() => enviar({ endpoint: 'https://127.0.0.1/metadata', p256dh: '', auth: '' }, {}, 60, 'prueba'));
  assert.equal(llamadas, 0);
});
