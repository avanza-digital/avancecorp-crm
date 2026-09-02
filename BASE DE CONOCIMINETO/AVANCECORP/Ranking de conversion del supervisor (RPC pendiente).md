---
tags: [crm, sql, rls, seguridad, ranking, resuelto]
actualizado: 2026-09-02
estado: RPC F2.2 VIVA — acoplamiento del front corregido; pendiente desplegar el cambio de interfaz
---

# Ranking de conversión del supervisor — la RPC que falta (decisión #10, parte b2)

Relacionado con [[Plan de escalabilidad del CRM a data gigante]] (decisión #10) y
[[Telemetria del CRM tiene dos extremos]].

## Actualización 2026-09-02 — el núcleo ya vive; la falla estaba en el front

Esta nota conserva debajo el razonamiento histórico previo a F2.2. El nombre del
archivo también es histórico: `crm.metricas_conversiones_equipo_fn` ya está
aplicada y responde con alcance `equipo` para supervisión y `global` para
gerencia.

La revisión en producción confirmó que los tres núcleos del ranking están sanos:

| Pestaña | Fuente autoritativa existente |
|---|---|
| Conversión general | `crm.conversion_mensual_fn` |
| Capital total | metas del mes + `crm.cumplimiento_metas_fn` + TC BCRP |
| Cosecha del lote | `crm.metricas_conversiones_equipo_fn` |

La falla funcional era de composición: la sección de gerencia activaba además
`crm.metricas_conversiones_fn` —una RPC amplia de inteligencia— y el componente
usaba su payload para descubrir identidades del tab de capital. Encima compartía
un único error entre las tres pestañas. Una lectura lateral caída podía apagar un
número sano de otro núcleo; en supervisión, un fallo mensual también podía tapar
el capital.

Corrección aplicada en el front, sin crear RPC, función SQL ni cálculo paralelo:

- la sección Ranking de gerencia ya no solicita `metricas_conversiones_fn`;
- cada pestaña consume directamente su núcleo y tiene carga, error y reintento
  propios;
- el clasificador de capital existente recibe el roster visible y, solo si ese
  roster no llegó, usa como respaldo los IDs ya servidos por metas/cumplimiento;
- el alcance visible sigue siendo la frontera: no se agregan IDs laterales cuando
  existe roster de supervisor o gerencia.

Smokes de solo lectura del 2026-09-02: supervisor = 10 filas, gerencia = 17 filas,
ambos con `cosecha_cuadra=true`. Validación local del cambio: 184 archivos / 2495
pruebas con cobertura, typecheck, build, bundle y umbral de duplicación en verde;
el E2E focalizado de Equipo pasó 4/4. El cambio de interfaz queda pendiente de
despliegue.

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

## Auditoría RLS (subagente `auditor-rls`) — sin bloqueantes de seguridad

Veredicto: **el ámbito NO fuga fuera del subárbol, no hay PII y no se toca
`public`**. Verificó una por una las citas del borrador y confirmó el contrato de
denegación rol por rol, el gate-antes-de-validación y la ACL. Confirmó también que
la rama de parkeados sería **código muerto** aquí (el agregado es un `LEFT JOIN`
sobre `vendedor_id`, así que un lead sin dueño no puede sumar en ninguna fila).

Encontró un **MAYOR real, ya corregido**, que es la clase de defecto que solo se ve
leyendo la RLS:

> **Faltaba `activo = true` en el predicado.** El canónico `leads_select` lo lleva
> DENTRO de la rama de ámbito, y `leads_update` concede el soft-delete a
> supervisor/gerencia. Sin ese filtro, **un supervisor que apaga un lead deja de
> verlo en las cinco RPC de F1 y lo seguiría contando en el denominador de su
> propio ranking — bajándole el porcentaje al vendedor.**

Es un choque entre dos reglas de la casa: «espejo exacto de `leads_select`» vs
«paridad as-built con gerencia» (que no filtra `activo`). Se resolvió a favor de la
primera —la que impide contar como propio lo que la RLS ya no deja ver— y la
divergencia queda declarada en la cabecera del SQL.

También corregidos: el postflight prometía custodiar tres patas y solo vigilaba
dos (faltaban `stable` y **el revoke a `service_role`**, justo «lo que un
copy-paste incompleto rompe en silencio»), y `vendedor_ids_visibles` se calculaba
también para gerencia, donde devuelve toda `crm.equipo` sin usarse.

**Queda un BLOQUEANTE de proceso**: la RPC nacería sin una sola línea en el gate
— y el auditor descubrió de paso que **la función global tampoco está cubierta hoy**
(`grep metricas_conversiones` en `test-rls.mjs` → cero). Los casos están redactados;
se codifican junto con la migración, no antes: sin la función aplicada dejarían el
gate en rojo.

Dato que importa para la decisión de abajo: los leads **parkeados** de la bandeja
del propio supervisor no entran en su denominador, así que este total **nunca va a
cuadrar con `resumen_cartera_fn`**. Conviene rotularlo, no explicarlo después.

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
