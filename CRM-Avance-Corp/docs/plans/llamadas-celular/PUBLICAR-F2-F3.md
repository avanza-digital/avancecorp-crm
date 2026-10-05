# Publicar F2 + F3 + F4-a de «Llamadas desde el celular» — guía técnica (05/10/2026)

Siete migraciones, **ninguna aplicada ni desplegada**. Las cuatro primeras están en `main` (PR #169); la quinta
(corrección), la sexta (F4-a, enlace exacto) y la séptima (enlace sin ciclo con Deshacer) están en el PR #190. Se publican **juntas** y con la Edge del contrato
nuevo (decisión 1 de Miguel). F1 (la encuesta al colgar) ya está en producción y no cambia.

Regla del proyecto (`CRM-Avance-Corp/CLAUDE.md`): rama de Supabase → aplicar → gate `test-rls.mjs` → advisors →
merge. **Nunca `apply_migration` directo a producción.**

> **Barrera.** No se despliega la Edge ni se da de alta ningún celular hasta aplicar y verificar la quinta, F4-a **y** la
> séptima (paso 3.4). Sin Edge y sin claves, las puertas de las cuatro no exponen nada: las tablas están vacías. La Edge nueva,
> además, solo entiende la respuesta de la quinta: contra las cuatro contestaría 503 a todo. **Al revés tampoco:** un
> alta antes de la quinta la deja sin poder aplicarse (exige tablas vacías y una asignación no se borra nunca).

> **Instalar no es activar** (decisión de Jhosep, 05/10, tras la segunda revisión de Miguel en el #190). Esta guía
> instala las migraciones y la Edge (§2 y §3). **El alta de claves (§4) y la macro productiva (§5) esperan a F4-b** (la
> pestaña «Llamadas del celular» y el id hasta la encuesta) **y a su prueba en C1 (F4-d)**. Antes, una llamada en «pide
> resultado» —también la que la séptima deja para unir a mano— no tendría pantalla donde resolverse y se borraría a los
> 30 días. Sin claves, la Edge desplegada solo responde 401 y no capta nada. Hasta entonces, C1 sigue apuntando al
> receptor de pruebas del PC.

## 0. Antes de que Miguel empiece

| # | Qué | Estado al 05/10 |
| --- | --- | --- |
| 0.1 | Siete migraciones, cada una con su registrador (`supabase/scripts/llamadas-celular/registrar-{datos,nucleo,ingesta,elegibilidad,correccion,enlace-exacto,enlace-sin-ciclo}.sql`); los tres últimos terminan con una fila de veredicto | Hecho. `npm run test:llamadas:local`: 308/308 |
| 0.2 | Reversas de las siete (`reversa-*.sql`) | Hecho; las de la quinta y F4-a, solo antes de dar de alta celulares; la de la séptima solo cambia cuerpos («Reversa») |
| 0.3 | Edge con el contrato nuevo | Hecho: 16/16 y mutantes 17/17 (05/10: un corte al leer el cuerpo responde 503); sin desplegar |
| 0.4 | Bloque `testLlamadasCelular` del gate al día con la quinta y F4-a (paso 4 del plan v2), y `banco/limpiar-entre-corridas.sql` vaciando las asignaciones | Hecho (05/10): cotejado con las migraciones; `node --check` y oxlint limpios; **sin correr** (necesita el esquema de producción) |
| 0.5 | `alta-celular.sql`, `rotar-celular.sql` y `cerrar-celular.sql` | Hechos (05/10): una sola sentencia cada uno, porque `db query` solo devuelve el último resultado; probados en un Postgres local |
| 0.6 | Codex r2 y `auditor-rls` sobre la quinta + F4-a + la séptima + la Edge | 05/10: su agente revisó dos veces; la segunda (18:46 UTC) da por cerrado el interbloqueo y pide el gate completo y separar la activación. **Pendiente: el gate (§2.5) y los advisors (§2.8)** |
| 0.7 | PR #190 → `main` (`main` tiene que contener lo que se aplica) | Pendiente |
| 0.8 | Activar C1: alta de la clave (§4) y macro productiva (§5) | **Después de F4-b y F4-d** (decisión de Jhosep, 05/10) |

## 1. Decisiones

- Tomadas: las siete de la corrección y sus confirmaciones (`CORRECCION-PLAN-CORTO.md`, «Decisiones»), la N1 según la
  recomendación (`MIGRACIONES.md`, `20261005143843`) y las de Jhosep para F4-a (`MIGRACIONES.md`, `20261005155914`) y la séptima (`20261005182227`: no esperar).
  MacroDroid Pro: todavía no.
- Para que Miguel las vea: los «criterios de Claude» de esas dos entradas de `MIGRACIONES.md`.
- Las migraciones no modifican nada de `public`: solo lo referencian (autoría con `ON DELETE RESTRICT`, lecturas).

## 2. Ensayo en una copia con el esquema de producción

En una copia Docker todo va con `psql "$DB_URL" -v ON_ERROR_STOP=1 -f <archivo>`: `db query --local --file` falla con
varias sentencias. Con `psql` sí se ven los `raise notice`.

1. `auth.uid()` lee `request.jwt.claim.sub` (la ingesta evalúa como el dueño del celular):
   `select pg_get_functiondef('auth.uid()'::regprocedure);` → tiene que consultar
   `current_setting('request.jwt.claim.sub', true)`.
2. Cada migración, seguida **justo después** de su registrador:

   | # | Migración (`supabase/migrations/`) | Registrador | Qué se ve si salió bien |
   | --- | --- | --- | --- |
   | 1 | `20261001145242_crm_llamadas_celular_datos.sql` | `registrar-datos.sql` | notice `REGISTRO: 20261001145242 / …` (con `psql`) |
   | 2 | `20261001160219_crm_llamadas_celular_nucleo.sql` | `registrar-nucleo.sql` | ídem |
   | 3 | `20261001212258_crm_llamadas_celular_ingesta.sql` | `registrar-ingesta.sql` | ídem |
   | 4 | `20261001222431_crm_llamadas_celular_elegibilidad_dueno.sql` | `registrar-elegibilidad.sql` | ídem |
   | 5 | `20261005143843_crm_llamadas_celular_correccion.sql` | `registrar-correccion.sql` | fila `veredicto_registro_20261005143843 = t` |
   | 6 | `20261005155914_crm_llamadas_celular_enlace_exacto.sql` | `registrar-enlace-exacto.sql` | fila `veredicto_registro_20261005155914 = t` |
   | 7 | `20261005182227_crm_llamadas_celular_enlace_sin_ciclo.sql` | `registrar-enlace-sin-ciclo.sql` | fila `veredicto_registro_20261005182227 = t` |

   - No van todos al final: `registrar-nucleo` exige `crm.llamadas_celular_pendientes_fn` y `registrar-elegibilidad`,
     la ingesta de dos argumentos, y la quinta retira las dos.
   - Los registradores comparan el md5 del archivo: se corren desde un checkout con finales de línea LF.
   - Solo entre la 1 y la 2: `verificar-datos.sql` (oráculo de la migración 1; termina en ROLLBACK; esperado
     `ORACULO F2-b OK`). **Después de la quinta ya no corre:** inserta `hash_payload` e ids que la quinta retira.
     Tampoco corren con la quinta `banco/verificar-hallazgos.sql` ni `banco/medir-bandeja.sql`: son de las cuatro.
3. Verificar con V1–V5 del paso 3.4.
4. Ensayar la reversa **antes de crear ninguna asignación** (el gate y el alta las crean, y desde ahí las reversas se
   niegan): `reversa-enlace-sin-ciclo.sql` → `reversa-enlace-exacto.sql` → `reversa-correccion.sql` →
   `reversa-elegibilidad.sql` → `reversa-ingesta.sql` → `reversa-nucleo.sql` → `reversa-datos-total.sql` (con
   `reversa-datos.sql` las tablas se quedan y no se puede volver a aplicar). Fuera de orden, cada una se niega.
   Después, volver a aplicar las siete con sus
   registradores (son idempotentes: la fila del historial se quedó).
5. Gate: `node supabase/scripts/test-rls.mjs` con `CRM_RLS_EXIGE_LLAMADAS=1` y `CRM_BANCO_PSQL_URL`. Tiene que probar:
   nadie toca las tablas directo; cada puerta, solo su rol; clave desconocida → 42501; el mismo id con otro contenido →
   aceptado sin cambios y sin `P0409`; inválidos con el cupo gastado; dos envíos a la vez → uno; número sin lead y lead
   de otro analista → no se guardan; entrantes bloqueadas; lead dado de baja (nadie lo ve); bolsa y reutilizable; un
   enlace real con su encuesta (v5); rotación. **El gate crea asignaciones: desde aquí, en esta copia, las reversas se
   niegan.** Entre corridas, `banco/limpiar-entre-corridas.sql` vacía también las tablas de llamadas.
6. Ensayar el alta por la misma vía que en producción: `alta-celular.sql` con `db query --linked --file` contra una
   rama de Supabase (en Docker esa vía falla). Esperado: una sola fila con la clave; con un usuario que no es gerencia,
   42501. Igual con `rotar-celular.sql` y `cerrar-celular.sql`.
7. Barrera, en una copia aparte que después se descarta: las cuatro con sus registradores, un alta y la quinta → se
   niega con «LLAMADAS_CORRECCION: hay filas en las tablas de llamadas…».
8. Advisors de seguridad y rendimiento: ninguna alerta nueva.

## 3. Producción (con el `!` de Miguel)

1. Antes, que no exista nada: `select to_regclass('crm.llamadas_celular_eventos') is null as limpio;` → `t`. Y el 2.1.
2. Las siete, en el orden del 2.2, **una por mensaje** y cada una seguida de su registrador, desde `CRM-Avance-Corp/` en
   un checkout LF (la Mac de Miguel):
   `npx supabase db query --linked --file supabase/migrations/<migración>.sql`, y después
   `npx supabase db query --linked --file supabase/scripts/llamadas-celular/<registrador>.sql`.
   - Por esta vía no se ven los `raise notice` y solo vuelve el último resultado. Una migración o uno de los cuatro
     registradores viejos que sale bien **no muestra nada** (su última sentencia es `commit`). Uno que falla muestra el
     error y no deja nada (cada archivo es una transacción). Los tres registradores nuevos muestran su fila de veredicto.
   - Después de cada registrador viejo, V1: la fila de esa versión tiene que salir con `ok = t`.
   - Si algo falla, parar ahí: la siguiente migración se niega sin la anterior.
3. Marcar las siete «EN PROD» en `MIGRACIONES.md`.
4. **Verificar (levanta la barrera).** Cada consulta es un solo `select`, para que se vea por `db query --linked`:
   ```sql
   -- V1 · historial: 7 filas, todas ok = t
   select e.version, (m.name = e.nombre and cardinality(m.statements) = 1 and md5(m.statements[1]) = e.md5) is true as ok
   from (values ('20261001145242','crm_llamadas_celular_datos','a431978920a73d38f5c8cf121ad94327'),
                ('20261001160219','crm_llamadas_celular_nucleo','4d78907164c4a77b12ea35f354aebc3e'),
                ('20261001212258','crm_llamadas_celular_ingesta','90d544e9e96c637bcab2869225333ceb'),
                ('20261001222431','crm_llamadas_celular_elegibilidad_dueno','0a4e5b9c148208cc660616bf84d585a9'),
                ('20261005143843','crm_llamadas_celular_correccion','306d706b4b8020b0a7e585300f233d14'),
                ('20261005155914','crm_llamadas_celular_enlace_exacto','69d2137ecf345dda3e8be66b3d6b44fb'),
                ('20261005182227','crm_llamadas_celular_enlace_sin_ciclo','6dea6bd39fa2435ae883396e2c957783')) e(version, nombre, md5)
   left join supabase_migrations.schema_migrations m on m.version = e.version order by e.version;
   -- V2 · forma de la quinta, de F4-a y de la séptima: todo t
   select to_regclass('private.llamadas_celular_recepciones') is not null as recepciones,
          to_regclass('private.llamadas_celular_intenciones') is not null as intenciones,
          to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb,timestamptz)') is not null as ingesta_nueva,
          to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb)') is null as sin_ingesta_vieja,
          to_regprocedure('crm.llamadas_celular_pendientes_fn(integer)') is null as sin_bandeja_vieja,
          to_regprocedure('crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text)') is not null as v5,
          exists (select 1 from pg_constraint where conrelid = 'crm.llamadas_celular_politica'::regclass
                  and conname = 'llamadas_celular_politica_entrantes_bloqueadas') as entrantes_bloqueadas,
          not exists (select 1 from pg_attribute where attrelid = 'crm.llamadas_celular_eventos'::regclass
                      and attname = 'hash_payload' and not attisdropped) as sin_hash_payload,
          exists (select 1 from pg_attribute where attrelid = 'crm.llamadas_celular_enlaces'::regclass
                  and attname = 'via' and not attisdropped) as enlace_con_via,
          strpos(pg_get_functiondef('private.llamada_celular_cumplir_intencion(uuid)'::regprocedure),
                 'for key share nowait') > 0 as sin_ciclo;
   -- V3 · vacías: todo 0
   select (select count(*) from crm.celulares_asignaciones) as asignaciones, (select count(*) from private.celulares_estado) as estado,
          (select count(*) from private.llamadas_celular_recepciones) as recepciones, (select count(*) from crm.llamadas_celular_eventos) as llamadas,
          (select count(*) from crm.llamadas_celular_enlaces) as enlaces, (select count(*) from private.llamadas_celular_intenciones) as intenciones;
   -- V4 · permisos: f, f, t, t, f
   select has_function_privilege('anon', 'crm.ingerir_llamada_celular_servicio(text,jsonb)', 'EXECUTE'),
          has_function_privilege('authenticated', 'crm.ingerir_llamada_celular_servicio(text,jsonb)', 'EXECUTE'),
          has_function_privilege('service_role', 'crm.ingerir_llamada_celular_servicio(text,jsonb)', 'EXECUTE'),
          has_function_privilege('authenticated', 'crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text)', 'EXECUTE'),
          has_function_privilege('anon', 'crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text)', 'EXECUTE');
   -- V5 · retención y política: 23 6 * * *, t, f, f, 30, 600
   select j.schedule, j.active, p.entrantes_activas, p.guardar_sin_identificar, p.limite_envios_minuto, p.limite_envios_dia
   from cron.job j, crm.llamadas_celular_politica p where j.jobname = 'crm-llamadas-celular-caducidad' and p.singleton;
   ```
5. Tipos: `npm run gen:types` en `app/` y commit. La pantalla todavía no usa las puertas nuevas (F4-b).
6. **Recién ahora, la Edge**, desde `CRM-Avance-Corp/` y con el commit del PR #190 o uno posterior:
   ```bash
   npx supabase@2.114.0 functions deploy crm-llamadas-ingesta --project-ref dctqcbznekcyxhjujuci --use-api
   ```
   Toma `verify_jwt = false` de `supabase/config.toml`. No pide secretos nuevos (`SUPABASE_URL` y
   `SUPABASE_SERVICE_ROLE_KEY`). Contrato: 202 llamada aceptada (guardada, repetida o ignorada responden igual), 200
   latido, 400 inválido con el mensaje de la base, 401 clave, 429 con `Retry-After`, 503 inesperado; 405, 415 y 413 sin
   tocar la base. Ya no hay 409.
7. Comprobar el despliegue:
   ```bash
   curl -s -X POST https://dctqcbznekcyxhjujuci.supabase.co/functions/v1/crm-llamadas-ingesta \
     -H 'content-type: application/json' -d '{}'
   curl -s -X POST https://dctqcbznekcyxhjujuci.supabase.co/functions/v1/crm-llamadas-ingesta \
     -H 'content-type: application/json' -H "x-celular-credencial: $(printf '0%.0s' {1..64})" -d '{}'
   ```
   Esperado, las dos veces: `{"error":"No autorizado"}`. La segunda llega a la base y no reconoce la clave. Un 503 en la
   segunda: la Edge no llega a la puerta. «Invalid JWT»: `verify_jwt` quedó encendido.

## 4. Dar de alta un celular (C1 primero) — solo después de F4-b y F4-d

Activación, no instalación: no se hace al publicar (ver «Instalar no es activar», arriba).

- Solo gerencia: `crm.asignar_celular('<etiqueta>', '<uuid del analista>')`. Etiqueta de `C1` a `C999`. El dueño,
  analista (`vendedor`) o supervisor activo. La `credencial` se devuelve **una sola vez**: en la base queda su sha256.
- Con `supabase/scripts/llamadas-celular/alta-celular.sql` (cambiar sus tres valores) y
  `npx supabase db query --linked --file supabase/scripts/llamadas-celular/alta-celular.sql`. Es una sola sentencia:
  la única fila que vuelve trae la clave.
- **⚠️ La salida trae la clave en claro.** Miguel lo corre en su propia terminal, nunca en una sesión de Claude ni
  pegando la salida en un chat. La clave se copia directo al celular (o va a Jhosep por un canal privado) y se limpia la
  terminal. Nunca va al repo ni a un chat. El archivo no se commitea con valores reales.
- **La etiqueta es el prefijo del id en la macro de ESE celular** (`C2-…` en C2). Con otra, la base rechaza cada aviso
  (400 «etiqueta de otro celular») y la macro los aparta en `errores_llamadas`.
- Comprobar sin ver la clave:
  ```sql
  select a.etiqueta, a.vigente_desde, s.ultimo_latido_en, s.version_macro, s.eventos_en_cola
  from crm.celulares_asignaciones a left join private.celulares_estado s on s.asignacion_id = a.id
  where a.vigente_hasta is null order by a.etiqueta;
  ```
- Rotar la clave (`rotar-celular.sql`, misma vía y misma advertencia) reinicia el límite de envíos (el estado va por
  asignación). Solo gerencia rota.

## 5. Cambiar la macro del celular (Jhosep, con Claude): `macrodroid.md` §3c — junto con el alta, después de F4-b y F4-d

1. Vaciar `cola_llamadas` **y** `errores_llamadas` (MacroDroid → Variables globales). La cola de C1 tiene avisos de
   prueba con números reales y con ids que todavía caben en la ventana de 30 días: entrarían como llamadas de verdad.
2. «Fecha y hora automáticas» y zona horaria de Lima. La base rechaza un id con la hora fuera de [hace 30 días, mañana].
3. En «Llamadas-Al colgar», el prefijo del id = la etiqueta del alta.
4. En «Llamadas-Enviar cola» → «Solicitud HTTP» (las dos, aviso y latido): la URL
   `https://dctqcbznekcyxhjujuci.supabase.co/functions/v1/crm-llamadas-ingesta` y la clave en `x-celular-credencial`.
5. Pruebas con datos móviles: A1, A3, las 1 y 6 de F3.3, y L1–L4 de §3c. La encuesta tiene que abrirse en todas las
   llamadas de prueba antes de entregar el celular.
6. Comprobar en la base, sin ver números:
   ```sql
   select (select count(*) from private.llamadas_celular_recepciones r where r.asignacion_id = a.id) as recibidas,
          (select count(*) from crm.llamadas_celular_eventos e where e.asignacion_id = a.id) as guardadas
   from crm.celulares_asignaciones a where a.etiqueta = 'C1' and a.vigente_hasta is null;
   ```
   `recibidas` cuenta todas las salientes de prueba. `guardadas`, solo las de leads del ámbito del analista, sin dueño o
   reutilizables. Un número sin lead o de un lead de otro analista se recibe y no se guarda (decisión 3). En la consulta
   del paso 4: latido reciente y `eventos_en_cola = 0`.

## 6. Pasar un celular a otro analista

La llamada se atribuye a la clave con la que llega. Una cola vieja enviada con la clave nueva quedaría a nombre del
analista nuevo.
1. El analista deja de llamar desde ese celular.
2. Cola en 0: `cola_llamadas` vacía en el celular y, en la consulta del paso 4, `eventos_en_cola = 0` con
   `ultimo_latido_en` posterior a su última llamada (la macro manda el latido cuando la cola se vacía).
3. Vaciar `errores_llamadas` (avisos del analista anterior, con sus números).
4. Gerencia cierra la asignación con `cerrar-celular.sql` (motivo `reemplazo`; los otros: `rotacion`,
   `baja_analista`, `extravio`, `otro`).
5. Alta con la misma etiqueta y el analista nuevo (paso 4), y la clave nueva en la macro.

## Reversa

**Solo antes de dar de alta ningún celular**: sin asignaciones (ni cerradas), estado, recepciones, llamadas, enlaces ni
intenciones. Cada reversa lo comprueba bajo candado y, si no se cumple, se niega.
- Base, una por mensaje: `reversa-enlace-sin-ciclo.sql` → `reversa-enlace-exacto.sql` → `reversa-correccion.sql` →
  `reversa-elegibilidad.sql` → `reversa-ingesta.sql` → `reversa-nucleo.sql` → `reversa-datos.sql` (conserva las tablas)
  o `reversa-datos-total.sql` (las borra). Fuera de orden, cada una se niega.
- La de la séptima solo devuelve dos cuerpos y sus COMMENT (sin tablas ni datos): corre también después del alta, pero
  devuelve el interbloqueo con Deshacer que la séptima corrige.
- La fila de `supabase_migrations.schema_migrations` se queda (regla de la casa, `scripts/potencial-lead/reversa.sql`):
  anotar la reversa en `MIGRACIONES.md`.
- Es más estricto que «antes del primer aviso» a propósito (revisión de Miguel en el #190): recepciones e intenciones
  caducan a los 32 días y una asignación no se borra nunca. Las cabeceras de las dos migraciones nuevas todavía dicen
  «antes del primer aviso» (están selladas por md5); valen los scripts y `MIGRACIONES.md`.
- Edge: si ya se desplegó, borrarla. No hay una versión anterior desplegada.

**Después del alta no se revierte** (reinstalaría las fugas): se apaga y se corrige hacia adelante.
- Borrar la Edge.
- Cerrar cada asignación (`cerrar-celular.sql`).
- En el celular, volver la URL de la «Solicitud HTTP» al receptor de pruebas y quitar la acción «Iniciar macro» de
  «Llamadas-Al colgar»: con «Siempre iniciar», apagar «Enviar cola» no basta.
- El arreglo va en una migración nueva.
