# Mi cartera por meses

**Estado: ✅ EN PRODUCCIÓN 2026-08-14.** Release `crm-20260814T205720Z-42a51c1c906e`
(commit `42a51c1`, 26.º release), con hash local↔vivo idéntico en los tres ficheros clave y las
llaves de Supabase verificadas dentro del fichero VIVO. 1.769 unitarias y **86 de navegador sin un
solo fallo ni inestable**. **Sin migración**: no toca el servidor. Rollback inmediato:
`crm-20260814T202404Z-d63f3a18a57d`.

Sustituye al diseño de bloques plegables que estuvo en producción unos 30 minutos esa misma tarde
(ese mismo release de rollback) y que Miguel cambió al verlo — ver
«[[#Por qué dejó de ser bloques]]».

## Qué problema resuelve

Un asesor **no tenía ninguna forma de saber qué cerró en un mes concreto**. Las pantallas que
responden a eso —Conversiones, Metas, Ranking, Rendimiento— son **exclusivas de gerencia**
(`VISTAS_GERENCIA` en `app/src/lib/router.ts`). Al asesor solo le quedaban **Hoy**, que habla del
mes en curso, y **Mi cartera**, una lista única con todos sus clientes y contratos mezclados.

## Cómo queda

Un **filtro de mes de cierre** junto a los de estado y asesor. La pantalla **arranca en el mes en
curso**: el asesor abre y ve lo que lleva cerrado, sin listas que recorrer. Encima de la lista, una
línea con el resumen de ese mes: contratos cerrados y capital, con PEN y USD **separados**.

## Las decisiones de Miguel

| Pregunta | Su respuesta |
|---|---|
| ¿Cómo se separa? | Con un **filtro**, no con bloques: «para no tener que ver el listado de meses». |
| ¿Qué muestra al abrir? | **El mes en curso.** |
| ¿Qué cuenta como «lo que cerró»? | **Todo contrato de un cliente que él atiende**, aunque lo haya registrado otra persona. |
| ¿Y el aviso de renovación? | **Manda sobre el mes**: al encenderlo, el filtro vuelve a «todos». |

## Por qué dejó de ser bloques

La primera versión partía la cartera en bloques plegables, uno por mes, con el resumen en la
cabecera. Se construyó, se revisó y **se publicó**. Miguel la vio y pidió el filtro: el resumen le
servía, la lista de meses le sobraba. El trabajo no se perdió —la lógica de agrupación
(`lib/cartera-meses.ts`) es la misma y alimenta ahora las opciones del desplegable y el resumen—,
pero conviene tenerlo escrito: **un plegable con N secciones y un filtro con N opciones responden
a la misma pregunta y no cuestan lo mismo de leer**.

## Las trampas que costaron trabajo

**1. La fecha que manda es `creado_en`, no `fecha_inicio`.** Es la misma ventana con la que se
mide la cuota del mes, y `fecha_inicio` sí puede retro-datarse: con ella, dos contratos idénticos
acabarían en meses distintos según quién los mire.

**2. El mes se decide en hora de LIMA.** Un contrato registrado el 31 de julio a las 20:00 es el
1 de agosto en UTC y saltaría de mes él solo, inflando uno que no le toca. Se reutiliza
`fechaLima` (`lib/agenda-derivada.ts`). Hay test dedicado: `mesLima('2026-08-01T01:00:00Z')` es
**julio**.

**3. El total del mes NO es la cuota.** Miguel eligió contar todo contrato de sus clientes; la
cuota, en cambio, paga por **quien registra** el contrato (`public.contratos.creado_por`), porque
el enlace lead↔contrato está vacío en los 373 contratos de producción. Medido: coinciden en
**353 de 372** y difieren en **18**. Cuando el mes incluye alguno ajeno, el resumen lo dice
—«incluye 1 registrado por otra persona»— para que la diferencia con Hoy no sea invisible. Es la
misma trampa de «dos números a 300 px» que costó una migración en
[[Conversion mensual - definicion cerrada]].

**4. Los clientes SIN NINGÚN contrato acompañan siempre al mes elegido.** No son historia de otro
mes: son trabajo pendiente, y esta es la pantalla desde la que se les crea el contrato. Dejarlos
fuera los volvía inalcanzables salvo por una opción del desplegable que nadie iba a buscar, y se
llevaba por delante el reparto de «Sin asesor» —donde esos clientes son justo los que hay que
repartir—. Lo destapó la suite: dos tests de supervisión se cayeron a la primera.

**5. El mes en curso va SIEMPRE en el desplegable**, aunque todavía no tenga ni un cierre: es el
valor por defecto, y un `value` que no existe entre las opciones deja el `<select>` mostrando
cualquier cosa. Cuando está vacío, el panel lo dice («Sin cierres en agosto») y **lleva la salida
puesta** («Ver toda la cartera»): es el primer estado que ve un asesor que aún no ha cerrado, y no
puede quedarse mirando un vacío.

## Los contadores de arriba también siguen al mes

Miguel, al ver el filtro funcionando: *«las demás ventanas, por ejemplo capital invertido soles y
dólares, también me gustaría que se actualicen conforme al mes»*. Y eligió que midan **lo que se
CERRÓ** en el mes, no lo que sigue vivo de él —una sola cifra en pantalla, no dos.

| Tarjeta | Sin mes («Todos los meses») | Con un mes |
|---|---|---|
| Dinero | «Capital invertido · Soles» — capital **vivo** | «**Cerrado en agosto** · Soles» — lo cerrado, cualquier estado |
| Alarma | «Por vencer ≤30 d» — toda la cartera | **igual**, y el sub lo declara: «en toda tu cartera, no solo el mes» |
| Personas | «Clientes con capital» | «Clientes que cerraron» — en el mes |
| Relleno | «Contratos activos» | **igual** — el testigo de que la cartera sigue viva |

**El rótulo se mueve con la cifra.** Una tarjeta que cambia de significado sin cambiar de nombre
es una mentira, y aquí el significado cambia de verdad: de saldo vivo a producción del mes.

**La alarma NO se recorta**, aunque lo pedido incluía «las demás ventanas». Es el único radar de
renovación del CRM y el propio botón saca del mes al encenderse: si la tarjeta contara solo
agosto diría 1, la pulsas y aparecerían 3. Se lo planteé y lo confirmó.

### Tres trampas que un análisis previo evitó

1. **Prohibido `resumenCartera(bloque.grupos)`.** La alarma de renovación se calcula DENTRO de esa
   misma función, así que pasarle el conjunto del mes la habría recortado por mes **gratis y sin
   avisar** — justo lo contrario de la decisión.
2. **Prohibido `meses.flatMap(m => m.grupos)`.** Un cliente que cerró en tres meses se contaría
   tres veces.
3. **Los otros filtros siguen vivos y recortan también el mes.** Si no se dijera, la tarjeta
   parecería el total del mes cuando es el total de lo buscado. Por eso el sub cambia a «de lo que
   estás filtrando».

### El borde que hubo que decidir

**Un cliente dado de baja SÍ cuenta en «Cerrado en agosto»**, aunque la regla de la casa diga que
las bajas no suman al dinero. No es una excepción caprichosa: esa regla protege el capital que se
puede TRABAJAR, y lo cerrado en un mes es un hecho histórico que no se deshace. Además ese cliente
está listado justo debajo (marcado «inactivo»), así que la tarjeta cuadra con lo que se ve. En
«Capital invertido» —el saldo vivo— sigue sin contar. Hay prueba para las dos mitades.

## ⚠️ El precio del arranque filtrado

**Para tocar un contrato de otro mes hay que cambiar el filtro primero.** Corregir, ver el detalle
o consultar el cronograma de algo cerrado en julio exige un clic más. Lo destapó la suite de
navegador: **cuatro specs** de corrección y detalle se cayeron porque su contrato de fixture era de
otro mes. No se relajaron las aserciones — se les añadió el paso que haría una persona
(`verTodaLaCartera`, en `e2e/_helpers.ts`).

Es la consecuencia directa de «arranca en el mes en curso», y está aceptada. Pero si algún día
alguien reporta que «no encuentra un contrato viejo», la causa es esta.

## Por qué no hizo falta servidor

`crm.contratos_cartera` ya devuelve, con el ámbito de cada rol, la fecha de registro, el capital,
la moneda y quién lo registró. Y los tamaños sobran: el asesor con más cartera tiene 39 clientes y
46 contratos en 3 meses, contra un tope de 2.000.

## Dónde vive

- `app/src/lib/cartera-meses.ts` (+ su test) — la lógica pura: partir por mes en hora de Lima,
  totales por moneda, los dos cubos y el conteo de ajenos. Alimenta las opciones del desplegable,
  la lista y el resumen: **una sola fuente**.
- `app/src/lib/cartera-vista.ts` — se extrajo `resumirCliente` para poder recalcular el resumen
  del cliente **por mes**; si se reutilizara el global, julio enseñaría el capital de toda su vida.
- `app/src/screens/mi-cartera.tsx` — el filtro, el resumen y el vacío con salida.
- `app/e2e/mi-cartera-meses.spec.ts` — va por la ruta REAL a propósito: con los datos de demo, que
  se anclan a «hoy», el mes viejo cambiaría de nombre cada día.

## De la revisión de accesibilidad (sobre la versión de bloques)

Sobrevive al rediseño **el token `--muted-foreground-strong`** (#475569): el gris de siempre daba
**4,44:1** sobre el fondo de la barra en hover —por debajo de AA— y se midió, no se estimó. Ahora
lo usa la línea de resumen. Gemelo de `--destructive-text` y `--warning-text`.

Lo demás (la cabecera como `<th scope="rowgroup">`, el `<h4>` en móvil en vez de un `<section>`
que creaba un landmark por mes, y el rótulo accesible derivado del mismo array que se pinta) murió
con los bloques, pero queda escrito por si vuelve un plegable a esta pantalla.

Ver también [[Anulación de cierres de Avance]] · [[Como se mide la conversion del asesor]].
