---
tags: [crm, analistas, tasas, notificaciones]
actualizado: 2026-09-11
---

# Alertas de respuestas de tasa para analistas

Miguel pidió que el analista reciba una alerta en su PC con sonido cuando
Gerencia aprueba, rechaza o aprueba con un tope su solicitud. Se acordó que el
CRM permanezca abierto, aunque el analista esté trabajando en otra ventana.

## Comportamiento

- Analistas y supervisores reciben únicamente respuestas a solicitudes propias.
- Aviso emergente con un timbre breve; la campana conserva las respuestas sin leer.
- El permiso de escritorio se solicita al pulsar «Activar alertas y sonido».
  La invitación desaparece de Hoy después de configurar. Configuración conserva
  los controles para silenciar, activar/desactivar escritorio y probar la alerta.
- Abrir una respuesta muestra el detalle, tasa autorizada y motivo de Gerencia.
  No acepta topes ni realiza operaciones financieras automáticamente.
- El escritorio usa texto genérico, sin cliente, capital, tasa o motivo.
- Preferencias y lectura se guardan por cuenta y navegador. El almacenamiento
  conserva solo identificadores, fechas y marcas, nunca el detalle comercial.
- Se coordina la incorporación entre pestañas con Web Locks para emitir una sola
  alerta. Sin persistencia o coordinación, el sonido se limita a la pestaña enfocada.
- Al cerrar sesión se retiran avisos, notificaciones y audio. Una respuesta o
  permiso que termina después no puede activar avisos para otra cuenta.

## Alcance y límites

Reutiliza `crm.solicitudes_tasa_fn`, con `p_solo_mias=true`, y verifica además
`es_mia` y `solicitada_por` antes de mostrar. Consulta cada 15 segundos en todas
las pantallas, también en segundo plano; el navegador puede demorar pestañas
suspendidas. Al recuperar conexión vuelve a consultar.

La bandeja existente devuelve hasta 500 solicitudes: autorizaciones vigentes y
terminales de los últimos siete días. La primera consulta exitosa inicializa el
registro sin anunciar decisiones históricas. La interfaz informa el período y
advierte si alcanza el límite. Las marcas de lectura se conservan en esta PC;
no se sincronizan entre dispositivos. Una PC en silencio o con notificaciones
bloqueadas puede mostrar solo el aviso dentro del CRM.

No modifica SQL, RLS, contratos, reglas de rentabilidad ni el servicio push de
Gerencia. El aviso del analista requiere el CRM abierto; no se promete entrega
con el navegador cerrado. La PWA de Gerencia mantiene su envío desde el servidor.

## Verificación

- `npm run check`: PASS, 3.329 pruebas; lint, tipos, cobertura, build,
  configuración, bundle y duplicación.
- 14 pruebas específicas de dominio, audio y ciclo de sesión: PASS.
- Recorrido general Chromium: 167 PASS, 26 SKIP; un selector antiguo de campana
  falló porque ahora abre Notificaciones. Se actualizó para recorrer campana →
  otros pendientes; las 22 pruebas afectadas (respuestas, push Gerencia y SLA)
  pasaron después. No se modificaron expectativas del negocio para resolverlo.
- Claude se consultó mediante `scripts/claude-review` dos veces. Ambas agotaron
  el plazo (300 y 240 segundos) sin devolver dictamen. Revisión secundaria:
  NOT RUN / sin resultado; no se declara aprobación de Claude.

Pruebas específicas de aprobación, rechazo, tope, lotes, doble pestaña, lectura,
permiso denegado, red caída, enlace desconocido y cierre de sesión. El navegador
de pruebas usa Web Audio real instrumentado y un sustituto de la notificación
del sistema; no confirma recepción audible en el equipo físico del analista.

La comprobación productiva de solo lectura encontró 39 solicitudes, dos
pendientes y un máximo de nueve por solicitante. `gate:realidad` no pudo iniciarse
por ausencia de sus variables de entorno; no se declara PASS. No se usó
producción como banco de escritura.

Relacionadas: [[Notificaciones de tasa - publicadas 2026-09-11]],
[[Solicitud de tasa en el lead - publicada 2026-09-09]], [[Inicio]].
