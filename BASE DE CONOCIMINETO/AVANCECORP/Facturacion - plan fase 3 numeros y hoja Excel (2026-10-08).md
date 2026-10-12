---
tags: [facturacion, plan, crm]
fecha: 2026-10-08
estado: propuesta — espera decisiones de Miguel
---

> Plan de la fase 3 de [[Facturacion - auditoria completa (2026-10-08)]]. Sin código. Nivel 3 (datos personales y una función viva de dinero): nada se escribe sin el OK de Miguel. Pieza visual para decidir: `ui-playground/facturacion-hoja-excel.html`.

# Facturación · fase 3: «todo número se abre» y hoja tipo Excel

- **Qué es.** Un plan sin código.
- **De dónde parte.** Del commit `c0bff295`, que es lo publicado (`0d9f8f3b`) más la fase 1.
- **Nivel 3.** Toca datos personales y una función viva que calcula dinero. Antes del gate pasa por `auditor-rls` y por una revisión de Codex.
- **Nada se escribe sin el OK de Miguel** (regla de «Autonomía»).

En las referencias, `:N` sin archivo es `app/src/screens/facturacion.tsx`.

## 1. Objetivo y punto de partida
**Objetivo**
- **Todo número se abre.** Cualquier número de la pantalla abre la **lista de operaciones** (contratos y cooperativas) que lo forman, y la lista suma exactamente ese número.
- **La pantalla se lee como una hoja de Excel:**
  - cifras de arriba en pastillas pequeñas;
  - columna #;
  - encabezado y primeras columnas fijos;
  - letra de 16 px o más en nombres y de 14 px o más en el resto;
  - tarjetas en el celular;
  - sin días por venir vacíos y sin hueco en la vista Día.

**Cómo está hoy**
- Solo abren algo la celda analista × día, si vale más de 0 (`:299`), y el nombre del analista (`:372-388`).
- Lo que abren es un desglose por tipo y moneda (`lib/facturacion.ts:923-953`), no la lista de contratos. El propio panel lo admite (`:1883-1886`).
- La puerta solo entrega el mes ya agrupado (`20260916205617:78-89, :208-212`).
- El volumen real se maneja con paginación: en setiembre hubo 209 operaciones (172 en soles y 37 en dólares), según la salida de producción de la auditoría (`auditoria-facturacion/salida/2-realidad.json`).

## 2. Servidor: un núcleo y dos puertas
**Para que la lista y la cifra nunca difieran, las dos salen de la misma pieza.**
- **Núcleo privado.** El cuerpo de `crm.facturacion_diaria_fn` se mueve tal cual a `private.facturacion_operaciones(p_desde, p_hasta)`:
  - las CTE `quien`, `ambito`, `episodios`, `eventos` y `tramos`;
  - el recorte `20260916205617:205-207`.
- **Qué devuelve.** Una fila por operación, con `contrato_id`/`cierre_externo_id`, `cliente_id`, `estado` y `anulado`. Todo eso ya lo da `private.capital_episodios` (`20260908211349:888`).
- **La cifra.** `facturacion_diaria_fn` pasa a ser un `group by` sobre el núcleo, con la misma firma, las mismas columnas y el mismo orden.
- **La lista.** La puerta nueva filtra, pagina y oculta datos sobre ese mismo núcleo. Así la cifra es el `count/sum` de las mismas filas: es la regla de unificar antes que vigilar.
- **Descartado: sacar las cifras de la lista en la pantalla.** Obligaría a bajar el mes entero con los nombres de los clientes solo para pintar la malla.

```
crm.listar_operaciones_facturacion_fn(
  p_dias date[],                       -- 1–31 días en ventana ≤31 (mes, semana que cruza de mes, días marcados)
  p_supervisor_id uuid default null,   -- equipo = supervisor DE ENTONCES
  p_sin_supervisor boolean default false,
  p_analista_ids uuid[] default null,  -- uno o varios (comparar)
  p_sin_analista boolean default false,
  p_tipo text default null,            -- contrato_nuevo|contrato_renovacion|contrato_upgrade|cooperativa
  p_moneda text default null,          -- PEN|USD; null = las dos
  p_pagina int default 1, p_tamano int default 50)  -- 25|50|100
returns jsonb -- {version, alcance, pagina, tamano, total, totales:[{moneda, operaciones, capital}], filas:[…]}
```

**Reglas de la puerta**
- **Sin rol ni negocio del cliente.** Los saca de `auth.uid()`.
- **Sin lógica de negocio.** Valida, autoriza, pagina y delega en el núcleo.
- **`security definer` justificado.**
  - La puerta lee `crm.cierres_externos`, que no tiene grants ni policies (`20260812000259:203-210`).
  - El núcleo lee `crm.usuario_eventos`, que solo puede leer su dueño (`20260916205617:257-263`).
  - Por eso las dos llevan dueño `postgres` y `search_path = ''`.
- **Errores.** Una entrada mala devuelve 22023, igual que `20260916023055:22-35`.
- **Permisos.** EXECUTE solo para `authenticated`. El núcleo queda revocado para todos.
- No hay tablas nuevas.

**Ámbito: el mismo de la cifra, porque lo pone el núcleo**
- **Gerencia y Directorio:** todo.
- **Supervisor:** las ventas cuyo supervisor de entonces es él o alguien de su subárbol de hoy, más las que vendió él (`20260916205617:103-117, :205-207`).
- **Vendedor, coordinador, cliente y personas dadas de baja:** total 0 y lista vacía. Es una verja que esconde, no un error 42501 (`:45-47` de esa migración).
- **`anon`:** sin EXECUTE.

**Columnas y datos personales**

| Dato | Gerencia | Supervisor | Directorio |
|---|---|---|---|
| Día, tipo, moneda, monto, estado o «anulada», analista, equipo | sí | sí | sí |
| Nombre del cliente y N.º (`numero_contrato`; en cooperativa `referencia_externa`, como la cartera, `20260908230249:83`) | sí | solo si ya lo ve por la vía de siempre; si no, «Cliente de otro equipo» con su importe | contratos sí; cooperativas las decide Miguel |
| DNI o documento | no | no | no |

- **Se copia la verja que ya existe, no se abre una más ancha** (memoria «envoltorio DEFINER se salta la RLS»):
  - en contratos, `cliente_id ∈ private.cliente_ids_visibles_crm()` (`20260828210351:459-494`);
  - en cooperativas, `vendedor_id ∈ vendedor_ids_visibles`, como `crm.cierres_externos_fn` (`20260914213928:1021`).
- **Cuándo se oculta un nombre.** Cuando el analista cambió de equipo: su venta vieja sigue contando para su antiguo supervisor, pero el cliente ya es de otro equipo.

**Tope de 1000 filas, paginación e índices**
- **El tope no aplica.** Un solo jsonb no lo toca `max_rows = 1000` (`supabase/config.toml:18`).
- **Totales y orden.** Los totales son de todo el filtro, no de la página (como `20260916023055:87-109`). Los nombres solo se buscan para la página (100 filas como máximo). Orden estable: día, moneda, monto de mayor a menor, id.
- **Sin índices nuevos.** Lee la misma ventana que la cifra (32 ms por mes según la auditoría) con `idx_contratos_fecha_cierre_comercial` (`20260824170630:214`) e `idx_cierres_externos_creado_en` (`20260812000259:217`).
- **Se mide igual.** `EXPLAIN ANALYZE` en el banco, como gerencia y como supervisor, con tope de 100 ms. Solo si se supera se propone un índice.

**Migración** (`…_crm_facturacion_lista_operaciones.sql`)
- **Preflight.** Comprueba la huella viva de `facturacion_diaria_fn` (el 16/09 era `79d75db2…`; se relee en producción con `!`).
- **Cuerpos generados desde el `prosrc` vivo.**
- **A/B dentro de la migración.** Guarda la salida de setiembre, octubre y un mes sin dólares, como gerencia y como cada supervisor. Después del cambio exige que salga idéntica.
- **Postflight.** Es el del 16/09 ampliado:
  - los totales de la lista igualan la cifra de cada supervisor;
  - vendedor y sesión vacía reciben vacío;
  - dueño `postgres`, `search_path=""`, sin PUBLIC y huella por `pg_get_functiondef`.
- **Además:** `COMMENT ON` en las tres funciones, `MIGRACIONES.md`, registrador y reversa.

## 3. Mapa número → lista
Abreviaturas de la tabla:
- **T**: los días del tramo, o los marcados (`:465-469`).
- **E / A**: los filtros de equipo y de analistas (`:598`).
- **t**: el tipo (null en «Todos»).
- **m**: la moneda de la vista (null en «Todo S/»).
- **u**: null si la cifra está unificada (`puedeUnificar`, `:766`); si no, m.

| Número (línea) | p_dias | equipo | analistas | tipo | moneda | Arriba de la lista |
|---|---|---|---|---|---|---|
| Titular y su «S/ X + US$ Y» (`:1274, :806-812`) | T | E | A | t | u | S/ X + US$ Y × tasa = cifra |
| % vs. tramo anterior (`:813-818`) | tramo anterior recortado (`:736-741`) | E | A | t | u | antes → ahora = ±z % |
| Contratos cerrados (`:1285`) | T | E | A | t | m | N operaciones = contratos + cooperativas |
| Mejor día (`:1299-1305`) | [ese día] | E | A | t | m | — |
| Promedio por día hábil (`:1319-1327`) | T | E | A | t | m | total ÷ N días hábiles (la lista más cercana, dicho así) |
| Equipo × día / total del equipo (`:1611-1628`) | [día] / T | grupo | A | t | m | — |
| Analista × día / total / nombre (`:391-412, :372-388`) | [día] / T | grupo (de entonces) | [analista] | t | m | — |
| Pie por día / total (`:1662-1693`) | [día] / T | E | A | t | m | — |
| Pie «Total del día en soles» (`:1737-1785`) | [día] / T | E | A | t | null | soles + dólares × tasa |
| Comparar (`:1562-1581`), vista Día y tarjetas (§4) | igual que analista; vista Día con el tipo de su columna | | | | | |

- **«Sin supervisor» y «Sin analista»** van como bandera, nunca como un id inventado (`lib/facturacion.ts:473`, `crm-api.ts:4675`).
- **Lo que no es dinero no abre lista.** Los conteos de personas (`:1288, :1607`) y los chips de filtro llevan a la malla, que ya es su lista. Un cero no se abre (`screens/rescate/analista.tsx:128`).
- **Total convertido.** En «Todo S/», la lista enseña cada moneda con su subtotal y la suma con la misma tasa que la malla (`totalEnSoles`, sin redondeos intermedios: `lib/tipo-cambio.ts:30`).

## 4. Pantalla por pasos
Cada paso es un commit, pasa `npm run check` y se mide con e2e en Docker.

| Paso | Qué cambia | Qué se mide |
|---|---|---|
| E1 Pastillas | Los 4 `KpiCard` (`:1265-1339`) se convierten en una fila de `Pastilla` (la de `base-gestion/filtros-base.tsx:22`, ampliada para aceptar texto). Cada pastilla es un botón | alto del resumen ≤ 56 px a 1440 px (hoy 196) |
| E2 Hoja | Columna # seguida, con los equipos como bandas (`hoja-base.tsx:5-6`). # y nombre fijos a la izquierda, total fijo a la derecha | tras desplazar a la derecha y hacia abajo, siguen a la vista #, nombre y cabecera |
| E3 Letra | Nombres de 13 a 16 px (`:381, :1603`). Celdas, pie, cabeceras y ayudas de 9–13 a ≥14 px (`:282, :383, :407, :1522, :1530, :1675, :1772, :233, :1224`). Celda de 52 a unos 64 px | ningún texto visible por debajo de 14 px; ningún nombre por debajo de 16 px |
| E4 Días por venir | En el tramo de hoy, los días que faltan se pliegan en una columna «9–31 oct · por venir» | el 08/10 se ven 8 días + 1 columna; sin scroll horizontal a 1440 px |
| E5 Vista Día | Columnas por tipo (Nuevo · Renovación · Upgrade · Cooperativa · Total) con los datos que ya trae `facturacion_diaria_fn` | hueco a la derecha < 15 % (hoy unos 930 px) |
| E6 Celular (`useEsMovil`) | Tarjeta por analista agrupada por equipo: nombre 16 px, total, operaciones y los días en que vendió. Pastillas arriba. La malla sale del teléfono y con ella `facturacion-movil.css` | a 390×844 sin scroll horizontal; el supervisor ve a su equipo; cada cifra es un botón |
| L1 Lista | `ListaOperaciones` con el molde de `base-gestion/detalle-cifra.tsx` (hoja lateral no modal, tabla con # y cabecera fija, tarjetas en el celular, paginación, estados cargando / error / «aún no disponible» con PGRST202 / vacío). Sustituye el desglose (`:1815-1890`) y `desgloseDeCelda`. Se añaden la función pura `parametrosDeCifra()`, `listarOperacionesFacturacion` y su hook | cada fila de §3 abre su lista y la cabecera muestra el número pulsado |
| L2 Cuadre | Si `totales` no coincide con el número (la malla se refresca cada 5 min, `crm-queries.ts:869`), se avisa y se refresca la malla | test con una respuesta que cambió |

## 5. Pruebas
- **Unitarias.**
  - Tabla de `parametrosDeCifra`: cada número × vista × tipo × días marcados × filtros.
  - Estado de producción: sin tasa y con dólares; más de 50 operaciones (página de 50 y cabecera con la cifra entera); cliente oculto.
  - PGRST202 da «no disponible».
  - Mutantes: quitar cualquier parámetro tumba una prueba.
- **SQL, `test-facturacion.sql`** (termina en rollback).
  - Con el cambio de equipo que ya siembra, la lista atribuye cada venta al supervisor de entonces y cuadra con la cifra.
  - El supervisor viejo ve esa venta con el cliente oculto.
  - Se engancha al gate (hoy está suelto: P2-12).
- **Gate `test-rls.mjs`** (bloque nuevo junto a `:9253`; con `CRM_RLS_EXIGE_FACTURACION=1`, saltarlo cuenta como fallo).
  - Gerencia y Directorio: la lista suma lo mismo que su cifra.
  - sup1 y sup2: ninguna fila ajena, totales iguales a la cifra, y números visibles ⊆ los que ya les da `crm.contratos_cartera_fn` / `crm.cierres_externos_fn`, que sirven de oráculo independiente.
  - vend1, coordinador, clientBank y vendInactive: vacío. anon: 42501.
  - Otro equipo da 0. Las páginas, sin duplicados ni huecos. Una entrada mala da 22023.
  - Quitar `a.ok`, el recorte o la máscara tiene que dar ROJO.
- **E2E en Docker local.** Se amplía `facturacion-realidad.spec.ts` con las medidas de §4 y un clic por fila de §3. Lleva `CRM_E2E_CONTAINER`/`TASK`/`VOLUME` propios y mocks con respuesta fija por pedido, sin eco de argumentos.
- **Banco Docker a paridad.**
  - El A/B, con el gate antes y después.
  - Advisors sin clase nueva.
  - Trinquetes iguales: los cuerpos nuevos no nombran `crm.leads` ni «reunion».
  - `gen:types`, `check`, `gate:realidad` y `revisor-a11y`.

## 6. Despliegue y reversa
1. **Primero E1–E6.** Son solo pantalla y no dependen de nada.
2. **Luego el servidor.**
   - La puerta todavía no tiene consumidor y `facturacion_diaria_fn` responde igual (probado con el A/B), así que el front vivo no nota nada.
   - Orden: banco → gate → advisors → `auditor-rls` → Codex → Miguel aplica con `!` y registra → postflight.
3. **Al final L1–L2**, con `/release-crm` y su preflight. En el orden inverso, todas las listas dirían «aún no disponible».

**Reversa**
- **Pantalla:** commit de reversa y release.
- **Servidor:** una migración de reversa, ensayada en el mismo PR:
  - borra la puerta;
  - devuelve `facturacion_diaria_fn` al cuerpo exacto de `20260916205617`, con su huella comprobada;
  - borra el núcleo.

  El front nuevo aguanta la reversa: con PGRST202 dice «no disponible».

## 7. Riesgos
- **Reescribir una función viva que calcula dinero.**
  - La cubren la huella, el A/B y el postflight rol por rol.
  - Si la fase 2 (jerarquía) la toca antes, esta migración se regenera sobre la huella nueva.
- **Datos personales en manos de supervisores.** Se copia la verja que ya existe, no el ámbito ancho. Lo revisan `auditor-rls` y Codex.
- **Lista y malla de distinto momento.** Lo resuelve L2.
- **Datos dudosos de la fase 0.** Las listas los harán visibles (12 contratos «nuevo» que son upgrades, el perfil de pruebas, el posible duplicado 001490/001484). Conviene cerrar la fase 0 antes de enseñarlas.
- **Lo anulado aparece y cuenta** (ATR-4, `lib/facturacion.ts:17-20`). Hay que rotularlo «cuenta igual».
- **Carpeta compartida.** Worktree y Docker propios; commits con `git commit -- <rutas>`.

## 8. Decisiones de Miguel
1. **Supervisor.** ¿Ve «Cliente de otro equipo» con el importe (recomendado) o el nombre siempre?
2. **Directorio y cooperativas.** ¿Ve sus nombres? Hoy chocan dos precedentes: la cartera se los oculta (`20260916023055:47`) y `cierres_externos_fn` se los da. Además sigue abierta la pregunta de la fase 0: ¿abrir Facturación a Directorio?
3. **DNI.** Fuera de la lista para todos (recomendado).
4. **Vista Día.** Por tipo (recomendado) o directamente la lista del día.
5. **Días por venir.** Una columna plegada (recomendado) u ocultos.
6. **Registro de quién abre las listas, como en la Cartera.** Recomendado: no, porque el mismo dato ya sale sin registro por `crm.contratos_cartera_fn`.
7. **Orden.** E1–E6, servidor y listas (recomendado), o todo junto.
