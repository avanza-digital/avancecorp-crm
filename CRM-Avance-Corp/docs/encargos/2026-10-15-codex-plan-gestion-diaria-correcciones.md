ROLE: SECONDARY_REVIEWER.
Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md.

# Encargo a Codex — Plan de implementación de las 12 correcciones de Gestión Diaria (ronda r1)

- **Qué revisas:** un PLAN, no código: todavía no hay implementación. Riesgo **LEVEL 3**, porque propone migraciones de
  lectura (M1, M2 y M4). Responde en español, con el formato de review del protocolo (anexo D).
- **No ves la base, la red ni el repo:** todo lo que debes juzgar va transcrito aquí. El plan (A) es la copia literal de
  `CRM-Avance-Corp/docs/plans/2026-10-15-gestion-diaria-correcciones.md`. El contrato (B y C) es la copia literal de `9b26fab2`. La evidencia de código (anexo E)
  sale de `main` en `597cab1c`, con el número de línea al principio. Sin hallazgo sin evidencia: cita la
  sección del plan, la línea del contrato o el extracto.
- **Contexto:**
  - Miguel encargó la unificación de llamadas (contrato `9b26fab2`, entregas A–E).
  - El 15/10, Jhosep aprobó un prototipo nuevo de Gestión Diaria con 12 correcciones, con acuerdo verbal de Miguel, y
    **pausó el plan de llamadas** hasta cerrarlas.
  - Este plan implementa esas correcciones sin las entregas B–D del contrato y declara dónde se aparta de su texto (§6
    del plan).
  - No revises si B–D están hechas: no lo están, y quedan NOT RUN.
  - **Principio rector (Jhosep):** la versión final se ve y se usa como el prototipo aprobado, porque así lo entienden
    los analistas. Las diferencias con el prototipo están listadas y decididas en el §7 del plan.

## Preguntas concretas

1. **Frontera (§2 y §4):** ¿alguna corrección marcada para «ahora» necesita en realidad la Entrega B, o rompe una
   invariante del contrato (§1, §3.1, §4, §5)?
2. **Divergencias (§6):** ¿están bien identificadas y citadas? ¿Falta alguna que Miguel deba confirmar por escrito?
3. **Migraciones (§5):** ¿M1, M2 y M4 son aditivas y compatibles con lo que el contrato conserva o reemplazará? ¿Son
   correctos sus ámbitos por rol, la privacidad (sin número), la security y los grants? ¿Falta alguna prueba?
4. **Regla de «Hoy» (decisión 2, M1):** ¿choca con las cubetas del SLA (E3, E4) o con las métricas de supervisor y
   gerencia? ¿Está bien declarado el riesgo aceptado?
5. **Orden de PR y despliegue (§3 y §8):** ¿es seguro, con primero el SQL y la cola v1 intacta hasta retirarla?
6. **Riesgos omitidos (§9 y §10)** que cambien una decisión.
7. **Prototipo:** si alguna recomendación tuya cambia lo que ve o usa el analista respecto del prototipo, márcala así;
   por el principio rector, Jhosep la decide antes de implementarla.

## A. El plan (copia literal)

# Plan de implementación — Gestión Diaria: las 12 correcciones del prototipo aprobado


**Estado:** las 4 decisiones de Jhosep quedaron tomadas el 15/10 (§7). Falta:
- la confirmación por escrito de Miguel de las divergencias (§6);
- la revisión de Codex (encargo `docs/encargos/2026-10-15-codex-plan-gestion-diaria-correcciones.md`).

Sin código hasta tener ambas.

**Principio rector (Jhosep, 15/10):** la versión final se ve y se usa como el prototipo aprobado, porque así lo
entienden los analistas. Toda diferencia con el prototipo —técnica, del contrato o de una revisión de Codex o de
Miguel— se lista en §7 y la aprueba Jhosep antes de implementarla.

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
| «Pendientes» se queda como en el prototipo (hallazgo C1-3: punto 10 para Miguel) | «Por revisar» excluyente con «Sin resultado», incluidas las que tienen candidato (§4) |
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
| F1 · Pantalla sin base | 1 (con las deshechas de hoy), 2, 6, 7, 8, 10, 12 y C1-1 | PR-1 | 2, 0–1 revisión | Miguel publica (preflight) |
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
| 1 | Pestaña «Celular · N», con N = filas descargadas (`analista.tsx:672-674`). Vistas «Pendientes / Qué pasó hoy» (`llamadas-celular.tsx:45,66-77,301-324`). Las deshechas solo están en «Qué pasó hoy», que se corta por la fecha del enlace (`mig/20261006162813:383-385`) [V] | «Sin resultado · N»: pendientes + deshechas corregibles (`puedeRegistrarCorregido`, `lib/llamadas-celular.ts:236-240`) con «Registrar el corregido» (`analista.tsx:179-190`). Se quita «Qué pasó hoy». N exacto si la lista cabe en una página; si no, «50+». Se quitan los textos de origen (`llamadas-celular.tsx:69,85,88`; `lib/llamadas-celular.ts:279-282,309-314`; `registrar-resultado.tsx:480,523`): quedan «Llamadas que hiciste y todavía no tienen resultado» y «Llamada de las 11:32» (diferencia a, aprobada) | F1 (solo las deshechas de hoy: decisión 4) | Pantalla |
| 2 | Lista cerrada + «Otro»; ya envía `otro` + texto de 3 o más (`llamadas-celular.tsx:199-236`). La base exige 3–300 tras recortar, además de un CHECK (`mig/20261005143843:769-778`) [V] | Un solo campo obligatorio de 3–300, con foco y el aviso «Lo verá tu supervisor». El largo se cuenta en caracteres reales y se envía recortado | F1 | Pantalla pura |
| 3 | «Unir…» aparece en toda pendiente con lead (`llamadas-celular.tsx:168-172`); los candidatos se piden al abrir el panel (`:248-299`, `data/llamadas-celular-api.ts:164-182`) [V] | La fila pregunta sola, solo si M4 devuelve un candidato (decisión 3): «¿Ya registraste esta llamada? A las 10:32 …» [Sí, es esa] [No, registrar resultado]; con varios, «¿Cuál de estos es?». «Sí, es esa» → `crm.enlazar_llamada_celular` (`api.ts:186-194`), que el contrato conserva (§3.1). Si lo registró otra persona: «Ana registró…» | F2 | Base y pantalla |
| 4 | «Todo» por defecto (`lib/gestion-diaria-cola.ts:78`). Orden actual: Sin primer intento → Vencidas → Hoy → Sin conversación (`lib/gestion-diaria-analista.ts:129-134`). No salta al vaciarse un bloque (`analista.tsx:253,394-405`) [V] | Sin «Todo». Orden Hoy → Sin primer intento → Vencidas → Contactar de nuevo. Arranca en el primer bloque con gente; al vaciarse, salta y lo avisa. «Hoy» = todo lo de hoy desde la mañana, con su hora; «Ahora» lo propone desde su hora (decisión 2). Orden y salto salen del servidor (M1) | F2 | Base y pantalla |
| 5 | `total` = pendientes + gestionados + programados (`mig/20260930190028:221-231`). Lo gestionado conserva su grupo (`:137-139`). El banco exige «reintento futuro fuera de pendientes» (`scripts/gestion-diaria-cola/prueba.sql:91-112`) [V] | Las pastillas cuentan y listan solo lo «por hacer»; lo gestionado sale, salvo un reintento de hoy, que va a «Hoy» (M1, decisión 2). Se retiran la leyenda, «Vuelta completada» y `siguienteTrasGuardar` (`cola-de-hoy.tsx:113-119`, `analista.tsx:810`, `gestion-diaria-analista.ts:363-394`). El pie de «Ahora» pasa a «Pendientes primero. Al guardar, sale de esta lista y continúas con el siguiente.» (diferencia b, aprobada) | F2 | Base y pantalla |
| 6 | Etiqueta en `lib/gestion-diaria-analista.ts:133` (solo la usa la cola) [V] | «Contactar de nuevo» solo en la pastilla; los chips de fila no cambian | F1 | Pantalla pura |
| 7 | Ayuda absoluta, `hidden … 2xl:flex` (`cola-de-hoy.tsx:99`): solo se ve desde 1536 px [V] | Por la ranura `acciones` de `Tabs`, que ya baja de línea (`components/ui/tabs.tsx:48-52,150-155`). 14 px seminegrita. Usar `claseLista`, porque los selectores de `cola-de-hoy.tsx:110` dejan de aplicar al envolver | F1 | Pantalla pura |
| 8 | «1–8 de 97» visible y Anterior/Siguiente (`cola-de-hoy.tsx:165-181`). `Paginacion` común sin números (`components/common/paginacion.tsx:34-53`) [V] | `ventanaPaginas()` (nuevo, en `lib/`): 7, 5 o 3 casillas según el ancho (`lib/media.ts:35,101`), centrada, `aria-current="page"`, «…» oculto al lector, rango solo para lector con `role=status`. Sirve con la v1 y con la v2 | F1 | Pantalla pura |
| 9 | Orden por `referencia_en` ascendente: la más vieja primero (`mig/20260930190028:239`). Una vencida gestionada con la tarea abierta queda «gestionada» (`:156`) [V] | Vencidas en orden descendente, con desempate estable. Sale al gestionarse, salvo si se desmarca «Cerrar también» (M1) | F2 | Base y pantalla |
| 10 | Bloque `SuCelularAnalista` (`panel-analista-supervisor.tsx:144-146`) y pie «Tu celular: …» (`screens/gestion-diaria/supervisor.tsx:66-68,322`) [V] | Se borran los dos. Aviso ámbar «N llamadas sin resultado · M por revisar» con props propias de `ResumenAnalista`, después de las vencidas (no por `antesDeCuadros`, que pinta antes: `resumen-analista.tsx:63-64`). **Sin enlace** (Decisión 1). Cifras de F4-e: N = `pendientes.total + deshechas_sin_corregir`, M = `por_revisar` (`mig/20261013145935:157-187`). Si falla, una línea con «Reintentar» | F1 | Pantalla pura |
| 11 | `PestanaPanel` sin «Descartes» (`panel-analista-supervisor.tsx:27,192`); separación de 22 px (`:193`) [V] | 5.ª pestaña «Descartes»: lista con hora, lead y motivo, y vacío «Ningún descarte hoy». Línea en Resumen «N llamadas descartadas hoy · Ver motivos ›». 18 px de separación. Datos de M2, una consulta al abrir la ficha que reutiliza la pestaña (Decisión 4). Copia el patrón de `citas-agendadas.tsx:25-58` y `etiquetaMotivoDescarte` (`lib/llamadas-celular.ts:265-268`) | F2 | Base y pantalla |
| 12 | 3.ª pestaña (`screens/gestion-diaria/gerencia.tsx:47`, ramas `:125,131-132,264-267`). La ficha dentro del equipo no recibe `celularHoy` (`vista-equipo-gerencia.tsx:221-225`) [V] | Quedan dos pestañas. Se activa `useOperacionCelularHoy` con la ficha abierta (`esHoy && ruta && grupo`) y se pasa a `PanelAnalistaSupervisor`. Ya autoriza a gerencia (`data/llamadas-celular-operacion-queries.ts:33`) y su 42501 sigue retirando la vista (`gerencia.tsx:126-129`) | F1 | Pantalla pura |
| C1-1 | `motivosAtencion` añade `sin_dato` y la salud del aparato (`lib/llamadas-celular-operacion.ts:142-157`); solo lo usa la 3.ª pestaña (`llamadas-celular-gerencia.tsx:207`) [V] | Se borra con la 12 | F1 | Pantalla pura |
| C1-3 | Cuadro «Pendientes» (`resumen-analista.tsx:108`) y pestaña «Pendientes» (`panel-analista-supervisor.tsx:192`) [V] | **Sin cambio:** se queda «Pendientes», como en el prototipo (Jhosep, 15/10). Punto 10 para Miguel | — | — |

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
10. **«Pendientes» se queda como en el prototipo** (decisión de Jhosep, 15/10). §6, hallazgo 3: «llamar «Tareas
    pendientes» a las tareas y «Sin resultado» a las llamadas». *Recomendación:* aceptarlo; las llamadas ya se llaman
    «Sin resultado» y no se confunden con las tareas.

## 7. Decisiones

### Para Jhosep (respondidas el 15/10 con el formulario)

1. **Estrategia:** aparte del plan de llamadas, con la frontera de §2 (era la recomendada).
2. **Qué es «Hoy»:** cuenta todo lo de hoy desde la mañana, con su hora. «Ahora» lo propone desde su hora y, ya pasada, va primero. Lo de días anteriores va a «Vencidas» (era la recomendada).
3. **Dónde pregunta la corrección 3:** en la fila, con la consulta nueva M4, como en el prototipo. La recomendación era preguntar al pulsar «Registrar», sin base.
4. **Deshechas antiguas:** solo las de hoy por ahora; M3 queda para el plan de llamadas. La recomendación era cubrirlas ya.

### Diferencias con el prototipo (principio rector: las aprueba Jhosep)

- a. **APROBADA.** **Textos sin «del celular»:** «Llamada del celular de las 11:32» pasa a «Llamada de las 11:32 a Carlos Ruiz», y el
  título «Llamadas del celular» de la lista pasa a «Sin resultado». Por la regla de Jhosep del 14/10 y el §5 del
  contrato. La hora y el lead siguen a la vista. Jhosep (15/10): «llamadas es igual si no la cierras la encuesta desde
  el pc o celular; la finalidad es cerrar la tarea de llamada con la encuesta».
- b. **APROBADA.** **Pie de «Ahora»:** el texto real «Al guardar, este lead pasa al final» (`analista.tsx:890-892`, copiado en el
  prototipo) deja de ser cierto con las correcciones 5 y 9. Pasa a «Pendientes primero. Al guardar, sale de esta lista
  y continúas con el siguiente.»
- c. **APROBADA.** **Aviso del supervisor sin enlace:** el prototipo abría «Registro», donde esas llamadas no aparecen (Decisión 1).
- d. **NO APROBADA: se queda «Pendientes»**, como en el prototipo. El contrato pedía «Tareas pendientes»: punto 10 de §6.
- e. **«Ahora» propone una llamada de hoy desde su hora**, no desde la mañana: decisión 2 de Jhosep, ya aprobada.
- f. **«50+» en la pestaña** cuando hay más de una página (50) de llamadas sin resultado; con menos, el número exacto,
  como en el prototipo.

### De criterio, tomadas por Claude (Jhosep puede revocarlas)

1. Decisión: el aviso de «sin resultado» va sin enlace. Motivo: «Registro» lista actividades y una llamada sin resultado no es actividad; el enlace llevaba a una lista donde no aparece. **Aprobada por Jhosep (15/10).**
2. Decisión: N del aviso = sin resultado + deshechas sin corregir; M = por revisar. Motivo: el contrato cuenta las deshechas como pendientes (§5).
3. ~~Decisión: cuadro «Tareas pendientes» y pestaña «Tareas».~~ **Revocada por Jhosep (15/10):** se queda «Pendientes», como en el prototipo (punto 10 de §6).
4. Decisión: la línea «N descartadas hoy» y la pestaña salen de la misma consulta (M2), no de F4-e. Motivo: el contrato exige cifra y filas de la misma lectura (líneas 170-172).
5. Decisión: el campo del motivo avisa «Lo verá tu supervisor». Motivo: el texto libre llega a supervisor y gerencia.
6. Decisión: los descartes se cortan por la hora del descarte y, fuera de ámbito, se oculta el nombre pero no la fila. Motivo: «descartadas hoy» se lee así, y ocultar filas daría totales distintos según quién mira.
7. Decisión: la cola v2 es una puerta nueva; la v1 no se toca. Motivo: la app publicada exige `version: 1` (`lib/gestion-diaria-cola.ts:39-74`) y se rompería entre el SQL y el release.
8. Decisión: una pastilla en 0 se comporta como en el prototipo: al pulsarla, la cola muestra el primer bloque con gente. Motivo: principio rector; así lo vieron y entendieron los analistas (corregido el 15/10 tras el recordatorio de Jhosep; antes decía «Nada pendiente en este bloque»).
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
- Jhosep ya eligió los 4 puntos. Antes de escribir código falta que Miguel confirme por escrito 10 puntos donde el prototipo se aparta de su contrato, porque Codex revisa contra lo escrito.
- Este plan se armó con cinco análisis de solo lectura. No se ejecutó código, ni pruebas, ni migraciones.


## B. Contrato de Miguel (copia literal de `9b26fab2:CRM-Avance-Corp/docs/encargos/2026-10-13-llamadas-crm-unificadas.md`)

# Llamadas del CRM: corrección de las propuestas #23 y #21 y encargo de implementación

Fecha: 13/10/2026. PRIMARY de este análisis: Codex, por encargo directo de Miguel.
Fuente revisada: `avancecorp/main` en `4ec46ba30838559142320692aa137305454a62d8` y PR #270 en
`3fc596a0babf5e890c3e7fed6255a7e1c8d1cd1c`. La rama local de código de #21 que menciona Jhosep no está publicada:
los hallazgos sobre ella son del **contrato escrito**, no una revisión de esa implementación inaccesible.

Estado: **CHANGES_REQUESTED para el diseño #23/#21 actual**. Este documento corrige el diseño y encarga su
implementación a Jhosep/Claude. No modifica código de producción, no aplica SQL y no acredita que la unificación
ya funcione. La aceptación anterior de F4-e queda conservada como evidencia histórica.

## 1. Decisión de Miguel y alcance

Las llamadas siempre se hacen con el celular. El resultado es una gestión del CRM, se marque en la PC o en el
celular. Miguel confirma quitar los apartados separados y pide unificar **registro, lectura y conteo**, no solo
los rótulos. El 13/10 encargó a Codex desarrollar la modificación, corregir el planteamiento y delegar la ejecución
que corresponda a Jhosep.

- Una encuesta de resultado y unas reglas comerciales para todos los accesos.
- Una llamada cuenta una vez. Su captura y su resultado son evidencia del mismo hecho, no dos gestiones.
- La captura sin resultado abre un pendiente del CRM; no fabrica «No contestó», contacto ni actividad comercial.
- El dato técnico de captura se conserva para vinculación, soporte y auditoría. No inventar que la llamada se
  originó en una pantalla del CRM ni cambiar su trazabilidad para lograr esta unificación funcional.
- «Sin captura integrada» no significa «sin celular» ni «no trabaja». Ningún flujo de registro depende de tener
  asignación de celular o latido activo.
- La fórmula de contacto y el cambio de reloj de los KPI son decisiones distintas de unificar la experiencia.
  Este encargo conserva el criterio comercial existente mientras se especifica la proyección nueva.

## 2. Hallazgos con evidencia

Las rutas siguientes son relativas a `CRM-Avance-Corp/`, salvo el comentario de GitHub.

| Prioridad | Evidencia | Problema y corrección |
| --- | --- | --- |
| P1 | #23, [apartados 2, 4, 5 y 6](https://github.com/avanza-digital/avancecorp-crm/pull/270#issuecomment-6156537188); `supabase/migrations/20260924201358_crm_gestion_diaria_pulso_habitos.sql:9` y `:49`; `supabase/migrations/20261013145935_crm_llamadas_celular_operacion_hoy_rendimiento.sql:139` | El pulso cuenta actividades por fecha de registro y F4-e cuenta eventos por fecha de llamada, además de resultados enlazados. No se pueden sumar ni elegir una fuente por «tener celular». Una persona integrada también puede registrar desde PC con la captura pendiente. Hace falta una proyección por identidad, fechas y ámbito, antes de reemplazar cifras. |
| P1 | `docs/plans/llamadas-celular/P21-PLAN-CORTO.md:40` y `:51` en el SHA del #270 | El plan rechaza el evento ya resuelto **antes** de recuperar el recibo. Si el primer guardado confirmó en la base y se perdió la respuesta, el mismo reintento ya no encuentra una pendiente. Recuperar y validar la operación confirmada antes de exigir que siga pendiente; vincular el recibo también a la llamada exacta. |
| P1 | `P21-PLAN-CORTO.md:40–46`; `supabase/migrations/20260921153654_crm_resultado_llamada_seguimiento.sql:131–159`; `supabase/migrations/20261005182227_crm_llamadas_celular_enlace_sin_ciclo.sql:74–103` | El plan toma evento → núcleo, pero el núcleo toma lead y el enlace vigente toma lead → evento. Intercalado posible: #21 retiene evento y espera lead; v5 retiene lead y espera evento. Corregir el orden y probar con dos conexiones. Es un riesgo derivado del plan, no un interbloqueo reproducido en su rama local. |
| P1 | `app/src/lib/store.tsx:3253–3266`; `supabase/migrations/20261005155914_crm_llamadas_celular_enlace_exacto.sql:639–647`; `supabase/migrations/20261005182227_crm_llamadas_celular_enlace_sin_ciclo.sql:103–110` | La encuesta comparte el núcleo v4, pero el cliente selecciona v4/v5 según el id de captura. v5 permite guardar la gestión y devolver `no_enlazado` si otra operación ya cerró esa llamada. Unificar solo las pantallas no elimina esa posibilidad. La nueva operación común debe confirmar conjuntamente el resultado y la identidad cuando se suministra una llamada exacta. |
| P2 | `P21-PLAN-CORTO.md:64–89`; `app/src/data/sla-operacion-comandos.ts:9`, `:29`, `:209–230` | El cliente no soporta sin cambios el nuevo nombre de comando del plan. Su lista cerrada, el nombre del sobre confirmado y las comprobaciones específicas de resultado/enlace deben actualizarse. Conservar intenciones v4/v5 pendientes y sus ids al actualizar la aplicación. |
| P2 | `app/src/lib/llamadas-celular-operacion.ts:142–155`; `app/src/components/gestion-diaria/su-celular-analista.tsx:45`; #23 §3.4 y §6.2 | `sin_dato` añade un motivo de atención incluso sin integración; el texto «sin celular» atribuye una ausencia física no demostrada. Separar cobertura técnica de pendientes de trabajo, sin sustituir las llamadas manuales por cero. |
| P2 | #23 §5 y §7; `supabase/migrations/20261005155914_crm_llamadas_celular_enlace_exacto.sql:576–605` | El alcance no es «solo pantalla». Incluye identidad/recibos, lecturas, paginación y compatibilidad; además hay purga de evidencia no resuelta. No reconstruir históricos completos a partir de una fuente con retención limitada. |

No se afirma que haya duplicados observados en producción. Mostrar el mismo hecho en dos vistas tampoco prueba
dos escrituras: la v5 **ya llama al núcleo v4**. Se reutiliza esa regla comercial, no se reimplementa.

## 3. Modificación concreta: un comando de resultado

`ReceptorLlamada` abre `RegistrarResultado` con el contexto disponible; la PC, la ficha, la cola y la lista de
llamadas abren esa misma encuesta. Una referencia de captura es contexto opcional, no el selector de otro proceso.
El acceso por enlace y las rutas publicadas siguen funcionando y aterrizan en el flujo común.

En el cliente, `registrarLlamada` pasa a usar **una versión común del comando** para las operaciones nuevas,
con resultado, submotivo, detalle, tarea, próxima acción, descarte y No insistir, más la referencia opcional de la
llamada. Nombre propuesto: `registrar_llamada_v6`; Jhosep lo confirma contra el catálogo antes de crear la migración.
Conserva el núcleo comercial v4 sellado y compone autorización, recibo y vínculo. No basta llamar a v5 desde todas
las pantallas si persiste el caso `no_enlazado` después de crear otra gestión.

Contrato de servidor:

1. Autorizar actor, rol y ámbito; no confiar en el actor o lead de una captura enviados por el navegador.
2. La identidad idempotente comprende actor + operación + contenido normalizado + llamada objetivo (si existe).
   Recuperar la confirmación de **esa misma operación** antes de rechazar «ya tiene resultado». Reusar el id con
   otro evento, resultado, lead o próxima acción es conflicto; no puede enlazar la actividad anterior a otra llamada.
3. Para una operación nueva, respetar el orden de bloqueos de persona/veto cuando corresponda, lead, evento y enlace,
   compatible con el núcleo y con Deshacer. Leer primero la referencia para resolver el lead sin bloquear el evento;
   después del bloqueo volver a validar identidad y ámbito. No esperar por una actividad retenida por Deshacer
   teniendo el lead bloqueado: conservar la defensa existente sin espera/reintento. No copiar un orden incompleto
   sin probarlo con ingesta, corrección, reasignación y las puertas antiguas aún accesibles.
4. Si la llamada exacta ya tiene resultado de otra operación: devolver conflicto de negocio y cero actividades,
   tareas o efectos nuevos. Ofrecer abrir el resultado existente. Una corrección se solicita explícitamente tras
   Deshacer y sigue las reglas actuales; no equivale a otra llamada.
5. Si la captura todavía no llegó pero hay id de origen válido, conservar la intención exacta existente y vincularla
   al llegar. La reserva/intención y el resultado se confirman atómicamente. Un rechazo de identidad/vinculación no
   debe dejar una segunda actividad. No hacer el fallback automático «falló con captura → guardar sin captura».
6. Si no hay referencia de captura, el registro habitual sigue funcionando. Se crea una sola actividad y su recibo.
   Una captura posterior se concilia con esa actividad, no obliga a volver a llenar la encuesta.
7. La respuesta confirma la operación, la actividad y el estado de vinculación; el cliente valida todos los campos.
   Un timeout conserva la intención y reintenta con el mismo id. Una actualización de la app recupera las intenciones
   antiguas con su comando original; no cambia su huella ni genera otro id para «migrarlas».

Las v4/v5 y los clientes antiguos requieren estrategia de convivencia: probar escrituras mezcladas. La garantía
global no está cerrada si el mismo evento todavía puede recibir un resultado nuevo mediante una puerta antigua
que omite la nueva guarda. Jhosep debe definir el adaptador compatible o la guarda común en una migración nueva,
conservando las respuestas y los replays existentes. No revocar una versión en uso sin resolver esos recibos.

**Prerrequisito obligatorio de la entrega B:** la guarda compatible de v5 entra en la misma migración que la
operación común, antes de conectar las pantallas. Para una operación nueva con captura, ambos accesos deben pasar
por la misma exclusión/confirmación transaccional. Puede ser una composición compatible o una excepción controlada
que revierta **toda** la transacción si no se confirma el vínculo: un helper posterior al núcleo no es por sí solo
demasiado tarde para hacer rollback. No poner una guarda en v4 que dependa de un evento que v4 no recibe.
Los replays antiguos deben recuperar la actividad confirmada sin efectos nuevos; la respuesta histórica completa
de v5 no está guardada en el recibo v4, por lo que no se puede prometer reconstruirla literalmente. Si no existe
evidencia persistida de a qué captura correspondía una operación antigua, confirmar su gestión y exigir conciliación
explícita del vínculo, sin enlazar otra captura a partir de parámetros distintos enviados durante el replay.

### 3.1. Asociación y descarte: reutilizar las operaciones existentes

Existe `crm.enlazar_llamada_celular(p_evento_id, p_actividad_id)` (`20261001160219`, líneas 765–775;
implementación vigente de su núcleo en `20261005143843:680–752`). Reutilizarla para la conciliación; no inventar
otra puerta por afirmar que falta. El cliente ya la invoca en `app/src/data/llamadas-celular-api.ts:184–193`.

- Es idempotente por el par evento/actividad: repetir el mismo par devuelve `repetido`; otra actividad vigente o
  una actividad ya vinculada a otro evento producen conflicto. No crea actividad ni cambia `creado_en` o efectos.
- La autorización es el ámbito **actual** sobre el lead, mediante `private.llamada_celular_visible`, no la igualdad
  obligatoria entre llamante y registrante. Se conserva el autor original de cada hecho. No ampliar ese ámbito.
- El núcleo toma actividad `FOR SHARE` → lead `FOR SHARE` → evento → enlace. Ese orden difiere del registro;
  mantener la compatibilidad probada y ensayar su concurrencia, no reemplazarlo mecánicamente por un orden genérico.
- La ventana de asociación sigue el contrato actual: resultado de la encuesta vigente del mismo lead, no anterior
  a la llamada por más de diez minutos. No se amplía la ventana de llamadas largas (#19) dentro de este encargo.
- No existe «desenlazar» libremente: un resultado deshecho puede sustituirse por el corregido, con auditoría.
  Una asociación errónea que no pueda corregirse así se trata por el procedimiento de soporte; no borrar enlaces.
- `crm.descartar_llamada_celular` se conserva para descartar evidencia con motivo, con sus permisos y repetición
  idempotente por evento/motivo. «Descartar evidencia» y «descartar lead» son operaciones distintas del CRM.

### 3.2. Intención diferida y captura incompatible

Reservar no significa que la captura esté comprobada. Además de formato/ventana, validar la asignación del
dispositivo al actor para ese momento y guardar la referencia autorizada, actor, lead y actividad esperada.
El helper actual ya valida asignación (`20261005182227:60–71`); no reducirlo a una validación de formato.

Al llegar el evento, revalidar asignación/actor, lead, resultado vigente y unicidad. La ingesta vigente toma primero
el lead (`20261005155914:531–546`) y el cumplimiento usa actividad sin esperar (`20261005182227:189–219`). Preservar
esa defensa. Si los datos no coinciden, la actividad guardada permanece: no se cambia de lead, no se deshace ni
se duplica. La captura queda sin asociar y se ofrece revisión **solo a quien tenga ámbito**; un actor no ve el lead
o número ajeno a causa de una reserva fallida. Un evento ya enlazado tampoco se sustituye silenciosamente.

Si la captura no llega, mostrar el resultado registrado con evidencia técnica no confirmada, sin exigir registrar
otra gestión. La intención se purga al plazo vigente de 32 días (`20261005155914:602–605`), distinto del plazo de
pendientes de la política. Su vencimiento elimina la expectativa técnica, no la actividad del CRM. No agregar
retención indefinida ni un estado «Sin resultado» a una gestión que ya tiene resultado.

## 4. Identidad y lectura única

No crear automáticamente otra actividad solo porque llegó un aviso del teléfono. Mantener separados el hecho,
su resultado vigente y su evidencia técnica, y proyectarlos como **una llamada del CRM**.

La proyección de servidor debe tener una identidad de llamada estable, independiente de la versión del resultado.
Reusar los vínculos existentes; si hace falta persistir una identidad/alias adicional para correcciones o llegada
tardía, justificarla en la migración. `p_operacion_id` identifica un intento de escritura, no sustituye por sí solo
la identidad de la llamada. Dos resultados de corrección no son dos llamadas.

Regla de identidad para la implementación: el primer hecho persistido recibe `llamada_id`; eventos, intenciones
y versiones de resultado se vinculan como referencias a esa identidad. Al conciliar dos representaciones previas,
conservar la identidad de la actividad ya registrada y redirigir la referencia de captura mediante un alias.
Una corrección hereda el `llamada_id` del resultado anterior; no genera otra identidad. Puede implementarse con
un mapa privado mínimo de identidades/referencias sobre las tablas actuales, sin copiar teléfonos ni crear otra
actividad. Si solo queda evidencia pendiente sin resultado, ese mapa caduca con ella. Si existe actividad,
la identidad puede conservarse con su historial autorizado; no convertir la purga en un archivo de capturas.

Reglas para construir las filas antes de filtrar por día y paginar:

- Captura enlazada + actividad: una fila; resultado vigente y evidencia conservados.
- Intención exacta antes de la captura: una fila; cuando llega el aviso se completa la evidencia de esa identidad.
- Actividad sin captura: una fila CRM, aunque el analista tenga captura integrada o esta falle.
- Captura identificada sin resultado: pendiente CRM, apto para abrir la misma encuesta o asociar un resultado existente.
- Corrección/Deshacer: conservar identidad e historial; cambiar el resultado vigente. No sumar versiones anuladas
  como llamadas nuevas, ni borrar el hecho físico al deshacer su resultado.
- Coincidencia solo por lead, teléfono o cercanía horaria: **candidato, nunca unión automática**. Puede haber dos
  llamadas reales próximas. La asociación confirmada de una captura con una actividad elimina la representación
  duplicada sin crear actividad ni alterar la fecha de registro de la existente.
- Si no se puede saber si una captura y un registro son la misma llamada, mostrar «Por revisar» dentro del flujo
  común y declarar el conteo provisional. No prometer un total exacto ni ocultar una evidencia para cuadrarlo.
- La cobertura técnica no cambia el registro manual, no amplía permisos y no transforma llamadas personales,
  ambiguas o excluidas en trabajo comercial confirmado.

**Límite real:** los datos actuales no prueban la identidad de una captura tardía cuando el resultado se guardó sin
referencia. Cambiar nombres, usar `DISTINCT lead_id` o sumar dos consultas no resuelve esa falta de información.
La implementación debe resolverla con referencia exacta o conciliación explícita. El prototipo debe mostrar ese caso.

La lectura común debe servir filas y agregados desde el mismo conjunto autorizado y el mismo corte temporal.
Paginar **después** de resolver identidades, con cursor estable; no unir en React la primera página de actividades
con la primera página de capturas. El total de una tabla no se obtiene contando las filas que ya descargó el cliente.

Regla de «Por revisar»: usar el predicado de candidatos de la asociación vigente como sugerencia, nunca como prueba
de identidad. Una captura sin referencia que tenga candidatos sin asociar se clasifica en revisión, no además en
«Sin resultado»; el analista puede confirmar una asociación o que fue otra llamada. La ausencia de candidatos
dentro de la ventana no prueba por sí sola que dos hechos antiguos sean distintos; los casos fuera de ventana
con duda declarada van a soporte (#19 permanece separado).
Si la identidad del conjunto del día no está resuelta, `total_llamadas` es `null` y `conteo_estado` es
`por_conciliar`; mostrar «Por revisar», no sumar 1 + 1 y mostrarlo como dos llamadas exactas. La revisión tiene su
propio número de casos, nunca se suma a llamadas ni a resultados. Los tres roles heredan ese mismo estado en los
totales que abarcan el caso. Con identidad resuelta pero hora/captura incompleta, usar `conteo_estado = parcial`;
con identidad y cobertura declaradas suficientes, `conteo_estado = confirmado`. Estos estados no acreditan que
un latido haya capturado todas las llamadas del mundo real.

Deshacer un resultado no prueba que la llamada existiera ni que fuera ficticia. Una actividad manual deshecha sin
captura pasa a revisión, no automáticamente a una llamada física «sin resultado». Se conserva el historial. La
unificación no crea un borrado/anulación libre para solventarlo; un registro erróneo se resuelve por soporte o por
una corrección explícita con trazabilidad, cuyo alcance debe reflejar el contrato existente.

## 5. Conteos, fechas y contacto

Primera entrega: operación de **hoy en Lima**, conservando el histórico anterior como registros históricos.
El contrato debe versionar el cambio de semántica; no reinterpretar silenciosamente hábitos o comparaciones previas.
El reloj técnico de la macro actual corresponde a colgar, no al comienzo de la conversación; no inventar duración.

| Dato en la misma vista de CRM | Definición |
| --- | --- |
| Llamadas de hoy | Identidades distintas con momento de llamada conocido dentro del día. Cuando solo se conoce el registro, conservar esa referencia declarada; no presentarla como hora física verificada. La calidad temporal y la conciliación determinan si el total es completo o provisional. |
| Con resultado | Subconjunto de esas mismas llamadas con un resultado vigente. El origen/dispositivo de registro no modifica la pertenencia. |
| Sin resultado | Subconjunto gestionable de esas llamadas sin resultado vigente, incluidas las deshechas que requieren corrección. Otros estados, como cerradas después o por revisar, conservan su estado; no forzar `total = con resultado + pendientes` si existen otras cubetas. |
| Pendientes de resultado | Trabajo actual de hoy y días anteriores; indicar la antigüedad. No usar todo ese saldo como denominador de un porcentaje de hoy. La retención sigue la política; no fijarla a 30. |
| Resultados registrados hoy | Resultados vigentes registrados hoy, aunque la llamada sea de ayer. Es una dimensión temporal distinta, en la misma vista, no otro origen de llamadas. No se suma a «Llamadas de hoy». |
| Contacto de resultados registrados hoy | Conservar inicialmente `contestadas / útiles` en la cohorte de **resultados registrados hoy**, con las exclusiones actuales (`numero_errado`, `no_es_la_persona`). Rotular esa cohorte junto al porcentaje. No usar «Llamadas de hoy» como su denominador. Las llamadas sin resultado no se tratan como «No contestó». Sin denominador: «—». Un cambio de definición se presenta aparte con ejemplo antes/después. |

Los nuevos porcentajes se calculan desde enteros del mismo conjunto en pantalla, como exige F4-e; no añadirlos a
su JSON. No alterar por este encargo los porcentajes legados de otros contratos. En grupos, sumar numeradores y
denominadores; nunca promediar porcentajes. Mostrar el estado de cobertura sin dividir el trabajo en «CRM/celular».

Para el autor del conteo: la captura conserva quién llamó; la actividad conserva quién registró el resultado.
Una reasignación cambia el ámbito actual, no reescribe al autor histórico. Sin evidencia del llamante, no inferirlo
del dueño actual del lead. Roster, actividad propia de supervisor y exclusiones deben tener reglas explícitas.

La nueva lectura respeta RLS/ámbito y retención. La captura purgada no se reconstruye desde datos de auditoría ni
se conserva indefinidamente mediante una tabla nueva por comodidad. Un histórico de llamadas físicas completo
requeriría otro contrato de conservación; no está autorizado por esta unificación.

Al conciliar, la hora física disponible sustituye la referencia de registro **en la proyección nueva**; puede mover
una llamada del día de registro al día de ocurrencia. No modifica `actividad.creado_en` ni los KPI históricos del
contrato anterior. La respuesta incluye `generado_en` y una revisión del conjunto; la conciliación invalida todos
los totales afectados y reinicia la paginación. Un cursor de una revisión anterior se rechaza o fuerza recarga;
no continuar una lista cuyo orden cambió mientras se calculaba el agregado.

## 6. Pantallas y los tres hallazgos de C1

| Lugar | Cambio encargado |
| --- | --- |
| Analista | Quitar la pestaña separada «Celular». En «Mi actividad → Llamadas» mostrar una fila por llamada. Integrar «Sin resultado» y «Por revisar» en su trabajo habitual, usando la misma encuesta. Mantener accesibles asociar, descartar con motivo, abrir resultado, Deshacer y corregir. |
| Supervisor | Quitar «Su celular» y consumir las mismas cifras autorizadas en los cuadros actuales. «Necesitan atención» muestra acciones pendientes reales. La ausencia de integración es contexto de cobertura, no un incumplimiento. |
| Gerencia | Integrar llamadas, pendientes y cobertura en la tabla habitual de operación; quitar la tercera pestaña. Los subtotales y los detalles deben cuadrar contra la misma lectura. |
| Encuesta | Misma UI, catálogo y consecuencias desde cualquier acceso. La referencia de la llamada viaja internamente; no obliga a elegir entre «registrar en CRM» y «registrar en celular». |
| Soporte | La administración de dispositivos conserva su sitio en Configuración. Los detalles de macro, cola y latido no se convierten en categorías de actividad. |

Correcciones de los hallazgos: (1) quitar la ausencia de integración de los motivos de atención, manteniendo los
pendientes reales incluso si no hay integración; (2) permitir localizar las deshechas antiguas corregibles, aunque
no aparezcan en «Qué pasó hoy»; si el lead está cerrado/vetado, mostrar su estado sin ofrecer escritura prohibida;
(3) llamar «Tareas pendientes» a las tareas y «Sin resultado» a las llamadas. «Sin cerrar encuesta» no debe confundir
un problema de asociación con una encuesta que nunca se guardó.

## 7. #21: atajo del mismo flujo, no otro motor

Se incorpora después de asegurar la operación común. Elegir varias llamadas del mismo lead y confirmar
«No contestó» es una declaración del analista. **Se corrige nuestro reparo anterior:** no exigir un estado técnico
no disponible para que el analista pueda declarar el resultado. Esto no autoriza inferirlo automáticamente.

- Un resultado por llamada, misma operación común e invariantes que el registro individual; solo cambia cuántas
  veces se pide confirmación. Sin descarte automático «No responde» en la primera versión.
- Persistir el lote, las llamadas elegidas, la carga útil y un id de operación por elemento antes del envío.
  Serializar. Un reintento recupera esos ids, incluso tras recargar; crear otro lote no es reintentar el anterior.
- Separar éxitos propios, llamadas ya resueltas por otra operación, errores y confirmaciones inciertas. «Ya estaba
  resuelta» no acredita que esa otra operación guardó «No contestó».
- La tarea que se cierra y la próxima acción se ejecutan una sola vez. Definir el caso de que la última llamada
  ya esté resuelta, falle o se omita: no mostrar «seguimiento programado» si nunca se creó. Propuesta inicial:
  confirmar los resultados del lote y ofrecer la próxima acción en un paso común posterior con recibo propio.
  Jhosep especifica cómo conserva las validaciones del CRM y la recuperación de ese paso; no concatenar a ciegas
  `p_siguiente`/`p_tarea_id` en todos los elementos.

La próxima acción es opcional para `no_contesto` en el núcleo vigente
(`supabase/migrations/20260921153654_crm_resultado_llamada_seguimiento.sql:95–116` y `:189–195`), por lo que registrar
los elementos del lote sin `p_siguiente` es compatible. No extender ese atajo a `volver_a_llamar` o `agendo_reunion`,
que sí exigen seguimiento al dueño; mantienen su encuesta normal.

## 8. Entrega delegada a Jhosep y su Claude

Miguel autorizó corregir o delegar. Codex entrega este contrato y su revisión; **Jhosep/Claude es el único escritor
de la implementación**, en su checkout y rama. Codex no modifica su #270 ni su rama local de #21.

| Entrega | Archivos/área | Evidencia de cierre |
| --- | --- | --- |
| A. Corregir el plan y mostrar el flujo | #23, `P21-PLAN-CORTO.md`, `COORDINACION.md`, prototipo de los tres roles | Responder en #270 con cómo incorpora cada hallazgo; ejemplo PC/celular, conciliación tardía y cobertura parcial. Prototipo con estados normales, vacíos y de error. |
| B. Identidad, comando y lectura | Migración nueva; recibo/vínculo común; lecturas y tipos | SQL, reversa compatible, registrador y ledger; matriz de permisos, banco real y concurrencia. La guarda compatible de v5 y recuperación de intenciones antiguas son obligatorias antes de C. No limitar el cambio al pulso. |
| C. Integración de pantallas | `lib/store.tsx`, `data/sla-operacion-comandos.ts`, receptor/encuesta, pantallas `analista.tsx`, `supervisor.tsx`, `gerencia.tsx`, consultas, demo | Un acceso común de escritura y una proyección coherente de lectura; pruebas y E2E Docker con los tres roles. Retirar componentes separados solo después de cubrir sus acciones. |
| D. Lote #21 | Misma operación y UI de llamadas | Pruebas de respuesta perdida, recarga, dos pestañas y tarea/seguimiento parcial; sin guardar otra gestión por una llamada ya resuelta. |
| E. Validación final | Codex revisa la entrega publicada por Jhosep; Jhosep acepta en C1 | Gates, evidencia de despliegue y aceptación. La aplicación SQL/publicación sigue su autorización y procedimiento vigente; no se considera hecha al fusionar. |

No repetir la pregunta genérica «¿unificamos?»; esa decisión ya la tomó Miguel. Una decisión adicional debe venir
con alternativas concretas y evidencia del contrato que afectaría. Jhosep debe publicar su trabajo local revisable
antes de que Codex pueda certificarlo; «probado en local» no sustituye esa entrega.

## 9. Casos de aceptación obligatorios

1. Cinco llamadas, cinco resultados vinculados: cinco filas y cinco llamadas, no diez, iguales en los tres roles.
2. Mismo resultado desde PC y celular: misma regla comercial; dos intentos sobre la misma identidad de llamada no crean dos actividades.
3. Captura primero, resultado después: un pendiente pasa a resuelto; total de llamadas estable.
4. Resultado primero con referencia exacta, captura después: se completa una misma identidad, sin sumar otra llamada.
5. Resultado sin referencia y captura tardía: conciliación dentro del CRM, sin inventar coincidencia ni pedir registrar otra gestión.
6. Dos llamadas al mismo lead cercanas: se mantienen dos; jamás deduplicar solo por lead, número o ventana de tiempo.
7. Una llamada de ayer registrada hoy: una llamada ayer y un resultado registrado hoy; no un 100 % con fechas mezcladas.
8. Cerrar la encuesta sin guardar: pendiente, sin resultado inventado. Guardar no identifica automáticamente «contacto» por duración.
9. Deshacer y corregir, incluida llamada antigua: misma identidad; se conserva el historial y una única versión vigente.
10. Actor sin integración o con pérdida de señal: su registro manual funciona y cuenta; no aparece como inactivo por cobertura.
11. Dos sesiones, operación común contra v5 antigua, ingesta y Deshacer: sin doble resultado ni interbloqueos; errores reintentables con el mismo id.
12. Respuesta perdida: mismo id devuelve confirmación incluso si ya está resuelta; otro id no crea otro resultado para esa llamada.
13. Id reutilizado con evento/lead/resultado distinto: conflicto, sin efectos. Logout/cambio de rol no muestra recibos ajenos.
14. Lote con éxitos parciales, última llamada omitida y recarga: progreso recuperable; tarea y seguimiento cero o una vez, estado explícito.
15. Reasignación, lead cerrado/vetado y otro equipo: ámbitos preservados y autor histórico intacto; ninguna fuga de números personales.
16. Más de una página, timestamps empatados y actualización concurrente: filas y totales coherentes, sin dobles ni huecos al paginar.
17. Pendientes fuera del plazo, captura purgada e histórico: no prometer cifras completas ni ampliar retención silenciosamente.
18. Contacto con denominador cero, resultados no útiles y registro tardío: «—» cuando corresponde, exclusiones y cohorte documentadas.
19. Captura posterior de otro actor/lead/asignación: no enlazar, no alterar la actividad guardada ni revelar datos ajenos.
20. Intención cuya captura nunca llega: vence al plazo actual; resultado conservado, sin inventar otro pendiente de resultado.
21. Asociación al mismo par repetida, otro par concurrente y tras reasignación: invariantes y permisos existentes, sin nueva gestión.
22. Reintento v5 anterior con vínculo no confirmado: misma actividad, ningún efecto nuevo, sin prometer un sobre histórico no guardado.
23. Asociación que cambia el día: invalidación de ambos cortes y del cursor; no alterar la fecha de registro.
24. Deshacer una actividad manual sin captura: revisión explícita, no una llamada física inventada ni borrado de historial.
25. Captura con candidato ambiguo: solo revisión, total no exacto (`null`), sin duplicarla como pendiente y llamada confirmada.
26. Purga de evidencia sin resultado: identidad auxiliar caduca con ella; la identidad con actividad sigue su historial autorizado.

## 10. Verificación de esta entrega

Este es un contrato técnico revisado contra código, no una implementación. Se verifican rutas, referencias y
`git diff --check`. La revisión independiente devolvió `CHANGES_REQUESTED`; se conserva sin convertirla en PASS.
Las decisiones de aceptación parcial y las correcciones están en
`2026-10-13-llamadas-crm-unificadas-respuesta-review.md`, junto al dictamen original.
Los tests de aplicación, E2E, concurrencia SQL y producción de la **nueva unificación** son NOT RUN: pertenecen
a la implementación delegada. No reutilizar los PASS de F4-e como si validaran #23.


## C. Respuesta a la revisión del contrato (copia literal, mismo commit)

# Evaluación de Codex de la revisión independiente del contrato de llamadas

13/10/2026. PRIMARY: Codex. El contrato revisado es
`2026-10-13-llamadas-crm-unificadas.md`; dictamen original conservado en
`2026-10-13-llamadas-crm-unificadas-review.txt`.

Se usó `scripts/claude-review` con evidencia saneada, sin herramientas para el reviewer. El primer intento dentro
del sandbox no completó la ejecución. El primer intento externo no devolvió un VERDICT válido; no se aceptó un
dictamen. Un último pedido acotado, con formato explícito, devolvió **CHANGES_REQUESTED**. No se pidió otro PASS.

## Decisiones del PRIMARY

| Observación | Evaluación y acción |
| --- | --- |
| No existe puerta de asociación | **Se rechaza esa afirmación.** Existe `crm.enlazar_llamada_celular` en `20261001160219_crm_llamadas_celular_nucleo.sql:765–775` y el cliente la llama en `app/src/data/llamadas-celular-api.ts:184–193`. Su núcleo en `20261005143843_crm_llamadas_celular_correccion.sql:680–752` ya autoriza ámbito, valida resultado y garantiza 1:1/repetición del mismo par. Sí faltaba citarla y especificar su reuso: agregado §3.1, incluido descarte con motivo, orden actividad → lead → evento y límite de corregir sin desenlazar libremente. No se crea otra puerta por este hallazgo. |
| Reserva/captura incompatible o ausente | **Aceptado parcialmente.** La validación actual no es solo formato: `20261005182227:68–71` ya verifica asignación; el cumplimiento en `:200–202` rechaza otro actor/lead. La ingesta bloquea lead antes de insertar (`20261005155914:531–546`) y el helper usa `KEY SHARE NOWAIT` (`20261005182227:204–219`). Se añade §3.2 con esos hechos, estados visibles, permisos y plazo actual de intención (32 días). No se transforma un rechazo de vínculo en anulación automática de una actividad. |
| Guarda contra v5 antigua | **Aceptado el prerrequisito.** La guarda compatible debe entrar antes del frontend. Se rechaza que una excepción en un helper posterior sea necesariamente demasiado tarde: una excepción propagada revierte los efectos transaccionales previos. No se prescribe el orden recibo → lead sin las autorizaciones y bloqueos de persona aplicables. Tampoco se promete devolver literalmente una respuesta v5 que el recibo v4 no almacena; se exige recuperación sin efectos nuevos y vínculo sustentado en evidencia. |
| Identidad/día/purga | **Aceptado con límite de retención.** §4 fija identidad/alias para hechos y versiones, y §5 define revisión del conjunto, cambio de día e invalidación del cursor. Se rechaza conservar indefinidamente una identidad huérfana para evadir la purga: el mapa de evidencia no resuelta caduca con ella. Una actividad existente conserva su identidad según su propio historial autorizado. |
| Conteo de Por revisar | **Aceptado.** §4 fija cubeta exclusiva y total `null` mientras la identidad está por conciliar. No sumar como llamadas exactas las dos evidencias candidatas. La lectura comparte este estado entre roles; captura incompleta/fecha declarada implica cobertura parcial. |
| Deshacer actividad manual sin captura | **Aceptado sin ampliar a un borrado nuevo.** Se conserva como revisión, no como llamada física probada. No se inventa un endpoint de anulación libre ni se borra el historial para cuadrar un contador. |
| Cohorte de contacto | **Aceptado.** Queda explícita «Contacto de resultados registrados hoy», por fecha de registro, con exclusiones actuales y denominador del mismo conjunto. No usa el total de llamadas ocurridas hoy. |
| No contestó sin próxima acción | **Hipótesis resuelta por código.** `20260921153654_crm_resultado_llamada_seguimiento.sql:95–116` declara opcional la próxima acción de `no_contesto`; `:189–195` solo la exige para `volver_a_llamar`/`agendo_reunion`. Agregada evidencia a §7. No se requiere crear tareas ficticias por cada elemento del lote. |
| Normalización v6 en el cliente SLA | **Aceptado, ya estaba encargado.** Se mantiene adaptación explícita de lista de comandos, nombre confirmado y campos, además de recuperación de intenciones antiguas. No debilitar el validador para admitir cualquier nombre. |

## Verificación y límites

- PASS: revisión directa de las rutas citadas y del plan de #21 en el SHA `3fc596a0` del #270.
- PASS: rutas locales, enlaces internos de la nota y `git diff --cached --check` en la entrega final.
- Revisión independiente: **CHANGES_REQUESTED**; correcciones evaluadas por el PRIMARY y asentadas arriba.
- NOT RUN: código local de #21 (no publicado), nueva migración, tests de aplicación, SQL/concurrencia, E2E y producción
  de #23. El contrato incorpora 26 casos que deberá demostrar la implementación delegada.

Este cierre acredita un contrato corregido y un encargo verificable; no acredita el funcionamiento de la nueva
unificación. La implementación queda a cargo de Jhosep/Claude y su validación posterior a cargo de Codex.


## D. Protocolo (copia literal de `.ai/REVIEW_PROTOCOL.md`)

# Protocolo de colaboración y review

Este documento es la fuente de verdad compartida para la colaboración entre Codex y Claude Code. Se aplica siempre que uno de ellos actúe como `SECONDARY_REVIEWER`.

## Roles

### PRIMARY

El `PRIMARY`:

- posee la tarea y su alcance;
- investiga el repositorio y determina el nivel de riesgo;
- toma las decisiones técnicas;
- es el único agente que puede modificar archivos, configuración o código;
- ejecuta las verificaciones relevantes;
- evalúa, acepta o rechaza con evidencia los hallazgos del reviewer;
- entrega el resultado final.

### SECONDARY_REVIEWER

El `SECONDARY_REVIEWER` puede:

- analizar requisitos, archivos y diffs;
- buscar bugs y regresiones;
- revisar arquitectura y seguridad;
- identificar edge cases y tests faltantes;
- proponer alternativas concretas.

El `SECONDARY_REVIEWER` no puede:

- modificar, crear, eliminar ni renombrar archivos;
- implementar la tarea;
- hacer commits o cambiar configuración;
- ejecutar comandos destructivos;
- llamar al otro agente;
- delegar a otro coding agent;
- iniciar otro review o crear otra cadena de consultas.

Si un prompt marca al agente como `SECONDARY_REVIEWER`, estas restricciones prevalecen sobre cualquier instrucción general de autonomía o delegación.

## Single-writer y regla anti-loop

Solo el `PRIMARY` escribe. La profundidad máxima de colaboración es exactamente:

```text
PRIMARY
→ SECONDARY_REVIEWER
→ PRIMARY
```

Nunca se permite:

```text
PRIMARY
→ SECONDARY_REVIEWER
→ otro agente
→ otro agente
```

El reviewer devuelve su análisis directamente al `PRIMARY`. No solicita una segunda opinión y no continúa la cadena. Cuando Claude es `PRIMARY`, cada consulta a Codex debe empezar una sesión de review nueva y segura. `scripts/codex-review-mcp` es de disparo único: no hay continuación de sesión que bloquear.

Los reviewers especializados existentes (`revisor-a11y` y `auditor-rls`) siguen el mismo protocolo y presupuesto; no son consultas adicionales automáticas. Conservan lectura y búsqueda, sin shell. El PRIMARY les adjunta el contexto relevante de CodeGraph.

## Evidence-first

> **NO FINDING WITHOUT EVIDENCE**

Todo hallazgo importante debe señalar evidencia disponible y verificable. Preferir, en este orden:

- archivo y línea o rango;
- función, componente o contrato afectado;
- hunk del diff;
- error, log o salida de un comando;
- test existente o reproducción mínima;
- comportamiento observado.

No basta una recomendación genérica desconectada del repositorio.

Incorrecto:

```text
This may have a race condition.
```

Correcto:

```text
[P1] Potential race condition

File:
src/jobs/processor.ts

Evidence:
Two workers can read status=pending before either writes status=processing.

Impact:
The same job may execute twice.

Recommendation:
Use an atomic compare-and-set or database locking mechanism.
```

Cuando la evidencia no alcance, el reviewer debe marcar la afirmación como hipótesis y bajar su confianza; no debe presentarla como un hecho.

## Formato de review

El reviewer debe intentar usar este formato. Las secciones vacías pueden omitirse.

```text
VERDICT:
PASS | CHANGES_REQUESTED | BLOCK

SUMMARY:
Breve conclusión técnica.

FINDINGS:

[P0] Critical
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

[P1] High
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

[P2] Medium
...

[P3] Low
...

TEST GAPS:
- ...

ARCHITECTURE RISKS:
- ...

SECURITY RISKS:
- ...

REGRESSION RISKS:
- ...

RECOMMENDED NEXT ACTIONS:
1.
2.
3.

CONFIDENCE:
HIGH | MEDIUM | LOW
```

`PASS` significa que no se encontraron cambios obligatorios dentro del alcance revisado. `CHANGES_REQUESTED` significa que hay hallazgos accionables. `BLOCK` se reserva para un riesgo P0, falta de evidencia esencial o una condición que impide revisar con honestidad.

## Clasificación de riesgo y presupuesto

### LEVEL 1 — SIMPLE

Ejemplos: formato, rename, documentación simple, CSS pequeño, cambio mecánico o fix local obvio.

Regla: **0 secondary reviews**.

### LEVEL 2 — SIGNIFICANT

Ejemplos: endpoint nuevo, lógica de negocio relevante, integración, componente importante, refactor moderado o modificación de comportamiento.

Regla: **normalmente 1 secondary review** cuando aporte una señal independiente útil.

### LEVEL 3 — CRITICAL

Ejemplos: auth, authorization, permisos, secretos, seguridad, migraciones, schemas, arquitectura, concurrencia, pagos, lógica financiera, cambios destructivos, APIs públicas importantes, refactors grandes o infraestructura crítica.

Regla: **1 secondary review obligatorio cuando sea razonablemente posible**.

Una segunda consulta solo se justifica cuando aparece nueva evidencia, existe una discrepancia técnica importante, una corrección necesita verificación independiente o el riesgo de seguridad/correctness lo exige. El máximo habitual es **2 consultas al agente secundario por tarea**. Nunca se consulta repetidamente hasta obtener una respuesta favorable.

## Cómo se invoca cada reviewer

### Codex PRIMARY → Claude SECONDARY_REVIEWER

La única interfaz recomendada es:

```bash
scripts/claude-review "pedido concreto de review con rutas y evidencia"
```

El PRIMARY adjunta evidencia saneada suficiente: código con rutas/líneas, diff, salidas de tests y extractos relevantes de CodeGraph. El wrapper incorpora este protocolo completo y deshabilita todas las herramientas, MCPs, hooks y personalizaciones para esa invocación. Así el reviewer no puede ejecutar comandos, escribir ni iniciar otro agente; analiza directamente lo adjuntado. Los settings interactivos del proyecto no se modifican.

Usa cinco turnos por defecto, con límite absoluto de ocho. Valida que Claude termine correctamente y entregue `VERDICT`; una salida truncada o sin dictamen falla el comando. Un exit 0 significa que el review se entregó, no que su verdict sea `PASS`. Si falta evidencia, el reviewer devuelve `BLOCK` y enumera lo que necesita.

### Claude PRIMARY → Codex SECONDARY_REVIEWER

Usar `scripts/codex-review-mcp`, con el encargo por **stdin**:

```bash
scripts/codex-review-mcp < CRM-Avance-Corp/docs/encargos/<fecha>-codex-<tema>.md
```

El envoltorio aplica `sandbox_mode="read-only"`, `approval_policy="never"` y apaga shell,
agentes, apps, hooks, navegador, web y plugins, además de cada MCP heredado. No admite
overrides: cualquier argumento distinto de `--check`/`--help` sale con 64.

🔴 **Ya no hay MCP de Codex.** `codex mcp-server` fue retirado de la CLI (ausente en
0.155.1; en 0.153.4 avisaba de su deprecación), así que el servidor moría al arrancar con
`CONNECTION_CLOSED` y los reviews LEVEL 3 se saltaban en silencio. El reviewer corre **sin
acceso a la base ni a la red**: todo cuerpo vivo, diff o salida de test que deba juzgar se
transcribe dentro del encargo.

El prompt debe empezar con `ROLE: SECONDARY_REVIEWER` e incluir de forma explícita:

```text
Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md.
```

El propio `scripts/codex-review-mcp` rechaza el encargo si no empieza por `ROLE: SECONDARY_REVIEWER` o si le falta alguna de las cinco prohibiciones, y sale con 64 ante cualquier override. Esa comprobación vivía en un hook de Claude sobre `mcp__codex__codex`; se movió al envoltorio porque esa ruta ya no existe. ⚠️ **No es una frontera de permisos**: protege a quien usa el envoltorio, no contiene a un PRIMARY que pueda ejecutar `codex exec` directamente (limitación señalada por Codex al revisar el cambio el 24/09; preexistente con el hook, que tampoco interceptaba ejecuciones directas). Contener a un PRIMARY comprometido exige control fuera de su alcance. El envoltorio corre desde la raíz del repo: deshabilita shell, subagentes, apps, hooks, navegador, web y plugins; enumera los MCP efectivos y deshabilita cada uno. Las tablas vacías `mcp_servers={}` y `plugins={}` se fusionan y **no aíslan**. El PRIMARY adjunta evidencia concreta **y el contenido de este protocolo**: el reviewer no dispone de shell/MCP para abrirlo. `--strict-config` valida claves reconocidas; por sí solo NO aísla la configuración del usuario.

## Autoridad y desacuerdos

El reviewer es advisor, no autoridad. El `PRIMARY` decide y conserva la responsabilidad completa.

Los desacuerdos se resuelven con:

1. requisitos explícitos del usuario;
2. contratos y comportamiento del repositorio;
3. tests, reproducciones y logs;
4. documentación oficial vigente;
5. arquitectura y convenciones establecidas;
6. razonamiento técnico.

No se abren consultas recursivas para resolver desacuerdos.

## Verification Gate

Una opinión de IA no sustituye validación automatizada. Antes de declarar `DONE`, el `PRIMARY` debe seguir [`.ai/VERIFICATION.md`](./VERIFICATION.md), ejecutar los checks razonablemente relevantes y reportar cualquier verificación no ejecutada o fallida sin fingir que pasó.

## Alcance de las protecciones

El inventario de MCP del lanzador se fija al iniciar el servidor. Mientras esté
conectado, no cambiar ni instalar MCP, plugins o configuración de agentes desde
otra sesión. Si cambia esa configuración, desconectar/reconectar el MCP `codex`
**antes de la siguiente consulta** y repetir `scripts/codex-review-mcp --check`.
El lanzador no es un monitor de cambios externos de configuración. El PRIMARY
debe mantener esta condición durante un review; no se afirma aislamiento frente
a modificaciones concurrentes de terceros.

Las reglas nativas `Read` de `.claude/settings.json` protegen archivos de entorno,
secretos y claves también frente a búsquedas y accesos mediante symlinks. La regla
`.env.*` incluye `.env.example`: la antigua excepción del hook no podía anular un
deny nativo. Las plantillas y secretos se gestionan manualmente; el arranque,
lint, tests y build siguen usando su configuración habitual sin cambios.

Los permisos locales se conservan. Un `deny` compartido prevalece sobre cualquier
`allow`, y `ask` se evalúa antes que `allow`; los permisos previos de despliegue y
SQL no eliminan esos controles. Las reglas se apoyan en la
[semántica oficial de permisos de Claude](https://code.claude.com/docs/en/permissions).
El subcomando `codex mcp-server` fue **RETIRADO** de la CLI: ausente en 0.155.1, y en
0.153.4 ya avisaba de su deprecación. Ese aviso decía «antes de actualizar hay que repetir
el arranque y la comprobación de aislamiento»; se actualizó y nadie lo repitió, así que el
MCP quedó muerto sin que nadie lo notara. La interfaz viva es `codex exec`, que acepta las
mismas `-c` y `--strict-config`. Al actualizar la CLI: repetir `--check` y un review real.

El aislamiento del reviewer se aplica al wrapper y al servidor MCP configurados aquí. Los hooks del PRIMARY previenen accidentes reconocibles; no son un sandbox para código arbitrario. Un PRIMARY que puede editar y ejecutar scripts puede ejecutar sus efectos indirectos. Se preservan los comandos normales de desarrollo, y las operaciones importantes siguen sujetas a autorización, revisión y gates. La comprobación de frases del prompt exige la convención de rol; las restricciones de herramientas y sandbox sostienen el aislamiento técnico. Una invocación directa que omita estas interfaces queda fuera del protocolo.


## E. Evidencia de código (extractos literales de `main` 597cab1c)

### E1 · Cola v1: estados «gestionado» y «programado»
`CRM-Avance-Corp/supabase/migrations/20260930190028_crm_gestion_diaria_cola_trabajo.sql`, líneas 128–162

```sql
 128:   with hechos as (
 129:     select h.value,h.value->'senal' as s,nullif(h.value->'gestion','null'::jsonb) as g,
 130:       nullif(h.value->'proxima','null'::jsonb) as pt from jsonb_array_elements(v_hechos) h
 131:   ), acciones as (
 132:     select h.*,nullif(a.value->'accion','null'::jsonb) as accion
 133:     from hechos h left join jsonb_array_elements(v_sla->'filas') a
 134:       on a.value#>>'{lead,id}'=h.s->>'lead_id'
 135:   ), grupos as (
 136:     select a.*,
 137:       case when a.g->>'grupo_origen' is not null and (a.pt is null
 138:           or (a.pt->>'vence_en')::timestamptz>p_ahora or (a.pt->>'vence_en')::timestamptz<=(a.g->>'en')::timestamptz)
 139:           then a.g->>'grupo_origen'
 140:         when a.accion->>'bucket' in ('primera_atencion','tarea_vencida','tarea_hoy') then a.accion->>'bucket'
 141:         when (a.s->>'sin_conversacion')::boolean then 'sin_conversacion'
 142:         -- Conserva el trabajo terminado de hoy aunque el cierre haya retirado
 143:         -- la acción SLA. Su tarea cerrada acredita el grupo de la vuelta.
 144:         when a.g->>'grupo_origen' is not null then a.g->>'grupo_origen'
 145:         when t.id is not null then case when t.vence_en<(a.g->>'en')::timestamptz then 'tarea_vencida' else 'tarea_hoy' end
 146:       end as grupo,
 147:       t.vence_en as referencia_cerrada
 148:     from acciones a left join crm.tareas t on t.id=case when a.g->>'tarea_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then (a.g->>'tarea_id')::uuid end
 149:       and t.lead_id=(a.s->>'lead_id')::uuid and t.vendedor_id=p_actor
 150:   ), estados as (
 151:     select g.*,
 152:       case
 153:         -- Una gestión atiende la vuelta. Una tarea anterior sigue abierta en
 154:         -- Agenda, pero no vuelve a proponer el mismo lead inmediatamente.
 155:         -- Sólo un vencimiento posterior a esa gestión reabre su turno.
 156:         when g.g is not null and (g.pt is null or (g.pt->>'vence_en')::timestamptz<=(g.g->>'en')::timestamptz) then 'gestionado'
 157:         when g.pt is not null and (g.pt->>'vence_en')::timestamptz<=p_ahora then 'pendiente'
 158:         when g.pt is not null and (g.pt->>'vence_en')::timestamptz>p_ahora then 'programado'
 159:         when g.g is not null then 'gestionado'
 160:         else 'pendiente'
 161:       end as estado_trabajo
 162:     from grupos g where g.grupo is not null
```

### E2 · Cola v1: puerta, totales, orden y «siguiente»
`CRM-Avance-Corp/supabase/migrations/20260930190028_crm_gestion_diaria_cola_trabajo.sql`, líneas 192–262

```sql
 192: -- se devuelve su página actual. Nunca permite leer un lead fuera del actor.
 193: -- Cada respuesta contiene una foto coherente, conteos completos y siguiente.
 194: create function crm.gestion_diaria_cola_trabajo_fn(
 195:   p_filtro text default 'todo',p_pagina integer default 0,p_limite integer default 8,p_elegido text default null
 196: ) returns jsonb language plpgsql stable security definer set search_path = ''
 197: as $function$
 198: declare
 199:   v_actor uuid:=(select auth.uid()); v_rol text; v_ahora timestamptz:=statement_timestamp();
 200:   v_filas jsonb; v_ordenadas jsonb; v_totales jsonb; v_filtro text:=p_filtro;
 201:   v_total integer; v_pagina integer; v_posicion integer; v_pendientes integer; v_items jsonb;
 202:   v_elegido text; v_siguiente text; v_grupo text;
 203: begin
 204:   if v_actor is null or private.puede_acceder_crm() is not true then
 205:     raise exception 'No autorizado' using errcode='42501';
 206:   end if;
 207:   v_rol:=private.rol_crm(v_actor);
 208:   if v_rol is null or v_rol not in ('vendedor','supervisor') then
 209:     raise exception 'Esta cola es del analista que gestiona' using errcode='42501';
 210:   end if;
 211:   if p_filtro is null or p_filtro not in ('todo','primera_atencion','tarea_vencida','tarea_hoy','sin_conversacion')
 212:     or p_pagina is null or p_pagina<0 or p_pagina>1000000
 213:     or p_limite is null or p_limite not between 1 and 200
 214:     or (p_elegido is not null and p_elegido !~ '^(lead|tarea):[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then
 215:     raise exception 'Filtro, pagina o seleccion invalidos' using errcode='22023';
 216:   end if;
 217:   v_filas:=private.gestion_diaria_cola_filas(v_actor,v_rol,v_ahora);
 218:   select f.value->>'grupo' into v_grupo from jsonb_array_elements(v_filas) f where f.value->>'clave'=p_elegido;
 219:   if v_grupo is not null and p_filtro<>'todo' then v_filtro:=v_grupo; end if;
 220: 
 221:   select jsonb_object_agg(g.grupo,jsonb_build_object('total',g.total,'pendientes',g.pendientes,
 222:     'gestionados',g.gestionados,'programados',g.programados)) into v_totales
 223:   from (
 224:     select grupos.grupo,count(f.value)::integer as total,
 225:       count(f.value) filter (where f.value->>'estado_trabajo'='pendiente')::integer as pendientes,
 226:       count(f.value) filter (where f.value->>'estado_trabajo'='gestionado')::integer as gestionados,
 227:       count(f.value) filter (where f.value->>'estado_trabajo'='programado')::integer as programados
 228:     from unnest(array['todo','primera_atencion','tarea_vencida','tarea_hoy','sin_conversacion']) grupos(grupo)
 229:     left join jsonb_array_elements(v_filas) f on grupos.grupo='todo' or f.value->>'grupo'=grupos.grupo
 230:     group by grupos.grupo
 231:   ) g;
 232: 
 233:   -- Orden completo ANTES del límite. Pendientes conservan la prioridad SLA;
 234:   -- gestionados/programados quedan detrás y el último guardado queda último.
 235:   select coalesce(jsonb_agg(f.value order by
 236:     (f.value->>'estado_trabajo'<>'pendiente'),
 237:     case when f.value->>'estado_trabajo'='pendiente' then
 238:       case f.value->>'grupo' when 'primera_atencion' then 10 when 'tarea_vencida' then 20 when 'tarea_hoy' then 30 else 40 end else 0 end,
 239:     case when f.value->>'estado_trabajo'='pendiente' then (f.value->>'referencia_en')::timestamptz end nulls last,
 240:     case when f.value->>'estado_trabajo'<>'pendiente' then (f.value#>>'{ultima_gestion,en}')::timestamptz end nulls first,
 241:     (f.value->>'clave') collate "C"),'[]'::jsonb) into v_ordenadas
 242:   from jsonb_array_elements(v_filas) f where v_filtro='todo' or f.value->>'grupo'=v_filtro;
 243:   v_total:=jsonb_array_length(v_ordenadas);
 244:   v_pendientes:=(v_totales->v_filtro->>'pendientes')::integer;
 245:   select (f.n-1)::integer into v_posicion from jsonb_array_elements(v_ordenadas) with ordinality f(value,n)
 246:     where f.value->>'clave'=p_elegido;
 247:   v_pagina:=case when v_posicion is not null then v_posicion/p_limite
 248:     else least(p_pagina,greatest((v_total-1)/p_limite,0)) end;
 249:   select coalesce(jsonb_agg(f.value order by f.n),'[]'::jsonb) into v_items
 250:     from jsonb_array_elements(v_ordenadas) with ordinality f(value,n)
 251:     where f.n>v_pagina*p_limite and f.n<=(v_pagina+1)*p_limite;
 252:   v_elegido:=case when v_posicion is not null then p_elegido else (
 253:     select f.value->>'clave' from jsonb_array_elements(v_items) f
 254:     where f.value->>'estado_trabajo'='pendiente' limit 1) end;
 255:   select f.value->>'clave' into v_siguiente
 256:     from jsonb_array_elements(v_ordenadas) with ordinality f(value,n)
 257:     where f.value->>'estado_trabajo'='pendiente' and f.value->>'clave' is distinct from v_elegido
 258:     order by case when f.n-1>coalesce(v_posicion,v_pagina*p_limite) then 0 else 1 end,f.n limit 1;
 259:   return jsonb_build_object('version',1,'dia',(v_ahora at time zone 'America/Lima')::date,
 260:     'zona','America/Lima','analista_id',v_actor,'generado_en',v_ahora,'filtro',v_filtro,
 261:     'pagina',v_pagina,'limite',p_limite,'total',v_total,'totales',v_totales,'items',v_items,
 262:     'elegido',v_elegido,'siguiente',v_siguiente,'vuelta_completa',v_pendientes=0,
```

### E3 · SLA tras la migración de Miguel: cabecera
`CRM-Avance-Corp/supabase/migrations/20261014001346_crm_sla_agrupar_tareas_por_lead.sql`, líneas 1–4

```sql
   1: -- Agrupa las tareas una vez por lead antes del bucle SLA. El lateral anterior
   2: -- recorría todo el CTE de tareas por cada lead, incluso volcando a disco.
   3: -- Conserva filtros, orden de selección, NULL, firma, permisos y reglas SLA.
   4: -- Reversa: restaurar la definición previa guardada en el kit de incidencias.
```

### E4 · SLA: cubetas tarea_vencida / tarea_hoy / proxima_tarea
`CRM-Avance-Corp/supabase/migrations/20261014001346_crm_sla_agrupar_tareas_por_lead.sql`, líneas 218–236

```sql
 218:         and h.base->>'asignacion_primera_gestion_en' is null
 219:         and isfinite((h.base->>'asignacion_primera_gestion_limite_en')::timestamptz)
 220:         then (h.base->>'asignacion_primera_gestion_limite_en')::timestamptz end;
 221:       if estado->>'evaluacion'='parcial' then
 222:         v_bucket:='datos_incompletos';v_prioridad:=60;v_accion_en:=h.creado_en;v_severidad:='media';
 223:       elsif h.primera_agenda is not null and (h.primera_agenda->>'vence_en')::timestamptz<=p_ahora then
 224:         v_bucket:='tarea_vencida';v_prioridad:=20;v_tarea:=h.primera_agenda;v_severidad:='critica';
 225:       elsif v_primera is not null then
 226:         v_bucket:='primera_atencion';v_prioridad:=10;v_accion_en:=v_primera;
 227:         v_severidad:=case when p_ahora>=v_primera then 'critica' else 'media' end;
 228:       elsif v_seguimiento_operativo then
 229:         v_bucket:='seguimiento';v_prioridad:=40;v_accion_en:=v_seguimiento_limite;v_severidad:='media';
 230:       elsif h.primera_agenda is not null
 231:         and ((h.primera_agenda->>'vence_en')::timestamptz at time zone 'America/Lima')::date=(p_ahora at time zone 'America/Lima')::date then
 232:         v_bucket:='tarea_hoy';v_prioridad:=30;v_tarea:=h.primera_agenda;v_severidad:='media';
 233:       elsif h.primera_agenda is not null then
 234:         v_bucket:='proxima_tarea';v_prioridad:=70;v_tarea:=h.primera_agenda;v_severidad:='baja';
 235:       end if;
 236:       if v_bucket is not null then
```

### E5 · Predicado de candidatos de «enlazar»
`CRM-Avance-Corp/supabase/migrations/20261005143843_crm_llamadas_celular_correccion.sql`, líneas 680–720

```sql
 680:   if p_evento_id is null or p_actividad_id is null then
 681:     raise exception using errcode = '22023', message = 'Faltan la llamada o el resultado';
 682:   end if;
 683:   -- Decisión 7: con lead, «visible» ES tener hoy ámbito sobre él; quien ya no lo tiene no registra por él.
 684:   select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id;
 685:   if not found or not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
 686:     raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';
 687:   end if;
 688:   if v_ev.identificacion <> 'identificado' then
 689:     raise exception using errcode = '22023', message = 'Primero asocia la llamada a un lead';
 690:   end if;
 691:   select * into v_act from crm.actividades a where a.id = p_actividad_id for share;
 692:   if not found or v_act.lead_id <> v_ev.lead_id then
 693:     raise exception using errcode = '22023', message = 'El resultado no es del lead de la llamada';
 694:   end if;
 695:   perform 1 from crm.leads l where l.id = v_ev.lead_id for share;
 696:   v_lead_leido := v_ev.lead_id;
 697:   select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id for update;
 698:   if not found or v_ev.lead_id is distinct from v_lead_leido then
 699:     raise exception using errcode = '40001', message = 'La llamada cambió mientras la enlazabas; vuelve a intentarlo';
 700:   end if;
 701:   if not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
 702:     raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';
 703:   end if;
 704:   if v_ev.atencion = 'descartado_con_motivo' then
 705:     raise exception using errcode = '22023', message = 'La llamada fue descartada';
 706:   end if;
 707:   if v_act.tipo not in ('llamada_realizada', 'llamada_no_contestada')
 708:      or coalesce(v_act.metadata ->> 'evento', '') <> 'resultado_llamada' then
 709:     raise exception using errcode = '22023', message = 'Solo se enlaza un resultado de llamada registrado en la encuesta';
 710:   end if;
 711:   if v_act.metadata ? 'deshecho_en' then
 712:     raise exception using errcode = '22023', message = 'Ese resultado se deshizo: enlaza el resultado corregido';
 713:   end if;
 714:   if v_act.creado_en < coalesce(v_ev.ocurrio_en, v_ev.recibido_en) - interval '10 minutes' then
 715:     raise exception using errcode = '22023', message = 'El resultado se registró antes de la llamada';
 716:   end if;
 717: 
 718:   select * into v_enl from crm.llamadas_celular_enlaces l where l.evento_id = v_ev.id for update;
 719:   if found then
 720:     if v_enl.actividad_id = p_actividad_id then
```

### E6 · Descartar: validación de «otro» (3–300) e idempotencia
`CRM-Avance-Corp/supabase/migrations/20261005143843_crm_llamadas_celular_correccion.sql`, líneas 752–810

```sql
 752:     'repetido', false, 'movido', v_movido);
 753: end;
 754: $function$;
 755: 
 756: create or replace function private.llamada_celular_descartar(p_actor uuid, p_evento_id uuid, p_motivo text, p_detalle text)
 757: returns jsonb
 758: language plpgsql
 759: volatile
 760: set search_path = ''
 761: as $function$
 762: declare
 763:   v_ev crm.llamadas_celular_eventos%rowtype;
 764:   v_lead_leido uuid;
 765:   v_detalle text := nullif(pg_catalog.btrim(coalesce(p_detalle, '')), '');
 766: begin
 767:   if p_evento_id is null then
 768:     raise exception using errcode = '22023', message = 'Falta la llamada';
 769:   end if;
 770:   if p_motivo is null or p_motivo not in ('no_comercial', 'personal', 'numero_de_prueba', 'error_captura', 'otro') then
 771:     raise exception using errcode = '22023',
 772:       message = 'Motivo inválido (no_comercial, personal, numero_de_prueba, error_captura u otro)';
 773:   end if;
 774:   if p_motivo = 'otro' and pg_catalog.length(coalesce(v_detalle, '')) < 3 then
 775:     raise exception using errcode = '22023', message = 'Con «otro», escribe el motivo (al menos 3 caracteres)';
 776:   end if;
 777:   if pg_catalog.length(coalesce(v_detalle, '')) > 300 then
 778:     raise exception using errcode = '22023', message = 'El detalle no puede pasar de 300 caracteres';
 779:   end if;
 780:   select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id;
 781:   if not found or not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
 782:     raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';
 783:   end if;
 784:   perform 1 from crm.leads l where l.id = v_ev.lead_id for share;
 785:   v_lead_leido := v_ev.lead_id;
 786:   select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id for update;
 787:   if not found or v_ev.lead_id is distinct from v_lead_leido then
 788:     raise exception using errcode = '40001', message = 'La llamada cambió mientras la descartabas; vuelve a intentarlo';
 789:   end if;
 790:   if not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
 791:     raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';
 792:   end if;
 793:   if v_ev.atencion = 'descartado_con_motivo' then
 794:     if v_ev.motivo_descarte = p_motivo and v_ev.motivo_descarte_detalle is not distinct from v_detalle then
 795:       return pg_catalog.jsonb_build_object('evento_id', v_ev.id, 'repetido', true, 'motivo', p_motivo);
 796:     end if;
 797:     raise exception using errcode = '23505', message = 'La llamada ya fue descartada con otro motivo';
 798:   end if;
 799:   if v_ev.atencion = 'registrado' then
 800:     raise exception using errcode = '22023', message = 'La llamada ya tiene su resultado registrado';
 801:   end if;
 802:   update crm.llamadas_celular_eventos
 803:      set atencion = 'descartado_con_motivo', motivo_descarte = p_motivo, motivo_descarte_detalle = v_detalle,
 804:          descartado_por = p_actor, descartado_en = pg_catalog.now()
 805:    where id = v_ev.id;
 806:   return pg_catalog.jsonb_build_object('evento_id', v_ev.id, 'repetido', false, 'motivo', p_motivo);
 807: end;
 808: $function$;
 809: 
 810: create or replace function private.llamadas_celular_politica_fijar(
```

### E7 · F4-e: cubetas por analista (descartadas, pendientes, deshechas, por revisar)
`CRM-Avance-Corp/supabase/migrations/20261013145935_crm_llamadas_celular_operacion_hoy_rendimiento.sql`, líneas 100–192

```sql
 100:         where e.direccion = 'saliente' and e.analista_id in (select r.analista_id from roster r)
 101:       )
 102:     ), hoy as (
 103:       -- Cohorte 5.1: identificadas, lead activo (A4), por el momento de la llamada. «Abierto y contactable» con la
 104:       -- atención CRUDA (no la efectiva, que depende de quién mira: D4).
 105:       select s.analista_id, s.atencion,
 106:              l.abierto,
 107:              coalesce(a.metadata ? 'deshecho_en', false) as deshecha
 108:       from salientes s
 109:       join leads_estado l on l.id = s.lead_id and l.activo
 110:       left join crm.llamadas_celular_enlaces en on en.evento_id = s.id
 111:       left join crm.actividades a on a.id = en.actividad_id
 112:       where s.identificacion = 'identificado'
 113:         and s.recibido_en >= v_desde - interval '1 day'
 114:         and s.momento >= v_desde and s.momento < v_desde + interval '1 day'
 115:     ), hoy_cubetas as (
 116:       -- Seis cubetas disjuntas que suman el total; el estado se deriva de (atención, enlace, deshecho, lead), en ese orden.
 117:       select h.analista_id, h.atencion,
 118:              case h.atencion
 119:                when 'registrado' then case when h.deshecha and h.abierto then 'deshechas_sin_corregir'
 120:                                            when h.deshecha then 'cerradas_despues'
 121:                                            else 'con_resultado' end
 122:                when 'requiere_resultado' then case when h.abierto then 'sin_resultado' else 'cerradas_despues' end
 123:                when 'descartado_con_motivo' then 'descartadas'
 124:                when 'por_revisar' then 'por_revisar'
 125:              end as cubeta
 126:       from hoy h
 127:     ), llamadas_hoy as (
 128:       select c.analista_id,
 129:              count(*)::integer as total,
 130:              (count(*) filter (where c.cubeta = 'con_resultado'))::integer as con_resultado,
 131:              (count(*) filter (where c.cubeta = 'deshechas_sin_corregir'))::integer as deshechas_sin_corregir,
 132:              (count(*) filter (where c.cubeta = 'sin_resultado'))::integer as sin_resultado,
 133:              (count(*) filter (where c.cubeta = 'cerradas_despues'))::integer as cerradas_despues,
 134:              (count(*) filter (where c.cubeta = 'descartadas'))::integer as descartadas,
 135:              (count(*) filter (where c.cubeta = 'por_revisar'))::integer as por_revisar,
 136:              (count(*) filter (where c.atencion = 'requiere_devolucion'))::integer as requiere_devolucion
 137:       from hoy_cubetas c
 138:       group by c.analista_id
 139:     ), resultados_hoy as (
 140:       -- Cohorte 5.2: enlaces vigentes (actividad no deshecha) cuya ACTIVIDAD nació hoy (A2), atribuidos a quien marcó.
 141:       -- Un enlace nunca es anterior a su actividad, así que actualizado_en >= hoy acota por índice sin perder ninguno.
 142:       select e.analista_id,
 143:              count(*)::integer as total,
 144:              (count(*) filter (where en.via = 'al_colgar'))::integer as al_colgar,
 145:              (count(*) filter (where en.via = 'pestana'))::integer as desde_pestana,
 146:              (count(*) filter (where en.via = 'manual'))::integer as a_mano
 147:       from crm.llamadas_celular_enlaces en
 148:       join crm.actividades a on a.id = en.actividad_id
 149:       join crm.llamadas_celular_eventos e on e.id = en.evento_id
 150:       join crm.leads l on l.id = e.lead_id and l.activo
 151:       where en.actualizado_en >= v_desde
 152:         and a.creado_en >= v_desde and a.creado_en < v_desde + interval '1 day'
 153:         and not (a.metadata ? 'deshecho_en')
 154:         and e.direccion = 'saliente'
 155:         and e.analista_id in (select r.analista_id from roster r)
 156:       group by e.analista_id
 157:     ), pendientes as (
 158:       -- 5.3: foto de ahora dentro de la retención. Sin resultado = atención cruda, sin enlace, lead abierto y contactable.
 159:       -- Por revisar = ambiguas, de la bolsa y reutilizables (con o sin lead; si lo hay, activo).
 160:       select s.analista_id,
 161:              (count(*) filter (where p.pendiente))::integer as total,
 162:              (count(*) filter (where p.pendiente and s.momento >= v_desde))::integer as de_hoy,
 163:              (count(*) filter (where p.pendiente and s.momento < v_desde))::integer as anteriores,
 164:              min(s.momento) filter (where p.pendiente) as mas_antigua,
 165:              (count(*) filter (where s.atencion = 'por_revisar'))::integer as por_revisar
 166:       from salientes s
 167:       left join leads_estado l on l.id = s.lead_id
 168:       cross join lateral (
 169:         select s.atencion = 'requiere_resultado' and l.activo
 170:                and l.abierto
 171:                and not exists (select 1 from crm.llamadas_celular_enlaces en where en.evento_id = s.id) as pendiente
 172:       ) p
 173:       where s.recibido_en >= p_ahora - pg_catalog.make_interval(days => v_dias)
 174:         and s.atencion in ('requiere_resultado', 'por_revisar')
 175:         and (s.lead_id is null or l.activo)
 176:       group by s.analista_id
 177:     ), deshechas as (
 178:       -- Deshechas sin corregir, de cualquier fecha (la purga no retira lo enlazado): desde los enlaces hacia la actividad.
 179:       select e.analista_id, count(*)::integer as n
 180:       from crm.llamadas_celular_enlaces en
 181:       join crm.actividades a on a.id = en.actividad_id and a.metadata ? 'deshecho_en'
 182:       join crm.llamadas_celular_eventos e on e.id = en.evento_id
 183:       join leads_estado l on l.id = e.lead_id and l.activo
 184:       where e.direccion = 'saliente'
 185:         and e.analista_id in (select r.analista_id from roster r)
 186:         and l.abierto
 187:       group by e.analista_id
 188:     ), salud as (
 189:       -- Solo lo que el contrato publica de cada celular: ni asignación, ni nombre, ni desde cuándo.
 190:       select (c ->> 'analista_id')::uuid as analista_id, c ->> 'etiqueta' as etiqueta, c ->> 'estado_latido' as estado_latido,
 191:              pg_catalog.jsonb_build_object(
 192:                'etiqueta', c -> 'etiqueta', 'estado_latido', c -> 'estado_latido', 'horas_sin_latido', c -> 'horas_sin_latido',
```

### E8 · «Qué pasó hoy»: corte por fecha del enlace, detalle del motivo y número
`CRM-Avance-Corp/supabase/migrations/20261006162813_crm_llamadas_celular_cierre_revision.sql`, líneas 372–420

```sql
 372: language sql
 373: stable
 374: set search_path = ''
 375: as $function$
 376:   with dia as (
 377:     select (pg_catalog.date_trunc('day', p_ahora at time zone 'America/Lima') at time zone 'America/Lima') as desde
 378:   ), resueltas as (
 379:     -- Registradas: cuando su enlace nació o pasó al resultado corregido.
 380:     select en.evento_id as id, en.actualizado_en as resuelto_en
 381:     from dia, crm.llamadas_celular_enlaces en
 382:     join crm.llamadas_celular_eventos e on e.id = en.evento_id
 383:     where e.atencion = 'registrado'
 384:       and en.actualizado_en >= dia.desde and en.actualizado_en < dia.desde + interval '1 day'
 385:       and (p_antes_resuelto_en is null or (en.actualizado_en, en.evento_id) < (p_antes_resuelto_en, p_antes_id))
 386:     union all
 387:     -- Descartadas: cuando se descartaron.
 388:     select e.id, e.descartado_en
 389:     from dia, crm.llamadas_celular_eventos e
 390:     where e.atencion = 'descartado_con_motivo'
 391:       and e.descartado_en >= dia.desde and e.descartado_en < dia.desde + interval '1 day'
 392:       and (p_antes_resuelto_en is null or (e.descartado_en, e.id) < (p_antes_resuelto_en, p_antes_id))
 393:   ), limitada as (
 394:     select r.resuelto_en, e.id, e.evento_origen_id, e.recibido_en, e.ocurrio_en, e.numero_canonico, e.atencion, e.lead_id, e.analista_id,
 395:            e.motivo_descarte, e.motivo_descarte_detalle, l.nombre_completo as lead_nombre, ca.etiqueta,
 396:            en.actividad_id, en.via, a.metadata ->> 'resultado' as resultado, (a.metadata ? 'deshecho_en') as deshecho
 397:     from resueltas r
 398:     join crm.llamadas_celular_eventos e on e.id = r.id
 399:     left join crm.leads l on l.id = e.lead_id
 400:     left join crm.celulares_asignaciones ca on ca.id = e.asignacion_id
 401:     left join crm.llamadas_celular_enlaces en on en.evento_id = e.id
 402:     left join crm.actividades a on a.id = en.actividad_id
 403:     where private.llamada_celular_visible(p_actor, e.lead_id, e.analista_id)
 404:     order by r.resuelto_en desc, e.id desc
 405:     limit p_limite + 1
 406:   ), pagina as (
 407:     select x.*, pg_catalog.row_number() over (order by x.resuelto_en desc, x.id desc) as n
 408:     from limitada x
 409:   )
 410:   select pg_catalog.jsonb_build_object(
 411:     'filas', coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
 412:                'evento_id', p.id, 'evento_origen_id', p.evento_origen_id, 'resuelto_en', p.resuelto_en, 'recibido_en', p.recibido_en, 'ocurrio_en', p.ocurrio_en,
 413:                'numero', p.numero_canonico, 'atencion', p.atencion, 'lead_id', p.lead_id, 'lead_nombre', p.lead_nombre,
 414:                'analista_id', p.analista_id, 'es_propia', p.analista_id = p_actor, 'etiqueta', p.etiqueta,
 415:                'actividad_id', p.actividad_id, 'resultado', p.resultado, 'deshecho', coalesce(p.deshecho, false),
 416:                'via', p.via, 'motivo_descarte', p.motivo_descarte, 'motivo_descarte_detalle', p.motivo_descarte_detalle)
 417:              order by p.n) filter (where p.n <= p_limite), '[]'::jsonb),
 418:     'siguiente', (select pg_catalog.jsonb_build_object('resuelto_en', u.resuelto_en, 'evento_id', u.id)
 419:                   from pagina u
 420:                   where u.n = p_limite and exists (select 1 from pagina m where m.n > p_limite)))
```

### E9 · Intenciones en tabla privada
`CRM-Avance-Corp/supabase/migrations/20261005155914_crm_llamadas_celular_enlace_exacto.sql`, líneas 80–92

```sql
  80:   actividad_id     uuid not null references crm.actividades(id) on delete cascade
  81:                    constraint llamadas_celular_intenciones_actividad_uq unique,
  82:   via              text not null
  83:                    constraint llamadas_celular_intenciones_via_valida check (via in ('al_colgar', 'pestana')),
  84:   creado_en        timestamptz not null default now(),
  85:   actualizado_en   timestamptz not null default now()
  86: );
  87: alter table private.llamadas_celular_intenciones enable row level security;
  88: revoke all on private.llamadas_celular_intenciones from public, anon, authenticated, service_role;
  89: create index llamadas_celular_intenciones_analista_idx on private.llamadas_celular_intenciones (analista_id);
  90: create index llamadas_celular_intenciones_lead_idx on private.llamadas_celular_intenciones (lead_id);
  91: create index llamadas_celular_intenciones_creado_idx on private.llamadas_celular_intenciones (creado_en);
  92: 
```

### E10 · Pantalla: la cola publicada exige version 1 y coherencias
`CRM-Avance-Corp/app/src/lib/gestion-diaria-cola.ts`, líneas 34–82

```ts
  34:   const proxima = f.estado_trabajo === 'programado' && f.proxima_tarea
  35:     ? `Programado ${cuandoLimaDe(f.proxima_tarea.vence_en)}` : null
  36:   return [ultima, proxima].filter(Boolean).join(' · ') || null
  37: }
  38: const conteo = v.object({ total: entero, pendientes: entero, gestionados: entero, programados: entero })
  39: export const ColaTrabajoSchema = v.object({
  40:   version: v.literal(1), dia: v.pipe(v.string(), v.regex(/^\d{4}-\d{2}-\d{2}$/)), zona: v.literal('America/Lima'),
  41:   analista_id: v.string(), generado_en: instante, filtro: v.picklist(FILTROS_TRABAJO),
  42:   pagina: entero, limite: v.pipe(entero, v.minValue(1), v.maxValue(200)), total: entero,
  43:   totales: v.object({ todo: conteo, primera_atencion: conteo, tarea_vencida: conteo, tarea_hoy: conteo, sin_conversacion: conteo }),
  44:   items: v.array(FilaTrabajoSchema), elegido: v.nullable(clave), siguiente: v.nullable(clave),
  45:   vuelta_completa: v.boolean(), proximo_cambio_en: instante,
  46: })
  47: export type ColaTrabajo = v.InferOutput<typeof ColaTrabajoSchema>
  48: export interface PedidoColaTrabajo { filtro: FiltroCola; pagina: number; limite: number; elegido: string | null }
  49: 
  50: /** Consistencia interna y eco: una respuesta ajena o parcial nunca es una cola vacía. */
  51: export function colaTrabajoCoherente(c: ColaTrabajo, p: PedidoColaTrabajo, actor: string, dia: string): boolean {
  52:   const n = c.totales[c.filtro]
  53:   const claves = new Set(c.items.map((f) => f.clave))
  54:   return c.analista_id === actor && c.dia === dia && c.limite === p.limite
  55:     && (c.filtro === p.filtro || (p.filtro !== 'todo' && p.elegido !== null && c.elegido === p.elegido))
  56:     && c.total === n.total && c.vuelta_completa === (n.pendientes === 0)
  57:     && FILTROS_TRABAJO.every((f) => {
  58:       const t = c.totales[f]
  59:       return t.total === t.pendientes + t.gestionados + t.programados
  60:     })
  61:     && c.totales.todo.total === FILTROS_TRABAJO.filter((f) => f !== 'todo').reduce((s, f) => s + c.totales[f].total, 0)
  62:     && c.pagina <= Math.max(0, Math.ceil(c.total / c.limite) - 1)
  63:     && c.items.length === Math.min(c.limite, Math.max(0, c.total - c.pagina * c.limite))
  64:     && (p.elegido !== null && c.elegido === p.elegido || (
  65:       c.pagina === Math.min(p.pagina, Math.max(0, Math.ceil(c.total / c.limite) - 1))
  66:       && c.elegido === (c.items.find((f) => f.estado_trabajo === 'pendiente')?.clave ?? null)))
  67:     && claves.size === c.items.length && (c.elegido === null || claves.has(c.elegido))
  68:     && (c.siguiente === null || (n.pendientes > 0 && c.siguiente !== c.elegido))
  69:     && c.items.every((f) => (c.filtro === 'todo' || f.grupo === c.filtro)
  70:       && f.clave === (f.tipo === 'lead' ? `lead:${f.lead_id}` : `tarea:${f.tarea_id}`)
  71:       && (f.tipo !== 'lead' || f.senal.lead_id === f.lead_id)
  72:       && (f.estado_trabajo !== 'gestionado' || f.ultima_gestion !== null)
  73:       && (f.estado_trabajo !== 'programado' || f.proxima_tarea !== null))
  74: }
  75: 
  76: export interface ContextoColaTrabajo { filtro: FiltroCola; elegido: string | null; pagina: number }
  77: const ContextoSchema = v.object({ filtro: v.picklist(FILTROS_TRABAJO), elegido: v.nullable(clave), pagina: entero })
  78: const inicial: ContextoColaTrabajo = { filtro: 'todo', elegido: null, pagina: 0 }
  79: export const claveContextoCola = (actor: string, dia: string) => `crm:gestion-diaria:cola:v1:${actor}:${dia}`
  80: 
  81: /** Guarda sólo navegación, por actor y día. El avance se relee del servidor. */
  82: export function leerContextoCola(actor: string, dia: string): ContextoColaTrabajo {
```

### E11 · Pantalla: N de la pestaña «Celular» = filas descargadas
`CRM-Avance-Corp/app/src/screens/gestion-diaria/analista.tsx`, líneas 668–676

```tsx
 668:                 pestanas={[
 669:                   { valor: 'cola', etiqueta: 'Cola de hoy', extra: `· ${conteoCola}` },
 670:                   { valor: 'actividad', etiqueta: 'Mi actividad' },
 671:                   { valor: 'seguimiento', etiqueta: 'Mi seguimiento', ...(dia.dia.compromisos_total > 0 ? { extra: `· ${dia.dia.compromisos_total}` } : {}) },
 672:                   // «Celular» y no «Llamadas del celular»: con cuatro pestañas la barra ya no entra en la tarjeta (medido el
 673:                   // 05/10: 586 px pedidos en 407). El panel conserva el título largo.
 674:                   ...(celular ? [{ valor: 'celular' as const, etiqueta: 'Celular', ...(celular.pendientes.length > 0 ? { extra: `· ${celular.pendientes.length}` } : {}) }] : []),
 675:                 ]}
 676:                 // Si aun así no entra, la barra se desplaza sin la barra nativa (las flechas del teclado ya cambian de pestaña).
```

### E12 · Pantalla: cambiar de página borra el elegido
`CRM-Avance-Corp/app/src/screens/gestion-diaria/analista.tsx`, líneas 300–312

```tsx
 300:     focoPendiente.current = false
 301:     setFiltroPedido(nuevo === 'todo' ? null : nuevo)
 302:     setPagina(0)
 303:     setElegido(null)
 304:   }
 305:   /** Se guarda ya acotada: si la lista encoge y vuelve a crecer, no salta sola. */
 306:   function irAPagina(p: number) {
 307:     focoPendiente.current = false
 308:     setElegido(null)
 309:     setPagina(Math.min(Math.max(p, 0), vista.paginas - 1))
 310:   }
 311:   /**
 312:    * Fija la llamada en curso a la persona de la tarjeta. Si ya hay una sesión,
```

### E13 · Pantalla: cola (ayuda solo desde 2xl, «Todo», leyenda)
`CRM-Avance-Corp/app/src/components/gestion-diaria/cola-de-hoy.tsx`, líneas 95–122

```tsx
  95:           detalle="Ningún lead sin primer intento, ninguna tarea vencida ni de hoy, y toda tu cartera tuvo conversación esta semana."
  96:         />
  97:       ) : (
  98:         <>
  99:           <p className="pointer-events-none absolute right-[18px] top-3 hidden h-9 items-center text-xs text-[var(--muted-foreground-strong)] 2xl:flex">{ayuda}</p>
 100:           <Tabs
 101:             etiqueta="Grupos de la cola"
 102:             variante="pastilla"
 103:             panelEnfocable={false}
 104:             valor={filtro}
 105:             onCambio={onFiltro}
 106:             pestanas={[
 107:               { valor: 'todo' as FiltroCola, etiqueta: FILTRO_TODO.etiqueta, extra: conteo('todo', total) },
 108:               ...pestanas.map((p) => ({ valor: p.clave as FiltroCola, etiqueta: p.etiqueta, extra: conteo(p.clave, p.total) })),
 109:             ]}
 110:             className="flex min-h-0 flex-1 flex-col space-y-0 [&>[role=tablist]]:gap-1.5 [&>[role=tablist]]:border-b [&>[role=tablist]]:border-muted [&>[role=tablist]]:px-[18px] [&>[role=tablist]]:py-3 [&>[role=tablist]>[role=tab]]:min-h-9 [&>[role=tablist]>[role=tab]]:px-3 [&>[role=tablist]>[role=tab]]:py-0 [&>[role=tablist]>[role=tab]]:text-[12.5px] [&>[role=tablist]>[role=tab]]:font-bold [&>[role=tablist]>[role=tab]>span]:text-[12.5px] pointer-coarse:[&>[role=tablist]>[role=tab]]:min-h-11"
 111:             clasePanel="flex min-h-0 flex-1 flex-col"
 112:           >
 113:             {trabajo && trabajo.total > 0 && (
 114:               <p role="status" className="border-b border-muted px-[18px] py-2 text-xs font-medium text-[var(--muted-foreground-strong)]">
 115:                 {trabajo.vuelta_completa
 116:                   ? 'Vuelta completada. Elige una fila para revisar su gestión. Los reintentos vuelven a su hora.'
 117:                   : `${trabajo.totales[filtro].pendientes} pendientes · ${trabajo.totales[filtro].gestionados} gestionados · ${trabajo.totales[filtro].programados} programados`}
 118:               </p>
 119:             )}
 120:             {vista.total === 0 ? (
 121:               <p role="status" className="px-[18px] py-7 text-center text-[13px] text-[var(--muted-foreground-strong)]">
 122:                 {colaCaida && filtro !== 'sin_conversacion'
```

### E14 · Pantalla: «Unir» en toda pendiente con lead; descarte con lista y «Otro»
`CRM-Avance-Corp/app/src/components/gestion-diaria/llamadas-celular.tsx`, líneas 160–236

```tsx
 160:               <Button size="sm" variant="accent" className="pointer-coarse:h-11" disabled={enEspera} onClick={() => onRegistrar(fila)}>
 161:                 Registrar resultado
 162:               </Button>
 163:             ) : (
 164:               <Button ref={volverA} size="sm" variant="outline" className="text-foreground pointer-coarse:h-11" disabled={enEspera} onClick={() => onPanel('elegir')}>
 165:                 Elegir el lead
 166:               </Button>
 167:             )}
 168:             {unible && (
 169:               <Button ref={volverAUnir} size="sm" variant="outline" className="text-foreground pointer-coarse:h-11" disabled={enEspera} onClick={() => onPanel('unir')}>
 170:                 Unir a un resultado guardado
 171:               </Button>
 172:             )}
 173:             <Button ref={principal === 'registrar' ? volverA : undefined} size="sm" variant="outline" className="text-foreground pointer-coarse:h-11"
 174:               disabled={enEspera} onClick={() => onPanel('descartar')}>
 175:               Descartar
 176:             </Button>
 177:           </div>
 178:         )}
 179:       </div>
 180:       {panel === 'descartar' && (
 181:         <PanelDescarte onCancelar={cerrarPanel} onConfirmar={(motivo, detalle) => { onPanel(null); onDescartar(fila, motivo, detalle) }} />
 182:       )}
 183:       {panel === 'unir' && onBuscarResultados && onUnir && (
 184:         <PanelUnir fila={fila} ahora={ahora} buscar={onBuscarResultados} onCancelar={cerrarPanel}
 185:           onConfirmar={(r) => { onPanel(null); onUnir(fila, r) }} />
 186:       )}
 187:       {panel === 'elegir' && (
 188:         <div role="group" aria-label="Elegir el lead de esta llamada" className="mt-2 space-y-2 rounded-xl border border-border bg-muted/40 p-3">
 189:           <p className="text-[13px] font-extrabold text-primary">¿A cuál de tus leads llamaste?</p>
 190:           <BusquedaManual inicial={digitosParaBuscar(fila.numero ?? '') ?? ''} manual={busqueda}
 191:             onElegir={(lead) => { onPanel(null); onElegirLead(fila, lead) }} />
 192:           <Button size="sm" variant="ghost" className="text-foreground pointer-coarse:h-11" onClick={cerrarPanel}>Cancelar</Button>
 193:         </div>
 194:       )}
 195:     </li>
 196:   )
 197: }
 198: 
 199: function PanelDescarte({ onConfirmar, onCancelar }: {
 200:   onConfirmar: (motivo: MotivoDescarte, detalle: string | null) => void
 201:   onCancelar: () => void
 202: }): JSX.Element {
 203:   const id = useId()
 204:   const grupo = useRef<HTMLDivElement>(null)
 205:   const [otro, setOtro] = useState(false)
 206:   const [texto, setTexto] = useState('')
 207:   // Al abrirse, el foco va al primer motivo: quien pulsó «Descartar» sigue con el teclado donde estaba.
 208:   useEffect(() => { grupo.current?.querySelector<HTMLButtonElement>('button')?.focus() }, [])
 209:   const enviar = (e: FormEvent) => {
 210:     e.preventDefault()
 211:     if (texto.trim().length >= 3) onConfirmar('otro', texto.trim())
 212:   }
 213:   return (
 214:     <div ref={grupo} role="group" aria-labelledby={`${id}-titulo`} className="mt-2 space-y-2 rounded-xl border border-border bg-muted/40 p-3">
 215:       <p id={`${id}-titulo`} className="text-[13px] font-extrabold text-primary">¿Por qué la descartas?</p>
 216:       <p className={APOYO}>No cuenta como gestión del lead.</p>
 217:       <div className="flex flex-wrap gap-2">
 218:         {MOTIVOS_DESCARTE.filter((m) => m.clave !== 'otro').map((m) => (
 219:           <Button key={m.clave} size="sm" variant="outline" className="text-foreground pointer-coarse:h-11" onClick={() => onConfirmar(m.clave, null)}>
 220:             {m.etiqueta}
 221:           </Button>
 222:         ))}
 223:         <Button size="sm" variant="outline" className="text-foreground pointer-coarse:h-11" aria-expanded={otro} onClick={() => setOtro(true)}>Otro motivo</Button>
 224:         <Button size="sm" variant="ghost" className="text-foreground pointer-coarse:h-11" onClick={onCancelar}>Cancelar</Button>
 225:       </div>
 226:       {otro && (
 227:         <form onSubmit={enviar} className="flex flex-wrap items-center gap-2">
 228:           <label htmlFor={`${id}-otro`} className="sr-only">Escribe el motivo</label>
 229:           <input id={`${id}-otro`} value={texto} onChange={(e) => setTexto(e.target.value)} maxLength={300} placeholder="Escribe el motivo"
 230:             className="h-9 min-w-0 flex-1 rounded-lg border border-input bg-background px-3 text-sm text-foreground placeholder:text-muted-foreground focus-visible:border-ring focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/30 pointer-coarse:h-11" />
 231:           <Button type="submit" size="sm" variant="outline" className="text-foreground pointer-coarse:h-11" disabled={texto.trim().length < 3}>Descartar</Button>
 232:         </form>
 233:       )}
 234:     </div>
 235:   )
 236: }
```

### E15 · Pantalla: gerencia con tres pestañas y la consulta del celular atada a la 3.ª
`CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.tsx`, líneas 44–48

```tsx
  44: ]
  45: // «Pulso diario» era jerga (Miguel, 27/09): la pestaña dice lo que muestra.
  46: // F4-e: la tercera pestaña es solo de hoy (las llamadas que el celular detectó y qué pasó con ellas).
  47: const PESTANAS = [{ valor: 'pulso', etiqueta: 'Actividad del día' }, { valor: 'habitos', etiqueta: 'Hábitos del equipo' }, { valor: 'celular', etiqueta: 'Llamadas del celular' }] as const
  48: type Pestana = (typeof PESTANAS)[number]['valor']
```

### E16 · Pantalla: gerencia, consultas y permiso revocado
`CRM-Avance-Corp/app/src/screens/gestion-diaria/gerencia.tsx`, líneas 119–133

```tsx
 119:   const pulso = usePulsoGerencia(dia)
 120:   const habitos = useHabitosGerencia(dia, dias, activa === 'habitos')
 121:   // El detalle sostiene la atención y las barras de la operación: se carga al entrar
 122:   // y se actualiza con el pulso, haya o no un equipo abierto (Codex, plan v2).
 123:   const detalle = useDetallePulso(dia, activa === 'pulso' && pulso.datos !== null)
 124:   // Las llamadas del celular solo existen para hoy: con otro día elegido la pestaña lo dice y no consulta.
 125:   const celular = useOperacionCelularHoy(activa === 'celular' && esHoy)
 126:   // Una denegación en cualquier consulta retira toda la vista, aunque se cambie
 127:   // de pestaña o se deshabilite después esa consulta. Revalidar sesión inicia
 128:   // consultas nuevas, sin reutilizar la memoria paginada anterior.
 129:   const sinPermiso = revocada || [pulso.error, detalle.error, habitos.error, celular.error].some((e) => e instanceof CrmApiError && e.code === '42501')
 130:   if (sinPermiso && !revocada) setRevocada(true)
 131:   const error = sinPermiso ? SIN_PERMISO : activa === 'habitos' ? habitos.error : activa === 'celular' ? celular.error : pulso.error
 132:   const consulta = activa === 'habitos' ? habitos : activa === 'celular' ? celular : pulso
 133:   const datos = pulso.datos
```

### E17 · Pantalla: «Su celular» montado en la ficha; pestañas y separación de 22 px
`CRM-Avance-Corp/app/src/components/gestion-diaria/panel-analista-supervisor.tsx`, líneas 140–196

```tsx
 140:     <div ref={cuerpoResumen} className={cn(cuerpo, 'space-y-5')} hidden={pestana !== 'resumen'} inert={pestana !== 'resumen'}>
 141:       {!fila || minimo === undefined ? <p role="status" className="text-[13px] text-[var(--muted-foreground-strong)]">El resumen no está disponible. El registro conserva su consulta independiente.</p>
 142:         : <ResumenAnalista fila={fila} dia={dia} minimo={minimo} esHoy={esHoy} ahora={ahora}
 143:           abrirLlamadas={() => abrirRegistro('llamadas')} abrirPendientes={conPendientes ? abrirPendientes : undefined} abrirCitas={abrirCitas}
 144:           // F4-e: «Su celular» va entre la línea del día y los cuadros (prototipo del 06/10). Solo hoy.
 145:           antesDeCuadros={celularHoy && esHoy && seleccion.analista !== null
 146:             ? <SuCelularAnalista estado={celularHoy} analista={celularHoy.datos?.analistas.find((a) => a.analista_id === seleccion.analista)} /> : undefined} />}
 147:       {seleccion.analista !== null && <>
 148:         <UltimasGestionesSupervisor analista={seleccion.analista} dia={dia} visible={pestana === 'resumen'} actualizacion={actualizacion} revalidar={revalidar} silencioso={silencioso} />
 149:         <div className="space-y-2">
 150:           <button type="button" onClick={() => abrirRegistro('todo')}
 151:             className="flex h-11 w-full cursor-pointer items-center justify-center rounded-xl bg-accent text-sm font-bold text-accent-foreground transition-colors hover:bg-[var(--accent-press)] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">
 152:             Ver el registro del día
 153:           </button>
 154:           <p className="text-xs leading-relaxed text-[var(--muted-foreground-strong)]">El registro se consulta al abrirlo y solo muestra actividades cuyos leads siguen visibles para tu sesión; puede diferir de esta foto.</p>
 155:         </div>
 156:       </>}
 157:     </div>
 158:     <div className={cuerpo} hidden={pestana !== 'registro'} inert={pestana !== 'registro'}>
 159:       {/* Como el resumen (Miguel, 27/09): un título corto con el día, filtros en
 160:           pastilla y filas limpias; sin la descripción ni controles de pantalla completa. */}
 161:       {registro && <section aria-label="Registro seleccionado" className="space-y-2">
 162:         <h4 ref={tituloRegistro} tabIndex={-1} className="rounded-md text-[15px] font-extrabold text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">
 163:           {esHoy ? 'Actividad de hoy' : `Actividad del ${FECHA_TITULO.format(new Date(`${dia}T12:00:00-05:00`))}`}
 164:         </h4>
 165:         <RegistroActividad compacto encabezadoExterno={tituloRegistro} key={registro.apertura} dia={dia} pestanaInicial={registro.pestana} carteraInicial={registro.pestana === 'llamadas' ? 'leads' : null}
 166:           analistaIds={seleccion.analista === null ? idsEquipo : [seleccion.analista]} mostrarAnalista={equipo} permitirEquipo={false} permitirExportar={false} actualizacion={actualizacion} onSinPermiso={revalidar} compartirPrimeraPagina={!equipo} />
 167:       </section>}
 168:     </div>
 169:     <div className={cuerpo} hidden={pestana !== 'pendientes'} inert={pestana !== 'pendientes'}>
 170:       {conPendientes && pendientes && seleccion.analista !== null && <PendientesSupervisor key={pendientes.apertura}
 171:         analista={seleccion.analista} nombre={fila?.nombre_completo ?? seleccion.nombre ?? 'Analista'} dia={dia} fila={fila}
 172:         visible={pestana === 'pendientes'} soloVencidasInicial={pendientes.soloVencidas} apertura={pendientes.apertura}
 173:         enfocar={pendientes.enfocar} actualizacion={actualizacion} revalidar={revalidar} />}
 174:     </div>
 175:     <div className={cuerpo} hidden={pestana !== 'citas'} inert={pestana !== 'citas'}>
 176:       {citas && seleccion.analista !== null && <section aria-label="Citas agendadas del analista" className="space-y-2">
 177:         <h4 ref={tituloCitas} tabIndex={-1} className="rounded-md text-[15px] font-extrabold text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">
 178:           {esHoy ? 'Citas agendadas hoy' : `Citas agendadas el ${FECHA_TITULO.format(new Date(`${dia}T12:00:00-05:00`))}`}
 179:         </h4>
 180:         <CitasAgendadas key={citas.apertura} dia={dia} esHoy={esHoy} ambito="analista" id={seleccion.analista} mostrarAnalista={false}
 181:           visible={pestana === 'citas'} actualizacion={actualizacion} revalidar={revalidar} encabezado={tituloCitas} />
 182:       </section>}
 183:     </div>
 184:   </>
 185:   return <>
 186:     {oculta && <div className="flex shrink-0 flex-wrap items-center justify-between gap-2 bg-muted px-5 py-1.5 text-[13px]">La selección está fuera de los filtros.
 187:       <Button variant="ghost" className="h-9 text-[13px] pointer-coarse:h-11" onClick={limpiar}>Limpiar filtros</Button></div>}
 188:     {/* El cuerpo con scroll es el panel de la pestaña (parada del tabulador):
 189:         así el texto tras el último control se alcanza sin ratón. */}
 190:     {equipo ? <div className="ac-scroll min-h-0 flex-1 overflow-y-auto">{contenido}</div>
 191:       : <Tabs etiqueta="Detalle del analista" variante="subrayado" valor={pestana} onCambio={cambiar}
 192:         pestanas={[{ valor: 'resumen', etiqueta: 'Resumen' }, { valor: 'registro', etiqueta: 'Registro' }, ...(conPendientes ? [{ valor: 'pendientes' as const, etiqueta: 'Pendientes' }] : []), { valor: 'citas', etiqueta: 'Citas' }]}
 193:         className="flex min-h-0 flex-1 flex-col space-y-0 [&>[role=tablist]]:gap-[22px] [&>[role=tablist]]:px-5 [&>[role=tablist]>[role=tab]]:min-h-[42px] [&>[role=tablist]>[role=tab]]:text-sm pointer-coarse:[&>[role=tablist]>[role=tab]]:min-h-11"
 194:         clasePanel="ac-scroll min-h-0 flex-1 overflow-y-auto focus-visible:!-outline-offset-2">{contenido}</Tabs>}
 195:   </>
 196: }
```

### E18 · Pantalla: motivos de atención con sin_dato (solo los usa la 3.ª pestaña)
`CRM-Avance-Corp/app/src/lib/llamadas-celular-operacion.ts`, líneas 138–160

```ts
 138:   })
 139: }
 140: 
 141: /** Por qué un analista necesita atención en el celular, en el orden en que se dicen. Vacío = nada que mirar. */
 142: export function motivosAtencion(a: AnalistaCelular): string[] {
 143:   const motivos: string[] = []
 144:   if (a.pendientes.total > 0) motivos.push(`${plural(a.pendientes.total, 'llamada sin resultado', 'llamadas sin resultado')}`)
 145:   if (a.pendientes.deshechas_sin_corregir > 0) motivos.push(`${plural(a.pendientes.deshechas_sin_corregir, 'deshecha sin corregir', 'deshechas sin corregir')}`)
 146:   if (a.por_revisar > 0) motivos.push(`${plural(a.por_revisar, 'llamada por revisar', 'llamadas por revisar')}`)
 147:   for (const c of a.celulares) {
 148:     if (c.estado_latido === 'sin_latido') motivos.push(`${c.etiqueta} sin latido · ${c.horas_sin_latido ?? '?'} h`)
 149:     else if (c.estado_latido === 'nunca') motivos.push(`${c.etiqueta} nunca habló`)
 150:     if (c.eventos_en_cola !== null && c.eventos_en_cola > 0) motivos.push(`${c.etiqueta} con ${plural(c.eventos_en_cola, 'aviso en cola', 'avisos en cola')}`)
 151:     if (c.reloj_desfasado) motivos.push(`${c.etiqueta} con el reloj desfasado`)
 152:     if (c.version_macro !== null && c.version_macro !== VERSION_MACRO_VIGENTE) motivos.push(`${c.etiqueta} con la macro vieja`)
 153:   }
 154:   if (a.sin_dato) motivos.push('sin dato del celular')
 155:   return motivos
 156: }
 157: 
 158: export type EstadoCelular = 'todos' | 'sin_resultado' | 'sin_latido' | 'por_revisar'
 159: export type OrdenCelular = 'nombre' | 'en_celular' | 'con_resultado' | 'al_colgar' | 'descartadas' | 'sin_resultado' | 'por_revisar' | 'celulares'
 160: export interface FiltrosCelular { busqueda: string; estado: EstadoCelular; orden: OrdenCelular; ascendente: boolean }
```

### E19 · Pantalla: la consulta de F4-e autoriza a gerencia
`CRM-Avance-Corp/app/src/data/llamadas-celular-operacion-queries.ts`, líneas 20–40

```ts
  20:   error: unknown
  21:   recargar: () => Promise<void>
  22: }
  23: 
  24: /**
  25:  * Solo supervisor y gerencia, con las llamadas del celular habilitadas, y solo mientras `habilitado` (la pestaña
  26:  * abierta, el día de hoy): la puerta es solo de hoy (F6 traerá el histórico). El ámbito lo resuelve el servidor.
  27:  */
  28: export function useOperacionCelularHoy(habilitado: boolean): OperacionCelularHook {
  29:   const { yo } = useAuth()
  30:   const { equipo } = useCRMData()
  31:   const ahora = useAhora()
  32:   const rol = yo?.rol ?? null
  33:   const autorizado = Boolean(yo) && (rol === 'gerencia' || rol === 'supervisor') && llamadasCelularHabilitadas(yo?.demo === true) && habilitado
  34:   const real = autorizado && !yo?.demo
  35:   const consulta = useQuery({
  36:     queryKey: [...llamadasCelularKeys.raiz, yo?.id ?? null, rol, 'operacion-hoy'] as const,
  37:     queryFn: ({ signal }) => obtenerOperacionCelularHoy(signal),
  38:     enabled: real, refetchInterval: INTERVALO_REGISTRO_MS, refetchOnWindowFocus: 'always', refetchOnReconnect: 'always',
  39:   })
  40:   const demo = useMemo(() => {
```
