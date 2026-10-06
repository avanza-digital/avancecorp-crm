# Cuatro mejoras de la PWA de Gerencia implementadas en local

Miguel pidió ejecutar las cuatro mejoras restantes del plan. Al 6 de octubre de 2026 están implementadas e integradas en el workspace; no se publicaron ni se creó PR. La barra queda **Resumen · Citas · Gestión Diaria · Más**, y Metas continúa en Más.

1. **Pendientes de gestión en Resumen**: hasta tres avisos activos, críticas antes que atención, misma fuente que la campana, total y enlace a todos. La carga no anuncia cero; se explican vacío, error parcial y posible desactualización. No se inventa antigüedad ni responsable.
2. **Bandeja móvil**: tarjetas compactas, filtros plegables con indicador activo, búsqueda y consulta en memoria por cuenta/rol. Al regresar se recuperan scroll y foco; si desapareció el aviso, se enfoca la cabecera. Se mantiene el comportamiento previo de los cortes pospuestos para supervisor y escritorio.
3. **Pantallas prioritarias**: equipos de Gestión Diaria con ordenación compacta; Citas recuerda filtros/vista/página; Ranking y Metas compactan fuentes y valores; Facturación contiene su tabla y deja legibles los nombres; Cartera conserva visibles la consulta activa y el conteo. Los avisos de mes cerrado y ninguna fuente elegida permanecen visibles aun con Fuentes plegadas.
4. **PWA**: estado de desconexión, revalidación de proveedores existentes, actualización aplazable con recarga voluntaria, convivencia con Más y diálogos, tratamiento de teclado y viewport sin confundir zoom con teclado. No se añaden permisos, migraciones, dependencias ni otro sistema de push.

Se reutilizó la copia limpia existente `/tmp/avancecorp-navegacion-movil-20261005`, basada en PR 201 (`1d4134e6476f007ac14cbb38df42b84e22fe862f`). La integración preservó el trabajo ajeno de `ResumenGestionesHoy` y `CitasClientes`. Hay backups y hashes de los 37 archivos verificados en `CRM-Avance-Corp/output/pwa-gerencia-cuatro/integracion-final/`.

Verificación: lint, tipos, build, bundle y duplicación PASS. Suite unitaria completa: 6.129 PASS antes de los ajustes finales; después, 249 pruebas específicas PASS y 251 PASS al integrar en el workspace. Docker completo: 354 PASS, cinco con reintento, 26 omitidas y un fallo persistente de aviso de mes cerrado. Ese fallo se corrigió. Revalidación final: 15 PASS sin reintentos, incluidos el caso corregido y los cinco intermitentes; no se debe afirmar que hubo una nueva ejecución completa totalmente verde. El review secundario pidió cambios; Codex evaluó y verificó las correcciones, sin consultar repetidamente para obtener aprobación.

Pendientes para cierre: backend real NOT RUN por falta de `SUPABASE_URL`; PWA instalada, teclado y áreas seguras reales, segundo plano y recepción de push en iPhone/Android físicos NOT RUN por falta de dispositivos. Publicación pendiente de orden de deploy e integración/preflight de Main. La vista local usa datos demo: <http://127.0.0.1:5184/navegacion-movil.html>.

Acta y evidencia: `CRM-Avance-Corp/output/pwa-gerencia-cuatro/ENTREGA.md`, `verificacion.json`, `review-resolucion.md`, logs, capturas y `cambios.patch`. Plan actualizado: `CRM-Avance-Corp/docs/encargos/2026-10-05-pwa-gerencia-plan-restante.md`.

Relacionadas: [[Gerencia - Plan de cierre PWA y acceso a Gestion Diaria (2026-10-05)]], [[Gerencia - Navegacion inferior movil en vista previa (2026-10-05)]], [[Gerencia - Resumen compacto movil y citas por equipo (2026-10-05)]], [[Notificaciones de tasa - publicadas 2026-09-11]].
