---
tipo: checkpoint-integracion
estado: candidata-local-verificada-no-desplegada
fecha: 2026-08-29
serial_continuidad: GC-ANALISTA-20260828-8DDF91B
migracion: 20260829183627_crm_ficha_360_scope_historial
---

# Ficha 360 — candidata integrada 2026-08-29

Relacionado: [[Ficha 360 - plan de reintegracion sobre nucleo unico (2026-08-27)]],
[[Ficha 360 R2 - aceptacion UX comercial 2026-08-27]],
[[Deploy Gestión de cartera 2026-08-29]],
[[Terminología comercial del CRM]] y
[[Auditoría backend Gestión de cartera 2026-08-28]].

## Resultado

La Ficha 360 fue reconstruida aditivamente sobre Gestión de cartera ya
desplegada. En la sesión real, «Ver detalle» abre un panel lateral con
continuidad comercial, inversiones, identidad/contacto, historial y cuentas
según capacidades. La rama preview antigua se usó como referencia UX; no se
fusionó ni se portaron sus migraciones en bloque.

Las acciones secundarias conservan la continuidad: al cerrar Gestión, alta,
renovación o detalle de contrato, se reabre la misma Ficha 360 y el foco vuelve
al siguiente contacto, a inversiones o al contrato que originó la acción.

La candidata sigue aislada y producción permanece intacta. No hay autorización
de deploy en este checkpoint.

## Reglas cerradas

- La palabra visible canónica es **Analista**. Los nombres heredados
  `rol_crm='vendedor'`, `vendedor_id`, `asesor_perfil_id` y `sin_asesor` solo
  permanecen dentro de contratos técnicos compatibles.
- La nueva RPC de ficha devuelve identidad y contacto mínimos. No lleva
  domicilio, banca, autoría ni campos del formulario de corrección.
- Directorio conserva lectura global mínima, sin enlaces de contacto, banca ni
  mutaciones.
- Actividades y operaciones siguen al cliente según su asignación actual; una
  reasignación revoca al ámbito anterior y habilita al nuevo.
- El cambio de Analista queda como un hecho del historial, sin convertir al
  responsable histórico en una vía de autorización.
- Contratos, tareas, numeración, PDF y writers existentes no se redefinen.

## Integración verificable

- Migración forward-only:
  `20260829183627_crm_ficha_360_scope_historial.sql`.
- Oráculo integrado al repositorio:
  `npm run test:ficha-360:db:preflight` y
  `npm run test:ficha-360:db`.
- Marcadores verdes: `FICHA_360_SCOPE_LOCAL_OK` y
  `FICHA_360_DB_GATE_OK`; `db lint` y advisors sin hallazgos en la base local
  desechable.
- Frontend: 184 archivos, 2.489 pruebas unitarias, cobertura, lint, typecheck,
  build, bundle y duplicación aprobados.
- Navegador: 111 E2E aprobados, 26 omitidos por diseño y 0 fallas.

## Condición pendiente

La migración agrega un trigger sobre `public.perfiles.asesor_perfil_id`. No
cambia el esquema ni las policies de `public`, pero la regla del proyecto exige
OK explícito de Miguel antes de aplicar cualquier objeto sobre `public`.
Después de ese OK, el orden es servidor primero, readback/PostgREST, frontend y
smokes autenticados por rol.
