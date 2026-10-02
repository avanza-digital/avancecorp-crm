# Registro del piloto F0 — llamadas desde el celular al CRM

Entregable de **F0.4.1**. Se llena a mano durante el piloto (F0.1–F0.4 del plan). **Sin números de teléfono reales ni datos de clientes**: se escribe «lead», «desconocido», «oculto». Cada fila es una evidencia; si una prueba no se hizo, se deja `NOT RUN` con la causa.

## 1. Equipos del piloto (F0.1.1)

| Celular | Marca y modelo | Android | Navegador por defecto | MacroDroid (versión) | Restricciones de batería (qué se cambió) | Fecha de alta |
| --- | --- | --- | --- | --- | --- | --- |
| C1 | Samsung Galaxy A16 (SM-A165M) | 16 | Chrome (predeterminado) | Play Store, versión 5.67 (septiembre 2026) | «Aparecer encima» activado · Batería «No restringido» · autoarranque («apps que nunca duermen»): por confirmar | 29/09/2026 |
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
| C1 | No aplica: el celular lo usa el propio responsable del piloto | — | 29/09/2026 | «Aparecer encima» ✓ · Batería «No restringido» ✓ · Teléfono y Registro de llamadas: por confirmar · **CRM Avance Corp → «Abrir vínculos admitidos» ✓ y dominio crm.miavance.com ✓ (30/09, necesario para que la URL abra la app)** |
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
| 30/09/2026 mañana | C1 | F0.3.3 | noche 1 de 3 (29→30/09): sin tocar MacroDroid | — | — | — | PARCIAL: MacroDroid seguía activo por la mañana y la macro con su interruptor encendido; no hubo llamadas nocturnas que verificar | Observado por Jhosep |
| 30/09/2026 12:16–12:20 | C1 | F0.3.2 | retorno a PWA con «Open Website» (`#/gestion-diaria`, codificación de URL desactivada) **tras activar en Android** Ajustes → Aplicaciones → CRM Avance Corp → «Definir como predeterminada» → «Abrir vínculos admitidos» ✓ y «Direcciones web admitidas» → crm.miavance.com ✓; acción «Lanzar app» desactivada | no verificado esta vez | Se abre la app instalada, sin barra de direcciones («como si fuese la PWA»), vía «Open Website» | — | PASS vía 1 con el ajuste de Android | Observado por Jhosep tras una llamada saliente corta. Resuelve el riesgo de F1: la URL con número puede llegar a la PWA sin «Send Intent» ni `packageName` |

Cierre de F0.3 por celular: salientes con número __/10 · entrantes con número __/10 · perdidas frente al registro del teléfono __ · duplicadas __ · noches sin fallo __/3.

## 5b. Pruebas de F1 en el celular (F1.4.2) — build de la rama servida desde el PC, sin tocar producción

| Fecha | Celular | Build | Caso | Resultado | Evidencia |
| --- | --- | --- | --- | --- | --- |
| 30/09/2026 12:45 | C1 | demo (Vite dev, `http://…:5173`) | Abrir la build de prueba en Chrome | FAIL primero: `ERR_SSL_PROTOCOL_ERROR` (Chrome fuerza HTTPS en el celular corporativo); se resolvió desactivando «Usar siempre conexiones seguras» y, como respaldo, sirviendo también por HTTPS con certificado propio (`:5174`, `:4174`) | Captura de Chrome |
| 30/09/2026 12:54 | C1 | demo | Entrar a la demo como Analista | PASS (Gestión Diaria con TERESA en «Ahora») | Captura |
| 30/09/2026 12:59 | C1 | demo | `#/gestion-diaria/llamada/<número de la persona de «Ahora»>` escrito en Chrome → recarga → login demo | PARCIAL: el número sobrevivió al login (el aviso salió con el número) pero la búsqueda corrió antes de que la demo cargara sus leads → «Ningún lead…». Corregido en `3065b84e` (espera a que haya leads) | Captura; hallazgo #1 de F1 |
| 30/09/2026 ~13:10 | C1 | demo (con `3065b84e`) | Mismo caso, tras la corrección | PASS: entró con la encuesta de TERESA abierta en «Ahora» | Observado por Jhosep («vi la encuesta») |
| 30/09/2026 13:52 | C1 | producción (por error) | Macro «Abrir Sitio web» que aún apuntaba a `crm.miavance.com` | Abrió la app instalada (sin barra) en la Gestión Diaria real, sin aviso: producción no tiene el receptor. Sirvió para confirmar que la app abre por URL con el ajuste de Android | Capturas (cuenta real, sin números) |
| 30/09/2026 ~14:05 | C1 | demo | **Macro real** con URL `http://<PC>:5173/#/gestion-diaria/llamada/{call_number}` → llamada saliente → colgar | PASS: se abrió Chrome (con barra) en el login de la demo; al entrar como Analista salió el aviso ámbar «Ningún lead de tu cartera tiene el número …» con el número marcado (no existe en la demo). El número viaja desde MacroDroid hasta el CRM y la URL queda limpia | Observado por Jhosep; el número no se transcribe |
| 30/09/2026 ~14:20 | C1 | **real** (`http://<PC>:4173`, misma base que producción) | Sesión con la cuenta de Jhosep; URL con el número de un lead propio escrita en Chrome | PASS: se abrió la encuesta del lead (su ficha lateral con el diálogo encima, porque no era la persona de «Ahora»). Se cerró **sin registrar**: nada guardado en la base. Observación: Jhosep preguntó si es normal que se abra la ficha; es el camino previsto para un lead distinto al de «Ahora» (posible ajuste de diseño para Miguel) | Observado por Jhosep |
| 30/09/2026 ~14:25 | C1 | — | Macro devuelta a `https://crm.miavance.com/#/gestion-diaria` y probada | PASS: al colgar abre la app instalada en Gestión Diaria (como por la mañana) | Observado por Jhosep |

## 5c. F1 en producción (desde el 01/10/2026, `build-20261002T005154879Z`)

| Fecha | Celular | Build | Caso | Resultado | Evidencia |
| --- | --- | --- | --- | --- | --- |
| 02/10/2026, antes de las 10:06 (Lima) | C1 | producción `build-20261002T005154879Z` | Macro «Abrir sitio web» cambiada a `https://crm.miavance.com/#/gestion-diaria/llamada/{call_number}` (codificación de URL desmarcada) → llamada saliente a un lead → colgar | PASS: abre la encuesta según el número del lead | Observado por Jhosep («abre la encuesta según el número del lead»). Sin detalle de la cuenta usada ni de si se registró el resultado |

## 5d. Pruebas de MacroDroid para F3 (F3.3) — contra el receptor de pruebas del PC

Receptor: `npm run receptor:llamadas-prueba` (mismo handler que la Edge `crm-llamadas-ingesta`, base falsa en memoria, clave de prueba inventada). Las pruebas 1–6 son las de `docs/plans/llamadas-celular/F3-PLAN-CORTO.md`. Macro aparte «Prueba F3» para no tocar la de F1.

| Fecha | Celular | Prueba | Configuración | Resultado | Evidencia |
| --- | --- | --- | --- | --- | --- |
| 02/10/2026 10:48 (Lima) | C1 | 1 — POST con cabecera y `{call_number}`, código y respuesta en variables | Disparador «Llamada terminada» → «Cualquier Número». Acción «Solicitud HTTP»: POST a `http://<PC>:8787/functions/v1/crm-llamadas-ingesta`, «Bloquear las siguientes acciones hasta completar» ✓, «Guardar el código de retorno HTTP en una variable entera» → `codigo` (local), «Guardar la respuesta HTTP en una variable de cadena» → `respuesta` (local); pestaña «Cuerpo del Contenido»: tipo `application/json`, texto con `"numero":"{call_number}"` e id fijo `C1-PRUEBA-0001`; pestaña «Parámetros de Encabezado»: solo `x-celular-credencial`. Acción «Mostrar notificación» con `{lv=codigo} {lv=respuesta}` | PASS: notificación `codigo: 202` + cuerpo `{"recibido":true,"abrir":"https://crm.miavance.com/#/gestion-diaria/llamada/<número>"}`; el receptor lo registró como guardada con la clave correcta y el número marcado (3 últimos dígitos coinciden). Comprobado de paso: Android 16 deja a MacroDroid usar `http` en la red local, el «Tipo de contenido» ya pone `Content-Type` (no hace falta a mano) y el número llega en formato nacional de 9 dígitos | Captura de la notificación (número no transcrito) y registro del receptor 10:48:53 |

## 6. Incidencias

| Fecha | Celular | Qué pasó | Impacto (perdida / duplicada / no abrió / otro) | Cómo se resolvió | Abierta o cerrada |
| --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |

## 7. Decisión de cierre (F0.4.3)

- Cobertura: ¿qué parte de las llamadas del día salió del CRM y qué parte fuera? (si casi todo sale del CRM, baja la prioridad de F1)
- Viabilidad: ¿llegó el número en salientes y entrantes en los 3 celulares? ¿abrió la PWA? ¿se perdió algo de noche?
- Decisión: **continuar / ajustar / detener**, con fecha, quién decide y por qué.
- Estimación de responsables y calendario para F1–F2 (sin fechas inventadas).
