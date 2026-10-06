# Cierre de gestiones en la ficha del cliente

## Estado

**Implementación terminada y vista aprobada por Miguel el 06/10/2026. Preparación de despliegue autorizada.** Se retomó el serial `CRM-CLIENTES-CIERRE-20261006-01` por petición del usuario. La [pausa anterior](2026-10-06-cierre-gestiones-clientes-PAUSA.md) se conserva como historial. El estado de entrega y las puertas de instalación están en el [plan de despliegue](2026-10-06-cierre-gestiones-clientes-DESPLIEGUE.md).

Evaluación de Claude y ajustes aplicables resueltos: [decisiones y evidencia](2026-10-06-cierre-gestiones-clientes-REVISION.md). Las dos migraciones están aplicadas únicamente en el banco sintético propio `gestiones_clientes_20261006`, dentro del contenedor Docker local existente. Producción sin cambios del encargo. El gate integral de entrega pasó en copia limpia del Main vigente: 6.219 pruebas y duplicación 0,43 %, conservando las copias ajenas del árbol compartido. Se mantienen pendientes las puertas remotas de instalación descritas en el plan.

Entrada local vigente: `http://127.0.0.1:5197/artifacts/postventa-local-entrada.html`. Abre la ficha multiempresa actual con datos de ejemplo en memoria; no es una conexión a la base productiva.

### Vista corregida contra la versión publicada (06/10, estado vigente)

Miguel aclaró que quiere **ver en local el CRM vigente con los cambios**, porque el demo heredado mostraba pantallas antiguas. Se sustituyó el servidor del puerto 5197 por una copia exportada del commit publicado `afae7b59412a4aff1160aecdb8f3de12191660d8`, comprobado mediante `https://crm.miavance.com/version.json` (`build-20261006T165239841Z`) y su manifiesto local. Sobre esa copia se aplicó el cambio de cierres: 36 archivos rastreados y ocho nuevos del encargo. No se cambió la rama compartida ni se sobrescribieron trabajos ajenos; los cambios concurrentes sobre restricciones de nueva inversión se excluyeron de la copia.

Código de App, menú, Cartera, ficha comercial, Hoy del analista, estilos y el último cambio de conversión: idéntico byte a byte al commit publicado. Typecheck de la copia PASS. Navegación de Chrome verificada hasta la ficha multiempresa y sus dos botones de cierre; la pestaña antigua se sustituyó y quedó abierta para Miguel. `VITE_ENABLE_DEMO=false`: no volver a usar el login demo para esta revisión. Los datos de la sesión son sintéticos y las escrituras del ejemplo permanecen locales.

Reproducción: `python3 app/artifacts/preparar-crm-vigente.py`. El destino y su procedencia quedan en `app/artifacts/crm-vigente-local.json`; el destino actual es `/private/tmp/crm-vigente-cierre-9tdtpqq6/CRM-Avance-Corp/app`. Iniciar allí Vite con las variables locales documentadas abajo. El backend de ejemplo permanece en `127.0.0.1:59999`. El script verifica y aplica los bloques del cambio sobre el commit publicado, no sobre una rama antigua. Las preferencias de demo que siguen son historial y quedan sustituidas por esta aclaración.

**Preferencia posterior de Miguel, 06/10:** pidió volver a habilitar el modo demo. El servidor 5197 vuelve a usar `VITE_ENABLE_DEMO=true`; la portada ofrece **Explorar en modo demo**. La entrada específica de arriba sigue disponible y abre el ensayo de la ficha multiempresa limpiando solo la marca de demo de esa pestaña.

**Corrección de la vista local, 06/10:** Miguel reportó que veía una versión antigua. El servidor usaba `VITE_ENABLE_DEMO=true`; una sesión demo guardada lleva a `MiCarteraAvance` y no a la ficha multiempresa vigente. Se reinició el mismo puerto con `VITE_ENABLE_DEMO=false`. La entrada explícita elimina la marca de demo y abre una sesión de ejemplo únicamente si el origen es `127.0.0.1:5197` y la API es `127.0.0.1:59999`; luego abre la ruta `#/mi-cartera/inversionista/22222222-2222-4222-8222-222222222222`. Verificado en una pestaña nueva de Chrome: menú vigente, ficha multiempresa y los dos botones **Cerrar tarea**. La aprobación visual sigue a cargo de Miguel. Esta corrección no retira código de compatibilidad del producto ni modifica autenticación productiva.

Para reiniciar esta vista, desde `app`: `env VITE_ENABLE_DEMO=false VITE_SUPABASE_URL=http://127.0.0.1:59999 VITE_SUPABASE_ANON_KEY=e2e-anon-key-not-a-real-secret-000000 npm run dev -- --host 127.0.0.1 --port 5197 --strictPort`. El backend de ejemplo se inicia aparte con `node artifacts/postventa-local-backend.mjs`. No usar el acceso de demo para la revisión de esta tarea.

## Recorrido y reglas

- Cartera → ficha de cliente → Seguimiento: cada tarea pendiente tiene **Cerrar tarea**. Conserva el cierre desde Agenda.
- La ficha neutral usa el formulario de postventa con resultado tipificado. La ficha anterior por perfil abre el cierre existente de Agenda: contestó/no contestó, WhatsApp y resultado comercial de entrevista. Conserva la nota y el diálogo si el servidor rechaza el guardado, hasta confirmar la operación.
- Llamada: siete resultados; agendar cita o volver a llamar exige crear el compromiso correspondiente en la misma operación.
- WhatsApp: enviado o respondido.
- Cita: realizada, no asistió, cancelada o reprogramada. Una cita confirmada sigue pendiente. Solo una asistencia registrada cuenta como entrevista; se conserva su resultado comercial.
- El recibo, tarea siguiente e historial se escriben atómicamente. Repetir el mismo envío devuelve el recibo existente.
- Un cierre anterior sin resultado permanece como histórico sin clasificación. No se inventan entrevistas o llamadas contestadas.
- Las gestiones se atribuyen a quien las registra. El responsable de la tarea en ese momento se guarda separadamente.

## Conexiones

| Destino | Resultado |
| --- | --- |
| Ficha y Agenda | La tarea cerrada sale de pendientes; historial y siguiente tarea se actualizan. |
| Registro de actividad | Leads, perfiles heredados y clientes neutrales; filtros de cartera, autor, tipo y fecha. Etapas aplican a leads. |
| Gestión Diaria | Botón **Gestión de clientes**: desglose leads/clientes/total y actividad por autor. Mantiene la densidad de las tablas existentes. |
| Resumen de gerencia | Desglose de llamadas, contestadas, entrevistas y gestiones del día Lima. |
| Citas | Bloque de clientes por fecha programada, con estado y resultado. |
| Citas agendadas y pendientes | Identifican y abren la ficha del cliente; conservan población, orden, total y cursor originales. |
| CSV | Exporta las filas autorizadas cargadas, incluida la cartera y el resultado. |

Los indicadores, metas, alertas y cortes sellados de **captación de leads** conservan sus fórmulas y fuentes. El resumen operativo nuevo separa clientes y leads. G4b sigue contando tareas de reunión creadas en el día, incluidas las reprogramaciones; no se confunde esa cifra con asistencias.

## Permisos e integridad

La rama de leads conserva su RLS bajo INVOKER. La lectura privada de clientes usa DEFINER con sesión real, roles explícitos, banderas y árbol visible; no se concede SELECT sobre `crm.inversionista_gestiones`. Los candados siguen el orden de F6: modo/resolver y jerarquía.

Después de una reasignación, el autor conserva el conteo histórico de su trabajo. Si pierde acceso al cliente, el Registro retira nombre, detalle privado y enlaces; gerencia mantiene su ámbito autorizado. Directorio, portal y anon no acceden a los nuevos lectores operativos.

El cursor del Registro incluye fecha con microsegundos, origen y UUID; soporta coincidencia de UUID/fecha entre fuentes. Se excluyen los espejos de postventa de leads y se deduplica la misma tarea entre F6 y actividades heredadas.

## Evidencia técnica

| Comprobación | Estado |
| --- | --- |
| SQL transaccional: cierre, resultado, replay, siguiente cita, confirmación/asistencia | PASS |
| SQL: autor/responsable, reasignación, redacción, roles, banderas, perfiles, no-show/cancelación, reprogramación | PASS |
| SQL: G4b y pendientes v2, paginación de citas, espejo, medianoche Lima, citas sin responsable para gerencia | PASS |
| SQL tras review: catálogo real del formulario, detalle heredado obligatorio, tipos del CHECK, nombre vacío, F6 apagada y conteo sin PII/F5 | PASS |
| Estrés de historial: 90.000 eventos, 30.000 por fuente, conteos completos y página limitada | PASS; carga sintética revertida |
| Dos conexiones concurrentes: misma clave / claves distintas | PASS; un único cierre |
| Tipos Supabase del banco migrado | PASS; cinco RPC integradas y verificadas, preservando contratos ajenos |
| Lint, typecheck, 387 archivos / 6.200 pruebas, release-config, push-tasa | PASS; advertencias preexistentes de hooks/coverflow |
| Build y verificación de bundle | PASS |
| E2E Docker local, siete especificaciones | 44 terminados sin fallos finales; tres requirieron retry con carga simultánea |
| Repetición F6 sin suite masiva simultánea | PASS; 13/13, sin retry |
| Repetición F6 tras ajustes finales | PASS; 13/13, sin retry |
| Ficha anterior por perfil: llamada con rechazo/reintento y cita con resultado comercial | PASS; 2/2 en Docker, sin retry en la ejecución final |
| `npm run dup` | FAIL; 1,1 % por copias preexistentes ` 2.*` ajenas a la tarea |
| Mismo análisis de duplicación excluyendo solo esas copias | PASS; 0,43 %, umbral sin alterar de 0,8 % |
| Claude: arquitectura | CHANGES_REQUESTED; decisiones resueltas en la implementación |
| Claude: implementación final | CHANGES_REQUESTED; recomendaciones evaluadas y ajustes verificados por Codex, sin atribuir un PASS nuevo al reviewer |
| `check:scripts` | PASS; requirió permiso local para una prueba que abre HTTP en 127.0.0.1 |
| `seed:preflight`, `test:rls:preflight` | NOT RUN efectivo: ambos terminaron antes de verificar por falta de SUPABASE_URL |
| `gate:realidad`, advisors remotos y ensayo en rama remota | NOT RUN; sin credenciales/destino remoto autorizado para esta tarea |
| Revisión visual del usuario | A cargo de Miguel |

EXPLAIN ANALYZE con gerencia, 90.000 eventos sintéticos y 30.000 tareas adicionales: Registro de 50 filas 332,031 ms; resumen completo 142,642 ms; Citas 4,036 ms. El Registro limita cada fuente antes de resolver detalles; el resumen no calcula identidad ni etapa histórica y resuelve el nombre de cada autor después de agrupar. Las listas vacías no consultan F5. Estas cifras prueban carga de historial, no la distribución productiva de personas y roles.

Evidencia en `app/artifacts/gestiones-clientes-*.log`, `review-gestiones-clientes-*.txt` y `supabase/scripts/gestiones-clientes/`. No se borraron archivos ajenos, ni se cambió el umbral de duplicación.

Los contratos frontend ya verifican `vendedor_id` nullable: la cita sin responsable se admite en gerencia sin filtro, pero no puede aparecer bajo un filtro de analista. El índice parcial por tarea evita un recorrido completo al excluir espejos de cierres F6.

Logs vigentes: `gestiones-clientes-check-reanudado-final.log`, `gestiones-clientes-sql-reanudado.log`, `gestiones-clientes-volumen.log`, `gestiones-clientes-e2e-reanudado.log`, `gestiones-clientes-e2e-perfil.log`, `gestiones-clientes-preflight-scripts.log` y `gestiones-clientes-dup-reanudado-sin-copias.log`. Los logs de la pausa se conservan como evidencia anterior.

## Instalación pendiente

Miguel aprobó la vista y pidió preparar el despliegue. El gate integral en copia limpia está aprobado. Quedan las puertas SQL y la publicación del entorno destino detalladas en el plan de despliegue; la tabla anterior conserva el historial técnico previo a esta preparación.

1. Aprobar el SQL exacto de `20261005224214_crm_resultados_cliente_postventa.sql` y `20261006012208_crm_gestiones_clientes_supervision.sql`.
2. Revalidar contra el esquema destino; la primera migración exige la huella anterior exacta del writer F6. Ensayar en rama autorizada y revisar advisors/permisos.
3. Aplicar ambas migraciones, en ese orden, y comprobar las cinco RPC antes del frontend.
4. Publicar solo mediante el flujo autorizado del proyecto, desde Main verificado contra `avancecorp/main`. No se realizó publicación ni commit en esta tarea.

Si hace falta retirar el frontend nuevo, el bundle anterior sigue admitido por el writer compatible. Conservar los resultados ya guardados; no borrar historial para revertir una pantalla.
