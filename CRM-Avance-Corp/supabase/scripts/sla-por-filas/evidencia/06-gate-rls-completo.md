# Gate RLS completo del paso 3a «SLA por filas», ANTES y DESPUÉS

- **Cuándo:** 17/10/2026, de 14:35 a 15:00 (hora de Lima, tomada con `date`).
- **Dónde:** la copia aislada `~/dev/avancecorp-crm-foto-sla`, rama `crm/sla-por-filas-20261017`, sin commit.
- **Qué se probó:** las tres migraciones del paso 3a, que **no están aplicadas en producción**:
  - M1 `20261017054425`
  - M2 `20261017054426`
  - M3 `20261017054427`
- **Base de pruebas:** un stack local de Supabase **propio**. No se tocó producción en ningún momento: ni `--linked`, ni
  `db push`, ni `apply_migration`, ni el MCP.

## En una línea

**PASS.** El gate deja los mismos 15 fallos ajenos antes y después. Solo cambian 8 aserciones: las que necesitan M1 y M3, que
antes se saltan y después pasan. `testSlaPorFilas` da 28/28 ANTES y 36/36 DESPUÉS.

## 1. Cambio en `test-rls.mjs` (soy su único escritor en esta tarea)

El cambio está en `testSlaPorFilas`, bloque D, y atiende la revisión de Codex. Ahora:

- **Recorre cada cola entera.** La cola v3 de vend1, sup1 y gerencia se lee por cursor, 200 por página, hasta `hay_mas=false`.
  En cada una se exige:
  - que lo recorrido sea `total_items`;
  - que ninguna clave se repita;
  - que el total coincida con el de la primera lectura.

  Con esto los fixtures nunca pueden quedar fuera de la página examinada.
- **No acepta conjuntos vacíos.** Las colas de vend1 y de sup1 deben traer al menos un ítem de lead.
- **Control positivo de la fuga.** La cola entera de gerencia sí trae leads del equipo de sup2. Si sup1 los recibiera, se
  verían.
- **Control positivo de `estado_sla_leads_v2_fn`.** Se le pasan a vend1 sus leads (juan, maría y los de su cola) junto con el de
  vend3. Debe devolver al menos una fila, solo filas suyas, todas las de su cola y ninguna de vend3.
- Las comprobaciones de ámbito de siempre (todo lead de vend1 es suyo; sup1 no recibe nada de sup2) ahora corren sobre la cola
  **entera**.

En total son **7 aserciones nuevas** y 2 reescritas. Todo lo demás del bloque queda igual.

En este banco, cada cola cabía en una sola página:

| Quién | Ítems | Leads |
|---|---|---|
| vend1 | 15 | 13 |
| sup1 | 22 | 20 |
| gerencia | 35 | 4 del equipo de sup2 (el control positivo) |

Por eso el bucle del cursor terminó en la primera vuelta. La paginación con más de una página ya la cubre
`testColaAccionV3`, bloque E (límites 1 y 2).

## 2. Cómo se montó el stack

| Qué | Valor |
|---|---|
| Carpeta (fuera del repo) | `~/dev/gate-sla-por-filas/`: `stack/supabase/config.toml`, `logs/`, volcados y guiones |
| `project_id` | `avancecorp-gate-sla-filas` |
| Puertos | API 57521 · base 57522 · inbucket 57524. Studio, realtime, edge y analytics apagados. Antes se comprobó con `docker ps` y `lsof` que estaban libres |
| CLI e imagen | Supabase CLI 2.117.0 · `public.ecr.aws/supabase/postgres:17.6.1.167` (producción usa 17.6.1.105; las dos son Postgres 17.6) |
| Esquema | Volcado de producción del **17/10/2026 a las 10:52 Lima**: `esquema-prod-20261017.sql`, sha256 `ff034b6d…`, esquemas public, crm, private y audit, solo estructura. Lo copié de `~/dev/banco-reemplazar-inversion/` (solo lectura; su stack no se tocó) |
| Configuración | `cargar-config-stack.sql`: 21 tablas de configuración de producción del 17/10, sin personas. Además, `storage-stack.sql` |
| Montaje | `scripts/montar-stack.sh`. Carga: **0 errores** |

**Por qué el volcado del 17/10 y no el del 15/10 más la opt1.** El volcado del 15/10 está detrás de producción: después de él se
aplicaron unas 9 migraciones, entre ellas la opt1, #315, #317 y #318. `main` también avanzó hasta `a5a771da`.

El del 17/10 ya es la foto de producción con todo eso dentro. En él, `verificar.sql` dio directamente la serie esperada, así que
no hizo falta reproducir ninguna migración a mano.

**Gate de una pasada.** Lo corre `scripts/gate.sh`, una copia de `banco/gate-rls-una-pasada.sh` con estos cambios:
- `--workdir` apunta al stack propio;
- se niega si la API no es `127.0.0.1:57521` o la base no es `127.0.0.1:57522`;
- la limpieza corre con `session_replication_role = replica`, como en `reemplazar-inversion/banco/gate-rls-stack.sh`; si no, la
  segunda corrida no puede limpiar el domicilio legal;
- las credenciales salen de `supabase status -o env` dentro de `eval`;
- la contraseña de los usuarios de prueba es de usar y tirar.

## 3. Acreditación del banco (antes de fiarse)

1. **`verificar.sql` ANTES** (`evidencia/verificar-0-antes.txt`):
   - `SERIE=ANTES · familia SLA=62 · 1adaf6c5708637fd916705cc090a4218 (la esperada)`;
   - productor, helper y operativos: IGUALES;
   - ACL de las piezas privadas: ninguna;
   - los 3 guardianes del SLA: OK.
2. **Las propias migraciones lo acreditan.** M1, M2 y M3 exigen las huellas vivas exactas de todo lo que tocan y necesitan, y las
   tres pasaron su comprobación previa con COMMIT.
3. **Paridad de catálogo después de M3.** Se volcó el banco con `supabase db dump --local --schema public,crm,private,audit
   --keep-comments` y se comparó con el volcado de producción (`evidencia/diff-volcado-prod-vs-banco-m3.txt`). Solo difieren
   dos grupos de objetos:
   - **Las piezas del 3a:**
     - las 2 funciones nuevas, con dueño, ACL y comentario;
     - la autorizada;
     - `avisos_sla_resumen_v2_fn` y `cola_accion_v3_fn`, con su comentario;
     - `assert_sla_nucleo`, `assert_sla_avisos` y `assert_cola_v3`.
   - **El texto de 3 CHECK escritos con BETWEEN:** `alertas_reconocimientos_miembros_check`, `empresas_monedas_check` y
     `producto_condiciones_capital_check`. Postgres quita paréntesis al recargarlos y la regla es la misma. Es un artefacto
     conocido (`fase2/banco/LEEME.md` §6), está desde la carga y es igual en todas las corridas.
4. **Control A/A en el mismo banco.** Dos corridas seguidas sin cambiar nada dieron 0 diferencias, aserción por aserción, tanto
   ANTES (`antes-2` frente a `antes-3`) como DESPUÉS (`despues-1` frente a `despues-2`).

   La primera corrida sobre el banco limpio (`antes-1`) sí se aparta del resto. Se debe al **residuo** que deja cada corrida (la
   limpieza no borra perfiles ni contratos):
   - 1 ✗ más desde la segunda corrida: «Supervisor recibe una fila bancaria completa»;
   - 2 ✓ más que solo existen con ese residuo: «la vuelta restaura al analista original» y «la identidad con perfil…».

   Por eso **ANTES y DESPUÉS se comparan entre corridas «con residuo»**: `antes-3` frente a `despues-1`.

## 4. Cifras

| Corrida | Hora (Lima) | M1–M3 | Gate (su propio resumen) | `testSlaPorFilas` |
|---|---|---|---|---|
| antes-1 (banco limpio) | 14:49:44–14:50:30 | no | ✗ 14 de 3820 | ✓ 28 · ✗ 0 · A, B y F saltados (falta M1) |
| antes-2 | 14:50:53–14:51:41 | no | ✗ 15 de 3822 | ✓ 28 · ✗ 0 |
| antes-3 | 14:51:56–14:52:41 | no | ✗ 15 de 3822 | ✓ 28 · ✗ 0 |
| *M1 → M2 → M3* | 14:52:48 | aplicadas | — | — |
| despues-1 (`CRM_RLS_EXIGE_SLA_FILAS=1`) | 14:53:04–14:53:47 | sí | ✗ 15 de 3830 | **✓ 36 · ✗ 0** |
| despues-2 (`CRM_RLS_EXIGE_SLA_FILAS=1`) | 14:54:16–14:54:57 | sí | ✗ 15 de 3830 | **✓ 36 · ✗ 0** |

Al contar líneas salen 2 ✓ más que en el resumen del gate (3809 frente a 3807, y 3817 frente a 3815). Son las dos líneas
«precondición» del arranque, que el gate no cuenta como aserciones.

**Aplicación** (`evidencia/aplicar-serie.out`), con `psql -f` como `postgres` (no superusuario). Cada migración terminó en
`COMMIT`, y `verificar.sql` detrás de cada una dio la serie y la familia esperadas:

| Tras | Serie y familia SLA | Gate de la serie completa |
|---|---|---|
| M1 | `SERIE=M1 · 64 · 1a632cfd…` (la esperada) | — |
| M2 | `SERIE=M2 · 64 · 5e4e27c4…` (la esperada) | — |
| M3 | `SERIE=M3 · 64 · f9ea9038…` (la esperada) | **OK** |

En las tres se mantuvo lo mismo:
- productor, helper y operativos: IGUALES;
- ACL efectiva y ACL guardada de las piezas privadas: ninguna;
- censo analítico: `48 · 083aeae5…`, igual antes y después;
- los 3 guardianes del SLA: OK;
- los 4 guardianes ajenos, con **el mismo texto** que en ANTES:
  - `assert_gestion_diaria`;
  - `assert_analitica_leads_citas`;
  - `assert_analista_vigencia`;
  - `assert_f7_piezas_cerradas`.

## 5. Diferencias, aserción por aserción (`scripts/comparar.py`)

`comparar.py` normaliza los uuid, los instantes, los tokens hexadecimales de 10 caracteres y las cifras.

**`antes-3` frente a `despues-1`** (`evidencia/diff-antes-3-vs-despues-1.txt`):
- ✗: 0 solo en ANTES y 0 solo en DESPUÉS. **Son los mismos 15.**
- ✓: 0 se pierden y **8 aparecen**. Son exactamente las aserciones A, B y F, que ANTES se saltan por diseño porque falta M1:
  - ACL efectiva;
  - ACL guardada;
  - forma;
  - «solo el ámbito lee `auth.`»;
  - `assert_sla_nucleo` OK;
  - `assert_sla_avisos` OK;
  - `assert_cola_v3` OK;
  - «GATE: la serie completa está en M3».

No hay ninguna otra diferencia, así que no queda nada sin explicar.

## 6. Los 15 fallos preexistentes (iguales antes y después; ninguno es del SLA)

Lista en `evidencia/_rojos-despues-1.txt`. Los mismos 15 salen también en el gate del banco de «reemplazar inversión», que está
montado sobre el mismo volcado con una rama al día con `main`. Por tanto **no se deben a que esta rama esté detrás de `main`**.

| Fallos | Cuántos | Causa probable |
|---|---|---|
| `potencial…` | 4 | La configuración de producción trae encendida la bandera `potencial_lead`, y el bloque la espera apagada |
| `facturacion_diaria_fn` | 4 | Huellas y llamadores de facturación |
| `listar_operaciones_facturacion_fn` | 1 | Huellas de facturación |
| `R2` (hito y tarjeta de rentabilidad) | 3 | — |
| `D-9` (sello de exenciones) | 1 | — |
| `F2` (claves del testigo) | 1 | — |
| «Supervisor recibe una fila bancaria completa» | 1 | Solo aparece desde la segunda corrida: es residuo |

## 7. Comprobaciones: PASS / FAIL / NOT RUN

| Comprobación | Resultado |
|---|---|
| `node --check supabase/scripts/test-rls.mjs` | **PASS** |
| `npm run test:rls:preflight`, con los valores ficticios del workflow de CI | **PASS** (`evidencia/preflight.log`) |
| oxlint sobre `test-rls.mjs` | **PASS** en el bloque tocado (0 avisos entre las líneas 8820 y 8999). Los avisos de otras líneas ya existían |
| Montaje del stack y carga del volcado | **PASS** (0 errores) |
| `verificar.sql` ANTES, M1, M2 y M3 | **PASS** (serie y familia esperadas en las cuatro) |
| M1, M2 y M3 con `psql -f` como `postgres` | **PASS** (COMMIT; guardianes dentro de cada transacción) |
| Gate ANTES (`antes-1`/`antes-2`/`antes-3`) | FAIL global, por los 14–15 fallos ajenos · `testSlaPorFilas` **PASS 28/28** |
| Gate DESPUÉS (`despues-1`/`despues-2`, `CRM_RLS_EXIGE_SLA_FILAS=1`) | FAIL global, por los mismos 15 ajenos · `testSlaPorFilas` **PASS 36/36**, incluido «GATE … M3» |
| Diferencias ANTES frente a DESPUÉS | **PASS** (0 ✗ nuevos, 0 ✓ perdidos, +8 esperadas) |
| Paridad de catálogo con producción tras M3 | **PASS** (solo las piezas del 3a y 3 CHECK de texto) |
| `registrar-indice.sql`, reversas, advisors y carga concurrente | **NOT RUN** (fuera de este encargo) |
| Paginación con más de una página en `testSlaPorFilas` | **NOT RUN** en este banco (todas las colas caben en una). La cubre `testColaAccionV3`, bloque E |

## 8. Hallazgos y lo que queda abierto

1. **El censo analítico de producción ya no es el del LEEME del kit.** En el volcado de producción del 17/10 da
   `48 · 083aeae525423db53fbb0fcd81748471`. El LEEME y su ensayo, hechos sobre el banco del 15/10, dicen `45 · ff12620b…`. La
   diferencia viene de #317 y #318. La serie lo deja igual antes y después, que es lo que importa. Aun así, quien corra
   `verificar.sql` en producción verá 48 · 083aeae5: conviene anotarlo en el LEEME (lo lleva el otro agente; no lo toqué).
2. **La rama está detrás de `main`.** Sale de `e4ded65d`, y `main` y `avancecorp/main` ya van en `a5a771da` (#317–#319).
   - La familia SLA no cambió: sigue en 62 · 1adaf6c5 en el volcado del 17/10, y M1–M3 aplican limpias sobre ese esquema.
   - Antes de la PR hay que traer `main`. Su `test-rls.mjs` solo añade 13 líneas de despacho de línea de comandos al principio
     del archivo, sin choque con este bloque.
3. **El volcado es de las 10:52 del 17/10.** Lo que se haya aplicado en producción después no está en el banco. Antes del «!», el
   primer `verificar.sql` en producción tiene que dar `SERIE=ANTES · 62 · 1adaf6c5…`.
4. **Forma de envío de las migraciones.** Aquí se aplicaron con `psql -f`, que manda varios mensajes. En producción se aplican con
   `db query --file`, que manda un solo mensaje. No se espera ninguna diferencia: las comprobaciones de las tres migraciones no
   leen el reloj del mensaje (comprobado con grep). El único `statement_timestamp()` está dentro del cuerpo de la función nueva
   `_filas` (M1, línea 167): es el reloj de la ventana cuando se ejecuta, igual que en la autorizada de siempre, y no forma parte
   de la lógica de la migración.
5. **La serie no se registró en `supabase_migrations.schema_migrations` del banco.** `registrar-indice.sql` no se corrió.

## 9. Qué dejé y dónde

**En el repositorio**, en la copia aislada y sin commit:
- `supabase/scripts/test-rls.mjs`: el bloque D de `testSlaPorFilas`, más 2 líneas del comentario de cabecera.
- `supabase/scripts/foto-sla/fase3/gate-rls-3a/`, que contiene:
  - este INFORME;
  - `scripts/`: `montar-stack.sh`, `gate.sh`, `aplicar-serie.sh` y `comparar.py`. Leen `GATE_DIR`, que por defecto es
    `~/dev/gate-sla-por-filas`;
  - `evidencia/`: los diffs, los `verificar-*`, las salidas de cada corrida y el preflight.

**Fuera del repositorio**, en `~/dev/gate-sla-por-filas/`:
- el stack;
- los volcados (el de producción y `volcado-banco-tras-m3.sql`);
- la configuración;
- `logs/`, con los registros completos `_rls-*.log` y `_seed-*.log` (sin secretos).

Borré `logs/supabase-start.log`, que yo mismo había creado, porque trae las llaves locales que imprime `supabase start`.

**Docker:**
- Stack parado con `supabase stop --workdir ~/dev/gate-sla-por-filas/stack` a las 14:59. No queda ningún contenedor ni red
  `*gate-sla-filas*`.
- Quedan los volúmenes `supabase_db_avancecorp-gate-sla-filas` y `supabase_storage_avancecorp-gate-sla-filas` (la copia de
  respaldo de `supabase stop`).
- Para retirarlos, cuando se decida: `supabase stop --workdir ~/dev/gate-sla-por-filas/stack --no-backup` con el stack
  arrancado, o `docker volume rm` de esos dos nombres.
- Las sondas de memoria `gate-sla-filas-sonda` y `gate-sla-filas-sonda2` corrieron con `--rm` y ya no existen.

No se tocó ningún contenedor, volumen ni stack ajeno, tampoco `foto-sla-f2-*` ni `reemplazo-inv*`.
