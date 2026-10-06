# Gerencia — navegación inferior móvil (adaptación local)

Estado: Miguel aprobó la vista y pidió completar la adaptación y el plan de implementación. **Implementado y verificado en local**, sin commit, PR ni deploy de esta navegación. Base validada: `b286b2bfce9a24004e887ee0cb127ecf5dab5a23`.

Solo Gerencia y ancho menor de 768 px: **Resumen, Citas, Metas, Más**. La barra reserva su propia fila, sin tapar contenido. Más reúne Facturación, Ranking, Gestión Diaria y Cartera; Análisis, Operación y Administración desplegables; identidad y cierre de sesión. Los 18 destinos heredan el catálogo ya filtrado del Sidebar y la navegación saneada de App. Desktop, tablet y otros roles conservan su lateral. La campana continúa arriba.

Adaptación final: selección accesible de Más para módulos secundarios; Configuración seleccionada también en subrutas; Escape y cierre con restitución del foco; foco al contenido cuando desaparece el disparador al pasar a tablet; cabecera y cuenta sin comprimir en pantallas bajas, lista desplazable. Abrir Más no crea una ruta en el historial; Atrás cambia de vista según el router existente y cierra el panel. No hay cambios de consultas, datos, permisos, dependencias ni migraciones.

Vista de revisión: http://127.0.0.1:5184/navegacion-movil.html, con 390/430/escritorio y demo explícita. Ahora se sirve desde `/tmp/avancecorp-navegacion-movil-20261005/CRM-Avance-Corp/app`, copia limpia con los mismos 15 archivos del alcance. Esta navegación corresponde al código real del CRM. Las cifras de ejemplo no representan producción.

Verificación final: **PASS** `npm run check` (379 archivos / 6.120 pruebas, lint/types/release-config/SW/build/bundle, duplicación 0,43%). **PASS** suite E2E completa Docker: **351 aprobadas, 26 omitidas, 0 fallos**, 13,8 min, 2 workers, **0 reintentos**. Primera corrida completa interrumpida tras encontrar pruebas antiguas que buscaban «Ocultar menú» en Gerencia móvil; adaptados siete specs sin eliminar assertions de negocio y repetida toda la suite. El fixture inicial de config-citas se corrigió: esa ruta exige superadmin; la prueba ahora acredita su denegación y la selección de config-metas autorizada. Runtime idéntico entre workspace y copia validada.

Revisión secundaria por wrapper: **PASS**, sin bloqueantes; incorporada espera explícita del diálogo en el helper E2E. Los P3 e hipótesis restantes están evaluados en `decision-review.txt`. Verificación CUA en Chrome: Resumen, Citas, Metas, abrir/cancelar Nuevo lead y vuelta móvil → escritorio → móvil. PWA en iPhone/Android físicos: **NOT RUN**, pendiente del smoke de publicación. Gate con base real: **NOT RUN**, intento previo sin credenciales de servicio; esta fase no cambia backend.

Plan completo: `CRM-Avance-Corp/docs/encargos/2026-10-05-gerencia-navegacion-movil.md`. Pendiente preparar commit/PR solo del alcance, integrar `avancecorp/main`, verificar igualdad con Main local, construir desde ese commit y publicar cuando Miguel lo indique. Después comprobar actualización PWA y dispositivos físicos. Mantener trabajos ajenos fuera del cambio.

Evidencia: `CRM-Avance-Corp/output/navegacion-movil-local/verificacion.json`, logs y capturas. Producto: `components/app/navegacion-gerencia-movil.tsx` y `.css`, integración en Sidebar y App.Workspace; soporte: helpers, spec de navegación, siete specs existentes y comparador local (no entra al build productivo).

Relacionadas: [[Gerencia - Resumen compacto movil y citas por equipo (2026-10-05)]], [[Gerencia - analisis del menu y limites de medicion (2026-10-05)]].
