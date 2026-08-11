# Cuentas bancarias: ledger vs casillas del perfil

**Fecha:** 2026-08-11 · **Origen:** bug reportado por Miguel en la ficha "Ver detalle" de Mi cartera (caso [[Cuenta piloto CRM Miguel|cuenta piloto]], cliente ORMESINDA JULCA).

## Los dos modelos que conviven

| Modelo | Dónde vive | Qué guarda |
|---|---|---|
| **Casillas embebidas** (portal, viejo) | `public.perfiles` — 14 columnas (`banco`, `cci`, … y `banco_usd`, `cci_usd`, …) | A lo sumo UNA cuenta por moneda |
| **Ledger** (CRM, nuevo) | `crm.cuentas_bancarias` (+ vínculo `crm.contrato_cuentas_pago`) | N cuentas por cliente, con `activa`, `origen` (`perfil`/`contrato`), versionado por desactivación |

**Cómo divergen:** `crm.crear_contrato_con_cuenta` con cuenta "nueva" inserta SOLO en el ledger (`origen='contrato'`) y **no toca** las casillas de `perfiles`. La casilla del perfil se copia al ledger la primera vez que un contrato la usa (`origen='perfil'`). Resultado: una cuenta registrada durante un contrato **no existe** en `perfiles`.

## La regla que deja el bug

> **Toda UI que muestre cuentas de un cliente debe leer la RPC `crm.cuentas_bancarias_cliente_fn`, nunca las casillas embebidas de `perfiles`.**

La RPC ya devuelve la unión correcta: ledger activo + casilla vigente del perfil, **deduplicada** (la casilla solo aparece si no está ya copiada al ledger), ordenada (casilla primero, luego más recientes). Gate de autorización: `private.puede_gestionar_cuentas_cliente` (admin del portal, analista con su cartera, vendedor/supervisor/gerencia por subárbol). Ojo: ese gate **no incluye al lector global** — por eso la ficha degrada la sección bancaria sin tumbar identidad/contacto.

## Lo arreglado (2026-08-11, solo front, cero migraciones)

- `cliente-detalle.tsx`: cuentas desde la RPC (antes: casillas embebidas → la cuenta USD del contrato nuevo era invisible). Muestra N cuentas por moneda con "Registrada el".
- Mismo cambio aprovechado: cliente legacy sin `nombres`/`apellidos` separados (2 de 295, este piloto incluido) muestra "Nombres y apellidos" con `nombre_completo` en vez de «—».

## «Corregir cliente» — arreglado 2026-08-11 (mismo día), con VETO de Codex al primer diseño

El primer diseño («convergencia»: sembrar la cuenta del ledger en las casillas y dejar que el guardado la escriba en `perfiles`) fue **vetado por Codex** con un ALTO de negocio: el módulo de **Pagos** usa las casillas embebidas como fallback `perfil_legacy` para contratos **sin** vínculo en `crm.contrato_cuentas_pago` — copiar una cuenta contractual al perfil convertiría esa cuenta en el destino de cobro de contratos viejos ajenos, el **backfill por inferencia** que prohíbe [[Cuentas bancarias por contrato]].

⚠️ **Lección cara del deploy (2026-08-11):** el primer release de este arreglo se construyó desde un worktree limpio de git… **sin `app/.env`** (gitignorado) → el bundle salió sin las llaves de Supabase y el LOGIN de producción se apagó («El acceso con cuenta aún no está disponible aquí») hasta el rollback. **Regla: todo build desde worktree/CI copia `app/.env` primero, y antes de publicar se verifica que el ZIP contenga el ref de Supabase** (`unzip -p … | grep dctqcbznekcyxhjujuci`).

**Diseño final (en prod, release `crm-20260811T221604Z-c13b79ee9d37`):**
- Las cuentas del ledger se muestran en un **bloque de solo lectura** («Cuentas registradas en contratos — se administran desde el contrato, no aquí»). **Jamás se siembran** en las casillas editables.
- La regla «Registra al menos una cuenta» se **perdona** cuando el ledger cubre (`validarBancariosForm({cuentaEnLedger})`), con patch bancario **en null** — idempotente sobre `perfiles`. Nunca perdona una sección malformada.
- Si el ledger no se puede leer: **aviso visible** con su Reintentar (degradación nunca muda), y el Reintentar del error de carga repara las tres consultas.

**Regla que queda:** las casillas de `perfiles` son la «cuenta global» del cliente (con efecto en Pagos legacy); las cuentas de `crm.cuentas_bancarias` son de SU contrato. **Ningún flujo copia del ledger a las casillas.**

## Pendientes conocidos

- **Snapshot PEN/USD no transaccional en la ficha (limitación aceptada):** son dos RPC independientes; una corrección concurrente entre ambas respuestas puede mezclar versiones por unos milisegundos. Unificarlo exigiría una RPC conjunta (servidor).
- **Escritura concurrente sin CAS en Corregir (preexistente, señalado por Codex):** el UPDATE de set completo puede pisar una casilla que otra sesión escribió después de la precarga. Existía antes de estos cambios; arreglo real = CAS del lado del servidor.
- Issue aparte detectado por Sentry el mismo día: 235 errores 42501 (`crm.clientes.listado_fallido` / `crm.contratos.listado_fallido`) desde el 2026-08-09, de un usuario/rol aún no identificado (el vendedor piloto NO es — verificado por impersonación). Sin resolver.

Relacionadas: [[Cuenta piloto CRM Miguel]] · [[Configuración operativa CRM 2026-08-07]]
