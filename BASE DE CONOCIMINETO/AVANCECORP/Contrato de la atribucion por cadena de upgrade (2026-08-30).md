# Contrato de la atribución por cadena de upgrade (2026-08-30)

Contrato técnico previo a la implementación, al estilo de [[Contrato de la capa semantica - Capital (F4, 2026-08-29)]].
Fija la semántica ANTES de escribir la migración. Origen: [[Atribucion de upgrades y sus renovaciones (decision 2026-08-30)]],
con las **4 respuestas de Miguel del 30/08 por la noche**.

## Las 4 reglas (decisión + respuestas firmadas)

1. **Venta nueva** → cuenta a quien la registra (`contratos.analista_cierre_id`, F3). Sin cambio.
2. **Renovación de un cliente normal** → cuenta al analista **dueño** del cliente
   (`operaciones_cartera.vendedor_id`, congelado al insertar). Sin cambio.
3. **Upgrade** → cuenta al **analista del selector «Analista de la venta»** del contrato de upgrade
   (= `analista_cierre_id`), NO al dueño del cliente. **Cambia.**
4. **La renovación de ese upgrade** (y las renovaciones sucesivas de esa cadena) → cuenta al
   **mismo analista que hizo el upgrade**. Adopción por **LÍNEA**: el upgrade adopta ESE contrato y
   su cadena hacia adelante. **Cambia.**

## Los cuatro amarres de las respuestas

- **Adopción por LÍNEA, no por cliente:** `perfiles.asesor_perfil_id` **jamás cambia por un upgrade**.
  El cliente sigue viendo a su analista en la app; las demás líneas del cliente y sus renovaciones
  siguen contando al dueño.
- **«Quien lo hace» = el del selector**, no quien digita: una administrativa puede registrar el
  upgrade de María a nombre de María. `creado_por` sigue siendo el hecho de quién tecleó.
- **Incluye agosto:** el mes abierto se re-atribuye ANTES del primer sellado real (10/09, 09:20 Lima).
  Los meses ya sellados son foto inmutable y NO se tocan (append-only + lectura de foto + sin reabrir).
- **Los dos podios (decisión explícita):** `public.directorio_ranking_analistas` (Portal) **se queda
  con la regla vieja** — acredita al `asesor_perfil_id` VIVO del cliente. El ranking del CRM acredita
  por la atribución de cadena. Son criterios distintos A PROPÓSITO; nadie debe «arreglar» esa
  diferencia sin decisión de Miguel.

## Dónde vive la regla: en la LECTURA (una sola pieza)

`private.analista_atribuido_cadena(p_contrato_id uuid) returns uuid` — STABLE, ACL solo postgres.

- Camina la cadena hacia atrás: contrato → `crm.operaciones_cartera.contrato_nuevo_id` →
  `contrato_origen_id` → … (CTE recursiva, tope 100 de cinturón; los ciclos son imposibles:
  `contrato_nuevo_id` es UNIQUE y hay índice único sobre `contrato_origen_id`).
- Si la **cabeza** de la cadena es `categoria='upgrade'` → devuelve el `analista_cierre_id` **VIVO**
  de esa cabeza (releído en cada llamada).
- Cualquier otra cosa → **NULL**, y el consumidor cae a su regla vieja con `coalesce`.

**La cadena sigue al CONTRATO, no a la persona:** reasignar la CABEZA con
`public.reasignar_analista_contrato` (válvula F3.4, con rastro en `crm.reasignaciones_analista`)
mueve la cadena ENTERA. Reasignar un eslabón intermedio no mueve la atribución — es conducta
declarada, no un bug.

## Semántica de columnas tras el cambio (el ledger NO cambia)

| Columna | Significa | Es |
|---|---|---|
| `operaciones_cartera.vendedor_id` | quién ERA el dueño del cliente al registrar | HECHO histórico (deja de significar «a quién cuenta») |
| `operaciones_cartera.creado_por` | quién digitó | HECHO |
| `contratos.analista_cierre_id` | quién procesó ESA venta (selector F3) | HECHO (inmutable salvo válvula con rastro) |
| «a quién cuenta» | `private.analista_atribuido_cadena` + `coalesce` a la regla vieja | POLÍTICA (un solo sitio) |

**Regla de los 3 puntos:** en cada núcleo parcheado, la columna de atribución, el filtro de
visibilidad (`p_visibles`) y el flag `en_roster` cambian JUNTOS al valor resuelto — si no, María no
vería sus números y el dueño vería números que ya no le cuentan.

## Fallbacks declarados

| Caso | Conducta |
|---|---|
| Cadena rota (renovación `backfill_agosto_2026`, `contrato_origen_id` NULL) | Regla vieja. A propósito. |
| Cabeza-upgrade con `analista_cierre_id` NULL | Regla vieja (no debería existir; el preflight lo mide). |
| Analista de la cabeza inactivo/revocado | La cadena le sigue apuntando (es del contrato). En producción/sello: fuera del cuadro de metas → no cuenta a NADIE (invariante F3.5b, «nunca cae a otro actor»). Remedio: gerencia reasigna la CABEZA. |
| Renovación de renovación de upgrade | La recursión encuentra el upgrade → adopta. |
| La categoría de un eslabón se CORRIGE a 'upgrade' por la puerta de edición | **La adopción más RECIENTE manda**: los descendientes de ese eslabón pasan a su analista (el resolutor busca el PRIMER ancestro upgrade, no el más lejano). Corregir la categoría corrige la adopción. |
| Reasignación de la cabeza DESPUÉS de un mes sellado | La FOTO del mes sellado no cambia jamás (es la que manda para pagos). La pantalla de «Conversiones» en BRUTO — decisión previa de Miguel — es una LENTE VIVA sobre cualquier rango: releerá la atribución nueva también para meses viejos. Lente ≠ foto; declarado, no es un bug. |
| Cliente cambia de dueño después del upgrade | Irrelevante para la cadena; las renovaciones normales siguen al congelado como siempre. |
| Dos operaciones del mismo cliente en el mes | La deduplicación (1 conversión por cliente/mes, primera por fecha) NO cambia: solo cambia quién cobra el episodio ganador. |

## Fase 3: SIN funciones nuevas (decisión de Miguel, 30/08)

El aviso del formulario y la ficha NO crean ninguna RPC nueva: se **amplía la existente**
`crm.atribucion_contrato_fn` con la clave `atribucion_efectiva` (quién cobra de verdad, y si viene
adoptada de una cadena de upgrade). Misma puerta, misma visibilidad, cero funciones fuera de los
núcleos. La única función nueva de todo el tren es el resolutor `private.analista_atribuido_cadena`
— y vive dentro del mundo de los núcleos (private, solo postgres, inalcanzable por la API).

## El interín F1→F2, declarado

Entre la Fase 1 (conversión/cartera) y la Fase 2 (capital/metas), una renovación-de-upgrade contaría
conversión al analista de la cadena pero capital a quien la procese. Riesgo real ≈ 0: los upgrades
nacieron en agosto y ninguno vence antes de octubre; la F2 sale el 11–12/09. Se acepta y queda escrito.

## Dos lentes que recortan por cartera → SE ALINEAN (decisión de Miguel, 31/08)

`crm.metricas_capital_mes_fn` y `crm.metricas_vencimientos_fn` enseñaban el capital recortando por
la CARTERA del que mira (`cli.asesor_perfil_id`). **Decisión firmada: se ALINEAN al analista
resuelto de la cadena** — el contrato de un upgrade aparece bajo quien se lleva la producción, no
bajo el archivador del dueño. **Va en ATR-3** (con su propio oráculo de paridad: solo cambian filas
de cadenas adoptadas). El **Directorio del Portal sigue con la regla vieja** (esa decisión no
cambió): queda como la ÚNICA lente por cartera, declarada.

## Deuda de rendimiento, anotada

El resolutor corre ~2 veces por fila del núcleo en lecturas globales (hoy ~475 contratos, cadenas de
0–2 saltos: trivial, medido en verde contra prod). Al crecer hacia 10k contratos: re-medir
`capital_episodios` con EXPLAIN ANALYZE — va junto a la re-medición pendiente de F4.

## La deuda con nombre (Fase 4, diferida)

`private.contratos_afectados_por_anulacion` busca el contrato por `creado_por`, no por atribución →
si el analista ≠ autor, la sanción por anulación no encuentra el contrato que sí puntuaba.

**✅ La regla de la sanción quedó DECIDIDA (Miguel, 31/08): «solo la conversión, siempre».** La
anulación baja la conversión del analista por igual con mes abierto o sellado; **el capital no se
toca jamás** (corrige la asimetría medida el 29/08: mes abierto quitaba también S/ 200 000 de
capital). La ATR-4 implementa AMBAS cosas en un solo viaje (la regla + el arreglo del `creado_por`),
re-sella la huella F6.a de esa función y lleva oráculo propio sobre `afecta_cuota` y sobre el
capital-que-no-se-mueve. **Se prepara DESPUÉS de publicar ATR-2 (12/09+)**: las dos re-modelan
`capital_episodios` y apilar variantes sin publicar del mismo núcleo repite la trampa de ordenación.

Relacionado: [[fase-3-analista-que-cierra]] · [[El núcleo de capital]] ·
[[PLAN MAESTRO del servidor (P-055) - de la deuda a la capa semantica]]
