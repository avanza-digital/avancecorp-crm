# Plan v2: una venta eliminada y vuelta a registrar conserva la conversión

**Estado: PENDIENTE DE APROBACIÓN de Miguel (16/10/2026).** Nada está implementado ni aplicado. Único archivo tocado: este documento.
**v2 (16/10, tarde):** incorpora los 5 hallazgos de la revisión (sección 8). Cambian R1, R2, R3, el script de datos y la secuencia de publicación.

## 0. Plan por fases

Cada fase termina en una puerta: si no está en verde, la siguiente no empieza. Las secciones 1 a 8 son el detalle.

| Fase | Quién | Qué se hace | Entregable | Puerta de salida |
|---|---|---|---|---|
| **0 · Decidir y medir** | Miguel y yo | Las 6 confirmaciones (sección 7); medir en producción (solo lectura) huellas vivas y hechos de los 2 casos; montar el banco Docker a paridad. | Plan aprobado, banco listo. | **Plan aprobado** por Miguel. |
| **1 · Servidor** (R1 a R4) | Yo | Migración única (eliminar ya no anula, reemplazo automático, rehabilitación con revocación, lectores parcheados, puertas, barrido), reversa fail-closed, registrador; `pruebas.sql` en ROLLBACK, mutantes, carrera; regresión de eliminar inversión y mes sellado; `auditor-rls`. | Migración y scripts en la rama `crm/conversion-reemplazo-20261016`. | **Banco en verde** y `auditor-rls` sin P0/P1. |
| **2 · Recuperar los 2 casos** | Yo | Script de datos de lista cerrada (2 rehabilitaciones, categoría de 2026-01-001621 a `nuevo`, enlace y acreditación), ensayado en banco con los hechos copiados de producción. | `recuperar-16-10.sql` con comprobación. | **Casos OK en banco**: Jurado y Gaspar cuentan; las 4 pruebas siguen anuladas. |
| **3 · Pantalla** (R5) | Yo | Textos de eliminar y Cartera, categoría fija con fecha límite, chip en la ficha, reintento de vínculo; `gen:types`; vitest; E2E en Docker. | App en la misma rama. | **`npm run check` y E2E en verde** (Docker apagado = no se avanza). |
| **4 · Revisión y publicación** | Yo ejecuto; Miguel aprueba PR y despliegue | Review de Codex (LEVEL 3) y conciliación; branch de Supabase con migración y script; advisors; `main` = `avancecorp/main`; preflight; publicar; push el mismo día; comprobación en producción; ledger y vault. | Producción con la regla nueva y los 2 casos recuperados. | **Producción verificada**. |

## 1. El problema

Un analista registra una venta con la moneda equivocada. Gerencia la elimina con «Eliminar inversión» y registra el contrato correcto. La conversión del analista desaparece para siempre: el lead sigue contando en el divisor (llegada) y el numerador queda en 0. La tasa del analista baja.

## 2. Causa (verificada en código y en producción el 16/10/2026)

1. **«Eliminar inversión» anula antes de borrar.** Por la decisión D2 del 05/10, si el contrato eliminado es la conversión del lead, `crm.eliminar_inversion_fn` llama primero a `crm.anular_cierre_avance` y después borra (`supabase/migrations/20261005200945_crm_eliminar_inversion.sql:794-806`).
2. **La anulación es de una sola dirección.** Inserta una fila en `crm.cierres_avance_anulados` (UNIQUE por lead, append-only) y deja copia en `crm.inversiones_eliminadas` con `conversion_anulada = true` (inmutable). Nada la revierte. `private.cierre_anulado(lead)` devuelve `true` para siempre (`20261005200945:315-335`). La puerta de anular rechaza a cualquier lead que ya tenga fila: «Ese cierre ya estaba anulado» (cuerpo vivo en `20260908211349:1252-1256`, parcheado por `20261009210000`).
3. **Todos los lectores respetan esa bandera.** Núcleo de cierres con aporte 0 (`20261006042144:188-210`), sello mensual (`20261012220959:187,210`), estado del lead «anulada» (`20260927073637:987`).
4. **El contrato nuevo no se enlaza al lead.** La llave foránea deja `leads.contrato_id` en NULL al borrar. El contrato nuevo nace por «Nueva inversión» de Cartera (persona ya convertida, sin lead de origen) y ningún trigger lo acredita: la acreditación sigue apuntando al contrato borrado → `fuente_retirada`.

### Los dos casos reales (horas en Lima)

| Lead | Analista | Contrato borrado | Eliminado | Contrato nuevo | Traba |
|---|---|---|---|---|---|
| `043ed717…` | Vladimir Jurado | 2026-01-001626, PEN 5000, cc 16/10 | 16/10 13:56 | 2026-01-001626, PEN 5000, `nuevo`, 16/10 13:57 | ninguna |
| `24eaface…` | Adelayda Gaspar | 2026-01-001621, USD 2000, cc 15/10 | 15/10 19:21 | 2026-01-001621, PEN 2000, **`upgrade`**, 15/10 19:32 | registrado como upgrade: hay que corregir la categoría |

Octubre no está sellado; plazo de acreditación de octubre: 11/11/2026 00:00 Lima. Las otras 4 anulaciones desde septiembre son ventas de prueba eliminadas a propósito: siguen anuladas.

## 3. Decisión de Miguel que recoge este plan

«Si se vuelve a registrar un contrato, simplemente le cuente a la conversión.» Comportamiento permanente del sistema, sin pasos manuales.

**Límite explícito (hallazgo 2):** el reemplazo cuenta si el contrato nuevo se registra **dentro del plazo de acreditación del mes de la venta** (hasta el día 10 del mes siguiente), igual que cualquier venta. Es la política vigente de conversión: la acreditación toma como reloj el momento del vínculo nuevo (`20260927073637:363`). Después del plazo, el reemplazo queda `fuera_de_plazo` como una venta tardía, aunque el mes siga abierto. Si el contrato nuevo lleva otra fecha comercial, la conversión se acredita en ese mes. La pantalla lo dirá con fecha límite. No se cambia el escritor único de acreditaciones.

## 4. Regla nueva (lo que cambia)

**R1 · Eliminar ya no anula.** Si la inversión eliminada es la conversión del lead, la puerta deja de llamar a `anular_cierre_avance`. La copia queda con `es_conversion = true, conversion_anulada = false`. La acreditación pasa sola a `fuente_retirada` (aporte 0, reversible). «Anular el cierre» (solo gerencia) sigue siendo la única manera de anular a propósito; la sanción ATR-4 ya no se dispara por una eliminación. Cooperativas (cierre externo) quedan como hoy.

**R2 · Reemplazo automático.** Trigger en `public.contratos` (al crear un contrato y al corregir su categoría) → núcleo `private.conversion_reemplazar_fuente(contrato)`:
- Candidato: el lead convertido de esa persona (`contratos.cliente_id = leads.perfil_id`) cuya acreditación apunte a un contrato que ya no existe (copia en `inversiones_eliminadas` con `es_conversion`), con mes no sellado y sin anulación vigente.
- Elegible: categoría `nuevo`, no demo, sin operación de cartera, no acreditado a otro lead, sin otra captación acreditada de la misma identidad, dentro del plazo (sección 3).
- Hace, en una subtransacción (todo o nada): toma los candados **en el mismo orden que el escritor** (candado consultivo del contrato → `public.contratos` FOR UPDATE → `crm.leads` FOR UPDATE → cerrojo del mes), enlaza `leads.contrato_id` con la válvula privilegiada, deja que el trigger existente re-acredite, marca la inversión nueva como primera conversión y escribe la actividad `reemplazo_conversion`.
- **Nunca rompe el alta** del contrato. Resultado en tres clases (hallazgo 3):
  - *inelegible* (regla de negocio): actividad informativa «reemplazo no aplicado: motivo», sin reintento; una corrección de categoría posterior vuelve a disparar el trigger;
  - *conflicto transitorio* (SQLSTATE 40001, 40P01, 55P03, PT409 «vuelve a intentar»): se revierte la subtransacción, se registra el intento en `crm.conversion_reemplazos_intentos` (append-only: contrato, lead, sqlstate, mensaje, instante) y el vínculo queda **pendiente de reintento**;
  - *éxito*: actividad y vínculo.
- **Reintento** de los pendientes: puerta idempotente `crm.conversion_reemplazar_fuente_fn(p_contrato_id)` (gerencia o el analista dueño del contrato), expuesta en la ficha solo mientras haya un intento pendiente («Reintentar vínculo»); y barrido automático cada 15 minutos con `pg_cron` (confirmado en producción el 16/10: extensión 1.6.4 activa con 12 trabajos; el barrido se registra en la migración y se da de baja en la reversa).

**R3 · Rehabilitar las anulaciones ya hechas (los 2 casos) sin perder la anulación explícita.** Tabla append-only `crm.conversion_rehabilitaciones` (una fila por lead: anulación, copia eliminada, motivo, autor, fecha) con **una sola transición permitida**: `revocada_en / revocada_por / revocacion_motivo` (de vigente a revocada, nunca al revés; trigger que solo admite ese cambio). Definición única `private.anulacion_avance_vigente(lead)`: hay fila en anulados (o copia con `conversion_anulada`) **y** no hay rehabilitación vigente. `private.cierre_anulado` la usa.
- **Anular otra vez (hallazgo 1):** `crm.anular_cierre_avance` se parchea **por ancla** en la rama «Ese cierre ya estaba anulado»: si la anulación existente está rehabilitada, en vez de rechazar **revoca la rehabilitación** (motivo nuevo, actividad `anulacion_cierre_avance` con `reanulacion = true`) y devuelve el mismo acuse. No se toca ni el UNIQUE ni la regla de mes sellado (`private.mes_sellado_de_venta` sigue delante). Ciclo cubierto en pruebas: rehabilitar → reemplazo automático → anular otra vez → ningún reemplazo más (anulación vigente).
- Sin botón de rehabilitar: solo el script de datos de lista cerrada escribe la rehabilitación.

**R4 · Lectores que miran la tabla de anulados directo.** `crm.cierres_estado_fn` y `crm.altas_nuevas_por_analista_fn` pasan a usar `private.anulacion_avance_vigente` (parche por ancla). Mensaje de «anulada» en el estado del lead: quitar la referencia al ajuste (no existe desde el 09/10).

**R5 · Pantalla.**
- Diálogo «Eliminar inversión» y toast de Cartera: «si registras el contrato correcto a la misma persona antes del <fecha límite>, la conversión se conserva»; quitar «la conversión quedó anulada» y «el ajuste pasa al mes vivo».
- «Nueva inversión»: si la persona tiene una venta eliminada pendiente de reemplazo, categoría fija en `nuevo` con aviso y fecha límite. Lectura `crm.conversion_reemplazo_pendiente_fn(persona)` → `{pendiente, contrato_eliminado, analista, periodo, plazo_hasta, intento_pendiente}`.
- Ficha del lead: chip «Conversión sin fuente: venta eliminada» mientras esté pendiente; «Reintentar vínculo» solo si hay intento pendiente.

## 5. Archivos

**Migración** `supabase/migrations/<ts>_crm_conversion_reemplazo_automatico.sql` (skill `nueva-migracion`; candado de sesión; orden preflight → tablas → RLS → núcleo → trigger → parches por ancla → puertas → permisos → comentarios → postflight).
- Preflight fail-closed con huellas vivas medidas en producción el 16/10: `private.cierre_anulado` df71c2b1…, `crm.eliminar_inversion_fn` 9abd6581…, `private.registrar_inversion_eliminada_avance` 71447936… (hoy exige anulación si es conversión: se relaja), `crm.cierres_estado_fn` f543c809…, `crm.altas_nuevas_por_analista_fn` b421dfb1…, `private.conversion_estado_lead_v1` cd5eb069…, `crm.anular_cierre_avance` 03b67308… (parche por ancla), `private.leads_before_update` 4ae909f2… (no se toca).
- NO se tocan: `crm.contrato_eliminar_auditado`, `private.conversion_acreditar_fuente`, `private.conversion_episodios`, `private.conversion_cierres`, `private.mes_sellado_de_venta`, piezas F7/F6.a.
- Tablas nuevas: `crm.conversion_rehabilitaciones`, `crm.conversion_reemplazos_intentos`. Núcleos nuevos: `private.anulacion_avance_vigente(uuid)`, `private.conversion_reemplazar_fuente(uuid)`, `private.conversion_reemplazo_pendiente(uuid)`, trigger-fn `private.contratos_conversion_reemplazo_trg()`. Puertas: `crm.conversion_reemplazar_fuente_fn(uuid)`, `crm.conversion_reemplazo_pendiente_fn(uuid)`.
- ⚠️ El trigger va sobre `public.contratos`: requiere OK explícito de Miguel anotado en el ledger (como el 08/10).
- Reversa fail-closed (devuelve `anular_cierre_avance` a 03b67308… y el resto a sus huellas), `comprobar-tras-aplicar.sql` y registrador en `supabase/scripts/conversion-reemplazo/`.

**Script de datos** `supabase/scripts/conversion-reemplazo/recuperar-16-10.sql` (READ COMMITTED, aparte de la migración). Preflight **por UUID completo y hechos exactos, zona `America/Lima` explícita** (hallazgo 4): las 6 filas de `cierres_avance_anulados` por id; las 2 a rehabilitar por id de anulación, id de copia, id de contrato nuevo y número de contrato; `anulado_en` exacto de cada una; acreditaciones en `fuente_retirada`; octubre sin sello y `now()` antes del plazo. Pasos: (1) 2 rehabilitaciones; (2) 2026-01-001621: categoría `upgrade` → `nuevo` con `private.fijar_categoria_contrato(…, 'puerta', uid de Miguel)` — **pendiente de que Miguel confirme que es venta nueva**; (3) `private.conversion_reemplazar_fuente` para 2026-01-001626 y 2026-01-001621; (4) verificación: episodios de octubre con cierre y aporte 1 para Jurado y Gaspar, sin chip de anulado, altas contadas, las 4 ventas de prueba con `cierre_anulado = true`.

**App** (`app/src`): `data/crm-api.ts`, `data/crm-queries.ts`, `lib/conversion-reemplazo.ts`, `components/app/inversion-eliminar.tsx`, `screens/cartera-inversionistas.tsx`, `components/app/inversion-nueva.tsx`, `components/app/lead-drawer.tsx`, `lib/cierre-estado.ts` y sus tests vitest; E2E nuevo `e2e/conversion-reemplazo.spec.ts`. `npm run gen:types`.

**Documentación**: `MIGRACIONES.md` (entrada; D2 sustituida; OK para `public.contratos`); nota del vault «Conversión se conserva al re-registrar una venta eliminada (2026-10-16)» + línea en `Inicio.md`.

## 6. Verificación

1. **Banco Docker con ROLLBACK** (`pruebas.sql`): reproducción del defecto; eliminar conversión → sin anulación, `fuente_retirada`, aporte 0; contrato `nuevo` → enlace automático, `acreditada`, mismo analista y episodio, aporte 1, altas contadas; `upgrade` → no enlaza y al corregir categoría sí; anulada a propósito → no enlaza; mes sellado → no enlaza y la foto se conserva; **fuera de plazo → no enlaza y lo dice**; demo / cartera / otro lead / identidad duplicada → no enlaza y el alta NO falla; **conflicto transitorio simulado → intento registrado, nada parcial, reintento por la puerta enlaza**; rehabilitación de lista cerrada; **ciclo rehabilitar → reemplazar → anular otra vez → sin reemplazo**; ventas de prueba intactas; candados append-only. `mutantes.sh` y `carrera.sh` (alta vs sello; alta vs eliminar; alta vs anular).
2. **Regresión**: `test-eliminar-inversion.sql` (24 bloques; los que asumen anulación se ajustan), 16 mutantes, `anular-venta-mes-sellado/pruebas.sql` (su reversa fija 03b67308…: se documenta la huella nueva), `test-rls.mjs` (bloque nuevo), `gate:analitica`.
3. **App**: `npm run check` + vitest; **E2E locales en Docker** (`npm run test:e2e:docker -- e2e/conversion-reemplazo.spec.ts` y los specs de cartera e inversiones); Docker apagado → `NOT RUN`, no se publica.
4. **Ciclo LEVEL 3 y publicación** (hallazgo 5): `auditor-rls` → review de Codex (SQL y evidencia transcritos) → branch de Supabase → migración + script de datos → advisors → `gen:types` → **`main` y `avancecorp/main` en el mismo commit ANTES de construir** → preflight del despliegue → publicar → push el mismo día.
5. **Comprobación final en producción (solo lectura)**: métricas de octubre de Jurado y Gaspar con la conversión contando; `cierre_anulado` sigue `true` en los 4 leads de prueba.

## 7. Lo que Miguel debe confirmar antes de empezar

1. Aprobar este plan v2.
2. El contrato 2026-01-001621 de Adelayda Gaspar es una venta nueva (se corrige de `upgrade` a `nuevo`).
3. Eliminar una conversión ya no la anula ni sanciona (ATR-4); anular sigue siendo acto explícito de gerencia y vuelve a estar disponible tras una rehabilitación.
4. OK para el trigger sobre `public.contratos`.
5. Límite de plazo (sección 3): el reemplazo cuenta si se registra hasta el día 10 del mes siguiente.
6. Cooperativas quedan como hoy en esta versión.

## 8. Respuesta a la revisión (CHANGES_REQUESTED, 16/10)

| # | Hallazgo | Veredicto | Cómo queda |
|---|---|---|---|
| 1 | P1 · tras rehabilitar no se puede volver a anular | **Aceptado** (cuerpo vivo: `20260908211349:1252-1256`) | R3: rehabilitación con revocación única; `anular_cierre_avance` parcheado por ancla; ciclo probado. |
| 2 | P1 · «sin ventana» no conserva la conversión | **Aceptado** (`20260927073637:363`) | Sección 3: promesa limitada al plazo vigente; no se toca el escritor; la pantalla muestra la fecha límite. |
| 3 | P2 · concurrencia y reintentos | **Aceptado** | R2: candados en el orden del escritor, subtransacción todo o nada, clases inelegible / transitorio / éxito, tabla de intentos, puerta de reintento y barrido `pg_cron` si existe. |
| 4 | P2 · fechas UTC vs Lima en el preflight | **Aceptado** (Adelayda: 15/10 19:21 Lima) | Script por UUID y hechos exactos con zona explícita. |
| 5 | P2 · E2E en Docker y paridad `main` antes de publicar | **Aceptado** | Sección 6, puntos 3 y 4. |
