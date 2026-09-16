---
tags: [crm, analistas, tasas, notificaciones, jornada]
actualizado: 2026-09-16
---

# Solicitudes de tasa: rechazos solo en notificaciones

## Decisión de Miguel

Miguel mostró dos rechazos del 11/09 que seguían ocupando «Mi jornada» el 16/09.
El panel incluía deliberadamente rechazos de los últimos siete días, incluso
después de leer la respuesta. Aprobó retirarlos del recuadro y conservarlos como
notificaciones en la campana.

«Tus solicitudes de tasa» queda reservado para solicitudes propias y vigentes:
pendientes de Gerencia, topes por aceptar y autorizaciones pendientes de utilizar.
Si no hay solicitudes en curso, el recuadro desaparece. Al responder la última,
se conserva un anuncio accesible y el foco de teclado, sin una tarjeta vacía.

## Implementación local

- `CRM-Avance-Corp/app/src/screens/hoy/tasas-autorizadas-analista.tsx` consulta
  `ESTADOS_SOLICITUD_TASA_VIVOS` y filtra también por estado efectivo, vigencia
  y pertenencia antes de presentar las tarjetas.
- La campana mantiene su consulta independiente, avisos, sonido y lectura.
  Las respuestas terminales siguen consultables durante los últimos siete días;
  la lectura se conserva por cuenta y navegador, como antes.
- Los formularios conservan el contexto del rechazo para volver a solicitar una
  tasa. No se modificaron reglas de rentabilidad, contratos, SQL ni permisos.
- Se actualizaron las pruebas existentes del panel para rechazos, solicitudes
  activas, ausencia de tarjeta y conservación del foco al resolver la última.

## Verificación del 16/09

- **PASS:** 19 pruebas específicas del panel, registro de respuestas y proveedor.
- **PASS:** `npm run check`, 248 archivos / 3.659 pruebas con cobertura; lint,
  TypeScript, configuración de release, service worker, build, bundle y duplicación.
- **PASS:** `npm run test:e2e -- e2e/respuestas-tasa.spec.ts`, cuatro recorridos
  Chromium: aprobación, rechazo/tope, lectura, sonido, dos pestañas, permiso
  denegado, caída de red y salida de sesión. Backend y notificación del sistema
  simulados; no acredita recepción física en la PC del analista.
- **NOT RUN:** `npm run gate:realidad` no inició sus lecturas: falta
  `SUPABASE_URL` en la sesión (salida 2). No se declara comprobación productiva.
- Cambio local de presentación, LEVEL 1; sin revisión secundaria.

## Estado de entrega

Implementado y verificado en el árbol local existente. **Sin publicar.**
La publicación requiere la invocación humana de `$release-crm` o `/release-crm`
según `CRM-Avance-Corp/CLAUDE.md`, más la integración y verificación de Main
contra `avancecorp/main`. No se creó rama ni worktree para este ajuste.

Relacionadas: [[Alertas de respuestas de tasa para analistas - 2026-09-11]],
[[Notificaciones de tasa - publicadas 2026-09-11]], [[Inicio]].
