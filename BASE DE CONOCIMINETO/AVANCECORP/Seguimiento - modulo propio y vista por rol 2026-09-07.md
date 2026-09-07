# Seguimiento: módulo propio y vista por rol

Decisión de Miguel del 07/09/2026: mejorar la presentación del seguimiento y darle un módulo propio fuera de Resumen de Gerencia. Autorizó guardar los cambios en commits y después publicarlos. Estado: **PUBLICADO** en `crm.miavance.com`, con verificación HTTP y de interfaz en sesión real de Gerencia correctas.

Continúa [[SLA R2 - publicacion conjunta y recuperacion 2026-09-07]], [[Nucleo operativo SLA - arquitectura y consumidores 2026-09-06]] y [[Plan final SLA - seguimiento compromisos y etapas 2026-09-06]].

Ruta `#/seguimiento`, menú «Seguimiento» para Gerencia, Supervisor y Analista. Gerencia retira toda la cola de Resumen. Supervisor sustituye la cola activa de Hoy por un acceso al módulo y conserva Agenda. Analista mantiene su cola de Hoy y también puede entrar al módulo. Directorio, Coordinador y Superadmin solo roles no ganan acceso; se respeta el gate de Leads.

La presentación es común; el servidor conserva el alcance global de Gerencia, el subárbol recursivo del Supervisor y la cartera propia del Analista. Los filtros no reconstruyen jerarquías en el cliente. No hace falta otro núcleo ni nuevas calculadoras: se reutilizan las RPC y reglas SLA vigentes.

Seguimiento siempre representa el estado actual; el período y origen del Resumen no lo filtran. Esta diferencia justificó separar la navegación. El filtro Analista solo debe enumerar vendedores activos del roster autorizado, no todos los roles. Los conteos de señales se solapan y nunca se suman como total de oportunidades.

La UI muestra prioridades seleccionables en escritorio y un selector en móvil, filas con responsable/acción/fecha, apertura de ficha y paginación 10/25/50. Conserva modo/error, invalidación, reinicio de cursor y apertura segura fuera del boot. La ayuda reutiliza el contexto operativo `hoy` reconocido por su RPC; no envía un contexto nuevo que el servidor rechazaría.

Commit de implementación `311a212ea9330511fb861c12e07d45801ccd4758`. Suite 2939/2939, 202 archivos; E2E 9/9; ajustes finales de escritorio/móvil 2/2 y título completo medido. Las capturas son de pruebas con datos sintéticos, no una sesión real de Supervisor. [Informe y capturas](../../CRM-Avance-Corp/PROPUESTA%20DE%20SLA%20PARA%20ETAPAS/MODULO-SEGUIMIENTO-2026-09-07.md).

Fuente del artefacto publicado `556133fdedf5983a4a3a5e221c1296039681b731`, build `build-20260907T054758176Z`, release `crm-20260907T055007Z-556133fdedf5`. ZIP de 1.920.456 bytes y 78 archivos, SHA-256 `c9d6abee25ea175e865c9fa14283073fb81b0f85dc78cdceb0d935c5c9340988`. Main se sincronizó con `avancecorp/main` y se construyó desde una fuente limpia. Los commits documentales posteriores no sustituyen la fuente de ese artefacto.

La [evidencia HTTP de producción](../../CRM-Avance-Corp/PROPUESTA%20DE%20SLA%20PARA%20ETAPAS/modulo-seguimiento-20260907/produccion-http.json) confirma versión estable y cero fallos: 65 hashes exactos, 12 imágenes optimizadas por Hostinger y `.htaccess` con 403. Las URLs del ZIP en CRM y portal devolvieron 404. El JSON se conserva íntegro, sin datos de clientes; las imágenes transformadas no cuentan como coincidencias binarias.

La [verificación real de Gerencia en Chrome](../../CRM-Avance-Corp/PROPUESTA%20DE%20SLA%20PARA%20ETAPAS/modulo-seguimiento-20260907/produccion-ui.json) confirmó menú Seguimiento único, cola ausente en Resumen, 815 oportunidades y páginas de 10; la segunda mostró 11–20 de 815. Contactado redujo a 408, un analista autorizado a 25 y Revisión comercial a 19. La ficha abrió con Seguimiento visible y se cerró sin guardar. Limpiar recuperó 815; el tamaño 25 mostró 25 filas; se restauraron filtros generales y tamaño 10. Cero errores de consola. Son conteos de esa lectura, no constantes comerciales. La captura real queda privada; no hubo sesión real de Supervisor y su evidencia sigue siendo sintética.
