---
tags: [crm, git, main, deploy]
actualizado: 2026-09-04
estado: publicado-verificado
---

# Main único — sincronización y publicación

Miguel pidió que la versión local y la rama remota `main` sean la misma antes
de publicar, sin ramas nuevas. Esta decisión sustituye la ruta histórica
Main local → `avancecorp/tronco` descrita en [[Deploy a Hostinger]].

El remoto del CRM es `avancecorp` (`avanzadigitald/avancecorp-crm`). `origin`
apunta a otro proyecto (`avanza-platform`), con estructura distinta; no es el
destino de esta sincronización ni se debe sobrescribir.

## Integración sin pérdida ni retroceso

La punta remota `d4aabbc26559d38e66e6f5e0d2c4b011514d89ec` del 01/08 tiene
su equivalente local en `5f674245eb1f16c79fddc04ec00f4853bc836f17`, que ya es
antepasado de Main. Ambos árboles `CRM-Avance-Corp` son exactamente
`c6e0ea5b272af289b0ff1649272c48ac65a232d3`.

Fuera del CRM, la comparación solo encontró cuatro archivos adicionales en
la historia local y la anonimización de cinco nombres en una nota antigua;
la anonimización ya está presente en Main actual. Por eso no se reintroduce
el código viejo: el merge `4f999482ceccfa4d4f6f4c900a8ffc5589bd6406` enlaza
ambos historiales conservando exactamente el árbol actual. Sus padres son
`3a3f883b2ed78c89a979c24084e9bd02e2258931` y `d4aabbc...`.

Respaldo completo y verificado previo a la unión:
`/private/tmp/crm-main-sync.cWpnGr/pre-sync.bundle`. No se creó ninguna rama.

## Regla operativa vigente

1. Trabajar en Main local con upstream `avancecorp/main`.
2. Integrar y guardar los cambios, ejecutar las pruebas y subir sin forzar.
3. Confirmar igualdad del commit local con el remoto antes de construir/publicar.
4. Mantener el artefacto y reversión anteriores fuera del directorio público.

La entrega de métricas se documenta en
[[Nucleo de conversion - diagnostico de llegadas y asignaciones 2026-09-04]].
Su frontend compatible se publica antes de la migración del núcleo.

## Publicación realizada y cierre

Antes de construir y publicar, Main local y `avancecorp/main` coincidían en
`ff21967acd193c9b4d9de0b9dc4843f31280fb26`, con el árbol limpio. GitHub Actions
aprobó calidad y E2E en el run `33926827372`. Se construyó desde un checkout
detached de ese commit, sin crear una rama y con la configuración pública de
producción verificada dentro del ZIP y en la pantalla de acceso.

Publicado en Hostinger: `crm-20260904T225440Z-ff21967acd19`, build
`build-20260904T225440168Z`. El frontend compatible salió primero; después se
aplicó `20260904210831_crm_conversion_llegadas_unicas`, con cuerpo idéntico al
archivo versionado. Los hashes, respaldo y verificaciones están en
[[Deploy a Hostinger]] y en el ledger `supabase/migrations/MIGRACIONES.md`.

Durante la publicación apareció el commit paralelo `a59f868`: contiene una
migración de altas nuevas por analista y su documentación, marcada pendiente
de aprobación. Se conserva en Main, **sin aplicarla**. No cambia `app/`; el
código de la aplicación sigue siendo idéntico al del artefacto publicado.
Los cambios posteriores de esta entrega solo documentan el despliegue; no
requieren reconstruir ni volver a publicar la misma aplicación.

Tras la pausa solicitada por Miguel, la verificación de solo lectura confirmó
el mismo build, las siete funciones sin deriva y el registro de migración
exacto. Para el 1–3 de septiembre: base automática **176**, numerador **9** y
conversión **5,11 %**. La migración de altas por analista sigue sin instalar.

La sincronización final se entrega en `avancecorp/main`, sin forzar historia;
`avancecorp/tronco` queda como referencia histórica, no como destino operativo.
