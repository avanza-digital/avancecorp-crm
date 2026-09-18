# Prodelco admite inversiones en dólares (2026-09-17)

> **Estado:** construido, ensayado y commiteado (`fef9af70`). **NO publicado.**
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

## Tres defensas que aparecieron en la revisión

Ninguna quita nada de lo que ya se podía hacer: **acotan lo que se acaba de abrir.**

### 1. La moneda de una solicitud no se corrige: se cancela y se prepara otra

Una pestaña del navegador sin recargar sigue mandando «soles» fijo. Alguien que corrigiera, por
ejemplo, la referencia de una solicitud en dólares la habría **reescrito como soles, sin avisar y
por el mismo importe**. Ahora la moneda es intocable entre revisiones, junto a la persona, la
empresa y el comprobante, que ya lo eran.

> ⚠️ **Al publicar hay que avisar al equipo:** quien tenga el CRM abierto sin recargar verá un error
> claro al corregir una solicitud en dólares, hasta que recargue. Falla del lado seguro.

### 2. La moneda de un cierre no cambia en un mes ya sellado

Cambiar la moneda mueve capital de la columna de soles a la de dólares **en un mes cuya foto ya se
tomó**, y el sello existe precisamente para que esos números no se muevan. Corregir importe,
número de operación, certificado, vencimiento o nota en un mes sellado sigue funcionando igual.

> **Esto es un criterio por defecto, no una ley.** Miguel puede decidir que Gerencia sí deba poder
> re-denominar un cierre de un mes sellado.

### 3. Una guarda para el futuro

Si algún día alguien relajara una restricción del catálogo, dos de los cinco candados se habrían
abierto solos mientras los otros seguían cerrados. Ahora fallan del lado seguro.

## Cómo se comprobó

Sobre una **copia local del servidor llevada al estado exacto de producción**, con un guion que se
corre entero con un comando y deja su acta escrita:

| Qué se probó | Resultado |
|---|---|
| Las 13 situaciones del negocio (incluida la inversión adicional en dólares de punta a punta) | pasan |
| **Sabotajes deliberados** al propio cambio, para comprobar que las pruebas los cazan | 7 de 7 cazados |
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

## Al publicar

**Primero el servidor, después las pantallas.** Las pantallas empiezan a enviar un valor nuevo que
el servidor viejo rechazaría. Al contrario no hay hueco: el servidor nuevo acepta lo que envían las
pantallas viejas.

Para cerrar la puerta en cualquier momento, sin desplegar nada, basta devolver la fila del catálogo
de Prodelco a solo soles.

---

Relacionado: [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]] ·
[[Anulación de cierres de Avance]] · [[Cuentas mancomunadas]]
