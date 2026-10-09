# Facturación 3A: una fuente para la cifra y la lista

**Estado: APLICADA en producción y registrada el 09/10/2026 (noche)** (md5 del texto `4665b9505efa07c9d8bf9c5f0a4d5695`).
- Huellas medidas en el banco Docker a paridad con producción. Ciclo, oráculos, gate y mutantes en verde.
- Revisada por auditor-rls y Codex: ninguna encontró P0 ni P1 (ver «Verificación» y «Revisión»).
- No cambia la pantalla. La puerta de la lista es la 3B.

## Qué cambia

- **`private.facturacion_operaciones(p_desde, p_hasta)`** — **SIN VERJA**. Devuelve TODAS las operaciones de stock de la
  empresa (contratos y cooperativas de `private.capital_episodios`), una fila por operación, con el día de Lima y el
  supervisor DE ENTONCES. Cuando no hay tramo, o el tramo dice NULL, cae al supervisor de hoy.
  - Su ÚNICO llamador es `_visibles`. Ninguna puerta la llama directo, y el gate lo censa.
- **`private.facturacion_operaciones_visibles(p_desde, p_hasta)`** — la verja y el recorte de quien pregunta, movidos al
  byte desde la puerta. Si `ok` es falso, no llama al núcleo.
  - Devuelve ids crudos (cliente, lead, `registrado_por`). La puerta de la lista (3B) DEBE aplicar la capa de datos:
    cliente de otro equipo sin nombre ni N.º, y DNI nunca.
- **`crm.facturacion_diaria_fn(p_mes)`** — añade nombres y agrupa sobre `_visibles`.
  - Conserva firma, columnas, tipos, DEFINER, ACL, comentario y `order by`. Los empates siguen sin desempate.

Un mes sellado sigue leyéndose con la **cuenta viva** (decisión de Miguel, 09/10/2026).

Las dos piezas `private` son SQL, STABLE e INVOKER, con dueño postgres, `search_path` vacío y ACL `{postgres=X/postgres}`.
Cada pieza invoca una vez a la siguiente en un FROM, sin SQL anidado por fila.

| Función | Huella antes | Huella después |
|---|---|---|
| `crm.facturacion_diaria_fn(date)` | `4b11e1da336f2f296c81f064ce30e35b` | `3753d03552e26eb7e61117a3baab6f78` |
| `private.facturacion_operaciones(timestamptz,timestamptz)` | — | `5d63cb537b0b286ad47feb7f5b26d161` |
| `private.facturacion_operaciones_visibles(timestamptz,timestamptz)` | — | `17c2ca27996adad88f685896915953e3` |
| `private.capital_episodios(...)` (no cambia) | `2ed07da302e9a1b881a4962724234dd7` | igual |

## Orden con otras migraciones

- **Precondición: la fase 2 (`20261009223000`) aplicada y registrada.**
  - La migración exige que esté aplicada, por la huella de su trigger.
  - El ensayo de producción exige además que esté registrada.
  - El motivo: su registrador y su reversa fijan la huella VIEJA de la puerta.
- **Reversas en orden inverso:**
  1. la de cualquier consumidor de las piezas (la 3B): la reversa de la 3A se niega si alguna función las usa;
  2. la de la 3A;
  3. la de la fase 2, si hiciera falta.

  Si `capital_episodios` cambia después de la 3A, la reversa también se niega hasta deshacer ese cambio. Falla cerrado
  a propósito.

## Archivos

- **`../../migrations/20261009224000_crm_facturacion_una_fuente.sql`**: una transacción REPEATABLE READ con
  `statement_timeout` de 120 s.
  - Pasos: PREFLIGHT, oráculo de antes, instalación, oráculo de después y POSTFLIGHT.
  - Es idempotente y se niega ante estados parciales.
- **`generar-cuerpos.py`**: verifica los cinco `vivo/` por md5.
  - Copia al byte `quien`/`ambito`, `mes`, `eventos`/`tramos` y los joins de atribución.
  - Su única sustitución cambia `coalesce(t.supervisor_id, eq.supervisor_id)` por la columna `ep.supervisor_id`.
  - Sincroniza la reversa y el DO copiado en los tres ensayos. `--verificar` no escribe.
- **`generar-registrar.py`**: escribe `registrar.sql` con el texto EXACTO de la migración. `--verificar` no escribe.
- **`reversa.sql`**: restaura la puerta al byte (huella, ACL y comentario) y borra las dos piezas sin CASCADE.
  - Es idempotente.
  - Se niega si otra función usa las piezas.
- **`ensayo-sintetico.sql`**: solo banco vacío. Hace la siembra propia, aplica la migración y corre los cuatro
  mutantes, la verja con una bomba y la reversa. Termina en ROLLBACK.
- **`ensayo-produccion.sql`** y **`medir.sql`**: para Miguel con `!`. Terminan en `RAISE` y lo deshacen todo.
- **`registrar.sql`**: se corre después de aplicar. Es idempotente, y se niega si la versión ya está registrada con otro
  texto.

## El oráculo de la migración

- **Identidades:** una Gerencia activa, Directorio (si `private.es_lector_global()` lo reconoce), CADA supervisor
  activo, un vendedor activo y sin sesión.
- **Meses:** los que tienen operaciones, más el mes en curso de Lima (el aviso imprime el primero y el último
  comparados).
- **Comparación:** guarda todas las columnas antes y después del reemplazo y compara multiconjuntos con `EXCEPT ALL` en
  los dos sentidos.
- **Además:** el agregado directo del núcleo es igual a Gerencia, y `operacion_id` no es nulo ni se repite (ni entre
  meses).
- **Base vacía:** la rechaza a propósito (sin Gerencia, sin vendedor o sin operaciones). Un oráculo que «pasa» sin datos
  no prueba nada, y los bancos se montan desde el volcado de producción, no repitiendo migraciones.

## Banco

1. **Banco con datos** (stack completo; esquema y configuración de producción, semilla del gate):
   - aplicar → reaplicar → reversa → reversa → aplicar;
   - `test-facturacion.sql`, `registrar.sql` y el gate RLS completo.
2. **Banco VACÍO** (Postgres de Supabase con el volcado de solo esquema, la configuración de producción sin personas, la
   fase 2 y la fila del producto legado `HISTORICO-SIN-CATALOGO`, que exige el alta de contratos): correr
   `ensayo-sintetico.sql` como postgres.
   - Corre en READ COMMITTED porque su siembra da de alta personas y el trigger de identidad unificada lo exige. La
     migración real no da de alta a nadie.
   - Solo el SQLSTATE propio del comparador (`P3A01`) cuenta como mutante cazado.

## Producción (Miguel, con `!`, desde la carpeta principal y con rutas absolutas a este worktree)

`db query --linked` no muestra los NOTICE: el ensayo y la medición llevan la evidencia en el mensaje del error final.
El error final **«… PASS … SE DESHACE TODO»** es el resultado correcto; cualquier otro error es un fallo.

1. **`ensayo-produccion.sql`**: la migración entera con su oráculo, deshecha.
   - Exige la fase 2 registrada y al menos un supervisor con filas.
   - El mensaje trae meses, identidades, filas, operaciones, huellas y milisegundos.
2. **`medir.sql`**: septiembre y octubre antes y después, en la misma transacción. Toma la mediana de 7 muestras tras
   calentar y falla si se pasa de la línea base +20 %.
3. **La migración.**
4. **`registrar.sql`**: muestra la versión y el md5 del texto.

## Verificación (09/10/2026, PRIMARY)

- **Generadores:** `generar-cuerpos.py --verificar` y `generar-registrar.py --verificar` dan PASS.
- **Banco con datos — ciclo completo:**
  - aplicar: «ORÁCULO PASS: 4 meses (2026-01 a 2026-10), 7 identidades (1 Directorio), 19 filas antes / 19 después,
    46 operaciones únicas; ~100 ms»;
  - reaplicar: «ya aplicada»;
  - reversa PASS, y repetida «ya completa»;
  - aplicar de nuevo: PASS.
- **`test-facturacion.sql`:** LOS 12 ORÁCULOS PASAN, sin cambios en el archivo.
- **Guardas negativas:**
  - una reversa con un consumidor falso de `_visibles` se niega;
  - el ensayo de producción sin la fase 2 registrada se niega;
  - el registrador con otro texto ya registrado se niega;
  - el censo detecta una puerta falsa que llama al núcleo directo (con espacio antes del paréntesis).
- **Ensayo de producción en banco:** «ENSAYO 3A PASS: 4 meses, 7 identidades (3 supervisores, 1 con filas; 1
  Directorio), 19 filas = 19, 46 operaciones; huellas 3753d035… · 5d63cb53… · 17c2ca27…; 95 ms».
- **Registrador:** registra la versión con el md5 del texto igual al del archivo, y repetirlo no cambia nada.
- **Ensayo sintético** (banco vacío):
  - oráculo PASS (2 meses, 6 identidades, 21 = 21 filas);
  - CUATRO MUTANTES CAZADOS (sin cooperativas · sin caída al supervisor de hoy · día UTC · sin ventas propias del
    supervisor);
  - verja sin llamada;
  - reversa exacta y ROLLBACK.
- **Gate RLS completo:** los mismos 9 rojos de fondo que antes de la 3A (diff vacío). Los checks de Facturación están en
  verde, incluido el bloque L: contrato y ACL exacta de las dos piezas y de la puerta, censo de llamadores y cadena
  existente.
- **Medición en banco** (meses con datos en el banco): 2026-01 1,49 → 1,23 ms · 2026-10 2,11 → 1,62 ms. PASS.
- **Producción (Miguel con `!`, 09/10/2026 noche):**
  - ensayo: «ENSAYO 3A PASS: 13 meses (2025-09 a 2026-10), 7 identidades (4 supervisores, los 4 con filas; 0
    Directorio), 1454 filas antes = 1454 después, 820 operaciones únicas; huellas 3753d035… · 5d63cb53… · 17c2ca27…;
    1886 ms». No hay un Directorio activo en producción; su camino es el de Gerencia, y en el banco dio lo mismo;
  - medición: septiembre 22,59 → 20,66 ms y octubre 11,20 → 10,35 ms. PASS;
  - migración aplicada sin errores y `registrar.sql` con md5 del texto `4665b9505efa07c9d8bf9c5f0a4d5695`.

## Revisión (09/10/2026)

- **auditor-rls:** CHANGES_REQUESTED, sin P0 ni P1. La verja es idéntica por rol y no hay vías nuevas de fuga.
- **Codex:** APPROVE_WITH_CHANGES, sin P0 ni P1. Equivalencia estructural confirmada.
- **Aceptado:**
  - la precondición y el orden con la fase 2;
  - el comentario del núcleo «sin verja» y el censo de llamadores;
  - la ACL exacta y el contrato de la puerta en el gate;
  - la guarda de consumidores en la reversa;
  - supervisores con filas en el ensayo;
  - `statement_timeout`;
  - el rango real de meses en el aviso;
  - la cabecera con la línea de reversa, y el ledger de la fase 2 y de la 3A;
  - el registrador que no pisa otro texto.
- **Rechazado con evidencia:**
  - **«El SQLSTATE de los mutantes no es exclusivo»:** el comparador del ensayo lanza `P3A01` y el manejador solo
    atrapa ese código. A Codex no se le transcribió el ensayo.
  - **«Aflojar la huella de `capital_episodios` en la reversa»:** se mantiene fallar cerrado y revertir en orden
    inverso.
- **Pendiente para la 3B:**
  - la capa de datos en la puerta de la lista;
  - añadir esa puerta a la lista cerrada del censo;
  - probar contra un resultado independiente las columnas nuevas (`cliente_id`, `lead_id`, `registrado_por`);
  - que su reversa vaya antes que la de la 3A;
  - el hueco previo de «supervisor dado de baja recibe vacío» en el gate.
