---
tags: [crm, ficha-360, incidente, hostinger, deploy, regresion]
actualizado: 2026-08-31
estado: resuelto-en-produccion
---

# Incidente y restauración Ficha 360 — 2026-08-31

Relacionado: [[Ficha comercial 360 de clientes - plan]],
[[Deploy Ficha 360 2026-08-29]], [[Mejoras UX Ficha 360 2026-08-29]] y
[[Deploy a Hostinger]].

## Veredicto

Miguel tenía razón: la Ficha 360 completa sí se publicó el 29/08, pero el
release posterior del 30/08 la sustituyó por el detalle básico anterior. No era
caché, permisos ni un error del usuario.

- Último release bueno de la ficha antes del incidente:
  `crm-20260829T220216Z-e8ac4262b75d`, build
  `build-20260829T220216363Z`.
- Release que estaba vivo al diagnosticar:
  `crm-20260830T195116Z-c9d875b5b5b2`, build
  `build-20260830T195115696Z`.
- Causa: `c9d875b` y `e8ac426` eran ramas paralelas desde `6088501`; el segundo
  despliegue no contenía la historia de la Ficha 360.

## Restauración

Se creó un worktree aislado desde el commit vivo y se integró la rama completa
de la ficha. El merge `f6dd76fa5b7b51cf9aed83fa6f4a58afccc155a3` conserva
como padres tanto `c9d875b5b5b2` como `e8ac4262b75d`.

La ruta real de «Ver detalle» usa `ClienteFicha`. El componente de detalle
básico no se eliminó físicamente porque sigue siendo parte del entorno demo
aislado y de tipos auxiliares; ya no es la experiencia de detalle para sesiones
reales de producción.

Release restaurado:

- release: `crm-20260831T214847Z-f6dd76fa5b7b`;
- build: `build-20260831T214847197Z`;
- ZIP SHA-256:
  `38b916999bef740f8d5b811ebed58865276234dd57311e5b0b06fc407e4f9661`;
- bundle principal: `index-DnBVVczb.js`;
- Mi cartera: `mi-cartera-9j5UtX-x.js`;
- API CRM: `crm-api-DeWg3-Od.js`.

No se aplicó ninguna migración ni escritura de negocio durante esta
restauración. La migración forward-only de Ficha 360 ya estaba en producción.

## Evidencia

- 145/145 pruebas focalizadas.
- 184 archivos y 2.492/2.492 pruebas en el gate completo.
- 6/6 E2E de la Ficha 360.
- TypeScript, lint, cobertura, build, verificación de bundle y duplicación en
  verde; solo permanecen cuatro advertencias a11y preexistentes del carrusel.
- `version.json`, `index.html`, JS/CSS principal, Mi cartera y API CRM vivos
  coinciden byte por byte con el artefacto local.
- El ZIP responde 404 en `crm.miavance.com` y `miavance.com`.
- La rama fuente está respaldada en GitHub como
  `release/restaurar-ficha360-20260831`.

La sesión existente de Chrome no pudo reutilizarse porque el complemento local
apunta a una versión retirada. La verificación visual/funcional se cerró con el
E2E del proyecto y la verificación pública de hashes; no se simuló una sesión
real ni se escribieron datos.

## Candados para que no vuelva a suceder

1. `app/scripts/verificar-bundle-produccion.mjs` rechaza cualquier build que no
   contenga `Capital vigente`, `Inversiones y contratos` e `Historial de
   gestiones`.
2. `_DEV_NO_SUBIR/deploy-hostinger-mcp.mjs` resuelve el build vivo a su
   manifiesto y exige que su commit sea ancestro del candidato.
3. La misma herramienta comprueba SHA-256 del ZIP y las tres secciones de la
   Ficha 360 justo antes de enviarlo a Hostinger.
4. Un release viejo como `c9d875b` ya falla el preflight con un rechazo
   explícito; el release restaurado lo pasa.
5. La regla operativa queda: integrar ramas paralelas antes de construir; no
   promover un ZIP correcto si no contiene todo el release actualmente vivo.
