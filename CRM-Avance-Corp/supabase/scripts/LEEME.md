# Seed y gate RLS del CRM

Estos scripts son el gate de seguridad del esquema `crm`. Solo se ejecutan contra
un branch/staging que tenga aplicada la migracion CRM. Ambos abortan de forma
incondicional si `SUPABASE_URL` contiene el ref de produccion.

## Instalacion

Desde `CRM-Avance-Corp/`:

```bash
npm ci
npm run check:scripts
```

`@supabase/supabase-js` esta fijado a una version exacta en el `package.json` y
el lockfile de esta carpeta. Node debe ser `>=22.12.0`.

## Variables

```bash
export SUPABASE_URL='https://<ref-del-branch>.supabase.co'
export SUPABASE_ANON_KEY='<publishable-o-anon-key-del-branch>'
export SUPABASE_SERVICE_ROLE_KEY='<service-role-del-branch>'
export CRM_DEMO_PASSWORD='<password-demo-aleatorio-de-al-menos-12-caracteres>'
```

No guardes estas variables en el repositorio. La `service_role` se usa en el
gate unicamente para comprobar que los fixtures existen y limpiar/restaurar una
fila si una prueba negativa descubre una policy vulnerable. Las aserciones RLS
siempre usan la anon key con sesiones reales, o una sesion anonima.

No existe password demo por defecto: `CRM_DEMO_PASSWORD` es obligatorio y debe
ser el mismo al sembrar y probar. La URL debe usar HTTPS; `http://` se acepta
solo para Supabase local en `localhost`, `127.0.0.1` o `::1`.

## Preflight sin red

```bash
npm run seed:preflight
npm run test:rls:preflight
```

El preflight valida Node, variables, destino y matriz, pero no abre conexiones.
Tambien puedes usar `node supabase/scripts/test-rls.mjs --help`.

El workflow `.github/workflows/crm-rls-preflight.yml` ejecuta `npm ci`, sintaxis
y ambos preflight con valores ficticios. No contiene secretos y no ejecuta el
seed ni el gate vivo. Las pruebas contra Supabase quedan deliberadamente
manuales hasta que se autorice trabajar con un branch de base de datos.

## Limpieza controlada del dataset (branch/staging)

> **WIP auditado localmente — no ejecutar la limpieza efectiva todavía.** La
> validación de opciones, los modos de preservación, el ejemplo de preflight y
> las pruebas de bloqueos destructivos ya están corregidos. Queda un bloqueo de
> integración: `crm.lead_asignaciones` veta todo `DELETE` mediante el trigger
> append-only `trg_lead_asignaciones_00_inmutables`, incluso para `service_role`.
> Hasta definir un camino transaccional exclusivo para una base desechable y
> probarlo allí, solo están aprobados `--help` y `--preflight`; no `--dry-run` ni
> la limpieza real. El propio CLI impone este bloqueo antes de crear el cliente,
> incluso si recibe la frase de confirmación correcta.

Antes de reusar una rama para F2/operación o para demos limpias, usa:

```bash
SUPABASE_URL='https://<ref-del-branch>.supabase.co' \
SUPABASE_SERVICE_ROLE_KEY='preflight-sin-red' \
npm run clean:crm -- --preflight
```

El preflight exige ambas variables, pero la clave ficticia del ejemplo solo
satisface la validación de presencia: no se crea el cliente Supabase ni se abre
una conexión. Valida Node, variables, destino permitido y el plan, sin borrar
nada. El plan incluye también `crm.objetivos_vendedores`, que debe vaciarse antes
de `crm.equipo` por sus claves foráneas.

Pruebas locales, sin red:

```bash
npm run test:clean:crm
```

Cubren flags desconocidos (incluidos `--...`), modos incompatibles, variables
obligatorias, bloqueo de producción, confirmación destructiva, URLs inseguras y
las combinaciones de preservación.

`--dry-run` queda reservado para cuando se cierre el bloqueo transaccional. Hoy
este comando aborta antes de conectarse:

```bash
SUPABASE_URL='https://<ref-del-branch>.supabase.co' \
SUPABASE_SERVICE_ROLE_KEY='....' \
npm run clean:crm -- --dry-run
```

La forma prevista para una futura ejecución real (con `SUPABASE_ANON_KEY` y
`CRM_DEMO_PASSWORD` **no necesarios**) también permanece bloqueada:

```bash
SUPABASE_URL='https://<ref-del-branch>.supabase.co' \
SUPABASE_SERVICE_ROLE_KEY='....' \
CRM_CLEAN_CONFIRM='QUIERO_BORRAR_TODOS_LOS_DATOS' \
npm run clean:crm
```

Opciones:

- `--preserve-equipo`: mantiene `crm.equipo` (vuelve con defaults posteriores si el
  fixture lo reprovisiona).
- `--preserve-reference`: conserva `crm.enfriamiento_politica`,
  `crm.cuentas_bancarias` y `crm.contrato_cuentas_pago`; las dos últimas se
  preservan juntas para no romper el enlace histórico contrato → cuenta.
- Las dos opciones se pueden combinar.

## Oraculo local del gate bancario P04

`test-p04-cuentas-bancarias.sql` es una prueba transaccional autocontenida para
una base PostgreSQL **vacia y desechable**. Primero reproduce el bypass previo,
aplica la migracion real `20260804144555_crm_p04_gate_cuentas_bancarias.sql` y
comprueba los estados mixtos de offboarding, la cartera, las dos variantes de
admin, el wrapper legacy, el resolver de Pagos y los privilegios. Termina en
`ROLLBACK`.

No lo ejecutes contra una rama Supabase ni contra produccion: crea de forma
temporal los roles API y los esquemas minimos que necesita el oraculo. La prueba
viva de las cuatro RPC y sus cinco caminos sigue siendo `npm run test:rls` en
una rama.

La cobertura es deliberadamente del esquema `crm`. Desde el cierre de Productos
del 2026-08-08, Admin y Analista del Portal escriben mediante las fronteras
públicas catalogadas; las RPC canónicas rechazan altas directas de vendedor o
supervisor si no existe una condición seleccionada por wrapper.

## Oráculo local del catálogo de Productos

`test-productos-inversion.sql` reproduce las migraciones de catálogo e
integración Portal sobre una base PostgreSQL vacía y desechable. Cubre creación,
publicación, selección por rol, snapshot histórico, actualización contractual,
interés compuesto anual por años completos, ACL/search path y el cierre
irreversible de `permite_altas_legacy`. Termina en `ROLLBACK` y emite
`PRODUCTOS_INVERSION_TX_OK`.

No ejecutarlo contra producción. En producción el bridge permanece abierto hasta
publicar al menos una condición comercial real y repetir el smoke autenticado;
cerrarlo antes bloquearía todas las altas nuevas.

## Oraculo local del alta atomica de leads P-048

`test-creacion-lead-atomica.sql` prueba la migracion real
`20260804165440_crm_creacion_lead_atomica.sql` sobre un PostgreSQL **vacio y
desechable**. Crea la frontera minima de P-047/P04 y usa `dblink` con dos
conexiones reales para demostrar que los advisory locks de telefono y DNI se
esperan hasta `COMMIT`/`ROLLBACK`, que la segunda sesion vuelve a consultar el
estado y que nunca quedan dos filas.

El oraculo cubre tambien:

- ACL de `crm.crear_lead_si_disponible`: solo `authenticated` tiene `EXECUTE`;
- alta libre, autoridad derivada e idempotencia del reintento inmediato con el
  mismo `p_id` + payload, antes de mutaciones posteriores de esa fila;
- rechazo de reutilizar `p_id` con datos distintos;
- `tomado`, `en_bolsa`, `no_contactar`, `ya_es_cliente`, enfriamiento vigente y
  vencido, telefono invalido y P04/ambito;
- el trigger de compatibilidad para un INSERT humano de un bundle anterior, el
  veto a cambiar teléfono/DNI hacia una identidad bloqueada y la imposibilidad
  de mudar una identidad que porta `no_contactar` o enfriamiento vigente;
- carreras por telefono, por DNI, despertar tras rollback, RPC contra INSERT
  legacy y revocacion P04 mientras una RPC espera el contacto.

La variable psql `test_conn` debe apuntar a esa misma base desechable para que
las conexiones `dblink` compartan los fixtures. Ejemplo:

```bash
psql -X -v ON_ERROR_STOP=1 \
  -v test_conn='postgresql://postgres:postgres@127.0.0.1:5432/crm_p048_test' \
  -f supabase/scripts/test-creacion-lead-atomica.sql
```

El oraculo termina con codigo 0 y el token
`CREACION_LEAD_ATOMICA_TX_OK`. No se ejecuta
contra una rama Supabase ni contra produccion: crea roles API, esquemas, tablas y
la extension `dblink`, y la base completa es descartable al terminar.

Alcance que la prueba no debe exagerar: la atomicidad cubre escritores que tocan
`crm.leads`, porque la RPC y los triggers comparten los mismos locks. La migracion
no instala ningun lock en `public.perfiles`; un alta o cambio de identidad alli
exactamente en paralelo conserva una carrera residual respecto de
`ya_es_cliente`. El
importador comparte la serializacion, pero mantiene deliberadamente sus reglas
propias de reingreso y `no_contactar`, distintas del alta manual.

Durante la adopcion se conserva el INSERT directo de `authenticated`: el trigger
lo protege para no romper un bundle anterior. Revocar ese privilegio y retirar la
policy de INSERT es una fase posterior, solo despues de verificar que todos los
clientes activos usan la RPC. Esta migracion y su frontend siguen **solo locales;
no se han aplicado ni desplegado en produccion**.

## Ejecucion en branch/staging

```bash
npm run seed:demo
npm run test:rls
```

Ejecuta siempre el seed antes del gate. El seed es idempotente: sincroniza las
cuentas demo, perfiles, jerarquia y fixtures conocidos.

### ⚠️ El GATE, en cambio, NO es re-ejecutable sobre la misma base

El seed es idempotente; **el gate no**. Sus fixtures transitorios nacen con
`randomUUID()` en cada corrida (`TRANSIENT_IDS` de `fixtures.mjs`) y el teardown
solo los **desactiva**, no los borra. La segunda corrida se encuentra los de la
primera y las aserciones que cuentan filas —`directorio ve N lead(s)` y su
gemela de conjunto exacto— fallan por acumulacion, no por un defecto real.

Paso de verdad el 2026-07-27: una rama con el gate corrido dos veces dio
**2 de 355 fallidas**, ambas de este tipo (7 demo + 23 residuos = 30 vistos).

Si necesitas correrlo otra vez sobre la MISMA rama, limpia antes los residuos.
El ledger `crm.lead_asignaciones` va primero (FK `RESTRICT`) y con DOS triggers
apagados por nombre — el de auditoria y `trg_lead_asignaciones_00_inmutables`,
que si no aborta con «Los episodios de asignacion no se eliminan»:

```sql
begin;
alter table crm.lead_asignaciones disable trigger trg_audit_lead_asignaciones;
alter table crm.lead_asignaciones disable trigger trg_lead_asignaciones_00_inmutables;
delete from crm.lead_asignaciones la using crm.leads l
 where la.lead_id = l.id and l.nombre_completo like '%TRANSIENT%';
delete from crm.leads where nombre_completo like '%TRANSIENT%';  -- tareas y actividades caen por CASCADE
alter table crm.lead_asignaciones enable trigger trg_audit_lead_asignaciones;
alter table crm.lead_asignaciones enable trigger trg_lead_asignaciones_00_inmutables;
-- Y las tareas transitorias colgadas de leads DEMO, que no caen por cascade:
alter table crm.tareas disable trigger trg_audit_tareas;
delete from crm.tareas where titulo like '%TRANSIENT%';
alter table crm.tareas enable trigger trg_audit_tareas;
commit;
```

Solo contra una RAMA desechable, nunca contra produccion.

## Matriz determinista

| Sesion | Leads esperados |
|---|---:|
| gerencia | 7 |
| supervisor 1 | 4 |
| supervisor 2 | 3 |
| supervisor anidado (bajo supervisor 1) | 1 |
| vendedor 1 | 2 |
| vendedor 2 | 0 |
| vendedor 3 | 1 |
| vendedor 4 | 0 |
| vendedor anidado | 1 |
| vendedor inactivo | 0 |
| directorio | 7 |
| cliente del portal | 0 |

El supervisor 1 ve exactamente cuatro: dos de `vend1`, uno de su **vendedor
nieto** (vendedor bajo un supervisor anidado) y su lead parkeado. Ese cuarto caso
demuestra que la jerarquia se recorre de forma recursiva, no solo un nivel. El
septimo lead pertenece al vendedor inactivo: gerencia/directorio y su supervisor
lo conservan visible para reasignarlo, pero el usuario desactivado no puede leerlo.

El seed tambien crea una actividad por lead, un cliente bancario, un contrato
enlazado y otro legacy sin enlace. Estos fixtures evitan que una prueba de
seguridad apruebe por accidente solo porque la tabla o un camino estaban vacios.

## Cobertura del gate

- conteos y conjuntos exactos por rol, con `count: 'exact'`;
- jerarquia recursiva supervisor → supervisor → vendedor, con aislamiento lateral;
- lecturas cruzadas vendedor/equipo/subarbol;
- escrituras cruzadas, reasignacion, soft-delete y hard-delete;
- `crm.equipo` de solo lectura y `crm.actividades` inmutable;
- directorio con lectura global y cero escritura;
- usuario desactivado y cliente del portal sin acceso operativo;
- matriz P04 de ambos flags (`true/true`, los dos casos mixtos y
  `false/false`), auth canónica ligada al UUID de sesión, fila CRM inactiva que
  revoca el fallback global y rol global que no eleva una membresía activa;
- destino de lead con perfil o membresía inactivos bloqueado incluso para
  `service_role`; política P-047 y feed ICS sin bypass de offboarding;
- `crm.clientes_basicos` con una fila real, pero sin columnas bancarias;
- acceso directo a columnas bancarias de `public.perfiles` y a
  `public.contratos` denegado para roles CRM;
- banca contractual CRM: fixture enlazado y fixture legacy real, las cuatro RPC
  bloqueadas en sus cinco caminos al apagar cualquiera de los flags P04, admin
  con membresia revocada bloqueado y admin global sin membresia conservado;
- RPC de consulta de DNI disponible para staff, no para clientes;
- `crm.agenda_ics`: cada quien SU fila (crear/rotar token); el token es
  privado incluso para supervisor, gerencia y lector global; sin DELETE ni
  para el dueño; fuera de `crm.equipo` no hay feed (FK);
- `crm.objetivos` (metas del mes): todo el arbol comercial + lector global
  las LEEN; solo gerencia las escribe y SOLO via la RPC `fijar_objetivos`
  (upsert parcial sin pisar otros roles; validacion 22023; sin escritura
  directa ni DELETE para nadie del API; usuario inactivo 0 filas). El gate
  usa el periodo sentinela 2099-12 y lo limpia al inicio y al final;
- anon sin lectura de `crm` ni de datos bancarios.

Cada query comprueba su objeto `error`. En negativas, solo cuentan como bloqueo
un error de autorizacion/RLS (o cero filas cuando esa es la semantica normal de
RLS); errores de red, columnas equivocadas o constraints no producen falsos
positivos.
