# Coordinación: cartera, Leads y corrección de categoría publicados

**Publicado y verificado el 15/10/2026, 19:28 Lima**, mediante `$release-crm` y el
conector oficial de Hostinger, destino [crm.miavance.com](https://crm.miavance.com).
El backend se había promovido a las 18:58 Lima tras la autorización explícita de Miguel.

Coordinación consulta Leads y la cartera de clientes de toda la empresa. Admin/Superadmin,
Gerencia y Coordinación corrigen Nuevo/Renovación/Upgrade en contratos Avance desde
Cartera → ficha → inversión → **Corregir categoría**. Exige motivo y deja auditoría;
actualiza conversión y ranking, conserva importes/condiciones/relojes y protege meses sellados.

## Artefacto efectivamente publicado

| Dato | Valor |
|---|---|
| Commit fuente | `d1796dd4cf8c771d7b35f3db608d536a99d51a9c` |
| Build servido | `build-20261016T002734754Z` |
| ZIP | `crm-20261016T002735Z-d1796dd4cf8c.zip` |
| Manifiesto | `crm-20261016T002735Z-d1796dd4cf8c.manifest.json` |
| SHA-256 del ZIP | `956e504ee7790ab912cf789a27a7e1ae36697dd2507e1c3c043d549a2d2d3cc6` |
| JS principal servido | `assets/index-CM9TwbZS.js` |

Construido mediante `npm run release:crm` desde Main limpio, igual a `avancecorp/main`
y al remoto consultado inmediatamente antes de subir. `release:crm:verify` y preflight PASS;
el candidato contiene el vivo anterior `875054a2`. ZIP y manifiesto conservados en `releases/`,
tanto en la copia de publicación como en el directorio habitual del proyecto.

La PR #302, con el banco Auth y el registro del backend, se integró **después** de construir
y publicar como `1be4ac56`. No cambia el código de pantalla ni el SQL aplicado. Esta acta tampoco
redefine el commit publicado ni justifica reconstruir o volver a subir el sitio.

## Verificación

- **PASS código:** 433 archivos / 6.966 tests, lint, tipos, cobertura, build, bundle y duplicación.
- **PASS E2E Docker local:** 427 aprobados, 26 omitidos, cero fallos; 16,2 min y dos workers.
  Los checks se hicieron sobre `81480ebb`; el árbol de `app` es idéntico al publicado:
  `9adc5c59fa90c640437ac0054036bf07376ecd10`. Los avances posteriores eran n8n/documentación,
  fuera del bundle, y conservaron íntegra la planilla de reparto de #296/#299.
- **PASS backend:** tres migraciones por merge de rama, 93 SQL y 61 Auth/PostgREST;
  1.110 funciones/propietarios/ACL iguales a lo validado; contratos, categorías e importes
  conservados. [Evidencia cloud](../supabase/scripts/permisos-coordinacion/VERIFICACION-CLOUD.md).
- **PASS smoke HTTP:** portada y JS principal HTTP 200; **123 JS/CSS y 3 archivos de
  acceso/versión/manifest**, 126 en total, idénticos por SHA-256 al manifiesto. El `version.json`
  servido identifica el build indicado en esta tabla. No se afirma igualdad de imágenes
  recomprimibles por CDN ni se solicita `.htaccess` por HTTP.
- **PASS acceso en Chrome:** la sesión de Coordinación muestra Leads/Cartera; Leads carga
  50 filas por página. Cartera muestra 119 registros con octubre seleccionado y **664 registros
  con mes Todos y empresa Todas**. Se abrió una ficha Avance, se vio el botón de categoría y
  el formulario con las tres opciones y motivo. Se canceló sin guardar ni cambiar inversiones reales.
- La rama Supabase de ensayo fue eliminada, se confirmó su ausencia y se retiraron sus
  credenciales locales. Advisors: cero WARN/ERROR nuevos; dos INFO esperados de auditoría privada.
- La matriz general RLS con seed-demo permanece **NOT RUN**; sí pasó la matriz focalizada
  real. Las 26 omisiones E2E no se presentan como pruebas aprobadas.

## Recuperación

Paquete anterior preservado y contrastado con la web antes de publicar:
`crm-20261015T225913Z-875054a2d630.zip`, SHA-256
`ee39c7162300b1f005727cf352858e8098c782c21e5ed3ac11eb7f6aea2af63e`.
Su preflight y smoke de 126 archivos coincidían. Una recuperación requiere la decisión
de Miguel según el flujo de release; no revierte migraciones ni auditorías por sí sola.
