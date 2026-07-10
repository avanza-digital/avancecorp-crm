---
tags: [auditoria, crm, seguridad, escalabilidad, rendimiento]
actualizado: 2026-07-10
veredicto: frontend-endurecido-db-pendiente
---

# Auditoría CRM — 2026-07-10

Revisión del código en `CRM-Avance-Corp/`, enfocada en escritura segura, escalabilidad y rendimiento. Alcance: app React/TypeScript, migración inicial del esquema `crm`, autenticación, RLS y scripts de prueba. El portal se revisó solo donde comparte Supabase y `public.perfiles`/`public.audit_log`.

## Veredicto

La UI y el diseño de RLS tienen una base prometedora, pero el CRM sigue siendo un **prototipo demo** y no está listo para datos reales. `StoreProvider` guarda leads y actividades en `sessionStorage`; TanStack Query está instalado pero todavía no existe una capa de datos real.

## Bloqueantes antes de conectar o desplegar datos reales

1. **Gate RLS no ejecutable:** `supabase/scripts/test-rls.mjs` no puede resolver `@supabase/supabase-js`, porque la dependencia vive en el `package.json` hermano de `app/`. Además, el seed da 4 filas visibles a `sup1` (3 leads de sus vendedores + 1 parkeado), pero el test espera 3.
2. **Cobertura RLS insuficiente:** la prueba bancaria puede aprobar con cero filas; no prueba acceso directo a columnas bancarias/contratos, desactivación, escrituras cruzadas de supervisores, roles del portal ni jerarquía recursiva. No existe CI que obligue a pasar este gate.
3. **Integridad incompleta en SQL:** la BD normaliza cualquier texto a un teléfono con `+`, pero no exige `^\+519[0-9]{8}$`; `vendedor_id` y `asignado_supervisor_id` pueden apuntar a miembros con rol incorrecto; falta asegurar que un contrato convertido pertenezca al perfil enlazado y que la conversión completa sea atómica.
4. **La vista de clientes no sigue la jerarquía CRM:** `crm.clientes_basicos` es `security_invoker` y hereda las policies del portal. Un supervisor/gerencia cuyo rol de portal sea `analista` no verá la cartera de su subárbol, solo clientes propios/asignados según las reglas actuales de `public.perfiles`.

## Escalabilidad y rapidez

- Cartera, buscador, pipeline y dashboards filtran/renderizan arrays completos en el navegador. No hay paginación ni virtualización real todavía.
- Las métricas recorren leads y vuelven a recorrer todas las actividades por cada lead; con miles de leads el costo crece aproximadamente como `leads × actividades`.
- El contexto global mezcla estado del servidor con estado de UI. Cada mutación reemplaza arrays y puede volver a renderizar todas las pantallas consumidoras.
- Recomendación: React Query con queries paginadas y búsqueda server-side, RPCs de agregación, índices compuestos según consultas reales, mutaciones atómicas/idempotentes y un contexto separado solo para drawers/modales.

## Disciplina de código pendiente

- El build normal pasa y `npm audit --omit=dev` reportó **0 vulnerabilidades**.
- No hay script de tests ni framework de pruebas en `app/package.json`; solo build y lint.
- TypeScript no tiene `strict`, `noUncheckedIndexedAccess` ni `exactOptionalPropertyTypes`; al activarlos aparecen varios errores que hoy quedan ocultos.
- El modo demo es opt-out (`VITE_ENABLE_DEMO !== 'false'`); producción debería ser fail-closed y habilitar demo solo de forma explícita en desarrollo.
- Falta observabilidad centralizada con scrub de PII, correlation IDs y registro de fallos de mutación/RLS; hoy predomina `console` y mensajes locales.
- Los helpers `SECURITY DEFINER` de `private` deberían revocar `EXECUTE` de `PUBLIC/anon` explícitamente y definir default privileges restrictivos.

## Orden recomendado

1. Hacer ejecutable y completo el gate RLS; correrlo en un branch de Supabase y en CI.
2. Corregir invariantes SQL y diseñar las RPC atómicas antes de conectar el frontend.
3. Sustituir el store demo por una capa de datos paginada con React Query y tipos generados desde Supabase.
4. Activar TypeScript estricto + tests unitarios, integración RLS y E2E por rol.
5. Añadir revocación inmediata de acceso, limpieza de caché al cambiar/desactivar rol y observabilidad sin PII.

## Notas relacionadas

[[Deuda técnica CRM fuera de DB 2026-07-10]] · [[Arquitectura del portal]] · [[Rol Analista]] · [[Rol Directorio]] · [[Auditorías del portal]] · [[Inicio]]

## Implementación sin DB — 2026-07-10

Se completó el hardening que no requiere modificar ni ejecutar la base de datos:

- configuración Supabase fail-closed, rechazo de keys privilegiadas, demo solo con opt-in en desarrollo y fixtures demo excluidos del build de producción;
- autenticación validada con servidor, timeout/reintento, revalidación al volver a la pestaña, revocación por miembro/perfil inactivo y limpieza inmediata de caché al perder o cambiar acceso;
- observabilidad estructurada con correlation ID y scrub de PII/credenciales, más CSP, headers de seguridad y política de caché en Apache;
- contextos separados para datos y paneles, cálculos comerciales indexados, paginación/render limitado, búsqueda diferida y capa React Query paginada lista pero todavía no activada;
- TypeScript estricto, CI, 51 pruebas automatizadas, 100% de líneas/funciones/statements y 93.19% de ramas en el núcleo cubierto;
- bundle propio inicial reducido de 527 kB a ~104 kB mediante lazy loading y chunks estables; `npm audit` reporta 0 vulnerabilidades;
- harness RLS determinista y reproducible con preflight offline: matriz exacta, jerarquía recursiva, usuario inactivo, lecturas/escrituras cruzadas, inmutabilidad y fixtures bancarios no vacíos. El CI solo ejecuta sintaxis/preflight y no abre conexiones.

La aplicación ahora bloquea una sesión real con un estado explícito de “datos aún no conectados”; nunca mezcla una cuenta real con datos demo. La capa remota existe como preparación, pero se mantiene deshabilitada hasta autorizar el trabajo de DB.

### Pendiente intencional de DB

No se modificó SQL, no se aplicaron migraciones, no se ejecutó seed y no se conectó el gate RLS a Supabase. Siguen pendientes las invariantes/RPC atómicas, la jerarquía de `crm.clientes_basicos`, los grants de helpers y la ejecución del gate en un branch. Las aserciones bancarias del gate pueden permanecer rojas hasta realizar ese hardening; ese fallo será una señal válida, no un falso positivo.
