# Llamadas desde el celular - pruebas de MacroDroid en C1 (2026-10-02)

Estado: **las 6 pruebas de MacroDroid de F3.3 pasaron en C1** (Samsung A16, Android 16) el 02/10/2026,
contra un receptor de pruebas en el PC de Jhosep que corre el mismo código de la Edge
`crm-llamadas-ingesta` con una base falsa (decisión de Jhosep: no esperar el despliegue de Miguel).
Conclusión: **MacroDroid sirve** para la captura automática; no hace falta otro adaptador (decisión 5
de F3, la ratifica Miguel). Ese mismo día, [[Llamadas desde el celular - F1 receptor por URL y ajuste Android (2026-09-30)|F1]]
quedó probada en producción: al colgar se abre la encuesta del lead según el número.

## Qué quedó demostrado

1. Al colgar, el celular envía solo el aviso de la llamada (POST con la clave en una cabecera y el
   número en el cuerpo) y lee la respuesta (202 + la URL de la encuesta).
2. Cada llamada lleva su propio id (`C1-` + la hora del sistema), y el reenvío conserva el mismo id.
3. El aviso se guarda en una variable global ANTES del envío, se borra solo con 202, se conserva sin red
   y sobrevive al reinicio del celular.
4. Al volver la conexión, una segunda macro lo reenvía sola (un aviso guardado 2 h llegó con su id).
5. Sin doble disparo en los casos probados (colgar antes de que contesten, sin respuesta).
6. La clave no aparece en el registro de MacroDroid.

## Requisito de Jhosep para la macro definitiva

El reenvío **no puede depender de una red Wi-Fi concreta**: hay analistas en otra oficina con otro
Wi-Fi y celulares en la calle con datos móviles. Disparador por cualquier cambio de conectividad +
reintento periódico mientras haya pendiente; nunca atado al nombre de un Wi-Fi y sin pedir permiso de
ubicación. El aviso va a la Edge en internet, no a un PC de la oficina.

## Pendiente para la macro definitiva (F3-c)

- Lista de varios avisos pendientes (la prueba usó un solo hueco).
- Reintento periódico ante 429 o 5xx.
- Dirección correcta: «Llamada terminada» también dispara con entrantes.
- No mostrar el número en notificaciones ni en el registro.
- La clave vive visible dentro de la macro: el control es rotarla si se pierde un celular.
- Repetir las pruebas 1 y 6 contra la Edge desplegada (Miguel).

Detalle: `CRM-Avance-Corp/docs/gestion-diaria/piloto-telefonia/REGISTRO.md` §5d y
`CRM-Avance-Corp/docs/plans/llamadas-celular/F3-PLAN-CORTO.md`. Relacionada:
[[Llamadas desde el celular - clientes como objetivo pendiente (2026-10-01)]].
