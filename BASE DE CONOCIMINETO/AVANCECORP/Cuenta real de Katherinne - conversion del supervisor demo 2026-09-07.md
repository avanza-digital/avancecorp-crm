---
tags: [crm, cuenta, acceso, supervisor]
actualizado: 2026-09-07
estado: produccion
---

# Cuenta real de Katherinne — conversión del supervisor demo

Miguel pidió reutilizar la cuenta **SUPERVISOR CRM (DEMO)** para una persona real y proporcionó sus datos. La cuenta ahora pertenece a **KATHERINNE DE LA CRUZ**, con correo `katherinne@groupmascapital.com`.

- Se conservó el UUID `3a4f3c2a-271d-478c-8625-16225e932c46` y el rol CRM `supervisor` (rol Portal `comercial`).
- Se actualizaron nombre, nombres, apellidos, DNI, teléfono y correo en el perfil. El correo de Auth y su identidad email quedaron sincronizados mediante la Admin API.
- Perfil y membresía CRM activos; bloqueo Auth retirado. No se asignó un nuevo superior ni se cambiaron subordinados.
- No se modificó la contraseña ni se enviaron correos. Cambiar el DNI del perfil no cambia automáticamente la clave de una cuenta existente.
- Verificación final: datos guardados, ambos flags activos, correo confirmado e identidad email coherente; Admin API accesible. No se hizo una prueba de ingreso con contraseña.

**Esta cuenta ya no es de pruebas.** Las referencias al antiguo correo `avancecorp26+crm-supervisor@gmail.com` y al supervisor demo son históricas. Los guiones `cerrar-sesion-demos-crm.sql` y `reabrir-cuentas-demo-crm.sql` todavía contienen su UUID, pero sus precondiciones de cuenta demo rechazan la cuenta convertida. No deben usarse como operación vigente sobre ella.

## Incidente encontrado durante la conversión

El bloqueo anterior guardaba `auth.users.banned_until = 'infinity'`, aplicado por el guion histórico de cierre. `auth.admin.getUserById` respondía 500. Se sustituyó únicamente el bloqueo de esta cuenta por una fecha futura finita, manteniendo la suspensión; la misma lectura pasó de 500 a correcta. Después se actualizó la identidad por Admin API y, al terminar el perfil y la membresía, se retiró el bloqueo mediante `ban_duration: 'none'`. No se alteraron las otras cuentas demo.

La respuesta inmediata de `updateUserById` no permitió verificar las identidades relacionadas; la lectura posterior de `auth.identities` confirmó que el correo sí se había sincronizado.

Relacionadas: [[Acceso y roles del CRM]] · [[Offboarding seguro del CRM (P04)]] · [[Cuenta piloto CRM Miguel]].
