---
tags: [crm, acceso-avance, incidente, produccion]
actualizado: 2026-10-03
estado: acceso-creado-solicitud-confirmada
---

# Primer acceso Avance — correo de solicitud corregido (03/10)

Relacionado: [[Primer acceso Avance - continuidad y revision UX (2026-09-22)]], [[Correccion de correo de clientes por admin - 2026-09-15]].

Al crear el acceso desde un lead, el CRM mostró un correo en la ficha y otro en la solicitud. Miguel confirmó que el correo correcto era el de la ficha. La consulta de solo lectura a producción halló una solicitud `preparada`, revisión 0, con reserva Auth en estado `reclamado`; no había usuario Auth ni perfil creado con esa reserva. El correo de la solicitud ya pertenecía a **otro cliente activo**, por lo que continuar con ese correo era incorrecto. El correo de la ficha no pertenecía a ningún usuario Auth, identidad ni perfil.

`Cancelar solicitud` no desbloqueaba el caso: la función vigente exige terminar el acceso cuando existe un claim pendiente. La corrección ordinaria de la solicitud también rechaza cambios de `alta_portal` después de reservar el claim. Se reutilizó la recuperación puntual previamente documentada en `CRM-Avance-Corp/supabase/scripts/conversion-inversion/recuperar-correo-acceso-20260925.sql`, adaptada solo a los identificadores de este caso y guardada como `CRM-Avance-Corp/supabase/scripts/conversion-inversion/recuperar-correo-acceso-20261003.sql`. Miguel pidió expresamente aplicarla de inmediato mientras atendía al cliente.

El SQL se ejecutó en producción el 03/10. Sus guardas comprobaron estado, revisión, claim, lease vencido, ausencia de usuario Auth con ese claim, disponibilidad del correo correcto y huella original. En una transacción cambió únicamente el correo de `alta_portal` al del lead, subió la revisión a 1, actualizó la huella de la reserva y registró la corrección en `crm.inversion_solicitud_correcciones`. Conservó el claim y el token de recuperación. El postflight de solo lectura confirmó: solicitud preparada, correo igual al de la ficha, nueva huella consistente, una corrección auditada, ningún Auth con el claim; la cuenta del otro cliente seguía presente. Se indicó a Miguel cerrar y reabrir «Crear cliente» para continuar la solicitud actual. Una consulta posterior de solo lectura confirmó **solicitud `confirmada`, acceso `enlazado` y un usuario Auth con el claim de esta solicitud**; el alta quedó completada por la interfaz.

Revisión independiente: `scripts/claude-review` no completó el review (exit 1), por lo que no se atribuye un dictamen. El postflight SQL pasó; no se ejecutó un E2E sobre producción. El arreglo general para evitar futuros bloqueos ya existe, pero está pendiente de instalar; ver [[Conversion - sincronizacion del correo antes de Auth (2026-09-25)]].
