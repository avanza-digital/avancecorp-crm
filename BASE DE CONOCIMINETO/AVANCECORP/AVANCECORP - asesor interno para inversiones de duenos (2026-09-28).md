---
tags: [crm, portal, contratos, equipo, ranking, decision]
actualizado: 2026-09-28
estado: aplicado-y-verificado-en-produccion
---

# AVANCECORP: asesor interno para inversiones de dueños y colaboradores (2026-09-28)

✅ **APLICADO EN PRODUCCIÓN el 28/09/2026** por Miguel con `!` (ensayo PASS y luego escritura).
Verificado con lectura en prod: perfil `d0468985-abc8-4d12-bcf2-f6fbc5096de6`, rol Portal
`analista` activo, `crm.equipo` = `supervisor` activo con `supervisor_id` nulo y 0 analistas a
cargo, fuera de `private.roster_metas_vendedores()`, `private.rol_crm` = `supervisor`, usuario
de auth confirmado e identidad creada. Sin DNI. Correo `avancecorp@miavance.com`.

Relacionado con [[Alta directa de clientes cerrada al analista (2026-09-15)]],
[[Como se mide la conversion del asesor]], [[Ranking cartera - publicacion verificada (2026-09-26)]]
y [[Par de identidades Portal-CRM]].

## Pedido de Miguel (28/09/2026)

Que exista un asesor llamado **AVANCECORP** que no es un analista real: agrupa las inversiones
que hacen los propios dueños o colaboradores de alto rango. Internamente **no cuentan para
nadie del área de ventas**. Miguel, con su usuario de admin, debe poder seleccionarlo al cargar
esos contratos.

## Lo que hay en el sistema (leído del código y de la base, no supuesto)

- El selector de analista de **Portal → Clientes** lista los perfiles activos con rol
  `analista`, `admin`, `superadmin` o `comercial` (`public_html/js/admin/clientes.js`,
  `cargarMiembrosAsesores`). Un perfil `analista` activo aparece solo.
- `public.perfiles.id` es llave foránea a `auth.users`: todo perfil necesita usuario de acceso.
- `public.crear_contrato` (la puerta del alta del portal):
  - Si no llega `analista_cierre_id` (el portal no lo manda), la venta queda **a nombre de quien
    la registra**, siempre que esté activo en `crm.equipo`. Hoy los contratos «nuevo» que carga
    Miguel desde el portal quedan a su nombre (gerencia).
  - Una **renovación o upgrade** se atribuye al asesor del cliente, que tiene que ser
    **vendedor o supervisor activo en `crm.equipo`**. Un perfil solo de portal se rechaza.
- `private.validar_supervisor_usuario_crm`: **todo vendedor activo necesita supervisor**. Y con
  supervisor entraría al roster de Metas y Ranking (`private.roster_metas_vendedores`).
- Un **supervisor activo sin supervisor ni analistas** es un estado válido: fuera de Metas y
  Ranking, fuera del reparto de leads (solo ofrece vendedores), sin leads ni conversión. El par
  Portal `analista` ↔ CRM `supervisor` está declarado en `private.pares_autoridad`.
- Gerencia lo ve en «Producción fuera del ranking» (motivo `supervisor`) y su capital **sí suma
  al total de empresa** (decisión D8, 27/08/2026).

## Decisión de implementación

Script `CRM-Avance-Corp/supabase/scripts/avancecorp-identidad-interna.sql`, una sola
transacción con candados nombrados y ensayo (`v_ensayo = true` termina en `raise`):

1. Usuario en `auth.users` + `auth.identities` con contraseña aleatoria que nadie conoce
   (correo `avancecorp@miavance.com`; si hiciera falta entrar, se restablece desde Portal → Equipo).
2. Perfil `AVANCECORP`, rol `analista`, activo, sin documento, cargo «Inversiones internas».
3. `crm.equipo`: rol `supervisor`, activo, `supervisor_id` nulo.

Verificaciones dentro del script: analista activo + supervisor activo sin supervisor; el
predicado exacto de `crear_contrato` lo acepta como dueño; no está en
`private.roster_metas_vendedores()`; `private.rol_crm` lo resuelve como `supervisor`.

**Ensayo en el banco Docker local (28/09):** PASS. Primer intento como `vendedor` sin
supervisor falló por `validar_supervisor_usuario_crm` («Un vendedor CRM activo requiere un
Supervisor activo»); por eso es `supervisor`.

## Cómo se aplicó

Miguel, con `!`, desde `CRM-Avance-Corp/` (el script queda en modo ensayo; volver a
correrlo muere en el CANDADO 1):

```
supabase db query --linked --file supabase/scripts/avancecorp-identidad-interna.sql
```

Primera pasada con `v_ensayo = true` (no escribe); segunda con `v_ensayo = false`.

## Cómo se usa después

- Portal → Clientes → alta o edición del cliente → analista **AVANCECORP**.
- Cargar la inversión **desde el CRM** (ficha del cliente → Nueva inversión): el contrato queda a
  nombre de AVANCECORP. Renovaciones y upgrades del portal también.

## Pendiente de decisión (Miguel)

1. Los contratos «nuevo» cargados desde **Portal → Contratos** siguen a nombre de quien registra.
   Opciones: cargarlos desde el CRM, o cambiar la regla para que el cierre vaya al asesor del
   cliente cuando esté activo en el equipo (LEVEL 3, toca `public.crear_contrato`).
2. Si ese dinero no debe sumar al total de empresa en Ranking ni en el Resumen de Gerencia, hace
   falta una exclusión de «identidad interna» en el núcleo (plan aparte).
