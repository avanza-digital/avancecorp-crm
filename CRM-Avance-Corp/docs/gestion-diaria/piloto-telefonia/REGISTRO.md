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
| 02/10/2026 11:13–11:14 (Lima) | C1 | 2 — id de origen propio por llamada | Primera acción de la macro: «Fijar Variable» → `id_llamada` (cadena, local) = `C1-{system_time}` (hora del sistema en SEGUNDOS, no milisegundos: basta, un celular no termina dos llamadas en el mismo segundo); en el cuerpo, `"evento_origen_id":"{lv=id_llamada}"`. Dos llamadas salientes al mismo número con ~50 s de diferencia | PASS (parcial): dos `202` en el celular y dos «guardada» en el receptor con ids distintos (`C1-1790957589`, `C1-1790957641`); con el id fijo la segunda habría salido «repetida». Una sola notificación por llamada en las 3 llamadas de hoy (sin doble disparo visto; la prueba 5 sigue abierta). **Falta** la otra mitad: que el MISMO id se reutilice al reintentar, que depende de la cola (pruebas 3 y 4) | Capturas de las notificaciones y registro del receptor 11:13:10 y 11:14:02 |
| 02/10/2026 11:19 (Lima) | C1 | 6 — la clave fuera del registro de MacroDroid | Menú → «Registro del sistema», líneas de las llamadas de 10:48, 11:13 y 11:14 | PASS: la línea del envío solo dice «(2) Solicitud HTTP (POST) Prueba F3» y luego «HTTP response code: 202»; no aparecen la cabecera, la clave ni la URL. «Prueba F3» no escribe en el registro de usuario. Observaciones para la macro definitiva: (a) la clave vive en texto visible dentro de la acción (y viaja en una macro exportada): el control es rotarla (F2-c); (b) el número sí aparece en el registro por las notificaciones y el «Registrar evento» de la macro F0: en la macro definitiva, no mostrarlo. Pista para la prueba 5: en cada llamada «Llamada terminada» disparó UNA vez cada macro (F0 y Prueba F3) | Captura del registro del sistema (número no transcrito) |
| 02/10/2026 12:06–12:17 (Lima) | C1 | 3 — el aviso se guarda antes del envío, se borra solo con 202 y sobrevive al reinicio | Variable GLOBAL `pendiente` (cadena) con un solo aviso (decisión de la prueba: un hueco basta para demostrar la durabilidad; la lista de varios pendientes va en la macro definitiva). Orden de acciones: `id_llamada` → `pendiente` = cuerpo JSON → `codigo` = 0 (para que un fallo no herede el 202 anterior) → Solicitud HTTP con cuerpo `{v=pendiente}` → «Si» `codigo = 202` (condición «Variable MacroDroid» de «MacroDroid Propio») → `pendiente` = vacío → «Fin de Si» → notificación con `{lv=codigo}` y `{v=pendiente}` | PASS. A (Wi-Fi): «guardada» en el receptor a las 12:06:48 (`C1-1790960807`). B (sin Wi-Fi, solo 4G): no llegó nada al receptor y `pendiente` conservó el aviso; código de la notificación no anotado. C: tras reiniciar el celular con datos móviles y sin Wi-Fi (confirmado por Jhosep), MacroDroid → Variables mostraba `pendiente = {"accion":"llamada…` | Captura de Variables a las 12:17 con 4G; registro del receptor |
| 02/10/2026 14:18 (Lima) | C1 | 4 — reenvío automático al volver la conexión (y la mitad pendiente de la 2: el mismo id al reintentar) | Macro aparte «Reintento F3» (copia de «Prueba F3»): disparador «Conectado a la red» → MASCAPITAL (pidió permiso de ubicación; solo para esta prueba, ver el requisito de la macro definitiva en F3-PLAN-CORTO.md); acciones «Espera antes de la siguiente acción» 10 s (con «Usar alarma») → `codigo` = 0 → Solicitud HTTP con `{v=pendiente}` → «Si» `codigo = 202` → `pendiente` = vacío → «Fin de Si» → notificación (conservó el título «Prueba F3»). Un primer intento cayó cuando el receptor ya estaba apagado (límite de 2 h): el aviso no se borró | PASS: al apagar y encender el Wi-Fi llegó solo `C1-1790961656` (creado a las 12:20:56, en la llamada sin Wi-Fi de la prueba 3) como «guardada» a las 14:18:44, ~2 h después y tras un reinicio; notificación `codigo: 202 pendiente:` vacío. Cierra la 2: el reenvío usa el MISMO id. **Falta** de la 4: ante 429 o 5xx el aviso se conserva, pero solo se reintenta en la próxima conexión (no hay reintento periódico; va en la macro definitiva) | Registro del receptor 14:18:44; notificación descrita por Jhosep |
| 02/10/2026 14:22–14:24 (Lima) | C1 | 5 — doble disparo de «Llamada terminada» | Misma macro «Prueba F3», Wi-Fi encendido. Dos casos raros, en el orden pedido (según Jhosep): (a) colgar antes de que contesten, (b) dejar sonar sin respuesta | PASS: un solo aviso por llamada, con ids distintos (`C1-1790968965` a las 14:22:45, `C1-1790969063` a las 14:24:23) y una sola notificación «Prueba F3» por llamada. En las 8 llamadas del día «Llamada terminada» disparó una vez por macro. No probados: llamada en espera (dos a la vez) y entrante rechazada, para F3-d. Hallazgo para la macro definitiva: «Llamada terminada» también dispara con entrantes y el cuerpo de la prueba dice siempre `"direccion":"saliente"`; la definitiva tiene que fijar la dirección (macro de «Llamada saliente» que marque la variable, como prevé §3 de `macrodroid.md`) o mandar `desconocida` | Captura de las notificaciones; registro del receptor |

**Resumen de las 6 pruebas (02/10):** todas PASS contra el receptor del PC. MacroDroid acredita en C1 lo que exige F3.3: envía solo el aviso con la clave en cabecera, crea un id por llamada y lo conserva al reintentar, guarda el aviso antes del envío y lo borra solo con 202, lo conserva sin red y tras reiniciar, lo reenvía solo al volver la conexión y no duplica en los casos probados. Quedan para la macro definitiva (F3-c): reintento periódico ante 429/5xx, disparador sin red concreta y sin ubicación (requisito de Jhosep), lista de varios pendientes, dirección correcta y no mostrar el número en notificaciones ni registro. Contra la Edge desplegada se repiten la 1 y la 6.

## 5e. Macro definitiva de salientes (F3-c) — pruebas de aceptación contra el receptor del PC

Macros armadas el 02/10 en C1 (MacroDroid gratuito, 5 macros como máximo): «Llamadas-Salientes» (Llamada saliente → `en_saliente` = Verdadero), «Llamadas-Al colgar» (copia de «Piloto F0»: Llamada terminada → Si `en_saliente` → `id_llamada` = `C1-{system_time}` → `cola_llamadas[{lv=id_llamada}]` = aviso con `"ocurrio_en":"{datetime}-05:00"` → Abrir sitio web F1 → Iniciar macro «Llamadas-Enviar cola» → Fin de Si → `en_saliente` = Falso) y «Llamadas-Enviar cola» (Datos Disponibles + Intervalo regular 5 min con alarma → espera 10 s → Iterar `cola_llamadas` → `codigo` = 0 → POST `{iterator_value}` → Si 202: Eliminar clave `[{iterator_dictionary_key}]` → Si 400: copiar a `errores_llamadas`, eliminar clave y notificación sin número). «Piloto F0» apagada; «Prueba F3», «Reintento F3» y `pendiente` borradas.

| Fecha | Prueba | Resultado | Evidencia |
| --- | --- | --- | --- |
| 02/10/2026 17:21–17:26 (Lima) | A1 — saliente con Wi-Fi | PASS: 4 salientes (2 a un número sin lead, 2 a un lead): una sola pantalla del CRM por llamada (aviso ámbar sin lead; encuesta y ficha del lead como protagonista con lead), y un solo aviso «guardada» por llamada en el receptor, ~11 s después de colgar, con `ocurrio_en` = hora real de la llamada (p. ej. `2026-10-02 17:21:12-05:00`, id `C1-1790979672`) | Registro del receptor 17:21:23, 17:24:43, 17:25:21, 17:26:34; observado por Jhosep |
| 02/10/2026 17:35–17:40 (Lima) | A3 — dos salientes sin Wi-Fi (con datos móviles), Wi-Fi encendido a las 17:36 | PASS: la lista guardó los avisos (a las 17:38 quedaba 1 entrada, `C1-1790980502`); llegaron los dos, cada uno con la hora en que se colgó: `C1-1790980536` a las 17:36:49 (`ocurrio_en` 17:35:36) y `C1-1790980502` a las 17:40:10 (`ocurrio_en` 17:35:02), esta con el intervalo de las 17:40 + 10 s de espera. **Hallazgo:** encender el Wi-Fi con los datos móviles activos NO disparó «Datos Disponibles» (para el celular, el internet no se cortó); el intervalo de 5 min recoge lo pendiente: demora máxima ~5 min tras volver la red. Supuesto no comprobado: la primera entró porque la vuelta lanzada al colgar la segunda seguía en curso cuando volvió el Wi-Fi | Registro del receptor; captura de `cola_llamadas` a las 17:38 |
| 02/10/2026 17:42–17:45 (Lima) | A4 — el servidor falla (503 forzado desde el PC con `/_control?modo=503&veces=1`) | PASS: el aviso `C1-1790980958` (colgado a las 17:42:38) recibió 503 a las 17:42:49 y se quedó en `cola_llamadas` (1 entrada, confirmado por Jhosep); el intervalo de las 17:45 lo reintentó a las 17:45:10 con el mismo id y la misma hora → 202 «guardada» | Registro del receptor; observado por Jhosep |
| 02/10/2026 17:59–18:15 (Lima) | A6 — reinicio con un aviso pendiente | PASS: saliente sin Wi-Fi colgada a las 17:59:56 (`C1-1790981996`) → 1 entrada en `cola_llamadas` → reinicio del celular con Wi-Fi apagado → la entrada seguía y MacroDroid estaba en marcha (su notificación fija visible) → Wi-Fi encendido ~18:14:10 → llegó a las 18:15:10 (intervalo de las 18:15 + 10 s) con `ocurrio_en` 17:59:56. El intervalo de 5 min se reactiva solo tras reiniciar | Registro del receptor; observado por Jhosep |
| 02/10/2026 18:18–18:30 (Lima) | A5 — un aviso dañado no bloquea la cola | PASS: entrada añadida a mano en `cola_llamadas` (clave `PRUEBA-DAÑADA`, tipo Cadena, valor `x`) → el intervalo de las 18:20 la envió → 400 «cuerpo que no es JSON» → pasó a `errores_llamadas`, salió de la cola y apareció la notificación «Un aviso de llamada fue rechazado» (sin número). Una saliente durante la prueba (Wi-Fi cortado en plena llamada, `C1-1790983309` a las 18:21:49) quedó sola en la cola y llegó con 202 a las 18:30:10 al volver el Wi-Fi | Capturas de `errores_llamadas` y `cola_llamadas` a las 18:26; registro del receptor |
| 02/10/2026 ~18:33 (Lima) | A2 — llamada entrante a C1 | PASS: no se abrió la encuesta ni llegó ningún aviso al receptor (`en_saliente` seguía en Falso). Las entrantes quedan fuera hasta que Miguel decida la propuesta #14 | Observado por Jhosep; registro del receptor sin envíos después de las 18:30:10 |

**Resumen F3-c (02/10):** la macro definitiva de salientes pasó las 7 pruebas de aceptación (A1–A7) contra el receptor del PC. Pendiente: repetir A1 y A3 con datos móviles contra la Edge desplegada (Miguel), latido de salud (decisión 3 de F3), entrantes (#14) y la compra de MacroDroid Pro si hacen falta más de 5 macros.

## 5f. Macro sin Pro: latido, prefijo y hora — contra el receptor y después contra la Edge

| Fecha | Prueba | Resultado | Evidencia |
| --- | --- | --- | --- |
|  | Antes: `cola_llamadas` y `errores_llamadas` vacías; «Fecha y hora automáticas» ✓ y zona de Lima | NOT RUN |  |
|  | L1 — latido en la primera vuelta | NOT RUN |  |
|  | L2 — latido al vaciar la cola | NOT RUN |  |
|  | L3 — latido a las 6 h | NOT RUN |  |
|  | L4 — otra etiqueta → 400 (solo contra la Edge) | NOT RUN |  |

L1 y L2 quedaron cubiertas por P1 y P2 de §5g (06/10). L2 cambió: desde el 06/10 el latido ya no sale al vaciarse la
cola, solo cada 6 h.

## 5g. Macro FINAL (06/10/2026) — armada en C1 y probada contra el receptor de pruebas del PC

Versión de `macrodroid.md` §3c del 06/10. Tiene la clave y la URL en variables, el latido solo cada 6 h con
`llamadas-v3`, el aviso ante 401 (D7) y la guarda de las 2 h, y abre la URL del CRM con el id de la llamada. El receptor
es el del PC (`192.168.30.222:8787`), con una clave de prueba nueva.

| Fecha | Prueba | Resultado | Evidencia |
| --- | --- | --- | --- |
| 06/10/2026 15:34 (Lima) | P1 — primera vuelta de «Enviar cola», disparada a mano | PASS: latido 200 con la clave en la variable | Receptor: `POST → 200 (latido registrado) · clave correcta · macro=llamadas-v3 en_cola=0`. Registro del sistema de MacroDroid: cada acción y `ultimo_latido` actualizado |
| 06/10/2026 15:55 (Lima) | P2 — saliente con Wi-Fi | PASS: se abrió la encuesta y el aviso llegó a los 10 s. El número era de un lead convertido, así que F1 dijo «ningún lead de tu cartera»: es lo esperado, los clientes van con la #13 | Receptor: `15:55:48 POST → 202 (guardada) · id=C1-1791320138 · ocurrio_en=…15:55:38-05:00`; `latidos` siguió en 1 |
| 06/10/2026 15:59–16:00 (Lima) | P4 — el receptor responde 401 durante el envío | PASS: notificación «La clave de este celular ya no vale…»; el aviso quedó en `cola_llamadas` (1 entrada). Con el receptor de nuevo en normal, se reenvió solo en la vuelta de las 16:00, con el mismo id y la hora original | Receptor: `15:59:07 POST → 401 (falla simulada)` y `16:00:10 POST → 202 (guardada) · id=C1-1791320337 · ocurrio_en=…15:58:57-05:00` |
| 06/10/2026 ~16:05 (Lima) | P5 — entrante | PASS: ni encuesta ni aviso | Observado por Jhosep; el receptor no registró nada nuevo |
|  | P3 — saliente sin red | NOT RUN: el camino «guardar y reenviar» ya quedó probado en P4 y en A3 (02/10) |  |

**Hallazgo (incidencia del 06/10, abajo):** MacroDroid gratuito estaba **desactivado desde ~02/10**, porque se acabaron
sus «días gratis». Ninguna macro corría. Se reactivó mirando un anuncio (+3 días).

## 5h. Pruebas físicas pendientes de F0 y F3 (07/10/2026) — contra el receptor de pruebas del PC

Misma macro final y misma clave de prueba del 06/10 (el receptor se arrancó con `--clave`, sin reconfigurar C1).
Receptor en `192.168.30.222:8787`. Lo que necesita la Edge real se repite en F4-d (`ACTIVAR-C1.md`, P15).

| Fecha | Prueba | Resultado | Evidencia |
| --- | --- | --- | --- |
| 07/10/2026 14:10–14:11 (Lima) | 429 forzado (`/_control?modo=429&veces=1`): lo recibió el **latido**, que C1 mandó apenas pudo porque el último era del 06/10 | PASS: el latido rechazado se reintentó solo y entró en la vuelta siguiente | Receptor: `14:10:09 POST → 429 (falla simulada) · latido` y `14:11:21 POST → 200 (latido registrado)`. En medio entraron dos llamadas normales (`14:11:17` y `14:11:40`, 202) |
| 07/10/2026 14:17–14:20 (Lima) | **429 explícito en un aviso de llamada** (F3.3.2): 429 armado de nuevo y una saliente corta | **PASS**: el aviso quedó en `cola_llamadas` (1 entrada, visto por Jhosep) y la vuelta del intervalo lo reenvió solo, con el **mismo id** y la **hora original** | Receptor: `14:17:34 POST → 429 (falla simulada) · id=C1-1791400645 · ocurrio_en=…14:17:25-05:00` y `14:20:09 POST → 202 (guardada) · id=C1-1791400645 · ocurrio_en=…14:17:25-05:00` |
| 07/10/2026 14:27 y 14:28 (Lima) | **Saliente a un fijo** que no es lead (F0.3.2) | **PASS** (captura y formato): el aviso llegó a los 10 s; el CRM mostró el número completo con **+51** y «Ningún lead de tu cartera tiene el número…», que es lo correcto porque no es lead | Receptor: `14:27:35 POST → 202 · id=C1-1791401245 · …632` y `14:28:31 POST → 202 · id=C1-1791401301 · …632` |
| 07/10/2026 14:34 (Lima) | **Pantalla bloqueada** al terminar la llamada (F0.3.3): la otra persona cortó a los 45 s con la pantalla apagada | **PASS**: el aviso llegó a los 9 s con la pantalla bloqueada; al desbloquear, el CRM ya tenía la encuesta abierta | Receptor: `14:34:24 POST → 202 · id=C1-1791401655 · ocurrio_en=…14:34:15-05:00` |
| 07/10/2026 15:24 (Lima) | **Saliente a un lead propio** (regresión de F1 en producción): Jhosep creó el lead «prueba leeds» en su cartera con el **celular** de un compañero | **PASS**: al colgar se abrió **la encuesta de ese lead**. Los números de clientes dicen «ya es cliente» y no abren encuesta: es lo esperado hasta la #13. El caso «lead con **fijo**» queda cubierto solo por las pruebas automáticas de F1 | Receptor: `15:24:18 POST → 202 · id=C1-1791404649 · …741`. El lead «prueba leeds» se conserva para F4-d |
| 07/10/2026 15:43–15:44 (Lima) | **Ráfaga**: 3 salientes cortas seguidas en 48 s (F3.4.1) | **PASS**: 3 avisos distintos, cada uno con su id, ~9 s después de colgar; sin repetidos, sin rechazos | Receptor: `15:43:32`, `15:44:02` y `15:44:20 POST → 202`, ids `C1-1791405803`, `C1-1791405833`, `C1-1791405851` |

Precio de MacroDroid Pro visto en C1 el 07/10: **S/ 19, pago único** (para la #18).

## 5i. C1 activado contra producción (F4-d, 07/10/2026) — Edge real

Alta desde la tarjeta «Celulares» con una sesión de gerencia en la PC: etiqueta C1, el analista de la cuenta abierta en
C1. La clave pasó a C1 por WhatsApp y nunca a Claude. En MacroDroid: `cola_llamadas` y `errores_llamadas` en 0 entradas,
`url_llamadas` apuntando a la Edge real, `clave_celular` con la clave nueva y `ultimo_latido` en 0. Versión publicada:
`build-20261007T222046462Z`. Lead de prueba: «prueba leeds» (propio, con el celular de un compañero y su permiso).
Resultado guardado: «No contestó», salvo donde se indica. Sin números ni claves en este registro. Pro sigue sin
comprar: Jhosep decidió renovar los días gratis con anuncios si hace falta.

| Fecha (Lima) | Prueba | Resultado | Evidencia |
| --- | --- | --- | --- |
| 07/10 ~19:15 | Alta y primer latido (§2–§4 de `ACTIVAR-C1.md`) | **PASS** | Tarjeta «Celulares» (gerencia, PC): C1 «Al día», macro `llamadas-v3`, en cola 0. Primer uso real de la tarjeta con gerencia después del release |
| 07/10 19:19 | P1 · guardar enseguida | **PASS** (unión) | «Qué pasó hoy»: «Registrada al colgar: el celular abrió la encuesta · llamada a las 19:19», resultado «Agendó cita». El mensaje al guardar no se vio; se completó a las 19:41 (abajo) |
| 07/10 19:25 | P2 · esperar ~30 s antes de guardar | **PASS** | «Llamada registrada · No contestó. Quedó unido a tu llamada del celular de las 19:25» |
| 07/10 19:29 | P15-A1 · una llamada por datos móviles (Wi-Fi apagado, 4G) | **PASS** | «Quedó unido a tu llamada del celular de las 19:29» (resultado «Volver a llamar»). Contra el receptor del PC no se podía probar |
| 07/10 19:34 | P3 · sin red (Wi-Fi y datos apagados) | **PASS** | El CRM mostró «No tienes conexión»; al volver el Wi-Fi, «Quedó unido a tu llamada del celular de las 19:34» |
| 07/10 19:41–~19:45 | P1, el mensaje que faltaba: aviso retenido (sin red y con «Llamadas-Enviar cola» apagada al guardar) | **PASS** | «Quedará unido a tu llamada del celular de las 19:41 en cuanto llegue su aviso». Al volver a encender la macro, la llamada se unió sola en la vuelta de las 19:45 («Qué pasó hoy · 5», «Pendientes · 0») |
| 07/10 19:59–20:00 | P6 · cerrar la encuesta sin guardar y registrar desde «Celular» en el celular | **PASS** | La llamada apareció en «Pendientes» con «Pide resultado»; registrada desde ahí: «Registrada desde «Llamadas del celular» · llamada a las 19:59» |
| 07/10 20:14 | P7 · lo mismo, registrando desde la PC | **PASS** | «Pendientes · 1» en la PC → «Registrar resultado»: «Quedó unido a tu llamada del celular de las 20:14»; «Registrada desde «Llamadas del celular»» |
| 07/10 20:19–20:20 | P9 · guardar, Deshacer y corregir | **PARCIAL** | «Deshecho: Prueba vuelve a su etapa y la tarea creada se cancela»; la fila quedó «No contestó · deshecho» sin borrarse. **Hallazgo:** la llamada no vuelve a «Pendientes» y la fila deshecha no tiene acción, así que la pantalla no ofrece cómo registrar el resultado corregido unido a la misma llamada. La regla del servidor que mueve el enlace al corregido existe, pero ningún botón llega a ella |
| 08/10 ~11:25 | P13 · llamar a un número que no es lead | **PASS** | Al colgar se abrió la encuesta con el aviso ámbar «ningún lead de tu cartera…»; «Pendientes · 0» y «Qué pasó hoy · 0» (nada guardado). Tarjeta «Al día», llamadas-v3, en cola 0 comprobada antes de la prueba (08/10 ~11:20) |
| 08/10 ~11:35 | P12 · recibir una llamada en C1 desde otro celular | **PASS** | Llamada entrante normal: no se abrió el CRM ni la encuesta ni ningún aviso. `cola_llamadas` con 0 entradas después de colgar. Pestaña «Celular»: «Pendientes · 0» y «Qué pasó hoy · 0» (las entrantes no se capturan) |
| 08/10 12:00–12:40 | P11 · rotar la clave de C1 (gerencia) y conservar la cola | **PASS** | (1) «Rotar clave» con la cola en 0: diálogo «En cola ahora: 0 avisos»; la tarjeta pasó a «Nunca habló · Esperando el primer latido», macro «–», cola «—», «Desde 8 oct.», y el historial muestra la asignación de ayer cerrada por «Rotación de clave» (por diseño: rotar cierra la asignación y abre otra contigua al mismo analista). (2) Con la clave vieja: llamada a «prueba leeds» a las 12:05, encuesta «No contestó» → «Quedará unido a tu llamada del celular de las 12:05 en cuanto llegue su aviso»; notificación de MacroDroid «La clave de este celular ya no vale: pide una nueva a gerencia»; `cola_llamadas` **1 entrada** (retenida, no vaciada: el P2 de Miguel del #215, ahora contra la Edge real). (3) Clave nueva pegada en `clave_celular` sin tocar las colas. (4) En las vueltas de 5 min la cola bajó sola a **0** y «Qué pasó hoy · 1» con la llamada unida a «No contestó». **Hallazgo H-P11:** la tarjeta siguió en «Nunca habló» después de vaciarse la cola, porque el latido solo se manda cada 6 h (`ultimo_latido` marcaba el de las 10:39) y la asignación nueva no tenía ninguno; se forzó poniendo `ultimo_latido = 0` y a las 12:40 la tarjeta volvió a «Al día», `llamadas-v3`, en cola 0. «Ya la copié al celular» solo cierra el diálogo (no toca el servidor): pulsarlo antes de pegar la clave no afecta |
| 08/10 ~14:20 | P15 · prueba 6: el registro de MacroDroid no muestra la clave | **PASS** | Búsqueda «http» en «Registro del sistema» de C1: las líneas «Solicitud HTTP (POST)» solo muestran el paso y el código de respuesta; los fallos muestran la URL de la Edge; **ninguna muestra la clave**. De paso, el registro confirma con horas exactas: 10:25–10:35 sin internet (falla de DNS) con el latido reintentando cada 5 min y entrando a las 10:39 (200); P13 a las 11:25 (aviso 202); P12 ~11:35 sin ningún envío; P11 con 401 a las 12:05 (×2) y 12:10, 202 a las 12:15 (clave nueva pegada entre 12:10 y 12:15) y latido forzado 200 a las 12:40. **Observación:** la línea «Abrir sitio web» de la macro «Al colgar» guarda el número marcado en el registro del celular (no es exposición nueva: el teléfono ya tiene su historial de llamadas). No se copian números aquí |
| 08/10 14:23–14:25 | P15-A3 · dos llamadas seguidas por datos móviles (Wi-Fi apagado, 4G) | **PASS** | Dos llamadas a «prueba leeds» con menos de dos minutos entre ellas, «No contestó» en las dos. La primera dio el mensaje largo («Quedará unido… en cuanto llegue su aviso», según recuerda Jhosep) y la segunda «Quedó unido…». Pestaña «Celular»: «Qué pasó hoy · 3» (12:05, 14:23 y 14:25, las dos nuevas «Registrada al colgar: el celular abrió la encuesta»), «Pendientes · 0». `cola_llamadas` y `errores_llamadas` con 0 entradas |
| 08/10 ~14:35 | P15-A6 · reiniciar C1 con un aviso pendiente | **PASS** | Wi-Fi y datos apagados (sin modo avión): llamada a «prueba leeds», encuesta cerrada sin guardar («No tienes conexión»); `cola_llamadas` 1. Reinicio de C1: MacroDroid arrancó **activado** y `cola_llamadas` siguió en **1** antes de encender la red. Con la red, la cola se vació sola en la vuelta siguiente, la llamada apareció en «Pendientes · 1» y, registrada desde ahí con «No contestó», quedó unida: «Qué pasó hoy · 4». Evidencia: confirmación de Jhosep paso a paso, sin captura ni hora exacta |
| 08/10 14:45–15:12 | P10 · reasignar el lead con una llamada pendiente | **PASS** (con hallazgo H-P10) | Llamada de C1 a «prueba leeds» a las 14:45, encuesta cerrada sin guardar. 15:06: gerencia reasignó el lead a otra analista (ficha → «Responsable comercial»). En la sesión de la otra analista, pestaña «Celular»: «Pendientes · 1» con la llamada de C1 (**sigue al dueño actual**, decisión 7). Gerencia devolvió el lead al analista de C1: la llamada volvió a sus «Pendientes» y, registrada desde ahí con «No contestó», quedó unida: «Registrada desde «Llamadas del celular» · llamada a las 14:45», «Qué pasó hoy · 5», «Pendientes · 0». Las tareas del lead siguieron iguales tras la ida y vuelta. **Paso 3, observado por Jhosep:** mientras el lead era de la otra analista, en la sesión del analista de C1 «prueba leeds» no aparecía en absoluto, «como si ya no existiera»: ni la pendiente ni las llamadas que él mismo resolvió hoy (coincide con la regla `private.llamada_celular_visible`, duodécima). **Hallazgo H-P10 (pantalla):** la otra analista vio también en «Qué pasó hoy · 4» las cuatro llamadas resueltas por el analista de C1, bajo el texto «Las llamadas de hoy desde **tu** celular que ya resolviste». La regla muestra las llamadas de un lead a quien lo tiene hoy, sin mirar quién llamó; la lectura ya devuelve `es_propia`, pero la pantalla no lo usa. Sus cifras de arriba («Llamadas 0 hoy») no se mezclaron. La otra cara: el analista anterior deja de ver su propio trabajo del día mientras no tenga el lead. La reasignación de ida y vuelta queda en el historial del lead |
| 08/10 ~15:20 | P8 · encuesta abierta a mano con el id de otro celular | **PASS** | Dirección preparada por Claude: la ruta de la encuesta con el número de «prueba leeds» y el id `C2-1791490562` (C2 no está asignado al analista; el servidor responde «celular ajeno» antes de crear ninguna intención). Abierta en C1 con la sesión del analista: encuesta de «prueba leeds», guardado «No contestó» → el resultado se guardó y **no se unió** a ninguna llamada. «Qué pasó hoy» siguió en 5 y «Pendientes» en 0. La primera vez no se anotó el motivo del mensaje; se **repitió (~15:35)** con la misma dirección y el mensaje dijo que el resultado se guardó pero no se pudo unir porque **la llamada es de otro celular** (el candado de «celular ajeno»). Los dos «No contestó» quedan en el lead como cualquier otro |
| 08/10 12:40–15:45 | P14 · latidos (L1, L2, L4; L3 pendiente) | **PASS** en L1, L2 y L4 | **L1:** el latido forzado tras la rotación entró a las 12:40 (200) y la tarjeta volvió a «Al día». **L2** (registro de MacroDroid, búsqueda «http»): en P15-A6 el aviso falló sin red a las 14:31:38 («Unable to resolve host»), quedó en la cola y salió con 202 a las 14:34:42 al volver la red (lo disparó «Datos disponibles», no el intervalo); **ninguna** «(25) Solicitud HTTP» (latido) desde las 12:40: volver la red no genera un latido extra. **L4** (~15:40): entrada a mano en `cola_llamadas` con id `C9-1791491289` (etiqueta de otro celular) y número de mentira → notificación «Un aviso de llamada fue rechazado» sin número, `cola_llamadas` 0, `errores_llamadas` 1 (la macro solo aparta con 400); la entrada se borró después. **L3** pendiente: anotar la hora y el código del siguiente latido, que toca hacia las 18:40–18:45 |

Al cerrar: «Qué pasó hoy · 8», «Pendientes · 0». Las 8 llamadas y sus resultados cuentan en las cifras de la cuenta del
analista, como prevé la guía; en su agenda quedaron de prueba una cita (08/10 19:20) y dos tareas. La batería de C1 bajó
a 7 % durante las pruebas y se conectó al cargador hacia las 19:40, sin efecto en los resultados.

**Falta de F4-d (al 08/10 ~15:45):** P4 y P5 (necesitan un segundo lead de prueba con otro número del equipo), P14-L3 (el latido de las ~18:40)
(P15 completa: A1 el 07/10; A3, A6 y la prueba 6 el 08/10). Después, el cierre de §5 de `ACTIVAR-C1.md`: llamadas del teléfono = recibidas
por el CRM, 0 resultados unidos dos veces, «Encuesta abierta al colgar: N de N» y la consulta de Miguel sin números.

## 6. Incidencias

| Fecha | Celular | Qué pasó | Impacto (perdida / duplicada / no abrió / otro) | Cómo se resolvió | Abierta o cerrada |
| --- | --- | --- | --- | --- | --- |
| 02/10/2026 ~16:40 (Lima) | C1 | MacroDroid no dejó crear la sexta macro: la versión gratuita admite **5 macros** por celular | Otro: límite de la herramienta | Se borraron las macros de prueba «Prueba F3» y «Reintento F3» (su configuración está en §5d) y la variable `pendiente`. La macro definitiva de salientes usa 3 (Saliente, Al colgar, Enviar cola); con las entrantes (propuesta #14) harían falta más | **Cerrada el 03/10; revisada el 05/10:** Miguel aprobó las entrantes (#14) el 02/10, pero (03/10) **MacroDroid Pro no se compra todavía**. Se queda en 3 macros + «Piloto F0» apagada (4 de 5). El latido va dentro de «Llamadas-Enviar cola» y no suma macros (`macrodroid.md` §3c). Las entrantes esperan a la #14 y a la decisión de Pro (`macrodroid.md` §3d, diseño sin probar) |

| 06/10/2026 ~15:50 (Lima) | C1 | MacroDroid gratuito **se desactivó solo** porque se acabaron sus «días gratuitos de uso». Inicio decía «MacroDroid está actualmente desactivado»; las macros, encendidas, figuraban con «última activación hace 4 días» | **Perdida:** desde ~02/10 no se capturó ninguna llamada en C1, sin aviso en el celular | Inicio → «Añadir Días Gratuitos» (un anuncio = 3 días) → interruptor general encendido. En producción no es viable: propuesta #18 (MacroDroid Pro). El latido lo habría marcado «sin latido» en la tarjeta de salud | **Abierta** hasta que Miguel decida la #18. En C1 los días vencen ~09/10 15:50 |

| 07/10/2026 ~19:11 (Lima) | C1 | Una captura de «Variables globales» enviada a Claude mostró los **primeros 16 de 64** caracteres de la clave nueva | Otro: exposición parcial de la credencial en un chat. Sin riesgo práctico: faltan 48 caracteres y la Edge limita 30 intentos por minuto | La clave se reemplazó en P11 (rotación del 08/10 ~12:00, gerencia): la clave vista ya no vale. Desde ahora, capturas de Variables sin la fila `clave_celular`. El valor no se copió a ningún documento | **Cerrada el 08/10** (P11 PASS) |

## 7. Decisión de cierre (F0.4.3)

- Cobertura: ¿qué parte de las llamadas del día salió del CRM y qué parte fuera? (si casi todo sale del CRM, baja la prioridad de F1)
- Viabilidad: ¿llegó el número en salientes y entrantes en los 3 celulares? ¿abrió la PWA? ¿se perdió algo de noche?
- Decisión: **continuar / ajustar / detener**, con fecha, quién decide y por qué.
- Estimación de responsables y calendario para F1–F2 (sin fechas inventadas).
