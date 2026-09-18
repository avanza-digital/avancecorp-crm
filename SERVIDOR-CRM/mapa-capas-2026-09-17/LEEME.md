# Mapa de capas del servidor CRM — 17/09/2026

**Artifact interactivo (privado):** https://claude.ai/artifact/7rSe49eefhyVyuXgKZpg81 (versión 3.1, 17/09/2026 ~00:10 UTC del 18/09)
**Página en disco:** `mapa-capas-crm.html` (es el mismo HTML publicado; ábrelo con `file://`).

## Versión 3.1 (misma URL): fallos corregidos en la página

Mismos datos y misma libreta; solo cambia la página. Miguel pidió arreglar los fallos DIRECTO sobre el artifact, así
que se editó el HTML publicado y se republicó con `url`; después se portaron los mismos parches a `scripts/plantilla.html`
(la plantilla con los datos vuelve a dar byte a byte este `mapa-capas-crm.html`).

- **Móvil (~400px).** La barra de herramientas ocupaba 7 filas (276px) y en pantalla completa el mapa era una franja:
  ahora es una sola fila desplazable (54px) y la barra de ayuda se oculta en pantalla completa estrecha.
- **Pantalla completa.** El lienzo usaba `calc(100% - 92px)` y se rompía en cuanto la barra se partía en varias filas
  (ya pasa a 1600px): ahora crece con `flex` y ocupa exactamente lo que queda.
- **Rótulos de capa siempre legibles.** En la vista general no se leía qué banda era cuál (30px en un lienzo de
  7 000): hay rótulos HTML fijos «1 · Tablas … 4 · Pantallas» pegados al borde del lienzo, que desaparecen cuando el
  rótulo del SVG ya se lee.
- **Mostrar todo** limpia también el buscador de la tabla (antes seguía filtrada).
- **Hover** sobre una línea atenuada (con otra seleccionada) la resalta; hover de tabla y matriz sin parpadeo.
- **Contador** de la tabla avisa «· 5 transversales apagados» cuando el filtro X los oculta.
- **Flujo/Trazo** se leen del selector real al cargar (el navegador puede restaurarlo al recargar).
- **Robustez:** una conexión «misma capa» en Pantallas ya no rompe el render (`segmentos[4]`); el buscador de la
  tabla conserva ancho mínimo.

Verificado en Chromium (Playwright, 1600px y 400px, claro y oscuro): sin errores de consola, 0 líneas cruzan cajas,
0 IDs sobre cajas, totales de la matriz cuadran (636 / 52 / 51). No probado: «Copiar evidencia» (portapapeles) y
`requestFullscreen` dentro del iframe de claude.ai (si lo bloquea, cae al modo `position:fixed`, que sí se probó).

## Versión 2 (misma URL): qué cambió en la página

Los datos son los mismos (el catálogo se releyó a las 19:54 UTC y dio exactamente las mismas 3 474 conexiones,
398 sanas y 171 saltos; solo cambia la fecha). Cambió la página:

- **Vista general calma.** Las líneas van finas y atenuadas (sanas 1.5px al 42 %, saltos 2.2–2.7px al 50 %) y solo
  recuperan el grosor de la especificación (A 4.4 · M/D 3.6 · B 2.9) al pasar el mouse, al seleccionarlas o con
  **Trazo → fuerte**. Cajas de 72px con título en dos líneas y letra 14/12; bandas de 140px.
- **Chapa «n saltos».** Una caja con más de 6 saltos salientes ya no amontona sus IDs: muestra una chapa
  `34 saltos ▾ A20 M11 B2 D1` (respeta los filtros) y al clic despliega los IDs en rejilla. Con 6 o menos, la
  rejilla va directa. Los IDs de las inversiones (Puertas → Núcleo) salen por arriba de la caja.
- **Foco.** Selector de módulo (sus tres cajas: Tablas, Núcleo y Puertas) o de pantalla/actor: selecciona todas sus
  líneas visibles, marca las cajas, encuadra la cámara y lista en el panel los objetos reales con sus etiquetas
  (cerrada, trigger, sin llamador, F7, config).
- **Copiar evidencia.** Botón en «Selección»: copia al portapapeles las cajas y líneas seleccionadas con cada
  conexión real (`p → c · vía archivo:línea · nota`), listo para pegar en una nota, un issue o un prompt.
- **Matriz de saltos.** Pestaña junto a «Mapa»: una tabla por par de capas (Tablas → Puertas · salta Núcleo,
  Tablas → Pantallas · salta Núcleo + Puerta, Puertas → Núcleo · inversión), origen × destino, con el ID y el nº de
  conexiones por celda, color por peso y totales por fila/columna. Un par puede llevar un salto por severidad
  (26 pares). Filtros y buscador apagan celdas; clic en una celda la selecciona en el mapa y acerca la cámara.

Regla que mide el mapa (del `CLAUDE.md`, «Arquitectura en 4 capas»): toda información recorre
**Tablas → Núcleo → Puerta → Pantalla**. Una conexión que se salta una capa existe y funciona,
pero rompe la arquitectura.

## Qué hay en esta carpeta

| Archivo | Qué es |
|---|---|
| `listas.txt` | Las tres listas del método: CAPAS (nodos por capa), SANAS y SALTOS con ID, tal como salieron del script. |
| `datos.json` | Nodos, líneas sanas, saltos y META que consume la página. |
| `evidencia-mapa.json` | Nivel objeto: los 810 objetos con su capa y módulo, y las 3 474 conexiones reales con su evidencia (`via`) y clasificación. |
| `evidencia/*.json` + `evidencia/sql/*.sql` | Consultas al catálogo VIVO (proyecto `dctqcbznekcyxhjujuci`) ejecutadas con `supabase db query --linked --file` el 17/09/2026 (17:11 UTC; releídas a las 19:54 UTC con resultado idéntico), y su resultado íntegro. Solo lectura; sin filas de clientes. |
| `front-graph.json` | Análisis estático del front: pantalla → símbolos → `rpc`/`from`/`invoke`, con archivo y línea. |
| `edge-refs.json` | Referencias SQL dentro de cada Edge Function (esquema resuelto por cadena o por `createClient`). |
| `pantallas.json` | Raíces de cada pantalla (archivo y componente). |
| `decisiones.json` | Libreta de decisiones por salto (aceptado / corr / cerrado), con fecha, quién y motivo. |
| `scripts/` | `analyze-front.mjs`, `analyze-edges.mjs`, `mapa-datos.py`, `plantilla.html`. |

## Libreta de decisiones (`decisiones.json`, versión 3 de la página)

El mapa solo sabe leer el código: si una lectura directa existe, la pinta en rojo. La libreta guarda lo que Miguel
decide sobre cada salto para que la regeneración no lo vuelva a pintar como el primer día.

- **Clave estable** por salto: `origen>destino:sev` (p. ej. `t:metas>p:metas:B`). Los IDs `A3`, `M1`… se renumeran
  al regenerar; la clave no.
- **Estados:** `aceptado` (gris punteado, no cuenta como pendiente; botón «Aceptados» lo oculta), `corr` (naranja,
  en corrección) y `cerrado`. **`cerrado` solo se confirma cuando el catálogo deja de mostrar el salto**; si sigue
  vivo, el mapa lo marca «⚠ cerrado pero vivo» en la tabla, la matriz, el panel y el resumen de la libreta.
- Cada entrada lleva `id` (el de entonces), `fecha`, `por` y `motivo`. Se edita a mano.
- Estado inicial (17/09, paso 0 del plan): los 30 B y 3 D quedan **aceptados** (B14 sigue `corr` por F7);
  **137 pendientes** (A 56 · M 81). La chapa «n saltos» de cada caja cuenta solo lo pendiente.
- El resumen sale en la terminal al regenerar (`== LIBRETA DE DECISIONES ==`) y bajo «Saltos» en la página.

## Cómo se clasificó (sin inventar nada)

- **Tablas (capa 1):** relaciones de `crm`, `private` y `public` (118).
- **Núcleo (capa 2):** funciones de `private`, todas las funciones trigger (aunque vivan en `crm`), las 15 piezas
  F7 `cerrada_permanente` («órgano interno, jamás se derriba»), `pg_cron` y la Edge `ciclo-contratos` (solo la llama el cron).
- **Puertas (capa 3):** funciones de `crm`/`public` no trigger (abiertas si tienen EXECUTE para `authenticated`/`anon`,
  cerradas si no), las 3 vistas y las Edge HTTP.
- **Pantallas (capa 4):** las 26 rutas del CRM (Gerencia fusiona Hoy + 5 vistas porque `screens/gerencia.tsx` son
  envoltorios de `HoyGerencia`), el armazón de la app, el portal (solo sus llamadas directas por grep), la hoja
  comercial y el calendario externo.
- **Conexiones:** cuerpos SQL del catálogo (tablas solo si aparecen tras `from/join/into/update/delete/truncate/lock`;
  funciones solo si van seguidas de `(`), triggers, definiciones de vistas, `cron.job`, `net.http_post`, fuentes de las
  Edge y análisis estático del front (pantalla → hook → API → `rpc`/`from`; el store se resolvió por
  `useCRMData#propiedad`; `lazy(() => import())` se sigue).
- **Severidad de un salto:** **A** pantalla o Edge con `service_role` o puerta autónoma (sin ningún núcleo) que toca
  datos del negocio; **M** puerta mixta (usa núcleo pero además lee/escribe tablas directo) o inversión (núcleo que
  depende de una puerta); **B** catálogos y configuración; **D** vistas con `security_invoker` y el reloj interno
  que dispara puertas cerradas. Estado `corr` solo cuando TODOS los consumidores están en observación F7.
- Los nodos de Tablas/Núcleo/Puertas agrupan por módulo (17 módulos por prefijo de nombre; `mapa-datos.py`,
  lista `MODULOS`). Cada línea conserva la lista de conexiones reales que la componen.

## Doble criterio

Las referencias se sacaron dos veces: criterio laxo (`esquema.nombre`) y estricto (patrón de lectura o llamada).
Diferencias: 33 menciones de tablas sin patrón de lectura (tipos `%rowtype`, `to_regclass`, strings) y 6 menciones
de funciones sin paréntesis (mensajes de error). Se usó el estricto. Detalle en `datos.json → META.comparacion_detalle`.

## Regenerar

Rutas relativas a esta carpeta (`SERVIDOR-CRM/mapa-capas-2026-09-17/`); `R` es la raíz del taller. La CLI de Supabase
tiene que correr desde `CRM-Avance-Corp` (proyecto enlazado); `12_edge_deployadas.sql` es un marcador (`n/a`) y se salta.

```sh
R=$(git rev-parse --show-toplevel); M=$R/SERVIDOR-CRM/mapa-capas-2026-09-17
cd $R/CRM-Avance-Corp
for f in $M/evidencia/sql/*.sql; do b=$(basename $f .sql); [ $b = 12_edge_deployadas ] && continue; supabase db query --linked --file $f > $M/evidencia/$b.json; done
cd $M
node scripts/analyze-front.mjs $R/CRM-Avance-Corp/app/src front-graph.json     # requiere pantallas.json al lado de la salida
node scripts/analyze-edges.mjs edge-refs.json $R/_supabase_functions/functions $R/CRM-Avance-Corp/supabase/functions
python3 scripts/mapa-datos.py > listas.txt        # trabaja sobre esta carpeta: escribe datos.json, evidencia-mapa.json, datos-artifact.json
python3 - <<'EOF'
d=open('datos-artifact.json').read().replace('</','<\\/'); open('mapa-capas-crm.html','w').write(open('scripts/plantilla.html').read().replace('__DATOS__', d))
EOF
rm datos-artifact.json                             # intermedio de 0,7 MB; no se versiona
```

Para republicar **en la misma URL**, pasar `url: https://claude.ai/artifact/7rSe49eefhyVyuXgKZpg81` al publicar
(antes hay que leer el artifact en esa conversación). Publicar sin `url` crea otro artifact y rompe los enlaces del
vault y de la memoria.
