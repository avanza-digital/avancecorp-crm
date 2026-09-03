---
tags: [crm, roles, autorizacion, leads, conversion]
actualizado: 2026-09-03
estado: desarrollado-no-desplegado
---

# Capacidad única de conversión de leads (2026-09-03)

Relacionado con [[Acceso y roles del CRM]], [[Las tres definiciones de autoridad (2026-08-29)]] y [[Rol Analista]].

## Incidente

Los usuarios nuevos creados desde Gerencia son correctamente **Comerciales del
Portal** (`public.perfiles.rol='comercial'`) y **Vendedores del CRM**
(`crm.equipo.rol_crm='vendedor'`). Sin embargo, el frontend y la Edge Function
de conversión conservaban una allowlist histórica del rol Portal
(`analista/admin/superadmin`). Por eso un analista nuevo podía trabajar sus
leads, pero al convertir veía «El alta del cliente la registra el analista».

La comprobación de producción en solo lectura encontró 3 usuarios activos con
la combinación `comercial + vendedor` y 69 leads abiertos en conjunto. No era
un defecto del alta ni requería cambiar sus roles o recrear sus cuentas.

## Decisión duradera

La única pregunta de autoridad para convertir es
`private.puede_gestionar_contratos_crm()`:

- `true`: miembro CRM activo con rol Vendedor, Supervisor o Gerencia y perfil
  activo;
- `false`: Coordinador, Directorio, no enrolado, revocado o combinación de
  autoridades inválida;
- el rol Portal por sí solo nunca concede esta capacidad.

`crm.mi_acceso_fn()` publica el resultado como `puede_contratar`. El frontend
solo consume ese booleano y la Edge Function lo consulta con el JWT del caller,
comprobando que el `perfil_id` devuelto coincida con la sesión verificada. Los
cuatro RPC de conversión también llaman al mismo helper. Así, un cambio futuro
de roles se hace una vez en PostgreSQL y no en listas duplicadas.

La pantalla «Mi cartera» reutiliza `puede_contratar` para «Nuevo cliente». Por
eso `crear-cliente` también quedó alineada: conserva `admin`, `superadmin`,
`analista` y `operaciones` como compatibilidad explícita del Portal, y admite a
los miembros CRM habilitados por la fuente canónica. Un `comercial + vendedor`
se autoasigna como asesor; Supervisión y Gerencia crean sin apropiarse de la
cartera. Una revocación CRM explícita falla cerrada incluso si subsiste un rol
Portal legacy.

No se usa `private.puede_registrar_ventas()` para esta operación: esa capacidad
también admite autoridades del Portal sin membresía CRM, mientras que convertir
un lead exige pertenecer activamente al equipo y conservar su ámbito comercial.

## Implementación y publicación

- Migración: `20260903215149_crm_capacidad_conversion_unica.sql`.
- Edges: `crm-convertir-lead` y `crear-cliente` consultan
  `crm.mi_acceso_fn()` con la sesión del usuario; `service_role` queda reservado
  para los efectos administrativos que ocurren después de autorizar.
- Frontend: `interpretarMiAcceso()` exige `puede_contratar` y deja de deducirlo
  desde `rol_portal`.
- Regresión explícita: `comercial + vendedor + activo` puede convertir;
  revocados y accesos globales fallan cerrados.

La revisión `auditor-rls` terminó en **GO**, sin hallazgos críticos, altos ni
medios. El gate automatizado final quedó verde en frontend, Edge, chequeo Deno
con lock congelado, tipos, lint y build.

Orden obligatorio de publicación: **migración → ambas Edge Functions → frontend**.
El estado al 2026-09-03 es **desarrollado y ensayado localmente, aún no
desplegado en producción**.
