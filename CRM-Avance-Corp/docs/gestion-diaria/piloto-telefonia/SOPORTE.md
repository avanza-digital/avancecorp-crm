# Soporte de llamadas desde el celular — guía única

Para quien atiende a los analistas con celular: en el piloto, Jhosep; para lo que pasa por la tarjeta «Celulares»,
alguien con cuenta de gerencia. Se busca por **lo que el analista ve**. Cada caso dice qué hacer y qué no tocar.

Escrita el 09/10/2026 con lo probado en C1 contra producción (`REGISTRO.md` §5i, P1–P15). Cómo se arma la macro:
`macrodroid.md` §3c. Cómo se da de alta un celular: `ACTIVAR-C1.md` §2–§4. Aquí no se repiten: se enlazan.

## 0. Reglas que no se rompen (sin secretos)

- **La clave del celular nunca pasa por soporte.** No se pide, no se manda por chat, no se dicta y no va en una captura
  ni en un ticket. Si alguien la pide «para revisar», la respuesta es **rotarla** (§3.2).
- La clave solo se ve **una vez**, en la tarjeta «Celulares», al asignar o rotar. Después no hay forma de volver a verla:
  en la base solo queda su huella (`sha256`).
- El registro de MacroDroid **no muestra la clave** (comprobado en C1 contra producción, 08/10). Sí muestra el número
  marcado en la línea «Abrir sitio web»: las capturas del registro se mandan **con los números tapados**.
- Lo que sí se pide para soporte: la **etiqueta** del celular (C1, C2…), la **hora de Lima**, el **texto exacto** que
  salió y una captura sin números ni clave.
- Si una clave se filtró (o se cree que sí): se **rota** desde la tarjeta. La vieja muere al instante.

## 1. ¿Está bien el celular? Mirarlo en dos lugares

### 1.1 En la PC: Configuración › Celulares (solo Gerencia; supervisión le pide esta comprobación a Gerencia)

| Salud | Qué significa | Qué hacer |
| --- | --- | --- |
| **Al día** | El celular mandó su latido (aviso de «sigo vivo») hace menos de 7 h | Nada |
| **Sin latido · N h** | Más de 7 h sin latido | §2, caso «Sin latido» |
| **Nunca habló** | Esta asignación todavía no recibió ningún latido | Si se acaba de asignar o rotar: poner `ultimo_latido` en 0 (§3.1) |
| **Analista de baja** | La cuenta del analista se dio de baja | Cerrar y asignar a otro (§3.5). No se puede rotar |
| + **Reloj desfasado** | El reloj del celular difiere del servidor en más de 5 min | Activar la hora automática del celular |
| + **Macro vieja** | El texto de versión del latido no es `llamadas-v3` | Corregir el texto en la macro (`macrodroid.md` §3c) |
| **En cola** > 0 (ámbar) | El celular tiene avisos guardados que no pudo enviar | §2, caso «Cola atascada» |

**Ojo:** el latido prueba que el celular **habla** con el CRM, no que capture llamadas. Un «Al día» con una macro
apagada es posible. Ante la duda, una llamada de prueba (§4).

El latido sale cada 6 h; en la práctica entre 6 h y 6 h 05 min, porque se revisa en las vueltas de 5 minutos de la
macro. Por eso «Sin latido» empieza a las 7 h y no a las 6.

### 1.2 En el celular: MacroDroid

| Dónde | Qué debe verse |
| --- | --- |
| Inicio | Sin el cartel «MacroDroid está actualmente desactivado» |
| Macros | «Llamadas-Salientes», «Llamadas-Al colgar» y «Llamadas-Enviar cola» **encendidas**; «Piloto F0» **apagada** |
| Variables → `cola_llamadas` | 0 entradas (o pocas, y bajando en ≤ 5 min con internet) |
| Variables → `errores_llamadas` | 0 entradas. Si hay alguna, §2, caso «Aviso rechazado» |

Las tres notificaciones que puede mostrar la macro (ninguna lleva el número):

| Notificación | Qué pasó | Caso |
| --- | --- | --- |
| «La clave de este celular ya no vale: pide una nueva a gerencia» | El servidor respondió 401: la clave se rotó o el celular se cerró | §2, «Clave que ya no vale» |
| «Un aviso de llamada fue rechazado» | Un aviso llegó dañado (400) y se apartó a `errores_llamadas` | §2, «Aviso rechazado» |
| «El latido fue rechazado: revisar la macro» | El latido llegó mal armado | §2, «Latido rechazado» |

## 2. Problemas: lo que ve el analista → qué hacer

| Lo que ve | Causa más probable | Qué hacer | Qué NO hacer |
| --- | --- | --- | --- |
| **Al colgar no se abre la encuesta** | MacroDroid desactivado (días gratis vencidos), una macro apagada o el ajuste «Abrir vínculos admitidos» perdido | Revisar §1.2. Si dice «desactivado»: Inicio → «Añadir Días Gratuitos» → encender. Revisar «Abrir vínculos admitidos» (`macrodroid.md` §2). La llamada no se pierde si el aviso llegó: registrarla desde «Celular» → «Pendientes» | No desinstalar MacroDroid: Android suele borrar sus datos, y con ellos las macros, la cola y la clave (no probado) |
| **Se abren dos encuestas** | «Piloto F0» quedó encendida | Apagar «Piloto F0» | — |
| **La llamada no aparece en «Pendientes» ni en «Qué pasó hoy»** | (a) el celular no tenía internet: el aviso espera en la cola y sale solo en ≤ 5 min al volver la red; (b) el número no es de un lead de su cartera (nada se guarda, por diseño); (c) era una **entrante** (no se capturan); (d) el CRM del celular está abierto con otra cuenta | (a) esperar 5 min con internet y mirar `cola_llamadas`; (b) y (c) es lo esperado; (d) la cuenta del CRM en el celular tiene que ser la del analista asignado | No reenviar a mano entradas de la cola |
| **Clave que ya no vale** (notificación) | Se rotó la clave o se cerró el celular en la tarjeta | Gerencia comprueba si la asignación sigue vigente y el analista sigue activo. Si solo se rotó la clave, pegar la nueva en `clave_celular`, conservar las colas y poner `ultimo_latido` en 0; si la nueva se perdió, Gerencia rota otra vez (§3.2). Si se cerró la asignación o el analista está de baja, seguir el procedimiento de extravío, reemplazo o baja (§3.3–§3.5) | No vaciar las colas durante una rotación del mismo analista. No intentar rotar una asignación cerrada ni reenviar su cola con la clave de otro analista |
| **Aviso rechazado** (notificación) | Un aviso dañado (400). Se apartó solo y no bloquea a los demás | Anotar la hora y avisar a soporte. La llamada se puede registrar desde la ficha del lead | No volver a meterlo a la cola |
| **Latido rechazado** (notificación) | El cuerpo del latido está mal armado en la macro | Revisar el latido contra `macrodroid.md` §3c (paso «Enviar cola») | — |
| **Sin latido · N h** (tarjeta) | Celular apagado o sin internet, MacroDroid desactivado o la batería lo frena | Revisar §1.2 y que la batería de MacroDroid esté «Sin restricciones» (`macrodroid.md` §2) | — |
| **Nunca habló** después de asignar o rotar | Falta poner `ultimo_latido` en 0: sin eso, el primer latido puede tardar hasta 6 h (hallazgo H-P11) | Poner `ultimo_latido` = 0; en ≤ 5 min pasa a «Al día» | — |
| **Cola atascada** (tarjeta «En cola» > 0 que no baja) | Sin internet, clave que ya no vale o MacroDroid desactivado | Resolver la causa: la cola sale sola | No borrar entradas de la cola |
| Al guardar sale **«Solo una tarea de llamada pendiente se cierra con el resultado de una llamada»** | La encuesta propone cerrar una tarea de **WhatsApp** (hallazgo H-WA, pendiente de arreglo) | Desmarcar «Cerrar también «WhatsApp a …»» y guardar | — |
| **Guardó el resultado equivocado** | — | Pulsar **Deshacer** en el aviso y, en «Celular» → «Qué pasó hoy», **«Registrar el corregido»** en la fila deshecha. Queda unido a la misma llamada. La fila sigue diciendo «Registrada al colgar»: es lo esperado | No registrar el corregido desde la ficha: no se une a la llamada |
| **Entró otra llamada con la encuesta abierta y la encuesta desapareció** | La segunda llamada recarga la app (hallazgo H-P5) | La primera llamada no se pierde: está en «Pendientes» | — |
| **Una llamada que no era de trabajo** | — | «Pendientes» → **Descartar** → motivo («Llamada personal», «No era comercial», «Número de prueba», «Error de captura» u «Otro motivo», que pide escribirlo) | — |
| **Al analista le reasignaron un lead y «desaparecieron» sus llamadas** | Las llamadas siguen al dueño **actual** del lead (decisión 7) | Es lo esperado. Si vuelve a tener el lead, vuelven a verse. La nueva dueña las ve como suyas (hallazgo H-P10, lo decide Miguel) | — |

## 3. Operaciones de gerencia (Configuración › Celulares)

### 3.1 Alta de un celular

Paso a paso en `ACTIVAR-C1.md` §1–§4. Lo esencial: la cuenta del CRM en el celular tiene que ser la del analista
asignado; en MacroDroid se vacían `cola_llamadas` y `errores_llamadas` (solo en el alta), se pega la clave en
`clave_celular`, se revisa `url_llamadas` y se pone `ultimo_latido` en 0. En ≤ 5 min: «Al día», `llamadas-v3`, cola 0.

### 3.2 Rotar la clave (perdida, filtrada o con error al pegarla)

Aplica a una asignación vigente con el mismo analista activo; para cierre o baja, ver §3.3–§3.5.

1. Tarjeta → fila del celular → **Rotar** → **Copiar** la clave nueva → mandarla al celular.
2. En MacroDroid: pegarla en `clave_celular` y poner `ultimo_latido` en 0. **Las colas no se tocan.**
3. Pulsar «Ya la copié al celular» (solo cierra la ventana: no cambia nada en el servidor).
4. En ≤ 5 min: «Al día» y la cola baja sola.

Rotar cierra la asignación vieja y abre otra al mismo analista: en el historial se ve como «Rotación de clave».
Comprobado en C1 el 08/10 (P11).

### 3.3 Se perdió o robaron el celular

1. Tarjeta → **Cerrar** → motivo **«Extravío del celular»**. La clave muere al instante.
2. Lo ya guardado se conserva. Lo que el celular tenía en cola se pierde con él (casi siempre es 0: envía segundos
   después de colgar). Lo que el analista contestó en la encuesta ya está en el CRM.
3. Con el celular nuevo: alta (§3.1) con **la misma etiqueta** y el mismo analista. El número de teléfono no importa:
   el CRM reconoce al celular por su clave.

### 3.4 Cambiar de equipo (el analista sigue)

1. **Antes, la cola del celular viejo en 0** (con internet, esperar a que se vacíe).
2. Tarjeta → **Cerrar** → **«Reemplazo por otro celular»**.
3. Alta del nuevo con la misma etiqueta (§3.1).

Si se cierra con avisos en cola y esa cola se envía después con una clave nueva, esas llamadas se atribuyen al analista
de la clave nueva. La tarjeta lo avisa en ámbar al cerrar.

### 3.5 El analista deja el CRM

1. **Antes, la cola de su celular en 0.**
2. Su baja en «Usuarios y jerarquía». La fila del celular pasa a «Analista de baja» y ya no se puede rotar.
3. Tarjeta → **Cerrar** → **«Baja del analista»**.
4. Si el celular físico pasa a otro analista: alta (§3.1) con la misma etiqueta y el analista nuevo. En el celular,
   la cuenta del CRM tiene que ser la del nuevo.

§3.3–§3.5 siguen los flujos repasados con Jhosep el 06/10 (`F4C-F4D-PLAN-CORTO.md`). En C1 solo se probaron el alta y
la rotación: cerrar por extravío, reemplazo o baja **no se ha probado en un celular** (sí en el banco de pruebas).

## 4. Prueba rápida de que todo funciona (2 minutos)

1. Desde el celular, llamar a un lead propio y colgar.
2. Tiene que abrirse la encuesta con «Llamada del celular de las HH:MM».
3. Guardar un resultado: sale «Quedó unido a tu llamada del celular…» o «Quedará unido… en cuanto llegue su aviso».
4. En «Celular» → «Qué pasó hoy» aparece la llamada con su resultado.

Deja una gestión real en las cifras del analista: usar un lead de prueba propio.

## 5. MacroDroid gratis: los «días gratuitos»

- La versión gratuita **se apaga sola** cada 3 días si no se renuevan: Inicio → «Añadir Días Gratuitos» (un anuncio)
  → encender. **No avisa:** mientras está apagada no se captura nada (pasó el 06/10 en C1).
- Hay que renovarlo antes de que venza. En C1 el próximo vencimiento es hacia el 12/10 (renovado el 09/10).
- Pro (pago único) está aprobado por Miguel (#18) y quita este límite. Se compra cuando terminen las pruebas, por
  decisión de Jhosep.
- La versión gratuita admite 5 macros; el piloto usa 3 más «Piloto F0» apagada.

## 6. Qué reportar y a quién

- **Al analista:** que nunca mande la clave; que diga etiqueta, hora y texto exacto.
- **A Miguel:** lo que pida tocar la base o la Edge, con `QUÉ HICE · RESULTADO · TURNO PARA`, sin números ni claves.
- **Al registro:** cada incidencia en `REGISTRO.md` §6 (fecha, celular, qué pasó, impacto, cómo se resolvió).

## En llano

Esta guía junta en un solo lugar cómo saber si un celular está bien, qué hacer cuando algo falla y cómo dar de alta,
cambiar la clave o retirar un celular, sin que nadie tenga que ver ni pasar la clave. Casi todo lo de aquí se probó en
C1 contra producción; lo que no (cerrar un celular por pérdida, cambio o baja) está marcado como no probado.
