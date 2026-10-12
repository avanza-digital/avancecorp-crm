---
tags: [crm, cartera, renovacion, capital]
fecha: 2026-10-06
estado: publicado-verificado
---

# Cartera: saldo activo al renovar

**Publicado y comprobado en producción el 06/10/2026 a las 23:20 de Lima.**
El caso real muestra US$12.000 activos en fila y resumen, conservando dos
inversiones históricas. Aplica a la lógica general de la cartera y a futuras
renovaciones; no es una excepción codificada para un cliente.

[Acta definitiva de publicación](../publicaciones/cartera-capital-activo-2026-10-06.md):
fuente `dfb8874d`, Main `e255e96d`, PR #210 integrado, ZIP y SHA-256, recibo
Hostinger y postflight HTTPS PASS.

El usuario reportó que un cliente mostraba 17.000 cuando correspondían 12.000.
La consulta de producción confirmó que la moneda es USD: el contrato anterior de
US$5.000 está cerrado como `renovado` y enlazado al nuevo contrato activo de
US$12.000. El registro de la renovación separa US$5.000 renovados y US$7.000
adicionales. La renovación y sus datos están correctos.

## Causa y corrección

La fuente de cartera devuelve `capital_registrado = 17000` y
`capital_activo = 12000`. La lista y su resumen elegían siempre el registrado,
mientras que la ficha ya prefería el activo. Buscar un documento quita el filtro
de mes; por eso el histórico completo aparecía como el dinero del cliente.

`app/src/screens/cartera-inversionistas.tsx` ahora aplica la misma elección a
filas y resumen:

- Sin mes, incluida la búsqueda exacta: capital activo cuando está informado.
- Con mes o estado histórico explícito (vencido, renovado, retirado o anulado
  comercialmente): capital registrado, conservando la consulta de operaciones.
- Si el servidor no informa capital activo, como en cooperativas: registrado y
  etiquetado como tal. Un saldo activo cero sigue mostrando cero.
- Cada importe se identifica como Activo o Registrado; PEN/USD siguen separados.

No hay cambios de base de datos. El contrato anterior permanece en el historial.
La cantidad de inversiones registradas sigue incluyendo ambos contratos.

## Verificación previa en el workspace

- PASS: reproducción previa, tres pruebas fallaban con 17.000 en vez del saldo activo.
- PASS: 74 pruebas de cartera tras el cambio; suite completa, 387 archivos / 6.226 pruebas.
- PASS: lint (10 advertencias previas en otros archivos), TypeScript, build y verificación del bundle.
- PASS: revisión visual de capturas móvil y escritorio con US$12.000 en fila y resumen.
- PASS: E2E Docker, 11/11 sin reintentos, con un contenedor y volumen exclusivos.
  La primera corrida se detuvo tras fallos en el acceso, antes de llegar a la
  cartera, mientras otro banco E2E usaba el mismo volumen de dependencias.
  El aislamiento resolvió la segunda corrida; no se cambiaron los timeouts.
- NOT RUN: `gate:realidad`, falta `SUPABASE_URL`. Sí se consultaron en producción,
  en transacciones de solo lectura, los contratos, la operación y la fuente de cartera.
- Revisión independiente sin dictamen válido: el wrapper del repositorio falló
  dentro del sandbox y devolvió un resultado incompleto/sin VERDICT al repetir
  fuera de él. No se considera una revisión aprobada.

Evidencia local y capturas archivadas al cerrar la sesión en
`output/renovacion-capital-20261006/verificacion-local.tar.gz`.
Los directorios temporales y las capturas originales se retiraron después de
verificar el archivo por SHA-256; el índice conserva la huella de cada entrada.

La preparación inicial quedó preservada en local. La publicación posterior se
completó por el skill de release con la excepción expresa del usuario; se
preservó el trabajo ajeno existente.

El usuario autorizó publicar, pidió una pausa segura y después indicó «sigue».
La pausa ya terminó. Al retomar se verificaron las dependencias de Main remoto
`62a375f0e23a220952489148c6f8e07357a053e8` con consultas de solo lectura:

- Gestiones de clientes: ambas migraciones instaladas y control completo de
  catálogo `comprobar-tras-aplicar.sql` **PASS** (2026-10-07 03:43 UTC).
- Upgrade cooperativo: migración y `crm.preparar_upgrade_fn` instaladas.
- Llamadas del celular: ninguna de sus migraciones registrada; las funciones
  de bandeja y resueltas, y sus núcleos, no existen. Main remoto incorpora una
  pestaña que las consulta para usuarios reales sin un bloqueo de disponibilidad.

Publicar Main completo en ese estado introduciría una pestaña con errores.
La autorización de frontend no incluye las doce migraciones y la Edge de llamadas.
La regla de Main tampoco permite publicar por iniciativa propia desde otra base
si el preflight no ha rechazado. Hasta ese punto no se había aplicado SQL ni
desplegado frontend.

Se preparó una alternativa concreta en una copia Git limpia, sobre el commit vivo
`4e6ee7ee296be83cd96366e3e79685343b3b706b`, con únicamente los tres archivos del
arreglo: commit aislado `dfb8874d` en
`/private/tmp/crm-renovacion-release-20261006` (HEAD separado, sin rama de release;
copia temporal retirada después de publicar y verificar).
El usuario **autorizó explícitamente esa excepción**: «Sí, publicar solo el arreglo
(recomendado)», ante la propuesta de publicarlo sobre el commit vivo e integrar
el mismo arreglo en Main el mismo día. Los checks de esta copia se
registran por separado y no se confunden con los del workspace que contiene WIP.

## Paquete aislado verificado al retomar

- Fuente limpia: `dfb8874d534bc6462432dee00298f022e4437a0b` (padre: commit vivo).
- PASS `npm run check`: 385 archivos / **6.213 pruebas**, lint, tipos, cobertura,
  configuración de release, service worker, build, bundle y duplicación (0,43%).
- PASS Docker E2E: **11/11**, cero reintentos; capturas móvil y escritorio revisadas.
- PASS `release:crm` y `release:crm:verify`.
- ZIP: `releases/crm-20261007T034649Z-dfb8874d534b.zip`, 2.512.762 bytes.
- SHA-256: `47070ef4c08e5f1e3c1d5cc371abfcbc208d07fcbce9f5ba5ec6571b73565ca2`.
- PASS preflight obligatorio: el candidato contiene el commit vivo `4e6ee7ee296b`.
  Este PASS acredita continuidad, **no sustituye la regla de Main**.
- **PASS publicación y smoke de producción**: build
  `build-20261007T034648905Z`, 154 archivos HTTPS conformes y caso real con
  US$12.000 activos en fila y resumen. Sesión real existente de Gerencia; el
  recorrido de analista se verificó en Docker.

Logs de esta copia: `release-check.log`, `release-e2e.log`, `release-build.log`,
`release-preflight.log`, conservados en `logs/` del archivo de verificación
local. Sus capturas están en `capturas-paquete/` del mismo archivo. ZIP y
manifiesto están preservados en `releases/` del workspace principal.

## Integración y cierre

PR [#210](https://github.com/avanza-digital/avancecorp-crm/pull/210) integrado por
squash en `e255e96d3d0ef39c55eedd29a9c879bf13822b91`, con todos los checks de
GitHub aprobados. Main local y `avancecorp/main` quedaron alineados. El árbol
final coincide exactamente con el head probado del PR (`a058e481`). Se preservó
el trabajo ajeno y no se aplicó SQL ni Edge.

La integración previa pasó 83 tests focalizados, 13 E2E Docker y 6.282 pruebas
completas. El paquete publicado sigue siendo el aislado de 6.213 pruebas, sin
los cambios adicionales de Main, conforme a la autorización del usuario.

El contrato anterior permanece como histórico; solo el saldo informado como
activo alimenta la búsqueda global y la consulta de todos los meses. Las
consultas de mes y estados históricos mantienen su capital registrado rotulado.

El stash `ca8745de4837ff186d4d834dcd121e5c48d3426b` respalda los tres archivos
propios ya integrados y no debe reaplicarse. Por el squash obligatorio, el
commit fuente del paquete no es ancestro de Main: la advertencia para futuras
publicaciones y la recuperación están en el acta definitiva. No omitir el
preflight ni atribuir al ZIP un commit distinto de su fuente real.

Limpieza solicitada y completada: copia Git y herramientas temporales retiradas,
caché Docker exclusiva eliminada y ninguna pestaña ni proceso de esta tarea
pendiente. La evidencia se conserva en el archivo de verificación; el detalle
está en `output/renovacion-capital-20261006/limpieza.json` y en el acta de publicación.

Relacionadas: [[Mi cartera por meses]],
[[Gestión comercial de clientes - renovaciones y upgrades]],
[[Ciclo de vida de contratos]],
[[Nueva inversion - bloqueo global y continuidad del cliente (2026-10-06)]].
