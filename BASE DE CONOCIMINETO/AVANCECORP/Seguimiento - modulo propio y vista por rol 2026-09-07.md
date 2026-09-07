# Seguimiento: módulo propio y vista por rol

Decisión de Miguel del 07/09/2026: mejorar la presentación del seguimiento y darle un módulo propio fuera de Resumen de Gerencia. Autorizó guardar los cambios en commits. Esta revisión está implementada y probada localmente; todavía no publicada.

Continúa [[SLA R2 - publicacion conjunta y recuperacion 2026-09-07]], [[Nucleo operativo SLA - arquitectura y consumidores 2026-09-06]] y [[Plan final SLA - seguimiento compromisos y etapas 2026-09-06]].

Ruta `#/seguimiento`, menú «Seguimiento» para Gerencia, Supervisor y Analista. Gerencia retira toda la cola de Resumen. Supervisor sustituye la cola activa de Hoy por un acceso al módulo y conserva Agenda. Analista mantiene su cola de Hoy y también puede entrar al módulo. Directorio, Coordinador y Superadmin solo roles no ganan acceso; se respeta el gate de Leads.

La presentación es común; el servidor conserva el alcance global de Gerencia, el subárbol recursivo del Supervisor y la cartera propia del Analista. Los filtros no reconstruyen jerarquías en el cliente. No hace falta otro núcleo ni nuevas calculadoras: se reutilizan las RPC y reglas SLA vigentes.

Seguimiento siempre representa el estado actual; el período y origen del Resumen no lo filtran. Esta diferencia justificó separar la navegación. El filtro Analista solo debe enumerar vendedores activos del roster autorizado, no todos los roles. Los conteos de señales se solapan y nunca se suman como total de oportunidades.

La UI muestra prioridades seleccionables en escritorio y un selector en móvil, filas con responsable/acción/fecha, apertura de ficha y paginación 10/25/50. Conserva modo/error, invalidación, reinicio de cursor y apertura segura fuera del boot. La ayuda reutiliza el contexto operativo `hoy` reconocido por su RPC; no envía un contexto nuevo que el servidor rechazaría.

Commit de implementación `311a212ea9330511fb861c12e07d45801ccd4758`. Suite 2939/2939, 202 archivos; E2E 9/9; ajustes finales de escritorio/móvil 2/2 y título completo medido. Las capturas son de pruebas con datos sintéticos, no una sesión real de Supervisor. Informe y capturas: `CRM-Avance-Corp/PROPUESTA DE SLA PARA ETAPAS/MODULO-SEGUIMIENTO-2026-09-07.md`.
