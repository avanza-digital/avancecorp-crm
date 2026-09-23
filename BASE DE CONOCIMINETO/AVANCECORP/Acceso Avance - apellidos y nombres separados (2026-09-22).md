---
tags: [crm, acceso-avance, formulario, publicacion]
estado: publicado, verificado y sesión cerrada
fecha: 2026-09-22
---

# Acceso Avance — apellidos y nombres separados

Miguel pidió eliminar el campo «Nombre completo», mostrar «Apellidos» primero y «Nombres» después, y publicar inmediatamente. `AltaAvance` conserva ambos campos obligatorios y deriva internamente `nombre_completo` como nombres + apellidos para el contrato existente. No cambia SQL ni Edge Functions.

Cambio local: `78a46f6b`; PR focalizado: [#72](https://github.com/avanza-digital/avancecorp-crm/pull/72), fuente `5fecf193a375d8c3a530c66f2d0e5f4d17c9857b`, tres archivos. Copia limpia: `/private/tmp/avancecorp-acceso-release-20260922`. El árbol de app coincide con el del cambio probado en el taller.

PASS: `npm run check`, 272 archivos / 4.085 pruebas, lint, tipos, cobertura, build, bundle y duplicación. Docker: seis E2E de rentabilidad/modo y tasas bajas; segunda corrida 6 PASS sin fallos. Primera corrida: 4 PASS y 2 flaky por timeout al abrir un cliente, fuera del formulario corregido. Logs: `/private/tmp/avancecorp-acceso-check.log`, `/private/tmp/avancecorp-acceso-e2e-final.log`. PASS adicional de `npm run check` en copia limpia con dependencias del lockfile; log `/private/tmp/avancecorp-acceso-clean-check.log`.

El push directo fue rechazado por las reglas de GitHub: PR, historial lineal, check `verify` y una aprobación. El PR #72 pasó `cambios`, `app-check` y `verify` y fue integrado por `miguejbs98` el 22/09/2026. El commit publicado es `7d65fcdb484f223f37cc98dd0ff33d41dfe682fc`; no se atribuye una revisión que no aparece en la API.

**Frontend publicado y verificado.** En la copia limpia, `main`, `avancecorp/main` y el remoto apuntaron al mismo commit antes de construir y subir. `npm run release:crm` y `release:crm:verify` pasaron. Build servido `build-20260922T221442353Z`; entrada `assets/index-B60XRNEd.js`. ZIP `CRM-Avance-Corp/releases/crm-20260922T221443Z-7d65fcdb484f.zip`, SHA-256 `bd9dc6c8dc10a55d5a314f862f75a45d9720b755401b84394e2976f85d891932`, manifiesto homónimo y 107 archivos. Hostinger devolvió subida exitosa y solicitud de deploy aceptada. La portada pública y tres assets principales coinciden byte a byte; los 89 JS/CSS/HTML/JSON comprobados directamente en origen coinciden con el manifiesto. El primer intento de comparar todos por CDN tuvo un timeout puntual; el archivo se comprobó por origen y después por la URL pública con la misma huella. Evidencia privada: `CRM-Avance-Corp/releases/private/acceso-avance-20260922-deploy.json` y `acceso-avance-20260922-postflight.json`.

Se integró `avancecorp/main` en el taller mediante `00492ae0`, conservando todos los commits locales, SQL y notas. Documentos anteriores restaurados y fuera del commit del arreglo; el stash `resguardo-documentos-previos-acceso-20260922` se conserva como respaldo. El PR focalizado excluye esos cambios ajenos. No se creó worktree ni rama de release.

Recuperación: `CRM-Avance-Corp/releases/crm-20260922T165248Z-e22c0cab2db3.zip` y manifiesto, ambos verificados. Se usó Hostinger 1.59.0 con `hosting_deployStaticWebsite`; no se cambió configuración. El taller principal conserva sus cambios y commits locales divergentes; la copia limpia de publicación queda sincronizada con `avancecorp/main`.

Relacionado: [[Inicio]], [[Conversion de lead con Nueva inversion - preparado 2026-09-19]], [[Gestion Diaria F4 - etapa 3 publicada con cortes OFF (2026-09-22)]].

## Cierre de sesión

Miguel confirmó «listo gracias guarda todo y cerramos esta sesión». El release, el manifiesto y la evidencia privada siguen guardados en `CRM-Avance-Corp/releases/`. El punto de control del taller conserva 26 archivos modificados o sin seguimiento en `CRM-Avance-Corp/releases/private/cierre-sesion-20260922-acceso-avance.tar.gz` (SHA-256 `86da46c8ff16490d8603fe78e475fe0a8936bf50c2672ebdca23ea2ad4042a79`) y los commits de `main` local que aún no están en `avancecorp/main` en `cierre-sesion-20260922-main-local.bundle` (SHA-256 `8d3b4da4656e3e38241b9e1377c7ca36bf4f6d22260bbd70641ba49e615d911d`). Ambos respaldos se verificaron y permanecen fuera del web root.

Al corte, el taller principal está en `b0ec94b0e70fd2c25da1f3c35724f255f77c5ec2` y `avancecorp/main` en `7d65fcdb484f223f37cc98dd0ff33d41dfe682fc` (9 commits locales / 2 remotos por reconciliar). La publicación salió de la copia limpia sincronizada. No se incorporó el trabajo de otras sesiones al PR #72 ni se alteraron sus archivos para cerrar esta tarea. El stash `resguardo-documentos-previos-acceso-20260922` sigue como respaldo adicional. La reconciliación del taller pertenece a la próxima sesión.
