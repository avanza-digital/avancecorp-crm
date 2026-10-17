# Reemplazar inversión — plan por fases (propuesta 17/10/2026)

Estado: **Fase 0 decidida · Fase 1 CONSTRUIDA Y ENSAYADA (17/10/2026), SIN PUBLICAR · checklist 9/9 · Codex r4 PASS.** Migración candidata
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
- [x] 7. auditor-rls y Codex sin P0/P1 abiertos (ver «Revisiones»): Codex r4 PASS.

## Revisiones (17/10/2026)

- **Codex r1** (CHANGES_REQUESTED, 4 P1 + 2 P2): segundo reemplazo mudaba el mes, analista en «quedarme con la otra», acreditación nueva, lead sin enlace, ciclos de candados, permisos del reintento. Todos corregidos con su caso y su mutante.
- **auditor-rls, concurrencia, seguridad y negocio**: sin P0/P1; lo de negocio (cuotas pagadas, duplicado exacto, mes de la venta, origen confirmado, cotitulares) corregido.
- **Codex r2** (CHANGES_REQUESTED, 1 P1 + 2 P2): una cadena A → B → C en la misma transacción saltaba el candado de tasa (B se borraba sin juzgar); cotitulares en «quedarme con la otra»; reintento con origen confirmado. Los tres **se reprodujeron en el banco antes de arreglarlos** (C33–C37 fallaban) y quedaron corregidos. También los huecos que señaló: pago en curso (carrera E4), condición de producto, lead enlazado a otra inversión, dos copias hacia el mismo contrato.
- **auditor-rls sobre el delta r2**: el arreglo del P1 es correcto, sin P0/P1; su P2 (la comparación de cotitulares no ordenaba: `order by 1` dentro de un agregado ordena por la constante) quedó corregido con C35b y su mutante.
- **Codex r3** (acotada al cierre de r2): los tres hallazgos de r2 **CERRADOS**. Abrió 1 P1 en la reversa (decidía si conservar `reemplazada_por` con una foto anterior al candado: un reemplazo confirmado en ese instante perdía su vínculo) y 1 P2 (un mutante quitaba dos defensas a la vez). El P1 se reprodujo con la carrera E5 (la columna se perdía) y se corrigió con un `LOCK TABLE` antes de la primera consulta; el mutante quedó aislado y muere en C33.
- **Codex r4** (mínima, solo el cierre de r3): **PASS**, los dos cerrados, sin P0/P1 nuevos.
- [x] 8. Informe con «¿apta para producción?» y «qué arregla comercialmente» (abajo).
- [x] 9. Este checklist.

## Qué quedó construido (Fase 1)

- Dos puertas: `crm.reemplazar_inversion_fn` (alta nueva con los datos correctos) y `crm.reemplazar_inversion_por_existente_fn` («quedarme con la otra»). Núcleo `private.reemplazar_inversion_avance`; copia con `crm.inversiones_eliminadas.reemplazada_por`.
- La venta conserva el **día de su registro** (también tras varios reemplazos y en «quedarme con la otra»): la fecha nueva solo la muda si cambia el mes y ese mes está abierto y en plazo.
- La tasa aprobada se hereda sin pedirla otra vez: el candado de tasa lo permite solo si en la misma transacción hay copia del reemplazo con la misma tasa (con la política en enforcement, además los mismos datos).
- Pasan al contrato que queda: el origen de capital confirmado (exige Gerencia), los cotitulares, la marca de primera conversión.
- Pruebas: 45 bloques, 43/43 mutantes muertos, 5/5 carreras (E4: pago en curso; E5: reversa a la vez que un reemplazo), regresión de «Eliminar inversión» (24) y «Eliminar lead» (100), test-rls entero (los mismos 15 fallos ajenos antes y después; bloque nuevo 17/17), reversa ejecutada de verdad en el banco, `registrar.sql` probado contra la tabla REAL `supabase_migrations.schema_migrations` que crea la CLI 2.117 en el stack (registra con el md5 del archivo, es idempotente, se niega ante otro contenido y si la migración no está aplicada). Kit en `CRM-Avance-Corp/supabase/scripts/reemplazar-inversion/` (LEEME, reversa, registrar, comprobar, carreras).

## Límites conocidos (no los causa la migración)

- No recupera ventas ya perdidas (Jurado, Gaspar): eso es des-anular, otra decisión (el plan v2 de la rama `crm/conversion-reemplazo-20261016` es la alternativa; choca con [[Capacidad única de conversión de leads (2026-09-03)]]).
- Doble conteo en la tarjeta (P3) y orden del tope de referidos (P3): vienen de antes; documentados.
- Re-acreditar reinicia los relojes de la acreditación: por eso se exige el plazo de carga abierto antes de borrar.
- Las puertas no se sondean con `service_role` fuera de test-rls: la imagen local de Supabase PG17 se cae (bug de plataforma).
- El alta del reemplazo nace con condición de producto «libre» (legacy): con la política en **enforcement**, una inversión de un producto del catálogo con tasa sobre la base pediría autorización otra vez. Hoy producción está en observación y casi todo contrato es legacy: el «catálogo» es el registro de condiciones de cada contrato, uno por contrato.
- «Quedarme con la otra» pone a la que se conserva la fecha comercial de la venta original, aunque esa otra tuviera una corrección manual de Gerencia. Es a propósito (manda el día de la venta), pero lo decide Miguel.
- Hay ~62 ventas cuya acreditación no coincide con `leads.contrato_id` (dato del contexto vivo). Si el lead apunta a OTRA inversión distinta de la que queda, el reemplazo pide revisión. Medir cuántas, solo lectura, con `!`: `select count(*) filter (where l.contrato_id is null), count(*) filter (where l.contrato_id is not null) from crm.conversion_acreditaciones ca join crm.leads l on l.id = ca.lead_id where ca.fuente_tipo = 'contrato' and l.contrato_id is distinct from ca.fuente_id and ca.estado in ('acreditada','mes_sellado','fecha_futura');`

