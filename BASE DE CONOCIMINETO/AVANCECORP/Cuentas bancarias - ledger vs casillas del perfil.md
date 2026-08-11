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

## Pendientes conocidos

- **"Corregir" del cliente tiene el mismo sesgo, confirmado por la auditoría Codex 2026-08-11:** precarga solo las casillas embebidas (`cliente-form.tsx`, `cliente-form-logica.ts`), así que un cliente con USD solo en ledger aparece SIN cuenta USD al corregir; y si ambas casillas del perfil están vacías, la validación «Registra al menos una cuenta» (`cliente-form-logica.ts:322`) **bloquea cualquier corrección** aunque el ledger tenga una cuenta activa. Arreglarlo toca el flujo de ESCRITURA (Corregir escribe las casillas del portal) — decisión de diseño pendiente de Miguel.
- **Snapshot PEN/USD no transaccional en la ficha (limitación aceptada):** son dos RPC independientes; una corrección concurrente entre ambas respuestas puede mezclar versiones por unos milisegundos. Unificarlo exigiría una RPC conjunta (servidor).
- Issue aparte detectado por Sentry el mismo día: 235 errores 42501 (`crm.clientes.listado_fallido` / `crm.contratos.listado_fallido`) desde el 2026-08-09, de un usuario/rol aún no identificado (el vendedor piloto NO es — verificado por impersonación). Sin resolver.

Relacionadas: [[Cuenta piloto CRM Miguel]] · [[Configuración operativa CRM 2026-08-07]]
