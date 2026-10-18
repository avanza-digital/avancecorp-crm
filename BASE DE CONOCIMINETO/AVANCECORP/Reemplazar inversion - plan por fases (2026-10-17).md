# Reemplazar inversión — plan por fases (propuesta 17/10/2026)

Estado: **Fase 0 decidida · Fase 1 CONSTRUIDA Y ENSAYADA (17/10/2026), SIN PUBLICAR · checklist 9/9 · Codex final PASS (ningún P0/P1 abierto).** Migración candidata
`20261017162053_crm_reemplazar_inversion.sql` en la rama `crm/reemplazar-inversion-20261017` (worktree
`~/dev/avancecorp-crm-reemplazar-inversion`). Nada aplicado en producción ni en branch.

## Problema (medido en el código del tronco, no en producción)

Eliminar una inversión cargada con error y volver a cargarla hace que la venta del lead se pierda para siempre:

- `crm.eliminar_inversion_fn` (`20261005200945_crm_eliminar_inversion.sql`, decisión D2) anula la venta antes de borrar.
- `private.cierre_anulado(lead)` responde **por lead**, no por fuente: `crm.cierres_avance_anulados.lead_id` es UNIQUE y sin des-anular; desde el 05/10 también mira `crm.inversiones_eliminadas.conversion_anulada`.
- `private.conversion_cierres` pone aporte 0 a todo lead anulado → el contrato nuevo no cuenta aunque se acredite.
- Además, crear un contrato no dispara `private.conversion_sincronizar_lead` (brecha del 06/10, ver [[Conversion - F0 impacto y conciliacion pendiente (2026-09-26)]]).
- La corrección (`crm.actualizar_contrato_con_cuenta_pdf_v3`) sí conserva la venta: ventana de 5 h para el vendedor; la rama admin corrige capital, tasa, fechas, cronograma, modalidad y titulares (`20260809003923`). No cambia cliente ni empresa.

## Diseño técnico propuesto

Puerta nueva `crm.reemplazar_inversion_fn` (DEFINER, actor por `auth.uid()`, roles = `private.eliminar_inversion_roles`). En UNA transacción:

1. Alta del nuevo contrato por el núcleo del alta de siempre, **mismo cliente**, mismo analista atribuido.
2. Re-apuntar el vínculo explícito del lead (`leads.contrato_id`, con `crm.op_privilegiada` porque `private.leads_before_update` lo revierte) y la solicitud/inversión de primera conversión.
3. `private.conversion_acreditar_fuente(lead, 'contrato', nuevo, 'Reemplazo …')`: ya soporta cambiar de fuente y de mes con los candados de `crm.cerrar_periodo`.
4. Eliminar el original con copia por el núcleo de `eliminar_inversion` **sin anular**: rama nueva `reemplazo` con `reemplazada_por`.

Candados en el orden de `eliminar_inversion_fn` (fuente → mes → acreditaciones). Rechaza: mes sellado (conversión o capital), historia propia (D3), dos convertidos sobre la fuente, fuente de otro cliente.

Riesgos a cuidar: huellas de las 5 puertas de escritura vigiladas por `ledger_rentabilidad`; no entrar al censo analítico; PDF (revisión nueva para el nuevo, el original lo conserva en la copia); tasa aprobada por solicitud (heredarla, no volver a pedirla); cortes de capital sellados (16/10).

## Fases (orden de ejecución)

0. Decisiones de Miguel.
1. Servidor apagado + ensayo en banco Docker con esquema de prod; auditor-rls + Codex (LEVEL 3).
2. Pantalla: botón «Reemplazar inversión» en la ficha del inversionista, formulario de alta precargado; maqueta en local para aprobar viendo; e2e Docker.
3. Producción: `!` de Miguel + `/release-crm` + prueba con el perfil vendedor de pruebas.
4. Cooperativas (Prodelco, Qorilazo): misma idea sobre `crm.cierres_externos`.

Diferidos: cambiar de cliente, cambiar de empresa, recuperar ventas ya perdidas (sería des-anular: choca con [[Capacidad única de conversión de leads (2026-09-03)]] y la regla «la anulación es la única puerta»), los 7 leads con contrato colgante del 06/10.

Relacionado: [[Eliminar lead por error de carga - copia auditada (2026-10-15)]].

## Qué ya se arregla con «Corregir» sin perder la venta (leído en el banco con el esquema de producción, 17/10)

| Error | ¿Se corrige hoy? | Quién | Puerta viva |
|---|---|---|---|
| Monto, moneda, tasa, modalidad, tipo de interés, fechas de inicio y vencimiento, titulares | Sí | Admin del portal o Gerencia, en cualquier momento; el analista solo sus contratos y dentro de 5 h | `crm.actualizar_contrato_con_cuenta_pdf_v3` → `public.actualizar_contrato` |
| Cronograma | Sí, solo si ninguna cuota está pagada | Los mismos | ídem |
| Moneda, cuando el contrato tiene cuenta de pago | Bloqueado si la cuenta es de otra moneda | — | `crm.actualizar_contrato_con_cuenta` |
| Número, notas, categoría | Sí, aunque haya cuotas pagadas | Admin o Gerencia | `crm.actualizar_numero_contrato_pdf_v3` |
| Tasa, sin aprobación de Gerencia | Sí | Admin o superadmin | `crm.corregir_tasa_contrato_admin_pdf_v1` |
| Fecha de cierre comercial (mes de la venta) | Sí, si ningún mes implicado está sellado y la fecha no es futura | Gerencia | `crm.corregir_fecha_cierre_comercial` |
| Analista de la venta | Sí, con motivo (deja historia: después ya no se elimina) | Gerencia | `reasignar_analista_contrato` |
| **Cliente equivocado, empresa equivocada, moneda con cuenta de otra moneda, cronograma con cuotas pagadas, contrato renovado/retirado** | **No** | — | El reemplazo cubre la moneda con cuenta de otra moneda y la carga doble; cliente, empresa, cuotas pagadas y renovados quedan fuera de la Fase 1 |

Conclusión: casi todo error de datos se arregla corrigiendo. Lo que no tiene arreglo hoy sin perder la venta es lo que obliga a borrar: moneda con cuenta de otra moneda, o una inversión cargada dos veces. Eso es lo que cubre «Reemplazar inversión». **Cambio del 17/10 (revisión de negocio):** con cuotas ya pagadas el reemplazo **se rechaza** — el contrato nuevo nacería con todas sus cuotas pendientes y se pagarían dos veces. Pasar los pagos al cronograma nuevo es otra decisión de Miguel.

## Decisiones de la Fase 0 (confirmadas por Miguel el 17/10 al fijar el goal de la Fase 1)

1. Reemplazan Gerencia y admin. 2. Cambia todo menos el cliente. 3. Mes sellado → no deja. 4. Si la fecha cae en otro
mes, la venta se muda solo si ese mes sigue abierto. 5. Mismo analista, fijo. 6. La tasa aprobada se hereda.
7. Modo «quedarme con la otra» para inversiones cargadas dos veces.

## Goals por fase

Los textos para `/goal` se entregaron en el chat del 17/10/2026. Cada uno apunta a esta nota y termina con un
informe «¿apta para producción?» + «qué arregla comercialmente», con su checklist marcado aquí.

## Fase 1 — checklist (17/10/2026)

- [x] 1. Anotado qué errores ya se arreglan con «Corregir» (tabla de arriba).
- [x] 2. Migración nueva `20261017162053_crm_reemplazar_inversion.sql` + entrada en `MIGRACIONES.md` («CANDIDATA LOCAL, SIN PUBLICAR»).
- [x] 3. Worktree propio, banco Docker `reemplazo-inv-db` y stack local propio, los dos con el esquema de producción del 17/10.
- [x] 4. Ensayo: conversión y capital del mes iguales antes y después, copia «reemplazada por N°…» y todo o nada (45 bloques PASS).
- [x] 5. Rechazos probados: analista, mes sellado (conversión y capital), upgrade/renovación, dos convertidos, otro cliente; además plazo vencido, cuotas pagadas (también con el pago en curso), demo, duplicado que no es igual (datos o cotitulares), lead enlazado a otra inversión, membresía revocada.
- [x] 6. test-rls entero en verde para lo propio, antes y después: los mismos 15 fallos ajenos del banco; bloque nuevo 17/17.
- [x] 7. auditor-rls y Codex sin P0/P1 abiertos (ver «Revisiones»): revisión consolidada de Codex sobre la versión final completa: PASS, ningún P0/P1 abierto.

## Revisiones (17/10/2026)

- **Codex r1** (CHANGES_REQUESTED, 4 P1 + 2 P2): segundo reemplazo mudaba el mes, analista en «quedarme con la otra», acreditación nueva, lead sin enlace, ciclos de candados, permisos del reintento. Todos corregidos con su caso y su mutante.
- **auditor-rls, concurrencia, seguridad y negocio**: sin P0/P1; lo de negocio (cuotas pagadas, duplicado exacto, mes de la venta, origen confirmado, cotitulares) corregido.
- **Codex r2** (CHANGES_REQUESTED, 1 P1 + 2 P2): una cadena A → B → C en la misma transacción saltaba el candado de tasa (B se borraba sin juzgar); cotitulares en «quedarme con la otra»; reintento con origen confirmado. Los tres **se reprodujeron en el banco antes de arreglarlos** (C33–C37 fallaban) y quedaron corregidos. También los huecos que señaló: pago en curso (carrera E4), condición de producto, lead enlazado a otra inversión, dos copias hacia el mismo contrato.
- **auditor-rls sobre el delta r2**: el arreglo del P1 es correcto, sin P0/P1; su P2 (la comparación de cotitulares no ordenaba: `order by 1` dentro de un agregado ordena por la constante) quedó corregido con C35b y su mutante.
- **Codex r3** (acotada al cierre de r2): los tres hallazgos de r2 **CERRADOS**. Abrió 1 P1 en la reversa (decidía si conservar `reemplazada_por` con una foto anterior al candado: un reemplazo confirmado en ese instante perdía su vínculo) y 1 P2 (un mutante quitaba dos defensas a la vez). El P1 se reprodujo con la carrera E5 (la columna se perdía) y se corrigió con un `LOCK TABLE` antes de la primera consulta; el mutante quedó aislado y muere en C33.
- **Codex r4** (mínima, solo el cierre de r3): **PASS**, los dos cerrados, sin P0/P1 nuevos.
- **Codex, revisión consolidada final** (migración md5 f3d99ce2… + reversa + registro + comprobación + pruebas, todo ya commiteado): **PASS — «Ningún P0/P1 abierto en la versión final revisada»**, sin P2/P3 que condicionen publicar. Límites de cobertura que señala (no defectos): E4 usa una actualización directa de la cuota, no la puerta real de pagos; E5 no detiene el reemplazo antes de escribir su copia.
- [x] 8. Informe con «¿apta para producción?» y «qué arregla comercialmente» (abajo).
- [x] 9. Este checklist.

## Qué quedó construido (Fase 1)

- Dos puertas: `crm.reemplazar_inversion_fn` (alta nueva con los datos correctos) y `crm.reemplazar_inversion_por_existente_fn` («quedarme con la otra»). Núcleo `private.reemplazar_inversion_avance`; copia con `crm.inversiones_eliminadas.reemplazada_por`.
- La venta conserva el **día de su registro** (también tras varios reemplazos y en «quedarme con la otra»): la fecha nueva solo la muda si cambia el mes y ese mes está abierto y en plazo.
- La tasa aprobada se hereda sin pedirla otra vez: el candado de tasa lo permite solo si en la misma transacción hay copia del reemplazo con la misma tasa (con la política en enforcement, además los mismos datos).
- Pasan al contrato que queda: el origen de capital confirmado (exige Gerencia), los cotitulares, la marca de primera conversión.
- Pruebas: 45 bloques, 43/43 mutantes muertos, 5/5 carreras (E4: pago en curso; E5: reversa a la vez que un reemplazo), regresión de «Eliminar inversión» (24) y «Eliminar lead» (100), test-rls entero (los mismos 15 fallos ajenos antes y después; bloque nuevo 17/17), reversa ejecutada de verdad en el banco, `registrar.sql` probado contra `supabase_migrations.schema_migrations` con la FORMA EXACTA de producción (leída en solo lectura el 17/10: `version text not null, statements text[], name, created_by, idempotency_key` único, `rollback text[]`; y `20261017162053` todavía no registrada allí) en el stack (registra con el md5 del archivo, es idempotente, se niega ante otro contenido y si la migración no está aplicada). Kit en `CRM-Avance-Corp/supabase/scripts/reemplazar-inversion/` (LEEME, reversa, registrar, comprobar, carreras).

## Límites conocidos (no los causa la migración)

- No recupera ventas ya perdidas (Jurado, Gaspar): eso es des-anular, otra decisión (el plan v2 de la rama `crm/conversion-reemplazo-20261016` es la alternativa; choca con [[Capacidad única de conversión de leads (2026-09-03)]]).
- Doble conteo en la tarjeta (P3) y orden del tope de referidos (P3): vienen de antes; documentados.
- Re-acreditar reinicia los relojes de la acreditación: por eso se exige el plazo de carga abierto antes de borrar.
- Las puertas no se sondean con `service_role` fuera de test-rls: la imagen local de Supabase PG17 se cae (bug de plataforma).
- El alta del reemplazo nace con condición de producto «libre» (legacy): con la política en **enforcement**, una inversión de un producto del catálogo con tasa sobre la base pediría autorización otra vez. Hoy producción está en observación y casi todo contrato es legacy: el «catálogo» es el registro de condiciones de cada contrato, uno por contrato.
- «Quedarme con la otra» pone a la que se conserva la fecha comercial de la venta original, aunque esa otra tuviera una corrección manual de Gerencia. Es a propósito (manda el día de la venta), pero lo decide Miguel.
- Hay ~62 ventas cuya acreditación no coincide con `leads.contrato_id` (dato del contexto vivo). Si el lead apunta a OTRA inversión distinta de la que queda, el reemplazo pide revisión. Medir cuántas, solo lectura, con `!`: `select count(*) filter (where l.contrato_id is null), count(*) filter (where l.contrato_id is not null) from crm.conversion_acreditaciones ca join crm.leads l on l.id = ca.lead_id where ca.fuente_tipo = 'contrato' and l.contrato_id is distinct from ca.fuente_id and ca.estado in ('acreditada','mes_sellado','fecha_futura');`


## Fase 2 — la pantalla · checklist (17/10/2026)

Rama `crm/reemplazar-inversion-pantalla-20261017` (worktree `~/dev/avancecorp-crm-reemplazar-inversion`), SIN publicar y
SIN push. Decisiones de Miguel del 17/10: maqueta «Aprobada, constrúyela»; el mes antes de confirmar lo calcula el
servidor con la MISMA regla que el reemplazo (migración nueva `20261017211313`, la de la Fase 1 no se tocó).

- [x] 1. Maqueta local a escala real (`ui-playground/reemplazar-inversion.html`: diálogo de 1120 px, letra de 14 px, Plus Jakarta Sans, con selector de rol y de respuesta del servidor). Se escribió a las 15:55 y se abrió en la pantalla de Miguel con `open` a las 15:57 (hora de Lima). Miguel la aprobó viéndola: «Aprobada, constrúyela», a las 16:04. Medida después en el navegador (Playwright, 1440×900, devicePixelRatio 1), con el diálogo abierto: 1120 px de ancho, sin `transform` ni `zoom`, letra de 14 px. Es escala 1:1. A las 20:27 se volvió a abrir en su navegador y Miguel confirmó haberla visto a tamaño real: «confirmo maqueta». Además, la rama se creó desde `main` en `a1ca4983` (con la Fase 1) a las 15:50, según el reflog.
- [x] 2. Worktree, banco Docker `reemplazo-inv-db` y stack local propio (API 56521) con las dos migraciones; prueba real contra el servidor: reemplazo correcto (original borrada, mismo N°, copia «reemplazada por»), «quedarme con la otra» (la distinta rechazada con el mensaje del servidor, la igual aceptada), cuotas pagadas (aviso real y botón inactivo).
- [x] 3. Llamadas solo por `crm-api.ts` (`vistaPreviaReemplazo`, `reemplazarInversion`, `reemplazarInversionPorExistente`), tipos regenerados con las 3 puertas; ninguna pantalla lee tablas.
- [x] 4. `app/CLAUDE.md` (gate de realidad y accesibilidad) + revisor-a11y: 4 pasadas; la última, PASS sobre las correcciones (su único P3, no robar el foco tras reintentar, también corregido con test y mutante).
- [x] 5. `npm run check` en verde (7131 tests, código final).
- [x] 6. E2E Docker en verde: reemplazo correcto (1440, 1366×768 y 390), «quedarme con la otra», mes cerrado, cuotas pagadas y 4 combinaciones de rol (los que no pueden no ven el botón) — 10/10 sin reintentos. E2E completo sobre el código final, con la máquina libre: **456 PASS, 0 fallos, 0 inestables** (26 omitidos). Una corrida anterior, con la máquina cargada, había dado 5 inestables que, solas, pasaron 30/30.
- [x] 7. Codex sin P0/P1 abiertos: r1 CHANGES_REQUESTED (1 P1 + 3 P2, todos corregidos), **r2 PASS** («sin hallazgos obligatorios»); sus dos P3 también corregidos.
- [x] 8. Informe con «¿apta para producción?» y «qué arregla comercialmente» (abajo).
- [x] 9. Este checklist.

### Fase 3 en curso: servidor EN PRODUCCIÓN (17/10/2026)

Lo aplicó Miguel con «!» y `db query --linked --file`, por PR #322 (`main` local `8274134e`). Horas de Lima, según el registro de la sesión:
- [x] Fase 1 `20261017162053`: migración a las 20:08:38 → `registrar.sql` a las 20:08:58 → comprobación a las 20:11:58, `APTA`.
- [x] Fase 2 `20261017211313`: migración a las 20:12:26 → `registrar.sql` a las 20:12:40 → comprobación a las 20:14:28, `APTA`.
- `vigia_sin_pendientes` dio false en las dos comprobaciones. Es informativo: son pendientes ajenos de antes; lo nuestro lo cubre `fuera_del_censo` = true.
- [ ] Fusionar la PR #322 y traer `avancecorp/main` al `main` local, para que los dos apunten al mismo commit.
- [ ] `/release-crm`, con preflight contra lo vivo. Hasta entonces la pantalla publicada no llama a estas puertas.
- [ ] Probar el reemplazo y el PDF del contrato nuevo con el perfil vendedor de pruebas.

### Revisiones (Fase 2, 17/10/2026)

- **Codex r1** (migración + kit + pantalla, evidencia transcrita): CHANGES_REQUESTED.
  - P1: se podía confirmar con el mes de la fecha ANTERIOR (respiro de 350 ms + respuesta anterior en pantalla). Ahora confirmar exige un mes calculado para lo que se envía, y se revalida al enviar.
  - P2: la reversa no veía llamadas en MAYÚSCULAS a los ayudantes.
  - P2: un accesorio mal formado del acuse convertía un reemplazo hecho en error.
  - P2: el kit podía declarar «16/16» sin haber probado (falta de contraseña).
  - Todos corregidos, con prueba que los detecta (mutante).
- **Codex r2**: PASS. Dos P3, corregidos: los ensayos de la reversa distinguen error de infraestructura (salida 3) y se registra un bloque `conversion` mal formado.
- **revisor-a11y**:
  - 1.ª pasada: P1, el formulario se desmontaba al ir a «quedarme con la otra» y volver, y el resumen y el mes quedaban viejos. Además, dos títulos de diálogo, acciones antes del motivo, parpadeo del aviso de cuotas y contraste.
  - 2.ª pasada: P2, la pista prometía que bastaba el motivo cuando faltaba la cuenta. Más P3: Enter en un campo confirmaba el reemplazo (el e2e lo probó con un mutante), caso sin candidatas, categoría fija como campo de solo lectura.
  - 3.ª pasada: P2, «Reintentar el cálculo» se desmontaba al pulsarlo.
  - 4.ª pasada: PASS.
- **Riesgo anterior a esta tarea, sin tocar:** el formulario de alta compartido deshabilita su envío durante CUALQUIER relectura de cuentas (`isFetching`). Al volver de otra ventana con el foco en el botón, el foco puede caer a `<body>`. Pasa igual en el alta suelta.

## Informe de la Fase 2

**¿Apta para producción? Sí, en cuanto se publique la Fase 1.** Se publica con el `!` de Miguel en este orden:
1. Migración de la Fase 1, su `registrar.sql` y su `comprobar-tras-aplicar.sql`.
2. Migración `20261017211313`, su `registrar.sql` y su `comprobar-tras-aplicar.sql` (debe dar `APTA`).
3. `/release-crm`.

No se aplicó nada en producción ni se publicó el CRM.

Queda por probar en la Fase 3, con el perfil vendedor de pruebas, el PDF del contrato nuevo: no se pudo en local porque el runtime de Edge Functions estaba apagado.

**Qué arregla comercialmente.** Gerencia y admin corrigen una inversión mal cargada (capital, tasa, fecha, número o cuenta) o una carga doble desde la ficha del inversionista, **sin perder la venta del lead**. Hoy «eliminar y volver a cargar» la anula para siempre.

Antes de confirmar ven:
- en qué mes queda la venta, con la misma regla que usa el servidor;
- si se muda de mes;
- si el contrato tiene cuotas pagadas (294 de 514 en producción el 17/10). En ese caso se avisa al abrir y no se deja seguir.

Al terminar, la analista conserva su venta y el aviso dice «reemplazada por N°…» con el mes real.

### Qué quedó construido (Fase 2)

- **Servidor (migración nueva `20261017211313_crm_reemplazar_inversion_vista_previa.sql`, md5 `64274e14…`):** tres ayudantes INVOKER (`private.reemplazo_dia_registro_venta`, `private.reemplazo_fecha_comercial`, `private.contrato_tiene_cuotas_pagadas`) que usa el núcleo del reemplazo (parcheado por 3 anclas: huella `541ce30f…` → `b6af7422…`) y la puerta de solo lectura `crm.reemplazar_inversion_vista_previa_fn` (mes resultante, si se muda, si Gerencia corrigió la fecha, si hay cuotas pagadas). Kit en `CRM-Avance-Corp/supabase/scripts/reemplazar-inversion-vista-previa/` (probar, mutantes, reversa, registrar, comprobar).
- **Pantalla:** botón «Reemplazar inversión» junto a «Eliminar inversión» (admin del portal; venta de un lead, además Gerencia). Diálogo en tres columnas: la original (cliente y analista fijos), «La correcta» (el formulario de alta de siempre, PRECARGADO e incrustado) o «La que se conserva» (lista de las del mismo cliente con «Igual a la original» / «Distinta: …»), y «Antes de confirmar» (mes del servidor, aviso de cuotas pagadas al abrir, cambios, motivo obligatorio, acciones al final). Confirmar exige un mes calculado PARA lo que se envía. Al terminar: ficha refrescada, aviso «… reemplazada por N° …» con el mes real, PDF del contrato nuevo como en un alta.
- **Gate de realidad (producción, solo lectura, 17/10):** banderas `resolver_en_puertas`, `ficha_360_neutral` e `inversiones_escritura` en true; 916 fuentes, 0 sin conciliar; 514 contratos Avance «nuevo» vigentes, **294 con cuotas pagadas** (por eso el aviso sale al abrir, antes de llenar nada).
- **Pruebas:** batería de la Fase 1 45/45 con el núcleo nuevo + vista previa 12/12 + candado de la reversa (mayúsculas/comillas); 16/16 mutantes (con corrida base obligatoria); carreras E1–E4 con el núcleo nuevo; reversa probada en el banco (Fase 1 APTA); test-rls sin fallos nuevos; vitest del diálogo, del formulario incrustado y del módulo cliente; e2e con mutantes (Enter en un campo no confirma; sin desplazamiento anidado en celular).

### Límites conocidos (Fase 2)

- Entre la vista previa y el reemplazo, una corrección comercial concurrente podría mover el mes: el aviso final dice el mes REAL que devolvió el servidor. Cerrarlo del todo pediría que las puertas reciban el mes esperado (cambio de contrato: migración nueva).
- «Quedarme con…» se activa aunque la elegida sea «Distinta»: la pantalla lo advierte y el servidor la rechaza con su mensaje (el servidor decide).
- PDF del contrato nuevo: mismo camino que un alta normal; no se probó en local (runtime de Edge Functions apagado). Probarlo en la Fase 3 con el perfil vendedor de pruebas.
- La reversa no ve una llamada a los ayudantes armada con SQL dinámico (EXECUTE con texto concatenado): revisar a mano antes de revertir.
- Orden para publicar (Fase 3, Miguel con `!`): Fase 1 (migración → registrar → comprobar) → esta migración → su `registrar.sql` → su comprobación `APTA` → `/release-crm`.
