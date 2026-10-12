---
tags: [crm, facturacion, atribucion, baja-analista, migracion]
fecha: 2026-10-09
estado: aplicada en producción
---

# Baja de analista: su capital pasa al responsable actual (09/10/2026)

**✅ APLICADA EN PRODUCCIÓN el 09/10/2026** — migración `20261009200000_crm_baja_analista_heredero`, registrada.
PR [#233](https://github.com/avanza-digital/avancecorp-crm/pull/233) **fusionada** el 09/10 (`f3efe078` en `avancecorp/main`).
`main` local al día (`f3efe078`), conservando los cambios sin commit ajenos de `MIGRACIONES.md`. Detalle técnico: `CRM-Avance-Corp/supabase/scripts/baja-analista-heredero/LEEME.md`.

## El problema

Facturación de octubre mostraba capital a nombre de **Pierina** (desactivada el 01/09). El contrato 2026-01-001570
(renovación del 07/10, registrada por Betzabeth) renueva un upgrade de Pierina de abril (000373), y la regla de adopción
por cadena ([[Atribucion de upgrades y sus renovaciones (decision 2026-08-30)]]) le daba la línea a quien hizo el upgrade
sin mirar si seguía activa. La baja (`crm.fijar_membresia_activa_fn`) mueve leads, tareas y clientes, pero no la
atribución de contratos. Diagnóstico previo: [[Cartera - atribucion de Escobar y contrato 001570 (2026-10-09)]].

## La decisión de Miguel

- «Cuando el analista se desactiva ya no debe aparecer más; al que se migra toda su información es el que debe aparecer.»
- «Todo a Betzabeth»: **todos los meses vivos**, también los de antes de la baja. Los meses sellados no se tocan.
- Configurado «a nivel de sistema»: vale para cualquier baja futura, sin corregir contratos a mano.
- Aplicar **antes** del sello de septiembre (cron del 11/10 ~09:20): septiembre se sella ya con la regla.

## La regla

Si el analista al que se cuenta algo (cadena de upgrade incluida) está dado de baja (`crm.equipo.activo = false`) y la
persona tiene un responsable actual distinto y activo, cuenta a ese responsable (contratos: `asesor_perfil_id` del
cliente; cooperativas: `responsable_relacion_id` de la persona). Si no hay responsable activo, no cambia.

Efecto al aplicar: Pierina → **Betzabeth** (36 filas) y **Vladimir** (2); Noelia → **Elizabeth Chiroque** (11, incluidas
4 cooperativas Qorilazo de setiembre, S/ 88.000); 001570 → Betzabeth. **Ivett** (3 contratos) se queda: sus clientes no
tienen responsable activo. **Decisión de Miguel (09/10): «déjalos así nomás, que figure Ivette»** (2026-01-000335, 000533 y
000799). Si algún día esos clientes reciben un responsable activo, la regla los pasaría a esa persona sola.

Alcance: Facturación, metas y sello del mes (`capital_episodios`), conversión (solo operaciones de cartera; la conversión
de leads es ledger inmutable y no cambia), métricas de cartera, altas por analista, ficha de Cartera, atribución del
contrato y cooperativas («Mi cartera → En cooperativas» y panel «Por empresa»).

## Lecciones

- **Postgres 17 re-planifica una función SQL llamada desde otra en CADA fila**: la primera versión llevaba el capital de
  setiembre de 15 a 171 ms. Arreglo: ayudantes PL/pgSQL con camino rápido y el valor calculado una vez por fila (lateral).
  Medir SIEMPRE antes/después en producción dentro de una transacción que se deshace (`medir-produccion.sql`).
- `contratos_afectados_por_anulacion` NO debe heredar: compara con la foto del crédito; si heredara, un alta anulada de un
  inactivo se volvería a contar al heredero (lo vio Codex).
- `crm.cierres_externos_fn` está en las exenciones analíticas con huella: tocarla obliga a renovar la exención y resellar.
  El 09/10 `private.assert_analitica_leads_citas()` ya fallaba en producción por tres funciones ajenas sin declarar
  (`crm.gestiones_resumen_fn`, `private.citas_clientes_core`, `private.gestion_diaria_cola_hechos`).

## Pendiente

- ✅ Front PUBLICADO (09/10 ~14:35 Lima): rótulo «heredada» en la ficha del contrato y en el alta de renovación — PR
  [#234](https://github.com/avanza-digital/avancecorp-crm/pull/234), release `crm-20261009T193129Z-9dc0b0874d7c` (commit `9dc0b087`,
  buildId `build-20261009T193128103Z`), preflight OK, smoke OK.
- ⚠️ Hallazgo de pruebas: con el `app/.env` real presente, `npm run check` tumba un proceso de vitest en paralelo
  (`src/screens/gestion-diaria/analista.test.tsx`); sin `.env` y en el CI pasa 399/399. Alguna prueba usa las variables reales.
- ⚠️ CORRECCIÓN 09/10: el `CRM RLS preflight` del CI de la #233 pasó, pero es ESTÁTICO (modo `--preflight`, URLs ficticias, sin red): NO ejecuta la matriz contra una base. `npm run test:rls` real: NOT RUN. Cobertura por rol de la regla: el ensayo sintético (104 casos) del banco Docker. Corrida real del gate → fase 0C del plan de Facturación.

Relacionadas: [[Facturacion - auditoria completa (2026-10-08)]] · [[Contrato de la atribucion por cadena de upgrade (2026-08-30)]] · [[Inicio]]
