---
tags: [crm, roles, conversion, ranking, mi-cartera, decision]
actualizado: 2026-09-15
estado: publicado-y-verificado-en-produccion
---

# Alta directa de clientes cerrada al analista (2026-09-15)

Relacionado con [[Capacidad única de conversión de leads (2026-09-03)]],
[[Como se mide la conversion del asesor]], [[Conversion mensual - definicion cerrada]]
y [[Ranking de capital total unificado (TC BCRP)]].

## El caso que lo destapó

El 15/09/2026 Miguel vio a **BETZABETH** (vendedora desde el 03/09, cartera heredada de
Pierina Levano) en el **puesto 1 del ranking de capital** de setiembre con **0,00 % de
conversión**. Lectura de producción bajo identidad de Gerencia:

| Lente | Fuente | Resultado |
|---|---|---|
| Ranking capital | `crm.cumplimiento_metas_fn` | S/ 222 450 de meta S/ 150 000 → 148 % |
| Conversión | `crm.conversion_mensual_fn` | 39 leads recibidos, 0 cierres → 0,00 % |

Sus 5 contratos de setiembre **no tienen ningún lead detrás** (comprobado por `perfil_id`,
DNI y teléfono): 3 clientes los dio de alta ella con **«Nuevo cliente»** (alta directa,
sin lead) y 2 son clientes de la cartera heredada con un depósito nuevo. Sus 84 leads
asignados: 78 abiertos, 6 descartados, 0 convertidos.

No es un fallo de cálculo: la conversión cuenta leads convertidos
(`lead_asignaciones.resultado_en`) y el capital cuenta contratos confirmados
(`fecha_cierre_comercial` + `analista_cierre_id`). La puerta «Nuevo cliente» permitía
producir capital sin que el embudo se enterase, y el incentivo premiaba saltarse el lead.

## Decisión (Miguel, 15/09/2026)

**El analista ya no tiene «Nuevo cliente».** Su único camino a un cliente nuevo es
**convertir un lead**. Supervisión y Gerencia conservan el alta directa (no rankean; la
necesitan para migraciones y cartera).

Lo que **no cambia** para el analista: registrar nueva inversión, upgrade, renovación y
corrección sobre clientes que ya existen en su cartera; y convertir leads desde «Leads».

## Implementación (solo frontend, a pedido de Miguel: «lo más fácil»)

- Capacidad nueva `altaDirectaCliente` en `app/src/lib/roles.ts`: vendedor `false`,
  supervisor y gerencia `true`, directorio y coordinador `false`.
- `app/src/screens/mi-cartera.tsx`: el botón «Nuevo cliente» y el diálogo de alta cuelgan
  de `altaDirectaHabilitada = accionesContractualesHabilitadas && can(rol, 'altaDirectaCliente')`.
  El vacío de cartera del analista dice «Tus clientes nuevos nacen al convertir un lead
  desde «Leads»».
- Tests: `roles.test.ts` (quién tiene la puerta), `mi-cartera.test.tsx` (analista sin
  botón y con sus acciones; supervisor y gerencia con botón) y `e2e/cliente-form.spec.ts`
  (los casos de alta corren como supervisor; caso nuevo: el analista no ve el botón).

## Publicación

- Commit `cdf03f2` en `main` y en `avancecorp/main` (main contiene el commit vivo anterior `95804fc`).
- Release `crm-20260915T154200Z-cdf03f266805`, SHA-256 del ZIP
  `574641dfa9641fd44f9cfd7648db6a9b170957bd6958c6ffad5a35281f3b1061`, construido en un
  worktree limpio del commit (el árbol compartido tenía cambios ajenos sin confirmar).
- Preflight OK contra lo vivo; deploy por el carril `_DEV_NO_SUBIR/deploy-hostinger-mcp.mjs`
  con el token de Miguel, el 15/09/2026 ~10:45 Lima.
- Smoke: `version.json` → `build-20260915T154159564Z`; `index.html`,
  `assets/index-YVCMKWK1.js` y `assets/mi-cartera-BhzN8yuD.js` coinciden con el manifiesto;
  el bundle vivo contiene la capacidad y el texto nuevo; raíz 200; el ZIP no quedó público (404).
- Rollback inmediato: `releases/crm-20260915T021656Z-95804fc8d83d.zip` (mismo carril).

## Servidor cerrado también: edge `crear-cliente` v35 (15/09/2026, ~11:40 Lima)

Miguel pidió «apaga esa función desde el servidor, pero no la elimines» y eligió el alcance
**solo al analista**. La función no se borró: se publicó la v35 con el veto.

- Cambio (commit `98bfd74`): en `_supabase_functions/functions/crear-cliente/autorizacion.mjs` el veto
  `esVendedorCrm(acceso.rol_crm)` se evalúa ANTES de la compatibilidad del Portal, porque 15 de los 18
  analistas activos conservan el rol Portal legacy `analista`, que hasta hoy los autorizaba por esa vía.
  Comparación normalizada (trim + minúsculas) como defensa extra; en prod `crm.equipo.rol_crm` tiene un
  CHECK con los cinco literales exactos. `index.ts` y `_shared` no cambian.
- Quién conserva el alta directa: Supervisión (incluidos los dos supervisores con rol Portal `analista`,
  que siguen resolviendo por la vía Portal y autoasignándose), Gerencia (resuelve por la vía Portal:
  admin/superadmin) y admin/superadmin/operaciones del Portal sin membresía CRM.
- Lo que no toca: `crm-convertir-lead` (la conversión de leads no usa esta edge).
- Revisión Codex (SECONDARY_REVIEWER, CLI en sandbox de solo lectura porque el MCP estaba caído):
  CHANGES_REQUESTED con dos P2 —cobertura de roles administrativos y dependencia del literal exacto—,
  ambos atendidos. Gate `npm run test:edge-preflight` (node --test + deno check) PASS.
- Despliegue: `npx supabase@2.114.0 functions deploy crear-cliente --project-ref … --use-api` desde un
  workdir con copia exacta de `_supabase_functions/functions/{crear-cliente,_shared}` y el `config.toml`
  del CRM (drift cero antes y después). Antes de desplegar, la v34 viva era byte a byte igual al árbol.
- Verificación: v35 ACTIVE, `verify_jwt=true`, 7 archivos idénticos al árbol, veto presente en la
  `autorizacion.mjs` viva. Smoke: OPTIONS con origen del CRM 200; POST sin sesión 401; POST con la llave
  pública y sin sesión de usuario → 401 «Sesión inválida» desde nuestro código.
- Hueco declarado: no se ejercitó el 403 con una sesión real de analista (habría que llamar la edge a
  mano con esa sesión). La conducta está probada en unidad con 10 casos y el código vivo es el del árbol.
- Reversa: republicar la v34 (`autorizacion.mjs` del commit `d96ed0a`), mismo carril. **Ojo: la reversa
  vuelve a permitir el alta al analista aunque el botón siga oculto.**

## Lo que queda abierto

- ~~La edge `crear-cliente` sigue aceptando al `comercial + vendedor`~~ → cerrada en la v35 (ver arriba).
  `private.puede_gestionar_contratos_crm()` / `mi_acceso_fn().puede_contratar` NO cambiaron: el analista
  los sigue necesitando para convertir leads.
- Los contratos de clientes ya existentes (Huarcaya S/ 120 000, Centeno S/ 10 000)
  están categorizados `nuevo` aunque el cliente existía; no cambia el total del ranking
  pero sí el conteo de «nuevos».
