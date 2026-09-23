# Conversión: quién discrepa de verdad (medido, 22/09/2026)

Las doce puertas de la conversión dan hoy **el mismo número por casualidad**:
`crm.periodos_cerrados` está vacío, así que no hay deuda de anulación viajando
entre meses. El día que se selle el primer mes, ese empate se rompe.

Para saber **quién** se rompe, el 22/09 se plantó una **deuda de 2 puntos** en
producción dentro de una transacción que termina en `raise` (no escribe nada) y
se miró, para el MISMO analista y el MISMO mes, quién cambia y quién no.

| Puerta | ¿tasa? | De dónde | SIN deuda → CON deuda | ¿Discrepa? |
|---|---|---|---|---|
| #4 `metricas_conversiones_fn` | sí | vivo | 4,24 % → 4,24 % | 🔴 SÍ |
| #5 `metricas_distribucion_leads_v3_fn` | sí | vivo | 4,24 % → 4,24 % | 🔴 SÍ |
| #6 `metricas_conversiones_equipo_fn` | por vendedor | vivo | 6 → **6** | 🔴 SÍ |
| #7 `cumplimiento_metas_fn` | numerador | oficial CON ajuste | 6 → **4** | no |
| #8 `cumplimiento_metas_sin_cartera_fn` | sí | oficial CON ajuste | 6 → **4** | no |
| #9 `series_comerciales_fn` | sí | delega en la oficial | — | no |
| #10 `metricas_multiempresa_fn` | sí | vivo | **no se puede llamar** | ⚪ apagada |
| #11 `resumen_cartera_fn` | **no** | vivo | cuenta cierres, sin ponderar | no |
| #12 `cerrar_periodo` | escribe la foto | bruto, correcto | — | no |

La oficial (`crm.conversion_mensual_fn`), para ese analista: **6 → 4**.

## Las dos cosas que leer el código NO daba

**1. La #7 no tiene ningún camino bruto.** Su cuerpo usa
`private.conversion_mensual_por_vendedor`, que sirve el BRUTO, y no se le ve un
`private.conversion_con_ajuste` por ninguna parte. Yo llegué a darla por
sospechosa leyéndola. **La medición la absuelve:** con la deuda puesta publica
4, y cada fila lleva `ajuste: {pendiente: 2}` — igual que la #8. El ajuste entra
por otro camino. Regla: para esta familia de preguntas, **medir gana a leer**.

**2. La #10 está detrás de una bandera apagada.** Arranca con
`if not coalesce((select activo from crm.multiempresa_flags where nombre='metricas_multiempresa_sombra'), false)`
y responde `P0409 · El informe multiempresa está en preparación`. Ninguna
pantalla la ve. Sigue siendo la única que calcula por su cuenta **y** no llama a
la mensual — hay que arreglarla **antes de encender esa bandera**, no antes que
las de gerencia.

## El orden con el front no es el mismo para las tres

Medido sobre el bundle vivo (`build-20260922T221442353Z` = `7d65fcdb484f`, que
**no** contiene `c2c9274b`):

- #4 y #6 validan su bloque `nucleo` con **`v.object`** → ignoran claves que no
  conocen → el servidor puede entrar antes que el front.
- #5 valida `resumen.conversion` con **`v.strictObject`** → una clave
  desconocida **tumba el payload entero** y la pantalla de distribución se queda
  sin datos.

Por eso la migración de la #5 lleva **pestillo**: su preflight se niega a entrar
sin un `set local crm.ola1_front_publicado = 'si'` escrito a mano después de
comprobar `version.json` → manifiesto → `merge-base`.

Relacionado: [[Gestion Diaria F4 - SQL OFF publicado y frontend pendiente (2026-09-22)]]
