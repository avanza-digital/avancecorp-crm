# Cierre de Mi cartera operativa — 2026-08-25

**Estado: PREVIEW PUBLICADA Y VERIFICADA · PRODUCCIÓN FRONTEND SIN CAMBIOS.** Se retomó el plan de
nueve pasos de la sesión interrumpida y se cerró el trabajo funcional. La migración autorizada se
aplicó y verificó en producción el 25/08/2026; el frontend quedó en una preview pública e inmutable,
sin promover el build a `crm.miavance.com`.

Continúa [[Mi cartera por meses]] y actualiza el antiguo [[Handoff Cartera 2026-07-21]].

## Qué quedó resuelto

- **Ámbito por rol coherente de punta a punta.** Vendedor opera su cartera; Supervisor consulta y
  gestiona la cartera de su equipo porque el frontend ahora refleja `private.vendedor_ids_visibles`;
  Gerencia conserva alcance global. Un cliente inactivo se puede consultar, pero no mutar.
- **Éxito solo después del servidor.** Crear una gestión de cliente y cerrar/anular una tarea ya no
  cierran el diálogo ni anuncian éxito con una escritura optimista pendiente. El formulario espera
  la confirmación remota; ante rechazo queda abierto y reintentable, y el store revierte/resincroniza.
- **Cierre de reuniones completo y atómico.** La llamada de siete parámetros conserva
  `resultado_reunion`, `motivo_no_realizada`, detalle, `perfil_id`, timeline del cliente y siguiente
  acción dentro de una sola RPC. Un rechazo no deja actividad, cierre ni tarea siguiente parciales.
- **Renovaciones y upgrades conciliados.** Capital renovado y adicional permanecen separados; una
  renovación enlaza el contrato de origen y un upgrade solo es elegible cuando cumple su regla. El
  conteo mensual deduplica por cliente y PEN/USD nunca se suman.
- **Reasignación sin pérdida de agenda.** Cuando cambia el asesor del cliente, todas sus tareas
  pendientes conservan identidad y pasan al nuevo responsable; las tareas ya cerradas y el timeline
  mantienen la atribución histórica del asesor que realmente hizo la gestión.

## Estado de base de datos

Lectura de producción al 25/08/2026:

- `20260824231133_crm_gestion_clientes_renovaciones_conversion.sql`: aplicada.
- `20260824233619_crm_cumplimiento_cartera_compatible.sql`: aplicada.
- `20260825005519_crm_cerrar_reunion_cliente_clasificada.sql`: **aplicada y verificada**.

La migración aplicada sustituye de forma unívoca la firma de cinco parámetros de
`crm.cerrar_tarea` por la de siete, conserva compatibilidad con el bundle anterior mediante valores
por defecto, usa `SECURITY DEFINER` con `search_path = ''`, revoca `PUBLIC`/`anon` y concede
`EXECUTE` únicamente a `authenticated` y `service_role`.

Rollback preparado en
`CRM-Avance-Corp/supabase/scripts/rollback-crm-cerrar-reunion-clasificada.sql`. Restaura la firma de
cinco parámetros de `20260824231133`; no borra ni reescribe actividades o clasificaciones ya
guardadas, pero los cierres futuros vuelven a la clasificación genérica (`sin_clasificar`/`otro`).

## Evidencia de verificación

- Producción: `dry-run` aislado contra el historial remoto propuso únicamente
  `20260825005519_crm_cerrar_reunion_cliente_clasificada.sql`; el push registró esa misma versión y
  nombre en `supabase_migrations.schema_migrations`.
- Smoke estructural de producción: firma nueva presente, firma anterior ausente, siete argumentos,
  cinco valores por defecto, `SECURITY DEFINER`, `search_path = ''`, `anon` sin `EXECUTE` y roles
  `authenticated`/`service_role` con `EXECUTE`. El cuerpo conserva timeline, resultado, motivo y
  siguiente acción. La llamada sin sesión devolvió el rechazo esperado antes de escribir datos.
- El asesor no reportó problemas de rendimiento propios de `crm.cerrar_tarea`. Su aviso de
  `SECURITY DEFINER` accesible a `authenticated` es intencional: la RPC es el punto de escritura de
  usuarios autenticados y valida dentro de la función `auth.uid()`, rol y ámbito; `anon` permanece
  revocado.
- Clon local desechable construido desde el esquema de producción.
- Migración aplicada con preflight y postflight verdes.
- Ciclo **rollback → reaplicación** verde en el clon.
- Gate SQL/RLS: `GESTION_CLIENTES_RENOVACIONES_OK`, incluida reasignación de cartera con dos tareas
  pendientes, conteo estable y atribución histórica intacta.
- Gate contractual autocontenido
  `CRM-Avance-Corp/supabase/scripts/test-crear-contrato-cartera.sql`:
  `CREAR_CONTRATO_CARTERA_OK`. Cubre contrato nuevo, fecha habilitante de renovación, puente exacto
  de capital, traslado de cuotas pendientes/vencidas, cuota pagada intacta, enlace entre contratos,
  doble renovación rechazada, upgrade elegible/no elegible, deduplicación cliente-mes, PEN/USD y
  rollback posterior a una escritura parcial simulada.
- Gates complementarios repetidos en el clon: `PERIODO_COMERCIAL_CONTRATOS_OK`,
  `CARTERA_KEYSET_TX_OK` y `TAREAS_TX_OK`; este último verifica RLS real de Vendedor, Supervisor y
  Gerencia, propagación de tareas al reasignar un lead y cancelación de pendientes al descartarlo.
- Datos históricos auditados: 48 operaciones de cartera, 29 conversiones cliente-mes, cero enlaces
  comerciales inválidos y cero capital adicional inventado en el backfill.
- Unitarias: **173 archivos / 2.271 pruebas verdes**.
- Navegador E2E completo, secuencial: **107 pasaron / 26 omitidas deliberadamente / 0 fallas**.
  Las omitidas corresponden a las pantallas retiradas de Clientes y Contratos.
- Typecheck, build de producción (3.109 módulos), lint, verificación de bundle y gate de duplicación:
  verdes.
- Revisión funcional por roles en E2E: Vendedor, Supervisor, Gerencia y Directorio ven el ámbito y
  las acciones esperadas; la demo bloquea escrituras de forma explícita.

## Candidato de publicación

- Rama remota: `release/mi-cartera-20260824`.
- Commit validado: `4e562f737e910f36ea0dc8d17914d0b568ffc8b2`.
- Preview canónica:
  <https://avancecorp-crm-preview-9hdvmram1-avancecorp26-1551s-projects.vercel.app>
- Deployment Vercel: `dpl_3Z99ckf67XvCJLFHq97jLgzCSFTr`, objetivo **preview**, estado `READY`.
- Build ID del candidato: `build-20260825T183241110Z`.
- El proyecto Vercel es aislado y se llama `avancecorp-crm-preview`; no tiene dominio real asociado.
  Su protección SSO se desactivó para que Miguel pueda abrir el enlace, pero conserva `robots.txt`
  y `X-Robots-Tag: noindex`.
- El primer despliegue de un proyecto nuevo fue etiquetado automáticamente por Vercel como
  producción **solo dentro de ese proyecto preview**. Se generó después el deployment canónico con
  objetivo `preview`; ninguno alteró Hostinger, `crm.miavance.com` ni su dominio.
- HTTP público: raíz `200`, ruta interna reescrita a `index.html` con `200` y `version.json` válido.
- QA visual de la preview: escritorio `1376×871` y móvil `390×844`, sin desborde horizontal y sin
  errores ni avisos de consola. La pestaña quedó abierta en Chrome para revisión.
- El build publicable no contiene modo demo por diseño (`DEMO_HABILITADO` exige `import.meta.env.DEV`).
  Por eso la preview se verificó hasta el login; el smoke autenticado con cuentas reales queda para
  la revisión de Miguel. El comportamiento por roles del mismo commit sí quedó cubierto por el E2E.
- Producción seguía en `build-20260825T005045176Z` después de publicar la preview.

## Prueba visual corta para Miguel

1. Entrar como **Vendedor** a Mi cartera; confirmar que ve su cartera, puede abrir detalle y que un
   cliente inactivo no ofrece acciones de escritura.
2. Entrar como **Supervisor**; confirmar que aparecen clientes de Vendedor Uno y Vendedor Dos y que
   puede usar Gestionar, + Contrato y Upgrade sobre el equipo.
3. Entrar como **Gerencia**; confirmar alcance global y lectura completa.
4. Crear una gestión de cliente y simular red lenta: el diálogo debe permanecer abierto hasta la
   confirmación; con error debe seguir abierto, volver a habilitar “Agendar gestión” y no mostrar
   un toast de éxito.
5. Cerrar una reunión realizada con resultado **Interesado** y siguiente acción; verificar en agenda
   y timeline que persisten resultado, detalle y tarea siguiente.
6. Cancelar otra reunión con `cancelada_cliente`; verificar que el motivo exacto queda visible y que
   no se crea una acción parcial si el servidor rechaza.
7. Revisar una renovación y un upgrade del mes: capital renovado/adicional separados y tarjetas PEN
   y USD independientes.
8. Desde la administración, reasignar un cliente que tenga dos tareas pendientes: el nuevo asesor
   debe ver ambas en Hoy/Agenda, el anterior debe dejar de verlas y el historial cerrado debe seguir
   mostrando a quien hizo cada gestión.
9. Repetir en móvil de 390 px: la tabla/tarjetas no deben producir scroll horizontal de la página.

## Acciones que aún requieren permiso explícito

1. Completar el smoke autenticado de la preview con las cuentas reales de Vendedor, Supervisor y
   Gerencia.
2. Promover el frontend a producción en Hostinger únicamente cuando Miguel lo autorice después de
   revisar la preview.
