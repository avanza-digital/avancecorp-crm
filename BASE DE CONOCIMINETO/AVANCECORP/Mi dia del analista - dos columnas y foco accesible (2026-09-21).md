---
tags: [crm, gestion-diaria, ux, accesibilidad, analista]
fecha: 2026-09-21
estado: integrado-sin-publicar
---

# «Mi día» del analista — dos columnas, y el foco de todo el CRM

Relacionado con [[Gestion Diaria - modulo nuevo y absorcion de Seguimiento 2026-09-19]],
[[Gestion Diaria F4 - vista del equipo validada localmente (2026-09-21)]],
[[Fundamentos UX del CRM]] y [[Acceso y roles del CRM]].

## El pedido

Miguel, 20/09: «gestión diaria de analista, no me gusta mucho cómo se ve, puedes
mejorar la UI/UX, pero cosas simples, dame propuestas». Venía de un «me gusta,
pero esa orientación vertical la odio» sobre la misma pantalla ya publicada.

Se le presentaron tres opciones dibujadas (no una pregunta abierta) y eligió
**dos columnas**, más cuatro retoques: fila de dos datos, un solo rojo, marcador
en una línea y una sola acción primaria.

## Decisión

La pantalla deja de ser una pila de cuatro secciones y pasa a ser **el que actúa
y el que elige, uno al lado del otro**:

- **Panel «Ahora»** (340 px, fijo con `sticky`): UN lead, con el nombre grande,
  el tiempo que le queda EN PALABRAS, el teléfono y «Llamar» como única acción
  primaria. Lo secundario vive tras «···».
- **«Cola de hoy»**: los cuatro grupos en PESTAÑAS —una lista a la vez— en vez
  de cuatro listas apiladas. **La fila es el selector**: nombre y tiempo, sin
  botones dentro. Elegirla lleva el foco al panel, que queda a un tabulador de
  «Llamar».
- **Un solo rojo**: reservado a lo vencido. La severidad se dice con esas mismas
  palabras («Se pasó hace 45 min»), así que el chip «Crítica» sobra.
- **El marcador sube a la cabecera en una línea** y su detalle baja al plegable
  «Mi actividad de hoy». El % sigue llevando pegado su conteo de útiles.

Lo metodológico, el seguimiento, los descartes y el registro propio siguen
plegados debajo, con su conteo a la vista. Nada de esto toca `api`, SQL,
permisos ni datos: es exclusivamente pantalla.

## Lo que descubrieron las revisiones

Revisado por **Codex** como `SECONDARY_REVIEWER` (1 P1 + 7 P2) y por el
subagente **`revisor-a11y`** (1 P1 + 4 P2). Los dos hallazgos que valían el
viaje, y que quedan como conocimiento reutilizable:

- **Una sola caja de contacto que cambia de lead puede escribir el resultado
  sobre la persona equivocada.** Las acciones de contacto vivían DENTRO de cada
  fila y se desmontaban con ella; al moverlas a un panel único, el refresco de
  cada minuto podía cambiarles el `lead` con el diálogo de resultado abierto.
  Se resuelve con `key={lead.id}`: un contacto a medias que se cae es
  reparable; atribuirlo a otra persona, no. Misma familia que el caché parcial.
- **Declarar `role="menu"` obliga al patrón completo del APG.** El menú de la
  casa sólo cumplía Escape: sin flechas, sin foco al abrir, y al salir con Tab
  quedaba abierto con el foco fuera y `aria-expanded="true"`. Se completó en
  `components/ui/dropdown-menu.tsx`, así que el menú del Pipeline lo gana también.

Además: el lead elegido se busca en la cola ENTERA y no dentro de la pestaña
(si el refresco lo mueve de «Hoy» a «Vencidas», la pestaña lo sigue a él); una
cola que no se pudo leer dejó de presentarse como cola vacía; y el `DropdownItem`
pasó de `disabled` nativo a `aria-disabled`, porque «Mi día» deshabilita
«Registrar resultado» justo en el ítem que el menú acaba de enfocar.

## El foco, que resultó ser de toda la app

El revisor de a11y encontró en «Mi día» algo que no era de «Mi día»: el foco del
CRM se pinta con un `ring` al 40 % —un `box-shadow`— y **81 controles en 41
archivos** apagan además el `outline` del navegador. De ahí dos fallos:

- En **alto contraste** (`forced-colors`) el navegador borra los `box-shadow` y
  respeta el `outline: none`: el indicador de foco **desaparecía por completo**
  (WCAG 2.4.7). No existía ninguna regla `forced-colors` en el proyecto.
- En modo normal el resplandor compone **~1,8:1**, cuando 1.4.11 pide 3:1.

Decisión de Miguel (21/09): arreglarlo con **dos reglas globales en `index.css`**
en vez de editar 41 archivos. La de modo normal apunta **por atributo**
(`[class*='focus-visible:outline-none']`) y no por la clase escapada: escrita
como clase, Tailwind la reconocía como una de sus utilidades y **la regla
desaparecía del build**. Ninguna de las dos alcanza a los modales, que usan
`outline-none` a secas y no deben pintar un borde alrededor de toda la ventana.

**La trampa que casi se cuela:** un `*/` dentro de un comentario CSS cerraba el
bloque antes de tiempo. El navegador de `npm run dev` se recuperaba solo y todo
parecía correcto; `dist` salía sin la regla. Un parche que sólo vive en un
entorno no existe. Por eso `verify:bundle` exige ahora las dos reglas en el CSS
que de verdad se publica, con un mutante por cada mitad.

Efecto secundario: su suite (`scripts/verificar-bundle-produccion.test.mjs`)
estaba **en rojo desde antes**, por el gate de la Ficha 360, y **no la corría
ningún script**. Se arregló partiendo de un bundle que cumple todos los
contratos. **Queda pendiente engancharla a `npm run check`**: un gate que no
corre es peor que no tener gate.

## Verificación

**PASS:** lint (sólo los avisos preexistentes de `coverflow-carousel.tsx`),
typecheck, **3.992 pruebas** en 270 ficheros, build, `verify:bundle`, los 11
casos de la suite del bundle y el recorrido Playwright completo (214 en verde;
un flake de tiempo en `sla-operacion.spec.ts` que pasa en aislado). Tres e2e
nuevos comprueban el foco en el navegador: alto contraste, modo normal y que el
modal siga sin `outline`.

Detalle útil para futuras pruebas de foco: **el foco tiene que llegar por
teclado**. Chromium no considera `:focus-visible` un `element.focus()`
programático, así que la prueba enfoca, hace `Tab` y vuelve con `Shift+Tab`.

## Estado y pendientes

**INTEGRADO EN `main` LOCAL, SIN PUBLICAR.** Commits `313ac607`, `40f2501b`,
`a561d728` y `1ff8b5e5`. La etapa 1 de F4 se reconcilió encima (`03249ba9`).

- 🔴 **Publicar**: nada de esto está en producción, y `main` local está
  divergido de `avancecorp/main`.
- 🔴 Enganchar `verificar-bundle-produccion.test.mjs` a `npm run check`.
- Decidido y NO cambiado: el nivel «Bajo» del marcador se queda en **ámbar**
  (la otra línea de trabajo ya lo había resuelto así, con pruebas que lo
  blindan), y «Registrar resultado» se queda tras «···».
- El 20 y 21/09 hubo **dos sesiones trabajando en la misma carpeta**. Los
  commits se hicieron separando lo ajeno (temperatura/TypeSafe), pero conviene
  recordarlo al leer el historial de estos dos días.
