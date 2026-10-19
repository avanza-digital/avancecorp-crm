# Fase 1: diagnóstico y revisión Codex

Fecha de lectura: 19/10/2026 06:07 UTC. Consultas solo lectura; se guardan agregados y contratos, no datos personales.

1. **Política:** Miguel aprobó iniciar el plan que incluye todas las primeras conversiones pendientes, antiguas y nuevas. La fecha de activación no constituye una exención por antigüedad.
2. **Censo vigente:** 1.964 leads operativos pendientes: 1.886 incompletos y 78 ambiguos bajo el evaluador conservador. Esto mide suficiencia del registro para la regla; no prueba que no hayan sido atendidos. Antes de la instalación no existe el sello de actividad de la nueva tabla, por lo que las entrevistas históricas no se acreditan automáticamente.
3. **Contratos:** seis precondiciones de funciones productivas coinciden exactamente con las huellas esperadas. No se sustituirán por versiones antiguas por la fuerza.
4. **Rutas de conversión:** preparación de identidad (`preparar_persona_lead_inversion_fn`), inserción de solicitud preparada/confirmada (trigger `recorrido_solicitud_guard`), acceso Auth nuevo (`acceso_inversion_fn`), confirmación (`confirmar_inversion_revisada_fn`), UPDATE de etapa (`conversion_lead_con_inversion`) e INSERT terminal (`recorrido_insert_convertido_guard`). Los guards ya creados se reutilizan; se unifica su alcance. Se comprobarán con SQL/HTTP reales, incluidos writers internos y caminos de recuperación.
5. **Dependencias/entorno:** trigger productivo `trg_leads_conversion_con_inversion` habilitado y asociado al UPDATE de etapa. No se demuestra un bypass por ausencia de trigger. Base de recorrido y RPC aún ausentes. Frontend actual tolera ausencia y mantiene la guía oculta. Stack Docker propio disponible. Dos ramas hosted existentes pertenecen a otros trabajos y no se reutilizan ni borran.
6. **Revisión Codex:** corregida la confusión entre entrega técnica y objetivo operativo; histórico no equivale a exento. No se añade un requisito de llamada/contacto. La migración será aditiva; se preservan las ocho anteriores y los formatos de API publicados. No se acepta por defecto un costo ni se inventa aprobación del SQL final.

## Precondiciones productivas comprobadas

| Firma | Huella MD5 esperada y encontrada |
|---|---|
| crm.eliminar_lead_error_carga(uuid,text) | 15ce9327e21306ec9682552815936e71 |
| crm.cerrar_reunion_v3(uuid,uuid,text,text,text,text,jsonb,numeric,text) | c0fa9a8ebb04cf84bc41155d4a318e30 |
| crm.preparar_persona_lead_inversion_fn(uuid,text,text,text) | b40dded8a923dcd02f028b24bc4de94e |
| crm.confirmar_inversion_revisada_fn(uuid,integer) | 68828d0a443160310a3fb2fd82cd7041 |
| crm.acceso_inversion_fn(uuid,text,jsonb) | 38229cbb9fde4d9b5e23ee55ca6e6784 |
| private.conversion_lead_con_inversion() | 0edf5180578781961aacbf0e78df242e |

Estas seis huellas corresponden a contratos preexistentes, no a las funciones que crean las primeras migraciones del propio paquete. Los preflights de cada migración verifican las dependencias intermedias en orden durante el replay.

## Límites

PASS documental, no PASS de implementación ni de producción. Histórico ambiguo requiere tratar hechos reales; no se resuelve retrofechando sellos ni convirtiendo 78 registros a completos. La capacitación debe explicar las vías de registro disponibles antes de exigir.

Las pruebas actuales que esperan exención de antiguos deben cambiar a rechazos reales y corrección mediante el cierre habitual. Se conserva comprobación de borradores abiertos antes de activar y se verifica que no se pierdan sus datos. Observación/apagado conservan reversibilidad explícita.

