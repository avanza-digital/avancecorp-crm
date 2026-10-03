# Guía de MacroDroid para el piloto F0 — llamadas desde el celular al CRM

Entregable de **F0.4.1** (plan: `docs/plans/llamadas-celular/PLAN.md`). Sirve para instalar y configurar MacroDroid en los 2–3 celulares del piloto y para comprobar los puntos de F0.3. En F0 **no existe todavía la ruta con número en el CRM** (la construye F1): aquí solo se verifica que Android entrega el número, que la URL abre la PWA instalada y que la macro sobrevive noche, bloqueo y batería. Ningún dato sale del celular en F0.

Lo marcado «verificado» sale de documentación oficial consultada el 29/09/2026 (fuentes al final); lo marcado «se prueba» solo se sabrá en el dispositivo.

## 1. Antes de instalar

- **Consentimiento primero.** Nada se instala sin el aviso firmado del analista (F0.1.3) y la revisión de tratamiento de datos (plan, sección 15).
- **Versión de Play Store basta** (verificado): la ficha de MacroDroid declara «read call log», «reroute outgoing calls», «read phone status and identity» y «write call log»; Google la acepta como app de automatización de dispositivo. **No** hacen falta el «Helper App» ni el «ADB hack»: ninguno de los dos aporta permisos de llamadas.
- Sin el permiso de **Registro de llamadas** el número llega vacío desde Android 9 (verificado). Concederlo cuando MacroDroid lo pida.
- Anotar en `compatibilidad.md`: marca y modelo, versión de Android, navegador por defecto, versión de MacroDroid.

## 2. Permisos y ajustes del sistema

| Ajuste | Dónde | Por qué |
| --- | --- | --- |
| Teléfono y Registro de llamadas | Ajustes → Apps → MacroDroid → Permisos | Sin ellos no hay número (verificado) |
| Mostrar sobre otras apps | Ajustes → Apps → MacroDroid → Mostrar sobre otras apps | Android 10+ lo exige para abrir algo desde segundo plano (verificado) |
| Batería sin restricciones | Ajustes → Apps → MacroDroid → Batería | Que la macro no muera de noche |
| Autoarranque / «apps que nunca duermen» | Depende de la marca: Xiaomi (Seguridad → Autoarranque), Huawei (Batería → Inicio de apps), Samsung (Batería → Apps que nunca duermen), Motorola (sin ajuste extra) | Marcas con optimización agresiva |
| Chrome como navegador por defecto | Ajustes → Apps → Apps predeterminadas → Navegador | En Android 12+ la PWA instalada solo se abre desde una URL si Chrome recibe el intent (verificado, Chromium) |
| PWA instalada | Abrir `https://crm.miavance.com` en Chrome → menú → «Añadir a pantalla de inicio» / «Instalar» | Es la app que debe abrirse |
| **La app abre sus enlaces** (comprobado en C1 el 30/09) | Ajustes → Aplicaciones → **CRM Avance Corp** → «Definir como predeterminada» → «Abrir vínculos admitidos» ✓ → «Direcciones web admitidas» → **crm.miavance.com** ✓ (en Samsung; en otras marcas «Abrir de forma predeterminada» / «Abrir enlaces compatibles») | Sin esto, una URL del CRM abre Chrome y no la app (visto el 29/09). Con esto, «Abrir sitio web» de MacroDroid abre la PWA y puede llevar el número (F1) |

## 3. Macro «Piloto F0 · llamada terminada»

**Trigger:** `Call Ended` (dispara en salientes y entrantes, contestadas y rechazadas — verificado). Magic text disponible: `{call_number}`, `{call_name}`, `{call_groups}`. **No existe** `{call_duration}` ni una variable de dirección (verificado).

**Acciones, en este orden:**

1. **Notification** — título `Llamada terminada`, texto `{call_number} · {call_name}`. Comprueba a ojo que el número llega (F0.3.1 y F0.3.2). Si llega vacío en salientes, anotarlo: es el riesgo #1 del plan.
2. **Add To Log (Log Event)** — texto `F0 {call_number} {call_name}`. Deja constancia en el registro de MacroDroid (menú → Registro) para compararlo con el registro de llamadas del teléfono al día siguiente (F0.2.3, F0.3.3).
3. **Open Website / HTTP GET** («Abrir sitio web») — URL `https://crm.miavance.com/#/gestion-diaria` (decisión de Jhosep, 29/09: el piloto aterriza en Gestión Diaria, donde está la tarjeta de resultado) con **«Parámetros de codificación de URL» desmarcado** (si queda activo codifica el `#` y la PWA no recibe la ruta — verificado) y «HTTP GET (sin navegador web)» desmarcado. Comprueba que se abre **la app instalada y no una pestaña de Chrome** (F0.3.2 «retorno a PWA»).
   - **Observado en C1 (Samsung A16, Android 16, Chrome predeterminado):** el 29/09 abrió Chrome, no la PWA (lo documentado para Android 12+). El **30/09, con el ajuste de Android de la tabla de la sección 2 («Abrir vínculos admitidos» + dominio), la misma acción abrió la app instalada sin barra de direcciones: PASS vía 1.**
   - **Vía 3, la que funcionó en C1 (29/09):** acción **Aplicaciones → «Lanzar app»** → casillas «Forzar nuevo» y «Excluir de apps recientes» sin marcar → elegir **Avance CRM** (la PWA aparece como una app más). Abre la app instalada, sin barra de navegador, en su portada (Hoy). Para F0 basta: comprueba que abre la app y no el navegador. No admite ruta ni número.
   - **Vía 2, para F1 (ruta con número):** acción **Send Intent** («Enviar intent») → Target `Activity`, Action `android.intent.action.VIEW`, Data `https://crm.miavance.com/#/gestion-diaria`, Package = el del WebAPK del CRM. El paquete se ve en Chrome escribiendo `chrome://webapks` (fila «Avance CRM», *Package name*, empieza por `org.chromium.webapk.`); en C1 esa página está bloqueada (el celular corporativo desvía las `chrome://` a una búsqueda), así que se obtendrá exportando la macro desde MacroDroid (menú de la macro → Exportar): el archivo trae el `packageName` de la acción «Lanzar app». Anotar cuál de las vías funciona en `compatibilidad.md`.
4. *(Opcional, para F0.3.3 «respuesta HTTP»)* **HTTP Request** GET a `https://crm.miavance.com/version.json` y guardar el código de respuesta en una variable; sirve para ensayar qué pasa sin red y tras reiniciar. No envía datos del celular.

**Dirección de la llamada (se prueba):** crear dos macros pequeñas, `Call Outgoing` → Set Variable `direccion = saliente` y `Call Incoming` → Set Variable `direccion = entrante`, y añadir `{lv=direccion}` a la notificación y al log de la macro principal. Si la variable llega bien a `Call Ended`, F3 podrá enviarla; si no, la dirección quedará `desconocida` (el plan lo admite).

**Duración:** MacroDroid no la entrega y su «Call Active → Call Ended» no sirve en salientes: Android no avisa cuándo contesta el otro (verificado). En F0 no se mide. Si más adelante hace falta, el plan contempla Tasker (`%CODUR`, solo última saliente) o Shizuku; es una decisión aparte (sección 16 del plan).

## 3b. Macro para F1 — la URL con el número (30/09/2026)

Desde F1 el CRM entiende **`#/gestion-diaria/llamada/<numero>`** (también `#/hoy/llamada/<numero>`): al abrirse con esa ruta busca el lead del número en la cartera del analista y, si es uno solo, abre la misma encuesta de resultado que hoy abre «Llamar» al volver del marcador. Si hay varios, ninguno, o el número no se entiende, muestra un aviso con los candidatos o con un buscador para elegir a mano; nada se autoselecciona.

**Cambio en la macro:** la acción de apertura pasa a llevar la URL
`https://crm.miavance.com/#/gestion-diaria/llamada/{call_number}`
con **«Parámetros de codificación de URL» desmarcado** (el `#` tiene que llegar tal cual; el `+` del número también se entiende sin codificar). Dos maneras de que esa URL abra la app y no Chrome:

1. **Ajuste de Android, sin paquete — es la vía que funcionó en C1 (30/09/2026):** Ajustes → Aplicaciones → **CRM Avance Corp** → «Definir como predeterminada» → «Abrir vínculos admitidos» ✓ → «Direcciones web admitidas» → `crm.miavance.com` ✓. Con eso la acción **«Abrir sitio web»** del F0 vale tal cual, solo cambiando la URL. Los dos interruptores tienen que estar encendidos: con el dominio apagado sigue abriendo Chrome.
2. **Send Intent con el paquete del WebAPK** (solo si en algún celular la vía 1 no existe): Target `Activity`, Action `android.intent.action.VIEW`, Data = la URL de arriba, Package = `org.chromium.webapk.…` (se obtiene exportando la macro: el archivo trae el `packageName` de la acción «Lanzar app»).

**Vigente en C1 desde el 02/10/2026:** F1 está en producción desde el 01/10 y la macro de C1 ya usa esta URL (PASS en `REGISTRO.md` §5c).

**«Lanzar app» ya no basta** para F1: abre la app pero no puede pasarle el número.

**Qué mirar en el celular (F1.4.2):** que la app se abra en Gestión Diaria y aparezca la encuesta (o el aviso) para el número marcado; que funcione con la sesión ya iniciada y también si toca iniciar sesión (el número debe sobrevivir al login); que Atrás no vuelva a abrir la búsqueda; y que con la encuesta abierta una segunda llamada no la pise (espera a que se cierre la primera). Anotar cada caso en `REGISTRO.md` sin el número real.

**Reversa:** volver la acción a «Lanzar app → Avance CRM» (o a la URL sin número). En el CRM, si hiciera falta, basta con no montar `ReceptorLlamada` en `App.tsx`: la ruta se ignora y todo lo demás sigue igual.

## 3c. Macro definitiva de salientes para F3 (F3-c) — armada y probada en C1 el 02/10/2026

**Estado:** armada en C1 (Samsung A16, Android 16, MacroDroid 5.67 gratuito, en español) y **las 7 pruebas de aceptación PASS** contra el receptor de pruebas del PC (`REGISTRO.md` §5e). Sale de las 6 pruebas de F3.3 (§5d) y del **requisito de Jhosep**: el reenvío funciona desde cualquier red y sin pedir ubicación (`docs/plans/llamadas-celular/F3-PLAN-CORTO.md`). Todos los nombres de pantalla de esta sección son los que se vieron en C1.

**Decisiones (de Claude, para Jhosep y Miguel):**
- **Por ahora solo salientes** entran en la cola y abren la encuesta. Las entrantes de leads y clientes vuelven con la propuesta #14 (pendiente de Miguel), con los disparadores «Llamada entrante» y «Llamada perdida».
- Al colgar, la encuesta se abre **enseguida** con la URL de F1, sin esperar al servidor.
- La **clave** y la **URL del servidor** viven en un solo sitio: la «Solicitud HTTP» de «Llamadas-Enviar cola».
- Solo el **400** se trata como rechazo definitivo (se aparta con aviso): los demás errores permanentes (409, 413, 415) no pueden salir de esta macro, porque el aviso se arma una sola vez con un tamaño y un formato fijos. Cualquier otro fallo (sin red, 401, 429, 5xx) deja el aviso en la cola para el próximo intento.
- No se sale del bucle al fallar un envío: sin red, cada intento falla y el aviso se queda igual; salir antes solo ahorraba segundos.

**Límite de MacroDroid gratuito: 5 macros por celular.** Estas tres + «Piloto F0» (apagada, de reserva) = 4. Con las entrantes (#14) harían falta más: decisión de Miguel sobre comprar MacroDroid Pro (`REGISTRO.md` §6). **03/10: Jhosep decidió comprar Pro** (S/19 por celular): el diseño con entrantes y latido está en §3d.

### Paso 1 — Variables globales

Pantalla principal de MacroDroid → recuadro **«Variables globales»** → botón **+** (abajo a la derecha). Todo lo creado ahí es global: lo comparten las macros y sobrevive al reinicio.

| Variable | Tipo | Para qué |
| --- | --- | --- |
| `cola_llamadas` | Diccionario | Avisos pendientes: clave = id de la llamada, valor = el aviso JSON |
| `errores_llamadas` | Diccionario | Avisos que el servidor rechazó para siempre (400), para revisarlos sin bloquear la cola |
| `en_saliente` | Booleana, valor Falso | «Llamadas-Salientes» la pone en Verdadero al marcar; «Al colgar» la lee y la vuelve a Falso |

### Paso 2 — Macro «Llamadas-Salientes»

- **Disparador:** «Llamada saliente» → «Cualquier Número».
- **Acción:** Variables → «Fijar Variable» → `en_saliente` → **Verdadero** (no tocar «PROBAR»).

### Paso 3 — Macro «Llamadas-Enviar cola»

- **Disparadores:**
  - Conectividad → **«Cambio de Conectividad de Datos»** → **«Datos Disponibles»**.
  - Fecha/Hora → **«Intervalo regular»** → 0 h **5 min** 0 s; «Usar hora de inicio de referencia» ✓ 00:00 (dispara en minutos terminados en 0 y 5); «Usar alarma» ✓ (dispara con la pantalla apagada).
  - **Nunca** «Cambio de estado de Wifi → Conectado a la red» con un nombre de red: pide permiso de ubicación y no funciona en otra oficina (requisito de Jhosep).
  - Hallazgo (A3): con los datos móviles activos, encender el Wi-Fi **no** dispara «Datos Disponibles» (para el celular, el internet no se cortó); el intervalo recoge lo pendiente. Demora máxima tras volver la red: ~5 min + 10 s.
- **Acciones**, en este orden (lo sangrado va **dentro** del bloque de arriba; en pantalla se ve corrido a la derecha):
  ```
  Espera antes de la siguiente acción: 10 s («Usar alarma» ✓)       (categoría Macros)
  Iterar Diccionario/Arreglo: cola_llamadas → «Este Diccionario»     (Condiciones/Bucles)
      Fijar Variable: codigo (local, entera) = 0
      Solicitud HTTP (POST)
      Si codigo = 202                                                (condición «Variable MacroDroid», en MacroDroid Propio)
          Borrar Entrada de Arreglo/Diccionario: cola_llamadas[{iterator_dictionary_key}] → «Eliminar clave»
      Fin de Si
      Si codigo = 400
          Fijar Variable: errores_llamadas[{iterator_dictionary_key}] = {iterator_value}   (tipo Cadena)
          Borrar Entrada de Arreglo/Diccionario: cola_llamadas[{iterator_dictionary_key}] → «Eliminar clave»
          Mostrar notificación: «Llamadas» / «Un aviso de llamada fue rechazado»          (sin el número)
      Fin de Si
  Fin de Bucle
  ```
- **«Solicitud HTTP»:** método **POST**; la URL del servidor; «Bloquear las siguientes acciones hasta completar» ✓; «Guardar el código de retorno HTTP en una variable entera» → `codigo`; pestaña **«Cuerpo del Contenido»**: tipo `application/json`, Texto `{iterator_value}`; pestaña **«Parámetros de Encabezado»**: solo `x-celular-credencial` = la clave (**no** añadir `Content-Type` a mano: lo pone el tipo de contenido y duplicado daría 415).
- **Trampas vistas al armarla:**
  - La clave de un diccionario va **entre corchetes** en «Define manualmente»: `[{iterator_dictionary_key}]` (sin corchetes sale una X roja y «ACEPTAR» queda gris).
  - Borrar una entrada: **«Eliminar clave»**, no «Borrar valor» (este deja el compartimento vacío y la siguiente vuelta mandaría un aviso vacío).
  - Para un segundo caso usar **otro «Si» con su propio «Fin de Si»**; un «Si» sin cerrar da «Macro inválido: Estructura de control no válido en: Fin de Bucle».
  - La lista de acciones solo muestra la URL de la «Solicitud HTTP», no su cuerpo: para revisarlo hay que abrirla.
- Si dos disparos coinciden y un aviso sale dos veces, no pasa nada: el servidor responde 202 «repetida» (idempotencia por id).

### Paso 4 — Macro «Llamadas-Al colgar» (sustituye a «Piloto F0»)

Se arma clonando «Piloto F0» (mantener pulsada → Clonar) para conservar la acción «Abrir Sitio web» ya configurada; se borran su notificación, su «Registrar evento» (los dos mostraban el número) y la acción apagada «Lanzar CRM Avance Corp».

- **Disparador:** «Llamada terminada» → «Cualquier Número» (no ofrece elegir saliente o entrante: por eso existe `en_saliente`).
- **Acciones:**
  ```
  Si en_saliente = Verdadero
      Fijar Variable: id_llamada (local, Cadena) = C1-{system_time}
      Fijar Variable: cola_llamadas[{lv=id_llamada}] (Cadena) = el aviso (abajo)
      Abrir Sitio web: https://crm.miavance.com/#/gestion-diaria/llamada/{call_number}   («codificación de URL» desmarcada)
      Iniciar macro: Llamadas-Enviar cola   («Omitir restricciones» ✓, «Siempre iniciar» ✓, «Bloquear…» sin marcar)
  Fin de Si
  Fijar Variable: en_saliente = Falso
  ```
- **El aviso** (pegarlo, no teclearlo: el teclado cambia las comillas rectas por curvas y el servidor lo rechaza con 400):
  ```
  {"accion":"llamada","evento":{"v":1,"evento_origen_id":"{lv=id_llamada}","numero":"{call_number}","direccion":"saliente","ocurrio_en":"{datetime}-05:00"}}
  ```
  `{datetime}` es texto mágico de MacroDroid (`aaaa-MM-dd HH:mm:ss` en la hora del celular); el `-05:00` (Lima, sin horario de verano) es obligatorio: sin él, el servidor, que trabaja en UTC, la leería 5 horas corrida. Así un aviso reenviado horas después conserva la hora real de la llamada (comprobado en A3, A4 y A6). `{system_time}` está en segundos: basta, un celular no termina dos llamadas en el mismo segundo.
- **Sin notificación ni «Registrar evento» con el número** (prueba 6).

### Antes de usarla

| Macro | Estado |
| --- | --- |
| Piloto F0 | Apagada (si siguiera encendida se abrirían dos encuestas) |
| Llamadas-Salientes | Encendida |
| Llamadas-Al colgar | Encendida |
| Llamadas-Enviar cola | Encendida (la copia sale desactivada) |

**URL del servidor:** mientras Miguel no despliegue la Edge, la del receptor de pruebas (`http://<IP del PC>:8787/functions/v1/crm-llamadas-ingesta`, solo dentro de la oficina y con el receptor encendido). Al desplegar, en la «Solicitud HTTP» cambian solo el servidor (misma ruta) y la clave de prueba por la del celular que da «asignar celular» (se muestra una vez).

### Pruebas de aceptación (todas PASS el 02/10, detalle en `REGISTRO.md` §5e)

| # | Caso | Resultado |
| --- | --- | --- |
| A1 | Saliente con Wi-Fi (a un número sin lead y a un lead) | Una sola pantalla del CRM y un solo aviso por llamada, ~11 s después, con la hora real |
| A2 | Entrante | Ni encuesta ni aviso |
| A3 | Dos salientes sin Wi-Fi | Quedan en la cola y llegan las dos con su hora (el intervalo recoge la vuelta del Wi-Fi) |
| A4 | 503 forzado desde el PC | El aviso se queda y el intervalo lo reintenta con el mismo id → 202 |
| A5 | Entrada dañada añadida a mano | 400 → pasa a `errores_llamadas` con aviso sin número; la cola sigue |
| A6 | Reinicio con un aviso pendiente | Sobrevive y sale solo con su hora original; el intervalo se reactiva solo |
| A7 | Permiso de ubicación | Ningún disparador definitivo lo pidió |

Con la Edge desplegada se repiten A1 y A3 **con datos móviles** (cualquier red), más las pruebas 1 y 6 de F3.3. Pendiente para después: el latido de salud (decisión 3 de F3: cada 6 h y al vaciar la cola), las entrantes (#14) y la lista de casos de F3-d. **El diseño del latido y de las entrantes está en §3d (03/10), sin probar.**

## 3d. Entrantes y latido, con MacroDroid Pro — diseño del 03/10/2026, SIN ARMAR NI PROBAR

**Estado:** diseño. Nada de esta sección se armó ni se probó todavía. Decisión de Jhosep (03/10): **comprar MacroDroid Pro** (S/19 por celular, pago único ligado a la cuenta de Google del teléfono) para usar las macros que hagan falta. Se descartó quedarse en 5 macros: para distinguir una entrante contestada de una perdida había que esperar unos segundos al colgar, y una perdida podía quedar registrada como contestada.

**Qué cambia frente a §3c:**
- **Entrantes de leads (#14, aprobada el 02/10)**: la contestada manda un aviso «conectada» y la no contestada uno «no_atendida». Con este último, el CRM creará «devolver la llamada» cuando exista el servidor de la #14. Hasta entonces el servidor las recibe y no las guarda (perilla de entrantes apagada; la corrección de F2 + F3 la bloquea).
- **Latido** (decisión 3 de F3, ratificada): cada 6 h y cuando la cola se vacía.
- **Menor 16 de la revisión** (`REVISION-2026-10-02.md`): si «Llamada terminada» no se disparara, `en_saliente` quedaba en Verdadero y la siguiente entrante se colaba como saliente. Ahora «Al colgar» ignora una marca de saliente con más de 2 h (`t_saliente`): ninguna llamada dura tanto.

**Decisiones de Claude:**
- La contestada se detecta **con un disparador propio** («Llamada activa», que en una entrante se dispara al contestar). Nunca esperando: un hecho, no una suposición.
- **Saliente y entrante no se pisan.** «Llamadas-Entrante» no toca nada de la saliente. Si entra una llamada en espera mientras el analista habla con un lead, la saliente conserva su aviso y su encuesta, y la entrante en espera sale como no atendida si no se contesta. Apagar `en_saliente` al sonar una entrante, como proponía el plan, rompería justo ese caso.
- **Una sola clave por entrante**, creada cuando suena (`id_entrante`) y con la hora del timbre (`hora_entrante`). «Perdida» y «Al colgar» escriben la misma entrada con el mismo contenido. Se dispare primero la que se dispare, sale un solo aviso, y el servidor lo ve como repetido si llegara dos veces.
- **Las entrantes todavía no abren la encuesta.** Hoy F1 muestra «ningún lead» con cualquier número que no sea lead, y abrirla con cada llamada personal molestaría. Se añade cuando F1 sepa callar con esos números (#14, caso c). Es un cambio pequeño de pantalla, y el objetivo sigue siendo que la encuesta se abra siempre con leads.

### Paso 0 — Antes de armar
- Comprar Pro en C1: menú de MacroDroid → «Pro». Comprobar que ya no aparece el aviso de 5 macros.
- Borrar «Piloto F0»: con Pro ya no hace falta de reserva.
- Vaciar `cola_llamadas` si tiene avisos de prueba (ver «Antes de usarla» en §3c).

### Paso 1 — Variables globales nuevas
| Variable | Tipo | Para qué |
| --- | --- | --- |
| `en_entrante` | Booleana, Falso | «Llamadas-Entrante» la pone en Verdadero al sonar; «Al colgar» y «Perdida» la vuelven a Falso |
| `en_contestada` | Booleana, Falso | «Llamadas-Contestada» la pone en Verdadero si la entrante se contesta |
| `id_entrante` | Cadena | Id de la entrante, creado al sonar: `C1-{system_time}` |
| `hora_entrante` | Cadena | Hora del timbre: `{datetime}` |
| `ultimo_latido` | Entera, 0 | `{system_time}` del último latido aceptado (200) |
| `t_saliente` | Entera, 0 | `{system_time}` de cuando empezó la saliente: con más de 2 h, «Al colgar» la ignora (menor 16) |

### Paso 2 — «Llamadas-Salientes» (ya existe): añadir una acción
Después de `en_saliente = Verdadero`: `t_saliente = {system_time}`. No toca las variables de las entrantes, porque una entrante contestada puede seguir en espera.

### Paso 3 — Macro nueva «Llamadas-Entrante»
- **Disparador:** «Llamada entrante» → «Cualquier Número». Se dispara cuando empieza a sonar.
- **Acciones:**
  ```
  Fijar Variable: en_entrante = Verdadero
  Fijar Variable: en_contestada = Falso
  Fijar Variable: id_entrante (Cadena) = C1-{system_time}
  Fijar Variable: hora_entrante (Cadena) = {datetime}
  ```

### Paso 4 — Macro nueva «Llamadas-Contestada»
- **Disparador:** «Llamada activa» (en inglés «Call Active»; confirmar el nombre en pantalla) → «Cualquier Número». Si deja elegir «entrante», elegirla.
- **Acciones:**
  ```
  Si en_entrante = Verdadero
      Fijar Variable: en_contestada = Verdadero
  Fin de Si
  ```
  La condición evita que una saliente cuente como contestada, porque «Llamada activa» también se dispara al marcar.

### Paso 5 — Macro nueva «Llamadas-Perdida»
- **Disparador:** «Llamada perdida» → «Cualquier Número».
- **Acciones:**
  ```
  Si en_entrante = Verdadero
      Fijar Variable: cola_llamadas[{v=id_entrante}] (Cadena) = el aviso «no atendida» (abajo)
      Fijar Variable: en_entrante = Falso
      Iniciar macro: Llamadas-Enviar cola   («Omitir restricciones» ✓, «Siempre iniciar» ✓)
  Fin de Si
  ```

### Paso 6 — «Llamadas-Al colgar» (ya existe): una guarda ANTES y un bloque DESPUÉS de las salientes
```
Fijar Variable: desde_saliente (local, Entera) = {system_time} - {v=t_saliente}     (va al principio)
Si desde_saliente >= 7200                                                         (2 h: marca vieja)
    Fijar Variable: en_saliente = Falso
Fin de Si
Si en_saliente = Verdadero
    … igual que en §3c, sin cambios …
Fin de Si
Si en_entrante = Verdadero
    Si en_contestada = Verdadero
        Fijar Variable: cola_llamadas[{v=id_entrante}] (Cadena) = el aviso «conectada» (abajo)
    Fin de Si
    Si en_contestada = Falso
        Fijar Variable: cola_llamadas[{v=id_entrante}] (Cadena) = el aviso «no atendida» (abajo)
    Fin de Si
    Iniciar macro: Llamadas-Enviar cola   («Omitir restricciones» ✓, «Siempre iniciar» ✓)
Fin de Si
Fijar Variable: en_saliente = Falso
Fijar Variable: en_entrante = Falso
Fijar Variable: en_contestada = Falso
```
Si «Llamada perdida» ya se disparó, puso `en_entrante = Falso` y este bloque no hace nada. Si se dispara después, encuentra `en_entrante = Falso` y tampoco. En los dos órdenes queda un solo aviso.

**Los avisos** (pegarlos, no teclearlos: el teclado cambia las comillas rectas por curvas):
```
conectada:    {"accion":"llamada","evento":{"v":1,"evento_origen_id":"{v=id_entrante}","numero":"{call_number}","direccion":"entrante","estado_tecnico":"conectada","ocurrio_en":"{v=hora_entrante}-05:00"}}
no atendida:  {"accion":"llamada","evento":{"v":1,"evento_origen_id":"{v=id_entrante}","numero":"{call_number}","direccion":"entrante","estado_tecnico":"no_atendida","ocurrio_en":"{v=hora_entrante}-05:00"}}
```
`{v=…}` es el texto mágico de una variable **global**; el `{lv=…}` de §3c es el de una local. La hora es la del timbre: así el aviso de «Perdida» y el de «Al colgar» son idénticos.

### Paso 7 — «Llamadas-Enviar cola» (ya existe): el latido, al final
Después de `Fin de Bucle`:
```
Fijar Variable: quedan (local, Entera) = 0
Iterar Diccionario/Arreglo: cola_llamadas
    Fijar Variable: quedan = {lv=quedan} + 1        (valor como expresión; confirmar en pantalla)
Fin de Bucle
Fijar Variable: desde_latido (local, Entera) = {system_time} - {v=ultimo_latido}
Fijar Variable: toca (local, Booleana) = Falso
Si desde_latido >= 21600                            (6 h)
    Fijar Variable: toca = Verdadero
Fin de Si
Si habia > 0
    Si quedan = 0                                   (la cola se acaba de vaciar)
        Fijar Variable: toca = Verdadero
    Fin de Si
Fin de Si
Si toca = Verdadero
    Fijar Variable: codigo_latido (local, Entera) = 0
    Solicitud HTTP (POST): la misma URL y la misma clave; cuerpo = el latido (abajo); código → codigo_latido
    Si codigo_latido = 200
        Fijar Variable: ultimo_latido = {system_time}
    Fin de Si
Fin de Si
```
`habia` se cuenta igual que `quedan`, pero **antes** del bucle de envío (un «Iterar» más al principio de la macro).
**El latido:**
```
{"accion":"latido","latido":{"v":1,"version_macro":"llamadas-v2","en_cola":{lv=quedan},"ocurrio_en":"{datetime}-05:00"}}
```
El servidor exige exactamente esas cuatro claves. `version_macro` admite letras, dígitos, espacio y `. _ -`, y `en_cola` va de 0 a 100000. Responde **200**, no 202.

### Antes de usarla
| Macro | Estado |
| --- | --- |
| Llamadas-Salientes | Encendida (con las 2 acciones nuevas) |
| Llamadas-Entrante | Encendida |
| Llamadas-Contestada | Encendida |
| Llamadas-Perdida | Encendida |
| Llamadas-Al colgar | Encendida (con el bloque de entrantes) |
| Llamadas-Enviar cola | Encendida (con el latido) |

### Pruebas de aceptación (contra el receptor del PC; anotar en `REGISTRO.md`)
| # | Caso | Qué se espera |
| --- | --- | --- |
| B1 | Entrante **contestada** de un número de prueba | Un solo aviso «entrante · conectada» con la hora del timbre; sin encuesta (todavía) |
| B2 | Entrante **no contestada** (dejar sonar hasta que corte) | Un solo aviso «entrante · no_atendida», aunque se disparen «Perdida» y «Al colgar» |
| B3 | Entrante **rechazada** (colgar sin contestar) | Un aviso «no_atendida». Si no sale ninguno, anotarlo: dice qué disparadores usa Android al rechazar |
| B4 | Saliente justo después de una entrante | Aviso «saliente» normal y encuesta |
| B5 | **Llamada en espera:** entra una llamada mientras hablas con un lead y no la contestas | La saliente conserva su aviso y su encuesta al colgar; la de espera sale «no_atendida». Caso pendiente desde F3.3.4 |
| B5b | Llamada en espera contestada (cambias de llamada) | Anotar qué pasa: es el caso raro, y dice qué número entrega «Llamada terminada» |
| B6 | Latido al vaciar la cola: una saliente y esperar el envío | Llega un latido con `en_cola` 0 (en el receptor, `/_estado` muestra el último latido) |
| B7 | Latido cada 6 h, sin llamadas | Anotar la hora del siguiente latido |
| B8 | Repetir A1 y A3 de §3c | Igual que el 02/10: las salientes no cambiaron |
| B9 | Ningún disparador pide permiso de ubicación | Como A7 |

## 4. Cómo cerrar cada comprobación de F0.3

| Tarea | Qué hacer | Qué anotar en `REGISTRO.md` |
| --- | --- | --- |
| F0.3.1 | Al menos 10 salientes y 10 entrantes por celular, más una atendida, una perdida, una rechazada y una cancelada | Por llamada: fecha, tipo, ¿llegó el número en la notificación?, ¿quedó en el log? |
| F0.3.2 | Un número oculto, un fijo, uno internacional, doble SIM si el equipo la tiene; enlace con `+`; cerrar sesión y volver a entrar; ver que la URL abre la PWA | Resultado por caso y qué vía de apertura funcionó (Open Website / Send Intent) |
| F0.3.3 | Pantalla bloqueada; batería baja; tres noches seguidas; reiniciar el celular y llamar; quitar la red, llamar y reconectar | ¿Disparó? ¿Cuánto tardó? ¿Se perdió alguna respecto al registro del teléfono? |

**Comparar siempre con el registro de llamadas del teléfono**: la cuenta del log de MacroDroid debe coincidir con la del teléfono; cada diferencia es una llamada perdida o duplicada y se anota.

## 5. Privacidad en F0

- El número aparece solo en la notificación y en el log del propio celular. No hay envío a servidores en F0.
- Al terminar el piloto, borrar el log de MacroDroid y las notificaciones. En `REGISTRO.md` y `compatibilidad.md` **no se escriben números reales**: se anota «número de lead», «número desconocido», «oculto».

## 6. Fuentes (consultadas el 29/09/2026)

- MacroDroid: [Trigger: Call Ended](https://wiki.macrodroid.com/wiki/index.php/Trigger:_Call_Ended) · [Trigger: Call Outgoing](https://wiki.macrodroid.com/wiki/index.php/Trigger:_Call_Outgoing) · [Trigger: Call Active](https://wiki.macrodroid.com/wiki/index.php/Trigger:_Call_Active) · [Magic text](https://wiki.macrodroid.com/wiki/index.php/Magic_text) · [Action: Open Website](https://wiki.macrodroid.com/wiki/index.php/Action:_Open_Website_/_HTTP_GET) · [Action: Send Intent](https://wiki.macrodroid.com/wiki/index.php/Action:_Send_Intent) · [Helper App](https://wiki.macrodroid.com/wiki/index.php?title=Helper_App) · [ADB Hack](https://wiki.macrodroid.com/wiki/index.php/ADB_Hack) · [ficha en Google Play](https://play.google.com/store/apps/details?id=com.arlosoft.macrodroid&hl=en_US)
- Google Play: [permisos de SMS y registro de llamadas](https://support.google.com/googleplay/android-developer/answer/10208820)
- Android: [cambios de Android 9](https://developer.android.com/about/versions/pie/android-9.0-changes-all) · [`EXTRA_INCOMING_NUMBER`](https://developer.android.com/reference/android/telephony/TelephonyManager#EXTRA_INCOMING_NUMBER) · [apertura desde segundo plano](https://developer.android.com/guide/components/activities/secure-bal) · [filtros de intent](https://developer.android.com/guide/components/intents-filters#DataTest) · [`CallLog.Calls.DURATION`](https://developer.android.com/reference/android/provider/CallLog.Calls#DURATION)
- Chromium: [WebAPK no verificado en Android 12+](https://github.com/chromium/chromium/blob/main/components/external_intents/android/java/src/org/chromium/components/external_intents/ExternalNavigationHandler.java)
- Tasker: [variables `%CONUM` / `%CODUR`](https://tasker.joaoapps.com/userguide/en/variables.html)

Pendiente de dispositivo: que `{call_number}` llegue relleno en salientes con Android 12–15; que la variable de dirección pase de «Call Outgoing» a «Call Ended»; el «Send Intent» al WebAPK; si «Call Ended» dispara antes de que el sistema escriba el registro de llamadas.
