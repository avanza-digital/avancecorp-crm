# Encargo 2 a Codex (IMPLEMENTADOR) — Facturación fase 4: accesibilidad y cuadre

ROLE: IMPLEMENTER delegado por Claude (PRIMARY). Mismas reglas que el encargo 1:
- solo este worktree;
- sin commit, red, Docker, dependencias nuevas ni otros agentes;
- en español.

Trabajas SOBRE tu entrega. Al final, `npm run check` tiene que quedar en VERDE en `app/`.

Contexto verificado por el PRIMARY:
- `npm run check`: PASS.
- e2e de Facturación en Docker: 14/14.

Cambios pedidos por la revisión de accesibilidad (revisor-a11y) y por el PRIMARY. Rutas relativas a `app/`:
- LO = `src/screens/facturacion/lista-operaciones.tsx`
- F = `src/screens/facturacion.tsx`

## P1 (obligatorios)

1. **El cuerpo de la lista se desplaza con teclado.**
   - `.lista-cuerpo` (LO ~155) pasa a ser una región enfocable con nombre: `role="region"`,
     `aria-label="Operaciones de este número"` y `tabIndex={celular ? -1 : 0}`.
   - Lleva la supresión EN LÍNEA ya aceptada en la casa (patrón `facturacion.tsx` ~1491 y
     `components/bases-cargadas/detalle-cifra-base.tsx:62`).
   - En el CSS, `.lista-cuerpo:focus-visible { outline-offset: -2px }`.
   - NO tocar `.oxlintrc.json`.
2. **La hoja NO es un `role="dialog"` en escritorio.**
   - Usa `<aside aria-labelledby={id}>`, complementaria y etiquetada; la maqueta usaba región. Sin `aria-modal`.
   - Motivo: varios selectores globales tratan `[role="dialog"]` como modal bloqueante:
     - `components/app/pwa-gerencia.css:11` pone `max-height` a todo diálogo en el teléfono de Gerencia;
     - `lib/gestion-diaria-avisos-context.ts:22` aplaza los avisos de Gestión Diaria;
     - `components/app/version-publicada.css:8` oculta el aviso de versión nueva.
   - Actualiza `getByRole('dialog')` en el test unitario y en `e2e/facturacion-lista.spec.ts`.

## P2

3. **Escritorio (≥ 641 px).**
   - La hoja empieza DEBAJO del topbar (`h-16`): `inset: 64px 0 0 auto`. El topbar sigue visible y operable.
   - Mientras está abierta, se reserva su ancho para la pantalla de Facturación, no solo para la malla.
   - `scroll-padding-right` de `.facturacion-malla` cubre el solape: el borde ya calculado en LO ~63 se publica en una
     variable CSS. Así, al tabular por la malla, ninguna celda enfocada queda bajo el panel.
   - Esc sigue cerrando y devolviendo el foco al número.
4. **Celular (≤ 640 px): ocupa toda la pantalla y entonces SÍ es modal.**
   - `role="dialog"` y `aria-modal="true"`.
   - Fondo inerte (`inert` en la raíz de la app mientras esté montada) y foco contenido.
   - La guarda de Esc no ignora el propio panel: `if (modal && modal !== panel.current) return`.
   - Neutraliza para ESTE panel la regla `max-height` de `pwa-gerencia.css:11`: en el teléfono de Gerencia ocupa el
     100 % del alto.
   - Reutiliza `components/ui/sheet.tsx` si encaja sin cambiar el diseño aprobado. Si no, hazlo a mano con esas reglas.
5. **El foco nunca cae en `<body>`:**
   - `placeholderData: keepPreviousData` en `useListaOperacionesFacturacion` (`crm-queries.ts`);
   - quitar el `focus()` síncrono de `ir()` (LO ~108) y dejar solo el efecto. Con `error`, enfocar el título;
   - prop `focoRespaldo` desde Facturación (la región de la malla o la de tarjetas). Al cerrar o con Esc, si el origen ya
     no existe (equipo plegado, cambio de periodo o de vista), el foco va al respaldo. Patrón de `sheet.tsx`:
     `gemelaDeFoco` y `focoRespaldo`;
   - tras un reintento con éxito, enfocar el título. No borrar `falloActualizacion` hasta conocer el resultado.
6. **Un solo canal vivo.**
   - Un `<p role="status" className="sr-only">{anuncio}</p>` SIEMPRE montado en la hoja, fuera del cuerpo, con el texto
     diferido como en F ~980. Anuncia:
     - «Hay cifras nuevas: la lista y el número pulsado ya no coinciden. Pulsa Actualizar»;
     - los errores, también el fallo al actualizar;
     - «Cifras actualizadas».
   - Quitar `role="status"` del aviso insertado y de «Cargando operaciones…».
   - `aria-busy` solo con `cargando`, no con `isFetching`.
7. **«Ver el mes completo de…» dice el tramo real** (F ~368-369, ~404 y `tarjetas.tsx` ~39). Etiqueta y `title`: «el mes»,
   «la semana», «el día» o «los días elegidos».

## P3 (incluir)

- **«#»:** `<span aria-hidden>#</span><span className="sr-only">Número de fila</span>`.
- **«—» de referencia:** con «sin dato» en `sr-only`.
- **Etiquetas de los botones de cifra:**
  - celdas con la acción: «ver N operaciones» o «sin operaciones, abrir»;
  - la columna «por venir» con su nombre completo;
  - en modo contratos, la unidad.
- **Separador** perdido en F ~1339-1343: «· ·» y el botón del % pegado al texto.
- **Celular:** al cambiar de página se vuelve a la primera tarjeta, desplazando el contenedor que de verdad se desplaza en
  móvil.
- **Tarjetas:** «Analista X · equipo de Y» y «N.º 2026-…».
- **«Volver a la primera página» y los totales de `tarjetas.tsx`** con aspecto de botón.
- **Paginación:** «Página anterior» / «Página siguiente» y el texto visible «Filas por página».
- **`forced-colors`:** el estado pulsado de `.lista-tamano` se ve en alto contraste.
- **Ícono:** no mostrar el `Check` junto a «La cifra cambió.» (usar uno neutro o ninguno).

## Del PRIMARY: el cuadre al CÉNTIMO

En `parametros-de-cifra.ts`, `mismosTotales` y `listaCuadraConNumero` comparan con una tolerancia de 0,000001 sumas en
coma flotante hechas en el navegador. Con totales de decenas de millones, el redondeo de cientos de sumas puede pasar
esa tolerancia, y saldría un falso «Hay cifras nuevas».
- **Montos:** comparar redondeados al céntimo (`Math.round(x * 100)`).
- **Valor pulsado en capital:** tolerancia de medio céntimo (0,005). El promedio ya va redondeado al sol.
- **Contratos:** igualdad exacta. **Porcentaje:** se mantiene la tolerancia actual.
- **Test:** muchas sumas fraccionarias (0,1 + 0,2… y totales de 10⁷ con 300 sumandos) siguen dando «Cuadra».

## Tests a añadir

- `.lista-cuerpo` con rol region, nombre y `tabIndex` 0 en escritorio.
- Página con `isPending` y con `isError`: el foco nunca termina en `body`.
- Origen eliminado antes de Esc o de Cerrar: el foco va al respaldo.
- El canal vivo cambia de texto cuando aparecen cifras nuevas.
- En celular, el panel es modal (`aria-modal`, fondo inerte).
- e2e (lo corre el PRIMARY):
  - escritorio: el panel no tapa el topbar;
  - Gerencia en celular a 390×844: el panel mide el alto completo.

## Pastilla compartida

`components/ui/pastilla.tsx` ahora lleva `aria-label` en todos sus usos (Base para gestión, Rescate, Bases cargadas). El
PRIMARY está corriendo la suite e2e completa para ver si eso rompe otras pantallas. Si `npm run check` falla por eso, o
el nombre accesible de otras pantallas empeora, limita el `aria-label` a Facturación con una prop opcional y conserva
el nombre visible en los demás usos.

Informe final breve: archivos, PASS/FAIL de `npm run check` y lo no verificado.
