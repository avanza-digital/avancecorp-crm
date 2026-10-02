# Banco y ciclos del potencial del lead

Arneses para repetir, en un banco Docker PROPIO, todo lo que acredita las dos migraciones del
potencial del lead. Nunca contra producción. Probados el 30/09/2026 de punta a punta sobre un banco
montado desde cero (montaje + los dos ciclos en menos de tres minutos).

| Script | Qué hace |
|---|---|
| `montar-banco.sh <esquema.sql>` | Levanta el contenedor (imagen `supabase/postgres:17.6.1.105`), crea los dos roles y las dos extensiones que el volcado espera, carga el esquema de producción, crea el historial de migraciones y activa `pg_cron` con los permisos de `postgres`. Imprime las huellas para comparar con producción. Se niega si el contenedor ya existe. |
| `ciclo-fase1.sh` | Migración de la fase 1: ciclo aplicar/repetir/revertir, sintética (75), mutantes de la migración (9) y de lógica (7), concurrencia (11) con sus 3 mutantes, registro y verificación. Si la fase 2 o la puerta de lectura están puestas, las retira y las repone. |
| `ciclo-fase2.sh` | Migración de la fase 2: ciclo sin y con `pg_cron`, caducidad (51), fase 1 sin regresión (75), concurrencia (10), mutantes de lógica (13), de concurrencia (2) y de la migración (4), una corrida REAL de `pg_cron`, la medición del lote y registro y verificación. Exige la fase 1. Si la puerta de lectura está puesta, la retira y la repone. |
| `medir-lote.sql` | Cuánto dura una pasada de la tarea con 2 000 marcas vencidas (todo se deshace). |
| `ciclo-fase3a.sh` | Migración de la puerta de lectura (fase 3, entrega A): ciclo aplicar/repetir/revertir, foto de los trinquetes sin y con la migración, lectura (94), fases 1 y 2 sin regresión (75 y 51), mutantes de lógica (30), de la migración y del preflight (28), el ensayo sin `pg_cron`, la medición, registro, verificación y el verificador frente a un ayudante abierto. Exige las fases 1 y 2. |
| `ciclo-fase3b.sh` | Migración del filtro por potencial (fase 3, entrega B): ciclo aplicar/repetir/reversa (la firma de 13 vuelve byte a byte), foto de los trinquetes, filtro (152), fases 1, 2 y 3A sin regresión, el oráculo de gestión de `scripts/cartera-gestion` contra la firma de 14 (128), mutantes de lógica (28), de migración y preflight (51) y de la reversa (8), la medición, registro y verificación frente a tres estados malos. Termina con un VEREDICTO de máquina (sale con 1 si algo no dio lo esperado). Exige además el trinquete analítico sembrado. |
| `generar-anterior-y-reversa.py` | Genera, desde el texto de `20261001154153`, `anterior-13.sql` (la función anterior como `pg_temp.cartera_filtrada_anterior`, la vara de la igualdad) y `../reversa-filtro.sql`. Con `--comprobar` dice si están al día. |
| `medir-filtro.sql` | La función anterior contra la nueva, sin y con filtro, con 6 000 leads y 2 400 marcas, como gerencia, supervisor y analista (mediana de 5; todo se deshace). Va con `anterior-13.sql` delante. |
| `trinquetes.sql` | Foto de los `private.assert_*()` y del censo de contadores, para compararla antes y después de una migración (todo se deshace). |
| `medir-lectura.sql` | Cuánto tarda la puerta de lectura con 50 y con 200 ids, como analista y como supervisor (todo se deshace). |
| `generar-registrador.py` | Genera el registrador de una migración con su md5 embebido. Si la migración cambia, se vuelve a generar. |

```bash
# 1 · Volcado del esquema (solo lectura sobre producción; sin datos), desde CRM-Avance-Corp/:
supabase db dump --linked --schema public,crm,private --keep-comments -f /ruta/esquema.sql
# 2 · Montar y correr (desde supabase/scripts/potencial-lead/banco/):
BANCO_CONTENEDOR=avancecorp-potencial-AAAAMMDD BANCO_PUERTO=55470 bash montar-banco.sh /ruta/esquema.sql
BANCO_CONTENEDOR=avancecorp-potencial-AAAAMMDD bash ciclo-fase1.sh
BANCO_CONTENEDOR=avancecorp-potencial-AAAAMMDD bash ciclo-fase2.sh
BANCO_CONTENEDOR=avancecorp-potencial-AAAAMMDD bash ciclo-fase3a.sh
# Fase 3B: antes, en un banco recién montado, el trinquete analítico y la migración de gestión.
docker exec -i -e PGPASSWORD=postgres avancecorp-potencial-AAAAMMDD psql -U postgres -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -q < ../../cartera-gestion/siembra-control-banco.sql
docker exec -i -e PGPASSWORD=postgres avancecorp-potencial-AAAAMMDD psql -U postgres -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -q < ../../../migrations/20261001154153_crm_cartera_filtro_gestion.sql   # solo si el volcado es anterior a ella
BANCO_CONTENEDOR=avancecorp-potencial-AAAAMMDD bash ciclo-fase3b.sh
```

## Cómo leer la salida

- En los mutantes de la **migración**, lo correcto es un `ERROR: PREFLIGHT…` o `ERROR: POSTFLIGHT…`.
  «SIN ERROR (¡el mutante pasó!)» es un fallo del pre/postflight.
- En los mutantes de **lógica**, lo correcto es «N FALLAS de M». Hay tres que deben dar «M de M OK» a
  propósito, porque la defensa está duplicada y el mutante solo rompe una mitad:
  `gerencia-pasa-solo-ayudante` (la puerta exige el rol antes), `cerrados-solo-filtro` y
  `corte-solo-filtro` (la relectura bajo candado los cubre). Sus mutantes **dobles** sí deben caer.
- En la fase 3A sobrevive a propósito `sin-sesion` (sin sesión el gate ya rechaza); su doble
  `sin-sesion-ni-gate` debe caer. Y la línea «trinquetes» debe decir «idénticos».
- En la fase 3B no sobrevive ningún mutante: los 28 de lógica dan «N FALLAS», los 51 de migración un
  `ERROR: PREFLIGHT…` o `POSTFLIGHT…` (o el error de un trinquete ajeno) y los 8 de la reversa un
  `ERROR: REVERSA filtro_potencial…`. La última línea es el veredicto.
- En los mutantes de **concurrencia**, lo correcto son líneas `✗`. Dos de la fase 1 (reversa sin
  candados y reversa con el orden viejo) BORRAN las tablas del banco: el ciclo las reaplica.

## Paridad con producción

`montar-banco.sh` imprime, con `search_path` vacío, el número de funciones y la huella de `crm` y
`private`. La misma consulta contra producción debe dar lo mismo **con el mismo `search_path`**: el
texto de `pg_get_functiondef` cambia con él (6 funciones de postventa muestran `DEFAULT uid()` o
`DEFAULT auth.uid()` según la sesión). El 30/09/2026: `crm` 280 y `private` 540, idénticas.

## Trampas del banco

- `auth.uid()` de la imagen solo lee `request.jwt.claim.sub`; el de producción también
  `request.jwt.claims`. Las pruebas fijan las dos.
- Llamar a una función SIN EXECUTE bajo `set role` tumba este Postgres (17.6 con `plan_filter`): los
  permisos se leen del catálogo, nunca se llama a la función.
- `pg_cron` ya viene cargado en la imagen (`shared_preload_libraries`), pero hay que crear la extensión
  y dar a `postgres` uso del esquema `cron`. Corre como cliente (`cron.use_background_workers=off`) en
  GMT, igual que producción.
- `supabase_migrations.schema_migrations` no existe en la imagen: se crea y se le da a `postgres`.
- La carga da UN error esperado: `storage.objects` no existe en la imagen pelada.
- Un contenedor PARADO lo borra `docker container prune`: mientras dure el trabajo, déjalo corriendo.
