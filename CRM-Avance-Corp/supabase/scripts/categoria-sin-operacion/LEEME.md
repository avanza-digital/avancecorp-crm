# Sin operación de cartera, solo 'nuevo' (migración 20261009180000)

Regla (decisión de Miguel, 09/10/2026): **un contrato SIN operación de cartera solo puede quedar como 'nuevo'**. Ninguna
vía —«Corregir» del CRM o del portal, elegir una condición de catálogo de upgrade, SQL— puede pasarlo a 'upgrade' o
'renovacion'. Pasar a 'nuevo' o dejarlo vacío sí se permite (el núcleo cuenta vacío como nuevo). Los contratos que ya
existen no se tocan: la regla solo actúa cuando la categoría CAMBIA.

Por qué: `20261009120000` («la operación decide», aplicada el 08/10) dejó la guarda de `public.contratos` sin restringir
los contratos sin operación. La puerta de Gerencia ya lo rechazaba (su núcleo), pero cualquier otra vía podía dejar un
'upgrade' o una 'renovacion' sin la operación que lo respalda. El cinturón del alta solo mira el INSERT.

Qué cambia: SOLO la guarda `private.trg_contrato_categoria_por_operacion()` (la del trigger
`trg_contratos_01_categoria_por_operacion`) y su comentario. Queda igual que antes más una regla al final: sin operación y
categoría nueva distinta de 'nuevo' ⇒ 23514 **«Un contrato sin operación de cartera solo puede quedar como nuevo»** (el
mismo texto que ya da la puerta). El rechazo de aislamiento (25001) sigue primero; con operación, todo igual. Ningún DDL
sobre objetos de `public` (el trigger y su comentario no se tocan). No toca datos, ni la API, ni permisos: **no hay datos
que corregir ni tipos que regenerar**.

Nada de esta carpeta corre contra producción por sí solo: lo corre Miguel con `!` y el orden de abajo.

| Archivo | Qué hace |
|---|---|
| `../../migrations/20261009180000_crm_categoria_sin_operacion_solo_nuevo.sql` | La guarda nueva y su comentario. Preflight por huellas de producción (la guarda y 7 piezas vecinas, los 16 triggers de `public.contratos`); postflight con tres pruebas en negativo que se deshacen. |
| `registrar/20261009180000.sql` · `generar_registrador.py` | Registro en `supabase_migrations.schema_migrations` (`db query --file` NO registra). Regenerarlo si cambia la migración (lleva su md5 y el del cuerpo de la guarda). |
| `reversa.sql` | Devuelve la guarda EXACTAMENTE a la de `20261009120000` y su comentario. No toca datos. |
| `prueba.sql` | Suite del banco (termina en ROLLBACK): sin operación por toda vía, con operación, RLS (el admin del portal no ve las operaciones y la guarda sí), la puerta, el alta y el cinturón, producto de catálogo, sincronización y, aparte, REPEATABLE READ. |
| `mutantes.py` | Mutantes de la guarda que deben MORIR por aserción de `prueba.sql`, y un control equivalente que sobrevive a propósito. |
| `transporte.sh` | Todo en UN mensaje, como `postgres` y con la sesión en REPEATABLE READ: aplicar, segunda aplicación (P0409), registrador (dos veces), reversa (dos veces: la segunda, P0409), registrador sin la migración (se niega) y aplicar de nuevo; 0 candados de aviso tras cada paso. |
| `../test-rls.mjs` (bloque «Categoría por operación») | Un caso más: UPDATE directo fuera de banda de un contrato legacy sin operación a upgrade ⇒ 23514; se deshace siempre; se salta si la regla no está. |

## Orden en producción (Miguel con `!`, desde `CRM-Avance-Corp/`)

1. `supabase db query --linked --file supabase/migrations/20261009180000_crm_categoria_sin_operacion_solo_nuevo.sql`
   La última fila tiene que ser `pg_advisory_unlock = t`. Los avisos `postflight (a)`, `(b)` y `(c)` dicen «OK»; si alguno
   dice «no se pudo correr aquí», es que no había contrato candidato para esa prueba (no es un error: con septiembre ya
   sellado, por ejemplo, la (c) puede quedarse sin candidato; con el puente legacy cerrado, las tres).
   Si falla a mitad, no aplicó nada; antes de reintentar, comprobar que su candado de sesión se soltó (consulta en
   `../categoria-por-operacion/LEEME.md`, «Transporte»). Con un P0409 de preflight: algo cambió desde la medición (o ya
   estaba aplicada): no forzar, revisar.
2. `supabase db query --linked --file supabase/scripts/categoria-sin-operacion/registrar/20261009180000.sql`

No hay paso 3: no hay datos que tocar ni tipos que regenerar. El postflight toca tres contratos un instante (sus filas, dentro
de subtransacciones que se deshacen; `lock_timeout` de 5 s): si alguien los está editando justo entonces, la migración
aborta sin aplicar nada y basta con repetirla. Mejor fuera de las 09:20 Lima (cron del cierre del mes).

## Efecto en las pantallas

- «Corregir» del CRM (`contrato-corregir.tsx` → `public.actualizar_contrato`) y del portal (`public.actualizar_numero_contrato`):
  elegir 'upgrade' o 'renovacion' en un contrato sin operación —también al elegir una condición de catálogo de upgrade—
  responde 23514. **El portal muestra el texto del servidor; el CRM, por ahora, el genérico «No se pudo guardar el
  cambio.»** (`app/src/data/crm-api.ts` no traduce este 23514; igual que ya pasaba desde el 08/10 con «La categoría la
  decide la operación de cartera»). Arreglo de pantalla aparte: mostrar el texto de esos dos 23514, o no ofrecer
  Renovación/Upgrade cuando el contrato no tiene operación.
- De los 106 antiguos sin operación ('upgrade'/'renovacion', marzo a julio): pueden volver a 'nuevo' o quedar vacíos y se
  pueden seguir corrigiendo en lo demás (sin tocar la categoría), pero no cambiar entre 'upgrade' y 'renovacion'.
- Los 19 con categoría vacía: las dos pantallas obligan a elegir una categoría al corregir, y sin operación solo se admite
  'nuevo'. Ojo con marcar 'nuevo' una renovación histórica solo para poder guardar otro dato (marzo a julio no están sellados).
- Para un contrato que YA existe no hay pantalla que le cuelgue una operación: hoy solo SQL (insertar la operación, como el
  backfill B del 23/09; la sincronización le pone la categoría). «Registrar desde la cartera» crea un contrato nuevo.

## Límites

- La regla es inmediata (AFTER por fila, no diferida): un flujo futuro que registre una renovación o un upgrade sobre un
  contrato existente inserta PRIMERO la operación y deja que la sincronización ponga la categoría; nunca al revés.
- Como todo trigger, no frena a un superusuario con `session_replication_role = replica` ni con el trigger deshabilitado.

## Reversa

`supabase db query --linked --file supabase/scripts/categoria-sin-operacion/reversa.sql` → «REVERSA categoría sin operación:
la guarda vuelve a la de 20261009120000». Se niega (P0409) si la guarda vigente no es la de esta migración. La fila de
`schema_migrations` se conserva (regla de la casa): anotar la reversa en `MIGRACIONES.md`.
Si además hubiera que revertir `20261009120000`, esta reversa va ANTES: `../categoria-por-operacion/reversa.sql` comprueba que
la guarda es la suya y se niega con la de esta migración.

## Banco (cómo se ensayó)

Stack propio `avancecorp-categoria-20261008` (puertos 5600x), rehecho desde cero el 09/10 con
`../categoria-por-operacion/banco/montar.sh` y el volcado de producción del 08/10 19:14; `20261009120000` aplicada y registrada
encima: las huellas de la guarda, de las 7 piezas y de los 16 triggers coinciden con las de producción.

```bash
# OJO: la limpieza del gate BORRA crm.equipo y los leads (el mundo pierde a sus personas): los gates, antes de mundo.sql
# o al final de todo.
bash ../categoria-por-operacion/banco/gate.sh <stack> A        # sin esta migración
psql … -U postgres -c "$(cat ../../migrations/20261009180000_crm_categoria_sin_operacion_solo_nuevo.sql)"   # UN mensaje
bash ../categoria-por-operacion/banco/gate.sh <stack> B        # con ella
psql … -U postgres -c "$(cat reversa.sql)"
bash ../categoria-por-operacion/banco/gate.sh <stack> C        # sin ella otra vez: comparar _rojos-B con _rojos-C
psql … -U postgres -c "$(cat ../categoria-por-operacion/reversa.sql)"   # mundo.sql exige 20261009120000 SIN aplicar
psql … -U supabase_admin -f ../categoria-por-operacion/banco/mundo.sql
psql … -U postgres -c "$(cat ../../migrations/20261009120000_crm_categoria_contrato_por_operacion.sql)"
psql … -U supabase_admin -f ../categoria-por-operacion/prueba.sql       # línea base con la guarda vieja
bash transporte.sh <contenedor>                                          # aplica, prueba y deja la migración puesta
psql … -U supabase_admin -f prueba.sql                                   # PRUEBA SIN OPERACION OK + AISLAMIENTO OK
psql … -U supabase_admin -f ../categoria-por-operacion/prueba.sql       # la anterior sigue en verde (83 + 6)
CATEGORIA_GUIONES=<copias con la firma del banco> python3 -I ../categoria-por-operacion/concurrencia.py <contenedor>
python3 -I mutantes.py <contenedor>
```
`psql …` = `-h 127.0.0.1 -p 56002 -d postgres`. Los mutantes de `20261009120000` se corren desde una copia de su carpeta con
la firma del banco en los guiones (su `mutantes.py` usa los guiones de su propia carpeta). Resultados en `MIGRACIONES.md`
(entrada 20261009180000).
