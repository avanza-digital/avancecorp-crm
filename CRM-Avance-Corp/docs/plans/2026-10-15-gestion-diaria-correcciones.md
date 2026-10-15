# Plan de implementación — Gestión Diaria: las 12 correcciones del prototipo aprobado

**Estado:** las 4 decisiones de Jhosep quedaron tomadas el 15/10 (§7). Falta:
- la confirmación por escrito de Miguel de las divergencias (§6);
- la revisión de Codex (encargo `docs/encargos/2026-10-15-codex-plan-gestion-diaria-correcciones.md`).

Sin código hasta tener ambas.

**Fecha:** 15/10/2026. **PRIMARY:** Claude (sesión de Jhosep). **Revisor previsto:** Codex (agente de Miguel).

**Fuentes**
- Prototipo aprobado: https://claude.ai/artifact/6Tm62NQ7vjpiLWkk2DZNzP (v26). Lo aprobó Jhosep el 15/10, con acuerdo verbal de Miguel. Es privado: Jhosep lo comparte desde «Share».
- Las 12 correcciones: §0 de este documento. La lista de trabajo con el análisis de cada una es local de Jhosep.
- Contrato de Miguel para llamadas (vinculante): `9b26fab2`, `docs/encargos/2026-10-13-llamadas-crm-unificadas.md`. Solo está en `origin/crm/llamadas-flujo-unico-contrato-20261013`, no en `main`.
- Cinco análisis de solo lectura del 15/10: escritura en base, lecturas y cola, pantalla del analista, supervisor y gerencia, y contrato con protocolo. Sobre `main` local `4ec46ba3`.

**Base de código**
- GitHub `main` está en `597cab1c`, 22 commits por delante. Verificado el 15/10 con `git diff` que esos commits no tocan:
  - las pantallas de `screens/gestion-diaria` ni `components/gestion-diaria`;
  - `lib/gestion-diaria-*.ts` ni `lib/llamadas-celular*.ts`;
  - la cola `20260930190028` ni su banco.
- Sí cambiaron `data/gestion-diaria-cola-queries.ts` (#277, 3 líneas) y otras zonas de `lib/store.tsx` (las líneas se corren unas 5).
- `20261014001346` reescribe `private.sla_operacion_leads` por rendimiento y «conserva … reglas SLA» (cabecera, línea 3). Las ramas `tarea_vencida`, `tarea_hoy` y `proxima_tarea` siguen iguales (líneas 223–234).
- Las líneas citadas aquí se revalidan al integrar `main`.

**Plan de llamadas:** EN PAUSA hasta cerrar este plan (Jhosep, 15/10). §11 dice qué queda para entonces.


---

## 0. Las 12 correcciones aprobadas

Regla de Jhosep (14/10): «una llamada es una llamada, venga de donde venga». En pantalla no hay etiquetas de origen ni la
palabra «captura»; solo el resultado, «Sin resultado», «Por revisar» y «Tareas pendientes».

1. **Analista:** la pestaña «Celular» pasa a «Sin resultado · N» y lista solo lo pendiente: las llamadas sin resultado y
   las deshechas de hoy, con «Registrar el corregido». Sale «Qué pasó hoy», que repetía «Mi actividad».
2. **Descartar** pide un motivo escrito libre, de 3 a 300 caracteres, que se envía como `otro` + texto. Supervisor y
   gerencia lo ven.
3. En vez del botón «Unir a un resultado guardado», **la fila pregunta sola**, solo si hay un resultado cercano: «¿Ya
   registraste esta llamada? A las 10:32 …» [Sí, es esa] [No, registrar resultado]. Nunca une sola.
4. **Cola:** sin la pastilla «Todo». Orden Hoy → Sin primer intento → Vencidas → Contactar de nuevo. Arranca en el primer
   bloque con gente y, al vaciarse uno, pasa solo al siguiente.
5. **Las pastillas cuentan solo lo por hacer.** Lo gestionado sale del bloque: a «Mi actividad», a «Hoy» si se acordó un
   reintento para hoy, o a «Mi seguimiento».
6. La pastilla «Sin conversación» pasa a **«Contactar de nuevo»**. Los chips de fila no cambian.
7. **La ayuda del filtro activo** va resaltada a la derecha de las pastillas, visible en todos los anchos.
8. **Paginación numerada** tipo Google, centrada, con 7 casillas como máximo, más «Anterior» y «Siguiente».
9. **«Vencidas»:** primero las que vencieron hace menos. Al gestionarlas salen del bloque, salvo si se desmarca «Cerrar
   también».
10. **Supervisor:** salen el bloque «Su celular» y la línea del celular. Queda un aviso «N llamadas sin resultado · M por
    revisar» cuando hay alguna.
11. **Ficha del analista** (supervisor y gerencia): pestaña «Descartes» (hora, lead y motivo) y, en Resumen, una línea
    «N llamadas descartadas hoy · Ver motivos ›».
12. **Gerencia:** sale la 3.ª pestaña «Llamadas del celular». La ficha del analista dentro de un equipo es igual a la del
    supervisor.

## 1. Resumen y recomendación

- Las 12 correcciones **no necesitan cambiar cómo se guardan las llamadas**. Descartar con motivo, «Sí, es esa» y «Registrar el corregido» usan puertas que ya existen y que el contrato conserva. Lo confirmaron por separado el análisis de escritura y el del contrato.
- Sí necesitan **3 lecturas nuevas en la base**, todas aditivas (se suman sin tocar lo existente):
  - la cola del analista v2 (correcciones 4, 5 y 9);
  - los descartes con motivo (11);
  - los candidatos de la pregunta «¿Ya registraste esta llamada?» (3).
  El contrato no reemplaza la cola, y las otras dos son compatibles con él. Las deshechas de días anteriores quedan para después (decisión 4).
- Hallazgo que cambia el diseño: **en el CRM real «Hoy» nunca tiene llamadas listas para hacer.** Una tarea de hoy figura «programada» hasta su hora y, al llegar la hora, pasa a «Vencidas». Jhosep decidió qué es «Hoy» (§7, decisión 2): cuenta desde la mañana y «Ahora» lo propone a su hora.
- Cuatro correcciones (1, 3, 10 y 12) se apartan del texto escrito del contrato. Miguel las aceptó de palabra, pero Codex revisa contra lo escrito: hace falta su confirmación por escrito en el #270 (§6).
- **Decidido (Jhosep, 15/10): NO unir con el plan de llamadas.** Este plan va aparte, con la frontera de §2:
  - dos PR: uno de pantalla ya, y otro de base con la pantalla que depende de ella;
  - documentos al #270.
  Unir exigiría antes las entregas B–D del contrato: comando nuevo, identidad de cada llamada, lectura única, 26 casos y pruebas de concurrencia. Eso es bastante más trabajo y riesgo, y no lo necesita ninguna corrección.

## 2. Frontera: qué va ahora y qué espera al plan de llamadas

| Ahora (este plan) | Espera al plan de llamadas (contrato B–E) |
|---|---|
| Correcciones 1–12 con las lecturas aditivas de §5 | Comando común `registrar_llamada_v6` y guarda de la v5 (§3 del contrato) |
| Quitar `sin_dato` de los motivos de atención (hallazgo C1-1) | Identidad de llamada (`llamada_id`) y lectura única con cursor y `conteo_estado` (§4) |
| «Tareas pendientes» (hallazgo C1-3) | «Por revisar» excluyente con «Sin resultado», incluidas las que tienen candidato (§4) |
| Deshechas de hoy en «Sin resultado» (decisión 4) | Cifras unificadas en los cuadros del supervisor y «Necesitan atención» con llamadas (§6) |
| | Columna «Sin resultado» y totales en la tabla de gerencia (§6) |
| | Deshechas de días anteriores en la lista del analista (hallazgo C1-2; decisión 4; diseño M3 en §5) |
| | Una fila por llamada en «Mi actividad», si Miguel lo sostiene (divergencia 1) |
| | Lote #21 sobre la v6 (§7); la rama `f7c9fecf` no se aplica |
| | Propuesta: descartar la F5 «Jev» del plan de llamadas (Jhosep, 15/10) |

**Regla para no rehacer trabajo**
- Lo de ahora lee por funciones o hooks con fuente intercambiable: `useSinResultado`, `useCandidatosUnion` y una sola función de `lib` que traduce las cifras al aviso.
- Al retomar el contrato, cambia la fuente y no la pantalla.

## 3. Fases y PR (un solo PR abierto a la vez: `COORDINACION.md`, regla 1)

| Fase | Qué | PR | Nivel de riesgo y revisión | Quién cierra |
|---|---|---|---|---|
| F0 · Preparar | Comentario en el #270 (§6), documentos al #270, fusión del #270 e integrar `main` | #270 (docs) | 1, sin revisión | Miguel fusiona |
| F1 · Pantalla sin base | 1 (con las deshechas de hoy), 2, 6, 7, 8, 10, 12, C1-1 y C1-3 | PR-1 | 2, 0–1 revisión | Miguel publica (preflight) |
| F2 · Base y pantalla dependiente | M1, M2 y M4 (§5) y, encima, 3, 4, 5, 9 y 11 | PR-2 | 3, 1 revisión (máximo 2) | Miguel aplica el SQL y después publica |
| F3 · Cierre | Aceptación en el C1 con los tres roles, documentos, vault y memoria; retomar llamadas | — | — | Jhosep acepta |

**F0 · detalle (sin código)**
1. Comentario en el #270 con formato QUÉ HICE · RESULTADO · TURNO PARA:
   - pausa del plan de llamadas;
   - prototipo aprobado;
   - la frontera de §2;
   - las divergencias de §6, numeradas («basta contestar 1 sí, 2 no…»);
   - los 26 casos en NOT RUN, dicho tal cual;
   - F5 «Jev» como propuesta.
   Lo publica Claude **con el OK de Jhosep**: es un mensaje hacia afuera.
2. Documentos en el mismo #270:
   - `COORDINACION.md`: cabecera, pausa y mapa de PR;
   - `PROPUESTAS-DE-AJUSTE.md`: la fila 23 dice «cambio de cómo se muestra, no de la base» y lo contradice el §2 P2 del contrato; además, fila nueva para F5 «Jev»;
   - `P21-PLAN-CORTO.md`: nota de pausa (sus líneas 40–43 quedaron atrás del código local).
3. Miguel confirma y fusiona el #270.
4. `git fetch` e integrar `main` (`597cab1c` o la que esté). Rama nueva desde `main`.

**F1 · PR-1 (solo pantalla)**
Ver §4 por corrección. Incluye borrar el código muerto (§4.3) y sus pruebas. No toca la base.

**F2 · PR-2 (base y pantalla)**
- Primer commit: migraciones M1, M2 y M4, cada una con reversa, registrador, oráculo, `test-rls`, ledger y `gen:types`.
- Segundo commit: la pantalla sobre ellas.
- Despliegue: **primero el SQL** (Miguel: rama de Supabase → gate → advisors → aplicar). Después, fusión y release.

## 4. Por corrección

Rutas: `app/` = `CRM-Avance-Corp/app/src/`; `mig/` = `CRM-Avance-Corp/supabase/migrations/`. [V] = leído en el código por los análisis; [S] = supuesto o propuesta.

| # | Hoy (evidencia) | Cambio | Fase | Tipo |
|---|---|---|---|---|
| 1 | Pestaña «Celular · N», con N = filas descargadas (`analista.tsx:672-674`). Vistas «Pendientes / Qué pasó hoy» (`llamadas-celular.tsx:45,66-77,301-324`). Las deshechas solo están en «Qué pasó hoy», que se corta por la fecha del enlace (`mig/20261006162813:383-385`) [V] | «Sin resultado · N»: pendientes + deshechas corregibles (`puedeRegistrarCorregido`, `lib/llamadas-celular.ts:236-240`) con «Registrar el corregido» (`analista.tsx:179-190`). Se quita «Qué pasó hoy». N exacto si la lista cabe en una página; si no, «50+». Se quitan los textos de origen (`llamadas-celular.tsx:69,85,88`; `lib/llamadas-celular.ts:279-282,309-314`; `registrar-resultado.tsx:480,523`) | F1 (solo las deshechas de hoy: decisión 4) | Pantalla |
| 2 | Lista cerrada + «Otro»; ya envía `otro` + texto de 3 o más (`llamadas-celular.tsx:199-236`). La base exige 3–300 tras recortar, además de un CHECK (`mig/20261005143843:769-778`) [V] | Un solo campo obligatorio de 3–300, con foco y el aviso «Lo verá tu supervisor». El largo se cuenta en caracteres reales y se envía recortado | F1 | Pantalla pura |
| 3 | «Unir…» aparece en toda pendiente con lead (`llamadas-celular.tsx:168-172`); los candidatos se piden al abrir el panel (`:248-299`, `data/llamadas-celular-api.ts:164-182`) [V] | La fila pregunta sola, solo si M4 devuelve un candidato (decisión 3): «¿Ya registraste esta llamada? A las 10:32 …» [Sí, es esa] [No, registrar resultado]; con varios, «¿Cuál de estos es?». «Sí, es esa» → `crm.enlazar_llamada_celular` (`api.ts:186-194`), que el contrato conserva (§3.1). Si lo registró otra persona: «Ana registró…» | F2 | Base y pantalla |
| 4 | «Todo» por defecto (`lib/gestion-diaria-cola.ts:78`). Orden actual: Sin primer intento → Vencidas → Hoy → Sin conversación (`lib/gestion-diaria-analista.ts:129-134`). No salta al vaciarse un bloque (`analista.tsx:253,394-405`) [V] | Sin «Todo». Orden Hoy → Sin primer intento → Vencidas → Contactar de nuevo. Arranca en el primer bloque con gente; al vaciarse, salta y lo avisa. «Hoy» = todo lo de hoy desde la mañana, con su hora; «Ahora» lo propone desde su hora (decisión 2). Orden y salto salen del servidor (M1) | F2 | Base y pantalla |
| 5 | `total` = pendientes + gestionados + programados (`mig/20260930190028:221-231`). Lo gestionado conserva su grupo (`:137-139`). El banco exige «reintento futuro fuera de pendientes» (`scripts/gestion-diaria-cola/prueba.sql:91-112`) [V] | Las pastillas cuentan y listan solo lo «por hacer»; lo gestionado sale, salvo un reintento de hoy, que va a «Hoy» (M1, decisión 2). Se retiran la leyenda, «Vuelta completada» y `siguienteTrasGuardar` (`cola-de-hoy.tsx:113-119`, `analista.tsx:810`, `gestion-diaria-analista.ts:363-394`) | F2 | Base y pantalla |
| 6 | Etiqueta en `lib/gestion-diaria-analista.ts:133` (solo la usa la cola) [V] | «Contactar de nuevo» solo en la pastilla; los chips de fila no cambian | F1 | Pantalla pura |
| 7 | Ayuda absoluta, `hidden … 2xl:flex` (`cola-de-hoy.tsx:99`): solo se ve desde 1536 px [V] | Por la ranura `acciones` de `Tabs`, que ya baja de línea (`components/ui/tabs.tsx:48-52,150-155`). 14 px seminegrita. Usar `claseLista`, porque los selectores de `cola-de-hoy.tsx:110` dejan de aplicar al envolver | F1 | Pantalla pura |
| 8 | «1–8 de 97» visible y Anterior/Siguiente (`cola-de-hoy.tsx:165-181`). `Paginacion` común sin números (`components/common/paginacion.tsx:34-53`) [V] | `ventanaPaginas()` (nuevo, en `lib/`): 7, 5 o 3 casillas según el ancho (`lib/media.ts:35,101`), centrada, `aria-current="page"`, «…» oculto al lector, rango solo para lector con `role=status`. Sirve con la v1 y con la v2 | F1 | Pantalla pura |
| 9 | Orden por `referencia_en` ascendente: la más vieja primero (`mig/20260930190028:239`). Una vencida gestionada con la tarea abierta queda «gestionada» (`:156`) [V] | Vencidas en orden descendente, con desempate estable. Sale al gestionarse, salvo si se desmarca «Cerrar también» (M1) | F2 | Base y pantalla |
| 10 | Bloque `SuCelularAnalista` (`panel-analista-supervisor.tsx:144-146`) y pie «Tu celular: …» (`screens/gestion-diaria/supervisor.tsx:66-68,322`) [V] | Se borran los dos. Aviso ámbar «N llamadas sin resultado · M por revisar» con props propias de `ResumenAnalista`, después de las vencidas (no por `antesDeCuadros`, que pinta antes: `resumen-analista.tsx:63-64`). **Sin enlace** (Decisión 1). Cifras de F4-e: N = `pendientes.total + deshechas_sin_corregir`, M = `por_revisar` (`mig/20261013145935:157-187`). Si falla, una línea con «Reintentar» | F1 | Pantalla pura |
| 11 | `PestanaPanel` sin «Descartes» (`panel-analista-supervisor.tsx:27,192`); separación de 22 px (`:193`) [V] | 5.ª pestaña «Descartes»: lista con hora, lead y motivo, y vacío «Ningún descarte hoy». Línea en Resumen «N llamadas descartadas hoy · Ver motivos ›». 18 px de separación. Datos de M2, una consulta al abrir la ficha que reutiliza la pestaña (Decisión 4). Copia el patrón de `citas-agendadas.tsx:25-58` y `etiquetaMotivoDescarte` (`lib/llamadas-celular.ts:265-268`) | F2 | Base y pantalla |
| 12 | 3.ª pestaña (`screens/gestion-diaria/gerencia.tsx:47`, ramas `:125,131-132,264-267`). La ficha dentro del equipo no recibe `celularHoy` (`vista-equipo-gerencia.tsx:221-225`) [V] | Quedan dos pestañas. Se activa `useOperacionCelularHoy` con la ficha abierta (`esHoy && ruta && grupo`) y se pasa a `PanelAnalistaSupervisor`. Ya autoriza a gerencia (`data/llamadas-celular-operacion-queries.ts:33`) y su 42501 sigue retirando la vista (`gerencia.tsx:126-129`) | F1 | Pantalla pura |
| C1-1 | `motivosAtencion` añade `sin_dato` y la salud del aparato (`lib/llamadas-celular-operacion.ts:142-157`); solo lo usa la 3.ª pestaña (`llamadas-celular-gerencia.tsx:207`) [V] | Se borra con la 12 | F1 | Pantalla pura |
| C1-3 | Cuadro «Pendientes» (`resumen-analista.tsx:108`) y pestaña «Pendientes» (`panel-analista-supervisor.tsx:192`) [V] | Cuadro «Tareas pendientes» y pestaña «Tareas» (Decisión 3) | F1 | Pantalla pura |

**Comportamientos del prototipo que ya existen [V]:**
- «Ahora» no vuelve a proponer el lead recién registrado (`analista.tsx:388-405`, `mig/20260930190028:255-258`, prueba en `analista.test.tsx:292-311`).
- «Llamar» copia el número y avisa (`components/app/contacto.tsx:229-242,293-300`).

**Nuevo:** cambiar de página sin cambiar «Ahora». Hoy `irAPagina` borra el elegido (`analista.tsx:306-310`). Se resuelve en M1: devuelve la página pedida y el elegido vigente por separado, sin anclar la página a él.

### 4.3 Código que se borra y código que se conserva (F1) [V]

**Se borra:**
- `components/gestion-diaria/su-celular-analista.tsx`, con su export `COLOR_TONO`;
- `llamadas-celular-gerencia.tsx`, con `SinDato`;
- en `lib/llamadas-celular-operacion.ts`: `porcentaje` y las líneas `:122-206`;
- el hueco `antesDeCuadros` (`resumen-analista.tsx:38-39,63`);
- los imports en `panel-analista-supervisor.tsx:12`, `supervisor.tsx:12` y `gerencia.tsx:20`.

**Se conserva:**
- `useOperacionCelularHoy` y `obtenerOperacionCelularHoy`, que alimentan el aviso (hay que corregir sus comentarios);
- los esquemas, `sumarCifras`, `sumarCelulares`, `claveEquipoCelular` y `plural`, que usa la demo (`lib/llamadas-celular-operacion-demo.ts:10,75-77`);
- `MOTIVOS_DESCARTE` y `etiquetaMotivoDescarte`, para leer los descartes viejos.

### 4.4 Pruebas que cambian [V]

- **F1, se borran o reescriben:**
  - `su-celular-analista.test.tsx` (4) y `llamadas-celular-gerencia.test.tsx` (4);
  - `screens/gestion-diaria/gerencia-demo.test.tsx:73-99` (2);
  - `lib/llamadas-celular-operacion.test.ts:77-108` (4);
  - `e2e/llamadas-celular-operacion.spec.ts:5-31` (2);
  - `llamadas-celular.test.tsx` (61-84, 99-140, 176-216) y `lib/llamadas-celular.test.ts:118-135`;
  - en `analista.test.tsx`, los bloques «Celular», «Qué pasó hoy» y «Unir» (1350-1486) y el rango visible (620-638).
- **F2:**
  - `analista.test.tsx` (240-272, 507-516, 596-605, 682-703, 811-841);
  - `lib/gestion-diaria-analista.test.ts` (41-51, 317-352) y `registrar-resultado.test.tsx:497-504`;
  - `data/gestion-diaria-cola-api.test.ts` y `-queries.test.tsx`, con el fixture `gestion-diaria-cola-sql.fixture.json` y `version` en `lib/gestion-diaria-cola.ts:40`;
  - los E2E `gestion-diaria-analista.spec.ts`, `gestion-diaria-vuelta.spec.ts` (simula la RPC con `paginarTrabajoDemo`) y `llamadas-celular.spec.ts`;
  - SQL: `prueba.sql:91-112`.
- **Que no deben romperse:** `resumen-analista.test.tsx:37-38` toma los 4 primeros `term`, así que el aviso y la línea no pueden usar `<dt>`. Tampoco los mocks con `datos:null` de `gerencia.test.tsx:18` y `supervisor.test.tsx:14`.
- **Nuevas:**
  - `ventanaPaginas` con 1–7, 13 y 120 páginas;
  - aviso: singular, plural, 0 oculto, analista sin celular y error;
  - las 5 pestañas, «Ver motivos» que enfoca y nada consultado antes de abrir;
  - descartes: carga, vacío, error, 42501, «otro» y descarte hecho por otra persona;
  - cola v2: sin «Todo», orden, salto con aviso, página sin cambiar «Ahora», no repetir el recién registrado;
  - lista «Sin resultado»: «Registrar el corregido», 3–300, «50+»;
  - **el estado de producción** (regla del gate de realidad): «Hoy» vacío, ningún candidato, sin capturas.
- **Demo:** `lib/gestion-diaria-cola-demo.ts:9-71` imita la cola y también sirve de servidor simulado en `analista.test.tsx:86-98` y en el E2E de la vuelta. Cambiarla afecta a los tres.

## 5. Migraciones propuestas (todas en PR-2)

Reglas comunes:
- `/nueva-migracion`, formato `AAAAMMDDHHMMSS_crm_<tema>.sql` y ledger `MIGRACIONES.md`.
- Núcleo INVOKER sin EXECUTE para nadie; puerta DEFINER con `set search_path = ''`, rol y ámbito verificados dentro.
- `revoke` a public, anon, authenticated y service_role; `grant` solo a authenticated en la puerta.
- `COMMENT ON` en todo; postflight como F4-e (`mig/20261012192500:353-399`); reversa sin datos (`drop` de lo nuevo).
- Registrador: md5 del archivo en LF más `md5(prosrc)`, atributos y ACL.
- `auditor-rls` antes del gate, `npm run gen:types` y declarar las funciones en el censo analítico si aplica [S] (`mig/20261013145852:56`).
- Ninguna toca la v1 de la cola, `private.sla_operacion_leads` (sellada por md5 en `20261014001346:10-13`), v4, v5 ni `enlazar`.

| | Objetos | Contenido | Pruebas |
|---|---|---|---|
| **M1** `…_crm_gestion_diaria_cola_trabajo_v2.sql` | `private.gestion_diaria_cola_filas_v2(uuid,text,timestamptz)` y `crm.gestion_diaria_cola_trabajo_v2_fn(p_filtro text default null, p_pagina int default 0, p_limite int default 8, p_elegido text default null)` → `version: 2` | Reutiliza `gestion_diaria_cola_hechos`, `sla_operacion_leads` y `tareas_clientes_autorizadas`. «Por hacer» (decisión 2): «Hoy» = tareas que vencen hoy, haya llegado o no su hora (las `tarea_hoy` y las `tarea_vencida` de hoy); se listan desde la mañana con su hora, y «Ahora» solo las elige desde esa hora. «Vencidas» = vencimiento anterior a hoy. Lo gestionado sale salvo un reintento de hoy, o «Cerrar también» desmarcado. Orden por bloque: Hoy por hora, Sin primer intento por plazo, Vencidas DESC; desempate `clave collate "C"`. Filtro nulo = primer bloque con gente; `'todo'` → 22023. `siguiente` salta de bloque. Página y elegido por separado | Banco de la cola `scripts/gestion-diaria-cola/ensayar.mjs` (hay que reconstruir su contenedor: README:108). Casos: lo de más tarde, reintento hoy/mañana, «Cerrar también», Vencidas DESC con empates, nulo y `'todo'`, ancla entre bloques, Deshacer, 23:59/00:01 de Lima, supervisor con 530 leads; un mutante por regla. Bloque `test-rls` (molde F4-e `test-rls.mjs:18933-19045`). EXPLAIN ≤ 250 ms con 530 leads (la v1 midió 228 ms: `docs/encargos/gestion-diaria-cola/RELEASE.md:17`) [S] |
| **M2** `…_crm_llamadas_celular_descartes_lectura.sql` | `crm.llamadas_celular_descartes_fn(p_analista_id uuid, p_dia date default null, p_limite int default 50, p_antes_descartado_en timestamptz default null, p_antes_id uuid default null)` → `{dia, generado_en, analista_id, total, filas[{id, llamada_en, descartado_en, lead_nombre?, motivo, motivo_detalle?, descartado_por_nombre?}], siguiente}` | Supervisor: `vendedor_ids_visibles`. Gerencia: `gestion_diaria_pulso_roster()`, como F4-e. Otro rol: 42501. Corte por `descartado_en` (Decisión 6). Lead fuera de ámbito: nombre oculto y fila visible. Nunca el número ni el id de origen. `p_dia` dentro de `dias_retencion_descartados` (30); fuera, 22023. El índice ya existe (`mig/20261005224330:61-62`) | Pasada nueva de `npm run test:llamadas:local` (en Windows, los `.sql` del banco van en LF): aplicar, negarse a repetir, oráculo, huella tras la reversa y mutantes de ámbito, nombre oculto y retención. `test-rls`: sin `numero`, mismas cifras para cualquier rol, EXPLAIN < 100 ms (`F4E-CONTRATO.md:181-182`) |
| **M3** `…_crm_llamadas_celular_deshechas_lectura.sql` *(DESCARTADA por ahora, decisión 4; el diseño queda guardado para el plan de llamadas)* | `crm.llamadas_celular_deshechas_fn(p_limite int default 50, p_antes_deshecho_en timestamptz default null, p_antes_id uuid default null)`, solo del analista que pregunta | Deshechas sin corregir de **cualquier fecha** (hoy, una registrada ayer y deshecha hoy no aparece en ningún sitio: Deshacer no toca el enlace, `mig/20261005182227:113`). Forma de fila igual a la bandeja, más el estado del lead (abierto, cerrado o vetado) y `puede_corregir`, para no ofrecer una escritura prohibida (hallazgo C1-2). Lo que cuenta en N usa el mismo predicado que `deshechas_sin_corregir` de F4-e, que exige lead abierto (`mig/20261013145935:169-171`): así cuadran el analista y el supervisor [S] | Pasada del banco reducido con oráculo (ayer → hoy, cerrado, vetado, corregida, otro analista) y mutantes. `test-rls` por rol |
| **M4** `…_crm_llamadas_celular_candidatos.sql` *(decisión 3)* | `private.llamadas_celular_candidatos(p_actor uuid, p_evento_ids uuid[])` y `crm.llamadas_celular_candidatos_fn(p_evento_ids uuid[])` | El mismo predicado que `enlazar` (`mig/20261005143843:684-716`), sin enlace y **sin intención pendiente**. Ámbito por `llamada_celular_visible`. Entre 1 y 200 ids; si no, 22023. Hasta 3 candidatos, con `hay_mas` y `es_propio`. Su núcleo es el predicado de «Por revisar» que necesitará la Entrega B | Oráculo K1–K12 y mutantes (filtro de intención, filtro de enlace, margen de 11 min, visibilidad). Paridad: todo lo que devuelve lo acepta `enlazar`. `test-rls` con la bandera `CRM_RLS_EXIGE_LLAMADAS_CANDIDATOS` |
| **Después** | Retirar la v1 de la cola | Cuando el build publicado ya no la llame (`LEEME.md:18-26`) | — |

## 6. Divergencias que Miguel debe confirmar por escrito (en el #270)

Cada una cita el contrato `9b26fab2` y lleva una recomendación.

1. **El analista conserva una pestaña, «Sin resultado · N»,** en vez de llevar sus filas a «Mi actividad». §6: «Quitar la pestaña separada «Celular». En «Mi actividad → Llamadas» mostrar una fila por llamada». *Recomendación:* aceptarla como el sitio del trabajo pendiente; la fusión con «Mi actividad» queda opcional para la Entrega C.
2. **Hasta la Entrega B, las llamadas con candidato siguen contando en «Sin resultado».** §4: «se clasifica en revisión, no además en «Sin resultado»». *Recomendación:* aceptarlo como transitorio y decirlo en pantalla. En B, «Por revisar» = ambiguas + de la bolsa + con candidato, excluyente.
3. **Deshechas antiguas: solo las de hoy hasta retomar llamadas** (decisión de Jhosep). §6, hallazgo 2: «permitir localizar las deshechas antiguas corregibles». *Recomendación:* aceptarlo como transitorio; el diseño de su lectura (M3) queda en el plan.
4. **Supervisor:** sale «Su celular», pero los cuadros y «Necesitan atención» no cambian hasta B; la llamada sin resultado se avisa en la ficha. §6: «consumir las mismas cifras autorizadas en los cuadros actuales. «Necesitan atención» muestra acciones pendientes reales». *Recomendación:* aceptar el aviso hasta B.
5. **Gerencia:** se quita la 3.ª pestaña antes de integrar sus cifras en la tabla. Mientras tanto, las cifras se ven por analista en la ficha, no por equipo. §6: «Integrar llamadas, pendientes y cobertura en la tabla habitual… quitar la tercera pestaña». §8 C: «Retirar componentes separados solo después de cubrir sus acciones»; la pestaña no tiene acciones de escritura (`llamadas-celular-gerencia.tsx:6`). *Recomendación:* columna «Sin resultado» cuando exista la lectura única.
6. **La cobertura del celular solo está en Configuración → Celulares;** no aparece en Gestión Diaria (regla de Jhosep, 14–15/10). §5: «Mostrar el estado de cobertura sin dividir el trabajo». Ojo: el supervisor se queda sin pantalla de latido, aunque `crm.celulares_salud_fn` le responde (`mig/20261001212258:439-440`).
7. **Rótulo del conteo provisional:** §4 pide «declarar el conteo provisional», y la regla de Jhosep quita esa palabra. *Recomendación:* acordar ya un rótulo para B (por ejemplo, «—» con «N por revisar»).
8. **El prototipo no dibuja los estados de error** (la Entrega A los pide). *Recomendación:* se reutilizan los estados reales (`llamadas-celular.tsx:78-81` y los de cada lista), probados en las pruebas de pantalla.
9. **Pausa:** las Entregas B, D y E, y la parte de C de §2, quedan para después. Los 26 casos, NOT RUN.

## 7. Decisiones

### Para Jhosep (respondidas el 15/10 con el formulario)

1. **Estrategia:** aparte del plan de llamadas, con la frontera de §2 (era la recomendada).
2. **Qué es «Hoy»:** cuenta todo lo de hoy desde la mañana, con su hora. «Ahora» lo propone desde su hora y, ya pasada, va primero. Lo de días anteriores va a «Vencidas» (era la recomendada).
3. **Dónde pregunta la corrección 3:** en la fila, con la consulta nueva M4, como en el prototipo. La recomendación era preguntar al pulsar «Registrar», sin base.
4. **Deshechas antiguas:** solo las de hoy por ahora; M3 queda para el plan de llamadas. La recomendación era cubrirlas ya.

### De criterio, tomadas por Claude (Jhosep puede revocarlas)

1. Decisión: el aviso de «sin resultado» va sin enlace. Motivo: «Registro» lista actividades y una llamada sin resultado no es actividad; el enlace llevaba a una lista donde no aparece.
2. Decisión: N del aviso = sin resultado + deshechas sin corregir; M = por revisar. Motivo: el contrato cuenta las deshechas como pendientes (§5).
3. Decisión: cuadro «Tareas pendientes» y pestaña «Tareas». Motivo: lo pide el hallazgo 3 del contrato, y «Tareas pendientes» no entra en la barra de 5 pestañas.
4. Decisión: la línea «N descartadas hoy» y la pestaña salen de la misma consulta (M2), no de F4-e. Motivo: el contrato exige cifra y filas de la misma lectura (líneas 170-172).
5. Decisión: el campo del motivo avisa «Lo verá tu supervisor». Motivo: el texto libre llega a supervisor y gerencia.
6. Decisión: los descartes se cortan por la hora del descarte y, fuera de ámbito, se oculta el nombre pero no la fila. Motivo: «descartadas hoy» se lee así, y ocultar filas daría totales distintos según quién mira.
7. Decisión: la cola v2 es una puerta nueva; la v1 no se toca. Motivo: la app publicada exige `version: 1` (`lib/gestion-diaria-cola.ts:39-74`) y se rompería entre el SQL y el release.
8. Decisión: una pastilla en 0 se abre y muestra «Nada pendiente en este bloque»; el salto automático solo ocurre al vaciarse el bloque en uso. Motivo: un clic que te lleva a otro bloque confunde.
9. Decisión: dos PR de código, más los documentos en el #270. Motivo: «un solo PR abierto a la vez» y «menos PR»; lo de pantalla no espera el turno de SQL de Miguel.
10. Decisión: no se aplica `f7c9fecf` (#21) ni se crean puertas de escritura. Motivo: el contrato pide el lote sobre la v6 (§7); además, su replay por enlace deja trabada la intención tras Deshacer.

## 8. Verificación y revisión de Codex

**PR-1 (nivel 2):**
- `cd CRM-Avance-Corp/app && npm run check:all` (lint, typecheck, cobertura y E2E). E2E con Docker: en la máquina Windows de Jhosep el script `e2e-docker.sh` falla y se corre `docker run` a mano. Docker apagado = NOT RUN.
- `revisor-a11y`, `npm run gate:realidad` y la prueba en el estado de producción.
- Navegador a 1680 px y a un ancho menor (la barra de 5 pestañas solo se midió a 1680).

**PR-2 (nivel 3):** todo lo anterior, y además:
- por migración: `npm run test:llamadas:local` (M2–M4) o el banco de la cola (M1);
- `npm run test:rls:preflight`;
- `CRM_RLS_EXIGE_LLAMADAS=1 CRM_RLS_EXIGE_LLAMADAS_F4B=1 CRM_RLS_EXIGE_LLAMADAS_F4E=1 npm run test:rls -- --llamadas`, más el bloque nuevo de la cola;
- advisors, EXPLAIN, `npm run gen:types` y typecheck;
- reversa probada y registrador.

**Codex:**
- Encargo en `CRM-Avance-Corp/docs/encargos/<fecha>-codex-<tema>.md`. Empieza con `ROLE: SECONDARY_REVIEWER.`, lleva las cinco prohibiciones literales y «Follow .ai/REVIEW_PROTOCOL.md».
- Transcribe el SQL, los diffs y las salidas de las pruebas: Codex no ve la base ni la red (`.ai/REVIEW_PROTOCOL.md:199-228`).
- Se invoca con `scripts/codex-review-mcp < encargo`. **Codex no está instalado en esta máquina:** la ronda la corre el agente de Miguel (precedente: `COORDINACION.md:81-85`) o queda NOT RUN, dicho así.
- Revisiones: PR-1, 0–1; PR-2, 1 (máximo 2 con evidencia nueva).

**Informe final de cada PR:** IMPLEMENTED · MODIFIED · REVIEW · VERIFICATION · REMAINING RISKS · MANUAL ACTION REQUIRED. Comentario QUÉ HICE · RESULTADO · TURNO PARA, con PASS / FAIL / NOT RUN.

**Publicación:** Miguel, con `/release-crm` y el preflight `node _DEV_NO_SUBIR/deploy-hostinger-mcp.mjs preflight crm.miavance.com <zip>`. Después, fusión a `main` el mismo día (regla del CLAUDE.md raíz).

## 9. Riesgos

- **Rendimiento.** El plan «foto del SLA» de Miguel (#277) busca menos consultas pesadas, y este plan suma:
  - una consulta en la ficha de gerencia (F4-e con la ficha abierta);
  - M2 al abrir cada ficha;
  - M1, que recalcula la cola entera por página, igual que la v1;
  - M4, una consulta por página de la lista «Sin resultado» (hasta 200 llamadas).
  Hay que medirlo con EXPLAIN y en el navegador.
- **Paginación por número de página.** Guardar entre dos páginas desplaza filas. Lo mitigan el desempate estable y que el elegido vaya aparte.
- **Medianoche.** El eco estricto del día (`lib/gestion-diaria-cola.ts:54`) puede dejar la cola como «caída»: hay que probar 23:59 y 00:01.
- **WhatsApp y citas en «Hoy».** `primera_agenda` no filtra por tipo (`mig/20260925001914:126`), y registrar la llamada no cierra esas tareas (`analista.tsx:357-360`), así que el lead seguiría en «Hoy». Hay que cerrarlo en el diseño de M1 con Miguel. Propuesta [S]: que no cuenten como llamada pendiente.
- **Dos gestiones por una llamada.** Hasta la Entrega B, la v5 guarda aunque devuelva `no_enlazado`: «Sí, es esa» en una pestaña y «No, registrar» en otra pueden crear dos gestiones. Es un riesgo de hoy; este plan no lo empeora, pero lo deja más a la vista.
- **Candidatos (M4).** Evita el punto ciego que tendría la pantalla: M4 excluye los resultados con intención pendiente, que desde la pantalla no se ven porque están en una tabla privada (`mig/20261005155914:87-88`).
- **Aceptado por Jhosep (decisión 2):** «Vencidas» del analista = días anteriores; la columna «Vencidas» del supervisor cuenta todo lo ya vencido, incluidas las de hoy. Pueden no coincidir.
- **Aceptado por Jhosep (decisión 4):** el aviso del supervisor cuenta deshechas de cualquier fecha (F4-e), y el analista solo encuentra las de hoy.
- **Privacidad.** El motivo libre y los nombres de los leads llegan a supervisor y gerencia. F4-e había elegido «sin números» (`docs/plans/llamadas-celular/F4E-CONTRATO.md:11`). El aviso en el campo lo hace explícito.
- **Clon atrasado y archivos que cambian a diario.** `MIGRACIONES.md` y `database.types.ts` cambian casi todos los días: hay que integrar `main` justo antes de cada PR.

## 10. Lo que este plan NO hace

- No cambia v4, v5, `enlazar`, `descartar`, la ingesta ni Deshacer.
- No aplica `f7c9fecf` ni crea la v6.
- No toca la v1 de la cola ni `private.sla_operacion_leads`.
- No mete «Sin resultado» en «Necesitan atención» desde la pantalla: rompe la regla de «una sola foto» (`lib/gestion-diaria-equipo.ts:1-2`) y espera a B.
- No muestra cobertura del celular en Gestión Diaria.
- No publica ni aplica SQL: eso lo hace Miguel con su procedimiento.

## 11. Al retomar el plan de llamadas

- Entregas B (comando v6, guarda de la v5, identidad, lectura única con cursor y `conteo_estado`, «Por revisar» excluyente), C (cifras unificadas en supervisor y gerencia, columna «Sin resultado», cambiar la fuente de los hooks), D (lote #21 sobre la v6, renumerando su migración) y E.
- Integrar el contrato `9b26fab2` a la rama de trabajo.
- Propuesta a Miguel: descartar la F5 «Jev» (0/15).
- Aparte, y sin esperar: rotar la clave de TypeSafe que se pegó en un chat el 20/09 (`scripts/jev/README.md:45`); no consta que se haya rotado.

---

**En llano.** Las correcciones de Gestión Diaria se pueden hacer sin tocar cómo se guardan las llamadas.
- Lo que sí hace falta en la base son 3 consultas nuevas: la cola del analista con su orden nuevo, los descartes con su motivo y los candidatos de la pregunta «¿Ya registraste esta llamada?».
- Conviene hacerlo aparte del plan de llamadas: va antes y no se rehace después, porque todo lee desde piezas que al retomar llamadas solo cambian de fuente.
- Jhosep ya eligió los 4 puntos. Antes de escribir código falta que Miguel confirme por escrito 9 puntos donde el prototipo se aparta de su contrato, porque Codex revisa contra lo escrito.
- Este plan se armó con cinco análisis de solo lectura. No se ejecutó código, ni pruebas, ni migraciones.
