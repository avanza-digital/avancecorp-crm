# Evaluación del PRIMARY

Revisión LEVEL 2. La primera llamada al wrapper terminó sin un dictamen válido;
la segunda devolvió CHANGES_REQUESTED. No se solicitó otra opinión para buscar
un resultado favorable. El reviewer recibió diff y código saneados, sin
herramientas ni credenciales; no pudo inspeccionar las capturas.

- **P2, cascada:** `gerencia.tsx` importa `supervisor.css` antes de
  `gerencia.css` (líneas 22–23): el orden vigente está definido y las pruebas
  actuales lo verifican. Se acepta reforzar la especificidad de la variante
  gerencial para que esa dependencia no fragilice futuras cargas.
- **P2, solapamiento de cabecera:** reproducido. La prueba de `elementFromPoint` falló
  después de desplazar ambos ejes: los nombres tapaban la cabecera. Captura
  `antes/columna-sobre-cabecera.png` y salida `scroll-antes.log`. Se eleva la
  cabecera a z-index 2 y se deja la columna del cuerpo en 1.
- **P3, atención:** descartado como fallo. `filtrarOrdenarEquipo`, en
  `src/lib/gestion-diaria-equipo.ts:106`, filtra por `requiere_atencion`, el
  mismo predicado del recuento. Buscar reduce sólo las filas, no el total de
  atención, igual que en supervisión.
- **P3, fixture:** `gerencia.test.tsx` tiene `beforeEach` que vuelve a analizar
  el JSON original. Se expresa la variación del test mediante reemplazo
  inmutable para eliminar la ambigüedad sin cambiar el contrato.
- **P3, cierre:** Dialog define animación de entrada, sin una salida específica.
  Se conserva el último contenido al cerrar para evitar depender de ello.
- **P3, foco:** se acepta explicitar el foco visible de la región desplazable
  del diálogo, que vive en un portal fuera de `.gd-pulso`.
- **P3, actualidad:** se conserva «Hoy en curso» al comparar cifras; la fecha
  elegida y el control «Hoy» continúan en la cabecera. No se requiere una nueva
  conformidad de producto para esta corrección ya autorizada.

Estado: ajustes aplicados y comprobados. PASS final: `npm run check`
(4423/298), 11 E2E Chromium y 11 WebKit sin reintentos. La prueba de pintura
que falló antes ahora pasa. Se verifica también el umbral 960/959 y 700 px de
alto. No se requiere una tercera consulta: el PRIMARY resolvió con evidencia. El dictamen del
reviewer se conserva literalmente; la resolución y los checks reales son
responsabilidad del PRIMARY.
