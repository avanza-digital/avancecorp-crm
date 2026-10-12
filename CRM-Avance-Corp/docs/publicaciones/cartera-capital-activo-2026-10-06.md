# Publicación: capital activo de clientes renovados

Publicado y comprobado en **https://crm.miavance.com** el **6 de octubre de 2026,
23:20 (Lima)**, mediante el conector oficial Hostinger y el skill
`../.agents/skills/release-crm/SKILL.md` desde la raíz CRM.

La búsqueda exacta del caso reportado muestra **US$12.000 activos** en la fila y
el resumen. Se conservan las dos inversiones históricas. No se cambió SQL, Edge
ni datos comerciales.

## Fuente, autorización y trazabilidad

- Fuente real del paquete: `dfb8874d534bc6462432dee00298f022e4437a0b`.
- Padre: `4e6ee7ee296be83cd96366e3e79685343b3b706b`, versión que estaba viva.
- Cambio: solo pantalla de cartera, sus tests y `e2e/f5-cartera.spec.ts`.
- El usuario autorizó expresamente publicar solo este arreglo sobre la versión
  viva e integrarlo en Main el mismo día, como excepción a la regla general.
- [PR #210](https://github.com/avanza-digital/avancecorp-crm/pull/210) integrado
  a las 23:12:55 de Lima; Main local y `avancecorp/main` alineados en
  `e255e96d3d0ef39c55eedd29a9c879bf13822b91` antes del despliegue.
- `e255e96d` tiene exactamente el árbol del head aprobado del PR,
  `a058e481029dc7c6f067b15f6dff1124733bcc81`.
- El manifiesto identifica **dfb8874d**, no el commit posterior de Main. Los
  cambios adicionales de Main no forman parte de esta publicación aislada.
- Se conservó todo el trabajo local ajeno. El stash
  `ca8745de4837ff186d4d834dcd121e5c48d3426b` es un respaldo de los tres archivos
  propios ya integrados; no hay que reaplicarlo.

## Artefacto publicado

- ZIP: `releases/crm-20261007T034649Z-dfb8874d534b.zip`.
- Manifiesto: `releases/crm-20261007T034649Z-dfb8874d534b.manifest.json`.
- Tamaño: 2.512.762 bytes.
- SHA-256: `47070ef4c08e5f1e3c1d5cc371abfcbc208d07fcbce9f5ba5ec6571b73565ca2`.
- Build servido: `build-20261007T034648905Z`.
- JS principal: `assets/index-BzQ0Qr_T.js`.

## Verificación

- **PASS** `npm run check` sobre la fuente limpia del paquete: 385 archivos /
  6.213 tests, lint, tipos, cobertura, configuración, build, bundle y duplicación.
- **PASS** 11/11 E2E Docker del paquete, sin reintentos; capturas de móvil y escritorio.
- **PASS** integración: 83 tests focalizados, 13/13 E2E Docker y 6.282 tests
  completos. En el head final, GitHub `preflight`, `app-check` y `verify`: PASS.
- **PASS** ZIP/manifiesto y preflight obligatorio inmediatamente antes de subir.
- **PASS** recibo Hostinger: upload y deploy aceptados; no se repitió la subida.
- **PASS** postflight HTTPS: portada y versión 200; 154 archivos comprobados
  (140 con bytes/SHA exactos, incluidos JS/CSS; 13 PNG disponibles; `.htaccess`
  protegido). El ZIP no quedó público: 404.
- **PASS** interfaz real: acceso existente de Gerencia, cartera y búsqueda del
  caso reportado; fila y resumen con US$12.000 activos y dos inversiones.
- **NOT RUN** sesión real de analista separada; su flujo está cubierto en Docker.
- El wrapper de revisión independiente no produjo dictamen válido. No se
  presenta como PASS. `gate:realidad` no corrió por falta de configuración;
  sí hubo diagnóstico SQL de solo lectura y verificación del caso en producción.

Evidencia en `output/renovacion-capital-20261006/deploy/`: esquema del conector,
integración Git, preflight inmediato, recibo Hostinger, postflight HTTPS y smoke.
Logs y capturas conservados en
`output/renovacion-capital-20261006/verificacion-local.tar.gz`, con índice y
SHA-256 por archivo en `verificacion-local.indice.json`.

## Limpieza autorizada al cerrar la sesión

El usuario pidió cerrar lo usado para esta tarea y borrar lo innecesario.
La pestaña de verificación ya estaba cerrada; no quedaban procesos, contenedores
ni redes propios activos. Se retiró el volumen exclusivo de dependencias E2E
`avancecorp-renovacion-capital-20261006`, sin contenedores asociados.

Tras comprobar que la copia Git temporal estaba limpia y que el ZIP publicado
conservaba su SHA-256, se eliminaron las dos carpetas temporales
`/private/tmp/crm-renovacion-{capital,release}-20261006`, las copias de archivos
usadas para planificar la alineación y las capturas duplicadas del workspace.
Los 45 registros y capturas de verificación se archivaron y comprobaron por hash
antes de retirar sus originales. Se conservaron los planes JSON, recibos,
actas, código, fuente Git, ZIP/manifiesto actual y respaldo de la versión previa.
Los recursos de otras tareas permanecieron intactos. Detalle en
`output/renovacion-capital-20261006/limpieza.json`.

## Recuperación y próximas publicaciones

ZIP anterior conservado: `crm-20261006T213355Z-4e6ee7ee296b.zip`, SHA-256
`9b5be00b190443726f5520fc37a54ba27ff3785ace447200b7ce2d807430e33d`.

GitHub exige squash e historial lineal: el commit fuente **dfb8874d no es ancestro
de Main**, aunque su arreglo sí está integrado. Un próximo preflight basado
solo en ancestría puede rechazar. Conservar el artefacto y esta acta; revisar el
rechazo por el procedimiento del proyecto, sin falsear el manifiesto ni saltar
la protección. Esta publicación ya pasó el preflight contra el commit entonces vivo.

Diagnóstico y reglas de presentación: [acta del arreglo](../encargos/2026-10-06-cartera-capital-renovado.md).
