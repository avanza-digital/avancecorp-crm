# Handoff — Pantalla "Cartera" (2026-07-21)

Punto de retomo de la sesión que construyó y desplegó la pantalla unificada **Cartera** (fusión de *Clientes* + *Contratos*). Ver también [[Deploy a Hostinger]] (ledger) y la memoria `crm-pantalla-cartera-unificada`.

## Estado: Fases 1→6.1 EN PRODUCCIÓN

- **En vivo:** `crm.miavance.com`, build `index-CLdw0VL4.js` (commit `4d09e5f`, pusheado a `avancecorp/main`).
- **Gate:** 568 tests · Playwright 32 passed / 37 skipped / 0 failed · lint / typecheck / build limpios.
- **Todos los deploys** verificados con SHA-256 idéntico local↔prod, ZIP 404, hash vivo antes/después (sin carrera).

| Fase | Qué | Commit |
|------|-----|--------|
| 1–4 | Pantalla unificada: tabla jerárquica cliente ▸ contratos, **capital invertido** (PEN/USD separados), gating por fila (ventana 5 h), rótulo por rol, "Leads" en nav | `f5a1bfc` |
| 5 | Vista móvil card-stack (< 768 px); hook `useEsMovil` | `bcb8c1b` |
| 6 | Retiro total de Clientes/Contratos (router/App/menú, pantallas borradas, bookmarks redirigen) | `07c68f7` |
| 6.1 | Cierre de los 3 hallazgos Codex de Fase 6 (parity supervisión + alias + E2E migrado) | `4d09e5f` |

**Auditoría Codex:** Fase 5 (3 rondas → limpio); Fase 6 (3 Medios → corregidos en 6.1). Fase 6.1 **sin re-auditar aún**.

## ▶ Próximo paso EXACTO: re-auditar Fase 6.1

1. Parche listo: `~/Desktop/cartera-fase6.1.patch` (8 archivos, 407 líneas).
2. Pásalo a Codex con el prompt de verificación (los 3 fixes): parity de supervisión espejo de `filtrarClientes` (dueño null O fuera del roster; solo `verEquipo`; chips de capital intactos), alias heredado en `leerHash` (`#/clientes`/`#/contratos` → `mi-cartera` sin reintroducir en `VISTAS`), y E2E migrados a `#/mi-cartera` conservando asserts de RPC.
3. Si Codex sale limpio → Cartera cerrada. Si hay hallazgos → corregir, re-verificar (`npm run typecheck` + `vitest run` + `npm run lint` + `build` en `CRM-Avance-Corp/app`), re-desplegar con el ritual del ledger.

## Follow-ups (no bloquean)

- **E2E de creación de contrato**: migrar la parte de *numeración* (`2026-01-XXXXXX`) + co-titulares en `p_contrato` + "sin 6 dígitos no llama al server" a un E2E que entre por el **"+ Contrato" por-cliente** de mi-cartera (sin picker). Hoy esos casos viven skipeados en `contratos.spec.ts`.
- **Bundle del entry**: creció a 259 KB (gzip 78) por re-fragmentado de Rolldown al quitar 2 rutas — Dialog/overlays se hundieron en el entry. Opcional: grupo `advancedChunks` para overlays (⚠️ la config advierte que es recursiva).

## Ojo (trampas)

- **Sin commitear a propósito:** conector de leads (`_supabase_functions/functions/crm-importar-leads/` + `scripts/hoja-leads-apps-script.gs`) — tienen **secreto hardcodeado** → rotar + mover a env ANTES de commitear. Y 3 notas del vault.
- **Loop de vigilancia APAGADO** (era un CronCreate cada 2 min, cancelado a pedido de Miguel).
- Reglas congeladas de la Cartera: **PEN y USD jamás se suman**; layout = lógica comercial (capital primero); gating por fila espeja al servidor.

## Falta (CRM en general, fuera de la Cartera)

- **Cargar leads reales** — sigue siendo el desbloqueador (crm.leads = 0; conector Google Sheets vivo, esperando datos).
- Cuenta de gerencia de **Kirk** (su correo es de cliente → necesita otro).
