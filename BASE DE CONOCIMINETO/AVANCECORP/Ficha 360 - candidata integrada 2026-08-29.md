---
tipo: cierre-deploy
estado: desplegada-verificada
fecha: 2026-08-29
serial_continuidad: GC-ANALISTA-20260828-8DDF91B
migracion_fuente: 20260829183627_crm_ficha_360_scope_historial
migracion_remota: 20260829195528_crm_ficha_360_scope_historial
release: crm-20260829T195236Z-7cfc31bb8ea8
---

# Ficha 360 — desplegada y verificada 2026-08-29

Relacionado: [[Ficha 360 - plan de reintegracion sobre nucleo unico (2026-08-27)]],
[[Ficha 360 R2 - aceptacion UX comercial 2026-08-27]],
[[Deploy Gestión de cartera 2026-08-29]],
[[Deploy Ficha 360 2026-08-29]],
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

La versión integrada fue desplegada con autorización de Miguel. El servidor se
actualizó primero, se leyó de vuelta y recién después se publicó el frontend.
La Ficha 360 quedó disponible en producción para Analistas desde «Mi cartera».

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

## Cierre de producción

- Migración remota aplicada: `20260829195528_crm_ficha_360_scope_historial`.
- Build publicado: `build-20260829T195235854Z`.
- Release fuente: `crm-20260829T195236Z-7cfc31bb8ea8`, commit `7cfc31bb8ea8`.
- Las tres lecturas reales de la ficha respondieron HTTP 200: ficha mínima,
  cuentas autorizadas y actividades del cliente.
- El smoke autenticado abrió Ficha 360, entró al detalle de un contrato y
  regresó a la ficha restaurando el foco en la acción de origen.
- La matriz productiva confirmó: Analista propio permitido, Analista ajeno
  bloqueado, Supervisor de equipo permitido, Gerencia y Directorio con lectura
  global mínima, Coordinador bloqueado.
- La migración F4 que ya estaba en el servidor permaneció presente y sus
  objetos no fueron reemplazados.
- Después se aplicaron `20260829200000_crm_f4_e_correcciones_codex` y
  `20260829201500_crm_f4_f_cooperativas_en_todo`, seguidas por
  `20260829202000_crm_f4_g_etiqueta_cooperativa`; el postflight completo, la
  matriz de roles y el smoke se repitieron sobre el tren y Ficha 360 permaneció
  intacta.
- No se hicieron escrituras de negocio como parte del smoke productivo. El
  trigger de reasignación quedó cubierto por el oráculo local destructivo.

La evidencia completa, las huellas y la ruta de rollback están en
[[Deploy Ficha 360 2026-08-29]].
