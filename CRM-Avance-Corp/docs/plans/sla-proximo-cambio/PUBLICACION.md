# Publicación: SLA, «próximo cambio» en el mismo paso

**APLICADA Y VERIFICADA EN PRODUCCIÓN el 16/10/2026**, alrededor de las 15:35 Lima (20:35 UTC).

Solo cambia la base de datos: `private.sla_operacion_autorizada(uuid[],boolean)` calcula `proximo_cambio_en` con `min()` en el
mismo `SELECT` que arma la ventana, en vez de recorrer otra vez todo el JSON. El resultado es el mismo. Con muchas consultas a la
vez baja un 16–19 % la escritura de temporales; la memoria total no cambia. No hay frontend que publicar.

## Fuente

- [PR #311](https://github.com/avanza-digital/avancecorp-crm/pull/311): `preflight`, `cambios`, `app-check` y `verify` PASS.
  Fusionada por Miguel en `afc0fda7` (20:23 UTC).
- Antes de aplicar se comprobó que la migración y el kit de `avancecorp/main` eran idénticos byte a byte a lo revisado.
- Migración: `supabase/migrations/20261016190408_crm_sla_proximo_cambio_en_un_paso.sql`. Kit:
  `supabase/scripts/sla-proximo-cambio/`.

## Aplicación (lanzada por Miguel con «!»)

1. `verificar.sql` ANTES: `cuerpo=ANTERIOR · metadatos=IGUALES · productor=IGUAL · familia SLA=62 · e17a083b3a64459b8f2f888928e03849`.
2. `npx supabase db query --linked --file supabase/migrations/20261016190408_crm_sla_proximo_cambio_en_un_paso.sql`: sin errores.
   Las precondiciones (huella, productor, metadatos y DDL), las poscondiciones y los 3 guardianes del SLA se cumplieron dentro de
   la misma transacción.
3. `verificar.sql` DESPUÉS, en una transacción `READ ONLY`: `cuerpo=MEJORA · metadatos=IGUALES · productor=IGUAL · familia SLA=62 ·
   1adaf6c5708637fd916705cc090a4218`.
4. Fila del índice registrada a mano, con guarda (solo si lo vivo es la mejora y la fila no existía): `20261016190408 ·
   crm_sla_proximo_cambio_en_un_paso · 4 sentencias`.

## Guardianes: idénticos antes y después

| Guardián | Antes | Después |
|---|---|---|
| `assert_sla_nucleo` | OK | OK |
| `assert_cola_v3` | OK | OK |
| `assert_sla_avisos` | OK | OK |
| `assert_f7_piezas_cerradas` | OK | OK |
| `assert_gestion_diaria` | FALLA: `actividades_select` cambió desde la auditoría | igual |
| `assert_analitica_leads_citas` | FALLA: contador sin declarar en `crm.cartera_filtrada_fn` | igual |
| `assert_analista_vigencia` | FALLA: `public.proteger_campos_inmutables()` cambió desde su declaración | igual |

Los tres FALLA ya estaban antes de este cambio y son de otros trabajos. Quedan pendientes de quien los toque.

## Advisors

- Seguridad: 381 hallazgos, igual que la referencia del mismo día (`supervisores-referidos/produccion/advisors-y-limpieza.json`).
  Sin alertas nuevas.
- Rendimiento: 191, frente a 192 de esa referencia (uno menos, ajeno).
- Ningún hallazgo menciona `private.sla_operacion_autorizada`.

## Si hubiera que revertir

Seguir «Si hay que revertir» de `supabase/scripts/sla-proximo-cambio/LEEME.md`: una migración NUEVA con el contenido de
`reversa.sql`, entre dos `verificar.sql`. La fila `20261016190408` del índice no se borra.
