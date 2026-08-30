# Contrato de la sanción de anulación (ATR-4, 2026-08-31)

Contrato técnico previo, estilo F4/F6/ATR. **La regla la firmó Miguel el 31/08: «solo la
conversión, siempre»** — una anulación baja la conversión del analista por igual con mes abierto o
sellado, y **el capital no se toca jamás: ni el del analista, ni el de la empresa**. (Eligió esta
opción frente a «como está hoy, por calendario» y «conversión y capital siempre».)

## La foto REAL de hoy (medida 31/08 — corrige la del 29/08)

| Escenario | Conversión | Capital analista | Capital empresa |
|---|---|---|---|
| Coop anulada, mes ABIERTO | baja | **baja** (−S/ 200 000 medido) | **baja** |
| Coop anulada, mes SELLADO | baja (ajuste al vivo) | **baja en el sello siguiente** (deuda) | **baja** (lente) |
| Avance anulado, mes ABIERTO | baja | **baja** (neutralización) | intacto |
| Avance anulado, mes SELLADO | baja (ajuste al vivo) | **baja en el sello siguiente** (deuda) | intacto |

⚠️ Lo del 29/08 («sellado solo quita conversión») describía el DEFECTO que la migración
`20260829182800` mató ese mismo día: desde entonces el sellado también cobra capital vía
`crm.ajustes_mes_cerrado` → `saldar_ajustes`. Y la coop anulada queda `medida='nula'` en el núcleo
→ desaparece del AUM de la empresa en `metricas_capital_mes_fn`, contradiciendo la regla escrita
«una anulación NO elimina capital de la empresa».

## Lo que la ATR-4 deja (estado objetivo)

Todo escenario: **solo la conversión baja** (mes abierto: recálculo; sellado: ajuste del numerador
al mes vivo, como hoy). El capital del analista queda en su producción/podio; el capital de la
empresa queda en el AUM. La anulación sigue dejando su rastro completo (actividades, anulado_en,
cierres_avance_anulados, retroceso de etapa).

## Los 4 puntos de bisturí (todo es LECTURA, ningún trigger)

1. `private.produccion_mes_por_vendedor` — retirar la CTE `neutralizados` + el `case → null` de
   `contratos_confirmados` (camino avance/mes abierto) y el `and not ce.anulado` de
   `externos_confirmados` (camino coop/mes abierto).
2. `private.registrar_ajuste_si_mes_cerrado` — las dos ramas de `piezas` dejan de calcular capital
   (`capital_pen=0, capital_usd=0, detalle=[]`); el numerador de conversión queda como está (F6.c,
   el episodio manda). ⚠️ el guard `if v_numerador <= 0 and v_pen = 0 and v_usd = 0 then return
   null` hoy protege el caso «no valía nada» — revisarlo para que una anulación con numerador 0 y
   capital 0 siga registrando el rastro correcto (o devolviendo null POR DISEÑO declarado).
3. `private.capital_episodios`, pierna cooperativa — la anulada VUELVE a `medida='stock'` con su
   monto real (el capital existe); conserva `estado='anulado'` y el flag `anulado=true` para quien
   quiera distinguirla. Con eso el AUM de la empresa y el analista la conservan sin tocar lentes.
4. `private.contratos_afectados_por_anulacion` — queda SOLO informativa (payload/afecta_cuota y
   retroceso de etapa). El filtro `c.creado_por = q.acreditado_a` se corrige a la ATRIBUCIÓN
   EFECTIVA (`coalesce(analista_atribuido_cadena(c.id), analista_cierre_id)`) para que el aviso
   diga la verdad — NO para quitar capital (ya no quita nada). `afecta_cuota` pasa a significar
   «afecta la conversión».

## Guardianes y re-sellos obligados

- Censo F6.a: `contratos_afectados_por_anulacion`, `produccion_mes_por_vendedor` y
  `registrar_ajuste_si_mes_cerrado` están EXENTOS CON HUELLA (normalizada lower+sin comentarios) →
  **re-sellar las 3 exenciones + el sello agregado** (plantilla: `20260830140000:209-227`).
- `capital_episodios` no debe ganar `count(`/`sum(1)` (postflight anti-conteos).
- Pines del mundo post-ATR-2 (el preflight de ATR-4 debe esperar): capital `90f1d8c2…` (el de
  ATR-2), producción `af6794…`, registrar_ajuste `aae02e…`, cerrar_periodo `cefe29…`,
  cumplimiento `5c12bc…`, conversion_episodios `71213a…`, lentes/ficha las de ATR-3a.
- Oráculos: conversión ANTES=DESPUÉS en todo (la sanción de conversión no cambia) · capital del
  analista y AUM: nueva = vieja + LO ANULADO re-aparecido (delta declarado y medido: hoy 1 coop
  anulada de S/ 200 000 — re-medir al escribir) · ensayo de anulación sintética deshecha (avance y
  coop, abierto y sellado) · foto del sello estable.

## Orden y calendario

**Se ESCRIBE tras publicar ATR-2 (12/09+)**: ATR-4 re-modela `produccion` y la pierna coop del
MISMO núcleo que ATR-2 re-modela — apilar variantes sin publicar del mismo cuerpo repite la trampa
de ordenación (P0 del pin bivalente). El primer sellado real (10/09) pasa con las reglas de hoy;
las deudas de capital ya registradas en `ajustes_mes_cerrado` ANTES de ATR-4: decidir en la fase si
se saldan (regla vieja, última vez) o se condonan (regla nueva retroactiva) — pregunta para Miguel
al escribirla.

Relacionado: [[Contrato de la atribucion por cadena de upgrade (2026-08-30)]] ·
[[Atribucion de upgrades y sus renovaciones (decision 2026-08-30)]]
