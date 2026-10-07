# Coordinación - reparto libre controlado por Gerencia (2026-10-07)

Relacionado: [[Acceso y roles del CRM]], [[Derivaciones de Rosa - diagnostico de cola vacia 2026-09-10]], [[Inicio]].

**APLICADO Y PUBLICADO el 07/10/2026. Permiso ACTIVADO para todo el rol Coordinadora.** Se confirmó por lectura en producción que Rosa recibe `reparto_libre = true`.

## Decisión y uso

Miguel pidió el permiso para todo el rol, con un botón de Gerencia. Se encuentra en **Administración → Configuración → Reparto libre de Coordinación**. La pantalla real de Gerencia muestra **Activado** y «Desactivar reparto libre».

Encendido permite derivar Landing/Formulario a cualquier supervisor activo, incluso sin turno. Apagado restaura la agenda obligatoria. No concede otros privilegios de administrador; conserva No Insista, vigencia del destino, identidad real, auditoría y exclusión de leads ya asignados. Las revisiones evitan sobrescribir cambios concurrentes (PT409).

El servidor comprueba el control en cada reparto. Al recuperar foco, la pantalla refresca el permiso sin perder selecciones ni contadores y sin intervenir durante un envío. La revocación rige para llamadas posteriores al commit; una sentencia ya iniciada conserva su fotografía.

## Publicación efectiva

- Autorizaciones: `$release-crm` y aprobación separada para probar/aplicar la migración con rama Supabase temporal a US$0,01344/h.
- SQL: `20261007143121_crm_reparto_libre_coordinacion_configurable.sql`, mediante `merge_branch`. Historial previo intacto; postflight de siete funciones, ACL/RLS y estado ON PASS. Las 22 Edge Functions permanecen idénticas.
- PR #216, commit publicado `e511d30504f24045aa28230a2d2eb03891bdf967`, copia limpia y Main/remoto iguales antes de construir y subir.
- ZIP `crm-20261007T152928Z-e511d30504f2.zip`; SHA-256 `44e46cc985a251a6d51d04bfd5b942e85443a2504fd7d9bab063f1df63846cf9`.
- Build `build-20261007T152927260Z`. El ZIP anterior `crm-20261007T054815Z-8e7524ed2a3f.zip` se conserva como recuperación.
- Rama temporal eliminada, ausencia confirmada y credenciales locales retiradas. No se derivaron leads reales para probar.

## Verificación y límites

Check limpio PASS: 6.333 pruebas, tipos/lint/build/bundle y duplicación 0,44 %. E2E Docker: 49 PASS. Matriz SQL local/remota y concurrencia real PASS. Revisión Claude evaluada y observación sobre recarga corregida.

La matriz HTTP general obtuvo 2.845 comprobaciones correctas y cinco fallos de preparación del banco: bandera de potencial encendida y ACL implícito de propietario en tres tablas B7. Se reconstruyó el seed y se repitieron los cuatro bloques originales afectados: 279 aserciones PASS. El SQL de la funcionalidad no cambió. Se conserva la evidencia del primer fallo; no se presenta como una corrida íntegramente verde.

Los nuevos avisos de advisors corresponden a dos puertas autenticadas con autorización interna de Gerencia y una tabla singleton sin acceso directo. Las negativas HTTP dieron 42501 sin caída del motor. La incidencia local previa de Supabase PG 17.6.1.105 no se provocó en producción; no se relajaron grants ni extensiones. `gate:realidad` completo no ejecutado: se cotejaron directamente los contratos vivos de esta entrega.

Acta vigente: `CRM-Avance-Corp/supabase/scripts/reparto-libre/PUBLICACION.md` (incluye smoke HTTP y límites de imágenes/CDN). Evidencia en `output/reparto-libre-20261007/`. Para recuperar la operación normal por turnos, Gerencia apaga el control; no se elimina la tabla ni su auditoría.
