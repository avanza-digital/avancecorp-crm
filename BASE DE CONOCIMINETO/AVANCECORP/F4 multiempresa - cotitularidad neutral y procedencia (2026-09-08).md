# F4 — cotitularidad neutral y procedencia

Continúa [[F4 multiempresa - historicos recuperables y commits (2026-09-08)]] y
[[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].
El bloque de mantenimiento/escala quedó en `ccba953`, en la rama
`codex/f4-cierre` del worktree `/private/tmp/avancecorp-f4-desarrollo`.

## Estado actualizado — 08/09/2026

La implementación y los 15 grupos SQL de cotitularidad ya están conformes en
el banco aislado. Véase [[F4 multiempresa - cotitulares y correccion versionada (2026-09-08)]].
El texto siguiente conserva el diagnóstico y diseño anteriores; G4 sigue abierto.

## Diagnóstico anterior y requisito previo

La cotitularidad neutral todavía no está implementada. El contrato y su snapshot
conservan los cotitulares documentales; `crm.inversion_titulares` recibe únicamente
el principal por el enlace F4 actual. No confundir ese registro con un vínculo
neutral completo.

La inspección del esquema sintético importado encontró que
`public._sync_contrato_titulares(uuid,jsonb)` es SECURITY DEFINER sin autorización
interna y tenía EXECUTE para anon/authenticated/service_role. Una llamada SQL
sin sesión pudo sustituir cotitulares de un contrato ficticio aún no congelado;
el ensayo terminó con rollback. Es evidencia del banco basado en el esquema
capturado, no una nueva prueba contra producción.

El módulo `09-cotitular-puerta.sql` prepara la revocación de esos permisos y PUBLIC,
con guarda de cuerpo/propietario. Conserva cuerpo, PDF y llamadas internas de
`crear_contrato`/`actualizar_contrato`, que autorizan antes de llamar como postgres.
Siete grupos SQL en copia pasaron: tres roles directos rechazados, alta y
corrección autorizadas, puertas canónicas sin sesión rechazadas y bloqueo PDF.
Revisión independiente evaluada y corrección instalada únicamente en el banco
sintético. Se añadió postcondición dentro del SQL y dos pruebas de privilegios
inesperados (nueve grupos SQL en total), más tres denegaciones HTTP reales.
El verificador conserva el cierre ACL como requisito permanente. No hubo
despliegue productivo. Evidencia y evaluación en
`supabase/scripts/evidencia-f4/auditoria-cotitular-puerta-2026-09-08/`.

## Propuesta para construir después del prerrequisito

Esta sección es diseño pendiente de revisión e implementación, no descripción
de funcionalidad instalada.

- Vincular solamente identidades ya verificadas y canónicas. Un documento con
  formato válido no verifica por sí solo a una persona. Se consultó a Miguel
  sobre casos no verificados; sin una decisión distinta se mantienen pendientes.
- Separar procedencia documental de la fila de titularidad. La fusión F3 puede
  mover o eliminar un titular duplicado; una FK obligatoria a ese ID rompería
  la fusión o perdería la procedencia.
- Registrar de forma inmutable la fuente documental concreta, inversión,
  identidad e identificador reconocidos al vincular, actor y huella. La persona
  de origen permanece como evidencia; su canónica se obtiene por el reconocedor
  vigente. Nunca volver a asignar a otra persona porque se reutilizó un documento
  corregido. Para el primer enlace histórico, documentos con propietarios
  históricos distintos requieren revisión.
- La integración nueva debe ocurrir después de reservar el snapshot/PDF, dentro
  de la misma transacción del alta. Así la fuente documental ya está congelada.
  La RPC `crm.crear_contrato_con_cuenta_pdf_v2` es el punto común usado también
  por `crm.confirmar_inversion_fn`; sus replays ya autorizan y bloquean la fuente.
- Conservar una sola pareja inversión/persona y un principal. Dos entradas
  documentales de la misma persona no duplican titularidad ni Capital; si la
  persona coincide con el principal no se degrada su rol.
- No crear Auth, perfil, responsable, lead, permiso Portal/documental ni otro
  cálculo financiero por ser cotitular. Las tablas neutrales actuales permiten
  lectura directa solo a Gerencia; la búsqueda de lectores no encontró políticas
  ni vistas que concedieran permisos por pertenecer a `inversion_titulares`.
- No editar contenido del PDF. Cualquier incorporación de texto sigue requiriendo
  mostrar texto/ubicación y aprobación previa de Miguel.

Quedan por resolver y ensayar en el diseño: lectores del estado pendiente,
reanudación tras verificación, históricos sin snapshot congelado, deriva de fuente
bajo corrección privilegiada y carreras con fusión/corrección antes de enlazar.
No cerrar G4 con esta nota ni con el cierre ACL del auxiliar.
