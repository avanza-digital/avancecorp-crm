---
tags: [crm, conversion, gerencia, renovaciones, figma]
actualizado: 2026-10-12
estado: activo_en_produccion
---

# Conversión: las renovaciones dejan de sumar desde octubre de 2026

Miguel pidió simplificar el FigJam para Gerencia y quitar renovaciones **a nivel del sistema**.
Autorizó la rama temporal de Supabase y la activación el 12/10/2026.

La regla: renovación **0**, referido **1** con el tope vigente del **15 %**, upgrade elegible **1**.
Rige desde octubre, abierto al autorizar. Agosto y septiembre conservan las fotos cerradas.
No se borran renovaciones ni importes de cartera. Se conserva la primera operación elegible
por cliente y mes: una renovación anterior a un upgrade sigue ocupando ese lugar con peso cero.
Cambiar la selección de esa primera operación requeriría otra decisión comercial.

La fórmula del analista sigue siendo cierres ponderados netos / llegadas automáticas × 100.
Divisor: landing/formulario por creación original y primer analista. El tope de referidos se
calcula sobre cierres de esas llegadas automáticas del analista, con redondeo hacia arriba;
sin esos cierres no aporta ningún referido. Confirmación y vínculo de la inversión, mes comercial
y plazo del día 10 siguiente siguen vigentes.

Migración local `20261012184345_crm_conversion_sin_renovaciones.sql`: configura peso cero,
default cero y CHECK que impide reactivarlo desde octubre. No cambia funciones ni permisos.
Preflight rechaza cambios de configuración o meses afectados ya sellados y comparte el
candado de `cerrar_periodo`. Kit y reversa en
`CRM-Avance-Corp/supabase/scripts/conversion-sin-renovaciones/`.

Ensayo: 22 comprobaciones SQL locales y 22 remotas, 108 unitarias focalizadas, 319 aserciones
RLS de contratos con Auth real; tipos/lint y migración/reversa aprobados. Advisors: sin altas
ni bajas atribuibles al cambio. La matriz RLS global y E2E no se ejecutaron; no hay release de frontend.

[FigJam para Gerencia](https://www.figma.com/board/tO6Lpx3ieJ6QuwUxfZcSvM?node-id=50-19):
los doce bloques anteriores se reemplazaron por un flujo de cuatro pasos, criterios, tope
y un ejemplo de 100 llegadas → 12 cierres válidos → 12 %.

Ver [[Como se mide la conversion del asesor]], [[Cierre de mes]] y
[[Conversion - divisor de Coordinacion desde el nucleo (2026-09-30)]].

PR #256 fusionada: https://github.com/avanza-digital/avancecorp-crm/pull/256.
Main verificado: `16f493006dce0ee4a82d0b065d9660f251953469`.
**ACTIVO EN PRODUCCIÓN** el 12/10/2026 a las 16:39 Lima, por `merge_branch`.
Migración remota `20261012213521`: 14 sentencias idénticas al archivo aprobado.

Nueva rama propia: 22 comprobaciones SQL y 319 aserciones RLS PASS. CI
`preflight`, `app-check` y `verify` PASS; batería local general de 6.625 pruebas PASS.
Peso y aporte de renovación 0 comprobados en oficial, Coordinación y Metas.
Foto de la activación: oficial/Coordinación 39,30 → 39,00; Metas 38,30 → 38,00;
divisor 779. Dos renovaciones registradas, USD 6.000 renovados conservados.
Fotos cerradas, periodos, 148 operaciones, 1.067 funciones y 463 migraciones previas
con huellas idénticas. Advisors productivos 366/235, sin altas ni bajas.

Rama propia eliminada y ausencia confirmada a las 21:40 UTC; coste de esta ventana
estimado US$0,0023, más US$0,0248 del ensayo anterior (estimaciones, no factura).
Figma marca ACTIVO EN EL SISTEMA, con captura revisada. Sin release de frontend.
Acta y evidencia: `CRM-Avance-Corp/supabase/scripts/conversion-sin-renovaciones/PUBLICACION.md`
y `activacion.json`. No se modificaron las ramas ni los cambios locales de otros trabajos.
