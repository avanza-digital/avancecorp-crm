# Registro del piloto F0 — llamadas desde el celular al CRM

Entregable de **F0.4.1**. Se llena a mano durante el piloto (F0.1–F0.4 del plan). **Sin números de teléfono reales ni datos de clientes**: se escribe «lead», «desconocido», «oculto». Cada fila es una evidencia; si una prueba no se hizo, se deja `NOT RUN` con la causa.

## 1. Equipos del piloto (F0.1.1)

| Celular | Marca y modelo | Android | Navegador por defecto | MacroDroid (versión) | Restricciones de batería (qué se cambió) | Fecha de alta |
| --- | --- | --- | --- | --- | --- | --- |
| C1 | Samsung Galaxy A16 (SM-A165M) | 16 | Chrome (predeterminado) | Instalado desde Play Store (versión por anotar) | «Aparecer encima» activado · Batería «No restringido» · autoarranque («apps que nunca duermen»): por confirmar | 29/09/2026 |
| C2 |  |  |  |  |  |  |
| C3 |  |  |  |  |  |  |

## 2. Personas (F0.1.2)

| Rol | Nombre | Celular |
| --- | --- | --- |
| Analista piloto | Jhosep (responsable del piloto; único celular por ahora, se irán sumando más) | C1 |
| Analista piloto |  | C2 |
| Analista piloto |  | C3 |
| Soporte (instala y configura) | Jhosep (configura C1 siguiendo `macrodroid.md`) | — |
| Responsable del registro de incidencias | Jhosep | — |

## 3. Comunicación y consentimiento (F0.1.3)

Texto base del aviso (ajustar con quien revise el tratamiento de datos; plan, sección 15):

> Durante el piloto, una app instalada en tu celular corporativo detectará cuándo termina una llamada y mostrará el número marcado o recibido para comprobar que el CRM podría abrir la encuesta de resultado automáticamente. En esta etapa ningún dato sale del celular. El registro se borra al terminar el piloto. Puedes retirarte cuando quieras avisando a soporte.

| Celular | Aviso entregado (fecha) | Firmado (fecha) | PWA instalada (fecha) | Permisos concedidos (Teléfono · Registro de llamadas · Mostrar sobre otras apps · Batería) |
| --- | --- | --- | --- | --- |
| C1 | No aplica: el celular lo usa el propio responsable del piloto | — | 29/09/2026 | «Aparecer encima» ✓ · Batería «No restringido» ✓ · Teléfono y Registro de llamadas: por confirmar |
| C2 |  |  |  |  |
| C3 |  |  |  |  |

## 4. Línea base — cinco días (F0.2)

Una fila por celular y día. «Desde CRM» = llamadas iniciadas con el botón «Llamar» de la PWA; «Fuera» = desde el marcador, contactos o historial; «Registro» = dónde se anotó el resultado y cuánto tardó (F0.2.2).

| Fecha | Celular | Salientes desde CRM | Salientes fuera | Entrantes de leads | WhatsApp (contactos) | Registro (PC / celular) | Minutos hasta registrar | Capturas en log de MacroDroid | Diferencia con el registro del teléfono (F0.2.3) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |  |  |  |  |

## 5. Pruebas de equipos (F0.3)

| Fecha | Celular | Tarea | Caso (saliente / entrante / atendida / perdida / rechazada / cancelada / oculto / fijo / internacional / doble SIM / bloqueado / batería / noche / reinicio / sin red) | ¿Llegó el número? | ¿Abrió la PWA? (Open Website / Send Intent / Chrome / no abrió) | ¿Quedó en el log? | Resultado (PASS / FAIL / NOT RUN) | Evidencia (captura saneada, nota) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 29/09/2026 18:57 | C1 | F0.3.1 | saliente a contacto interno | Sí: número y nombre del contacto en el trigger y en la notificación | Chrome (no PWA), vía «Open Website» | Sí: `F0 <número>` | PASS número · FAIL apertura PWA (vía 1) | Registro del sistema de MacroDroid, captura saneada |
| 29/09/2026 18:58 | C1 | F0.3.1 | saliente a contacto interno | Sí | Chrome (no PWA), vía «Open Website» | Sí | PASS número · FAIL apertura PWA (vía 1) | Registro del sistema de MacroDroid |
| 29/09/2026 19:04 | C1 | F0.3.1 | saliente a contacto propio | Sí | Chrome (no PWA), vía «Open Website» | Sí | PASS número · FAIL apertura PWA (vía 1) | Registro del sistema de MacroDroid |
| 29/09/2026 ~19:20 | C1 | F0.3.1 | saliente (prueba de la acción «Lanzar app») | Sí | App instalada (PWA), vía «Lanzar app» | Sí | PASS número · PASS apertura PWA (vía 3) | Observado por Jhosep; total 29/09: 4 salientes con número, 0 entrantes probadas |
| 29/09/2026 19:04 | C1 | F0.3.2 | retorno a PWA con «Open Website» (`#/gestion-diaria`, codificación de URL desactivada) | — | Chrome (no PWA) | — | FAIL vía 1 | Observado por Jhosep; coincide con lo documentado para Android 12+ |
| 29/09/2026 19:20 | C1 | F0.3.2 | retorno a PWA con «Lanzar app → Avance CRM» (vía 3; la vía 2 «Send Intent» no se probó: `chrome://webapks` bloqueado en el equipo, sin nombre de paquete) | — | Se abre la app instalada, sin barra de Chrome, en su portada (Hoy) | — | PASS vía 3 | Observado por Jhosep tras una llamada de prueba |
| 29/09/2026 19:06 | C1 | F0.3.2 | notificación con número | Sí: las tres notificaciones «Llamada Terminada» con número y nombre estaban en la barra (agrupadas bajo MacroDroid); no se vieron al momento porque Chrome se abrió encima | — | — | PASS | Captura de la barra de notificaciones, saneada |
|  |  | F0.3.3 |  |  |  |  |  |  |

Cierre de F0.3 por celular: salientes con número __/10 · entrantes con número __/10 · perdidas frente al registro del teléfono __ · duplicadas __ · noches sin fallo __/3.

## 6. Incidencias

| Fecha | Celular | Qué pasó | Impacto (perdida / duplicada / no abrió / otro) | Cómo se resolvió | Abierta o cerrada |
| --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |

## 7. Decisión de cierre (F0.4.3)

- Cobertura: ¿qué parte de las llamadas del día salió del CRM y qué parte fuera? (si casi todo sale del CRM, baja la prioridad de F1)
- Viabilidad: ¿llegó el número en salientes y entrantes en los 3 celulares? ¿abrió la PWA? ¿se perdió algo de noche?
- Decisión: **continuar / ajustar / detener**, con fecha, quién decide y por qué.
- Estimación de responsables y calendario para F1–F2 (sin fechas inventadas).
