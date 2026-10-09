# Categoría por operación (migración 20261009120000)

Regla (decisión de Miguel, 08/10/2026): **el tipo de un contrato lo decide su operación de cartera**. Si un contrato tiene
operación de cartera (renovación o upgrade), su `categoria` es la de la operación, venga de donde venga el cambio. Sin
operación no se restringe (los contratos antiguos de marzo a julio siguen como están). Los 12 de septiembre que hoy dicen
'nuevo' se corrigen a 'upgrade' por la puerta de Gerencia, antes del sello de septiembre.

Nada de esta carpeta corre contra producción por sí solo: lo corre Miguel con `!` y el orden de abajo.

| Archivo | Qué hace |
|---|---|
| `../../migrations/20261009120000_crm_categoria_contrato_por_operacion.sql` | Núcleo, puerta, los dos triggers, permisos y comentarios. Preflight por huellas (R7 de la medición del 08/10) y postflight con pruebas en negativo que se deshacen. No toca datos. |
| `registrar/20261009120000.sql` · `generar_registrador.py` | Registro en `supabase_migrations.schema_migrations` (`db query --file` NO registra). Regenerarlo si cambia la migración (lleva su md5). |
| `1-ENSAYO.sql` | Los 12 por la puerta con la cuenta de Gerencia elegida por Miguel (ADMINISTRADOR AVANCE CORP: prefijo `bf1c562e` en `c_firma_prefijo`, igual en `2-REAL.sql` y `reversa-datos.sql`), contrato por contrato; termina SIEMPRE en `raise exception` con el resultado. Veredicto esperado: «LISTO PARA 2-REAL». Muestra además, para que Miguel decida, lo que se mueve en el Ranking por origen y en la tarjeta de rentabilidad. |
| `2-REAL.sql` | Lo mismo, todo o nada, con postflight en la misma transacción (los 12 en 'upgrade', capital de septiembre por moneda igual, lo movido = S/ 2.092.254 y US$ 54.971, nadie cambia de dueño, conversión igual, PDF igual, observador sin P0410, libro firmado por Gerencia). El resultado viaja como UNA fila (con el candado de septiembre soltado). |
| `oraculo-despues.sql` · `generar_oraculo.py` | Solo lectura, DESPUÉS de 2-REAL: compara con lo medido el 08/10 (R1–R4) y lista la deriva de septiembre desde la medición. Veredicto PASS / REVISAR. |
| `reversa.sql` | Retira la migración (esquema). No toca datos. |
| `reversa-datos.sql` | Devuelve los 12 a 'nuevo' (solo con septiembre abierto, con la política de rentabilidad en observación y DESPUÉS de `reversa.sql`: mientras exista la prevención, nada puede dejarlos en 'nuevo'). Ver «Reversa» abajo. |
| `prueba.sql` | Suite del banco (81 casos; termina en ROLLBACK): autoridad, motivo, sellado, respaldo, eliminación, «Corregir» en la ventana entre la migración y 2-REAL, alta normal, la puerta con éxito (auditoría, PDF, congelación, idempotencia, producto, libro en observación y en enforcement, declaración de origen pendiente repuesta y vacía durante el UPDATE), prevención (también si otro BEFORE cambia la categoría) y sincronización; y aparte, en una transacción REPEATABLE READ, 6 casos: la puerta, la sincronización (por sus dos caminos) y la guarda (con y sin operación) se niegan con 25001; editar otra cosa del contrato pasa. |
| `concurrencia.py` | Carreras con DOS conexiones (9): el bloque de candados idéntico en los tres guiones (P0); la sincronización bloquea la fila (C1, C2); orden mes → fila frente a un sello (C3); el día comercial que cambia (C4, 40001); una foto REPEATABLE READ anterior a la operación frente a la guarda (N1, 25001); los guiones bajo REPEATABLE READ por defecto y frente a un sello en curso (N2); frente a un alta real de septiembre detenida entre contrato y operación (N3); y corregir a la vez la fecha y la categoría del mismo contrato (N4: Postgres aborta una con 40P01 porque `crm.corregir_fecha_cierre_comercial` toma la fila antes que el mes; lo que aborta no escribe nada). Tras cada una, 0 candados de aviso. |
| `transporte.py` | Los archivos que escriben, cada uno como UN mensaje (lo que hace `db query -f`) y como `postgres`: ENSAYO, REAL (frente a un sello y a un alta en curso, fallando en el contrato 11, y bien), oráculo, `reversa.sql`, `reversa-datos.sql` (frente a un sello en curso, con septiembre sellado, y bien) y la migración otra vez; varios con la sesión en REPEATABLE READ por defecto. Comprueba que lo que falla no escribe nada y que no queda ningún candado. Deja el banco como estaba. |
| `mutantes.py` | 23 mutantes que deben MORIR por aserción (21 de funciones y triggers, 2 del bloque de candados de los guiones: sin NOWAIT y sin READ COMMITTED) y 2 controles de defensa duplicada (sobreviven a propósito). |
| `../test-rls.mjs` (bloque «Categoría por operación») | En el gate de CI: autoridad (anon, vend1, sup1, coordinador, directorio → 42501), motivo y categoría (22023), respaldo (23514), `{cambio:false}` sin escribir, triggers y permisos. Se salta si la migración no está. |
| `banco/mundo.sql` · `banco/montar.sh` · `banco/gate.sh` | Banco propio: mundo sintético en el estado de producción (los 12 con su número, K1–K11), montaje del esquema de producción con permisos a paridad y gate RLS de una pasada. |

## Orden en producción (Miguel con `!`, desde `CRM-Avance-Corp/`)

1. `supabase db query --linked --file supabase/migrations/20261009120000_crm_categoria_contrato_por_operacion.sql`
   Si falla a mitad, no escribió nada; antes de reintentar, comprobar que su candado de sesión se soltó (consulta en
   «Transporte»).
2. `supabase db query --linked --file supabase/scripts/categoria-por-operacion/registrar/20261009120000.sql`
3. `npm run gen:types` en `app/` (la puerta es una función nueva de `crm`) y commit de los tipos.
4. `supabase db query --linked -f supabase/scripts/categoria-por-operacion/1-ENSAYO.sql` → «LISTO PARA 2-REAL» (y mirar con Miguel
   lo que cambia en el Ranking por origen y en la tarjeta de rentabilidad: también se mueven).
5. `supabase db query --linked -f supabase/scripts/categoria-por-operacion/2-REAL.sql` → fila `resultado` «OK: 12 contratos…».
   Si el ENSAYO o el REAL responden «Hay actividad en curso: vuelve a correr el guion en unos minutos», no escribieron nada:
   esperar y volver a correrlos (mejor de noche, ver «Transporte»).
6. `supabase db query --linked -f supabase/scripts/categoria-por-operacion/oraculo-despues.sql` → PASS.

Todo antes del sello de septiembre: el cron `crm-cierre-mes-diario` puede sellarlo desde el 11/10 a las 00:00 de Lima (corre
a las 09:20 Lima). No sellar septiembre sin el oráculo en PASS.

## Aplicado en producción (08/10/2026)

Migración 22:55 Lima, registrada; `2-REAL.sql` «OK: 12 contratos de nuevo a upgrade» y oráculo **PASS** a las 23:49 Lima. El primer
ENSAYO abortó sin escribir porque producción tiene 3 cuentas de Gerencia y la regla de entonces («la que se llame como el perfil de
pruebas») solo valía en el banco: Miguel eligió ADMINISTRADOR AVANCE CORP y los guiones la fijan. Para el banco (una sola Gerencia,
`ca7e0000-0000-4000-8000-000000000001`), cambiar `c_firma_prefijo` en los tres guiones antes de correr `transporte.py`,
`concurrencia.py` o `mutantes.py`. Resultado completo en `MIGRACIONES.md` (entrada 20261009120000, «Producción»).

## Transporte: todo va en UN mensaje, y los guiones nunca esperan

`supabase db query --linked -f` manda el archivo ENTERO como un solo mensaje (Simple Query). Por eso `1-ENSAYO.sql`,
`2-REAL.sql` y `reversa-datos.sql` no tienen nada antes del BEGIN ni candados de sesión, y abren la transacción con
`begin isolation level read committed;` (no heredan el aislamiento por defecto de la sesión). Después, el bloque
`$candados$` (idéntico en los tres) lo toma todo SIN ESPERAR y en este orden:

1. `lock table … in share mode nowait` sobre las 22 tablas que se miden;
2. `pg_try_advisory_xact_lock` del mes de septiembre (las llaves del sello mensual y del núcleo);
3. las 12 filas `for update nowait`.

Si algo ya está tomado, el guion aborta al instante con **«Hay actividad en curso: vuelve a correr el guion en unos
minutos»** y no escribe nada: basta con esperar y volver a correrlo. Así nunca espera a otra transacción, y no puede cerrar
un círculo con un alta a medias (el alta toma `public.contratos` y, en su trigger `definir_periodo_comercial_contrato`, el
mes) ni con el sello mensual (`crm.cerrar_periodo` toma el mes y `crm.equipo` en SHARE, y su trigger
`trg_conversion_fijar_sello` escribe `crm.conversion_acreditaciones`, que es UNA DE LAS 22: con NOWAIT no hay círculo, el
guion sale). Mientras corren (unos segundos) bloquean las escrituras en esas 22 tablas, también `crm.leads` y
`public.perfiles`: mejor en un rato tranquilo (de 22:00 a 07:00 de Lima no entran leads de la landing).
Si algo falla a mitad, el resto del mensaje no se ejecuta, la conexión se cierra y Postgres suelta todo (probado en el
banco: ningún candado de aviso queda tomado).

La migración y `reversa.sql` conservan el candado de SESIÓN `crm_migracion_funciones` de la casa: se suelta al cerrarse
la conexión. **Si fallan a mitad, antes de reintentar hay que comprobar que se soltó** (tiene que dar 0 filas; si sale una
conexión, esperar a que termine, no matarla sin hablarlo con Miguel):

```sql
select l.pid, a.usename, a.state, a.backend_start
  from pg_locks l join pg_stat_activity a using (pid)
 where l.locktype = 'advisory' and l.objsubid = 1
   and l.objid = (hashtext('crm_migracion_funciones')::bigint & 4294967295)::oid
   and l.classid = ((hashtext('crm_migracion_funciones')::bigint >> 32) & 4294967295)::oid;
```

La migración abre su transacción en READ COMMITTED (no REPEATABLE READ como otras de la casa) porque la guarda que crea solo
deja cambiar una categoría en READ COMMITTED y su postflight cambia una (prueba en negativo 2). Lo mismo vale para cualquier
SQL que cambie una categoría o registre una renovación o un upgrade, también una migración futura (la API ya trabaja en READ
COMMITTED).

## Reversa: son DOS transacciones

`reversa.sql` (esquema) y `reversa-datos.sql` (los 12) van por separado y en ese orden. Si `reversa-datos.sql` falla, no
escribe nada (todo o nada), pero el esquema YA está revertido: los 12 siguen en 'upgrade' y no hay puerta ni prevención.
Para salir de ahí: (a) arreglar la causa que da el mensaje `ABORTA: …` (septiembre sellado, política en enforcement,
contrato en eliminación, alguien tocó un contrato) y volver a correr `reversa-datos.sql`, que vuelve a comprobarlo todo;
o (b) volver al estado protegido aplicando otra vez la migración (`db query --linked --file` del archivo; la fila del
registro ya está y el registrador es idempotente): los 12 quedan en 'upgrade' y con la prevención puesta. No dejarlo a
medias: mientras el esquema esté revertido, nada impide otra categoría distinta de su operación.

## Banco (cómo se ensayó, y cómo volver a levantarlo)

```bash
# config.toml propio: copia de supabase/config.toml con project_id "avancecorp-categoria-20261008", puertos 56000–56009,
# realtime/studio/edge/analytics apagados y sin las secciones [functions.*]; en <stack>/supabase/config.toml (fuera del repo)
supabase start --workdir <stack> --ignore-health-check
bash banco/montar.sh supabase_db_avancecorp-categoria-20261008 <esquema.sql> <config-carga.sql> <storage-carga.sql>
# OJO: la limpieza del gate BORRA crm.equipo y los leads (el mundo pierde a sus personas): los gates van ANTES de cargar
# mundo.sql o al final de todo.
bash banco/gate.sh <stack> A-antes                               # gate SIN la migración (deja _rojos-A-antes.txt en <stack>)
psql … -U postgres -c "$(cat ../../migrations/20261009120000_crm_categoria_contrato_por_operacion.sql)"   # en UN mensaje
psql … -U postgres -c "$(cat registrar/20261009120000.sql)"
bash banco/gate.sh <stack> B-despues                             # y comparar _rojos-A-antes.txt con _rojos-B-despues.txt
psql … -U postgres -c "$(cat reversa.sql)"                       # mundo.sql exige la migración SIN aplicar
psql … -U supabase_admin -f banco/mundo.sql                      # el estado de producción (crea personas: después no correr el gate)
psql … -U postgres -c "$(cat ../../migrations/20261009120000_crm_categoria_contrato_por_operacion.sql)"
psql … -U supabase_admin -f prueba.sql                           # PRUEBA CATEGORIA OK y PRUEBA AISLAMIENTO OK
python3 -I concurrencia.py supabase_db_avancecorp-categoria-20261008   # CONCURRENCIA OK 9/9
python3 -I mutantes.py supabase_db_avancecorp-categoria-20261008 # 23 de 23 mueren; C1 y C2 sobreviven (controles)
python3 generar_oraculo.py <medición del banco> <oraculo-banco.sql>                       # el oráculo del banco
python3 -I transporte.py supabase_db_avancecorp-categoria-20261008 --oraculo <oraculo-banco.sql>   # TRANSPORTE OK 12/12
supabase stop --workdir <stack>                                  # conserva el volumen; `supabase start --workdir <stack>` lo recupera
```
`psql …` = `-h 127.0.0.1 -p 56002 -d postgres` (contraseña local `postgres`). La medición del banco sale de correr
`medir-categoria.sql` (la de producción, solo lectura) contra el banco con `set search_path = public`.
