# Decisiones #16, #17 y #18 — «Llamadas desde el celular» (07/10/2026, aprobadas)

Pedidas por Miguel en el #215 (18:24 UTC): cada decisión abierta con una propuesta concreta y sus consecuencias.
Eran propuestas; **Miguel aprobó las tres el mismo día** (sección siguiente, copiada tal cual). Contexto completo en
`PROPUESTAS-DE-AJUSTE.md` (#16, #17, #18) y en `SEGUIMIENTO.md`.

Orden por urgencia: **#18** (vence el 09/10), **#16**, **#17**.

## Resultado: aprobadas por Miguel (07/10, 21:20 UTC)

Comentario de Miguel en el #215, tal cual:

> 1. **#18: MacroDroid Pro aprobado para el piloto de 2–3 celulares**, según la oferta verificada de S/19 por cuenta,
>    pago único (hasta S/57 si hacen falta tres compras). Compra/configura C1 con cuenta corporativa antes del
>    vencimiento registrado del 09/10 ~15:50 Lima. Verifica precio y condiciones en cada compra; si cambian o requiere
>    una suscripción, informa antes de aceptar ese cambio. No compartas credenciales ni datos de pago. Registra
>    equipo/licencia/fecha de forma saneada y confirma que desapareció el límite por días. La compra y su verificación
>    física las haces tú en los equipos.
> 2. **#16: aprobada.** F0 se acepta con diez salientes por equipo y los casos especiales del plan. Las diez entrantes
>    pasan a la aceptación de #14. No se elimina esa ampliación ni se marca como PASS lo no probado.
> 3. **#17 y decisión 4: aprobadas.** F4-e va en F4 como paso propio, después de la aceptación de F4-d en C1; F6
>    amplía la misma puerta/vista. A1 quien marcó; A2 fecha del resultado; A3 día de la llamada; A4 excluir leads de
>    baja; A5 un lead cerrado deja de pedir resultado; A6 siete horas para «sin latido»; A7 celular del supervisor en
>    línea aparte. Los rótulos deben hacer explícito qué fecha usa cada cifra. Los porcentajes deben usar numerador y
>    denominador de la misma cohorte; no dividir resultados de hoy entre llamadas ocurridas hoy si mezclan llamadas de
>    días distintos. «Sin dato» se mantiene separado de cero y no se cuentan llamadas personales como trabajo.

Lo que sigue en este archivo es el registro de lo que se propuso.

## #18 · MacroDroid Pro en los celulares de producción — aprobada para el piloto

**La pregunta:** ¿se compra MacroDroid Pro para los celulares que capturan llamadas?

**Por qué ahora:** la versión gratuita **se apaga sola** cuando vencen sus «días gratuitos» (en C1, +3 días por cada
anuncio visto). Apagada, ninguna macro corre aunque estén encendidas. C1 estuvo apagado del ~02/10 al 06/10 sin que
nadie lo notara (`REGISTRO.md`, incidencia del 06/10). **Hoy C1 vence el 09/10 a las ~15:50 Lima.**

**Lo verificado:**
- Pro es un **pago único**, sin suscripción: quita los anuncios, el límite de **5 macros** y el apagado por días
  (descripción de la app en Google Play y en tiendas de apps).
- La compra queda en la **cuenta de Google** que la hace: según el foro de MacroDroid, se usa en otros celulares
  con esa misma cuenta.
- **Precio: S/ 19, pago único** (visto por Jhosep en C1 el 07/10: MacroDroid → menú → «Actualizar a Pro», precio de
  Google Play en Perú).

**Propuesta:**
1. **Comprar Pro para C1 antes del 09/10**, con la cuenta de Google de C1.
2. Para producción: **una compra por cuenta de Google.** Si los celulares corporativos usan una misma cuenta de la
   empresa en Google Play, una compra los cubre a todos; si cada uno tiene su cuenta, una por celular. Con el piloto de
   2–3 celulares, el costo máximo es **S/ 38–57, una sola vez**.
3. Anotar en `compatibilidad.md` qué cuenta tiene cada equipo y si ya tiene Pro (F0.1.1).

| Si dice que sí | Si dice que no |
| --- | --- |
| Sin apagados, sin anuncios ni días que renovar | Cada analista tiene que abrir MacroDroid y mirar un anuncio cada ~3 días. El día que se le olvide, **sus llamadas no se registran**: el latido lo avisa («sin latido» en la tarjeta), pero no las recupera |
| Más de 5 macros: cabe la #14 (entrantes suma 3 macros; hoy usamos 4 de 5) | La #14 no cabe en la versión gratuita |
| Producción estable desde el primer día de F4-d | Hay usuarios que reportan que los anuncios **ya no suman días**: riesgo de que un celular quede apagado sin forma de renovarlo |

**Revisa:** la decisión «Pro todavía no» (Miguel, 03/10), tomada cuando la versión gratuita todavía no se apagaba.
**No recomiendo** cambiar de app: habría que rehacer y volver a probar todas las macros (pruebas 1–6, A1–A7, P1–P5).

## #16 · Cerrar el piloto (F0) con salientes — aprobada

**La pregunta:** ¿F0 se acepta con las llamadas salientes, dejando las «diez entrantes por equipo» para la #14?

**Por qué:** F0.3.1 y la aceptación de F0 piden «diez salientes y diez entrantes por equipo». Pero las entrantes
quedaron **bloqueadas** (decisión 2 de Miguel, 03/10): la base las ignora hasta la #14, que es un paso propio y
además necesita la #18.

**Propuesta:** F0 se acepta con **diez salientes por equipo** y sus casos (atendida, no atendida, rechazada,
cancelada), más los especiales de F0.3.2 y F0.3.3 (oculto, fijo, internacional, doble SIM, pantalla bloqueada,
batería, noches). **Las diez entrantes pasan a la aceptación de la #14.** Lo no ejecutado no se marca como aprobado.

| Si dice que sí | Si dice que no |
| --- | --- |
| F0 se puede cerrar con lo que el sistema hace hoy (salientes) | F0 queda abierta hasta construir y probar la #14, que espera a la #18 |
| Las entrantes se prueban donde se construyen (#14) | Se mezcla la aceptación del piloto con una ampliación todavía sin hacer |

## #17 · Diccionario de métricas (A1–A7) y dónde va la vista de supervisor y gerencia (decisión 4) — aprobadas

**La pregunta:** ¿cómo se cuenta cada cifra, y la vista del día va en F4 (como F4-e) o espera a F6?

**Por qué ahora:** sin esto no se puede construir F4-e ni F6.1–F6.3 (bloqueadas en el seguimiento). Hay prototipo
aprobado por Jhosep el 06/10; el prototipo no sustituye esta decisión.

**Propuesta, punto por punto** (detalle en `F4E-PLAN-CORTO.md`):

| # | Pregunta | Propuesta | En llano |
| --- | --- | --- | --- |
| 4 | ¿F4 o F6? | **F4, como paso propio (F4-e), después de activar C1 (F4-d).** F6 la amplía después, sin otra puerta | Supervisión y gerencia ven desde el piloto qué llamadas quedan sin resultado y qué celular calla. Si espera a F6, nadie lo ve hasta entonces |
| A1 | Lead que cambia de dueño: ¿a quién se cuenta la llamada? | **A quien marcó**; la pendiente dice «pasó a otro analista» | El esfuerzo es de quien llamó |
| A2 | «Con resultado»: ¿fecha del resultado o del enlace? | **Fecha del resultado** | Igual que la cifra del día de Gestión Diaria |
| A3 | «En el celular»: ¿día de la llamada o de la recepción? | **Día de la llamada**, explicando el retraso | Una llamada sin señal que llega mañana se cuenta en su día |
| A4 | ¿Leads dados de baja? | **Excluirlos** | Como la bandeja: nadie los ve |
| A5 | ¿Lead cerrado después de la llamada? | **Deja de ser «sin resultado»** | No se le pide resultado a algo ya cerrado |
| A6 | ¿Desde cuándo «sin latido»? | **7 horas** | Lo mismo que ya muestra la tarjeta «Celulares» |
| A7 | ¿El celular del supervisor? | **Una línea aparte** en su panel | «Mi equipo hoy» solo lista analistas |

**Reglas que van con el diccionario** (no son preguntas): nunca se suman llamadas detectadas y gestiones como si
fueran dos resultados; «—» (el celular no avisó) no es «0» (avisó y no hubo); con pocas llamadas, el conteo va al lado
del porcentaje.

| Si dice que sí | Si dice que no o cambia algo |
| --- | --- |
| Se escribe el plan corto de F4-e con la puerta y su oráculo, para su OK | Se ajusta el diccionario y el prototipo antes del plan corto |
| F6 reutiliza el mismo diccionario | — |

## Fuera de llamadas, pero bloquea F5

- **Rotar la clave de TypeSafe (Jev)** que se pegó en un chat el 20/09 (`scripts/jev/README.md:45`). Sin eso, F5.3.1
  no puede usar datos reales.

## Fuentes de lo verificado

- Google Play, ficha de MacroDroid: https://play.google.com/store/apps/details?id=com.arlosoft.macrodroid
- Foro de MacroDroid (uso de Pro con la misma cuenta en varios dispositivos):
  https://www.macrodroidforum.com/index.php?threads/can-i-use-macrodroid-subscription-in-two-profiles-in-android.5846/
- Reportes de usuarios sobre los «días gratuitos» y los anuncios: https://www.appbrain.com/app/macrodroid-device-automation/com.arlosoft.macrodroid
- Incidencia en C1: `docs/gestion-diaria/piloto-telefonia/REGISTRO.md` (06/10).
