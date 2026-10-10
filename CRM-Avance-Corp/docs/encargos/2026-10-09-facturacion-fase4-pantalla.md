# Encargo a Codex (IMPLEMENTADOR) — Facturación fase 4: «todo número se abre» en pantalla

ROLE: IMPLEMENTER delegado por Claude (PRIMARY).
- Escribes SOLO dentro de este worktree:
  `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop-worktrees/facturacion-fase4-20261009`.
- Sin commit, push, red ni Docker. Sin dependencias nuevas y sin otros agentes. Todo en español.
- Puedes correr los comandos locales del front: `npm run check` y los tests de vitest.

## Objetivo

Regla de Miguel: «todo número se abre». En Facturación, al pulsar CUALQUIER número se abre una HOJA LATERAL NO MODAL con
la lista de operaciones (contratos y cooperativas) que lo forman, y esa lista suma exactamente ese número.
- **Qué número:** pastillas, celda analista×día, total de fila, de día, de equipo y la vista Día por tipo.
- **Maqueta APROBADA por Miguel (09/10):** `docs/encargos/maqueta/facturacion-lista-operaciones.html`. Ábrela y léela
  ENTERA: es el diseño a programar, con su panel de revisión de 6 estados. La maqueta de la fase 1 (la hoja ya
  programada) es `docs/encargos/maqueta/facturacion-hoja-excel.html`.
- **Montos:** CON COMA, como hoy en el CRM («S/ 25,000»). Decisión de Miguel: usa los formateadores existentes, NO el
  espacio de la maqueta.

## El servidor (fase 3B, APLICADA en producción)

```
crm.listar_operaciones_facturacion_fn(p_desde date, p_hasta date, p_dias date[] = null, p_analistas uuid[] = null,
  p_sin_analista boolean = false, p_equipo uuid = null, p_sin_equipo boolean = false, p_tipos text[] = null,
  p_moneda text = null, p_pagina int = 1, p_tamano int = 25) → jsonb
```

**Tipos:** ya regenerados en `app/src/lib/database.types.ts`.

**Respuesta:** `{version: 1, pagina, tamano, total, totales: [{moneda, operaciones, monto}], filas: [...]}`
- Fila VISIBLE: `n, fecha, tipo, moneda, monto, anulado, analista_id, analista_nombre, supervisor_id, supervisor_nombre,
  visible: true, cliente_nombre, estado`. Además:
  - contrato: `contrato_id, numero_contrato, cliente_id`;
  - cooperativa: `cierre_externo_id, cooperativa, lead_id`.
- Fila de OTRO EQUIPO: solo `n, fecha, tipo, moneda, monto, anulado, analista_id, analista_nombre, supervisor_id,
  supervisor_nombre, visible: false, cliente_nombre: 'Cliente de otro equipo'`. Ningún id.
- La lista sale de la MISMA fuente que la cifra (`crm.facturacion_diaria_fn`). Gerencia ve todo. Directorio ve
  contratos con nombre y cooperativas como «Cliente de otro equipo». El DNI no sale nunca.

**Reglas de los parámetros:**
- rango ≤ 31 días;
- `p_dias` ⊆ `[p_desde, p_hasta]` (días SUELTOS marcados en la hoja; regla de Miguel del 11/09, ver `facturacion.tsx`
  alrededor de «DÍAS SUELTOS»);
- `p_analistas` excluye a `p_sin_analista` y `p_equipo` excluye a `p_sin_equipo`;
- páginas de 25, 50 o 100;
- moneda `PEN`, `USD` o NULL.

Cualquier otro valor da el error 22023. Tipos de operación: `contrato_nuevo`, `contrato_upgrade`, `contrato_renovacion`,
`cooperativa`.

## Qué construir

### 1. Datos (un solo módulo cliente)

- **En `app/src/data/crm-api.ts`:** `listarOperacionesFacturacion(params)`.
  - Llama a la RPC con los Args generados.
  - VALIDA la respuesta: con `version` distinta de 1 o una forma inesperada, da un error claro de contrato. Nunca pinta
    datos a medias.
  - Exporta los tipos `OperacionFacturacion` y `ListaOperacionesFacturacion`.
  - Errores en palabras: el 22023 se traduce a un mensaje entendible.
- **Test MSW:** con el patrón de `app/src/data/crm-api-facturacion-msw.test.ts`. Debe cubrir que los argumentos viajan
  exactos, el parseo, el enmascarado y la versión desconocida.
- **Hook en `crm-queries.ts`:** la clave incluye TODOS los parámetros. Misma política de refresco que la cifra: un mes
  cerrado se refresca menos, pero no se congela (ver la fase 1).

### 2. `parametrosDeCifra()`: función PURA y con tests

Va del número pulsado a los parámetros de la puerta. Un caso por cada número de la pantalla:
- **pastillas:** total del tramo, por moneda o por tipo;
- **celda:** analista × día;
- **total de fila:** analista × tramo, o × días marcados;
- **total de día;**
- **total de equipo** (supervisor de entonces). «Sin supervisor» se convierte en `p_sin_equipo`;
- **«Sin analista»:** se convierte en `p_sin_analista`;
- **vista Día por tipo:** día × tipo;
- **días sueltos marcados:** se convierten en `p_dias`.

Si el número es de una moneda, va `p_moneda`. Si el número es un total convertido con tipo de cambio, la lista trae
las dos monedas y una línea explica la cuenta, como en la maqueta.

### 3. Componente de la hoja lateral

Por ejemplo `app/src/screens/facturacion/lista-operaciones.tsx`, fiel a la maqueta aprobada:
- **título en palabras;**
- **pastillas por moneda**, nunca sumadas, más la línea «Cuadra» que compara con el número pulsado;
- **tabla tipo Excel**, con número de fila y encabezado fijo:
  - fijos: # y Fecha a la izquierda, y Monto a la derecha;
  - N.º, Analista y Supervisor se ven deslizando, con la pista de la maqueta;
- **«Anulada · cuenta igual»** debajo del cliente;
- **«Cliente de otro equipo»** apagado, con su línea explicativa;
- **paginación** 25/50/100, con «Mostrando a–b de N»;
- **estados:**
  - cero → «Sin operaciones en este número»;
  - promedio o % → la lista de su base, con la línea de la cuenta;
  - carga;
  - error con reintento (`AvisoReintentar` o equivalente existente);
- **«Hay cifras nuevas · Actualizar»** cuando los `totales` no cuadran con el número pulsado. Sin recarga automática:
  Actualizar vuelve a pedir la cifra y la lista;
- **celular (≤ 640 px):** panel inferior a pantalla completa, con tarjetas.

Tiene que ser NO modal: la hoja de Facturación sigue usable detrás.
- Al abrir, el foco va al título del panel.
- Esc cierra el panel y el foco vuelve al número pulsado.

**Reglas de diseño y accesibilidad:**
- **Apariencia:** reglas de Miguel (navy `#111e3d`, azul `#2563eb`, sin verde, nombres de 16 px o más y detalle de 14 px
  o más), con las piezas de la fase 1 (`components/ui/pastilla.tsx`, `components/ui/estilos-hoja.ts`) y los
  formateadores existentes.
- **Movimiento:** `prefers-reduced-motion`.
- **Accesibilidad:** patrones de `app/.oxlintrc.json`. NO se apagan reglas nuevas.

### 4. Cablear la pantalla (`app/src/screens/facturacion.tsx`)

- Todo número es un `<button>` con un `aria-label` descriptivo que abre la hoja.
- Conserva la forma accesible de «Ver el mes completo de…»: sus tests se ADAPTAN, no se borran.
- Lo que ya funciona no se rompe: tests de la fase 1 y vista celular.

### 5. Pruebas

- **Unitarias:**
  - `parametrosDeCifra`: cada número, «Sin analista», «Sin supervisor» y días sueltos;
  - el parser.
- **De componente:**
  - los 6 estados de la maqueta;
  - foco y Esc;
  - tarjetas en celular;
  - que la fila de otro equipo no muestra N.º ni cooperativa.
- **ESTADO DE PRODUCCIÓN** (regla del gate de realidad, `CRM-Avance-Corp/CLAUDE.md`): probar también con lo que hay hoy
  en producción, no solo con el fixture lleno:
  - filas de otro equipo para un supervisor;
  - meses sin operaciones;
  - error del servidor.
- **e2e:** nuevo spec `app/e2e/facturacion-lista.spec.ts`, con el patrón de `app/e2e/facturacion-realidad.spec.ts`.
  - Abrir una celda, comprobar que la lista suma la cifra, paginar, Esc y celular.
  - Ojo: los mocks e2e hacen eco de los argumentos: comprueba los args que viajan con `postDataJSON()`.
  - No lo puedes correr (Docker): lo corre el PRIMARY.
- **`npm run check`** en `app/` (oxlint, typecheck y coverage): tiene que quedar en VERDE.

## Fuera de alcance

El servidor, que no se toca. La 0B. Publicar: lo hace Miguel con `/release-crm`.

## Informe final

Breve. Archivos tocados, PASS/FAIL de `npm run check` y qué no pudiste verificar.
