# Prodelco admite inversiones en dólares (2026-09-17)

> **Estado:** ✅ **FUNCIONANDO EN PRODUCCIÓN** desde el 18/09/2026.
> **Decisión de Miguel (17/09/2026):** Prodelco sí, **Qorilazo solo soles**.

## Qué pidió el negocio

Que en la cooperativa **COOPAC Prodelco** se puedan registrar inversiones en **dólares**. Hasta
ahora las dos cooperativas solo aceptaban soles, por una decisión de Miguel del 12/08/2026 que este
cambio revisa **solo para Prodelco**.

## La pregunta que ordenó todo el trabajo

*¿Dónde está escrito que una cooperativa solo toma soles?*

En **cinco sitios a la vez**, aunque desde la fase F1 existía una tabla creada justamente para
decidirlo: el **catálogo de empresas de inversión**, que guarda por empresa qué monedas admite.
Nadie lo consultaba: cada escritor llevaba la palabra «soles» escrita a mano.

El peor de los cinco era el que registra una **inversión adicional** de alguien que ya invirtió:
escribía «soles» en la fila sin mirar lo que el analista había elegido. Una inversión en dólares se
habría **guardado como soles, por el mismo importe**.

## La decisión de arquitectura

**La moneda la manda el catálogo.** Los cinco escritores dejan de opinar y preguntan.

La consecuencia es la parte que vale para el futuro:

> **Abrir o cerrar una moneda a una cooperativa pasa a ser cambiar UNA FILA, no desplegar código.**

Si mañana Qorilazo también acepta dólares, o si hay que cerrar la puerta de Prodelco esta misma
tarde, es un cambio de dato y surte efecto **en el acto**. Lo único que sigue necesitando una
publicación es el **desplegable** del formulario, que no adivina las monedas: las refleja.

## Lo que NO hubo que tocar, y por qué

Se midió antes de escribir: de las **38** funciones del servidor que leen los cierres en
cooperativa, **solo esas cinco** decidían la moneda. El resto —incluido el **único** cálculo de
capital de la casa y la **cuota** de los analistas— ya llevaba la moneda como una dimensión más y
**nunca suma soles con dólares**.

Por eso un cierre en dólares entra en su propia columna **sin tocar una sola calculadora**. Medirlo
primero ahorró casi todo el trabajo que se imaginaba al empezar.

## Dos defensas que aparecieron en la revisión

Ninguna quita nada de lo que ya se podía hacer: **acotan lo que se acaba de abrir.**

### 1. La moneda de una solicitud no se corrige: se cancela y se prepara otra

Una pestaña del navegador sin recargar sigue mandando «soles» fijo. Alguien que corrigiera, por
ejemplo, la referencia de una solicitud en dólares la habría **reescrito como soles, sin avisar y
por el mismo importe**. Ahora la moneda es intocable entre revisiones, junto a la persona, la
empresa y el comprobante, que ya lo eran.

> ⚠️ **Al publicar hay que avisar al equipo:** quien tenga el CRM abierto sin recargar verá un error
> claro al corregir una solicitud en dólares, hasta que recargue. Falla del lado seguro.

### 2. Una guarda para el futuro

Si algún día alguien relajara una restricción del catálogo, dos de los cinco candados se habrían
abierto solos mientras los otros seguían cerrados. Ahora fallan del lado seguro.

## La decisión que tomó Miguel

**Gerencia sí puede cambiar la moneda de un cierre de un mes ya cerrado** (18/09/2026).

Se le planteó el reparo con su consecuencia: cambiar la moneda mueve plata de la columna de soles a
la de dólares **en un mes cuyos números ya estaban congelados y reportados**. Con la alternativa de
bloquearlo sobre la mesa, eligió permitirlo.

Lo que sí queda es el **rastro**. Cada corrección de ese tipo escribe una nota en el historial del
cliente con la moneda que tenía antes y la que tiene después, y el auditor guarda la fila completa.
Quien revise más adelante puede ver qué se cambió y cuándo.

Y hay una prueba automática que **afirma que está permitido**: si en el futuro alguien lo bloquea
«por prudencia» sin preguntarte, esa prueba falla y se nota.

## Cómo se comprobó

Sobre una **copia local del servidor llevada al estado exacto de producción**, con un guion que se
corre entero con un comando y deja su acta escrita:

| Qué se probó | Resultado |
|---|---|
| Las 13 situaciones del negocio (incluida la inversión adicional en dólares de punta a punta) | pasan |
| **Sabotajes deliberados** al propio cambio, para comprobar que las pruebas los cazan | 6 de 6 cazados |
| Intentar aplicar dos veces | se niega |
| Volver atrás con dólares ya registrados | se niega y explica por qué |
| Volver atrás en limpio | deja el servidor exactamente como estaba |
| Pantallas del CRM | 3 680 pruebas en verde y compilación correcta |

Falta una suite del proyecto (la de permisos) que necesita un entorno de pruebas sembrado: sus
cuatro casos nuevos **están escritos pero no ejecutados**.

## Dos trampas que costaron tiempo y conviene recordar

- **El entorno de pruebas tenía apagadas cuatro banderas que en producción están encendidas.** Con
  una de ellas apagada, el camino que escribe la moneda **no se recorría**: la prueba habría dado
  verde sin medir nada. Es la misma lección de *Ejecutar contra la forma real*.
- **La vuelta atrás tiene que restaurar los cinco escritores.** Si dejara uno fuera, el cambio
  **ya no se podría volver a aplicar**. El camino de regreso se rompe justo cuando se necesita.

## Ya está publicado

Salió el 18 de septiembre: primero el servidor y después las pantallas, en ese orden, porque las
pantallas envían un valor nuevo que el servidor viejo habría rechazado.

Se comprobó contra la base real, **sin escribir nada**: una inversión de Prodelco en dólares se
acepta y queda guardada en dólares; Qorilazo las rechaza con un mensaje claro; y el cálculo de
capital las reporta en la columna de dólares, no en la de soles. Los 26 cierres que ya existían y
el capital quedaron intactos.

**Lo que verá tu equipo:** al cerrar en Prodelco aparece un desplegable de moneda, que arranca en
soles. En Qorilazo la pantalla no cambia en nada.

⚠️ **Aviso del día de la publicación:** quien tuviera el CRM abierto sin recargar la página vería un
error al corregir una solicitud en dólares, hasta recargar. No se pierde nada ni se guarda mal.

**Para cerrar la puerta en cualquier momento**, sin desplegar nada, basta devolver la fila del
catálogo de Prodelco a solo soles.

---

Relacionado: [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]] ·
[[Anulación de cierres de Avance]] · [[Cuentas mancomunadas]]
