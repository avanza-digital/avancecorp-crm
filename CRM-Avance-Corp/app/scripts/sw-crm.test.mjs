import { readFileSync } from 'node:fs'
import vm from 'node:vm'
import test from 'node:test'
import assert from 'node:assert/strict'
const fuente = readFileSync(new URL('../public/sw-crm.js', import.meta.url), 'utf8')
function banco(ventanas = [], permitido = true, fallo = '') {
  const eventos = {}; const avisos = []; const abiertas = []
  let bajas = 0
  const datos = new Map([['/__crm_push_habilitado', new Response(permitido ? '1' : '0')]])
  if (fallo === 'json') datos.set('/__crm_push_recibidos', new Response('json roto'))
  const contexto = { URL, Response, caches: { open: async () => { if (fallo === 'cache') throw new Error('almacenamiento bloqueado'); return {
    match: async clave => datos.get(clave)?.clone(), put: async (clave, valor) => { datos.set(clave, valor) },
  } } }, self: { location: { origin: 'https://crm.miavance.com' },
    addEventListener: (nombre, handler) => { eventos[nombre] = handler },
    registration: { showNotification: async (...args) => { avisos.push(args) }, pushManager: { getSubscription: async () => ({ unsubscribe: async () => { bajas++; return true } }) } },
    clients: { claim: async () => {}, matchAll: async () => ventanas, openWindow: async url => { abiertas.push(url) } }, skipWaiting: async () => {},
  } }
  vm.runInNewContext(fuente, contexto)
  const emitir = async (nombre, contenido) => {
    let pendiente; eventos[nombre]({ ...contenido, waitUntil: tarea => { pendiente = tarea } }); await pendiente
  }
  return { eventos, avisos, abiertas, emitir, bajas: () => bajas }
}
test('el worker no intercepta peticiones de red', () => {
  assert.deepEqual(Object.keys(banco().eventos).sort(), ['activate', 'install', 'notificationclick', 'push'])
})
test('un reintento reemplaza el mismo aviso sin sonido y cumple userVisibleOnly', async () => {
  const b = banco(); const id = 'd7100000-0000-4000-8000-000000000001'
  for (let i = 0; i < 2; i++) await b.emitir('push', { data: { json: () => ({ solicitudId: id, title: 'TITULO EXTERNO', body: 'DNI 12345678' }) } })
  assert.equal(b.avisos.length, 2)
  assert.equal(b.avisos[0][1].tag, `tasa-${id}`)
  assert.equal(b.avisos[0][1].tag, b.avisos[1][1].tag)
  assert.equal(b.avisos[1][1].silent, true)
  assert.equal(b.avisos[0][1].renotify, false)
  assert.ok(!JSON.stringify(b.avisos).includes('12345678'))
})
test('un aviso en tránsito después de salir solo informa la baja y retira la suscripción', async () => {
  const b = banco([], false)
  await b.emitir('push', { data: { json: () => ({ solicitudId: 'd7100000-0000-4000-8000-000000000001' }) } })
  assert.equal(b.avisos.length, 1)
  assert.equal(b.avisos[0][0], 'CRM Avance Corp')
  assert.equal(b.avisos[0][1].data.solicitudId, null)
  assert.equal(b.bajas(), 1)
})
test('un fallo del almacenamiento conserva un aviso visible sin revelar actividad del CRM', async () => {
  const b = banco([], true, 'cache')
  await b.emitir('push', { data: { json: () => ({ solicitudId: 'd7100000-0000-4000-8000-000000000001' }) } })
  assert.equal(b.avisos[0][0], 'CRM Avance Corp')
  assert.equal(b.avisos[0][1].data.solicitudId, null)
})
test('un registro de repetidos dañado no oculta una solicitud nueva', async () => {
  const b = banco([], true, 'json')
  await b.emitir('push', { data: { json: () => ({ solicitudId: 'd7100000-0000-4000-8000-000000000001' }) } })
  assert.equal(b.avisos[0][0], 'Nueva solicitud de tasa')
})
test('clic reconstruye una ruta interna y no acepta URLs del mensaje', async () => {
  const b = banco(); const id = 'd7100000-0000-4000-8000-000000000001'
  await b.emitir('notificationclick', { notification: { close() {}, data: { solicitudId: id, url: 'https://evil.invalid' } } })
  assert.deepEqual(b.abiertas, [`https://crm.miavance.com/#/hoy/solicitud-tasa/${id}`])
})
test('si una ventana desaparece durante el clic abre otra', async () => {
  const b = banco([{ url: 'https://crm.miavance.com/#/hoy', focus: async () => { throw new Error('cerrada') } }])
  await b.emitir('notificationclick', { notification: { close() {}, data: { solicitudId: 'https://evil.invalid' } } })
  assert.deepEqual(b.abiertas, ['https://crm.miavance.com/#/hoy'])
})
test('el clic conserva un formulario abierto en otra pestaña', async () => {
  let navegaciones = 0
  const b = banco([{ url: 'https://crm.miavance.com/#/leads/123', navigate: async () => { navegaciones++ } }])
  await b.emitir('notificationclick', { notification: { close() {}, data: { solicitudId: 'd7100000-0000-4000-8000-000000000001' } } })
  assert.equal(navegaciones, 0)
  assert.equal(b.abiertas.length, 1)
})
