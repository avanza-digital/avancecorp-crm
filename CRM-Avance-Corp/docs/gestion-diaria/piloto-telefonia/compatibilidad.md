# Matriz de compatibilidad por equipo — piloto F0

Entregable de **F0.4.1**. Una fila por celular; se completa con lo observado en F0.3 (no con lo que dice la documentación). Sin números reales.

| Celular | Marca / modelo | Android | Navegador por defecto | MacroDroid | Número en salientes | Número en entrantes | Número oculto se clasifica como oculto | Fijo / internacional | Abre la PWA (vía que funcionó) | Sobrevive bloqueo / batería / 3 noches | Dirección por variable (Call Outgoing / Incoming) | Notas |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| C1 | Samsung Galaxy A16 (SM-A165M) | 16 | Chrome | Play Store 5.67 (sep. 2026), gratis: se renueva cada 3 días (Pro no durante las pruebas) | PASS: más de 40 salientes con número (29/09–10/10); contra la Edge, 19 llamadas = 19 avisos (07–08/10) | NOT RUN (entrantes bloqueadas; #14) | NO APLICA en salientes (propuesta: a la #14) | Fijo PASS (07/10); internacional NO APLICA (propuesta: Avance no llama al extranjero) | `Open Website` → PASS con «Abrir vínculos admitidos» + dominio (30/09); con el id de la llamada desde el 06/10 | PASS: bloqueo (07/10), batería 7 % (08/10), ahorro de energía (09/10); noches 08→09 y 09→10 PASS, 07→08 macro viva sin internet | Saliente por `en_saliente` + `numero_saliente` (H-ESPERA, 09/10); entrantes no se capturan | Una sola SIM; «Llamada en espera» activa; permisos Teléfono y Registro de llamadas OK; «Suspender aplicaciones sin uso» apagado |
| C2 |  |  |  |  |  |  |  |  |  |  |  |  |
| C3 |  |  |  |  |  |  |  |  |  |  |  |  |

Valores: `PASS`, `FAIL`, `PARCIAL (detalle)`, `NOT RUN (causa)`. En «Abre la PWA» anotar `Open Website`, `Send Intent`, `Chrome (no PWA)` o `no abrió`.

Lectura al cierre (F0.4.3): un `FAIL` en «Número en salientes» en cualquier equipo confirma el riesgo #1 del plan y obliga a evaluar Tasker, app nativa o Knox antes de F1; un `FAIL` en «Abre la PWA» con las dos vías reabre la opción de notificación local y registro desde PC (plan, sección 6, «Dos decisiones separadas»).
