# Baja de analista: su capital pasa al responsable actual del cliente

**Estado: ✅ APLICADA EN PRODUCCIÓN el 09/10/2026** (migración `20261009200000_crm_baja_analista_heredero`, registrada en
`supabase_migrations.schema_migrations` con el texto del archivo, md5 `f05c02e05d90770660bdb63954c08be7`).

## La regla (decisión de Miguel, 09/10/2026)

> «Cuando el analista se desactiva ya no debe aparecer más, y al que se migra toda su información es el que debe aparecer»
> — y eligió **«Todo a Betzabeth»**: vale para TODOS los meses de las lecturas vivas, no solo desde la baja.

1. Se calcula el analista como siempre (incluida la adopción por cadena de upgrade del 30/08).
2. Si ese analista está **dado de baja** (`crm.equipo.activo = false`) y la persona tiene un **responsable actual
   distinto y activo**, cuenta a ese responsable.
   - Contratos: `public.perfiles.asesor_perfil_id` del cliente.
   - Cooperativas: `crm.inversionistas.responsable_relacion_id` de `coalesce(ce.inversionista_id, lead.inversionista_id)`.
3. Sin responsable activo, sin membresía CRM o con analista NULL: no cambia (no se inventa dueño).
4. Los meses SELLADOS (fotos de `crm.cierre_mes_vendedor`) no se tocan. La conversión de LEADS (ledger inmutable) tampoco.

Caso que lo originó: 2026-01-001570 (renovación del 07/10 que registró Betzabeth) salía en Facturación a nombre de Pierina,
desactivada el 01/09, porque renueva un upgrade suyo de abril (000373). Efecto medido en producción al aplicar:
Pierina → Betzabeth (36 filas de capital) y Vladimir (2); Noelia → Elizabeth Chiroque (11, incluidas 4 cooperativas
Qorilazo de setiembre, S/ 88.000). Ivett (3 contratos) se queda: sus clientes no tienen responsable activo.

## Qué cambió en la base

| Pieza | Qué hace |
|---|---|
| `private.analista_dado_de_baja(uuid)` | ÚNICA definición de «dado de baja». |
| `private.heredero_de_baja(uuid, uuid)` | ÚNICA definición de «quién hereda». |
| `private.analista_efectivo_contrato(uuid, uuid)` | cadena de upgrade (o respaldo) + regla de baja. |
| `private.analista_efectivo_cierre(uuid)` | regla de baja sobre una cooperativa. |
| `private.capital_episodios` | Facturación, metas, sello del mes: el efectivo, calculado UNA vez por fila (lateral). |
| `private.conversion_episodios` | solo la pierna de operaciones de cartera. |
| `private.metricas_cartera_por_vendedor` | asesor de cada operación. |
| `crm.altas_nuevas_por_analista_fn` | altas por analista efectivo. |
| `crm.atribucion_contrato_fn` | `analista_id/nombre` = efectivo; `heredada` (nuevo); `adoptada` = la cadena manda de verdad. |
| `private.cartera_f5_fuentes` | `analista_origen_id` (ficha «Analista de la operación»), con mapa `bajas_map`. |
| `crm.cierres_externos_fn` | ámbito, nombres y panel «Por empresa» por el efectivo; el teléfono no cambia. |

**Intacta a propósito:** `private.contratos_afectados_por_anulacion` (compara con la FOTO del crédito; con la regla, un
alta anulada de un inactivo se volvería a contar al heredero). `private.analista_atribuido_cadena` tampoco cambia.

**Exención analítica:** `crm.cierres_externos_fn(date)` está declarada en `private.analitica_leads_citas_exenciones`; la
migración renueva su huella y su razón y resella `private.analitica_lc_sello`. NO llama a
`private.assert_analitica_leads_citas()`: el 09/10 ya fallaba en producción por tres funciones ajenas sin declarar
(`crm.gestiones_resumen_fn`, `private.citas_clientes_core`, `private.gestion_diaria_cola_hechos`).

## Rendimiento (medido en producción, mediana de 5 en caliente)

La primera versión (SQL anidado) llevaba el capital de setiembre de 15 a 171 ms: Postgres 17 re-planifica una función SQL
llamada desde otra en CADA fila. Por eso los tres ayudantes que encadenan son PL/pgSQL con camino rápido (solo los dados de
baja buscan heredero) y `capital_episodios` calcula el efectivo una vez por fila. Final:
capital octubre 7,2 → 6,6 ms · setiembre 16,7 → 19,2 ms · cartera 13,8 → 18,2 ms.

## Archivos

| Archivo | Para qué |
|---|---|
| `generar-cuerpos.py` | FUENTE de los cuerpos: genera migración, reversa y los dos guiones de producción desde `vivo/`; `--verificar` no escribe. |
| `vivo/*.sql`, `vivo/exencion-cierres-externos.json` | cuerpos y fila de exención VIVOS de producción del 09/10 (evidencia; no editar). |
| `ensayo-sintetico.sql` | banco Docker vacío: 104 casos (regla, NULL, cadenas, cooperativas, roles vendedor/supervisor/gerencia, permisos); termina en ROLLBACK. |
| `ensayo-produccion.sql` | la migración al byte terminada en `raise`: muestra qué se mueve y se deshace. |
| `medir-produccion.sql` | tiempos antes/después en la misma transacción, que se deshace. |
| `registrar.sql` | registra la versión en `schema_migrations` (exige las 11 huellas nuevas). |
| `reversa.sql` | restaura los 7 cuerpos y la exención exactos, borra los 4 ayudantes y resella. |

## Cómo se probó

Banco Docker propio (`supabase/scripts/potencial-lead/banco/montar-banco.sh` + volcado de esquema de producción; huellas
crm 333 / private 685 idénticas a producción) con la configuración copiada de producción (`sla_politicas`,
`sla_operacion_control`, `piloto_f8_control`, `conversion_pesos`, exenciones y sello analíticos, producto histórico).
- Aplicar → reaplicar («ya aplicada») → reversa → reversa («ya revertida») → aplicar: PASS; tras la reversa, huellas
  idénticas a producción y exención/sello exactos.
- `ensayo-sintetico.sql`: 104/104. Mutantes (`analista_dado_de_baja` siempre false, `heredero_de_baja` sin herencia,
  `analista_efectivo_cierre` sin regla): 45, 45 y 18 FAIL; el preflight de la migración rechaza cualquier cuerpo ajeno.
- Oráculo de la migración con 1.000 filas sintéticas (3 analistas de baja): PASS.
- Producción (todo deshecho): `ensayo-produccion.sql` y `medir-produccion.sql` antes de aplicar.
- `npm run test:rls:preflight`: **NOT RUN** (sin credenciales en esta sesión). Advisors de seguridad: sin alertas nuevas.

## Aplicar / revertir

```bash
! supabase db query --linked --file supabase/migrations/20261009200000_crm_baja_analista_heredero.sql \
  && supabase db query --linked --file supabase/scripts/baja-analista-heredero/registrar.sql
! supabase db query --linked --file supabase/scripts/baja-analista-heredero/reversa.sql   # reversa
```

## Pendiente (front, aparte)

La ficha del contrato aún no rotula `heredada` («cuenta a Betzabeth por la baja de Pierina»): en los contratos heredados
sin cadena se sigue leyendo «Analista de la venta: Pierina» (es quien la registró). `app/src/data/crm-api.ts` no declara
`heredada` (`v.object` la descarta sin romper nada).
