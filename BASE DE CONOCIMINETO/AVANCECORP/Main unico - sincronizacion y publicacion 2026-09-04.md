---
tags: [crm, git, main, deploy]
actualizado: 2026-09-04
estado: sincronizacion-en-curso
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
