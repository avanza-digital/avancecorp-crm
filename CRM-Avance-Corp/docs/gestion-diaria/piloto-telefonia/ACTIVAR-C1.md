# Activar C1 — guía del día (F4-d)

Paso a paso para encender de verdad la captura de llamadas en el celular C1. Se usa **una sola vez**, el día que Miguel
avise que la base está lista. Una acción por línea; al lado de cada prueba, qué tiene que pasar.

Escrita el 07/10/2026 a partir del runbook de `docs/plans/llamadas-celular/F4C-F4D-PLAN-CORTO.md` (F4-d) y de la macro
final de `macrodroid.md` §3c. Si algo de aquí no coincide con lo que ves en pantalla, para y avisa: no improvises.

## 0. No empieces hasta que Miguel avise estas cuatro cosas

- [ ] Las doce migraciones de llamadas **aplicadas en producción**, cada registrador con veredicto `t`.
- [ ] La Edge `crm-llamadas-ingesta` **desplegada**.
- [ ] Una release con el interruptor **`LLAMADAS_CELULAR_APROBADAS = true`**: en el CRM ya se ve la tarjeta «Celulares»
  en Configuración y la pestaña «Llamadas del celular» en Gestión Diaria.
- [ ] El #215 (la tarjeta «Celulares») fusionado y dentro de esa release.

Antes de esas cuatro, **instalar no es activar**: C1 sigue apuntando al receptor de pruebas del PC.

## 1. Preparar (antes de tocar nada)

- [ ] **C1 cargado** y con Wi-Fi o datos.
- [ ] **MacroDroid encendido:** en su pantalla de Inicio no debe decir «MacroDroid está actualmente desactivado».
  - Con la versión gratuita: Inicio → «Añadir Días Gratuitos» → interruptor de arriba a la derecha. Vence cada 3 días.
- [ ] **Hora automática** activada en el celular (en el Samsung: Ajustes → Administración general → Fecha y hora).
- [ ] En C1, el CRM abierto con **la cuenta que va a tener C1**. Tiene que ser la misma que elijas al asignar: la
  llamada solo se une si el celular es de quien registra.
- [ ] **Dos leads de prueba** («PRUEBA C1 A» y «PRUEBA C1 B») en la cartera de esa cuenta, con teléfonos del equipo y
  su permiso. Las pruebas dejan gestiones reales en las cifras de esa cuenta.
- [ ] Alguien con **cuenta de gerencia** a mano, en la PC.

## 2. Dar de alta C1 (gerencia, en la PC)

1. CRM → **Configuración** → tarjeta **«Celulares»** → **Abrir**.
2. **«Asignar celular»**.
3. Etiqueta: **C1**.
4. Analista: **la cuenta de C1** (la del paso 1).
5. **«Asignar y ver la clave»**.
6. **«Copiar»**.
7. Manda la clave al celular C1 por WhatsApp (o el canal que uses). **A mí (Claude) no me la pases.**
8. **No cierres la ventana todavía.** Primero termina la parte 3.
9. Cuando la clave ya esté pegada en MacroDroid: **«Ya la copié al celular»**.

La fila de C1 aparece como **«Nunca habló»**. Es lo normal: todavía no mandó su primer latido.

## 3. Poner la clave en C1 (en MacroDroid, sin tocar ninguna macro)

Todo es en **MacroDroid → Variables**.

1. **`cola_llamadas`**: ábrela y borra **cada** entrada con **«Eliminar clave»** (no «Borrar valor»: ese deja la entrada
   vacía y la siguiente vuelta mandaría un aviso vacío). Tiene que quedar sin entradas.
2. **`errores_llamadas`**: lo mismo.
   - Por qué se vacían **ahora**: es el alta. Lo que quedara ahí sería de las pruebas con el receptor del PC.
   - Ojo: **al rotar la clave no se vacían.** Eso es otro caso (prueba P11).
   - **Al rotar la clave (hallazgo H-P11, 08/10):** se pega la nueva en `clave_celular` **y se pone `ultimo_latido` en 0**,
     igual que en el alta. Rotar abre una asignación nueva que todavía no tiene latido: sin este paso, la tarjeta dice
     «Nunca habló» hasta el siguiente latido, que puede tardar hasta 6 horas, aunque las llamadas ya lleguen bien.
3. **`url_llamadas`**: borra lo que tiene y pon exactamente:
   `https://dctqcbznekcyxhjujuci.supabase.co/functions/v1/crm-llamadas-ingesta`
4. **`clave_celular`**: borra lo que tiene y pega la clave que te llegó.
5. **`ultimo_latido`**: pon **0**. Así la próxima vuelta manda el primer latido.
6. Revisa las macros (pestaña Macros):

   | Macro | Tiene que estar |
   | --- | --- |
   | Llamadas-Salientes | Encendida |
   | Llamadas-Al colgar | Encendida |
   | Llamadas-Enviar cola | Encendida |
   | Piloto F0 | **Apagada** (si sigue encendida, se abren dos encuestas) |

7. Ya puedes borrar el mensaje de WhatsApp con la clave: no hace falta guardarlo. Si algún día se pierde, se rota.
8. Vuelve a la PC y pulsa **«Ya la copié al celular»** (paso 2.9).

## 4. Comprobar que vive (en ≤ 5 minutos)

En la PC, Configuración › Celulares. En la fila de C1 tiene que aparecer:

- [ ] Salud: **«Al día»**.
- [ ] Macro: **`llamadas-v3`**.
- [ ] En cola: **0**.

Si a los 10 minutos sigue «Nunca habló»:
- ¿MacroDroid sigue encendido? (paso 1).
- ¿C1 tiene internet?
- ¿La URL quedó exacta, sin espacios? (paso 3.3).
- Si en C1 salió la notificación **«La clave de este celular ya no vale…»**, la clave se pegó mal: vuelve a pegarla. Si
  ya no la tienes, gerencia la **rota** desde la tarjeta y sale otra. Al pegar la nueva, pon también `ultimo_latido` en 0 (paso 3.5).

## 5. Las pruebas (P1–P15)

Anota cada una como **PASS**, **FAIL** o **NOT RUN**, sin números de teléfono ni nombres. Si una falla, anota qué viste
y sigue con la próxima solo si no depende de ella.

**Con la encuesta**

| # | Qué haces | Qué tiene que pasar |
| --- | --- | --- |
| P1 | Llamas a PRUEBA A, cuelgas y guardas el resultado **enseguida** | Se abre la encuesta. Al guardar dice «Quedará unido a tu llamada del celular … en cuanto llegue su aviso» |
| P2 | Llamas otra vez, cuelgas y **esperas ~30 segundos** antes de guardar | Al guardar dice «Quedó unido a tu llamada del celular …» |
| P3 | **Sin red:** apagas Wi-Fi y datos, llamas, cuelgas; vuelves a encender la red y guardas | El aviso llega solo al volver la red y en ≤ 5 minutos la llamada queda unida |
| P4 | Llamas a PRUEBA A y a PRUEBA B seguidas (menos de 10 minutos) y guardas cada una | Cada resultado queda unido a **su** llamada; no se cruzan |
| P5 | Llamas a A, **dejas la encuesta abierta** sin guardar y llamas a B | Cada encuesta queda con su llamada; una no pisa a la otra |
| P6 | Llamas, **cierras la encuesta sin guardar** y registras desde la pestaña «Llamadas del celular» **en el celular** | La llamada se une igual. En «Qué pasó hoy» dice «Registrada desde "Llamadas del celular"» |
| P7 | Lo mismo que P6, pero registrando **desde la PC** | Igual que P6 |
| P8 | Abres a mano una encuesta con el id de **otro celular** (Claude te pasa la dirección exacta ese día) | Al guardar dice «…no se unió a la llamada del celular: la llamada es de otro celular» |
| P9 | Guardas un resultado, pulsas **Deshacer** y lo corriges | Queda **un solo** enlace: el del resultado corregido |

**Dueño y clave**

| # | Qué haces | Qué tiene que pasar |
| --- | --- | --- |
| P10 | Llamas a PRUEBA B y, **antes de registrar**, gerencia reasigna ese lead a otra persona | La llamada sigue al **dueño actual** del lead (decisión 7). Anota qué ves en tu pestaña y en la de la otra persona |
| P11 | Gerencia **rota** la clave de C1. Haces una llamada con la clave vieja. Después pegas la clave nueva **sin vaciar las colas** y pones `ultimo_latido` en 0 | Con la vieja, C1 avisa «La clave de este celular ya no vale…» y la llamada **espera en la cola**. Con la nueva, la cola se vacía sola y, con el latido de la vuelta siguiente, la tarjeta vuelve a «Al día» (sin poner `ultimo_latido` en 0 tarda hasta 6 h: hallazgo H-P11, 08/10) |

**Lo que no debe guardarse**

| # | Qué haces | Qué tiene que pasar |
| --- | --- | --- |
| P12 | Alguien **te llama** a C1 | Nada: ni encuesta ni aviso (las entrantes van con la propuesta #14) |
| P13 | Llamas a un número que **no es lead** | El CRM no guarda la llamada: no aparece en tu pestaña |

**El celular por dentro** (con Claude al lado ese día: algunas son técnicas)

| # | Qué haces | Qué tiene que pasar |
| --- | --- | --- |
| P14 | **Latidos:** una llamada sin red y vuelve la red (L2); seis horas sin llamar (L3); una entrada a mano con otra etiqueta (L4) | L2: llega el aviso y **ningún** latido extra. L3: anotar a qué hora sale el siguiente latido; la tarjeta sigue «Al día». L4: rechazada, pasa a `errores_llamadas` con un aviso sin número y la cola sigue |
| P15 | **Con datos móviles** (Wi-Fi apagado): una llamada (A1) y dos seguidas (A3). Después, reiniciar el celular con un aviso pendiente (A6). Y revisar dónde vive la clave (F3.3, prueba 6) | A1 y A3: los avisos llegan por datos móviles, con su hora (con el receptor del PC solo funcionaba con el Wi-Fi de la oficina). A6: el aviso sobrevive al reinicio y sale solo. Prueba 6: el registro de MacroDroid **no** muestra la clave |

**Al cerrar las pruebas:**
- Cuántas llamadas hiciste (según el registro del teléfono) = cuántas recibió el CRM.
- **0** resultados unidos dos veces.
- «Encuesta abierta al colgar: N de N».
- Miguel lo confirma en la base con una consulta sin números (recibidas, guardadas, sin duplicados y el sello de la v4
  intacto). Claude marca las casillas de F4.4 con esa evidencia.

## 6. Si algo sale mal (volver atrás)

En la base no hay marcha atrás: se **apaga**. Del más suave al más fuerte:

1. **La encuesta no une las llamadas.**
   - En MacroDroid, macro «Llamadas-Al colgar», acción «Abrir sitio web»: quita el final `/{lv=id_llamada}` de la dirección.
   - La encuesta guarda como antes; las llamadas se unen a mano desde la pestaña «Llamadas del celular».
2. **El celular no captura bien.**
   - Gerencia cierra C1 en la tarjeta, motivo **«Otro»**: la clave deja de valer al instante.
   - En MacroDroid: `url_llamadas` vuelve al receptor de pruebas y se vacían las colas.
   - Lo que quedó pendiente se descarta con el motivo «Número de prueba», o se borra solo a los 30 días.
3. **Último recurso (Miguel).** Borrar la Edge (solo C1 está activo) o volver a la release anterior con el interruptor
   apagado.

Regla de Miguel (07/10): con altas o uso, **nunca** se ejecutan las reversas SQL. Se cierra la asignación o la clave, o
se apaga la pantalla con un release aprobado; el historial se conserva y se corrige hacia adelante.

## 7. Qué reportar y a quién

- **A Miguel**, en el PR de F4-d, un solo comentario: `QUÉ HICE · RESULTADO (P1–P15) · TURNO PARA`.
- **Capturas sin la clave y sin números.**
- La clave **nunca** va al repo, a un comentario ni a Claude.
- Claude actualiza `REGISTRO.md`, la bitácora de `COORDINACION.md` y el tablero.

## En llano

El día que Miguel deje lista la base, gerencia le da una clave a C1 desde la tarjeta, tú la pegas en MacroDroid junto con
la dirección del servidor, y en cinco minutos la tarjeta dice «Al día». Después se prueban quince situaciones —llamar y
guardar enseguida, sin red, dos seguidas, cambiar la clave, que te llamen— y se anota qué pasó en cada una. Si algo sale
mal, se apaga en tres niveles, del más suave al más fuerte.
