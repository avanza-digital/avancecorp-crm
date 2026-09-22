# Sonda de paridad contra PRODUCCIÓN — ejecutada 21/09/2026 11:00 Lima

Corrida vía MCP de Supabase (`execute_sql`, proyecto `dctqcbznekcyxhjujuci`,
sesión `postgres`), solo lecturas, con impersonación de un perfil Gerencia
mediante `set_config('request.jwt.claims', …, true)` dentro de cada sentencia.
Ninguna escritura. Solo agregados: no salió ningún dato personal.

## 0 · Contexto

| | |
|---|---|
| Ahora (Lima) | 2026-09-21 11:00 |
| `crm.periodos_cerrados` | **0 filas — NINGÚN mes sellado** |
| Perfiles de gerencia activos | 2 |

## 1 · Paridad M = R = D (septiembre 2026)

| Lectura | divisor | numerador | pct |
|---|---|---|---|
| Núcleo directo (`private.conversion_episodios`, 01–21/09) | 1170 | 45.2000 | **3.86** |
| **M** `crm.conversion_mensual_fn('2026-09-01')` | 1170 | 45.200 | **3.86** |
| **R** `crm.metricas_conversiones_fn(01/09, 21/09)` | 1170 | 45.200 | **3.86** |
| **D** `crm.metricas_distribucion_leads_v3_fn(01/09, 21/09)` | 1170 | 45.200 | **3.86** |

`cuadra = true`, `paridad_nucleo = 0.000` en R y en D.
Núcleo directo: 1231 llegadas · 49 cierres vivos · 0 anulados en la ventana ·
14 operaciones de cartera que aportan 11.4500.
Sondas de D: `divisor_sin_analista: 57`, `nucleo_sin_ficha: 0`,
`episodios_sin_origen: 0`, `peso_referido: 0.15`.

## 2 · Agosto (mensual vs rango)

| | divisor | numerador | pct | cerrado |
|---|---|---|---|---|
| **M** `conversion_mensual_fn('2026-08-01')` | 802 | 39.100 | **4.88** | `false` |
| **R** `metricas_conversiones_fn(01/08, 31/08)` | 802 | 39.100 | **4.88** | — |

## 3 · Integridad del ledger

| | |
|---|---|
| Leads con etapa `convertido` | 74 |
| Leads con cierre en el ledger | 74 |
| Convertidos SIN fila en el ledger | **0** |
| Ledger sin etapa `convertido` | **0** |
| Cierres sin `resultado_en` | **0** |
| Convertidos sin fecha | **0** |
| Mes de ficha ≠ mes de ledger | **0** |
| Cierres anulados | **1** (mes de cierre: agosto 2026) |
| Operaciones de cartera elegibles | 70 |
| Clientes con varias operaciones el mismo mes | **7** |

## 4 · Puertas de conversión (hipótesis F12, reportada como P0)

| | |
|---|---|
| `inversiones_escritura` activo | **`true`** |
| Miembros del piloto F8 | 4 |
| Solicitudes preparadas con lead | 0 |
| Confirmadas con lead desde el 19/09 | 2 |
| Cierres en el ledger desde el 19/09 | 7 |

## Qué demuestra, y qué no

- **F12 queda REFUTADA con datos reales.** La bandera está encendida y el
  ledger recibió 7 cierres desde el 19/09: la puerta de conversión no está
  cerrada para nadie. Deja de ser un P0.
- **C1, C2 y C4 son mecanismos reales pero LATENTES, no activos hoy.** Las tres
  divergencias necesitan un mes sellado o una deuda que viaje entre meses, y
  hoy no hay ni lo uno ni lo otro: `periodos_cerrados` está vacío (agosto se
  reabrió) y la única anulación pertenece a agosto, que sigue abierto, así que
  se descuenta dentro de su propio mes en las dos lecturas.
- **El día que se vuelva a sellar agosto** (`02-resellar.sql`, pendiente de que
  terminen de cargarlo), M servirá la foto y R/D seguirán recalculando en vivo:
  ahí aparecen las dos verdades. **Esa es la fecha límite del arreglo.**
- **C3 sigue en pie sin necesidad de más datos**: `cuadra=true` y
  `paridad_nucleo=0.000` es exactamente lo que la sonda devuelve siempre, tanto
  si hay divergencia como si no. No detectó nada porque no puede detectar nada.
- **C7 tiene material real**: 7 clientes con varias operaciones elegibles el
  mismo mes, que es justo el caso que el dedupe recorta mal en rangos parciales.
- Lo que la sonda NO dice: nada sobre las pantallas. Todos los hallazgos de
  front siguen verificados solo contra el código.
