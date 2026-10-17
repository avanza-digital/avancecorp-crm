# Verificación independiente del paso 3a «SLA por filas» · INFORME

17/10/2026, de 01:44 a 10:54 (hora de Lima, tomada con `date`; entre las 01:51 y las 09:52 el equipo estuvo parado).

- **Quién:** verificador independiente. No escribí ni corregí migraciones. No toqué producción (ni para leer), ni git, ni
  Codex, ni otros agentes.
- **Dónde:** banco Docker `foto-sla-f2-db`: PostgreSQL 17.6, esquema de producción con la opt1 y 3.869 leads sintéticos.
- **Con qué usuario:**
  - Migraciones, `verificar.sql` y reversas: **postgres** (`psql -f`, igual que `db query --linked --file`).
  - Arnés: supabase_admin. Cambia de rol en cada llamada: `authenticated` para las puertas y `postgres` para las piezas privadas.
- **Viejo:** mis propias copias `bench.vi_*`, sacadas de `pg_get_functiondef` del banco en `SERIE=ANTES`. Solo cambian el
  nombre y la llamada a la autorizada vieja. Dueño postgres y la misma ACL.
  - Comprobé que la autorizada y los 7 consumidores son iguales a las copias `bench.v0_*` del escritor.
  - Comprobé también que los cuerpos vivos son iguales a `fase3/cuerpos/*.sql` y al «Attached 3» de `encargo-codex-plan.md`
    (la única diferencia es el salto de línea final).

## Veredicto

**FAIL** de la afirmación «mismo jsonb byte a byte **para todos los argumentos**» (cabecera de M3, línea 3; `LEEME.md`).
**PASS en todo lo demás.**

- **13.162 comparaciones propias.** Cada una en una sola sentencia y con el mismo reloj, exigiendo igualdad jsonb **y** de
  texto. Si una versión daba error, se exigía el mismo SQLSTATE, mensaje, detalle y pista.
- **12 diferencias,** todas del mismo caso, construido a propósito: **«pendiente sin acción» con empates de clave NULL** (H1).
  Fuera de ese caso: **0 diferencias.**
- **El caso no aparece con los datos del banco.** Hace falta un actor con rol vendedor que figure como
  `asignado_supervisor_id` de leads sin vendedor. El escritor ya lo había marcado como «no ejercitado».
- **Las piezas cumplen:**
  - permisos efectivos correctos;
  - los 3 guardianes del SLA en OK con la serie;
  - las reversas devuelven las huellas exactas;
  - **el banco quedó IGUAL que producción** (ver el final).

## Comparaciones (nueva = función real con la serie M3 aplicada; vieja = copia `bench.vi_*`)

| Grupo | Qué cubre | Comparaciones | Diferencias | Con error (igual en las dos) |
|---|---|---|---|---|
| A | Envoltorio (`true`/`false`/`NULL`) y `estado_sla_leads_v2_fn` con **subconjuntos aleatorios de 1–200 ids** (semilla 0.4242): 6 por usuario × 35, con ids ajenos, repetidos, inexistentes y de uno solo. Ventanas completas. Los 5 consumidores del envoltorio. | 980 | 0 | 96 |
| B | Avisos de los 35 usuarios en los dos órdenes. 13 identidades raras (sin claims, `role` anon/service/inventado, `sub` inexistente, malformado, solo en el JSON, distinto entre claim y JSON, en mayúsculas, perfil sin equipo, miembro inactivo, claims rotos) × 10 llamadas. | 200 | 0 | 100 |
| C · reloj por página | **1.717 cadenas** de la cola v3 con `p_limite` 7 y 13, las 8 señales × analista NULL y × **cada analista visible**, más uno ajeno, uno inexistente, etapas y etapa + analista. Cursor **cruzado**: la nueva recibe el cursor de la vieja y al revés. Una página por sentencia. | 5.121 | 0 | 239 |
| C · un reloj por cadena | Las **239 cadenas** largas que con un reloj por página morían en «Cursor incompatible» (en las dos versiones por igual; ver H6), repetidas **hasta el final** en una sola sentencia. Son 5.684 páginas; las más largas: gerencia 3 `todas`/7 = 269, coordinador `pendientes`/7 = 238, gerencia 2 `tareas_vencidas`/7 = 179, supervisor 4 `todas`/7 = 151, gerencia 1 `todas`/13 = 145. Todas llegaron a `hay_mas = false`. | 5.684 | 0 | 0 |
| D (ROLLBACK) | Antes y después de cada cambio: cerrar una tarea vencida con `crm.cerrar_tarea`, marcar «No contactar» con `crm.marcar_no_contactar`, **reasignar** 9 → 10 con UPDATE como gerencia y triggers activos, 6 leads «sin acción» y **150 leads inactivos** (subconjuntos de A con 101 inactivos). Batería de 13 llamadas + cadenas cortas. | 674 | 0 | 26 |
| D6 (ROLLBACK) | `observacion` con y sin activación, `legado`. Directorio por el fallback de `perfiles` (sin equipo) y con membresía. | 203 | 0 | 9 |
| E2/E3 | **52 cursores alterados propios** (prioridad 1.5, 1e2, 1e400, -0, 20.0, "20" o null; referencia vacía, mes 13, hora 25, zona inexistente, desplazamiento +25, año 294277, `allballs`, `±infinity`, `epoch`, `now`, 1.000 caracteres; clave en mayúsculas o sin prefijo; versión "2" o 2.0; array, string, null, `{}`…) en 3 bases. Precedencia: límite o señal inválidos, sin sesión, otro usuario y gerencia con cursor de vendedor. | 198 | 0 | 152 |
| E1 (ROLLBACK) | «Pendiente sin acción» con N = 2, 7, 8, 15, 30 y 70 empates NULL; límites 7–200 en los dos órdenes; cola v2; supervisor 4. | 102 | **12** | 0 |
| **Total** | | **13.162** | **12** | 622 |

- **Errores vistos,** todos iguales en las dos versiones: 22023 (Cursor incompatible, Cursor SLA invalido, Entrada SLA
  invalida, límite/filtros, 200 IDs, zona horaria `marte/olimpo`), 22009 (desplazamiento de zona), 22P02 (uuid y json
  inválidos) y 42501 (tres mensajes).
- **El arnés tiene controles positivos** (`03-arnes.sql`, control en ROLLBACK): `clock_timestamp` da distinto,
  `statement_timestamp` da igual, un límite distinto da diferencia, `1.0` contra `1` da diferencia de texto, y el rol efectivo
  es `authenticated`/`postgres`.
- **35 casos anulados por error de mi arnés** (`A2-invalido-arnes`). `estado_sla_leads_fn()` devuelve filas, no jsonb. Los
  rehíce agregando las filas: 35 de 35 iguales.

## Hallazgos

**H1 · P2 · No equivalente: orden de los empates NULL en la cola v3** (lo que hace FALLAR la afirmación byte a byte).

- **Archivo:** `20261017054427_crm_sla_cola_por_filas.sql`.
  - Corte previo de la página de leads: líneas 184–186.
  - Armado de la página: líneas 202–207.
  - Segunda pasada con los clientes: líneas 305–320.
  - La versión vieja ordenaba UNA sola vez todos los candidatos.
- **Cuándo pasa:**
  - Un actor con rol vendedor ve leads con `vendedor_id` NULL y `asignado_supervisor_id` = él. Por ejemplo, alguien que fue
    supervisor y ahora es vendedor, con leads devueltos a su nombre.
  - Con un aviso propio pendiente, `pendientes` = true y `accion_pendiente` = NULL. El ítem queda `[null, {…}]`, con prioridad,
    referencia y clave NULL.
  - Si la página de `pendientes` tiene `hay_mas` = true y contiene 2 o más de esos ítems, **salen en otro orden**.
- **Qué NO cambia** (`salida-11-E1.txt`): el CONJUNTO de ítems, los ítems no nulos y su orden, los totales, el rango y el
  cursor.
- **Reproducción mínima sin arnés:** `12-repro-empates.sql` → `salida-12-repro.txt`. En una sola sentencia:
  - nueva: `55:00373562 56:07b3292f 57:0e1738f1 58:068d7b55 59:03b09730 60:0e9c3bf6`;
  - vieja: `55:0e9c3bf6 56:0e1738f1 57:07b3292f 58:068d7b55 59:03b09730 60:00373562`.
- El orden de los empates no está definido en ninguna de las dos versiones (el ORDER BY no desempata NULL), pero el contrato
  declarado era «byte a byte para todos los argumentos».
- **Siguiente paso, con el «!» de Miguel y solo lectura:** contar en producción si existe la precondición:
  ```sql
  select count(*) from crm.leads l join crm.equipo e on e.perfil_id = l.asignado_supervisor_id
  where l.vendedor_id is null and l.activo and e.rol_crm = 'vendedor';
  ```
- Decidir si se acepta y se documenta, o si se corrige.

**H2 · P2 · Los 3 guardianes del SLA no sellan la autoridad.** Ya pasaba antes de la serie; no lo introduce el 3a.

- **Dónde:**
  - M1 líneas 263–300: `assert_sla_nucleo` solo mira dependencias, propiedades, ACL y `auth.`.
  - M2 líneas 159–169.
  - El único sello es el de la cola (M3 líneas 380–382).
- **Mis mutantes** (ver «Mutantes»): 6 cambios que abren la cartera o cambian el contrato pasan con los 3 guardianes en OK.
- **Ya pasaba antes** (`17-mutante-antes.sql`, `salida-17-mutante-antes.txt`): con la serie revertida, la autorizada vieja con
  `v_global:=true` también deja los 3 guardianes en OK (el vendedor 9 ve 3.869 filas).
- **Lo nuevo:** el 3a concentra la autoridad en `private.sla_operacion_ambito` (INVOKER) y `private.sla_operacion_autorizada_filas`
  (DEFINER), sin huella.
- **Recomendación:** sellar con md5, en `assert_sla_nucleo`, el ámbito, `_filas` y el envoltorio (como ya se hace con la cola), y
  el resumen en `assert_sla_avisos`.

**H3 · P3 · Comentarios desfasados frente al código.** Las migraciones conservan el `COMMENT ON` a propósito («misma …
comentario»: M2 líneas 4–5, M3 líneas 5–6). Con eso:

- **`crm.cola_accion_v3_fn`:** su comentario sigue diciendo «reutiliza private.sla_operacion_autorizada (DEFINER sin grants
  externos)». Tras M3 no la llama: llama a `_filas`.
- **`crm.avisos_sla_resumen_v2_fn`:** dice «Autoridad y reloj de sla_operacion_autorizada».
- **`_filas`** (M1 línea 261): dice que la consumen el resumen y la cola. Eso solo es cierto tras M2 y M3, y el comentario sigue
  ahí cuando se revierten M3 y M2.

**H4 · P3 · `verificar.sql`, líneas 55–62: la línea de ACL solo mira `public`, `anon`, `authenticated` y `service_role`.**

- Con EXECUTE de `_filas` para `crm_metricas_bridge` (mutante V4), esa línea seguiría diciendo «ninguna».
- Sí lo delatan las líneas de los guardianes: `assert_sla_nucleo` FALLA. El postflight de cada migración usa `aclexplode` y
  también lo detectaría.

**H5 · P3 · Documentación:** las cifras de memoria y temporales no coinciden entre la cabecera de M2 (línea 8: «108–121 → 35–43
MiB», «4.814 → 2.373»), `LEEME.md` (líneas 67–70: «104–117 → 35–48») y `RESULTADO-MIGRACIONES.md` («4.836 → 2.380»). Lo mismo con
la cola en M3, línea 9.

**H6 · Ya existía, informativo · Paginar con el tiempo:**

- Con un reloj por página, de las 1.717 cadenas 239 mueren con «Cursor incompatible; reinicia la paginacion» en LAS DOS
  versiones. Mientras se pagina, el estado SLA de algún lead cambia y el contexto del cursor lo detecta.
- Con ítems «sin acción» al final de una página, el cursor sale con `prioridad` null y la página siguiente se rechaza («Cursor
  SLA invalido») en las dos versiones: el ítem 61 queda inalcanzable (`12b-repro-callejon.sql`).
- No lo introduce el 3a.

**H7 · Entorno, P1 conocido (memoria del 20/08):**

- **Lo que pasó:** llamar a una función sin EXECUTE **tumba el backend** en esta imagen (signal 11).
- **Cómo lo vi:** mi prueba de llamada directa a `_filas` como `authenticated` (`08-permisos.sql`, bloque final) provocó a las
  09:56:27 (Lima) «server process … terminated by signal 11» y la recuperación del banco.
- **Qué hice:** no la repetí. El permiso es correcto (`has_function_privilege` = no). Pero en esta imagen «debe fallar» = cae
  el proceso, no un 42501.
- **Efecto en test-rls:** el bloque C de `testSlaPorFilas` (`test-rls.mjs` líneas 8866–8869) llama por PostgREST a
  `.schema('private')`. Ese esquema no está expuesto, así que prueba la configuración de PostgREST y no las grants de la base.
  Las grants las prueba el bloque A.

**Revisión estática sin hallazgos:**

- **Precondiciones ante NULL:**
  - `is distinct from` en todas las huellas.
  - La comprobación «ya aplicada» de M2 y M3 da NULL si falta la pieza, pero el preflight falla después con «no existe».
  - Los guardianes se comprueban con `(… like 'OK: %') is not true`.
  - `v_cuerpo` siempre sale de `into strict`.
  - `es_global` nunca es NULL: si el rol es NULL y no es global, antes salta el 42501.
- **Cada migración y cada reversa es UNA transacción:** si falla, `commit` hace ROLLBACK y no queda nada a medias.
- **`reversa-m1`:** solo borra las 2 funciones nuevas, y se niega si otra función las usa.
- **La pre-lectura del cursor (M3, líneas 134–144) es equivalente:** su error se aplaza al mismo punto; `when others` no atrapa
  cancelaciones.
- **El envoltorio con `false`/NULL** conserva la salida temprana y el orden 42501 → 22023.

## Permisos (`08-permisos.sql`, `salida-08-permisos.txt`, con M3 aplicada)

**Las 3 piezas privadas: nadie fuera del dueño.**

- `has_function_privilege` da **no** para public, anon, authenticated, service_role, crm_metricas_bridge,
  crm_gestion_diaria_lector y authenticator.
- ACL `{postgres=X/postgres}` y dueño postgres en las tres.
- `_filas` y la autorizada son DEFINER; el ámbito es INVOKER.

**Puertas:**

- `avisos_sla_resumen_v2_fn`, `cola_accion_v3_fn` y `estado_sla_leads_v2_fn` (más `estado_sla_leads_fn` y `cola_accion_v2_fn`)
  tienen ACL `{postgres=X/postgres,authenticated=X/postgres}`, **idéntica a la foto de ANTES**.
- EXECUTE efectivo: authenticated, y crm_gestion_diaria_lector por herencia (igual que antes). No: public, anon, service_role.

**Privilegios por defecto:** no hay ninguno en `private` que regale EXECUTE.

**Llamada directa como `authenticated`:** ver H7 (no se repite por el segfault del entorno).

## Mutantes propios (ninguno está entre los 11 del escritor; en ROLLBACK, como postgres; `14-mutantes.sql`, `salida-14-mutantes.txt`)

| Mutante | ¿Lo detecta algún guardián? | Efecto observado |
|---|---|---|
| V1 `_filas` pasa `p_global = true` al núcleo | **NO** (los 3 en OK) | vendedor 9: 3.869 filas (3.550 ajenas); cola 1.835 ítems |
| V2 el ámbito declara `es_global := true` | **NO** | vendedor 9 ve todo y 1.349 avisos de supervisión |
| V3 el ámbito sin el 42501 | **NO** | la cola sin sesión da 22023 en vez de 42501 |
| V4 EXECUTE de `_filas` a `crm_metricas_bridge` | **SÍ**: `assert_sla_nucleo` y `assert_sla_avisos` («grants externos») | la línea ACL de `verificar` no lo vería (H4) |
| V5 el ámbito pasa a SECURITY DEFINER | **SÍ**: «propiedades incorrectas» | — |
| V6 `_filas` sin el filtro de avisos de supervisión | **NO** | el vendedor ve 43 avisos de supervisión |
| V7 el resumen cuenta todas las filas | **NO** | `total_oportunidades` 60 → 77 |
| V8 el envoltorio `false` con hechos globales | **NO** | consumidor v1 del vendedor 9: 3.869 filas |

Tras el ROLLBACK: los 3 guardianes en OK y el efecto vuelve a la base (319 filas, 0 ajenas). En ANTES, el equivalente de V2 sobre
la autorizada vieja tampoco se detectaba (H2).

## Migraciones y reversas

- **SHA-256** (iguales a `LEEME.md`):
  - M1 `8c808a02…`
  - M2 `0c51c9dd…`
  - M3 `2aaa8837…`
- **Aplicación** (`salida-02-aplicar.txt`, 01:51), con un `verificar` tras cada una:
  - ANTES `62 · 1adaf6c5…`;
  - M1 `64 · 1a632cfd…`;
  - M2 `64 · 5e4e27c4…`;
  - M3 `64 · a8b4558d…`.
  - Todas «la esperada», con los 3 guardianes del SLA en OK.
  - Los otros 4 guardianes, igual que antes: `gestion_diaria`, `analitica_leads_citas` y `analista_vigencia` FALLAN por causas
    ajenas; `f7` en OK.
- **Los 35 guardianes `private.assert_*()`:** mismo estado en M3 y tras revertir: 15 OK y 20 fallan por causas ajenas
  (`salida-guardianes-todos-*.txt`).
- **Reversas** (`salida-16-reversas.txt`, 10:53):
  - Negativas correctas: la de M1 y la de M2 se niegan en M3, la de M3 se niega dos veces, y la de M1 se niega en ANTES.
  - M3 → `SERIE=M2`; M2 → `SERIE=M1`; M1 → `SERIE=ANTES · 62 · 1adaf6c5708637fd916705cc090a4218 (la esperada)`, con las 8 piezas
    en ANTES/AUSENTE y la ACL de las piezas privadas en «ninguna».

## Estado final del banco: REVERTIDO, igual que producción

- **`verificar.sql` final** (10:53, `salida-20-verificar-final.txt`): **`SERIE=ANTES · familia SLA=62 · 1adaf6c5708637fd916705cc090a4218
  (la esperada)`**.
  - Ámbito y `_filas`: AUSENTES.
  - Autorizada, resumen, cola y guardianes: en ANTES.
- **Foto completa del catálogo** (`foto-catalogo.sql`: 1.114 funciones de crm/private/public/auth con huella, dueño, ACL y
  comentario, y 144 tablas y vistas con RLS y ACL) **y checksums de datos** (`crm.leads`, `crm.tareas`, `crm.lead_asignaciones`,
  `crm.actividades`, `crm.equipo`, `crm.sla_operacion_control`, `public.perfiles`, `crm.lead_sla_etapa_ajustes`): **idénticos**
  a los de antes de empezar (`foto-antes.txt` = `foto-final.txt`).
- **Sin conexiones ni procesos míos activos.** Sin esquema `supabase_migrations` (no lo creé).
- **Quedan en `bench`** (andamiaje que no existe en producción y que ni `verificar` ni la foto miran):
  - funciones `vi_*` (8 copias viejas + arnés);
  - tablas `vi_resultados` (la evidencia), `vi_cadenas`, `vi_subconjuntos`, `vi_analistas`, `vi_identidades` y
    `vi_mutaciones_cursor`.
  - Se borran con `drop function bench.vi_…` y `drop table bench.vi_…`.
- **Incidente:** el segfault de H7 reinició el banco una vez (09:56). La recuperación terminó bien (`redo done`, checkpoint) y no
  dejó estado a medias: las transacciones en curso se deshicieron.

## Scripts (en esta carpeta)

- `psqlv.sh`: conexión sin imprimir el `.env`.
- `01-copias-vi.sql`: copias viejas propias.
- `03-arnes.sql`: `vi_eval` y `vi_cmp`.
- `04*`: A.
- `05`: B.
- `06`, `07`, `correr-cadenas.sh`, `10-cadenas-un-reloj.sql`, `correr-un-reloj*.sh`: C.
- `08-permisos.sql`.
- `09-bloque-D-mutaciones.sql` y `bateria.sql`.
- `11-empates-null.sql` y `empates-bateria.sql`.
- `12-repro-empates.sql` y `12b-repro-callejon.sql`.
- `13-bloque-E-cursores.sql`.
- `14-mutantes.sql`.
- `15-bloque-D6-modos-directorio.sql`.
- `16-reversas.sh`.
- `17-mutante-antes.sql`.
- `18-resumen.sql`.
- `foto-catalogo.sql`.
- `guardianes-todos.sql`.

Las salidas son `salida-*.txt`, `salida-*.csv` y `foto-*.txt`.

## NEXT ACTIONS (para el PRIMARY)

1. **H1:**
   - Con el «!» de Miguel, medir la precondición en producción con la consulta de arriba.
   - Si da 0: aceptar y documentar «orden de empates NULL no definido» en `LEEME.md` y en la cabecera de M3.
   - Si no da 0: decidir si se corrige antes de publicar.
2. **H2:** sellar con md5 el ámbito, `_filas` y el envoltorio (y el resumen), dentro de esta serie o como siguiente paso.
3. **H3, H4 y H5:** ajustar los comentarios, la línea ACL de `verificar` y las cifras de los documentos (P3).

CONFIDENCE: alta en la equivalencia fuera de H1 (13.150 comparaciones sin diferencia y 239 cadenas completas hasta el final);
alta en H1 (reproducido sin arnés, en los dos órdenes de evaluación).
