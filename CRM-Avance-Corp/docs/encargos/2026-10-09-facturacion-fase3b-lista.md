# Encargo a Codex (IMPLEMENTADOR) — Facturación fase 3B: la puerta de la lista y sus permisos

ROLE: IMPLEMENTER delegado por Claude (PRIMARY).
- Escribes SOLO dentro de este worktree:
  `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop-worktrees/facturacion-fase3b-20261009`.
- Sin commit, push, red, Docker ni producción, y sin invocar a otros agentes.
- Todo en español. Nivel 3. No edites migraciones ya commiteadas.
- Al terminar, informe breve.

## Objetivo (plan de Facturación por fases, 09/10, auditado por Codex)

«Todo número se abre»: en la fase 4, cada número de Facturación abrirá una hoja lateral con las operaciones que lo forman.
- **Qué número:** pastilla, celda analista×día, total de fila, de día, de equipo o la vista Día por tipo.
- **Qué hace esta fase (3B):** crea la PUERTA del servidor de esa lista. En pantalla no cambia nada.
- **Base (3A, APLICADA en producción hoy):** la cifra (`crm.facturacion_diaria_fn`) ya es un `group by` sobre
  `private.facturacion_operaciones_visibles`.
- **La regla que importa:** la lista lee de ESA MISMA pieza, así que la lista de cada número suma exactamente ese número.

**Decisiones de Miguel (09/10), obligatorias:**
- **Mes sellado = cuenta viva**, como la cifra.
- **Si el cliente no es visible para quien mira:** la fila sale como «Cliente de otro equipo», CON su importe y SIN nombre,
  N.º ni ningún identificador.
- **Directorio** ve los nombres (también en cooperativas).
- **El DNI no sale NUNCA.**
- **No se registra** quién abre listas.

## Cuerpos vivos de producción (en `supabase/scripts/facturacion-lista/vivo/`, md5 de `pg_get_functiondef`)

| Función | md5 | ACL |
|---|---|---|
| `crm.facturacion_diaria_fn` | `3753d03552e26eb7e61117a3baab6f78` | postgres + authenticated |
| `private.facturacion_operaciones` (SIN verja; único llamador `_visibles`) | `5d63cb537b0b286ad47feb7f5b26d161` | solo postgres |
| `private.facturacion_operaciones_visibles` (verja + recorte) | `17c2ca27996adad88f685896915953e3` | solo postgres |
| `private.cliente_ids_visibles_crm` | `6e3e3442103b216116a263ae6342e852` | solo postgres |
| `private.vendedor_ids_visibles` | `85544c70a0920f3a7a1b5da06935f236` | postgres + authenticated |
| `private.es_lector_global` | `c8be602f84348a0125617995802db618` | postgres + authenticated |
| `private.rol_crm` | `99827f3fe2fbc3cfae5668c30015c758` | postgres + authenticated |
| `crm.cierres_externos_fn` (regla de cooperativas) | `67f5f9c020ea6395da20444911bd303b` | postgres + authenticated |
| `private.analista_efectivo_cierre` | `2cf2201f8a01c381a7756293fbdadd46` | solo postgres |
| `crm.cartera_inversionistas_filtrada_fn` → `private.cartera_f5_listar` (patrón de lista paginada) | `79aac4ba…` / `33d7d57b…` | — |

Léelos enteros. Contexto de la 3A: `supabase/scripts/facturacion-una-fuente/` (LEEME, migración `20261009224000`, generadores,
ensayos y registrador), que es el PATRÓN de este kit.

Columnas relevantes:
- `public.contratos`: `numero_contrato`, `cliente_id`, `estado`, `categoria`.
- `public.perfiles`: `nombre_completo`, `dni`, `beneficiario_dni`, `beneficiario_dni_usd`, `asesor_perfil_id`, `creado_por`.
- `crm.cierres_externos`: `cooperativa`, `nombre_completo`, `documento` (es DNI), `documento_tipo`, `numero_transaccion`,
  `lead_id`, `inversionista_id`, `anulado_en`.
- `crm.inversionistas`: `responsable_relacion_id`.
- `crm.leads`: `vendedor_id`.

Tipos de operación: `contrato_nuevo`, `contrato_upgrade`, `contrato_renovacion`, `cooperativa`.

## Diseño

### 1. Puerta `crm.listar_operaciones_facturacion_fn`

- **Firma:** `(p_desde date, p_hasta date, p_analistas uuid[] default null, p_equipo uuid default null,
  p_sin_equipo boolean default false, p_tipos text[] default null, p_moneda text default null,
  p_pagina integer default 1, p_tamano integer default 25) returns jsonb`.
- **Contrato:** LANGUAGE sql, STABLE, SECURITY DEFINER, dueño postgres, `search_path ''`.
  - EXECUTE solo para `authenticated` (revocado a public, anon y service_role).
  - Solo delega en el núcleo. Patrón: `crm.cartera_inversionistas_filtrada_fn`.

### 2. Núcleo `private.facturacion_lista` (mismos parámetros)

- **Contrato:** plpgsql, STABLE, SECURITY INVOKER, dueño postgres, `search_path ''`, ACL solo postgres.
- **Validación:** error `22023` con mensaje claro si:
  - `p_desde` o `p_hasta` son NULL, o `p_hasta < p_desde`;
  - el rango pasa de 31 días (`p_hasta - p_desde > 30`);
  - `p_tamano` no es 25, 50 ni 100, o `p_pagina` es NULL o menor que 1;
  - `p_moneda` no es NULL, 'PEN' ni 'USD';
  - viene `p_equipo` junto con `p_sin_equipo`;
  - `p_analistas` o `p_tipos` llegan como arreglo VACÍO (NULL = todos).
- **CAPA 1 (qué operaciones):** UNA llamada a `private.facturacion_operaciones_visibles(p_desde a medianoche de Lima,
  (p_hasta + 1) a medianoche de Lima)`. Usa las mismas expresiones de medianoche que la puerta de la cifra.
  - Encima, los filtros:
    - analistas → `analista_id = any(p_analistas)`;
    - equipo → `supervisor_id = p_equipo`, que es el supervisor DE ENTONCES, como las bandas de la pantalla;
    - `p_sin_equipo` → `supervisor_id is null`;
    - tipos → `tipo = any(p_tipos)`;
    - moneda → `moneda = p_moneda`.
  - NADA de la lista puede salir de otra fuente.
- **Orden total:** `(fecha, tipo, operacion_id)`. `n` es la posición 1..total en ese orden.
  - Página: `offset (p_pagina - 1) * p_tamano limit p_tamano`.
  - Mismo orden en todas las páginas: ninguna fila se repite ni se salta.
- **CAPA 2 (qué datos de cada operación).** `visible` es verdadero para Gerencia y el lector global (Directorio).
  Para los demás:
  - **contrato:** `cliente_id = any(<array de private.cliente_ids_visibles_crm()>)`;
  - **cooperativa:** la RELACIÓN con el cliente es del equipo de quien mira, con la MISMA regla que la sección «En
    cooperativas» de `crm.cierres_externos_fn`:
    - con `inversionista_id`: su `responsable_relacion_id` ∈ `private.vendedor_ids_visibles(auth.uid())`;
    - sin inversionista: `crm.leads.vendedor_id` ∈ esos visibles.
  - **Por qué esta regla:** «cliente de otro equipo» significa que la relación con el cliente es hoy de otro equipo.
    Para contratos, `cliente_ids_visibles_crm` mira el asesor del cliente; en cooperativas, el responsable de la
    relación es el equivalente. Así la lista nunca revela un nombre que quien mira no vea ya en Mi cartera.
  - **Rendimiento:** los dos arreglos de visibles se calculan UNA vez y solo si quien mira no es global. NADA de llamar
    funciones SQL por fila: en Postgres 17 una función SQL anidada se re-planifica en CADA fila, y el 09/10 eso llevó un
    cálculo de 15 a 171 ms.
- **Respuesta jsonb:**
  ```
  { "version": 1, "pagina": n, "tamano": n, "total": n,
    "totales": [ { "moneda": "PEN", "operaciones": n, "monto": n }, ... ],   -- del conjunto FILTRADO; PEN y USD nunca sumados
    "filas": [ ... ] }
  ```
  - **Fila VISIBLE:** `n`, `fecha` (`dia` de Lima, date), `tipo`, `moneda`, `monto`, `anulado`, `estado`,
    `analista_id`, `analista_nombre`, `supervisor_id`, `supervisor_nombre` (o 'Sin analista' / 'Sin supervisor', como
    la cifra), `visible: true` y `cliente_nombre`. Además:
    - contrato: `contrato_id`, `numero_contrato`, `cliente_id`;
    - cooperativa: `cierre_externo_id`, `cooperativa`, `lead_id`, `cliente_nombre` = `ce.nombre_completo`.
  - **Fila ENMASCARADA:** SOLO `n`, `fecha`, `tipo`, `moneda`, `monto`, `anulado`, `analista_id`, `analista_nombre`,
    `supervisor_id`, `supervisor_nombre`, `visible: false` y `cliente_nombre: 'Cliente de otro equipo'`.
    - Ni un id del contrato, cierre, cliente o lead.
    - Ni N.º, cooperativa, estado ni `numero_transaccion`.
  - **El DNI no sale nunca**, y tampoco `perfiles.dni`, `beneficiario_dni*`, `cierres_externos.documento` ni datos
    bancarios.
  - **Sin autorización** (vendedor, coordinador, de baja, sin sesión): `total` 0, `filas` [] y `totales` [], porque la
    capa 1 ya no devuelve nada. Mismo criterio que la cifra: verja de visibilidad, no error.
- `COMMENT ON` de todo. El de la puerta explica las dos capas.

## Entregables

### 1. Migración

**`supabase/migrations/20261009234500_crm_facturacion_lista_operaciones.sql`**. Patrón: la de la 3A.
- Transacción REPEATABLE READ con `lock_timeout` 10s y `statement_timeout` 120s.
- `DO` idempotente y fail-closed.
- **PREFLIGHT:**
  - exige la 3A con sus huellas: `5d63cb53…`, `17c2ca27…` y `3753d035…`;
  - exige que ni la puerta ni el núcleo nuevos existan, o que ya estén con sus huellas nuevas (reaplicar).
- **POSTFLIGHT:**
  - huellas nuevas como `'PENDIENTE_MEDIR_EN_BANCO'` (las mido yo);
  - dueño, ACL exacta, `prosecdef`, volatilidad, lenguaje y `search_path`;
  - guardas con `is not true`.
- **ORÁCULO en la misma transacción.**
  - **Identidades:** una Gerencia activa, Directorio (si `es_lector_global()` lo reconoce), CADA supervisor activo, un
    vendedor activo y sin sesión. La identidad se fija con los dos GUC, como la 3A, y se limpian al final.
  - **Meses:** los que tienen operaciones, más el actual.
  - **Por cada identidad y mes**, se recorren TODAS las páginas con tamaño 100 y se exige:
    - a) filas recogidas = `total`, y `n` = 1..total sin huecos ni repetidos;
    - b) **LA LISTA SUMA LA CIFRA:** las filas agregadas por (fecha, tipo, moneda, analista_id, supervisor_id) con
      `count` y `sum(monto)` son IGUALES (`EXCEPT ALL` en los dos sentidos) a `crm.facturacion_diaria_fn(mes)` de esa
      misma identidad, sin nombres;
    - c) `totales` = suma por moneda de la cifra;
    - d) toda fila enmascarada tiene EXACTAMENTE las claves permitidas, y para Gerencia no hay ninguna;
    - e) en contratos visibles no globales, `cliente_id` ∈ `cliente_ids_visibles_crm()` de esa identidad;
    - f) **NINGÚN DNI:** ningún texto de fila contiene un `dni`, `beneficiario_dni*` o `documento` no vacío (≥ 6
      caracteres) de los clientes y cierres de las operaciones del mes.
  - **Filtros en al menos un mes con datos:** analista, equipo, sin equipo, tipo y moneda devuelven exactamente la parte
    de la cifra correspondiente.
  - **Negativas:** cada parámetro inválido da `22023`.
  - Avisos (`raise notice`) con lo comparado y los milisegundos.

### 2. Kit en `supabase/scripts/facturacion-lista/`

- **`generar-cuerpos.py`:** sincroniza el DO de la migración en los ensayos y la medición. `--verificar` no escribe.
- **`generar-registrar.py`:** copia el de la 3A ajustado. Escribe un `registrar.sql` idempotente que se niega ante otro
  texto ya registrado.
- **`reversa.sql`:** borra puerta y núcleo, sin CASCADE.
  - Es idempotente.
  - Se niega si otra función los usa (patrón de la guarda de consumidores de la reversa 3A).
  - Va ANTES que la reversa de la 3A, que se niega mientras esto exista: es correcto.
- **`ensayo-sintetico.sql`** (banco VACÍO con la 3A instalada con las huellas de producción; termina en ROLLBACK):
  - **Siembra propia** (patrón de la siembra de la 3A, con la misma precaución de READ COMMITTED):
    - dos equipos;
    - un contrato cuyo cliente hoy es del otro equipo (enmascarado para el supervisor viejo);
    - una cooperativa con inversionista de otro equipo y otra sin inversionista (regla por lead);
    - una cooperativa anulada;
    - clientes con `dni` y cierres con `documento`;
    - PEN y USD.
  - **Aplica la migración** y comprueba casos concretos por identidad.
  - **MUTANTES**, cada uno cazado SOLO por un SQLSTATE propio de la comparación:
    - sin capa 2 (todo visible);
    - con el DNI en la fila;
    - página corrida una posición;
    - capa 1 saltada (llamar al núcleo sin verja);
    - totales que suman PEN y USD.
  - **Reversa** al final.
- **`ensayo-produccion.sql`:** el DO de la migración, terminado en RAISE.
  - Exige la 3A REGISTRADA (`20261009224000`).
  - El MENSAJE FINAL lleva la evidencia (meses, identidades, filas, enmascaradas, huellas y ms), porque
    `db query --linked` no muestra los NOTICE.
- **`medir.sql`:** en la misma transacción, como Gerencia.
  - Mide una página (tamaño 100, página 1, con totales) de septiembre y de octubre: mediana de 7 muestras tras calentar.
  - Falla si pasa de 150 ms. El mensaje final lleva los números.
- **`LEEME.md`.**

### 3. Ledger

**`supabase/migrations/MIGRACIONES.md`:** una entrada AL FINAL, «en banco, sin aplicar».

### 4. Gate (`supabase/scripts/test-rls.mjs`)

- **Bloque L de `testFacturacionDiaria`:** actualizar el CENSO a la nueva lista cerrada.
  - Llamadores de `_visibles`: `crm.facturacion_diaria_fn` y `private.facturacion_lista`.
  - Llamadores de `private.facturacion_lista`: solo la puerta nueva.
  - Contrato y ACL exacta de las dos funciones nuevas, y la cadena nueva en el catálogo.
- **Nueva `testFacturacionLista(sessions, seed)`**, registrada junto a `testFacturacionDiaria`. Usa la API y el mismo
  `MES` que el bloque de la cifra. Debe comprobar:
  - **sesiones** gerencia, directorio, sup1, sup2, vend1, coordinador, clientBank y vendInactive: la lista del mes
    (`total` y `totales`) es igual a la suma de SU cifra;
  - **Directorio** recibe lo mismo que Gerencia;
  - **páginas** de 25, 50 y 100 concatenadas dan el mismo conjunto, sin repetidos;
  - **filas enmascaradas** sin ids;
  - **ningún DNI** del banco en ninguna respuesta (obtenerlos fuera de banda con `textoFueraDeBanda`/`contarFueraDeBanda`);
  - **parámetros inválidos** dan `22023`;
  - **anon** da error de autorización;
  - **sin autorización** (vend1, coordinador, clientBank, vendInactive): `total` 0.

  Salto ruidoso si la función no existe (patrón del bloque de la cifra).
- `supabase/scripts/test-facturacion.sql` NO cambia.

## Fuera de alcance

La pantalla (fase 4), la 0B y cualquier cambio en la cifra o en las piezas de la 3A.
