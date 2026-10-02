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

## 6. Incidencias

| Fecha | Celular | Qué pasó | Impacto (perdida / duplicada / no abrió / otro) | Cómo se resolvió | Abierta o cerrada |
| --- | --- | --- | --- | --- | --- |
| 02/10/2026 ~16:40 (Lima) | C1 | MacroDroid no dejó crear la sexta macro: la versión gratuita admite **5 macros** por celular | Otro: límite de la herramienta | Se borraron las macros de prueba «Prueba F3» y «Reintento F3» (su configuración está en §5d) y la variable `pendiente`. La macro definitiva de salientes usa 3 (Saliente, Al colgar, Enviar cola); con las entrantes (propuesta #14) harían falta más | **Abierta:** decisión de Miguel sobre comprar MacroDroid Pro para los celulares del piloto si se aprueban las entrantes (Jhosep, 02/10: «ya tendremos en cuenta ver si lo compramos») |

## 7. Decisión de cierre (F0.4.3)

- Cobertura: ¿qué parte de las llamadas del día salió del CRM y qué parte fuera? (si casi todo sale del CRM, baja la prioridad de F1)
- Viabilidad: ¿llegó el número en salientes y entrantes en los 3 celulares? ¿abrió la PWA? ¿se perdió algo de noche?
- Decisión: **continuar / ajustar / detener**, con fecha, quién decide y por qué.
- Estimación de responsables y calendario para F1–F2 (sin fechas inventadas).
