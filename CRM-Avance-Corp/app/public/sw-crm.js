/* Solo notificaciones. Guarda un interruptor y hasta 100 UUID para evitar
   avisos repetidos. No intercepta peticiones ni guarda fichas o datos personales. */
const UUID_TASA = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
let entregaPendiente = Promise.resolve()
self.addEventListener('install', evento => evento.waitUntil(self.skipWaiting()))
self.addEventListener('activate', evento => evento.waitUntil(self.clients.claim()))
self.addEventListener('push', evento => {
  let datos = {}
  try { datos = evento.data?.json() ?? {} } catch { /* Mensaje sin datos: aviso genérico visible. */ }
  const id = typeof datos.solicitudId === 'string' && UUID_TASA.test(datos.solicitudId) ? datos.solicitudId : null
  const prueba = !id && datos.tag === 'tasa-prueba'
  entregaPendiente = entregaPendiente.catch(() => {}).then(async () => {
    let cache
    let permitido = false
    try {
      cache = await caches.open('crm-push-tasa-control-v1')
      const permiso = await cache.match('/__crm_push_habilitado')
      permitido = !!permiso && await permiso.text() === '1'
    } catch { /* Sin estado local comprobable no se revela una solicitud. */ }
    if (!permitido) {
      // Safari exige un aviso visible por cada push. Uno que ya estaba en
      // tránsito al salir solo muestra la baja, sin revelar actividad del CRM.
      await self.registration.showNotification('CRM Avance Corp', {
        body: 'Los avisos de tasa están desactivados en este dispositivo. Abre el CRM para revisarlos.',
        icon: '/brand/avance-icon-192.png', tag: 'crm-avisos-desactivados', silent: true,
        data: { solicitudId: null },
      })
      try { await (await self.registration.pushManager.getSubscription())?.unsubscribe() } catch { /* Se reintenta también al entrar. */ }
      return
    }
    let recibidos = []
    try {
      const registro = await cache.match('/__crm_push_recibidos')
      const datos = registro ? await registro.json() : []
      if (Array.isArray(datos)) recibidos = datos.filter(v => typeof v === 'string' && UUID_TASA.test(v)).slice(-100)
    } catch { /* Un registro dañado no impide mostrar el aviso. */ }
    const repetido = !!id && recibidos.includes(id)
    await self.registration.showNotification(prueba ? 'Avisos de tasa activados' : 'Nueva solicitud de tasa', {
    body: prueba ? 'Este teléfono puede recibir tus solicitudes de tasa.' : 'Tienes una solicitud pendiente de aprobación. Toca para revisarla.',
    icon: '/brand/avance-icon-192.png',
    badge: '/brand/avance-icon-192.png',
    tag: id ? `tasa-${id}` : 'tasa-prueba',
    renotify: false,
    ...(repetido ? { silent: true } : {}),
    data: { solicitudId: id },
    })
    if (id) try { await cache.put('/__crm_push_recibidos', new Response(JSON.stringify([...recibidos.filter(v => v !== id).slice(-99), id]))) } catch { /* Ya se mostró el aviso. */ }
  })
  evento.waitUntil(entregaPendiente)
})
self.addEventListener('notificationclick', evento => {
  evento.notification.close()
  const id = evento.notification.data?.solicitudId
  const ruta = typeof id === 'string' && UUID_TASA.test(id) ? `/#/hoy/solicitud-tasa/${id}` : '/#/hoy'
  const destino = new URL(ruta, self.location.origin).href
  evento.waitUntil((async () => {
    const ventanas = await self.clients.matchAll({ type: 'window', includeUncontrolled: true })
    // Reutiliza solo la misma solicitud; conserva formularios abiertos en otras pestañas.
    const existente = ventanas.find(ventana => ventana.url === destino)
    if (existente) {
      try {
        await existente.focus(); return
      } catch { /* Una ventana que acaba de cerrarse no impide abrir la solicitud. */ }
    }
    await self.clients.openWindow(destino)
  })())
})
