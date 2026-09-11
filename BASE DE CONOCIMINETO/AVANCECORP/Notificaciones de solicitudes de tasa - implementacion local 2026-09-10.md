---
tags: [crm, pwa, notificaciones, tasas, pendiente-publicacion]
actualizado: 2026-09-11
---

# Notificaciones de solicitudes de tasa — implementación local

Miguel pidió recibir avisos en su teléfono, donde ya instaló el CRM como PWA,
y solicitó expresamente ayuda de Claude para reducir errores. La implementación
está en el checkout aislado `/private/tmp/avancecorp-tasa-lead-real-20260908`,
separada del trabajo F7. **PUBLICADA Y ACTIVADA el 11/09/2026**; estado vigente
en [[Notificaciones de tasa - publicadas 2026-09-11]]. Los apartados posteriores
conservan el historial de preparación y pausas.

Gerencia puede activar, probar y desactivar cada dispositivo desde Hoy o
Configuración. Las solicitudes nuevas desde lead o cliente generan avisos sin
nombre, documento, dinero ni tasa en la pantalla bloqueada. El enlace conserva
la solicitud al iniciar sesión y la enfoca cuando termina el splash.

El servidor comprueba rol/perfil/sesión y vigencia de la solicitud. Usa cola
persistente, reintentos y reservas; el cron despierta cada minuto. Un fallo de
notificación no bloquea al analista. No hay envío retrospectivo al activar un
teléfono. La baja se intenta localmente y en servidor, con reintento al entrar.

Claude entregó dos reviews `CHANGES_REQUESTED`; Codex evaluó y corrigió los
hallazgos. No se presenta como PASS de Claude. Las pruebas cubren fallos de la
cola, cierre de sesión, permisos, concurrencia, firma del cron, duplicados y
navegación. Safari exige mostrar cada push: los duplicados usan el mismo tag sin
sonido y un mensaje en tránsito después de salir solo muestra la baja.

Hallazgo duradero: `net.http_request_queue` tiene SELECT para roles de API a nivel
SQL, aunque `net` no se expone en PostgREST. `postgres` no puede revocarlo por ser
propiedad de `supabase_admin`. Por eso el cron nuevo usa HMAC temporal, exclusivo
de este servicio/proyecto, y nunca copia el secreto de Vault a las cabeceras.
No se cambiaron permisos de net ni objetos public. Los tres secretos VAPID ya
existen; solo se comprobaron sus nombres, no se leyeron valores.

Paquete canónico:
`CRM-Avance-Corp/supabase/scripts/push-tasa/README.md`.
SQL pendiente: `20260910225540_crm_notificaciones_push_tasa.sql` y
`supabase/scripts/push-tasa/activar-produccion.sql`. Falta aprobación de esos
archivos, banco gestionado/advisors, publicación desde main verificado y la
prueba de entrega real en el teléfono de Miguel.

Pausa solicitada por Miguel el 2026-09-10 para continuar mañana. El avance queda
guardado en un commit local, con los checks locales completos y la evidencia
en el paquete canónico. No se hace push ni se modifica producción durante esta
pausa. Retomar desde la revisión y autorización de los dos archivos SQL, luego
validar en un banco gestionado y preparar la publicación desde main verificado.

Reanudación del 2026-09-11: Miguel indicó «sigamos». Se integraron los cambios
remotos hasta `4febe47` sobre el commit de pausa `25c6fd5`; solo hubo un conflicto
documental, resuelto conservando ambos avances. Pasaron 3.266 pruebas y el build.
El navegador completo registró 163 PASS, 26 SKIP y un fallo intermitente de foco
en F6; el caso aislado y las once pruebas conjuntas F6/push pasaron después sin
cambios. No se declara corregido ese fallo ni aprobado el gate completo.
Evidencia y pendientes actualizados en `supabase/scripts/push-tasa/VERIFICACION.md`.
El SQL exacto conserva sus hashes; autorización, organización/coste del banco
temporal y publicación siguen pendientes. Producción continúa sin push de tasa.

Después de esa preparación Miguel respondió «siii» y autorizó expresamente los
dos SQL enlazados y la organización `AVANCECORP- CRM-PORTAL`. No volver a pedir
aprobación de esos archivos mientras conserven sus hashes. Se consultó el coste
real del banco: US$0,01344/hora; su confirmación se pidió y sigue pendiente.
Se reprodujo el fallo de Escape en F6 (5 de 8 ensayos y 3 de 4 con registro de
capas): la ficha inferior recibía la tecla aunque el foco estaba en el modal.
La corrección conserva la ficha y entrega esa tecla al modal; pasaron ocho
ensayos después y cinco pruebas de foco. Gate completo posterior PASS: 3.268
pruebas, build y 164 recorridos de navegador; 26 omisiones ya configuradas.
La instrumentación temporal se retiró y se conservó la evidencia del fallo y
de su corrección. La siguiente acción depende únicamente de confirmar el coste
del banco y ejecutar los gates remotos; no volver a pedir los dos SQL aprobados.

Relacionadas: [[Solicitud de tasa en el lead - publicada 2026-09-09]],
[[Notificaciones de pagos]], [[Arquitectura del portal]],
[[Main unico - sincronizacion y publicacion 2026-09-04]].

## Banco remoto autorizado el 11 de septiembre

Miguel confirmó «sii hazlo» para el coste de US$0,01344/hora y eliminación al
terminar. Banco exclusivo: `push-tasa-20260911`, proyecto `pdummdtfablfkdgrmauo`,
ID `d57f0619-4722-4d6a-a4a2-efc5ff131a53`. Creado a las 16:44 UTC. El historial
antiguo volvió a fallar durante el arranque; se reconstruye este banco vacío
con la estructura e historial vigentes, sin usuarios ni filas de negocio reales.
La rama `banco-f7` pertenece a otro trabajo y no se modifica. Los dos SQL y el
coste ya están autorizados; no hace falta pedirlos nuevamente.


Ensayo gestionado completado el 11/09: SQL 48, concurrencia 3, HTTP/Auth 19 y
cron real PASS con destinos ficticios. Matriz global: 50 fallos previos y 46
posteriores, sin aserciones nuevas fallidas; variación del candidato de referidos
registrada en el paquete, sin declarar PASS global. Advisors y tipos verificados.
Integración `321a0ee` con Facturación: 3.303 pruebas y 164 E2E PASS, 26 SKIP.
Publicación preparada desde main verificado; falta la prueba física en la PWA.
