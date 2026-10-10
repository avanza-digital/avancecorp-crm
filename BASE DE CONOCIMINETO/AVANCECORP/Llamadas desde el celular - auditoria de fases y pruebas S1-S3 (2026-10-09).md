# Llamadas desde el celular — auditoría de fases y pruebas S1–S3 (2026-10-09)

Estado al 09/10/2026: **45/102 tareas, 2/8 fases** (F1 y F2). C1 activo en producción desde el 07/10. H-WA cerrado
(#232 publicado y probado). Plan, seguimiento y registro: `CRM-Avance-Corp/docs/plans/llamadas-celular/` y
`CRM-Avance-Corp/docs/gestion-diaria/piloto-telefonia/`. Tablero vivo: artifact del plan (ver
[[Llamadas desde el celular - decisiones de Miguel y plan v2 (2026-10-03)]]).

## Lo que encontró la auditoría (solo lectura, 09/10)

- **Tres puertas instaladas sin pantalla:** unir a mano una llamada a un resultado ya guardado (F4.2.4,
  `crm.enlazar_llamada_celular`), el detalle de una llamada (F4.1.2, `crm.llamada_celular_detalle_fn`) y la marca
  «Celular» en «¿Qué hice hoy?» (B6, `crm.actividades_con_llamada_celular_fn`). El servidor ya deja algunas llamadas
  «para unirlas a mano», así que hoy la única salida es registrar dos veces o descartar.
- **Pruebas automáticas prometidas que no existen:** el E2E del circuito y el de F4-c con dobles.
- **Aviso de tratamiento de datos desactualizado** desde el 07/10: hay que corregirlo antes de C2/C3.
- Casi todo F0 y F7 depende de conseguir C2/C3, de decisiones de Miguel o de sesiones cortas con C1.

## Pruebas en C1 del 09/10 (S1–S3)

- **H-ESPERA (encontrado y arreglado):** con una llamada en espera, la macro tomaba el número de quien entraba, no el de
  la llamada hecha. Arreglo solo en MacroDroid (`numero_saliente`, `macrodroid.md` §3c), probado al ignorar, rechazar y
  contestar. **Todo celular nuevo se arma con este cambio.**
- **H-PERMISO (abierto, para Miguel):** si a MacroDroid le quitan el permiso «Registro de llamadas», la llamada se
  pierde sin aviso y la tarjeta de gerencia sigue «Al día».
- PASS: rechazada, «+51» a mano, login con la sesión cerrada, ahorro de energía, ráfaga de 3, hora adelantada
  («Reloj desfasado» y la llamada se une igual). La noche 07→08 la macro siguió viva, pero C1 estuvo ~9 h sin internet.

## Pendientes (tablero de pendientes del proyecto)

| Pendiente | Quién |
| --- | --- |
| Decidir si se programa ya «¿Es este su resultado?» (F4.2.4) | Miguel |
| H-P10 (texto «tuya / de otro analista»): lo arregla su sesión | Miguel |
| H-PERMISO: cómo delatar una llamada perdida por falta de permiso | Miguel |
| Aceptar NO APLICA: doble SIM e internacional; «oculto» a la #14 | Miguel |
| Aviso de tratamiento nuevo para C2/C3 | Miguel · Claude |
| Conseguir C2 y C3 | Miguel · Jhosep |
| Noche 09→10 (tercera), S4 (apagados), «respuesta perdida», repetición de P5 (H-P5) | Jhosep con C1 |
| Renovar MacroDroid gratis cada 3 días (próximo: 12/10 antes de ~15:50 Lima) | Jhosep |
| Contrato y oráculos de F4-e | Claude |

Relacionado: [[Llamadas desde el celular - pruebas de MacroDroid en C1 (2026-10-02)]],
[[Llamadas desde el celular - clientes como objetivo pendiente (2026-10-01)]].
