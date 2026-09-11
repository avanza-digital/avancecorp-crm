---
tags: [crm, pwa, notificaciones, tasas, produccion]
actualizado: 2026-09-11
---

# Notificaciones de tasa publicadas

Objetivo de Miguel: recibir un aviso en su teléfono por cada solicitud nueva de
aprobación de tasa, aunque la PWA esté cerrada, y abrir la solicitud al tocarlo.

Migración `20260910225540`, Edge `crm-notificaciones-tasa`, controles PWA y cron
quedaron publicados y activados el 11/09/2026. Gerencia entra en Configuración →
Avisos en tu teléfono → Activar notificaciones → Permitir → Enviar prueba.
La recepción real sigue pendiente de ese gesto en el teléfono; no se activó un
dispositivo por Miguel. Los avisos no muestran datos del cliente ni importes.

48 SQL, tres carreras, 19 HTTP/Auth y cron gestionado PASS. Frontend: 3.303 pruebas
y 164 E2E PASS, 26 SKIP. La matriz global conserva deuda previa: 50 fallos antes,
46 después, sin aserciones nuevas fallidas. Dos revisiones de Claude evaluadas
y corregidas. Se conservaron banderas F3 ON/F4-F5-F6 OFF y claves VAPID.

Release válido `crm-20260911T183422Z-5d49bcfb1ac3`, commit `5d49bcf`, construido
desde main limpio e igual a `avancecorp/main`. El primer paquete omitió las
variables públicas VITE y dejó el acceso deshabilitado al cargar; se sustituyó
y se verificó la sesión Gerencia real. Ese paquete está descartado y no sirve
de rollback. Siempre validar la conexión del bundle productivo antes de publicar.

El banco exclusivo de pruebas se eliminó; el banco F7 no se tocó.
Acta canónica: `CRM-Avance-Corp/supabase/scripts/push-tasa/PUBLICACION-2026-09-11.md`.

Miguel informó que pulsó «Enviar prueba» y pidió retirar el recuadro una vez
configurado porque ocupaba espacio. El resumen oculta la invitación cuando ese
dispositivo tiene los avisos activos; Configuración conserva los controles.
Ocultar la invitación no desactiva los avisos ni cambia la suscripción.

Relacionado: [[Notificaciones de solicitudes de tasa - implementacion local 2026-09-10]],
[[Inicio]].
