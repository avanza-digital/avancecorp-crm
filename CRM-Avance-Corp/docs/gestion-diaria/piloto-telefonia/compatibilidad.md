# Matriz de compatibilidad por equipo — piloto F0

Entregable de **F0.4.1**. Una fila por celular; se completa con lo observado en F0.3 (no con lo que dice la documentación). Sin números reales.

| Celular | Marca / modelo | Android | Navegador por defecto | MacroDroid | Número en salientes | Número en entrantes | Número oculto se clasifica como oculto | Fijo / internacional | Abre la PWA (vía que funcionó) | Sobrevive bloqueo / batería / 3 noches | Dirección por variable (Call Outgoing / Incoming) | Notas |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| C1 | Samsung Galaxy A16 (SM-A165M) | 16 | Chrome | Play Store (versión por anotar) | PASS preliminar (3/3 con número el 29/09; faltan 10) | PASS preliminar (1 entrante con número, por confirmar) |  |  | `Open Website` → Chrome (no PWA) · `Lanzar app → Avance CRM` → PASS (abre la app en su portada) · `Send Intent` no probado (`chrome://webapks` bloqueado, sin paquete) |  |  | Corporativo; lo usa Jhosep. Android 16 queda fuera del rango 12–15 que cubre la documentación consultada: el número sí llegó en las tres primeras llamadas |
| C2 |  |  |  |  |  |  |  |  |  |  |  |  |
| C3 |  |  |  |  |  |  |  |  |  |  |  |  |

Valores: `PASS`, `FAIL`, `PARCIAL (detalle)`, `NOT RUN (causa)`. En «Abre la PWA» anotar `Open Website`, `Send Intent`, `Chrome (no PWA)` o `no abrió`.

Lectura al cierre (F0.4.3): un `FAIL` en «Número en salientes» en cualquier equipo confirma el riesgo #1 del plan y obliga a evaluar Tasker, app nativa o Knox antes de F1; un `FAIL` en «Abre la PWA» con las dos vías reabre la opción de notificación local y registro desde PC (plan, sección 6, «Dos decisiones separadas»).
