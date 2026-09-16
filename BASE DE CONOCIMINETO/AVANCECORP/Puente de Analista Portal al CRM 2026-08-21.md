# Puente de Analista Portal al CRM — 2026-08-21

## Decisión operativa

Un perfil activo con rol Portal `analista`, todavía sin fila en `crm.equipo`,
es un candidato válido para el CRM. Es la identidad Portal equivalente a un
vendedor CRM y debe reutilizar su misma cuenta Auth.

La regla no incorpora como candidatos a `cliente`, `admin`, `directorio` ni
`superadmin`.

## Flujo de autoridad

1. Gerencia prepara el alta desde **Nuevo usuario**. Si el correo ya existe
   como Analista Portal, el CRM lo deja disponible en el directorio.
2. Superadmin asigna el rol CRM **Vendedor**. La membresía nace inactiva y sin
   supervisor.
3. Gerencia asigna el supervisor y activa la membresía.

Este orden conserva la separación establecida en
[[Configuración operativa CRM 2026-08-07]].

## Incidente y corrección

El 2026-08-21 el flujo fallaba con “La identidad Auth ya pertenece a otro
perfil Portal”: el buscador y la asignación inicial solo aceptaban el rol
Portal `comercial`, aunque el Portal crea vendedores como `analista`.

La migración `20260821212628_crm_admision_analista_portal_como_candidato`
admite únicamente `analista` en el buscador, directorio, edición operativa y
primera asignación de rol CRM. Complementa el precedente documentado en
[[El portal llamaba a una puerta cerrada 2026-08-21]].

## Corrección de validación del correo

El primer despliegue del puente dejó `\\.` en la expresión regular SQL. Con
`standard_conforming_strings` activo ese escape doble rechazaba correos válidos
y producía `Correo invalido`, aunque Gerencia sí estuviera autorizada. La
migración `20260821214502_crm_corregir_validacion_correo_candidato` usa `[.]`
para expresar el punto literal sin ambigüedad.

## Decisión de credenciales CRM

Para una identidad nueva creada exclusivamente desde el CRM, la contraseña
inicial y permanente será el documento de identidad normalizado, conservando
ceros iniciales. El alta no debe enviar correos de recuperación o definición de
clave y el CRM no tendrá una ruta para establecer ni cambiar contraseña.

Esta decisión está limitada al CRM. No se deben modificar el Portal, sus rutas,
sus plantillas de correo, su configuración Auth ni las credenciales de sus
usuarios. Cuando el CRM reutilice una identidad Portal existente —por ejemplo,
un `analista`— conservará su contraseña actual; no se sustituirá por el
documento.

La pertenencia al CRM se expresa mediante el perfil `comercial`, la membresía
en `crm.equipo` y metadatos de origen escritos por el servidor. No existe una
vinculación de una identidad Supabase Auth a un dominio web específico dentro
del proyecto compartido. El acceso efectivo debe seguir protegido por las
reglas de autorización del CRM.

## Implementación y despliegue de credenciales

El 2026-08-21 quedó desplegada la Edge `crm-usuarios` versión **5** con JWT
obligatorio. Las identidades nuevas exclusivas del CRM se crean confirmadas,
sin correo, con el documento normalizado como contraseña exacta y con
`app_metadata.origen_app = 'crm'` escrito por el servidor. Si la identidad ya
existe en el Portal, la Edge la reutiliza sin mutar Auth ni su contraseña.

La migración productiva
`20260821223019_crm_eliminar_recuperacion_credenciales` eliminó
`crm.preparar_recuperacion_usuario_fn(uuid, uuid)`. La interfaz publicada en
`crm.miavance.com` es el build `build-20260821T222650651Z`; no contiene botón,
acción, ruta ni enlace de recuperación.

Una reconciliación protegida por conteo exacto actualizó **1** identidad
heredada auditada como exclusiva del CRM. Otras **4** identidades comerciales
sin marca de origen CRM quedaron intactas. No se cambió el Portal, su
configuración Auth, sus plantillas, sus rutas ni las credenciales de sus
usuarios.

## Alta completa de vendedores por Gerencia

El segundo incidente del 2026-08-21 reveló un callejón sin salida distinto:
Gerencia podía crear una identidad exclusiva del CRM, pero la operación solo
dejaba el perfil en `pendiente_rol`, sin fila en `crm.equipo`. La interfaz no
mostraba Jerarquía ni Activación sin esa fila y Gerencia tampoco gobierna roles.
Auth aceptaba la contraseña, pero `crm.mi_acceso_fn()` respondía `no_enrolado`.

La migración productiva
`20260821233241_crm_alta_vendedor_completa_gerencia` incorpora
`crm.registrar_vendedor_usuario_fn(...)`. Para una identidad con perfil
`comercial` y `auth.users.raw_app_meta_data.origen_app = 'crm'`, Gerencia crea
o completa en una sola transacción el rol fijo `vendedor`, el Supervisor activo
obligatorio y la membresía activa. No recibe un rol como parámetro y no concede
a Gerencia administración general de roles. La autoridad se revalida dentro
del candado, el documento de un perfil existente debe coincidir y los reintentos
comprueban que perfil, Auth y membresía continúen vigentes.

Las identidades compartidas con el Portal retornan `candidato_existente` sin
mutar perfil, Auth, contraseña, membresía ni auditoría. Conservan el flujo de
autoridad de tres pasos documentado arriba. También se retiró la edición de
tipo y número de documento desde el CRM: cambiar el documento visible sin una
operación Auth atómica rompería la regla «contraseña = documento».

La Edge `crm-usuarios` versión **6** y el build Hostinger
`build-20260821T233409404Z` quedaron publicados con JWT obligatorio. Las altas
nuevas exigen Supervisor y terminan listas para iniciar sesión; los candidatos
CRM heredados muestran **Alta pendiente → Completar alta**. No hay correo ni
ruta de recuperación. El Portal no fue modificado ni desplegado.

El caso real de Alan confirmó la causa: Auth registró un ingreso correcto el
2026-08-21 a las 23:01:39 UTC con CE `001237707`, pero no existía membresía CRM.
Sigue pendiente hasta que Gerencia elija explícitamente entre los Supervisores
activos; no se asigna una jerarquía por defecto.
