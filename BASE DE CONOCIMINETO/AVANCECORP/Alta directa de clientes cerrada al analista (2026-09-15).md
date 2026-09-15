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

## Lo que queda abierto

- **La edge `crear-cliente` sigue aceptando al `comercial + vendedor`** (fuente canónica
  `private.puede_gestionar_contratos_crm()`). Hoy solo se llega por el botón, pero es un
  candado de UX, no de servidor. Cerrarla al analista es un cambio de autorización
  (LEVEL 3: edge + posiblemente `mi_acceso_fn`) que se decide aparte.
- Los contratos de clientes ya existentes (Huarcaya S/ 120 000, Centeno S/ 10 000)
  están categorizados `nuevo` aunque el cliente existía; no cambia el total del ranking
  pero sí el conteo de «nuevos».
