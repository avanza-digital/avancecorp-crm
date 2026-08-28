---
tags: [crm, conversion, c0-1, ficha-360, checkpoint, continuidad]
actualizado: 2026-08-28
estado: reconciliacion-canonica-local-certificada-sin-produccion
serial: AVC-F41-360-20260828-R4
serial_origen: AVC-F41-360-20260827-R3
rama: feature/c01-nucleo-unico-r4-20260828
sha_reconciliacion: 30e95f399c7114c0cad4b725ef07fcd98c081730
padre_canonico: 1f012829f4dbd4b45d8d1615d6a579b730dbfb05
padre_c01_r3: d35a2845b03c61b6a90aefa5140157831d8bad5f
sha_candidato_r3: a1f7b2ec2608fbbedb6107157fdb7a9033d26a00
base_c01_local: 7c94d77c39f642e27af676dce6178e6b9f64a315
---

# Checkpoint C0.1 — núcleo único — R4

Serial de continuación: **AVC-F41-360-20260828-R4**

Este checkpoint reemplaza como punto vigente a
[[Checkpoint C0.1 nucleo unico 2026-08-27 R3]] y continúa
[[Ficha 360 - plan de reintegracion sobre nucleo unico (2026-08-27)]].

## Resultado alcanzado

La divergencia 5/5 entre C0.1 R3 y el canon quedó reconciliada localmente en el
merge `30e95f399c7114c0cad4b725ef07fcd98c081730`. Sus padres son el canon
`1f012829f4dbd4b45d8d1615d6a579b730dbfb05` y el checkpoint R3
`d35a2845b03c61b6a90aefa5140157831d8bad5f`.

- Worktree aislado: `/private/tmp/crm-c01-nucleo-unico-r4-20260828`.
- Rama: `feature/c01-nucleo-unico-r4-20260828`.
- El worktree canónico y su rama `wip/workspace-20260823-completo` no fueron
  modificados.
- Los cuatro conflictos reales se resolvieron en `gerencia.tsx`,
  `resumen-gerencia.tsx`, `inteligencia-comercial.tsx` y su prueba.
- No se creó migración, no se aplicó SQL, no se tocó Supabase, PostgREST, una
  base compartida ni producción. Tampoco hubo push ni deploy.

## Decisiones de reconciliación

- C0.1 conserva una sola conversión mensual exacta y fail-closed en sus cinco
  superficies: HOY, Ranking, Metas, Gestión y Directorio.
- La pantalla principal **Conversiones** conserva la decisión canónica más
  reciente: muestra la cosecha bruta del rango —entraron versus cerraron— y no
  queda gobernada por las sondas del núcleo mensual.
- Se conservaron también el filtro por origen, la terminología de citas, la
  compilación histórica, los montos compactos y el contador único de leads del
  Resumen introducidos por los cinco commits canónicos.
- El detalle de vendedor sí rotula una cifra mensual: mantiene la precisión
  canónica de dos decimales y oculta porcentajes, cierres y tendencias cuando
  `cierres_sin_episodio > 0`. La ausencia normal y un mes no medible conservan
  sus estados informativos; el capital del rango permanece visible porque no
  depende de esa sonda.
- La gráfica por origen del Resumen solo publica porcentajes cuando existen el
  núcleo y sondas verificadas. Ningún estado no confiable se convierte en cero.

## Certificación local repetida sobre R4

- El banco hermético aprobó PostgreSQL 17.10, socket Unix privado y TCP
  desactivado; capturó 21 placeholders desde el catálogo local.
- El caso real y los mutantes internos quedaron verdes. La matriz de cuerpos
  terminó 17/17 y emitió una única salida final
  `C0.1_BANCO_ADVERSARIO_OK`.
- El clúster, la base y el directorio temporal fueron eliminados al terminar.
- El check integral aprobó 182/182 archivos y 2.426/2.426 pruebas, con cobertura
  de 75,23 % de statements, 71,47 % de branches, 73,52 % de functions y
  77,58 % de lines.
- También quedaron verdes lint, typecheck, build, verificación del bundle de
  producción y duplicación. Los avisos de accesibilidad del carrusel y de
  tamaño de chunks ya eran no bloqueantes.
- `bash -n`, `node --check`, ausencia de marcadores de conflicto y
  `git diff --check` quedaron verdes. El hook del merge repitió lint y
  typecheck en verde.

## Qué queda fuera del GO local

R4 certifica la reconciliación local, no el servidor vivo ni producción. Aún
se requiere:

1. Revisar y aprobar o rechazar el SQL exacto de C0.1.
2. Con autorización, reproducir todas las migraciones vigentes en orden sobre
   un runtime compatible.
3. Capturar en un servidor autorizado las 18 huellas live y el fingerprint de
   catálogo/ACL, verificar deriva y recalcular los hashes candidatos.
4. Confirmar permisos de locks y ejecutar `EXPLAIN (ANALYZE, BUFFERS)` con
   volumen representativo.
5. Solo con otra autorización, crear/aplicar la migración, hacer readback por
   rol mediante PostgREST/JWT y publicar servidor más frontend de forma
   coordinada.

El siguiente trabajo de Ficha 360 debe partir de un descendiente explícitamente
aprobado de R4; la rama preview R2 sigue siendo referencia UX y no se fusiona en
bloque.

Relacionado: [[Conversion unica en todo el CRM - plan de migraciones]],
[[Conversion mensual - definicion cerrada]] y
[[Ficha comercial 360 de clientes - plan]].
