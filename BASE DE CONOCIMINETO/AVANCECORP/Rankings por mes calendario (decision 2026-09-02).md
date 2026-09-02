---
tags: [crm, ranking, metas, conversion, tipo-de-cambio]
actualizado: 2026-09-02
estado: IMPLEMENTADO Y DESPLEGADO
---

# Rankings por mes calendario (decisión 2026-09-02)

Relacionado con [[Ranking de conversion del supervisor (RPC pendiente)]],
[[Ranking de capital total unificado (TC BCRP)]], [[Conversion mensual - definicion cerrada]]
y [[Cierre de mes]].

## Regla de negocio

Miguel confirmó que los rankings de Gerencia y Supervisión se comparan por
**mes calendario**, no por el rango libre exacto:

- la fecha final del filtro de Gerencia selecciona el mes del ranking;
- un mes pasado abarca del día 1 al último día calendario;
- el mes vigente abarca del día 1 hasta hoy en `America/Lima`;
- Conversión general, Capital total y Cosecha del lote deben usar el mismo mes,
  la misma población y el mismo alcance del usuario.

Para convertir USD a PEN en un mes histórico se usa el promedio de los últimos
**7 días publicados/hábiles** disponibles hasta el último día de ese mes. No se
inventa una tasa ni se usa el tipo de cambio actual para reescribir el pasado.

## Población mensual

Los tres núcleos existentes siguen siendo la única autoridad; no se crea una
función comercial paralela:

| Pestaña | Núcleo existente |
|---|---|
| Conversión general | `crm.conversion_mensual_fn(date)` |
| Capital total | `crm.cumplimiento_metas_fn(date)` + metas del mes + `crm-tipo-cambio` |
| Cosecha del lote | `crm.metricas_conversiones_equipo_fn(date,date)` |

La población se resuelve así:

- mes vigente: roster vivo;
- mes pasado todavía abierto: última revisión publicada de
  `crm.meta_periodos` / `crm.metas_vendedor`;
- mes cerrado: foto sellada y alcance histórico de
  `private.cierre_mes_visible`, incluido el supervisor que correspondía al
  momento del cierre.

El 2026-09-02 la comprobación de producción confirmó el caso real que motivó
la regla: agosto seguía abierto, su foto tenía 16 analistas y el roster vivo 17;
había 2 altas posteriores y 1 integrante de agosto ya inactivo. Mezclar ambos
conjuntos hacía divergir las pestañas o invalidaba toda la Conversión por su
defensa fail-closed.

## Restricciones de implementación

- Se reemplazan solo los núcleos existentes; no nacen RPC, tablas ni Edge
  Functions nuevas.
- `crm.cumplimiento_metas_fn` no se modifica: ya entrega la foto mensual.
- Mientras la identidad mensual carga o falla, las tres pestañas quedan en
  carga/error; ninguna muestra nombres o cifras de otro mes.
- El selector demo permanece fijado al mes vigente.
- La Edge existente `crm-tipo-cambio` debe desplegarse antes del frontend que
  solicita una fecha de corte histórica.

## Publicación y auditoría final

Quedó desplegado en producción el 2026-09-02 desde el `main` local hacia su
espejo remoto `avancecorp/tronco`, commit `5b1c808f9138`.

- Migración registrada: `20260902070052_crm_ranking_poblacion_mes_calendario`.
- Se reemplazaron únicamente `crm.conversion_mensual_fn(date)` y
  `crm.metricas_conversiones_equipo_fn(date,date)`; la huella posterior fue
  `016f19d203bb552696d5270ee8c4884e` y
  `0631448b64810fc4d0a5dc936016debf`, respectivamente.
- `crm.cumplimiento_metas_fn(date)` quedó intacta, con huella
  `b76cc20b5b88604308a9974fc1948a7a` antes y después.
- La Edge existente `crm-tipo-cambio` pasó de v7 a v8, conserva
  `verify_jwt=true` y responde el corte histórico. Para 2026-08-31 devolvió
  3,3491 con siete fechas BCRP publicadas entre el 21 y el 31 de agosto; una
  fecha futura devolvió 400 y una llamada sin autenticación, 401.
- Oráculo de producción bajo identidades reales: Gerencia ve la misma población
  en Conversión/Capital/Cosecha — agosto 16/16/16 y setiembre 17/17/17. Un
  Supervisor comprobado ve agosto 8/8/8 y setiembre 10/10/10.
- Supabase Advisors terminó sin errores; owner, ACL, `STABLE`,
  `SECURITY DEFINER`, `search_path` y ausencia de ejecución `anon/public`
  quedaron verificados.
- Gate local: 2.524/2.524 pruebas unitarias; E2E completo 113 aprobadas, 26
  omitidas y 0 fallidas; E2E focal Gerencia/Supervisión 9/9; Edge 30/30 en
  Node y 5/5 en Deno, además de formato, lint y typecheck verdes.
- CI: `CRM app quality` quedó verde en el run `33644821968`. El primer
  preflight RLS descubrió que Deno 2 usaba `nodeModulesDir=manual` en un runner
  limpio y no instalaba una dependencia transitiva de los tipos de Supabase;
  no falló ninguna prueba ni hubo acceso remoto. El commit `eca2dcb85cef`
  activó instalación automática con lock congelado, registró `deno.lock` y se
  verificó tanto en un checkout frío como en el run `33646311542`, ya verde.
- Release `crm-20260902T145408Z-5b1c808f9138`, build
  `build-20260902T145407204Z`, ZIP SHA-256
  `3b7797c1f57c939fc7d6b362337a3f3e7082ae3229d3a9a5be90fae001d01132`.
  En vivo coincidieron 62/62 archivos de código y las 12/12 imágenes
  respondieron 200; el ZIP no quedó publicado y el asset principal anterior
  quedó 404.

La sesión de Chrome disponible durante el smoke final era del perfil de
reparto: cargó el build nuevo y el guard de roles la devolvió correctamente a
`#/repartir`. No se cerró la sesión ni se manipularon credenciales. La conducta
de Gerencia y Supervisión se comprobó con el E2E por rol y con el oráculo real
de base de datos descrito arriba.

### Rollback preservado

- Base completa previa: `/private/tmp/crm-before-ranking-20260902.sql`,
  SHA-256 `8d5a51f9338bdb5491788b56482f4d24d4b5a833531b142ba13f200049ee96e8`.
- SQL focal probado: `/private/tmp/rollback-ranking-20260902070052.sql`,
  SHA-256 `a863055cb91da437787cc072b2157e4c6892664d1b65797a7d9ac4edbac86a8e`.
- Edge v7 original:
  `/private/tmp/crm-tipo-cambio-v7.RYpJr3/supabase/functions/crm-tipo-cambio/index.ts`,
  SHA-256 `ae395cbc1a09d081382c72d7143988e548616d4228c6157815eaf33ea544a8b1`.
- Frontend anterior inmediato:
  `releases/crm-20260902T060243Z-5c208ad9bf31.zip`.
