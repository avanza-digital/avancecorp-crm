---
tags: [crm, gerencia, resumen, auditoria, conversion, capital, citas]
fecha: 2026-09-24
estado: front-en-produccion · servidor-y-dato-pendientes
---

# Auditoría del Resumen de Gerencia: métricas (24/09/2026)

Miguel pidió auditar el módulo **Resumen** de gerencia (`#/hoy`) y decir si sus
métricas son correctas. Se hizo contra producción (solo lectura), con 7 auditores
por bloque, triaje con **Jev** (agrupar y ordenar; nunca veredicto, ver
[[Jev para auditar - que sabe juzgar y que no (2026-09-21)]]) y verificación
adversarial de 3 lentes por hallazgo (producción, negocio, código): 49 hallazgos
crudos → 34 grupos → **28 confirmados, 6 refutados**.

## Veredicto

**Los cálculos de fondo son correctos.** Recontados desde tablas base (01–24/09):

| Cifra | Pantalla | Recuento independiente |
|---|---|---|
| Índice comercial | 7.07 % | 93.85 / 1,327 (69 cierres no referidos + 16 × 0.15 + 22 upgrades + 3 × 0.15) |
| Base / manuales / referidos | 1,327 · 87 · 20 | `crm.leads` por `creado_en` y `alta_manual` |
| Capital confirmado | S/ 6,232,008.47 | S/ 5,051,804 + US$ 350,635.63 × 3.3659 (131 operaciones: `public.contratos` por `fecha_cierre_comercial` + coops por `coalesce(fecha_imputacion, creado_en)`) |
| Citas realizadas / pactadas | 46 / 253 | `crm.tareas` reunión por `vence_en` |
| Mejores analistas | top 5 | los 16 divisores y cierres cuadran por primer analista |
| Avance de metas | 86 % · 47 % | 6,232,008 / 7,250,000 · 7.07 / 15 |

Lo que falla es **lo que se lee alrededor** de esas cifras: datos que no son
reales y rótulos que dicen otra cosa.

## Problemas de dato (acción de Miguel)

1. **Perfil de pruebas `d731f284` («MIGUEL BRICEÑO», vendedor)**: su venta de
   prueba de septiembre suma al índice (7.07 % → 7.00 % sin ella) y en **agosto
   encabeza «Mejores analistas» con 215 %** (divisor 1) y aporta S/ 100,000 a la
   meta. Miguel confirmó el 23/09 que es solo de pruebas: anular por la única
   puerta, republicar metas de agosto sin él y DESPUÉS desactivarlo.
2. **Backfill del 23/09** ([[Backfill de conversion - contratos nuevos sin lead (2026-09-22)]]):
   sus 30 leads creados el 23/09 son «prospectos del período» para la cohorte:
   «77 de 1,434 cerraron» son en realidad 47 de 1,404; el pico de 37 cierres en
   la semana 22–24 es un artefacto (sin backfill, 169/7); la tabla por origen se
   infla (formulario 6.0 → 3.5 %). El índice NO se afecta de más: ahí el efecto
   era el buscado. **Decisión de Miguel (24/09): se deja así.** Los leads se crearon
   con su autorización para que la conversión les cuente a las analistas; no se
   eliminan, no se excluyen de la cohorte y no se les añade rótulo. Si alguien
   vuelve a ver el pico de la semana 22–24, la explicación es esta, no un defecto.

## Arreglado en pantalla (PR de esta auditoría)

- Pastillas del héroe con rótulo corto y detalle debajo: «Capital · mes», «Citas ·
  realizadas» (antes decía «Citas del período» y mostraba las realizadas), «Meta ·
  conversión · mes»; con filtro de fuente la meta dice «No aplica al filtro».
  Sin TC la pastilla de capital dice cuántos dólares faltan.
- Héroe: un solo candado para el % y su pie. Si la cifra es la oficial delegada
  pero la sonda del recálculo vivo no cuadra, el pie enseña solo base y aporte
  oficiales («desglose de cierres en revisión»), no conteos vivos. Aviso
  «Provisional» en un mes parcial delegado; «Mes anterior al registro» / «Sin
  base» en vez de «Cifras en revisión» cuando no hay base (solo para ese mes).
- «Avance de metas»: la barra de conversión escribe su base mensual; con filtro
  de fuente ya no presenta el aporte del rango como mensual.
- Capital y mejores analistas nombran su mes; el pie fecha las dos ventanas.
- «Resultados por origen»: etiqueta legible y la precisión que sirve el servidor.
- Gráfica semanal con fechas legibles y el bloque corto marcado «(N días)».
- `adaptarAporteConversionRango` publica la base con la que dividió.
- «Por empresa» incluye a quien está fuera del ranking (`produccionPorPersona`).
- Rentabilidad dice desde cuándo observa y no afirma «nada se bloquea» con el
  modo de hoy; el aviso de cierre ya no culpa al ciclo automático.
- Contraste: el rótulo del héroe estaba en gris sobre navy (1,5–3:1).

Verificación: `npm run check` 4,408/4,408; 18 mutantes, uno por arreglo, todos
muertos; revisión adversarial de 4 lentes (19 hallazgos menores, corregidos).
Codex NO revisó: cupo agotado hasta el 26/09.

## Publicación (25/09/2026, 23:1x Lima del 24/09)

PR #100 fusionada por squash (`3027028d`). Release
`crm-20260925T041520Z-3027028d7c97` (build `build-20260925T041520137Z`), construido
en worktree limpio; preflight OK contra lo vivo `b402a7f1`; publicado por Miguel con
`deploy-hostinger-mcp.mjs deploy` (la MCP de Hostinger no cargó en la sesión).
Smoke: home 200, `version.json` e `index-*.js` idénticos al build, textos nuevos en
el bundle vivo. Rollback: `crm-20260925T023617Z-b402a7f1b5c9.zip` en `releases/`.

## Pendiente de servidor (plan + OK de Miguel)

- Rentabilidad cuenta dos veces 18 contratos borrados y re-creados (156 → 138
  observados) y carga a analistas margen autorizado por gerencia con candado.
- La gráfica semanal solo suma el roster activo (1,433/76 vs 1,434/77).
- Antes de resellar agosto: el pie del héroe mezclaría foto sellada con recálculo vivo.
- Estado `en_pausa` para el aviso de cierre; roster del mes con filtro de fuente;
  analista sin meta con fila «Sin meta» en Ranking.

## Refutados (no son defecto)

Referido 12 % (Resumen, ponderado) vs 80 % (Conversiones, bruto): cada pantalla
rotula su decisión. El 86 % incluye producción fuera del ranking: decisión del
02/09. Meta 15 %: una sola meta replicada. «253 pactadas» cuenta tareas: unidad
firmada el 30/08.

Relacionado: [[Conversion mensual - definicion cerrada]] ·
[[Conversión de Gerencia respeta el rango visible]] ·
[[Plan de correccion de metricas de Gerencia - requerimiento vigente]] · [[Inicio]]
