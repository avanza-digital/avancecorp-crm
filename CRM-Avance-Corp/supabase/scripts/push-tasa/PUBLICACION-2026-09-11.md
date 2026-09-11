# Notificaciones de tasa publicadas — 11/09/2026

El CRM puede avisar a Gerencia de solicitudes nuevas, con la PWA cerrada. Cada
teléfono debe activar su permiso en **Configuración → Avisos en tu teléfono →
Activar notificaciones** y pulsar **Enviar prueba**. No se activó ningún
dispositivo real durante esta publicación; la recepción física sigue **NOT RUN**.

## Publicación verificada

- Migración `20260910225540` integrada mediante merge del banco autorizado.
  Las 34 sentencias productivas coinciden literalmente y en orden con el SQL
  aprobado; solo las separan espacios y punto y coma. No se normalizó el historial.
- Las 273 entradas anteriores conservan su huella; funciones `public`, banderas
  F3 ON/F4-F5-F6 OFF y las 18 Edge anteriores permanecen iguales. No entraron
  usuarios de prueba. Las dos tablas nuevas tienen RLS cerrado.
- Edge `crm-notificaciones-tasa` activa, versión 1; tres fuentes exactas. Las 14
  huellas de secretos permanecen iguales, incluidas las tres VAPID. Supabase solo
  renovó las fechas de sus siete variables de sistema al hacer el merge.
- Frontend construido desde main limpio e igual a `avancecorp/main`, commit
  `5d49bcfb1ac304187af98fe634fd274435b06d49`.
  Release `crm-20260911T183422Z-5d49bcfb1ac3`, build `build-20260911T183417529Z`.
  ZIP SHA-256 `ec36e23284ec2397aaa1f151aac5ae1e214cb8fe93279bd8b2fa7f6eb7515fa8`.
- **PASS:** 89 archivos por HTTP. Código, CSS y archivos de configuración exactos;
  iconos PWA con dimensiones correctas. El CDN transforma imágenes anteriores,
  cuyos originales son iguales al ZIP previo. Worker, manifest y versión usan
  `no-store`. ZIP no público en CRM ni portal.
- Activación productiva ejecutada desde el SQL exacto aprobado, después de la
  comprobación del frontend. Vault apunta al proyecto correcto; cron activo cada
  minuto. Cero dispositivos y cero envíos al verificar la activación.
- **PASS en UI real:** sesión Gerencia recuperada; Configuración muestra «Avisos
  en tu teléfono» y «Activar notificaciones». No se concedió permiso en el escritorio.
- Banco exclusivo `push-tasa-20260911` eliminado y ausencia comprobada; el banco
  F7 se conserva. VAPID y Vault de prueba retirados antes del merge.

## Pruebas

**PASS:** 48 SQL remotas, tres carreras, 19 comprobaciones HTTP/Auth y cron real.
**PASS:** gate frontend completo, 3.303 pruebas y 164 E2E (26 SKIP configurados).
GitHub Actions del código probado `321a0ee` finalizó correctamente: CRM app quality
y RLS preflight. El commit de publicación agrega únicamente evidencia a ese código.

La matriz global continúa **FAIL**: 50 fallos antes y 46 después sobre 1.827
aserciones. No hay aserciones nuevas fallidas; la diferencia de un payload del
mismo fallo de referidos está explicada, con ambas salidas conservadas. No se
declara PASS global. Véase [el ensayo gestionado](BANCO-REMOTO-2026-09-11.md).
Las dos revisiones de Claude fueron evaluadas y corregidas por PRIMARY; sus
dictámenes originales siguen siendo `CHANGES_REQUESTED`.

## Incidencia del primer paquete, corregida

El primer artefacto `crm-20260911T182653Z-5d49bcfb1ac3` se construyó sin las
variables públicas VITE del checkout original. Al cargarlo, el CRM mostraba el
acceso deshabilitado. La comprobación en navegador detectó el error. Se reconstruyó
el mismo commit con la URL productiva y la clave pública validadas, demo apagado,
y se volvió a publicar. Se comprobó la recuperación de la sesión Gerencia y los
controles reales. El primer artefacto queda en `releases/descartados/`, marcado
**NO USAR**, sin presentarlo como una publicación válida.

Para próximas publicaciones, además de los checks de código, verificar antes de
empaquetar que el bundle contiene el destino productivo y su clave pública. Nunca
copiar claves privadas al frontend. Un build sin configuración puede ser válido
para CI y resultar inoperante como release.

Evidencia: `evidencia/produccion-verificada-20260911.json`,
`sql-produccion-verificado-20260911.json`, `edge-secretos-prod-verificados-20260911.json`,
`web-verificada-20260911.json` y `banco-eliminado-20260911.json`.
ZIP/manifiesto válido conservados en `CRM-Avance-Corp/releases/`, fuera del web root.

Reversión si fuera necesaria: usar el release estable anterior a notificaciones
o apagar este cron con `cron.alter_job`, conservando solicitudes, auditoría y
claves del portal. No usar el primer artefacto descartado.
