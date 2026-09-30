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

**«Lanzar app» ya no basta** para F1: abre la app pero no puede pasarle el número.

**Qué mirar en el celular (F1.4.2):** que la app se abra en Gestión Diaria y aparezca la encuesta (o el aviso) para el número marcado; que funcione con la sesión ya iniciada y también si toca iniciar sesión (el número debe sobrevivir al login); que Atrás no vuelva a abrir la búsqueda; y que con la encuesta abierta una segunda llamada no la pise (espera a que se cierre la primera). Anotar cada caso en `REGISTRO.md` sin el número real.

**Reversa:** volver la acción a «Lanzar app → Avance CRM» (o a la URL sin número). En el CRM, si hiciera falta, basta con no montar `ReceptorLlamada` en `App.tsx`: la ruta se ignora y todo lo demás sigue igual.

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
