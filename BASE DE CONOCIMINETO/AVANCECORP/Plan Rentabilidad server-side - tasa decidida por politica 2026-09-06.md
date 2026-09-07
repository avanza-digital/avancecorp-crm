# Plan Rentabilidad server-side: la tasa la decide la política, la excepción la decide Gerencia

Fecha: 2026-09-06. Origen: propuesta `arquitectura-rentabilidad-v1.html` (Codex, basada en `trunk@dc6c83e`)
más la decisión D6 de Miguel (contraoferta de Gerencia). Relacionado: [[Plan de mejoras UX-UI del CRM]],
[[Decisiones UI UX Gerencia - 2026-09-06]], regla "una sola fuente en servidor" (conversión).

## Objetivo comercial

La rentabilidad que se paga al inversionista es el margen de Avance Corp. Hoy la fija quien llena el
formulario (15% sugerido, editable, corregible después). El objetivo es que sea **política de empresa**:

- Cliente nuevo: 15% fijo.
- Renovación / upgrade: hereda la tasa del contrato origen que el analista selecciona.
- Subir la tasa: solo con autorización de Gerencia, con motivo, para un caso, un solo uso.
- Gerencia puede aprobar, rechazar o **aprobar hasta un tope** (D6); el analista acepta el tope y sigue, o declina.
- Bajar la tasa: no existe como excepción.
- Los 514 contratos históricos no se tocan.

## Situación verificada en el código (06/09)

- Tres puertas escriben tasa: `crm.crear_contrato_con_cuenta_pdf_v2` (CRM), `public.crear_contrato`
  (portal admin: `analista.js`, `contratos.js`) y `crm.actualizar_contrato_con_cuenta_pdf_v3` (corrección).
  Las tres aceptan la tasa del navegador entre 0 y 50.
- El catálogo versionado ya valida `tasa_min`/`tasa_max` por condición, pero con 0 productos publicados el
  puente legacy crea el snapshot con la tasa que llegó: la validación no restringe nada.
- `operaciones_cartera.contrato_origen_id` ya existe: es el gancho para heredar la tasa.
- Front: `contrato-nuevo.tsx` inicia en '15' y valida 0 < tasa <= 50.

## Decisiones (R0)

| # | Decisión | Regla acordada | Estado |
|---|---|---|---|
| D1 | Nueva inversión de cliente existente | Parte de 15%. Si pide excepción, su solicitud tiene prioridad en la bandeja de Gerencia. | **Acordada 2026-09-06** (Miguel, sesión de este día) |
| D2 | Contrato base de renovación / upgrade | El analista selecciona el contrato activo exacto del cliente; el servidor valida propiedad y estado. La tasa base es la `tasa_anual` de ese contrato. | **Acordada 2026-09-06** (Miguel, sesión de este día) |
| D3 | Autoridad para aprobar | Solo Gerencia. Nunca la misma persona que solicitó, aunque tenga rol de Gerencia. | **Acordada 2026-09-06** (Miguel, sesión de este día) |
| D4 | Tasa inferior a la base | Bloqueada. La excepción solo eleva la tasa. No existe excepción a la baja. | **Acordada 2026-09-06** (Miguel, sesión de este día) |
| D5 | Techo máximo autorizable | Lo fija Gerencia en cada solicitud ("aprobar hasta X%"). 50% es defensa técnica del servidor. El catálogo de productos NO forma parte de este plan. | **Acordada 2026-09-06** (Miguel, sesión de este día) |
| D6 | Contraoferta de Gerencia | Gerencia puede aprobar, rechazar o aprobar hasta un tope X con base < X <= tasa pedida. El analista acepta y sigue con cualquier tasa entre la base y X, o declina. Un solo uso, atada al fingerprint (cliente, producto, contrato origen, capital, moneda, plazo). Vence a los 7 días sin aceptar. | **Acordada 2026-09-06** (Miguel, sesión de este día) |

**R0 cerrada el 2026-09-06.** Las seis reglas son firmes: ninguna fase posterior las interpreta ni las
ajusta. El informe de R2 puede *proponer* un cambio a D1 o D4 con datos, pero solo entra si Miguel lo decide
de forma explícita y se registra aquí como nueva fila.

## Fases

Regla transversal: se trabaja sobre `main`, commit pequeño, `auditor-rls` + test-rls antes de cada
migración, preflight obligatorio antes de publicar, y el mismo día se vuelve a `main` (`push avancecorp main:tronco`).

### R0. Cerrar reglas ✅ (hecha 2026-09-06)
**Goal:** Dejar D1–D6 marcadas como acordadas en esta nota, con fecha y firma de Miguel, para que ninguna
fase posterior tenga que interpretar negocio.
- R0.1 Revisar la tabla anterior con Miguel; ajustar recomendaciones.
- R0.2 Registrar en esta nota y en el ledger del plan.
- Hecho cuando: las 6 filas tienen estado "acordada".

### R1. Núcleo de datos y resolver (migración aditiva, sin bloquear) ✅ EN PRODUCCIÓN 06/09/2026
**Estado 06/09/2026:** migración `20260906170000_crm_rentabilidad_r1_politica_solicitudes_ledger_resolver.sql` (v3 auditada,
md5 `758b26b2…`) construida, aplicada y registrada en **banco-f7**; oráculo `scripts/oraculo-rentabilidad-r1.sh` 130/130 verde
(mutante 102 rojos); reversa y registro ensayados; `auditor-rls`: APTA con condiciones, todas cerradas en la v3; suite RLS:
bloque R1 46/46 (los rojos de la suite son ambientales, ajenos). Detalle y evidencia en `supabase/migrations/MIGRACIONES.md`
(entrada 20260906170000). **Aplicada y registrada en producción el 06/09 (~13:45 Lima) por Miguel**: política v1 en
observación, ledger legacy 524 = 524 contratos, 238 migraciones. Falta su OK a la decisión de ámbito de abajo.

**Decisión pendiente de Miguel (auditor m2) — ámbito de las puertas de tasa.** El alta de contratos ya funciona con la
«decisión B»: cualquier analista/supervisor/Gerencia vigente (o admin del Portal) puede registrar una venta a CUALQUIER
cliente, sin acotar por cartera. R1 usa exactamente esa misma autoridad para resolver y pedir tasa, para que el formulario
no reciba un 42501 en un contrato que el alta sí aceptaría. Si Miguel prefiere acotar por cartera (que un analista solo
pueda ver la tasa base y pedir excepción de SUS clientes), hay que hacerlo a la vez en la puerta de tasa y en el alta.
Censo real de producción al construir: **524 contratos (no 514), 357 con tasa ≠ 15%, 17 tasas distintas** — el 68% de los
contratos NO está al 15%: R2 va a mostrar mucho margen cedido. Cambios de diseño respecto al plan original (los del auditor incluidos): una viva por huella pida quien pida (D6: el supervisor no abre otra sobre la del analista); tasas a 2 decimales; cliente inactivo rechazado; una sola RPC
`crm.responder_tope_tasa_fn(id, acepta, motivo)` en vez de aceptar/declinar separadas; sin FK a `public.contratos` en las
tablas nuevas (para no bloquear la eliminación de contratos por su puerta); el sello `vencida` es perezoso (el front lee
`vence_en`); la política nace en `modo = observacion` y R1 rechaza publicar `enforcement` (0A000) hasta R4.
**Goal:** Que exista en la base UNA función que responda "qué tasa base corresponde a este contrato y por
qué", y las tablas para política, solicitudes y ledger, sin cambiar el comportamiento de ninguna alta.
- R1.1 `crm.politica_rentabilidad` versionada (tasa base nueva, regla de herencia, techo, vigencia,
  `modo`: observacion | enforcement) + RPC publicar/retirar solo Gerencia, molde del catálogo.
- R1.2 `crm.solicitudes_tasa`: contrato en intención (huella), tasa base, tasa pedida, motivo, estado
  (`pendiente`, `aprobada`, `aprobada_con_tope`, `rechazada`, `aceptada_por_analista`,
  `declinada_por_analista`, `consumida`, `vencida`), tasa máxima autorizada, solicitante, resolutor, fechas.
  RPC: `solicitar_tasa_fn`, `resolver_solicitud_tasa_fn` (aprobar | rechazar | aprobar_hasta),
  `responder_tope_tasa_fn(id, acepta, motivo)`. Expiración perezosa al entrar en cada puerta (sin cron).
- R1.3 `crm.ledger_rentabilidad` append-only: contrato, tasa base, tasa final, regla, contrato origen,
  solicitud consumida, quién, cuándo. Backfill de los 514 como `historica_legacy` (base = final).
  Preflight de conteos y hashes; rollback ensayado en banco.
- R1.4 `crm.resolver_tasa_fn(cliente, categoría, contrato_origen)` → base, regla, origen validado.
  ÚNICO núcleo; ninguna otra función calcula tasa (misma disciplina que conversión).
- R1.5 Suite SQL (roles, RLS deny-by-default, solicitante ≠ resolutor, tope fuera de rango rechazado),
  `auditor-rls`, test-rls, banco, migración a producción.
- Hecho cuando: las 3 puertas de escritura siguen funcionando igual y `resolver_tasa_fn` responde
  correctamente para nuevo, renovación y upgrade en banco y producción.

### R2. Observación (dark read) ✅ SERVIDOR EN PRODUCCIÓN 06/09/2026 · tarjeta pendiente de release · semana de datos en curso
**Estado 06/09/2026:** migración `20260906180000_crm_rentabilidad_r2_observacion_ledger_y_tarjeta.sql`: un constraint
trigger DIFERIDO sobre `public.contratos` observa TODA alta y corrección de tasa (CRM, portal, corrección, directa) y
escribe en el ledger la tasa del núcleo frente a la que quedó, sin bloquear nunca; el núcleo gana `p_contrato_nuevo_id`
(la firma de R1 delega). Upgrade: origen inferido solo si es inequívoco (prod: 78 upgrades, 35 con origen único, 43
ambiguos → caso «no definido» que R3 resuelve). Tarjeta `crm.observacion_rentabilidad_fn` (Gerencia/Directorio) y panel
«Rentabilidad: margen cedido» en el Resumen de Gerencia (7/30/90 días; margen cedido = capital × puntos × plazo/365;
sondas `consistencia_interna` / `cobertura_altas` / `cobertura_correcciones`). v5: oráculo R2 52/52, oráculo R1 130/130 con
R2 montada; auditor-rls APTA con condiciones (cerradas); **Codex 1.ª ronda NO-GO con 17 hallazgos, todos cerrados en la v4/v5**
(los cuatro reales: condición de renovación con NULL, imagen del evento vs estado final al commit, doble conteo de correcciones
en la tarjeta, huecos falsos anteriores a R2); **Codex 2.ª ronda NO-GO** (1 bloqueante real: el contrato del front rechazaba el payload nuevo; más 8) → v6; **Codex 3.ª
ronda** (2 reales más: la tarjeta escondía la alarma con 0 observados; la reversa sin tabla de hitos) → **v7**, oráculo 55/55,
reversa→reaplicar→registrar en cadena. Lo que queda de Codex está aceptado y declarado en la cabecera de la migración (edge
cases de `SET CONSTRAINTS IMMEDIATE`, `statement_timeout` en el commit, demo eliminado, altas eliminadas en la cobertura).
⚠️ Coordinación: el banco ya lleva F2.b D-19 (otra sesión), que cambia dos de las cinco puertas de escritura; la guarda de R2
acepta ambos textos y puede aterrizar antes o después de D-19. La suite RLS no llega a nuestros bloques hoy por fatales
ajenos (identidad D-13 y un bloque F2.b roto por otra sesión). Lección: la excepción externa del observador probó su valor
en el ensayo (dos bugs propios quedaron en WARNING, ningún alta se cayó, y la sonda `cobertura_altas` los declaró). Detalle en `MIGRACIONES.md` (20260906180000). ⚠️ Toca `public` (un trigger): Miguel da el OK al
aplicar con `!`. Dato previo de prod: 218 altas en 30 días, 147 con tasa ≠ 15%.
**Goal:** Medir, con datos reales y sin rechazar ningún contrato, cuánto se aparta hoy la tasa que manda el
navegador de la que diría la política, y qué casos la política no define.
- R2.1 Las 3 RPC de escritura llaman a `resolver_tasa_fn` y escriben en el ledger tasa resuelta vs. recibida,
  sin bloquear.
- R2.2 `private.divergencias_rentabilidad_fn` + tarjeta en Gerencia: contratos del periodo, margen cedido
  (puntos × capital), por analista, casos no definidos (multi-origen, nuevo recurrente).
- R2.3 Una semana calendario en producción. Informe en el vault: números y decisión final sobre D1/D4.
- Hecho cuando: hay informe con margen cedido real y lista de casos no definidos resueltos o descartados.

### R3. Front sobre la nueva puerta ✅ construido y revisado 06/09 (Codex ×3, revisor-a11y, suite RLS en banco) — pendiente `!` (migración de lecturas) y release
**Estado 06/09/2026 (noche):** construido completo en el CRM y el portal: tasa bloqueada en la base con «Solicitar tasa
superior», selector del contrato origen del upgrade (D2), bandeja de Gerencia en el Resumen (Aprobar · Rechazar · Aprobar
hasta X%), aviso al analista en Hoy (aceptar/declinar el tope), historial de tasa en la ficha, Configuración → Política de
rentabilidad, y en el portal admin la tasa del alta «nuevo» bloqueada en la base (renovación/upgrade se registran en el
CRM). Servidor: migración `20260906220000` con 3 lecturas (solicitudes, historial por cliente, política), ensayada en
banco-f7 en su **v5** (md5 `44f002a4…`) tras tres rondas adversariales de Codex (11 + 7 + 1 hallazgos atendidos: filtros de servidor
`p_solo_mias`/`p_cliente_id` para que el límite de la bandeja no tape una autorización, Enter en el mini-formulario, corrección
que conserva la tasa persistida, caducidad recomprobada al guardar, rechazos visibles para el analista; origen del upgrade
en el alta, corrección siempre bloqueada, huella estricta, caducidad en el cliente, portal con guardas; en el servidor el
nombre del cliente solo con ámbito, el filtro por estado efectivo y el asesor con autoridad del alta) y de `revisor-a11y`
(foco, contraste, etiquetas). Hasta R4 el candado es del front.
**Hotfix R1 (`20260906233000`, mismo `!`):** el conflicto de versión al publicar la política lanzaba SQLSTATE `40001`, que PostgREST
reintenta hasta el timeout del gateway (~125 s); ahora `P0409` (143 ms). El mismo `40001` vive en metas/SLA, catálogo y
usuarios desde agosto: hallazgo anotado en `MIGRACIONES.md`, fuera de este plan, decisión de Miguel. Detalle en `MIGRACIONES.md` (20260906220000). Decisión no prevista en el plan:
en el portal admin las renovaciones y upgrades quedan bloqueados (heredan del origen, que el portal no captura): se hacen
en el CRM.
**Goal:** Que analista y Gerencia trabajen la tasa desde el CRM con el flujo pedir → decidir → aceptar,
en un clic, sin que ninguna pantalla calcule la tasa por su cuenta.
- R3.1 Contrato nuevo (`contrato-nuevo.tsx`): tasa bloqueada con regla visible; para renovación/upgrade,
  selector de contrato origen entre activos del cliente (validado por servidor); botón "Solicitar tasa
  superior" (tasa pedida + motivo).
- R3.2 Bandeja de Gerencia (nueva pantalla en `screens/hoy/` o sección en `gerencia.tsx`): tarjeta con
  cliente, capital, base, pedida, motivo, analista, antigüedad. Botones: Aprobar · Rechazar · Aprobar
  hasta [X%]. Un clic, confirmación inline, optimista. Prioriza D1.
- R3.3 Respuesta al analista en el mismo formulario: "Gerencia autorizó hasta 17%. Aceptar y continuar /
  No cerrar". Al aceptar, el alta se ejecuta con la autorización consumida. Aviso en la campana/alertas.
- R3.4 Corrección (`contrato-corregir.tsx`): cambiar tasa exige solicitud aprobada nueva y nueva revisión PDF.
- R3.5 Ficha del cliente: historial de tasa por contrato, regla, origen, decisión de Gerencia.
- R3.6 Configuración: política versionada junto al catálogo (publicar, retirar, auditar).
- R3.7 Portal admin (`public_html/js/admin/analista.js`, `contratos.js`): migrar a las mismas RPC o retirar
  el alta de contratos. Si queda abierta, es el agujero.
- R3.8 `revisor-a11y`, tests unit + MSW, preflight CRM y portal, publicar, volver a `main`.
- Hecho cuando: un analista pide 20%, Gerencia aprueba hasta 17% en un clic, el analista acepta y el
  contrato sale con 17% y PDF correcto, todo en producción.

### R4. Enforcement autoritativo 🧪 construido 07/09 — pendiente `!` y release; el candado se enciende APARTE
**Estado 07/09/2026:** construido y ensayado en banco-f7 en su **v3** (migración `20260907093000`, md5 `32f6e3ef…`;
oráculo propio 50/50, mutante 29 rojos, R1 131/131 y R2 55/55 con R4 encima), tras una revisión adversarial de Codex con
16 hallazgos: los 10 accionables cerrados y con prueba, entre ellos uno BLOQUEANTE (la autorización se estiraba a otra
intención corrigiendo el capital después) y la corrección de un contrato legacy, que era imposible de autorizar. Codex da
GO para instalar el candado APAGADO. Detalle de los 16 en `MIGRACIONES.md`. El candado NO reescribe las cinco puertas: vive en el
mismo trigger diferido de `public.contratos` que R2, así que cubre CRM, portal, RPC antiguas y SQL directo a la vez.
Con la política en `observacion` se comporta igual que R2; con `enforcement` rechaza (`P0410`) toda tasa distinta a la
resuelta sin autorización viva para la misma huella, que consume de un solo uso. `public.crear_contrato` NO se toca a
propósito (su texto difiere entre banco y producción por trabajo de otra sesión). El upgrade ya declara su origen (D2):
la puerta del alta lo publica en un GUC transaccional. Aplicar R4 **no enciende nada**; enciende Gerencia desde
Configuración → Política de rentabilidad, y apagarlo es publicar otra versión, sin migración. Hallazgo del oráculo de
R2 sobre R4: la tarjeta de Gerencia solo miraba filas `observacion` y se habría quedado ciega al encender el candado;
R4 la amplía. Detalle en `MIGRACIONES.md` (20260907093000).
**Goal:** Que ninguna vía (CRM, portal, RPC antigua, llamada directa) pueda crear o corregir un contrato con
una tasa distinta a la resuelta salvo autorización válida, de un solo uso, del mismo fingerprint.
- R4.1 Las RPC ignoran la tasa del navegador y usan la resuelta; con autorización, exigen
  base <= tasa <= tope y consumen dentro de la misma transacción (lock por solicitud).
- R4.2 Trigger BEFORE INSERT/UPDATE en `public.contratos`: rechaza tasa que no coincida con el ledger.
- R4.3 Suite adversarial: bypass directo, doble aprobación, doble consumo, auto-aprobación, upgrade sobre
  contrato ajeno o cerrado, fingerprint cambiado tras aprobar, carrera concurrente, solicitud vencida.
- R4.4 Activación por interruptor (`politica.modo = enforcement`), 48 h de observación, rollback = volver a
  `observacion` sin migración.
- Hecho cuando: la suite pasa en banco y producción, y 48 h sin altas rechazadas por error.

## Estimación

| Fase | Esfuerzo | Calendario |
|---|---|---|
| R0 | hecha | 2026-09-06 |
| R1 | hecha | 2026-09-06 (producción) |
| R2 | servidor en producción 2026-09-06 17:29 Lima · 7 días de datos → informe ~13/09 | semana 2 |
| R3 | 4–5 días | semana 3 |
| R4 | 2 días + 48 h | semana 4 |

Si solo se hace una fase este mes: R1 + R2. Dan visibilidad real del margen cedido sin riesgo.

## Fuera de este plan (pendiente aparte)

Catálogo de productos de inversión (Configuración → Productos): existe la pantalla y las tablas, pero hay 0
productos publicados y todo contrato entra por el puente legacy. Cuando negocio defina productos reales, el
techo autorizable podría salir de la condición del producto y se cerraría el puente
(`crm.cerrar_altas_legacy_productos`, irreversible). Miguel decidió el 06/09 que eso NO es parte del flujo
de rentabilidad; queda como trabajo independiente.

## R2.3 — qué mirar en una semana (a partir del 13/09/2026)

La tarjeta «Rentabilidad: margen cedido» del Resumen de Gerencia (o `crm.observacion_rentabilidad_fn` directamente) con
horizonte 7 días: cuántos contratos se apartaron de la base, cuánto margen se cedió (PEN/USD, en el plazo), quién lo cedió,
y los casos sin regla (sobre todo upgrades con origen ambiguo: dato para dimensionar el selector de origen de R3).
Si `coherente = false`, mirar primero `altas_sin_observar` y `sondas`. Con esos números se decide si D1 y D4 se mantienen tal
cual y se arranca R3. Dato previo de producción: 218 altas en los 30 días anteriores, 147 con tasa ≠ 15%.

