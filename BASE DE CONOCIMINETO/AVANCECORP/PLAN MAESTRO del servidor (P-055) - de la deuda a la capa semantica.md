# PLAN MAESTRO del servidor (P-055) — de la deuda a la capa semántica

Código estable para retomar: **`RETOMAR-SERVIDOR`**. Escrito el 2026-08-28.

Este documento **reemplaza** a [[Plan de saneamiento del servidor (P-053) - implementacion por tandas]] y a [[Capa semantica del servidor - plan por nucleos (episodios)]] como plan vigente: ambos siguen valiendo como detalle técnico, pero la secuencia que manda es esta. Inventario de origen: [[Auditoria servidor Supabase - duplicacion y deuda (2026-08-28)]] (1 ROTO · 12 DUPLICADO · 8 COSMÉTICO + 3 colaterales de edges).

Producido con tres arquitecturas independientes (lente de riesgo, lente de cadencia de Miguel, lente de estado final) y un crítico de cobertura que encontró 13 hallazgos huérfanos y 11 errores de secuencia; las tres afirmaciones nuevas más pesadas del crítico fueron **verificadas contra producción y disco** antes de escribir esto (ver «Correcciones» al final).

---

## Cómo leer este plan

- **14 etapas** (E0–E13). Cada una: objetivo, entregables, si es **autónoma** o **espera a Miguel**, riesgo, y criterio de cierre **verificable** (una consulta o un procedimiento nombrado, nunca «quedó bien»).
- **Ninguna etapa de construcción espera una respuesta.** Las decisiones viajan en **mesas** de máximo 5 preguntas con su número al lado, entregadas antes de la etapa que las consume. Si una mesa lleva 2 semanas sin respuesta, se re-secuencia el plan en vez de esperar.
- **El tablero** (al final) es la única medida de avance: 20 contadores que solo pueden bajar. El plan termina cuando el tablero llega a su meta o cada excepción está firmada.

---

## Reglas invariantes (valen para TODAS las etapas)

1. **Nada que esté en producción se borra sin OK de Miguel.** Todo retiro: re-medir → **REVOKE** (reversible) → observar → **DROP**.
2. **Todo cambio nace con su rollback escrito ANTES de publicarse**: guion re-GRANT inverso probado para cada REVOKE, cuerpo anterior guardado *dentro* de la propia migración para cada función migrada, `CREATE INDEX` inverso para cada drop.
3. **Nunca dos modos de fallo nuevos en la misma semana.** Y dos ventanas de congelamiento con fecha: **08–12/09** y **05–12/10** (sellados mensuales) — en ellas solo trabajo de papel.
4. **Toda paridad se mide en la MISMA transacción** (md5 del jsonb agregado). Dos lecturas separadas ya produjeron un falso ROTO el 27/08.
5. **La paridad del servidor no basta:** cada tanda cierra con inventario del front (React del CRM + vanilla del portal) según el protocolo de E0, no con un «grep limpio» impreciso.
6. **Release del front solo si la capa 3 cambió de forma.** Paridad byte a byte ⇒ el bundle no cambia ⇒ no se publica: menos ventanas de riesgo.
7. **Peaje de toda migración:** rama de banco (receta de [[banco-branch-replay-manual]]) → `auditor-rls` → `npm run test:rls` (gate 1175) → **`npm run gate:realidad`** (un cambio ya pasó el gate entero sin hacer nada en producción porque los tests montan el mundo del fixture).
8. **Prohibido probar EXECUTE-denegado en producción:** `select fn()` sin EXECUTE tumba el backend en la imagen 17.6.1.105. Solo en rama.
9. **Excepción a la regla del LEEME:** toda etapa que toque `public` lo declara explícitamente y pide OK, citando el precedente de `recordatorios_disponibilidad` (ver E0).

---

## El contrato de la capa semántica

**Las tres reglas de capas:**
1. **El núcleo no autoriza** — recibe la visibilidad ya resuelta, devuelve filas-hecho. En `private`, sin grants a la API.
2. **La ventana autoriza UNA vez** — un despachador por métrica resuelve actor, valida rol y calcula visibilidad. Nada llega al núcleo sin pasar por ahí.
3. **La pantalla no calcula** — capa 3 solo suma, filtra y da forma.

**La regla de diseño del hecho (la pieza que desbloquea todo el plan):**
> Toda dimensión con decisión de negocio abierta **viaja como columna dentro del hecho**, no como criterio aplicado adentro. El hecho de capital lleva `vendedor_lead_id` **Y** `asesor_perfil_id` en la misma fila; pipeline y AUM son **valores de `tipo`**, no filas ausentes. La elección de Miguel se aplica arriba (en la ventana o la pantalla).

Consecuencia: la decisión de S/ 3,76 M vs S/ 113 K pasa a ser un cambio de **números**, no de **forma** — ninguna etapa de construcción queda bloqueada esperando, y una respuesta tardía no obliga a reconstruir nada. Los hechos usan **tipos base**; los dominios viven en las tablas.

---

## E0 · Cimientos: tablero, trinquete, reglas escritas y desbloqueos pedidos el día 1
**Autónoma · riesgo nulo (cero escrituras a la base) · 1–2 sesiones · ARRANCA YA**

El medidor y las reglas se fijan **una sola vez, al principio**: construir un trinquete de 4 contadores y querer después el de 20 significa reescribir el test y re-congelar líneas base.

- **Nota-tablero única** con los **23 renglones** (21 hallazgos + 3 colaterales, descontando solapes), cada uno **exactamente una vez** con su etapa asignada. Es el criterio de cobertura contable contra hallazgos huérfanos, y el estado persistente para volver tras semanas de pausa.
- **Trinquete estructural en la suite** (no lista blanca — una lista blanca se convierte en lo que se erosiona): veta por **columnas-fuente crudas** fuera de `private`, con las **20 constantes** del tablero, todas «solo bajan». Toda excepción exige editar el test con justificación escrita, visible en el diff. Límite declarado: no caza SQL dinámico — lo cubre `auditor-rls` en cada migración.
- **⚠️ Auditoría del denominador (hallazgo del crítico, verificado):** el predicado `sum(capital)` **no ve a los consumidores indirectos**. Hay 33 funciones que mencionan capital sin sumarlo directo (`resumen_cartera_fn`, `series_comerciales_fn`, `contratos_cartera_fn`, `conversion_mensual_fn`, `cumplimiento_metas_sin_cartera_fn`, `admin_pagos_resumen`…), algunas por las vistas `contratos_cartera`/`clientes_basicos`. **Sin esto, el tablero podría marcar «capital 16 → 0» con capital calculándose todavía fuera del núcleo.** E0 audita la cadena vista→función y produce el denominador real: cada función va a *migrar*, *fichar como paso-a-través* o *declarar*. Lo mismo para el denominador de leads (~12 de 21 son superficie de métricas; los incidentales se declaran «operativos» **con nombre y razón en el propio test**).
- **Reglas escritas donde se leen:** corregir `CRM-Avance-Corp/supabase/migrations/LEEME.md`, que hoy dice «Trigger `log_audit_change` sobre toda tabla `crm.*`» cuando producción usa `private.log_audit_crm` en las 33 de crm (**verificado**) — es el archivo que lee quien escribe la próxima migración, y el modo de fallo de D3 es que la función equivocada no falla al crear el trigger sino **al escribir**. En el mismo pase: convención de auditoría por familia, regla de helpers/`v_actor`/`COMMENT` en el CLAUDE.md del CRM, y el **protocolo de inventario del front** (qué archivos, qué patrones, qué cuenta como «cálculo propio» y qué no — un `toFixed` de presentación no lo es).
- **Sonda diaria de logs arrancada HOY** (la ventana del API es de 24 h): así E11 llega con 10+ días acumulados en vez de empezar a esperar.
- **Los dos desbloqueos de terceros pedidos el día 1**, como condición de **entrada** de E11, no de salida: abrir a mano el Apps Script del puente y responder qué consume el rol `crm_metricas_bridge`.
- **Mesa 1 entregada** (ver «Mesas»).

**Cierre verificable:** el tablero existe con 23 renglones y ninguno sin etapa; el trinquete corre en la suite y **falla ante un mutante** que suba cualquier constante; el LEEME dice lo que hace producción; la sonda de logs tiene ≥1 día de datos.

---

## E1 · Blindaje pre-sellado — rastro de auditoría completo y malla del dinero
**Autónoma · riesgo bajo · 2 sesiones · EN PRODUCCIÓN ANTES DEL 05/09** (margen deliberado sobre el 10/09: ya se vivieron 429 de Hostinger y ramas que caen en `MIGRATIONS_FAILED` por diseño)

Cierra el único ROTO y arma la malla anti-NaN **mientras las tablas del sellado están vacías**. Después del 10/09 deja de ser gratis.

- **Rastro:** trigger de auditoría en `public.contrato_titulares` (el ROTO), `crm.actividades_cliente` y `crm.agenda_ics`. **⚠️ Dos detalles que ningún borrador vio y aquí entran:**
  - `_sync_contrato_titulares` **borra todos los co-titulares y los reinserta** en cada `actualizar_contrato`: colgar el trigger tal cual llenaría `audit_log` de pares DELETE+INSERT espurios y **no diría qué cambió** — que es justo la reconstrucción forense por la que R1 es ROTO. Se audita **con diff** (en el `_sync`, o filtrando en el trigger). Decisión técnica, no de negocio.
  - La tabla ya tiene `trg_contrato_titulares_00_documental_congelado`: el trigger nuevo se nombra y ordena explícitamente, y se prueba qué queda auditado cuando el candado aborta.
- **`crm.actividades`: DELETE sin auditar (verificado — `trg_audit_actividades` solo dispara en INSERT).** Es el historial de gestión del lead, la hija de más valor comercial de las cascadas de C3. Se completa a INSERT/UPDATE/DELETE. Igual `public.cronograma_pagos` (hoy **solo UPDATE**, verificado): se le agrega DELETE aquí — la auditoría ya decía que comparte migración con esta.
- **Declaraciones con `COMMENT` (las 5 que no llevan trigger):** `crm.usuario_eventos` (⚠️ `id` es BIGINT: `log_audit_crm` abortaría todo DML por el cast `::uuid`) como bitácora; `crm.operaciones_cartera` como **ledger append-only a propósito** (refutada 3/3 como roto); `public.suscripciones_push`, `public.novedades_leidas` y `public.audit_log` como sin auditoría deliberada. 3 cableadas + 5 declaradas = **8, la consulta llega a 0**.
- **Malla anti-NaN:** CHECK canónico en `cronograma_pagos.monto_programado/monto_pagado`, todos los campos de `cierre_mes_vendedor`, `periodos_cerrados.ponderacion_referido`, `lead_asignaciones.monto_estimado` y los 6 de `ajustes_mes_cerrado`. Pre-verificado: **0 filas violan hoy**.
- Toca `public` → **declara la excepción del LEEME y pide OK** (regla invariante 9).

**Cierre verificable:** (a) 0 tablas sin trigger **ni declaración**; (b) 0 columnas de dinero sin la regla canónica **o su variante equivalente** (tope superior, cero legítimo) — el carve-out va escrito, si no el contador queda rojo para siempre; (c) en rama, quitar un co-titular deja en `audit_log` **qué co-titular** cambió, no un par espurio; (d) gate 1175 + `gate:realidad` verdes.

---

## E2 · Diseño de los tres núcleos y las mesas de decisión
**Autónoma (produce preguntas, no respuestas) · riesgo nulo · 1–2 sesiones · ideal DURANTE el congelamiento 08–12/09**

⚠️ Los diseños de capital/leads/citas **no existen** (solo el de conversión, verificado). Esta etapa los produce con el método del de conversión y **separa las dos superficies**: la de **decisión** (~6 definiciones de capital, ~4 de leads, ~3 de citas — lo único que consume tiempo de Miguel) y la de **migración** (el denominador real que salió de E0 — trabajo mecánico).

- Ficha por métrica: forma exacta de la fila-hecho **aplicando la regla de diseño del hecho** (dimensiones abiertas como columnas), su ventana, sus consumidores. Conversión se ficha ya (su núcleo está en prod).
- **Plantilla literal:** `private.conversion_episodios` y su migración `20260826233000_crm_f1_conversion_episodios.sql` — con `revoke all`, `COMMENT` y postflight de owner/ACL/definer **dentro de la propia migración**; banco local con stubs vía `run-test-conversion-episodios-local.sh`.
- **Anclar la huella `md5` del texto VIVO** de cada función a reescribir antes de tocarla (`metricas_conversiones_implementacion` en particular): un cuerpo pudo aplicarse en caliente sin migración, y «un parche que solo vive en el artefacto no existe».
- Nombrar el **16.º consumidor** de capital que la auditoría dejó sin nominar.
- **Mesas 2 y 3 entregadas.**

**Cierre:** las 3 notas de diseño existen con ambas listas **nominales**; cada mesa entregada con fecha registrada y **ninguna respondida por inferencia desde el código**.

---

## E3 · Congelamiento y vigilancia del primer sellado (08–12/09)
**Autónoma · riesgo bajo por diseño (no se cambia nada) · 0,5 sesiones**

El estreno del sellado se **observa**, no se esquiva. Cero migraciones y cero releases entre el 08 y el 12/09 (verificable en el historial de migraciones); sesiones paralelas avisadas.

- Vigilar el 10/09: `cierre_mes_vendedor` se puebla, **ningún CHECK de E1 rebotó una escritura legítima**, los 5 cron jobs siguen en 0 fallos.
- **Guion de contingencia escrito ANTES del 10/09** (las tablas del sellado nacen vacías: el rollback natural es vaciar y re-sellar).
- **Fixture de sellado** capturado del mes real: los datos de entrada que produjeron el sellado, guardados como semilla reproducible. *(Corrección al borrador de riesgo: «replayar el sellado del 10/09» contra un baseline no es ejecutable — las ramas se siembran con la FORMA de producción, no con sus datos, y producción se mueve. El oráculo de E7 es **el mismo fixture, antes y después**.)*

**Cierre:** sellado ejecutado, filas dentro de la malla, 0 fallos de cron, fixture guardado con su procedimiento de reconstrucción, cero migraciones publicadas en la ventana.

---

## E4 · Pase único de superficie: grants, políticas y puertas de borrado
**Espera 2 respuestas (Mesa 1) pero NO se bloquea · riesgo MEDIO (el mayor del saneamiento) · 1–2 sesiones · semana del 14/09 — DESPUÉS del sellado**

*(Corrección a P-053, que ponía esto la semana previa al sellado: REVOKEs sobre el portal vivo y el estreno del sellado son dos modos de fallo nuevos que no pueden compartir ventana.)* Grants y políticas van en **una sola rama y un solo smoke** — partirlos expondría el portal vivo dos veces al mismo modo de fallo.

- **REVOKEs:** todo de `anon` en las 10 tablas de `public`; `TRUNCATE/REFERENCES/TRIGGER/MAINTAIN` de `authenticated`; EXECUTE de `anon`/PUBLIC en las 5 RPC `admin_*` y las 6 funciones de trigger de `public`; **ACL explícita a las 5 funciones de trigger de `private` con `proacl` NULL** (heredan EXECUTE a PUBLIC; las otras 158 tienen ACL explícita).
- **`ALTER DEFAULT PRIVILEGES` en crm y private — y va ANTES de crear los núcleos** (E6+): si nacen antes, hay que revocarlos uno a uno después.
- **Políticas (D4+C4, que quedaban huérfanas de tanda en P-053):** las 3 con `'superadmin'` inline pasan a los helpers, se borra `audit_log_superadmin_select` (100 % redundante, verificado), y los **13 helpers desnudos** se envuelven en `(SELECT helper())`.
- **`private.puede_ver_cartera`** a `search_path=''` (hoy `private, crm, public`, hallazgo del auditor de Miguel — inexplotable pero divergente) + revisión de los otros 13 SECURITY DEFINER de crm/private con `public` en el path.
- **Puertas de borrado:** alcance en `superadmin_elimina_perfiles` y chequeo previo en la edge `eliminar-cliente` (5 clientes expuestos hoy) — **entran cuando lleguen las respuestas; los REVOKEs no las esperan**, se parte la tanda si hace falta. Y se **encola la decisión sobre `equipo_perfil_id_fkey`** (hoy CASCADE: tapar la política deja vivo el mecanismo que viola P04 por cualquier otro camino).
- Regla de dirección del deploy si toca el portal: clave nueva en la **respuesta** → front primero; en la **petición** de una edge → servidor primero. Portal siempre archivo a archivo, con purga y verificación de la URL exacta.

**Cierre:** 0 privilegios de `anon`/PUBLIC sobre tablas de `public` y 0 TRUNCATE de `authenticated`; default privileges vigentes en crm y private; 0 políticas con rol inline y 0 helpers desnudos; **smoke completo del portal con cuenta admin real verde el día del release**; guion re-GRANT probado antes de publicar.

---

## E5 · Modelo de datos: la capa de tablas se cierra antes que los núcleos
**Mixta · riesgo bajo-medio · 3–4 sesiones · segunda mitad de septiembre**

*(Decisión de secuencia del plan maestro: P-053 mandaba esto al final; va **antes** de los núcleos. Si los NOT NULL, los dominios y los drops de índices llegaran después de 40+ paridades firmadas, cambiarían planes de ejecución bajo funciones ya verificadas y habría que re-medir todo.)*

- **Índices en UNA tanda medida en rama con planes antes/después:** crear los 5 de FKs en tablas que crecen; soltar los 8 redundantes (siempre el no-UNIQUE). `idx_perfiles_rol` (251 466 scans, lo usan los helpers de rol) con **doble medición con rol real** — los EXPLAIN de la auditoría corrieron con un rol que bypassa RLS. **Y declarar las otras 19 FKs sin índice como aceptadas conscientemente**, en especial las 12 hacia `perfiles`, que es el padre con más deletes reales (1 594).
- **NOT NULL:** las 10 columnas de timestamps/autoría 100 % pobladas.
- **Listas fijas:** punto único para `moneda` (×7) y `categoria` (×4); los 7 motivos de descarte pasan a FK. **Y una postura explícita para las que caen en el hueco de la regla «×4 se unifican, ×2 se toleran»:** `tipo_documento` (×3) y las etapas gestionables ×2 con superset en `leads` — se unifican o se declaran, no quedan sin renglón.
- **Documentos:** los 3 perfiles divergentes se corrigen **en sesión con Miguel** (datos reales de clientes) y solo entonces entra el CHECK de formato. **La frontera de la capa de tablas es parcial y se dice: este bloque puede llegar después** si la sesión con Miguel se demora.
- **`set_actualizado_en_crm` vs `public.set_actualizado_en`** (segunda mitad de D3, que ningún plan previo mencionaba): unificar o declarar la duplicación tolerable por familia. Sale con destino, no vive.

**Cierre:** 0 pares de índices redundantes y las 5 FKs indexadas con planes medidos y latencia de helpers igual o mejor; las 19 restantes declaradas; 10 columnas NOT NULL; `moneda`/`categoria`/motivos con punto único (consulta escrita en esta etapa: contar CHECKs de texto idénticos por familia — no existe en la auditoría); 0 documentos fuera de formato con CHECK vigente; el par `set_actualizado_en` con destino.

---

## E6 · Núcleo de CAPITAL — el primero
**Espera Mesa 2 para los NÚMEROS, no para la forma · riesgo medio por volumen, bajo por mecánica · 4–5 sesiones · desde ~21/09**

Gracias a la regla de diseño del hecho, **el núcleo se puede escribir sin la respuesta de atribución**: ambas dimensiones viajan en la fila.

- `private.capital_episodios(...)` + ventana `private.capital_autorizada(...)`, molde de conversión. PEN/USD jamás sumados.
- **Tandas escalonadas** (nunca dos releases con riesgo el mismo día): **a)** gerencia · **b)** cartera/ficha · **c)** portal.
- **⚠️ La decisión de C5 se pide ANTES de la tanda b:** `resumen_cartera_clientes_fn` y `contratos_por_periodo_comercial_fn` están a la vez en los 16 consumidores **y** en las «4 esperando pantalla». Pagar una tanda completa de paridad sobre ellas y después preguntar si se apagan es construir lo que se tira.
- Método por tanda: paridad md5 en la misma transacción + **mutante** (romper el núcleo debe romper a **todos** los migrados; el que no se rompe, no está consumiendo) + inventario del front según el protocolo de E0 + gates + release **solo si cambió la forma**.
- Los gates de las funciones tocadas migran a helpers en el mismo pase; `COMMENT` en todo lo tocado.

**Cierre:** paridad y mutante por tanda; contador de capital baja al valor comprometido (**2**: solo las escritoras); ficha de capital completa; front inventariado o excepción fichada.

---

## E7 · Las escritoras del sellado al núcleo
**Autónoma · riesgo ALTO en consecuencia, bajo en probabilidad · 2 sesiones · PUBLICADA ANTES DEL 03/10 o se pospone un mes**

`crm.cerrar_periodo` y `private.registrar_ajuste_si_mes_cerrado` pasan a **leer** del núcleo (siguen escribiendo el ledger). Es el cambio más delicado de toda la capa.

- **Ensayo doble sobre el fixture de E3:** el mismo asiento, antes y después, debe dar paridad byte a byte; y un mutante del núcleo **debe** alterar el sellado de prueba — si no lo altera, la escritora no está leyendo del núcleo.
- Cuerpos anteriores guardados dentro de la migración (rollback de un paso).
- **El sellado real del 10/10 es la prueba de aceptación**, con vigilancia idéntica a E3 y congelamiento 05–12/10. Si el ensayo no cierra limpio antes del 03/10, **se espera un mes**: el costo de esperar es cero, el de apurar no.

**Cierre:** paridad sobre fixture + mutante efectivo + sellado del 10/10 sano con montos consistentes con gerencia (comparados en la misma transacción); contador de capital = 0.

---

## E8 · Núcleos de LEADS y CITAS
**Autónoma · riesgo bajo-medio · 6–7 sesiones · octubre, esquivando 05–12/10**

Molde ya rodado dos veces. `private.leads_episodios` (denominador de E0) y `private.citas_episodios` (sobre `crm.tareas`; «qué cuenta como cita» se escribe una vez).

- La fila-hecho de leads trae **el criterio de pertenencia al roster explícito** (el hallazgo D8: 7,03 % vs 7,22 % era gente fuera de roster).
- Se respeta la decisión vigente: **UN solo contador de leads visible**.
- Los contadores incidentales quedan fuera de la capa **declarados con nombre y razón en el test** — sin eso el contador se puede llevar a 0 moviendo funciones a excepciones, y no mediría nada.

**Cierre:** contadores de leads y citas en 0 sobre el denominador de E0; paridad por tanda; **captura del «antes» agendada** de las pantallas afectadas para poder comparar el después.

---

## E9 · Productos: el criterio único (y el trío dormido, aparte)
**Partida a propósito · riesgo bajo · F1: 1 sesión (autónoma) · F2: 1–2 sesiones (espera Mesa 3)**

- **F1 va sí o sí:** `private.producto_condiciones_seleccionables(...)` con el predicado único, consumido por sus 3 copias. Las dos selectoras se quedan (columnas distintas por superficie es diseño legítimo). Paridad de ambas + mutante que las cambie a la vez.
- **F2 espera la decisión de frontera** y va **después**, nunca antes: unificar el trío en un cuerpo interno con la coreografía del GUC una sola vez (guardar-y-restaurar), **o** retirarlo por el protocolo de E11. Ejecutar la unificación y que Miguel decida después no estrenar sería construir exactamente lo que la otra rama borra.

**Cierre:** el predicado existe una sola vez (verificable en `pg_proc`); paridad de ambas selectoras; F2 con su rama ejecutada según la respuesta.

---

## E10 · El bug del pasaporte (fuera de tanda)
**Autónoma · riesgo bajo · 0,5 sesiones · cualquier semana no congelada — cuanto antes**

`crm-usuarios` usa el documento como contraseña inicial sin relleno: un pasaporte de 6–7 caracteres muere en el mínimo de 8 de Auth. **Es el único hallazgo de toda la auditoría que hoy le pega a una persona intentando trabajar** — no espera a nada ni a nadie. Protocolo de edges: contrastar árbol↔función VIVA antes de desplegar (la regresión v8-pisó-v5 ya se cobró una vez).

**Cierre:** alta con pasaporte de 6 caracteres exitosa; versión desplegada = árbol commiteado.

---

## E11 · Retiros programados
**Espera OK por pieza (Mesa 4) + 2 desbloqueos de terceros · riesgo medio en agregado, bajo por pieza · 2–3 sesiones repartidas en 3–4 semanas · noviembre**

Los desbloqueos (Apps Script, `crm_metricas_bridge`) son **condición de entrada**, pedidos desde E0. La sonda de logs ya lleva semanas corriendo.

- Piezas: `contrato_pdf_snapshot_v2` (muerta confirmada), las 3 superadas, las 2 RPC `pagos_admin_*`, la edge `diagnostico-push` (stub 410), y **v1 → después v2** de distribución.
- **v2 exige el orden correcto: primero publicar el front que deja de llamarla**, después esperar la muerte del bundle, después REVOKE. Sin ese release previo el reloj nunca empieza a correr y el REVOKE rompe pantallas de gente trabajando.
- **La caché no es una sola:** la CDN de 7 días es del **portal** (`public_html`); las RPC del **CRM** viajan en releases al byte. Cada pieza declara **qué superficie la llama** y **cómo se comprueba** que su bundle murió (no por calendario: por evidencia).
- REVOKEs **escalonados**, nunca más de una familia por semana, para que una regresión sea atribuible.
- Las 4 esperando pantalla: se ejecuta lo que Miguel haya decidido en E6.

**Cierre por pieza:** ≥10 días de sonda sin peticiones + ≥7 días post-REVOKE sin errores nuevos → DROP. Global: 1 sola versión de distribución con grant; ledger de retiros escrito (qué se apagó, qué se observó, cuándo se dropeó). *(«0 funciones sin llamador conocido» no es una consulta: es el procedimiento de C5 — catálogo + repo + 16 bundles + logs — y así queda escrito.)*

---

## E12 · Gate de autorización y catálogo (lo que el contagio no cubrió)
**Autónoma · riesgo bajo · 2–3 sesiones · diciembre**

Sin campaña de 114 ediciones (la fuente lo veta explícitamente).

- **Pase chico:** las 20 funciones con `rol_crm in (...)` inline → helper de capacidad, en una tanda; cambio mecánico con el gate 1175 como red.
- **Catálogo de errores.** ⚠️ **Primero el inventario del front:** el front matchea mensajes por string (dicho literal en D6) — unificar 70 ocurrencias sin saber qué pantallas comparan textos rompería una rama en silencio, que es el mismo modo de fallo que el plan dice cerrar. El inventario es entregable, no nota al pie.
- **Zona horaria:** el literal no se reemplaza (cambiaría planes); se agrega la **guardia** que falla ante cualquier zona distinta de `America/Lima`. El punto único de verdad pasa a ser el test.
- **La dispersión del gate no se declara resuelta:** se **mide y se registra su valor de cierre real** en el tablero. Un plan que promete 0 sobre 114 y entrega 60 se lee como fracaso; uno que promete «baja por contagio, valor registrado» y entrega 60 se lee como lo que es.

**Cierre:** 0 gates inline; las 4 familias de error con helper y 0 copias nuevas desde su creación; la guardia de tz falla ante un mutante con otra zona; valor final de rol-literal registrado.

---

## E13 · Cierre: re-auditoría, contrato sellado y excepciones firmadas
**Mixta · riesgo nulo · 1–2 sesiones · fin de ciclo**

- Re-ejecutar las consultas de la auditoría del 28/08 como regresión. **Faltan consultas para C5, C6 completo, C7 y R1 más allá de los conteos: escribirlas es entregable de esta etapa**, si no el «terminado medible» tiene agujeros.
- Registro semántico completo (conversión, capital, leads, citas, distribución + «seleccionable» como capa no-métrica).
- **Lista de excepciones conscientes firmada por Miguel**, incluyendo lo que la auditoría dejó verificado-y-descartado para que no reaparezca como anomalía: las 26 tablas con RLS y cero políticas (deny-all deliberado), el USAGE de `private` para `authenticated` (requisito del patrón), las 19 FKs sin índice aceptadas, las listas ×2 toleradas, el stock de rol-literal, los `verify_jwt=false` deliberados de `notificar-pagos`/`ciclo-contratos`/`crm-agenda-ics`, y las funciones sin COMMENT históricas.
- Nota de retomar actualizada bajo `RETOMAR-SERVIDOR`.

**Cierre:** informe con el antes/después de cada contador y **cero hallazgos sin destino registrado** (arreglado / retirado / declarado-a-propósito / aparcado por Miguel).

---

## ✅ Decisiones ya tomadas por Miguel (2026-08-28)

| Tema | Decisión | Qué cambia en el plan |
|---|---|---|
| **Capital: ¿de quién es?** | **Del vendedor, sí o sí** | El núcleo se construye con el vendedor como atribución principal. «Quien dio de alta» queda descartado: son 19 analistas de back office + 1 superadmin + 1 admin, es quien tipea, no quien vende. |
| **Tablero de gerencia, por ahora** | **Solo la cartera total** (S/ 18,0 M + US$ 1,10 M) | No se abre por vendedor hasta que el proceso capture bien. Se guarda igual la atribución en el hecho, pero no se expone. |
| **Desglose renovado/adicional** | **Completarlo: lo quiere ver** | Trabajo nuevo: arreglar el alta para que grabe las dos cifras + rellenar las 62 operaciones existentes. Entra al diseño del núcleo de capital (E2/E6). |
| **Catálogo de productos versionados (6 funciones dormidas)** | **Eliminarlas** | E9-F2 queda resuelta: rama de retiro. Primero quitar el guard del cierre legacy, después apagar, después borrar. **E9-F1 (criterio único) sigue: lo consumen las dos pantallas vivas.** |
| **4 funciones esperando pantalla** | **Publicar las pantallas** | Salen de la lista de retiros de E11. «Mi cartera» y «Ficha 360°» (88 %) y el período comercial del supervisor pasan a trabajo de producto, con calendario propio. ⚠️ Consecuencia para E6: `resumen_cartera_clientes_fn` y `contratos_por_periodo_comercial_fn` **sí** se migran al núcleo (ya no hay riesgo de pagar paridad sobre algo que se apaga). |
| **Botón «eliminar cliente»** | **Avisar antes de borrar** | Muestra qué se va a borrar (cuentas bancarias y actividades del CRM) y pide confirmación. Entra en E4. |
| **Superadmin borrando perfiles** | **Queda abierto como hoy** | Excepción consciente firmada. Consecuencia dicha y aceptada: borrar un colaborador borra su membresía del equipo, en contra de la regla P04. Se documenta en E13, no se restringe. |
| **Conexión `crm_metricas_bridge`** | **No se sabe qué la usa → investigar** | Sigue siendo bloqueo duro de E11: no se retira nada que dependa de ella hasta identificar al consumidor. |
| **Apps Script del puente** | **DESBLOQUEADO** (verificado 28/08) | El conector solo llama a la puerta de importar leads; no toca ninguna candidata a retiro. Deja de ser condición de entrada de E11. |
| **Nomenclatura** | **«analista» en todo el sistema, CRM y portal — incluidos los nombres internos** | Campaña nueva: **E14**. El portal ya dice «analista»; el CRM converge hacia él. Alcance completo (columnas, tablas, índices, funciones, rol y textos). |
| **Tablero por analista** | **Abrir, pero verificando antes con Miguel** | Se le presenta el reparto de agosto por persona; si calza con lo que él sabe del equipo, se abre. Reemplaza la decisión previa de «solo cartera total», tomada cuando se creía que el dato no existía. |
| **Cierres en cooperativas** | **SON parte del capital: se incluyen** | El núcleo de capital lee **dos fuentes**: `public.contratos` (portal) **y** `crm.cierres_externos` (cooperativas, hoy solo PEN por restricción deliberada). Los anulados (`anulado_en`) no cuentan — la anulación sigue siendo la única puerta que descuenta. Agosto: S/ 260 000 vigentes en 5 cierres (+1 anulado por S/ 100 000). Un núcleo que leyera solo contratos le restaría S/ 200 000 a una sola analista. |
| **«Quien registra» ≠ «quien vende» (regla nueva)** | Confirmada por Miguel con el caso Gloria | Personal administrativo registra contratos por encargo. Medido: **449 de 466** contratos los registró un analista o supervisor (atribución directa); **17** los registró gerencia o administración (S/ 666 000 + US$ 129 267) y de esos el sistema **no sabe quién vendió**. El núcleo necesita una regla explícita para esos casos — decisión pendiente: atribución manual, bolsa de «sin analista», o capturar el analista real en el alta. |

---

## E14 · Campaña de nomenclatura: «vendedor» → «analista» en todo el sistema

**Decidida por Miguel el 28/08, alcance completo.** Justificación de primera mano: la doble nomenclatura ya invalidó un análisis entero en la sesión donde se decidió (ver el hallazgo de arriba).

**Alcance medido (28/08):**

| Capa | Objetos | Quién lo ve |
|---|---|---|
| Texto del CRM | 3 236 apariciones en 218 archivos | todos, todo el día |
| Rol del sistema | 19 filas de `crm.equipo`, 54 funciones con el literal, 18 políticas RLS, 6 constraints CHECK | semi-visible; raíz de la ambigüedad |
| Nombres internos | 10 columnas, 4 tablas, 17 índices, 13 funciones | nadie |

El **portal ya dice «analista»** en sus 17 archivos y no dice «vendedor» ni una vez: la convergencia es del CRM hacia el portal, no al revés.

**Riesgo declarado y a auditar antes de ejecutar:** renombrar el valor `rol_crm='vendedor'` toca el gate de autorización entero (54 funciones + 18 políticas + 6 CHECK); un solo lugar que quede comparando el string viejo deniega acceso en silencio. Y hay una fusión semántica que debe decidirse a propósito: `public.perfiles.rol='analista'` ya existe con su propio significado. **Auditado por Codex antes de escribir la primera migración** (regla del proyecto: pedirle refutar el diagnóstico).

**Fases previstas:** (1) auditoría de rotura y orden de despliegue; (2) rol y lógica del servidor con el gate 1175 como red; (3) textos del CRM; (4) nombres internos (columnas, tablas, índices) al final, cuando todo lo demás esté estable — es la parte cara y sin retorno visible.

**Dependencia dura:** no se solapa con E6–E8 (los núcleos) ni con ninguna ventana de sellado; un renombre a mitad de una campaña de paridad haría imposible distinguir qué cambió un número.

---

## 🔑 Hallazgo del 28/08: la doble nomenclatura ya produjo un diagnóstico errado

**La misma persona se llama `analista` en el portal y `vendedor` en el CRM.** Verificado: 17 personas tienen simultáneamente `perfiles.rol='analista'` y `crm.equipo.rol_crm='vendedor'`, más 2 que son analista+supervisor. **No son dos grupos: son el mismo equipo comercial.**

Esa ambigüedad causó un error de análisis en esta misma sesión: se concluyó que «el capital lo registra el back office, no los vendedores» y que «el CRM no captura la venta nueva». **Las dos afirmaciones eran falsas** y quedan retractadas.

**El cuadro correcto — la atribución del capital existe y siempre existió:**

| Quién registró el contrato | Contratos | Capital |
|---|---|---|
| Analistas del equipo comercial (hoy rol «vendedor») | 432 | S/ 15,36 M + US$ 939 K |
| Supervisores | 17 | S/ 1,99 M + US$ 28 K |
| Gerencia | 16 | S/ 506 K + US$ 129 K |
| **Fuera del equipo comercial** | **1** | **S/ 160 K** |

**465 de 466 contratos tienen dueño.** En agosto: 205 contratos, S/ 6,26 M + US$ 585 K, entre 16 personas con producción.

**Dónde estaba el error de las métricas:** buscaban la atribución por la *operación de cartera*, que solo existe para upgrades y renovaciones (62 de 210 en agosto; de las 113 ventas nuevas, ninguna). La atribución real vive en **quién registró el contrato**, que es el analista que lo vendió. El núcleo de capital se construye sobre ese camino, no sobre el de cartera.

**Dato colateral que sigue en pie:** la fecha de cierre comercial está **inferida en 435 de 466 contratos**; solo 13 tienen fecha registrada de verdad. Eso sí es una debilidad real del dato y entra al diseño del núcleo (E2).

**Lección de método, para el registro:** un término con dos nombres según el sistema desde el que se lo mire es capaz de invalidar un análisis entero hecho sobre datos correctos. Es la justificación más fuerte de la campaña de nomenclatura (E14).

---

## Mesas de decisión (máximo 5 preguntas, con el número al lado)

| Mesa | Cuándo se entrega | Preguntas | Bloquea |
|---|---|---|---|
| **1 · Puertas y borrado** | E0 | Alcance de `superadmin_elimina_perfiles` · `eliminar-cliente`: ¿bloquear o avisar? (5 clientes expuestos) · `equipo_perfil_id_fkey`: ¿pasa a RESTRICT? | Solo la mitad de E4 (los REVOKEs van igual) |
| **2 · Capital** | E2 | Atribución: ¿asesor o vendedor del lead? (**S/ 3,76 M vs S/ 113 K**) · ¿pipeline estimado convive con capital real? · ¿AUM entra? · ¿Qué se hace con las 4 RPC esperando pantalla? (2 de ellas están en la tanda b) | Los **números** de E6, no su construcción |
| **3 · Productos y datos** | E2 | ¿Se estrena la frontera catalogada? · Los 3 documentos a corregir (sesión con Miguel) · `tipo_documento`: ¿unificar o tolerar? | E9-F2 y el CHECK de E5 |
| **4 · Retiros** | Antes de E11 | OK pieza por pieza · ¿Qué consume `crm_metricas_bridge`? · Apps Script del puente (abrir a mano) | E11 completa |

**Latencia de respuesta = métrica del tablero.** Si una mesa lleva más de dos semanas, la etapa que bloquea se re-secuencia; nunca se espera con las manos quietas: el trabajo mecánico (trinquete, índices, pase de políticas) existe para llenar esas esperas.

---

## Tablero (20 contadores — todos «solo bajan»)

| Contador | Hoy | Meta | Etapa |
|---|---|---|---|
| Capital calculado fuera del núcleo | 16 + indirectos de E0 | 0 | E6 → 2 · E7 → 0 |
| Leads contados fuera del núcleo | 21 (denominador real en E0) | 0 | E8 |
| Citas contadas fuera del núcleo | 6 | 0 | E8 |
| Tablas sin trigger **ni declaración** | 8 | 0 | E1 |
| Tablas de negocio con DELETE sin auditar | 4 | 0 | E1 |
| Columnas de dinero sin regla canónica (o equivalente declarada) | 11+ | 0 | E1 |
| Privilegios de `anon`/PUBLIC sobre `public` + TRUNCATE de `authenticated` | todas | 0 | E4 |
| Políticas con rol inline · con helper desnudo | 3 · 13 | 0 · 0 | E4 |
| SECURITY DEFINER de crm/private con `public` en el path | 14 | declarados o corregidos | E4 |
| Pares de índices redundantes · FKs de tablas que crecen sin índice | 8 · 5 | 0 · 0 | E5 |
| Columnas 100 % pobladas sin NOT NULL | 10 | 0 | E5 |
| Listas fijas sin punto único (moneda ×7, categoria ×4, motivos ×3, tipo_documento ×3) | 4 | 0 o declaradas | E5 |
| Documentos de perfiles fuera de formato | 3 | 0 | E5 |
| Predicado «seleccionable» escrito N veces | 3 | 1 | E9 |
| Versiones de `metricas_distribucion_leads` con grant | 3 | 1 | E11 |
| Candidatas a retiro con EXECUTE vivo | 9 | 0 (retiradas o con pantalla) | E11 |
| Gates `rol_crm in (...)` inline | 20 | 0 | E12 |
| Funciones con algún rol literal | 114 | **sin meta: valor final registrado** | contagio |
| Apariciones de `America/Lima` | 47 fn / 139 occ | solo baja + guardia activa | E12 |
| Fichas del registro semántico | 1 | 6 | E13 |
| Sellados reales sanos | 0 | 2 (10/09 y 10/10) | E3, E7 |
| Mesas con respuesta o aparcamiento firmado | 0/4 | 4/4 | E13 |

---

## Definición de terminado (medible)

1. Los contadores del tablero en su meta, **o** con excepción firmada por Miguel.
2. Cada métrica con su ficha: fila-hecho, ventana única, consumidores — y ninguna pantalla calculando (inventario del front limpio o excepción fichada).
3. Dos sellados mensuales reales ejecutados sanos, el segundo con las escritoras leyendo del núcleo.
4. Cero hallazgos de la auditoría del 28/08 sin destino registrado.
5. El trinquete queda **permanente** en la suite: es el candado, no el andamio.
6. Toda decisión de negocio con respuesta registrada o aparcamiento explícito — **ninguna resuelta por inferencia desde el código**.

---

## Correcciones a los planes anteriores (y al trabajo previo)

Verificado contra producción y disco antes de escribir esto:
- **El LEEME de migraciones miente sobre la auditoría** (dice `log_audit_change` para todo `crm.*`; producción usa `private.log_audit_crm` en las 33). Se corrige en E0 — es el archivo que lee quien escribe la próxima migración.
- **`crm.actividades` audita solo INSERT** y **`cronograma_pagos` solo UPDATE**: dos puertas de borrado de historial que ningún plan previo ubicaba. Entran en E1.
- **El trinquete de capital, tal como estaba diseñado, no vería a los consumidores indirectos** (33 funciones mencionan capital sin sumarlo directo, algunas vía vistas). E0 produce el denominador real antes de que el contador signifique algo.
- **P-053 ponía los REVOKE del portal la semana previa al primer sellado**: se corren a después del 10/09.
- **El modelo de datos sube de la última etapa a antes de los núcleos**, para no re-medir 40 paridades ya firmadas.
- **El «replay del sellado real» no era ejecutable** (las ramas se siembran con la forma, no con los datos): el oráculo pasa a ser el mismo fixture antes y después.
- **El fix del pasaporte se despega del buzón de decisiones**: no espera nada y es lo único que hoy le pega a una persona trabajando.
