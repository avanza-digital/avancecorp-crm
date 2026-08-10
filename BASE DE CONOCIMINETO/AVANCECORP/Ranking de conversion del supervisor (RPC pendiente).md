---
tags: [crm, sql, rls, seguridad, plan, pendiente]
actualizado: 2026-08-10
estado: DISEÑADO y ATACADO — NO aplicar todavía (4 bloqueantes abiertos)
---

# Ranking de conversión del supervisor — la RPC que falta (decisión #10, parte b2)

Relacionado con [[Plan de escalabilidad del CRM a data gigante]] (decisión #10) y
[[Telemetria del CRM tiene dos extremos]].

## Dónde encaja

Miguel cerró la decisión #10 el 2026-08-10: los supervisores ven el ranking de SU
equipo, **con las dos pestañas**. Lo entregado y en producción:

| Parte | Estado |
|---|---|
| (a) Monto unificado en las 6 celdas de equipo/supervisor/directorio | ✅ EN PROD |
| (b1) Pestaña «Capital total» para el supervisor | ✅ EN PROD |
| **(b2) Pestaña «Conversión general»** | ⛔ **esta nota** |

b1 salió sin tocar servidor porque sus tres fuentes —roster, metas y
cumplimiento— ya llegan recortadas al subárbol recursivo. b2 no puede.

## Por qué b2 NO es «relajar el gate»

Al leer el SQL aparecieron **dos razones independientes**, y cualquiera basta:

1. **Sería una fuga.** De las 9 claves del payload de
   `crm.metricas_conversiones_fn`, **cinco son agregados de TODA la empresa**
   (`cohorte`, `produccion`, `embudo`, `origenes`, `categorias`). Un agregado
   global **no se puede desagregar a posteriori**:
   `private.filtrar_desglose_sujetos_crm` solo reescribe la clave `responsables`
   y, encima, **filtra por ROL efectivo, no por visibilidad** — dejaría pasar el
   desglose de todos los vendedores activos de la empresa.
2. **Ni siquiera funcionaría.** La implementación privada conserva **su propio
   gate de gerencia dentro del cuerpo**: el supervisor recibiría `42501` desde
   dentro aunque el wrapper lo dejara pasar.

La regla estructural que sí demuestra el repo (y que conviene no citar al revés):
**gate relajado a supervisor ⟺ payload sin ningún agregado global**. Por eso la
función nueva nace con la superficie mínima y el ámbito **dentro** de las CTE.

## Estado: diseñada, atacada, NO aplicable

El borrador completo (19 KB, con preflight, postflight, índice, contrato de
denegación y `comment on function`) está guardado en el scratchpad de la sesión
como `borrador-metricas-conversiones-equipo.sql`. Tres lentes adversariales lo
atacaron y encontraron **15 hallazgos, 4 BLOQUEANTES**:

### 🔴 B1 — el postflight abortaría la migración entera (tres lentes coincidieron)

El guardia compara `proconfig @> array['search_path=']`, pero Postgres almacena
`set search_path = ''` como **`search_path=""`** (con comillas: `search_path`
lleva `GUC_LIST_QUOTE`, y el valor vacío se cita). La comparación **nunca casa**,
salta el `raise exception` y hace **rollback de toda la migración**. Un agente lo
verificó ejecutándolo en un Postgres local.

> Lo perverso: el mensaje culparía a la función, que está bien. Se habrían perdido
> horas revisando la RPC mientras el defecto estaba en su propio validador.

El repo ya tiene el literal correcto en tres gates vivos
(`test-metricas-servidor.sql:532` y `:778`,
`test-inteligencia-comercial-reuniones.sql:340`).

✅ **Ya corregido en el borrador guardado** (`search_path=""`), para que no vuelva
a morder al retomarlo. Los otros tres bloqueantes siguen abiertos.

### 🔴 B2 — el payload mínimo NO lo puede consumir el front

La cabecera justificaba la superficie mínima diciendo que el ranking solo pinta
cuatro campos. **Cierto del render, falso del contrato**: entre la RPC y el render
hay un `v.safeParse(MetricasConversionesSchema, …)` que exige `cohorte`,
`produccion`, `embudo`, `origenes`, `categorias` y, por responsable,
`contactados`, `reuniones_realizadas`, `capital_pen`, `capital_usd` y
`tendencia_semanal` — **todos obligatorios**. Y `adaptarConversionVendedores`
itera `responsable.tendencia_semanal` **sin guarda** → `TypeError`.

Desplegarla tal cual daría al supervisor el banner «las métricas no tienen el
formato esperado»: exactamente la mentira que `conversionDisponible={false}` evita
hoy. **Prerrequisito duro: esquema Valibot y adaptador PROPIOS para el payload de
equipo**, sin tocar el esquema de gerencia.

### 🔴 B3 y B4 — el contrato de denegación no tiene dónde probarse

`crm.metricas_conversiones_fn` **no aparece ni una vez en `test-rls.mjs`**. Las
listas del gate son literales y no se autodescubren, así que el ciclo pasaría
**verde sin haber ejercido jamás el gate nuevo** — moviendo una frontera de
seguridad sin una sola aserción. El ataque dejó redactados **~30 casos** (bloques
A permitidos/forma, B denegaciones, C no-vacuidad) listos para codificar.

## ⚠️ Decisión de negocio que necesita Miguel

**¿El ranking del supervisor es «mi gente hoy, toda su historia» o «lo producido
bajo mi mando»?**

Tal como está diseñada, el ámbito es por **dueño actual** sobre una ventana de
hasta 366 días. Consecuencia: basta que gerencia traspase un vendedor para que el
supervisor reciba **el año entero** de esa persona, incluido el periodo en que
estuvo con otro supervisor. Y al revés: su propio ranking se reescribe solo cuando
alguien se mueve de equipo.

El precedente de F1 no zanja esto: aquellas RPC son foto del *ahora*, y la única
con historia larga (`series_comerciales_fn`) entrega agregado de equipo, **nunca
desglose nominal por persona**. Esta sería la primera que da rendimiento histórico
nominal a un supervisor.

## Por qué la migración NO se commitea todavía

No es prudencia de más: es una **regla dura del proyecto**. «Nunca editar una
migración ya commiteada — se crea una nueva». La decisión de negocio de abajo
cambia el CÁLCULO de la RPC (dueño actual vs. ledger de asignaciones), así que
commitear el archivo ahora y responder después significaría **una segunda
migración correctiva** por un cambio que aún estábamos a tiempo de evitar.

El archivo se escribe cuando estén las dos cosas: la decisión de Miguel y el visto
bueno para abrir branch en la base **compartida con el portal**.

## Lección del ciclo

> **Un validador puede estar más roto que lo que valida.** El postflight habría
> abortado una migración correcta, y su mensaje de error apuntaba al sitio
> equivocado. Cuando un guardia nuevo usa una API que el repo no usa en ningún
> otro sitio (`proconfig` no aparecía en ninguna migración), hay que probarlo
> contra un Postgres real antes de confiar en él.

Y la hermana: **«los campos que pinta la pantalla» no son «los campos que exige el
contrato»**. Entre la RPC y el JSX hay un validador fail-closed y un adaptador;
diseñar la superficie mirando solo el render es diseñarla contra el sitio
equivocado.
