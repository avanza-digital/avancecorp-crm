---
tags: [crm, rentabilidad, notificaciones, pwa]
fecha: 2026-09-10
estado: diagnostico-sin-implementacion
---

# Notificaciones de solicitudes de tasa en la PWA

Miguel preguntó si puede recibir una notificación en su teléfono por cada
solicitud de tasa. Indicó que ya tiene la aplicación instalada como PWA.
El sistema operativo del teléfono aún no está confirmado.

La bandeja del CRM consulta las solicitudes cada 45 segundos mientras está
montada (`SolicitudesTasaGerenciaPanel`). El frontend revisado no registra un
service worker ni suscripciones de Web Push. La portada productiva de
`crm.miavance.com` tiene icono para Apple, pero no declara un manifiesto web.

La inspección de metadatos de producción encontró únicamente los triggers de
auditoría y protección de escrituras en `crm.solicitudes_tasa`. Las funciones
de solicitud y resolución de tasa no referencian mecanismos de envío push.
No se modificaron datos ni se enviaron notificaciones durante el diagnóstico.

El portal tiene infraestructura de Web Push en `public.suscripciones_push`
y funciones de envío. Esto no implica que el CRM esté suscrito: se debe
preparar la recepción en su propio origen y conectar el evento de solicitud.

Propuesta: activar avisos voluntariamente en el dispositivo, enviar una
notificación por nueva solicitud que el destinatario pueda resolver y abrir
la solicitud correspondiente al tocarla. Todavía no está implementada.

Web Push permite recibir mensajes con la aplicación cerrada. En iPhone
requiere una web app añadida a la pantalla de inicio, iOS 16.4 o posterior y
permiso solicitado tras una acción del usuario.
Fuentes: [MDN](https://developer.mozilla.org/en-US/docs/Web/API/Push_API) y
[WebKit](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/).

Relacionado: [[Solicitud de tasa en el lead - publicada 2026-09-09]],
[[Notificaciones de pagos]], [[Realtime de novedades]], [[Inicio]].
