# Mi cartera por meses

**Estado: construido y verde 2026-08-14, pendiente de publicar.** Sin migración: no toca el
servidor.

## Qué problema resuelve

Un asesor **no tenía ninguna forma de saber qué cerró en un mes concreto**. Las pantallas que
responden a eso —Conversiones, Metas, Ranking, Rendimiento— son **exclusivas de gerencia**
(`VISTAS_GERENCIA` en `app/src/lib/router.ts`). Al asesor solo le quedaban **Hoy**, que habla del
mes en curso, y **Mi cartera**, una lista única con todos sus clientes y contratos mezclados.

Pedido de Miguel, 2026-08-14: *«necesito que el vendedor pueda saber qué cerró por mes, y que la
cartera no salga todo junto»*.

## Cómo queda

Mi cartera es ahora una sucesión de bloques por mes, del más reciente al más antiguo. Cada bloque
lleva en su cabecera lo que se cerró (contratos y capital, con PEN y USD **separados**) y debajo
sus clientes. El más reciente arranca abierto; los demás, plegados. Con un filtro puesto se abren
todos —esconder un resultado tras un plegado es lo contrario de lo que el usuario vino a hacer.

Un cliente que cerró en varios meses **aparece en cada uno**, con los contratos de ese mes y su
resumen recalculado. Los clientes sin ningún contrato van a un cubo propio al final: siguen
siendo operables (mantienen su «+ Primer contrato»).

## Las decisiones de Miguel

| Pregunta | Su respuesta |
|---|---|
| ¿Cómo se separa? | Por **mes de cierre**. |
| ¿Qué cuenta como «lo que cerró»? | **Todo contrato de un cliente que él atiende**, aunque lo haya registrado otra persona. |
| ¿Dónde va el resumen? | **En la cabecera de cada mes**, sin pantalla nueva. |

## Las trampas que costaron trabajo

**1. La fecha que manda es `creado_en`, no `fecha_inicio`.** Es la misma ventana con la que se
mide la cuota del mes, y `fecha_inicio` sí puede retro-datarse: con ella, dos contratos idénticos
acabarían en meses distintos según quién los mire.

**2. El mes se decide en hora de LIMA.** Un contrato registrado el 31 de julio a las 20:00 es el
1 de agosto en UTC y saltaría de bloque él solo, inflando un mes que no le toca. Se reutiliza
`fechaLima` (`lib/agenda-derivada.ts`). Hay test dedicado: `mesLima('2026-08-01T01:00:00Z')` es
**julio**.

**3. El total del mes NO es la cuota.** Miguel eligió contar todo contrato de sus clientes; la
cuota, en cambio, paga por **quien registra** el contrato (`public.contratos.creado_por`), porque
el enlace lead↔contrato está vacío en los 373 contratos de producción. Medido: coinciden en
**353 de 372** y difieren en **18**. Cuando un mes incluye alguno ajeno, la cabecera lo dice
—«incluye 1 registrado por otra persona»— para que la diferencia con Hoy no sea invisible. Es la
misma trampa de «dos números a 300 px» que costó una migración en
[[Conversion mensual - definicion cerrada]].

**4. El plegado del cliente se guarda por (mes, cliente).** Con la clave del cliente a secas,
expandirlo en agosto lo expandía también en julio, y el auto-desplegado al filtrar abría un
bloque cualquiera dejando escondida la fila buscada. Hay regresión para las dos cosas.

**5. El nombre accesible salía pegado.** Los trozos de la cabecera son `<span>` hermanos sin
espacios, así que el nombre calculado era «Agosto 20261 contrato cerradoS/ 20,000» —un lector de
pantalla lo lee como otro número—. Y los separadores `sr-only` **no lo arreglan**: el cómputo
recorta cada nodo, así que « · » llega igual de pegado. La salida: un `aria-label`, pero
**derivado del mismo array que se pinta**. Un `aria-label` escrito a mano gana sobre el contenido
y deja mudo cualquier dato visible que se añada después; derivándolo, no hay forma de pintar algo
que no se anuncie.

## Lo que dijo la revisión de accesibilidad

Nada bloqueante, y cuatro cosas que se corrigieron antes de commitear:

- **Contraste medido, no estimado.** `text-muted-foreground` sobre la barra da 4,55:1 en reposo
  —pasa por 0,05— pero **4,44:1 en hover**, y como la barra ENTERA es el botón, el hover es el
  estado normal de uso. Nació el token `--muted-foreground-strong` (#475569, 7,2:1), gemelo de
  `--destructive-text` y `--warning-text`.
- **La cabecera es `<th scope="rowgroup">`, no `<td>`.** Sin eso, la relación mes↔fila existía
  solo en lo visual y ninguna ayuda técnica podía decir a qué mes pertenece la fila que está
  leyendo. ⚠️ No lleva un `<h4>` dentro aunque ayudaría a saltar de mes con la tecla H: **el HTML
  prohíbe encabezados dentro de `<th>`**.
- **En móvil, `<h4>` y no `<section aria-label>`.** La `<section>` con nombre es un LANDMARK: dos
  años de cartera son 24 landmarks compitiendo con Navegación y Principal, y el lector decía
  «Agosto 2026» tres veces al entrar (región → botón → lista).
- **`aria-controls` se queda fuera a propósito**: es opcional en el patrón *disclosure*, y aquí lo
  controlado son N `<tr>` hermanos que **no existen en el DOM** cuando está plegado — un IDREF
  colgante es peor que no tenerlo.

Verificado además: el botón **no se desmonta** al plegar, así que el foco no se pierde; el
chevron es `aria-hidden` y el estado va solo en `aria-expanded` (nada por color).

⚠️ **Deuda anotada, no corregida**: `components/common/paginacion.tsx` deja el foco en el aire al
llegar a la última página (el botón pulsado pasa a `disabled` y el foco salta a `<body>`). Es
preexistente, pero antes había UN paginador y ahora hay uno por mes. El arreglo —`aria-disabled`
con handler no-op— toca un componente compartido por muchas pantallas y merece su propio ciclo.

## Por qué no hizo falta servidor

`crm.contratos_cartera` ya devuelve, con el ámbito de cada rol, la fecha de registro, el capital,
la moneda y quién lo registró. Y los tamaños sobran: el asesor con más cartera tiene 39 clientes y
46 contratos en 3 meses, contra un tope de 2.000.

## Dónde vive

- `app/src/lib/cartera-meses.ts` (+ su test) — la lógica pura: partir por mes, totales por moneda,
  los dos cubos y el conteo de ajenos.
- `app/src/lib/cartera-vista.ts` — se extrajo `resumirCliente` para poder recalcular el resumen
  del cliente **por mes**; si se reutilizara el global, julio enseñaría el capital de toda su vida.
- `app/src/screens/mi-cartera.tsx` — `CabeceraMes` y el render por bloques (un `<tbody>` por mes,
  paginación por mes).
- `app/e2e/mi-cartera-meses.spec.ts` — va por la ruta REAL a propósito: con los datos de demo, que
  se anclan a «hoy», los bloques cambiarían de nombre cada día.

Ver también [[Anulación de cierres de Avance]] · [[Como se mide la conversion del asesor]].
