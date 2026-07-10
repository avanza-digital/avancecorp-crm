# Informe técnico — Autenticación y resolución de roles en CRM VITANOVA (Clínica Álvarez)

Repositorio analizado (READ-ONLY): `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANZA-DIGITAL/REPOSITORIO/CLINICA ALVAREZ/crm-vitanova-vite`
Todas las rutas de abajo son relativas a esa raíz salvo indicación contraria.

---

## 1. Cliente Supabase y configuración

- `src/lib/supabase.ts:1-7` — cliente Supabase **ÚNICO y compartido**: `export const sb = createClient(CONFIG.SUPABASE_URL, CONFIG.SUPABASE_ANON_KEY)`. Comentario de cabecera: "Persistencia de sesión por defecto (localStorage). Una sola instancia → una sola sesión / un solo canal realtime". No pasa options: usa los **defaults de supabase-js** (persistSession=true en localStorage, autoRefreshToken=true, detectSessionInUrl=true).
- `src/lib/config.ts:18-25` — URL y ANON key desde `import.meta.env.VITE_SUPABASE_URL/VITE_SUPABASE_ANON_KEY`; **throw en build/arranque si faltan**. Comentario `config.ts:2`: "NUNCA el service_role acá".
- `src/lib/config.ts:33` — `WHATSAPP_LIVE: false` (modo demo del inbox).

## 2. Login

`src/screens/login.tsx`:
- Formulario email+password puro (líneas 12-37). `store.signIn(email.trim(), password)` en línea 21.
- Manejo de error: si el mensaje matchea `/invalid/i` → "Correo o contraseña incorrectos", si no, mensaje crudo o genérico (líneas 22-29); catch de red → "Error de conexión" (línea 33).
- Comentario clave `login.tsx:31`: "El AuthGate detecta la sesión vía onAuth y arranca el boot" — el login **no navega ni bootea**; solo crea la sesión y deja que el listener global reaccione.
- **NO existe flujo de recuperación de contraseña** (grep de `resetPassword|recover|forgot|olvid` en `src/` = 0 resultados). Tampoco registro self-service: los usuarios los crea el gerente (ver §7).
- UI: shadcn/Radix + Tailwind, fondo "aurora" (`vn-aurora`, línea 41), branding "CA"/Clínica Álvarez — 100% web, no portable a RN tal cual.

## 3. Capa auth del store

`src/lib/store.ts`:
- `init()` (232-237): solo valida que exista config; devuelve `{ok:false, reason:'sin-config'}` si faltan URL/key.
- `getSession()` (239-241): `sb.auth.getSession()` → sesión persistida en localStorage (o null).
- `signIn()` (243-248): `sb.auth.signInWithPassword({email, password})` → `{session}` o `{error}`.
- `signOut()` (250-258): `sb.auth.signOut()` + **limpieza total del cache en memoria** (me, lineas, usuarios, prospectos, convs, plantillas, notifs, activeConvId), `bootStarted=false`, **remueve el canal realtime** (`sb.removeChannel`) y `notifyAll()`.
- `onAuth(cb)` (260-263): wrapper de `sb.auth.onAuthStateChange`; devuelve unsubscribe.
- API pública del store (2341-2343): `init, getSession, signIn, signOut, onAuth, boot, me` expuestos en el objeto `store`.

## 4. Resolución de rol tras login — **fila en tabla `usuarios`, NO JWT claim**

`src/lib/store.ts:266-282` — `boot(session)`:

1. `sb.from('usuarios').select('id,nombre_completo,rol,clinica_id').eq('id', session.user.id).maybeSingle()` — la tabla `usuarios` de dominio es **espejo de `auth.users`** (misma PK `id = session.user.id`). El rol vive en la **columna `usuarios.rol`**, se lee UNA vez en boot. No hay custom claims en el JWT ni `app_metadata`.
2. **Fallback de privilegio mínimo** (269-274): si no hay fila, construye un pseudo-usuario `{id, nombre_completo: email, rol: 'asesor', clinica_id: null}` — nunca escala, degrada al rol más bajo.
3. Carga secuenciada de caches: `loadLineas+loadUsuarios` → `loadProspectos+loadPlantillas` → `loadConversaciones` → `loadNotificaciones+loadConfigClinica` (275-278). Ninguna consulta filtra por rol en cliente: **el scoping por rol lo hace RLS en el servidor** (asesor ve lo suyo, supervisor su equipo, gerente todo). Ejemplo explícito: comentario `src/screens/inbox.tsx:76` "el asesor no ve 'Míos' (todo lo suyo ya es su lista por RLS)".
4. `bootStarted = true` → `suscribirRealtime()` → `notifyAll()` (279-281).

`me()` (`store.ts:216-229`): deriva `Me` desde el cache: `{id, nombre_completo, rol, clinica_id, esStaff, firstName}` con **`esStaff = rol === 'gerente' || rol === 'supervisor'`** hardcodeado (línea 220). Tipo `Me` en `src/lib/types.ts:378-385`.

Tipos (`src/lib/types.ts`):
- `types.ts:7` — `export type Rol = 'gerente' | 'supervisor' | 'asesor'` (union cerrada, 3 niveles).
- `types.ts:49-57` — `interface Usuario { id, nombre_completo, rol: Rol, supervisor_id?, clinica_id?, color? }`. **La jerarquía se modela con `usuarios.supervisor_id`** (FK auto-referente): asesor→supervisor. El gerente no necesita FK (ve todo por rol).
- `types.ts:315-323` — `UsuarioConfigRow` agrega `email, activo, telefono`. **Soft-delete de usuarios vía `activo:boolean`** (nunca delete).

**Limitación**: el rol se lee una sola vez en boot; un cambio de rol en la BD no se refleja hasta re-login o refresh (no hay realtime sobre `usuarios`).

## 5. AuthGate — máquina de fases y persistencia de sesión

`src/components/app/auth-gate.tsx`:
- `auth-gate.tsx:8` — `type Phase = 'init' | 'anon' | 'booting' | 'ready' | 'error'`.
- `auth-gate.tsx:10` — `BOOT_TIMEOUT_MS = 15000`: el boot corre en `Promise.race` contra un timeout (62-67); si falla o expira → `phase='error'`.
- **Dedupe de boots** (55-59): ref `bootingFor` guarda el `session.access_token` booteado; `runBoot` retorna temprano si es el mismo token (protege contra StrictMode doble-mount y eventos onAuth repetidos).
- Arranque (75-94): `store.init()` → `store.getSession()`; si hay sesión persistida → `runBoot(session)` (login automático al recargar la página); si no → `'anon'` → renderiza `<Login/>`.
- Listener global (96-106): `store.onAuth((_event, session) => ...)` — con sesión y token distinto → `runBoot`; con `session=null` (signOut o sesión muerta) → `bootingFor=null`, `phase='anon'` → vuelve al Login.
- Render (115-134): `'anon'`→Login; `'error'`→`BootError` con botones **Reintentar** (re-getSession+runBoot) y **Cerrar sesión** (con fallback a 'anon' si el signOut server-side falla, 124-128); `'ready' && snap.booted`→children; resto→`Splash` ("Cargando…" / "Preparando tu información…").

**Expiración de sesión**: no hay manejo explícito. Se apoya en supabase-js:
- Token expira → autoRefresh lo renueva → `onAuthStateChange('TOKEN_REFRESHED', session)` con **access_token NUEVO** → `bootingFor.current !== session.access_token` → **`runBoot` se re-ejecuta completo** (`auth-gate.tsx:100`): re-lee `usuarios` + TODAS las cargas y muestra el Splash de nuevo (phase pasa por 'booting'). Es decir: **cada refresh de token (~1h) provoca un re-boot completo de datos** — quirk/deuda leve, molesto en móvil al volver de background.
- Si el refresh falla definitivamente (refresh token inválido) → evento con `session=null` → `phase='anon'` → Login. No hay toast/aviso de "tu sesión expiró".

## 6. roles.ts — transcripción COMPLETA (CAPS y can)

`src/lib/roles.ts` (52 líneas, archivo completo relevante). Cabecera (líneas 1-2): *"Fuente única de capacidades por rol (portado de roles.js). **NO es seguridad (eso vive en RLS) — es la UX.**"* — patrón de doble capa: RLS = seguridad real, CAPS = qué muestra la UI.

```ts
export type Accion =
  | 'verTodaClinica'
  | 'verEquipo'
  | 'filtrarPorAsesor'
  | 'filtrarPorEquipo'
  | 'reasignar'
  | 'repartirLeads'
  | 'inboxVerAjeno'
  | 'verConfiguracion'
  | 'editarConfiguracion'
  | 'verReportes'

export type Caps = Record<Accion, boolean>

export const CAPS: Record<Rol, Caps> = {
  gerente: {
    verTodaClinica: true, verEquipo: true, filtrarPorAsesor: true, filtrarPorEquipo: true,
    reasignar: true, repartirLeads: true, inboxVerAjeno: true, verConfiguracion: true, editarConfiguracion: true, verReportes: true,
  },
  supervisor: {
    verTodaClinica: false, verEquipo: true, filtrarPorAsesor: true, filtrarPorEquipo: false,
    reasignar: true, repartirLeads: true, inboxVerAjeno: true, verConfiguracion: false, editarConfiguracion: false, verReportes: true,
  },
  asesor: {
    verTodaClinica: false, verEquipo: false, filtrarPorAsesor: false, filtrarPorEquipo: false,
    reasignar: false, repartirLeads: false, inboxVerAjeno: false, verConfiguracion: false, editarConfiguracion: false, verReportes: true,
  },
}

/** can(rol, accion) — ¿el rol tiene la capacidad? */
export function can(rol: Rol | null | undefined, accion: Accion): boolean {
  const c = CAPS[rol ?? 'asesor'] || CAPS.asesor
  return !!c[accion]
}

/** dashboardVariant(rol) — qué variante de dashboard renderizar. */
export function dashboardVariant(rol: Rol | null | undefined): Rol {
  return rol === 'gerente' ? 'gerente' : rol === 'supervisor' ? 'supervisor' : 'asesor'
}

/** inboxPuedeResponder — solo el dueño del prospecto responde su chat. */
export function inboxPuedeResponder(
  conv: { asesor_id?: string | null } | null | undefined,
  me: { id: string } | null | undefined,
): boolean {
  return !!(conv && me && conv.asesor_id != null && conv.asesor_id === me.id)
}
```

Notas: `can()` degrada a `asesor` (mínimo privilegio) ante rol null/desconocido (`roles.ts:36`). `dashboardVariant` es un ternario hardcodeado de 3 vías (`roles.ts:41-43`). Es TS puro sin dependencias de plataforma.

## 7. Route guards y navegación por rol

`src/App.tsx`:
- **No hay router de URL**: la navegación es `const [view, setView] = useState('dash')` (`App.tsx:59`) — sin deep links, sin history. Pantallas lazy-loaded (16-25).
- **Route guard por estado** (`App.tsx:66-69`):
```ts
useEffect(() => {
  if (view === 'config' && snap.booted && !can(rol, 'verConfiguracion')) setView('dash')
  if (view === 'leads' && snap.booted && !can(rol, 'repartirLeads')) setView('dash')
}, [view, rol, snap.booted])
```
Comentario (64-65): el nav ya oculta el ítem; el guard cubre el caso de llegar por estado. Doble defensa: **ocultar en nav + expulsar por efecto**.
- `App.tsx:104-118` — `<AuthGate>` envuelve TODO el árbol (providers + Workspace): nada de la app se monta sin sesión+boot.
- ErrorBoundary POR PANTALLA con `resetKeys={[view]}` (77-81) — un crash de pantalla no tumba el shell/nav.

Sidebar (`src/components/app/sidebar.tsx`):
- `sidebar.tsx:13-15` — `ROL_LABEL: Record<Rol,string> = { gerente:'Gerente', supervisor:'Supervisor', asesor:'Asesor' }` (mostrado bajo el avatar, línea 97).
- `sidebar.tsx:17-27` — `NAV` declarativo; el ítem `leads` lleva flag `staff: true`.
- `sidebar.tsx:52` — filtro por capacidad: `NAV.filter((n) => !('staff' in n) || puedeRepartir)` con `puedeRepartir = can(snap.me?.rol,'repartirLeads')` (línea 39).
- `sidebar.tsx:31,76-90` — sección "Administración"/Configuración solo si `can(rol,'verConfiguracion')` (= solo gerente).
- Badges con conteos vivos desde el snapshot (35-38). SignOut en 41-43/99.

## 8. Modo auditoría (solo-lectura sobre datos ajenos)

Regla transversal: **solo el dueño (asesor asignado) escribe; el staff que puede VER lo ajeno lo ve en solo-lectura**. Aplica incluso al gerente.

### Inbox (`src/screens/inbox.tsx`)
- Cabecera del archivo (líneas 6-7): "responder → SOLO si inboxPuedeResponder(conv, me); staff ajeno → banner 'auditor' + sin composer (solo lectura)".
- `inbox.tsx:161-164`:
```ts
// Modo auditoría: solo el asesor DUEÑO del prospecto responde; staff ve solo-lectura.
const dueno = convRows.find((r) => r.prospecto_id === active)?.prospectos?.asesor_id ?? null
const puedeResponder = !!(me && dueno != null && dueno === me.id)
```
(duplica en línea la lógica del helper `inboxPuedeResponder` de roles.ts:46-51).
- `inbox.tsx:168` — `enviar()` retorna si `!puedeResponder` (guard imperativo además del visual).
- `inbox.tsx:383-415` — si `puedeResponder` renderiza el composer; si no, **banner de auditoría**: icono `Eye` + "Estás viendo como **auditor** — responde {nombre del dueño}. Solo el asesor dueño puede responder este chat." Sin input.
- `inbox.tsx:77-78` — filtros extra ('Míos', Select de asesor) solo si `can(rol,'filtrarPorAsesor')`.

### Ficha (`src/components/ficha/ficha-provider.tsx`)
- `ficha-provider.tsx:274-277`:
```ts
// Modo auditoría: supervisor/gerente sobre un prospecto AJENO ve la ficha en
// solo lectura (igual que el Inbox). Solo el asesor dueño registra acciones.
const ajeno = !!p.asesor && p.asesor !== (snap.me?.id || null)
const soloLectura = can(snap.me?.rol, 'filtrarPorAsesor') && ajeno
```
Es decir: `soloLectura` = (es staff) AND (el prospecto tiene dueño y no soy yo). Un asesor nunca entra en soloLectura porque RLS ya le impide ver ajenos. Prospectos SIN asignar no son soloLectura (staff puede gestionarlos).
- Efectos de `soloLectura`: botón WhatsApp deshabilitado (`ficha-provider.tsx:355-356,359`), menú de etapas `readOnly` (376), botón "Enviar" de borradores oculto (508), y el footer de 5 acciones (WhatsApp/Llamar/Nota/Cita/Cotizar) se **reemplaza por banner ámbar** (529-532): "Modo auditoría · solo {asesor} puede registrar acciones en este prospecto."
- Excepción gerente (Ley 29733, 279-297): exportar datos del titular / anonimizar están disponibles al gerente aun en ficha ajena (`esGerente = snap.me?.rol === 'gerente'`, línea 280).

**Importante**: todo esto es UX; la escritura real la corta RLS (comentario roles.ts:2). El modo auditoría de VITANOVA es **por registro** (ajeno vs propio), no **por rol** — no existe un rol 100% lector.

## 9. Gestión de usuarios y roles (Configuración, solo gerente)

`src/lib/store.ts:2136-2226`:
- `configUsuarios()` (2138-2144): lista `usuarios` con `email,rol,supervisor_id,activo,telefono` (RLS gerente-only según comentario en store.ts:1944).
- `limitesUsuarios()` (2154-2172): **cuotas por rol** desde `clinicas.configuracion.limites` con defaults 3 supervisores / 6 asesores; cuenta solo `activo !== false`.
- `crearUsuario()` (2177-2208): invoca **Edge Function `admin-crear-usuario`** — "gerente-gated + cuota en el servidor"; puede devolver `tempPassword` generada. `CrearUsuarioInput.rol: 'supervisor' | 'asesor'` (`types.ts:333`) — **"NUNCA crea gerente"** (`types.ts:329`): el rol máximo no es creable desde la app.
- `actualizarUsuario()` (2212-2226): update directo a `usuarios` (rol/supervisor_id/activo/nombre/teléfono) — desactivación = `activo:false` (soft-delete).

## 10. Qué cambia para agregar el 4º nivel (vendedor → supervisor → gerencia → directorio/auditoría)

Puntos de contacto EXACTOS que tocaría el 4º rol de solo-lectura total:

1. **`types.ts:7`** — ampliar la union: `Rol = 'vendedor' | 'supervisor' | 'gerencia' | 'directorio'`. Al ser `Record<Rol, ...>`, TypeScript obliga a completar CAPS y ROL_LABEL (fallo de compilación guía la migración). Renombrar `asesor→vendedor`, `gerente→gerencia` toca todos los literales (`me()` store.ts:220, ficha-provider.tsx:280, sidebar ROL_LABEL, dashboardVariant, filtros `u.rol === 'asesor'` en inbox.tsx:93, etc.).
2. **`roles.ts` CAPS** — entrada `directorio`: `verTodaClinica:true, verEquipo:true, filtrarPorAsesor:true, filtrarPorEquipo:true, verReportes:true, verConfiguracion:true(o false)`, y **todo lo de escritura en false** (`reasignar:false, repartirLeads:false, editarConfiguracion:false`). Además conviene **agregar una capacidad nueva `soloLecturaTotal` (o `esAuditor`)** porque el CAPS actual no expresa "no escribe NADA": acciones como crear prospecto, mover etapa, nota, cita, cotizar no están capeadas — su visibilidad depende de `soloLectura` por registro o de nada.
3. **`ficha-provider.tsx:277`** — la condición debe pasar de `can(rol,'filtrarPorAsesor') && ajeno` a `can(rol,'soloLecturaTotal') || (can(rol,'filtrarPorAsesor') && ajeno)` — para directorio TODO es solo-lectura, incluso registros sin asignar.
4. **Inbox** — `puedeResponder` (ownership) ya excluye al directorio sin cambios (nunca es dueño). El banner "auditor" ya existe y aplica.
5. **Pantallas con CTAs de escritura no capeadas** — botón "+ Nuevo prospecto", drag&drop del pipeline, agendar cita en calendario, importación (prospectos.tsx:106-136 `esStaff`), reasignación: todas deben chequear la nueva cap. Hoy `esStaff`/`filtrarPorAsesor` habilita MÁS acciones al staff; con directorio se invierte: más visibilidad, cero escritura.
6. **`store.ts:220` (`esStaff`)** — hardcode `gerente||supervisor`; directorio debe contar como staff para filtros/columna Asesor. Mejor derivarlo de CAPS (`can(rol,'filtrarPorAsesor')`) y eliminar el hardcode.
7. **`roles.ts:41-43` `dashboardVariant`** — ternario de 3 vías; agregar variante `directorio` (dashboard de métricas globales sin CTAs).
8. **RLS (servidor)** — la pieza mayor y no visible en este repo frontend: políticas SELECT que den al directorio visibilidad total de la empresa, y **políticas de INSERT/UPDATE/DELETE que lo excluyan explícitamente**. En VITANOVA la seguridad real es RLS; el CAPS solo esconde botones. Sin esto, el "modo auditoría" del 4º nivel es decorativo.
9. **Edge Function de creación de usuarios** — cuotas y roles creables: decidir si gerencia puede crear directorio o solo el superadmin (patrón "nunca crea el rol máximo" de types.ts:329 se conserva).
10. **AuthGate y boot** — **cero cambios**: son agnósticos al rol (resuelven la fila de `usuarios` sea cual sea el rol).

## 11. Consideraciones React Native (Expo) para el destino

- `roles.ts`, `can()`, `inboxPuedeResponder`, la máquina de fases del AuthGate y el patrón de resolución de rol (fila en `usuarios` con fallback mínimo) son **TS puro / lógica** → viajan a RN sin fricción.
- El cliente Supabase **debe reconfigurarse**: en RN no hay localStorage — `createClient(..., { auth: { storage: AsyncStorage (o adaptador expo-secure-store), autoRefreshToken:true, persistSession:true, detectSessionInUrl:false } })` + arrancar/parar el auto-refresh con `AppState` (patrón oficial supabase-js RN). `supabase.ts:7` tal cual NO funciona en RN.
- El quirk de **re-boot completo en TOKEN_REFRESHED** (§5) es más dañino en móvil (refresh al volver de background) — comparar token de usuario (`session.user.id`) en vez de `access_token`, o ignorar `TOKEN_REFRESHED` si ya está booteado.
- Route guards: RN usará expo-router/react-navigation → los guards por `useEffect+setView` se convierten en rutas protegidas/redirect (o grupos de rutas por rol); el patrón "nav oculta + guard expulsa" se conserva conceptualmente.
- Toda la UI (shadcn/Radix/Tailwind, sidebar web de 256px, aurora del login, verde emerald del inbox/WhatsApp) **no transfiere** a RN; además el destino prohíbe verde y exige navy #111e3d / azul #2563eb / Plus Jakarta Sans.
- `useSyncExternalStore` + store pub/sub singleton funcionan en RN sin cambios (React 18+).
- Naming: VITANOVA ya usa **español snake_case** en BD (`usuarios.nombre_completo`, `rol`, `supervisor_id`, `activo`) — compatible con la convención destino; solo cambian los valores de rol y `asesor_id`→`vendedor_id`/dominio inversiones.

## 12. Huecos detectados (VITANOVA no los tiene, Avance los necesita)

- **Recuperación / cambio de contraseña**: inexistente en el CRM (solo `tempPassword` al crear usuario). Avance ya tiene una nota "Recuperación de contraseña" en su vault para el portal cliente; el CRM interno necesitará al menos reset por email o cambio forzado de clave temporal.
- **Rol de solo-lectura total (directorio/auditoría)**: no existe; el modo auditoría actual es por-registro.
- **Log de auditoría de accesos/acciones**: no hay bitácora de sesiones ni de quién vio qué (solo `actividades` por prospecto y la auditoría que deja `anonimizar_prospecto`). Para un nivel directorio/auditoría con ~5,000 clientes e inversiones es exigible.
- **Refresco de rol en caliente**: el rol se congela en boot; desactivar/despromover a un vendedor no lo expulsa hasta que su sesión muera.
- **Persistencia segura móvil**: SecureStore/AsyncStorage + manejo de AppState (ver §11).
- **Deep links / protección por URL**: no hay router; en Expo Router los guards deben ser reales por ruta.

