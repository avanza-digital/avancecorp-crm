# HOY del analista: leads recibidos hoy

Estado: PUBLICADO Y VERIFICADO el 05/10/2026 en https://crm.miavance.com/. Integración por PR #191 pendiente de aprobación externa obligatoria.

## Alcance confirmado por Miguel

«Solo los que le llegaron hoy», en el mismo dashboard HOY. No es un filtro de
etapa Nuevo ni una lista de todos los pendientes sin gestionar.

- Bloque «Leads recibidos hoy» encima de «Tus citas» en modo activo. Agenda y
  cumplimiento conservan su columna. En legado o si falla SLA, el bloque se
  muestra tras «Tu siguiente movimiento», fuera del boundary de seguimiento. En móvil conserva la primera acción dentro de la ventana.
- Recepción del día en America/Lima y titular actual; reutiliza
  `useCarteraPaginada` → `cartera_filtrada_fn`, con fechas y analista en servidor.
  No depende de la creación del lead ni de la colección parcial del store.
- Todas las etapas: un recibido hoy permanece si ya fue contactado, convertido
  o descartado. Reasignados de hoy también entran. Soft-delete sigue excluido.
- Total autoritativo, paginación de 50, nombre, teléfono y hora de recepción;
  conserva la marca aproximada cuando la entrega el servidor. Abrir ficha usa
  la acción existente, que relee el lead bajo RLS.
- Actualización manual y cada 60 segundos mientras la pestaña sea visible;
  conserva la invalidación compartida tras mutaciones, foco y reconexión.
  El reloj de HOY cambia la consulta al pasar la medianoche de Lima.
- Carga, error y vacío distintos. Si falla otra página, conserva las filas ya
  cargadas. El foco pasa al primer lead nuevo o al reintento si falla.

## Verificación

- **PASS** `npm run check`: 5.031 tests / 323 archivos, lint, tipos, cobertura,
  configuración de release, build, bundle y duplicación.
- **PASS** comprobación dirigida final: 58 tests, incluidos sondeo visible,
  medianoche, recepción frente a creación, otras etapas, ámbito demo, error de
  segunda página, foco y descripción accesible con hora aproximada.
- **PASS** E2E local Docker: `hoy-leads-recibidos`, `demo-roles` y
  `sla-operacion`: 26/26. Tras los ajustes de accesibilidad/recarga, repetición
  del spec del bloque: 2/2. HTTP simulado; no acredita una sesión productiva.
- **PASS** revisión de capturas en escritorio 1512×900, portátil 1280×800 y
  móvil 390×844. Citas con y sin filas, ancho y espacio útil verificados.
- **PASS** `git diff --check` en los archivos existentes modificados.
- **NOT RUN** gate de realidad: el comando salió por falta de `SUPABASE_URL`.
  En la preparación de publicación se comprobó además el contrato vivo mediante
  el conector Supabase (ver abajo). No se modificó backend/configuración.

El lint conserva cuatro avisos previos de accesibilidad en
`components/ui/coverflow-carousel.tsx`, fuera de este cambio. Un intento E2E
falló limpiando artefactos antiguos (`ENOTEMPTY`); la corrida final con salida
propia `app/artifacts/hoy-leads-20261005-final/` terminó 2/2.

## Review independiente y decisiones del PRIMARY

Claude, mediante `scripts/claude-review`, devolvió CHANGES_REQUESTED sin P0/P1.
Se aceptaron el refresco estando abierto, conservar filas tras error, plural y
texto accesible del contador, descripción de teléfono/hora, foco de paginación
y ciclo horario h23. Todos quedaron cubiertos por pruebas.

Dos hipótesis se contrastaron con código existente: `vivos` es `count(*)` de la
misma base filtrada (migración `20260929195918_crm_leads_reasignados.sql`, sección
`metricas`), y el espejo usa `ambito.length` (`lib/resumen-cartera.ts`). El filtro
`p_vendedor_id` aplica junto al ámbito autorizado; no hay prohibición por rol
vendedor en esa función. En la preparación de publicación se verificó también el cuerpo vivo y su ejecución bajo el rol autenticado.

Se conserva el bloque fuera del boundary cuando SLA no está activo: una avería
de seguimiento no debe ocultar la recepción. Al resolverse el modo puede cambiar
de posición; la caché y los filtros son los mismos. Las listas tienen scroll
interno para conservar el espacio de citas.

Solo se tocaron los dos archivos de HOY previamente limpios y se añadieron el
componente, sus tests y el spec. Se preservaron los cambios ajenos del árbol.
La autorización posterior de publicación y su resultado se registran debajo.


## Preparación de publicación autorizada

Se trasladó únicamente el parche de HOY a una copia limpia de `avancecorp/main`
`447208e1`, conservando Bases y los cambios remotos. Frente al build vivo
`build-20261005T023047087Z` (`27e6f24849aa`), el árbol de `app` en remoto solo
cambia un test (`receptor-llamada.test.tsx`); el runtime previo es idéntico.

**PASS** contrato vivo de `crm.cartera_filtrada_fn`: SECURITY INVOKER, permiso
EXECUTE para authenticated, `p_vendedor_id` y límites diarios en America/Lima.
Consulta con transacción READ ONLY, JWT de un analista activo y rol authenticated:
9 recibidos, 9 filas, todas del titular y día correctos. No se registraron datos
personales ni se alteraron filas. `totales.vivos` es `count(*)` de la base filtrada.

El primer check sobre la versión actual detectó que el arnés de HOY carecía del
QueryClientProvider que ahora requiere la cartera. Se añadió el contexto de
caché real manteniendo los mocks de red. 71 pruebas dirigidas pasaron. El primer
E2E detectó que, en demo móvil, el nuevo bloque desplazaba la primera acción;
se colocó después de las prioridades, sin cambiar la ubicación activa.

**PASS** check integral sobre la versión actual: 6.091 tests / 378 archivos,
lint (los cuatro avisos previos), tipos, cobertura, build, bundle y duplicación.

**PASS** repetición E2E final en Docker: 26/26 (`hoy-leads-recibidos`,
`demo-roles`, `sla-operacion`), sin fallos ni reintentos. Capturas en escritorio,
portátil y móvil; primera acción demo y espacio de citas verificados.

El preflight rechazó el primer artefacto `acf8e4c3b668`: el historial remoto no
contenía al vivo `27e6f24849aa`, aunque su runtime era idéntico. Según CLAUDE.md,
se creó `rescue/hoy-leads-recibidos-20261005` desde el vivo, en copia separada.
Se integró `avancecorp/main` preservando byte a byte su árbol (`fac4f404`) y se
aplicó el parche verificado (`798a746b`). Los tres conflictos eran actas y el
banco RLS: se conservaron las versiones remotas actualizadas. No se aplicó SQL.
`git diff acf8e4c3b668 798a746b` vacío; los checks corresponden al mismo código.
El vivo es ahora ancestro real del candidato. Se reconstruye desde fuente limpia,
se repitió el preflight y se abrió la PR de esta misma rama para integrar a Main.

Recuperación conservada: `crm-20261005T023047Z-27e6f24849aa.zip`, SHA-256
`31d974446fc2c61bcb9a21c0764e460a6448531f0e69f140235d7b4cf1c704f9`.


## Publicación efectiva

- Build vivo: `build-20261005T154516511Z`.
- Fuente limpia: `a98cf73fbd2866ee79f7f8801475631d010c2616`.
- ZIP: `crm-20261005T154517Z-a98cf73fbd28.zip`.
- SHA-256: `8f4bef27c3f705a601b7c3d4f8a41fda1ef753fbae486698081a69e35a395977`.
- Preflight y verificación del artefacto PASS. Hostinger oficial aceptó el despliegue.
- HTTPS: portada y 96/96 HTML/JS/CSS/version devuelven 200 y SHA-256 exacto;
  `version.json` idéntico al ZIP. Sin cambios de base de datos.
- Acceso productivo PASS con sesión existente de gerencia. HOY de analista en
  sesión productiva: NOT RUN, no había sesión de ese rol en el navegador;
  recorrido E2E simulado y consulta real READ ONLY del rol sí pasaron.
- PR: https://github.com/avanza-digital/avancecorp-crm/pull/191.
- Copia aislada de publicación: `/private/tmp/avancecorp-hoy-20261005-release`.
  El taller original conserva sus cambios ajenos e historial local divergente.


## Cierre de verificaciones e integración pendiente

GitHub **PASS**: app-check, verify, preflight y cambios para el HEAD publicado
`a98cf73fbd2866ee79f7f8801475631d010c2616`. Supabase Preview: SKIPPED por su integración,
no se usó como evidencia. E2E exclusivamente locales en Docker.

La fusión normal `gh pr merge 191 --squash --match-head-commit a98cf73fbd2866ee79f7f8801475631d010c2616`
fue rechazada por la política de Main: `REVIEW_REQUIRED`. Hace falta la aprobación
de otro revisor; `allow_auto_merge=false`. No se usó `--admin` ni se modificaron
protecciones. Se solicitó a Miguel gestionar esa revisión. El despliegue está
completo, pero la integración a Main sigue pendiente. Mantener la rama de rescate.

Se preservaron ZIP y manifiesto en el taller original y se trajeron los objetos
de la rama publicada para que futuros preflights resuelvan la versión viva.
Se sincronizaron solo los ajustes propios de HOY en el taller; sus 58 pruebas
dirigidas pasan. No confundir su Main local antiguo con la fuente del despliegue.
