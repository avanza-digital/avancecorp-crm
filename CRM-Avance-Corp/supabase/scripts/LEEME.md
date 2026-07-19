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

## Ejecucion en branch/staging

```bash
npm run seed:demo
npm run test:rls
```

Ejecuta siempre el seed antes del gate. El seed es idempotente: sincroniza las
cuentas demo, perfiles, jerarquia y fixtures conocidos.

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

El seed tambien crea una actividad por lead y un cliente/contrato bancario
ficticio. Estos fixtures evitan que una prueba de seguridad apruebe por accidente
solo porque la tabla estaba vacia.

## Cobertura del gate

- conteos y conjuntos exactos por rol, con `count: 'exact'`;
- jerarquia recursiva supervisor → supervisor → vendedor, con aislamiento lateral;
- lecturas cruzadas vendedor/equipo/subarbol;
- escrituras cruzadas, reasignacion, soft-delete y hard-delete;
- `crm.equipo` de solo lectura y `crm.actividades` inmutable;
- directorio con lectura global y cero escritura;
- usuario desactivado y cliente del portal sin acceso operativo;
- `crm.clientes_basicos` con una fila real, pero sin columnas bancarias;
- acceso directo a columnas bancarias de `public.perfiles` y a
  `public.contratos` denegado para roles CRM;
- RPC de consulta de DNI disponible para staff, no para clientes;
- `crm.agenda_ics`: cada quien SU fila (crear/rotar token); el token es
  privado incluso para supervisor, gerencia y lector global; sin DELETE ni
  para el dueño; fuera de `crm.equipo` no hay feed (FK);
- anon sin lectura de `crm` ni de datos bancarios.

Cada query comprueba su objeto `error`. En negativas, solo cuentan como bloqueo
un error de autorizacion/RLS (o cero filas cuando esa es la semantica normal de
RLS); errores de red, columnas equivocadas o constraints no producen falsos
positivos.
