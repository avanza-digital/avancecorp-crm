# Encargo a Codex (IMPLEMENTADOR) — Facturación fase 3A: una sola fuente para la cifra y la lista

ROLE: IMPLEMENTER delegado por Claude (PRIMARY). Escribes SOLO dentro de este worktree
(`/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop-worktrees/facturacion-fase3a-20261009`). Sin commit,
push, red, Docker ni producción, y sin invocar a otros agentes. Todo en español. Nivel 3. No edites migraciones ya
commiteadas. Al terminar, informe breve.

## Objetivo (plan de Facturación por fases, 09/10, auditado por Codex)

«Todo número se abre»: en la fase 4, cada cifra de Facturación abrirá la lista de operaciones que la forman, y esa lista
tiene que sumar EXACTAMENTE la cifra. Para que nunca puedan diferir, las dos salen de las mismas piezas. Esta fase (3A)
crea esas piezas y hace que la cifra de hoy beba de ellas, **sin cambiar ni una fila de su salida** (lo demuestra un
oráculo). La puerta de la lista es la 3B y no entra aquí. En pantalla no cambia nada.

**Decisión de Miguel (09/10):** un mes sellado se sigue leyendo con la CUENTA VIVA, como hoy.

## Cuerpos vivos de producción (en `supabase/scripts/facturacion-una-fuente/vivo/`)

| Función | md5 de `pg_get_functiondef` | ACL |
|---|---|---|
| `crm.facturacion_diaria_fn` | `4b11e1da336f2f296c81f064ce30e35b` | `{postgres=X/postgres,authenticated=X/postgres}` |
| `private.capital_episodios` | `2ed07da302e9a1b881a4962724234dd7` | `{postgres=X/postgres}` |

`private.vendedor_ids_visibles`, `private.es_lector_global` y `private.rol_crm` se incluyen solo para lectura.
`capital_episodios` ya lleva el analista efectivo (regla de bajas, `20261009200000`).

Léelos enteros. `facturacion_diaria_fn` tiene estas CTE:
- `quien` / `ambito`: la verja (`ok`, `es_global`, `subarbol`);
- `mes`: la normalización de `p_mes`;
- `episodios`: el núcleo, llamado una vez;
- `eventos` / `tramos`: el supervisor DE ENTONCES por eventos `jerarquia_actualizada`; sin tramo, o con tramo NULL,
  manda el de hoy.

Termina con el recorte del supervisor, los nombres, el `group by` y el `order by`.

## Diseño: tres piezas, cada regla en un solo sitio

1. **`private.facturacion_operaciones(p_desde timestamptz, p_hasta timestamptz)`** — TODAS las operaciones `medida =
   'stock'` de `private.capital_episodios(p_desde, p_hasta, true, '{}')`, **una fila por operación**, sin ámbito.
   - Lleva las CTE `eventos`/`tramos` y el `left join crm.equipo` de la caída al supervisor de hoy, movidos tal cual.
   - Columnas:
     - `operacion_id` = `coalesce(contrato_id, cierre_externo_id)`, único por fila: compruébalo en el oráculo;
     - `dia` = `(fecha at time zone 'America/Lima')::date`;
     - `fecha`, `tipo`, `moneda`, `monto`;
     - `analista_id` y `supervisor_id` (de entonces, con la caída al de hoy);
     - `contrato_id`, `cierre_externo_id`, `cliente_id`, `lead_id`, `registrado_por`;
     - `categoria`, `estado`, `anulado`, `fecha_vencimiento`.
2. **`private.facturacion_operaciones_visibles(p_desde timestamptz, p_hasta timestamptz)`** — las mismas columnas,
   recortadas a quien pregunta (`auth.uid()`).
   - Mueve aquí `quien`/`ambito` y el recorte final TAL CUAL.
   - Si `ok` es falso, no llama al núcleo: el filtro `a.ok` va sobre `ambito`, antes del `lateral`.
   - La regla de quién ve qué queda en un solo sitio. La puerta de la lista (3B) leerá de aquí y verá exactamente las
     operaciones que forman su cifra.
3. **`crm.facturacion_diaria_fn(p_mes date)`** — misma firma, columnas, tipos y `order by`.
   - Conserva `mes`.
   - Lee `facturacion_operaciones_visibles` una vez para el mes, con las mismas medianoches de Lima que hoy.
   - Une los nombres (`'Sin analista'`, `'Sin supervisor'`) y agrupa con `count(*)::bigint` y `sum(monto)`.

**Contrato de las dos piezas `private`**
- LANGUAGE sql, STABLE, **SECURITY INVOKER**. Mismo precedente que `private.actividades_de_lead_core` y
  `private.tareas_pendientes_core`. Solo las llama la puerta DEFINER de `postgres`, así que leen como hoy.
- `set search_path to ''` y nombres calificados.
- Dueño `postgres`. `EXECUTE` revocado a `public`, `anon`, `authenticated` y `service_role`.
- `COMMENT ON` que diga que son la ÚNICA fuente de la cifra y de la lista.

**Rendimiento.** Cada pieza se llama UNA vez en un FROM. No anides funciones SQL por fila: en Postgres 17 se
re-planifican en cada fila (el 09/10 eso llevó un cálculo de 15 a 171 ms). Los empates del `order by` (dia, moneda,
capital desc) hoy no tienen orden definido. No añadas desempate: el oráculo compara multiconjuntos.

## Entregables

1. **`supabase/migrations/20261009224000_crm_facturacion_una_fuente.sql`** (patrón:
   `20261009200000_crm_baja_analista_heredero.sql`).
   - `begin … commit`, idempotente y fail-closed.
   - **PREFLIGHT** con las huellas vivas.
   - **POSTFLIGHT** con las huellas nuevas `'PENDIENTE_MEDIR_EN_BANCO'` (las mido yo en el banco), más dueño, ACL,
     `prosecdef`, volatilidad y `search_path` de las tres. Las guardas se escriben con `is not true`.
   - **ORÁCULO en la misma transacción.** Antes del reemplazo, guarda en tablas temporales la salida COMPLETA de
     `crm.facturacion_diaria_fn(mes)` para cada mes desde el primero con operaciones hasta el mes en curso, y para cada
     identidad:
     - una Gerencia activa;
     - un Directorio (`private.es_lector_global()`), si existe;
     - CADA supervisor activo;
     - un vendedor activo (vacío);
     - sin sesión (vacío).

     La identidad se fija con `set_config('request.jwt.claims', …, true)` y `set_config('request.jwt.claim.sub', …, true)`,
     como `supabase/scripts/test-facturacion.sql`. Se limpia al terminar.

     Después del reemplazo se repite y se exige igualdad exacta: `EXCEPT ALL` en los dos sentidos, todas las columnas.
     Además:
     - por cada mes, el `group by` directo de `facturacion_operaciones` (día, tipo, moneda, analista y supervisor con su
       `count` y `sum`) es igual a la salida de Gerencia sin nombres;
     - `operacion_id` no se repite.

     Si algo difiere, se aborta todo. `raise notice` con meses, identidades, filas comparadas y milisegundos.
2. **`supabase/scripts/facturacion-una-fuente/`**
   - **`generar-cuerpos.py`**: arma los cuerpos nuevos MOVIENDO el texto vivo de `vivo/` (CTE copiadas al byte, no
     reescritas). Con `--verificar`, comprueba que la migración y la reversa contienen exactamente lo generado.
   - **`reversa.sql`**: restaura `facturacion_diaria_fn` al byte (huella viva y ACL) y borra las dos piezas
     `private`. Idempotente.
   - **`ensayo-sintetico.sql`** (banco, termina en ROLLBACK):
     - aplica la migración;
     - corre los MUTANTES sobre el núcleo; cada uno tiene que hacer fallar la comparación contra la foto de antes:
       - sin cooperativas;
       - sin la caída al supervisor de hoy;
       - `dia` en UTC en vez de Lima;
       - el recorte del supervisor sin «sus ventas propias»;
     - comprueba la reversa.
   - **`ensayo-produccion.sql`**: la migración terminada en `raise` para deshacerse; la corre Miguel con `!`.
   - **`medir.sql`** (patrón `scripts/baja-analista-heredero/medir-produccion.sql`): cifra de octubre y de septiembre
     antes y después, en la misma transacción. Falla si pasa de la línea base +20 % y termina en `raise`.
   - **`LEEME.md`**.
3. **`supabase/migrations/MIGRACIONES.md`**: una entrada AL FINAL, «en banco, sin aplicar».
4. **Gate** (`supabase/scripts/test-rls.mjs`, `testFacturacionDiaria`).
   - Sus bloques A–K tienen que seguir pasando sin cambios.
   - Añade un check fuera de banda (patrón `contarFueraDeBanda`) del contrato de las dos piezas `private`:
     - INVOKER, STABLE, `search_path=""` y dueño `postgres`;
     - sin `EXECUTE` para `anon`, `authenticated` ni `service_role`.
   - `supabase/scripts/test-facturacion.sql` debe seguir pasando sus 12 oráculos SIN cambios. Si alguno depende de
     detalles internos, explícalo en vez de cambiarlo.
