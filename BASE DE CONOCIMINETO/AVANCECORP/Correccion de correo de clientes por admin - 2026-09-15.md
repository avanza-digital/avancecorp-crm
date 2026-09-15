# Corrección de correo de clientes por admin — 15/09/2026

Relacionado: [[Arquitectura del portal]], [[Clave temporal = DNI]],
[[Main unico - sincronizacion y publicacion 2026-09-04]].

Miguel necesita corregir el correo de **clientes** desde su cuenta admin y que
el correo nuevo permita iniciar sesión de inmediato con la misma contraseña.
Autorizó expresamente instalar el SQL `20260915173423` y el banco temporal de
US$0,01344/h, a eliminar al terminar.

Admin y superadmin activos pueden corregirlo desde Clientes → Editar →
Correo y motivo. La Edge verifica la sesión y el rol vigente. Auth, identidad
email, perfil y acuse de auditoría se confirman juntos. El trigger es diferido:
GoTrue escribe email y metadatos en sentencias separadas dentro de una misma
transacción. La comprobación inmediata fallaba en Auth real; el ensayo detectó
el problema antes de publicar.

La ruta directa de escritura del correo del perfil queda protegida. Un correo
que ya pertenece a otra cuenta se rechaza. La corrección no cambia la contraseña
ni autoriza modificar cuentas del equipo interno.

Pruebas locales: Auth real (9 grupos), interfaz del portal (5 pruebas), CRM
(3600 pruebas y 190 E2E aprobadas). Dos pruebas globales del portal ya estaban
desactualizadas. La revisión independiente no produjo un dictamen válido.
Resultado remoto y publicación: ver el acta en
`CRM-Avance-Corp/supabase/scripts/correo-admin/`.
