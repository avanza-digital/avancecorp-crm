# F4-e — Contrato de la puerta y oráculos (10/10/2026, solo documento, para el OK de Miguel)

Desarrolla `F4E-PLAN-CORTO.md` con las decisiones aprobadas por Miguel el 07/10 (#215: decisión 4 «F4-e en F4»,
#17 con A1–A7 y sus cuatro condiciones; texto en `DECISIONES-PENDIENTES.md`). **No hay SQL ni código:** la
migración se escribe cuando Miguel apruebe el plan corto de la sección 9. Todo lo citado se leyó en `main`
(`8a71317c`); lo que no se comprobó va marcado **(por confirmar)**.

## 1. En una línea

Una puerta de **solo lectura** que devuelve, para **hoy en Lima**, las cifras de llamadas del celular por analista y
por equipo, más la salud de los celulares, sin números, leads ni horas exactas. La consumen la tercera pestaña de
«Toda la operación hoy» (gerencia) y el bloque «Su celular» de «Mi equipo hoy» (supervisor).

## 2. Firma, roles y errores

| | Puerta | Núcleo |
| --- | --- | --- |
| Nombre | `crm.llamadas_celular_operacion_hoy_fn(p_supervisor_id uuid default null) → jsonb` | `private.llamadas_celular_operacion_hoy(p_actor uuid, p_supervisor_id uuid, p_ahora timestamptz) → jsonb` |
| Seguridad | `security definer`, `stable`, `set search_path = ''`; `execute` solo a `authenticated` | `security invoker`, `stable`, `set search_path = ''`; sin `execute` para nadie (la llama solo la puerta) |
| Actor | `private.llamadas_celular_actor(array['supervisor','gerencia'])` (`20261001160219:163`): los demás roles, directorio incluido, reciben `42501` | Recibe el actor ya validado |
| Reloj | `statement_timestamp()` | `p_ahora` (para el oráculo, como la novena) |

**`p_supervisor_id`:**

| Actor | Nulo | Su propio id | Id de otro supervisor | Id que no es supervisor activo |
| --- | --- | --- | --- | --- |
| Gerencia | Toda la operación | — | Ese equipo | `22023` «No es un supervisor activo» |
| Supervisor | Su equipo | Su equipo | `42501` (el mismo mensaje; no se revela si existe) | `42501` |

**Errores hacia la pantalla:** solo `42501` «Sin acceso a las llamadas del celular» (uniforme, el de la familia) y
`22023` para gerencia con un id inválido. Nunca detalles internos.

## 3. Ámbito: quién cuenta para quién

- **Analistas, gerencia:** salen de `private.gestion_diaria_pulso_roster()` (`20260924201358:124`: vendedores
  activos visibles con su supervisor más cercano). Así las claves de equipo coinciden con «Actividad del día».
  Nulo → todas las filas; con id → filas con `supervisor_id = <id>`.
- **Analistas, supervisor:** el roster **no sirve**: llama a `private.gestion_diaria_pulso_autorizar()`
  (`20260924201358:112`), que da `42501` a todo lo que no sea gerencia (comprobado el 10/10; el plan corto lo daba por
  reutilizable tal cual). Para el supervisor, el núcleo usa `private.vendedor_ids_visibles(p_actor)`
  (`20260803164348`: su subárbol) cruzado con `crm.equipo` (`rol_crm = 'vendedor'`, activos) y los nombres de
  `public.perfiles`; todos bajo un único equipo con su id.
- **Regla D4 (igualdad por analista):** las cifras de un analista dependen solo de él (`eventos.analista_id` y los
  predicados de §5), nunca de quién pregunta. Gerencia y un supervisor que lo incluyan ven **los mismos números**
  de ese analista; lo único que puede diferir es la composición del equipo (roster para gerencia, subárbol para el
  supervisor) y, por tanto, los totales de equipo, que son siempre la suma de los miembros listados. Lo prueba O17.
- **Atribución (A1):** cada evento cuenta para `eventos.analista_id` (quien marcó), aunque el lead cambie de dueño.
  **No** se usa `private.llamada_celular_visible` fila por fila: sigue al dueño actual del lead y cuesta una consulta
  por fila.
- **El celular del supervisor (A7):** sus asignaciones vigentes (`celulares_asignaciones.analista_id = actor`) van en
  `su_celular`, fuera de `analistas[]`. Sus llamadas no se suman al equipo.
- **Equipos:** un elemento por `supervisor_id` del roster, con el nombre del supervisor; los analistas sin supervisor
  activo van en un equipo `sin_supervisor` (misma regla que el pulso, **por confirmar** contra `gerencia.tsx`).

## 4. La ventana «hoy»

`v_desde := date_trunc('day', p_ahora at time zone 'America/Lima') at time zone 'America/Lima'`; hoy = `[v_desde,
v_desde + 1 day)`. Es el molde de `private.llamadas_celular_resueltas_hoy` (`20261006162813:368`).

**Momento de una llamada** (A3): `ocurrio_en` (hora del celular). Si es nulo, o va más de 5 minutos por delante de
`recibido_en` (reloj corrido; el mismo umbral de `reloj_desfasado` en `20261006150254:51`), se usa `recibido_en`.
→ decisión **D2**.

## 5. Las cifras

Base común a todo: `direccion = 'saliente'`; nunca `private.llamadas_celular_recepciones` (cuenta personales, N1).
Las llamadas personales y a no-leads no existen en `crm.llamadas_celular_eventos` (decisión 3 de F2), así que no se
cuentan como trabajo.

### 5.1 Cohorte «llamadas de hoy» (reloj: el momento de la llamada)

Universo: eventos del analista con `identificacion = 'identificado'`, lead con `activo` (A4: los de baja no cuentan)
y momento dentro de hoy. Se reparte en **cubetas que suman el total**, para que el oráculo cierre:

| Cubeta | Predicado | Rótulo que debe mostrar la pantalla |
| --- | --- | --- |
| `total` | el universo | «Llamadas de hoy (por la hora de la llamada)» |
| `con_resultado` | tiene enlace cuya actividad **no** está deshecha (`not (a.metadata ? 'deshecho_en')`) | «ya con resultado» |
| `deshechas_sin_corregir` | tiene enlace, pero su actividad **está deshecha** (`a.metadata ? 'deshecho_en'`) y el lead sigue abierto y contactable. Deshacer conserva `atencion = 'registrado'` y el enlace (`20261005182227:108–135`): la llamada espera «Registrar el corregido», que mueve el enlace | «deshechas sin corregir» |
| `sin_resultado` | `atencion = 'requiere_resultado'`, sin enlace, y el lead sigue **abierto y contactable**: `l.activo`, `l.etapa not in ('convertido','descartado')`, `not l.no_contactar`, `not private.persona_vetada(l.id)` | «sin resultado» |
| `cerradas_despues` | `requiere_resultado` sin enlace, **o** deshecha sin corregir, pero el lead ya no está abierto o contactable (A5) | «ya no piden resultado» |
| `descartadas` | `atencion = 'descartado_con_motivo'` | «descartadas» (nunca son gestión) |
| `por_revisar` | `atencion = 'por_revisar'` (reutilizables identificadas) | «por revisar» |

`total = con_resultado + deshechas_sin_corregir + sin_resultado + cerradas_despues + descartadas + por_revisar`.
Las seis cubetas son disjuntas: el estado se deriva de (`atencion`, enlace, `deshecho_en` de la actividad, estado
del lead), en ese orden. `requiere_devolucion` no puede aparecer (entrantes bloqueadas) y el oráculo lo comprueba.
Una deshecha sin corregir **no caduca**: la purga solo retira eventos sin enlace (`20261005143843:846–886`), así que
sigue contando hasta que se corrija o el lead se cierre.

**Porcentaje permitido:** `con_resultado / total` (misma cohorte). **Prohibido:** dividir `resultados_hoy.total`
entre `llamadas_hoy.total` (relojes distintos; condición de Miguel).

### 5.2 Cohorte «resultados de hoy» (reloj: la fecha del resultado, A2)

Universo: enlaces vigentes (actividad no deshecha) cuya **actividad** tiene `creado_en` dentro de hoy, atribuidos a
`eventos.analista_id`. Es la cifra que mide el hábito «registrar al colgar».

| Cubeta | Predicado | Rótulo |
| --- | --- | --- |
| `total` | el universo | «Resultados registrados hoy (de llamadas de cualquier día)» |
| `al_colgar` | `enlaces.via = 'al_colgar'` | «al colgar» |
| `desde_pestana` | `via = 'pestana'` | «desde «Llamadas del celular»» |
| `a_mano` | `via = 'manual'` | «unidas a mano» |

Difiere de «Qué pasó hoy», que ordena por `enlaces.actualizado_en` (cuándo nació o se movió el enlace): los tres casos
en que no coinciden —intención cumplida tras medianoche, enlace manual y enlace movido— van al oráculo (O8).
**Porcentaje permitido:** `al_colgar / total`, siempre con el conteo al lado.

### 5.3 Estado de ahora (sin reloj de día)

| Cifra | Predicado |
| --- | --- |
| `pendientes.total` | eventos `requiere_resultado` sin enlace vigente, lead abierto y contactable (como 5.1), de cualquier fecha dentro de la retención (30 días: la purga los retira) |
| `pendientes.de_hoy` / `pendientes.anteriores` | los de arriba, partidos por el momento de la llamada |
| `pendientes.mas_antigua_dias` | `floor(extract(epoch from p_ahora - momento) / 86400)` de la más antigua; `null` si no hay |
| `pendientes.deshechas_sin_corregir` | eventos con enlace a una actividad deshecha, lead abierto y contactable, de cualquier fecha (no caducan) |
| `por_revisar.total` | eventos `por_revisar` (ambiguas, de la bolsa, reutilizables) |

**Retención (D5):** lo que **no** tiene enlace (sin resultado, por revisar) lo retira la purga a los 30 días
(`dias_retencion_sin_resolver`); las descartadas, a sus días propios; lo que **tiene** enlace (registradas, incluidas
las deshechas) **se conserva sin límite**. Por eso `pendientes.total` abarca como mucho 30 días y
`pendientes.deshechas_sin_corregir` no tiene tope: se muestran separados.

«Sin resultado» usa la atención **cruda**, no `llamada_celular_atencion_efectiva` (depende de quién mira): así
supervisor y gerencia ven la misma cifra del mismo analista.

### 5.4 Celulares y «sin dato»

- `celulares[]` del analista: de `private.celulares_salud_listar(p_actor)` (`20261006150254:33`), que ya trae
  `etiqueta`, `estado_latido` (`al_dia` / `sin_latido` con 7 h, A6 / `nunca`), `horas_sin_latido` (entero),
  `reloj_desfasado`, `eventos_en_cola` y `version_macro`. Se filtra por `analista_id` del ámbito.
  **Ojo:** esa función filtra con `vendedor_ids_visibles(p_actor)`; para gerencia con `p_supervisor_id`, la puerta
  vuelve a filtrar por el equipo.
- `sin_dato` (booleano por analista): `llamadas_hoy.total = 0` **y** ningún celular vigente con
  `estado_latido = 'al_dia'`. La pantalla muestra **«—»**, no «0». Un celular al día con 0 llamadas muestra «0»
  (sabemos que vive). → decisión **D1**. Sin celular vigente: `sin_dato = true` y `celulares = []`.

### 5.5 Equipos y totales

`equipos[]` y `totales` suman las cubetas de 5.1, 5.2 y 5.3 de sus analistas, más `celulares_vigentes`,
`celulares_sin_latido` (estado `sin_latido` o `nunca`) y `analistas_sin_dato`. Los porcentajes **no** se suman:
se recalculan de las sumas.

## 6. Forma del jsonb

```
{
  "dia": "2026-10-10", "generado_en": "…Z", "alcance": "operacion" | "equipo",
  "rotulos": { "llamadas_hoy": "Llamadas de hoy (por la hora de la llamada)",
               "resultados_hoy": "Resultados registrados hoy (de llamadas de cualquier día)",
               "pendientes": "Sin resultado ahora (hasta 30 días)" },
  "totales": { "llamadas_hoy": {…5.1…}, "resultados_hoy": {…5.2…}, "pendientes": {…5.3…}, "por_revisar": n,
               "celulares_vigentes": n, "celulares_sin_latido": n, "analistas_sin_dato": n },
  "equipos": [ { "supervisor_id": uuid|null, "supervisor_nombre": "…", "analistas": n, …mismas sumas… } ],
  "analistas": [ { "analista_id": uuid, "nombre": "…", "supervisor_id": uuid|null, "sin_dato": bool,
                   "llamadas_hoy": {…}, "resultados_hoy": {…}, "pendientes": {…}, "por_revisar": n,
                   "celulares": [ { "etiqueta": "C1", "estado_latido": "al_dia", "horas_sin_latido": 2,
                                    "reloj_desfasado": false, "eventos_en_cola": 0, "version_macro": "llamadas-v3" } ] } ],
  "su_celular": [ …igual que celulares[], solo para el supervisor (A7)… ] | null
}
```

Los `rotulos` viajan en el jsonb para que pantalla y base digan lo mismo (condición de Miguel: cada cifra dice qué
fecha usa). **Sin** `numero`, `lead_id`, `evento_id`, nombres de leads ni horas de latido: el oráculo lo verifica
con un recorrido del jsonb (O14).

## 7. Rendimiento y privacidad

- Volumen: la tabla **crece sin tope** con las registradas, porque la purga conserva todo lo enlazado
  (`20261005143843:846–886`; el oráculo de la corrección conserva registradas de 100 días, deshechas incluidas). Solo
  lo sin enlace se retira a los 30 días. Con C1 son ~20 registradas al día; con tres celulares, del orden de 60/día
  → ~20.000 filas al año, más las pendientes de 30 días. No es un límite: es una estimación para el EXPLAIN.
- Cómo acota la consulta: la cohorte de llamadas de hoy filtra primero por `recibido_en >= v_desde − 1 día` (una
  llamada ocurrida hoy no pudo recibirse antes de ayer: la ingesta rechaza más de un día de adelanto del reloj) y por
  `analista_id` del ámbito, con el índice `(analista_id, atencion, recibido_en)`; el momento con `ocurrio_en` se
  evalúa después, sobre ese subconjunto. Los pendientes acotan por `atencion` y `recibido_en >= p_ahora − 30 días`.
  Las deshechas sin corregir se buscan desde `llamadas_celular_enlaces` (`evento_id` único) hacia `crm.actividades`.
  Índices que ya existen: `(analista_id, atencion, recibido_en)`, `(lead_id, recibido_en)`, `(recibido_en)` en
  eventos; `evento_id` único y `(lead_id)` en enlaces.
  **Objetivo: < 100 ms en `EXPLAIN ANALYZE` sobre el banco de Miguel con historial acumulado (los 100 días del oráculo
  de la corrección como mínimo); sin índice nuevo salvo que ese EXPLAIN lo pida.**
- Una sola pasada por eventos del ámbito y de la ventana acotada, agregando en SQL; sin `llamada_celular_visible`
  por fila.
- Bitácora: la puerta no escribe nada. La fuga del latido ya está cerrada (undécima y macro del 06/10).

## 8. Oráculos (banco reducido) y gate

**Banco reducido** (`supabase/tests/llamadas-celular/base.sql`, actores: gerencia `g1`, supervisor `b1`, vendedores
`a1`–`a3`). Falta un **doble** de `private.gestion_diaria_pulso_roster()` (vendedores activos con su `supervisor_id`
de `crm.equipo`), declarado en `base.sql` como la v4. Archivo nuevo `oraculo-operacion-hoy.sql`, con `p_ahora` fijo
y el patrón «foto antes → acción → foto después» de los demás oráculos.

| # | Caso | Qué debe pasar |
| --- | --- | --- |
| O1 | Roles | `a1` (vendedor), directorio y anon → `42501`; `b1` y `g1` → jsonb |
| O2 | `p_supervisor_id` | `b1` con su id = nulo; `b1` con otro id → `42501`; `g1` con un vendedor como id → `22023` |
| O3 | Aislamiento | el equipo de `b1` no incluye a un vendedor de otro supervisor; `g1` nulo los incluye a todos |
| O4 | Ingesta de hoy | una saliente identificada de `a1` → `llamadas_hoy.total +1`, `sin_resultado +1`, `pendientes.de_hoy +1` |
| O5 | Registrar al colgar | v5 con el id → `con_resultado +1`, `sin_resultado −1`, `resultados_hoy.total +1`, `al_colgar +1` |
| O6 | Borde del día (Lima) | evento con `ocurrio_en` = 23:59 Lima de ayer y `recibido_en` hoy → cuenta en **ayer**; uno de 00:00 hoy → hoy |
| O7 | Llamada de ayer resuelta hoy | está en `resultados_hoy` y **no** en `llamadas_hoy`; `pendientes.anteriores −1` |
| O8 | Los tres casos de A2 | intención cumplida tras medianoche, enlace manual, enlace movido: `resultados_hoy` sigue la **fecha de la actividad**, no la del enlace |
| O9 | Deshacer y corregir, con la distribución completa | Antes: `con_resultado = 1`, las demás 0, `total = 1`. Tras **Deshacer**: `deshechas_sin_corregir = 1`, las demás 0, `total = 1` (sigue `registrado` con su enlace) y `pendientes.deshechas_sin_corregir = 1`. Tras **«Registrar el corregido»** (séptima, el enlace se mueve): `con_resultado = 1`, `deshechas_sin_corregir = 0`, sin duplicar. Variante: deshecha y después el lead se convierte → `cerradas_despues = 1`, `total = 1`. Variante: deshecha de hace 40 días → sigue en `pendientes.deshechas_sin_corregir` (no la purga) |
| O10 | Por revisar | una ambigua → `por_revisar +1` y **no** toca `sin_resultado` |
| O11 | Lead de baja (A4) y lead convertido después (A5) | el primero desaparece de todas las cubetas; el segundo pasa de `sin_resultado` a `cerradas_despues` |
| O12 | Entrante insertada a mano (como dueño) | no cuenta en nada; `requiere_devolucion` = 0 siempre |
| O13 | Latidos, con los bordes del umbral | `al_dia` con latido hace 1 h, **6 h 30 min** y **7 h 00 min exactas** (`> 7 h` es estricto en `20261006150254:45`); `sin_latido` con **7 h 00 min 01 s** y 8 h; `nunca` sin latido. `sin_dato` solo con 0 llamadas y sin latido al día; con latido al día y 0 llamadas → `sin_dato = false`. Los casos de 6 h 30 y 7 h 00 son los que matan al mutante de 6 h |
| O14 | Privacidad | recorrido recursivo del jsonb: ninguna clave `numero`, `lead_id`, `evento_id`, `ultimo_latido_en`, ningún valor que cumpla `^\+?[0-9]{7,}$` |
| O15 | Cierre de cubetas | en cada analista, `total` = suma de las **seis** cubetas; equipos y totales = sumas de sus analistas |
| O16 | Reloj corrido (D2) | `ocurrio_en` 20 min por delante de `recibido_en` → el momento es `recibido_en` |
| O17 | Supervisores anidados (D4) | `S1` supervisa a `S2`, que supervisa al vendedor `V` (banco: alta de `S2` bajo `b1`). Gerencia (roster: `V` bajo `S2`), `S1` (subárbol: incluye a `V`) y `S2` reciben **las mismas cifras de `V`**, cubeta por cubeta; solo cambian los totales de equipo según quién lo compone. El mutante «contar según quién pregunta» (atención efectiva o `llamada_celular_visible`) lo mata |

**Mutantes** (cada uno debe hacer fallar al menos un caso): quitar el filtro `direccion` (O12); quitar `l.activo`
(O11); usar `enlaces.actualizado_en` en vez de `actividades.creado_en` (O8); contar deshechas como `con_resultado`
o dejarlas fuera de toda cubeta (O9, O15); usar `llamada_celular_visible` o la atención efectiva (O3, O17); omitir el
`42501` del supervisor ajeno (O2); umbral de 6 h en vez de 7 (O13); ventana en UTC (O6); dividir cohortes distintas
(O15 con un porcentaje de más); acotar `recibido_en` desde hoy en vez de desde ayer (O6).

**Gate (`test-rls.mjs`, bloque nuevo con bandera `CRM_RLS_EXIGE_LLAMADAS_F4E`, como `_F4B` en `:18224`):** roles;
aislamiento (`sup2` no ve a `vend1`); cifras antes y después de ingerir, registrar y descartar; claves de equipo
iguales a las de `gestion_diaria_pulso_fn`; `EXPLAIN` registrado.

## 9. Plan corto de la migración (para el OK de Miguel)

1. **Una migración:** `AAAAMMDDHHMMSS_crm_llamadas_celular_operacion_hoy.sql`, orden: núcleo → puerta → `revoke`/`grant`
   → `comment on`. Sin tablas, sin RLS nuevo, sin índices (salvo lo que diga el EXPLAIN, que se decide antes de
   aplicar).
2. **Registrador y reversa** en `supabase/scripts/llamadas-celular/`: `registrar-operacion-hoy.sql` (veredicto y huella
   del catálogo, como los demás) y `reversa-operacion-hoy.sql` (`drop function` de puerta y núcleo; no hay datos que
   conservar).
3. **Ledger** `MIGRACIONES.md` y `COMMENT ON` en las dos funciones.
4. **Oráculo y mutantes** (sección 8) en `npm run test:llamadas:local`; bloque del gate; `auditor-rls`; Codex r1
   (**LEVEL 3**: función `definer` con control de rol).
5. Banco de Miguel → `EXPLAIN` → aplicar → `npm run gen:types`.
6. Pantalla (PR aparte): tercera pestaña en `screens/gestion-diaria/gerencia.tsx` (`PESTANAS`), tabla sobre el molde
   de `tabla-equipos-gerencia.tsx`, bloque «Su celular» en `panel-analista-supervisor.tsx`, consulta sobre el molde de
   `data/gestion-diaria-pulso-queries.ts` (refresco 60 s), demo, E2E en Docker, `revisor-a11y`, `gate:realidad`.
   Prototipo aprobado: el de F4-e del 06/10.

## 10. Decisiones que faltan (Miguel)

| # | Pregunta | Recomendación |
| --- | --- | --- |
| D1 | «Sin dato» = 0 llamadas **y** sin latido al día. ¿Un celular al día con 0 llamadas muestra «0»? | Sí: el latido prueba que vive |
| D2 | Reloj corrido: si `ocurrio_en` va > 5 min por delante de `recibido_en`, ¿se cuenta por `recibido_en`? | Sí, con el mismo umbral de `reloj_desfasado` |
| D3 | Dos cohortes (5.1 por llamada, 5.2 por resultado) para cumplir «numerador y denominador de la misma cohorte» | Sí; es la única forma de dar un % de «con resultado» honesto |
| D4 | **Resuelta como regla del contrato (10/10, pedido de Miguel):** las cifras por analista son idénticas para todos los que lo incluyen (§3, O17); la composición del equipo (roster para gerencia, subárbol para el supervisor) es técnica y los totales de equipo son la suma de los miembros listados | — |
| D5 | Retención: lo sin enlace caduca a los 30 días (pendientes y por revisar: ventana visible = 30 días); lo enlazado, registradas y deshechas, se conserva sin límite, y las «deshechas sin corregir» se muestran aparte sin tope (§5.3) | Sí; F6 decidirá si se guardan agregados (F6.3.2) |

## 11. Qué sigue

1. Revisión del 10/10 (#249): D1, D2 y D3 aprobadas; D4 resuelta como regla; D5 precisada. Falta el OK a la sección 9
   → migración + oráculo + mutantes (Claude) → su banco y EXPLAIN con historial acumulado (Miguel).
2. Pantalla sobre la puerta (PR aparte) → publicación → aceptación en C1 con los dos roles.
3. F6 amplía esta misma puerta (histórico, retrasos, cobertura, entrantes con la #14).

## En llano

Este documento dice, número por número, qué va a contar la vista de supervisores y gerencia y con qué reloj: las
llamadas de hoy se cuentan por la hora de la llamada, los resultados de hoy por la hora en que se registraron, y lo
pendiente es una foto de ahora. También dice quién puede verla (gerencia todo, cada supervisor su equipo), qué nunca
sale (números, leads, horas exactas) y qué pruebas demuestran cada cifra. Una llamada cuyo resultado se deshizo cuenta
aparte, como «deshecha sin corregir», hasta que se registre el corregido. Miguel ya decidió las definiciones; falta su
OK al plan de la consulta para escribirla en la base.
