---
tags: [crm, seguridad, rls, offboarding, p04]
actualizado: 2026-08-03
estado: produccion
---

# Offboarding seguro del CRM (P04)

P04 elimina la ambigüedad entre los dos flags que gobiernan a una persona del
CRM. Un miembro humano solo tiene acceso efectivo cuando están activos
`public.perfiles.activo` **y** `crm.equipo.activo`. Apagar cualquiera corta las
tablas, RPC y agenda del esquema CRM. Ver [[Acceso y roles del CRM]].

## Reglas canónicas

- `private.rol_crm()` solo devuelve rol con ambos flags activos.
- `private.puede_acceder_crm()` centraliza el gate del actor.
- Un rol global activo sin fila de equipo conserva el fallback de Directorio;
  una fila de equipo explícitamente inactiva prevalece y revoca ese fallback.
- Los miembros inactivos permanecen visibles **como objetos históricos** para
  que Gerencia pueda reasignar cartera; no pueden actuar ni recibir nueva
  responsabilidad.
- Un destino nuevo de lead debe tener perfil y membresía activos y ser vendedor
  o supervisor según corresponda. El trigger vuelve a comprobarlo incluso si
  escribe `service_role`.

## Superficies cubiertas

- policy RESTRICTIVE común en todas las tablas `crm` existentes; la migración
  aborta si encuentra alguna con RLS apagado;
- `crm.mi_acceso_fn()` distingue miembro, global, revocado y no enrolado sin
  confundir la ausencia de fila con una fila oculta por RLS; la respuesta queda
  ligada al UUID de la sesión para cerrar carreras de cambio de usuario;
- RPC SECURITY DEFINER y helpers de cartera, incluido el precheck P-047, con
  gate explícito y ACL mínimos;
- feed ICS atómico: token, ambos flags y tareas se leen en una sola sentencia;
  `equipo=false` rota irreversiblemente el bearer. `perfil=false` es una
  suspensión temporal: el feed responde 404 mientras dure y no toca objetos de
  `public`, conforme a la frontera de migraciones del CRM;
- importación de leads no resuelve como destino a un perfil parcialmente
  inactivo, y el trigger de destino es la garantía final;
- el ciclo de contratos toma un snapshot de asesores elegibles —ambos flags y
  allowlist— inmediatamente antes del claim. Así, una consulta fallida no
  consume sellos y el siguiente ciclo puede reintentar; una baja concurrente
  posterior al snapshot conserva la carrera mínima inevitable de todo envío
  externo sin outbox transaccional.

P04 **no revoca poderes genéricos del portal** que un analista conserve fuera
del CRM, no retira correos ya entregados ni URLs ya copiadas, y no cambia las
reglas comerciales de P-047. P-048 sigue separado en
[[Disponibilidad y enfriamiento de leads (P-047 y P-048)]].

## Extensión a banca contractual

El 2026-08-04 la migración `20260804144555_crm_p04_gate_cuentas_bancarias`
extendió el gate vivo a las RPC de [[Cuentas bancarias por contrato]] que
habían nacido después del P04 original. Cubre listado y alta bancaria,
corrección de contratos enlazados y legacy, y el resolver contractual de
Pagos. Una membresía CRM revocada prevalece también para un admin del portal;
un admin global sin fila de equipo conserva el fallback acordado.

La migración se probó en una branch Supabase sin datos con gate PostgREST
`475/475`, sin errores ni clases nuevas en advisors. Producción la registró
como `20260804154054`; los hashes y ACL de las tres funciones reemplazadas
coincidieron con la rama y esta se eliminó tras el merge. La frontera sigue
siendo deliberada: `public.crear_contrato` y `public.actualizar_contrato` son
capacidades legacy del portal y su migración o retiro pertenece a una fase
separada; P04 no se comunica como revocación contractual universal.

## Despliegue y rollback

Orden obligatorio: migración SQL → smoke de RPC/ICS → Edge Functions → app CRM.
La app nueva depende de `crm.mi_acceso_fn`; publicarla antes de la migración
bloquearía el login de todos. Rollback de app/Edges puede hacerse con el release
anterior; la migración es aditiva/reemplaza gates y está preparada para una
reaplicación segura si Supabase registra un timestamp distinto al archivo.

Despliegue de servidor 2026-08-03: branch temporal
`p04-offboarding-activos`, migración registrada en producción como
`20260803182426`, gate PostgREST `434/434`, advisors sin clase inesperada y
`P04_HTTP_SMOKE_OK`. Los smokes cubrieron ICS 200/404 y rotación, importación a
destino activo/inactivo, y ciclo `dry_run` sin filtrar contratos a un asesor
inactivo. En producción quedaron `crm-agenda-ics` v3, `crm-importar-leads` v9 y
`ciclo-contratos` v4 con fuentes exactas y flags JWT preservados. La rama fue
borrada para detener el coste.

Despliegue del front 2026-08-03: publicación tras la invocación humana
`/release-crm`, release `crm-20260803T185343Z-f1e6042fbefb`, ZIP SHA-256
`fe93128613fbc35690b054060a5f48d92e7fb81f6d9ef60a5679f65212705a95`.
A las `2026-08-03T19:10:44Z`, producción servía
`assets/index-CfihSZSH.js` con SHA-256
`7dfc133761614c833af61b0014da32c19029e0169556b5578f3cb773bb8919f2`.
Los 33 recursos no rasterizados accesibles coincidieron byte por byte; los
cuatro PNG de marca fueron recomprimidos por Hostinger y conservaron exactamente
el mismo payload de píxeles. Las rutas de ZIP, fuentes, migraciones, sourcemaps,
`.env` y `package.json` devolvieron 403/404.
