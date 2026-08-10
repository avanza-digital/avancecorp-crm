---
tags: [crm, conversion, metas, plan, pendiente-aprobar]
actualizado: 2026-08-10
estado: plan-esperando-aprobacion-de-miguel
---

# Conversión mensual — plan de implementación

Plan para llevar a producción la fórmula de [[Conversion mensual - definicion cerrada]].
**Nada de esto está escrito todavía**: espera el OK de Miguel.

Sale de tres fuentes que se contrastaron entre sí: un workflow de 15 agentes (3 diseños
en competencia + 3 revisores adversariales), una pasada de `codex-rescue` sobre el
esquema real, y verificación directa contra producción. Donde los tres no coincidían,
se dice cuál se eligió y por qué.

---

## 0. El estado real de producción HOY (verificado, 2026-08-10)

Esto no es contexto: cambia lo que el CRM podrá enseñar el primer día.

| Cosa | Valor real |
|---|---|
| Leads en `crm.leads` | **1** |
| Convertidos / descartados | **0 / 0** |
| Leads con origen `referido` | **0** |
| Episodios en `crm.lead_asignaciones` | **1** (el primero es del 2026-08-05) |
| Episodios con `resultado='convertido'` | **0** |
| Metas publicadas | **3 revisiones de agosto-2026, 16 analistas cada una** |
| Meta de conversión en esas 3 revisiones | **0,00 en las tres** |
| Cambios históricos de `origen` en `public.audit_log` | **0** |

Tres lecturas que hay que tener presentes:

1. **Guardar metas ya funciona.** Miguel publicó tres revisiones hoy (17:32, 17:42 y
   18:04 UTC), 16 analistas cada una. El arreglo del 2026-08-10 quedó probado en vivo.
2. **Pero la meta de conversión sigue saliendo en 0**, porque el arreglo del editor
   (`fijarConversionEmpresa`, que dejó de pisarla) vive en el commit `04393f8` y **no
   está desplegado**: producción corre `de01175`. Hasta que se despliegue, la conversión
   no se puede pactar aunque la pantalla la muestre.
3. **La base está vacía.** Con 1 lead y 0 cierres, esta métrica va a decir «sin datos»
   para todo el mundo el día que se publique. Eso es correcto y hay que anunciarlo: el
   valor de este ciclo es que **el negocio empiece a contarse bien**, no que enseñe un
   número bonito mañana.
4. **Y el CRM no vuelve a recibir leads hasta el 15 de agosto** (decisión de Miguel,
   D6). O sea que agosto es medio mes de ingreso sobre una base vacía: **el primer mes
   contable completo es septiembre**, que es exactamente donde D1 puso la meta.

---

## 1. Los cinco huecos del esquema (no son opinables)

**H1 · El ledger nace el 2026-07-17: antes no hay divisor posible.**
`crm.lead_asignaciones` es la única tabla donde «recibir» y «cerrar» son hechos
inmutables, y no existía antes de esa fecha. Su backfill reconstruyó solo el episodio
*vigente* de los leads abiertos, con `asignado_en` **adivinado** (`aproximado = true`).
Consecuencia: **agosto-2026 es el primer mes contable**; julio es parcial; junio y
anteriores son incontables. La pantalla dirá «sin datos de asignación para este mes»,
**nunca «0 %»** — son dos frases muy distintas sobre el trabajo de una persona.

**H2 · Reasignar un lead YA CERRADO no deja rastro en el ledger.**
Un `UPDATE vendedor_id: A→B` sobre un lead `convertido` o `descartado` está permitido y
no abre episodio. **Esta métrica es inmune**, porque el cierre se atribuye a la fila
inmutable del episodio y no a `crm.leads.vendedor_id`. Pero el CRM queda con dos verdades
sobre el mismo lead: el informe dice A, la ficha dice B. **No se prohíbe por trigger**:
ese es justamente el camino con el que gerencia traspasa la cartera de quien se va, y
romperlo por cuadrar un informe sería cambiar la operación. Se mide, se declara y se fija
por test. En producción han ocurrido **0** veces.

**H3 · Una carga masiva desde la hoja entraría como demanda nueva del mes.**
El divisor no usa la fecha de alta del lead: usa `asignado_en` del episodio, o sea
**cuándo pasó a ser del asesor**. Es la decisión de Miguel y es la correcta — pero
significa que un lote de leads viejos repartido hoy es, para la métrica, demanda de hoy.
Guardar la fecha de la hoja **no lo arreglaría**: la asignación ocurre de verdad hoy.

Verificado el 2026-08-10, el riesgo es **mucho menor** de lo que parecía, porque el
puente ya está blindado por dos lados:

- `scripts/puente-drive-origen.gs` tiene `FECHA_CORTE` (decisión de Miguel del
  2026-07-23): las filas con fecha legible anterior al corte se descartan con motivo
  «Anterior al corte».
- La pestaña oculta `_puente_huellas` guarda la huella `pestaña|teléfono` de todo lo ya
  traído y la salta en cada pasada, así que **volver a correr el puente no re-importa
  nada**. (Ojo: «re-pegar el `.gs`» es volver a pegar el **código** del script, no
  reimportar datos.)

Quedan dos agujeros, los dos conocidos y ninguno silencioso:

1. **Una fila sin fecha legible entra igual** aunque sea vieja (decisión de Miguel del
   2026-07-27: el origen dejó de llenar «Fecha de Registro» y la regla anterior tenía 159
   leads presos en REVISAR). O sea: **el corte solo frena lo que viene fechado.**
2. **Si se borra o resetea `_puente_huellas`**, la siguiente pasada re-importa de golpe
   todo lo posterior al corte. Ese sí hundiría el mes.

Mitigación en el producto: `cobertura.divisor_por_motivo` deja el pico visible en pantalla
en vez de esconderlo dentro de un porcentaje. Cierre operativo: ver D6, ya decidido.

**H4 · «Registró» no existe en el esquema con ese nombre.** Hay dos lecturas distintas:
`crm.leads.creado_por` (quién dio de alta) y `lead_asignaciones.analista_id` (a quién se
lo dieron). Un referido que da de alta gerencia a nombre de Ana tiene
`creado_por = gerencia`. **Se devuelven los dos números.** El que ocupa el rótulo
«registrados» es *lo que recibió*, porque es lo que está en su divisor y lo único con lo
que el «aporta 1,6 %» cuadra aritméticamente (D3).

**H5 · La meta de conversión deja de ser un cero en cuanto se despliegue `04393f8`.**
En cuanto gerencia pueda pactarla, la cifra vieja (`convertidos ÷ resueltos`) se pinta
viva contra ella. Por eso este plan **no puede dejar `cumplimiento_metas_fn` con la
definición antigua**: sería el mismo asesor con dos porcentajes distintos a 300 px de
distancia. Va incluido (migración B).

---

## 2. Las decisiones técnicas que fija este plan

| # | Pregunta | Decisión | Por qué |
|---|---|---|---|
| **T1** | ¿De dónde sale el divisor? | `crm.lead_asignaciones.asignado_en` | Es el único registro inmutable de «este lead pasó a ser suyo». `leads.creado_en` es la fecha de alta, y un lead puede pasar días en la bandeja de un supervisor antes de llegar a un asesor. |
| **T2** | ¿A quién se le apunta el cierre? | `analista_id` de la fila del episodio con `resultado='convertido'` | Todas las demás fuentes pierden al dueño: `leads.vendedor_id` es el dueño de HOY; `finalizado_por` es el ACTOR (gerencia puede cerrar por otro); `contratos.creado_por` es quien creó el contrato; `perfiles.asesor_perfil_id` lo reescribe el offboarding. |
| **T3** | ¿Qué reloj fecha el cierre? | **`resultado_en`** del episodio | Codex propuso `leads.convertido_en` (es lo que ve gerencia en la ficha). Se elige `resultado_en` porque sale de la **misma fila** que `asignado_en`: numerador y procedencia comparten reloj y no se pueden contradecir. Difieren solo en microsegundos (`statement_timestamp()` vs `now()`) y el único caso donde importa —una transacción a caballo de un fin de mes— lo **caza la sonda** `cierres_sin_episodio`, que lo declara en vez de esconderlo. |
| **T4** | ¿Cómo se sabe que «era referido»? | El **snapshot** `lead_asignaciones.origen` del episodio, nunca `crm.leads.origen` | El snapshot es inmutable por trigger. `crm.leads.origen` no lo era hasta ahora (migración D), y aunque lo sea, la verdad histórica del cierre debe salir de la fila que ya está sellada. |
| **T5** | A→B→A en el mismo mes: ¿1 o 2 al divisor de A? | **1** (`group by analista_id, lead_id`) | Un lead que va y vuelve no es trabajo nuevo. Contando episodios se podría hundir un porcentaje moviendo leads de ida y vuelta. |
| **T6** | ¿Se redondea el numerador? | **No.** `numeric` exacto; solo se redondea el porcentaje, y una sola vez | `0,15 × 3 = 0,45`, y al entero más cercano son 0: se borraría el aporte de tres cierres reales. Codex avisó del mismo riesgo por el otro lado: sumar porcentajes ya redondeados hace que «agosto + julio» no cuadre con el total. Por eso la procedencia viaja en **conteos enteros**, no en porcentajes. |
| **T7** | ¿Quién define el roster? | `private.roster_metas_vendedores()`, la fuente única del 2026-08-10 | Los tres diseños inventaban un **cuarto** roster horas después de que esa migración estableciera la fuente única. Con el helper, quien tiene meta y quien tiene conversión son el mismo conjunto — y por eso el `total` cuadra exactamente con la suma de las filas. |
| **T8** | ¿`SECURITY DEFINER` o `INVOKER`? | **DEFINER**, con gate propio | El ledger tiene `REVOKE ALL` para `authenticated`: con INVOKER la RPC no lee nada. Y el payload son **solo agregados** (uuids y números): ni un nombre, ni un teléfono, ni un DNI. Los nombres los pone el front uniendo por id. |
| **T9** | ¿Cómo entra algún día la data vieja sin dañar a nadie? | **Por la base fría** (DL-01 fase C2), y **sin ninguna excepción en la fórmula** | Ver abajo. |

### T9 · La base fría resuelve la data vieja sin tocar la conversión

Decisión de Miguel del 2026-08-10: la data histórica **no** se carga como leads normales.
Va a una **base fría**, y *«solo entra al divisor cuando el vendedor decide sacarlo de esa
base a su pipeline»*. Es la fase **C2 de [[CRM distribución de leads + base fría — plan
(DL-01)|crm-distribucion-leads-plan]]**, que estaba diferida y ahora tiene destinatario.

Lo relevante para este plan: **no hay que programar nada, y se cae una complicación que
yo iba a añadir.** Encaja por construcción:

- Un lead de base fría **no tiene dueño**. El escritor del ledger solo abre episodio
  cuando el lead está activo, en etapa operativa **y tiene `vendedor_id`** — así que un
  lead frío genera **cero filas** y no está en el divisor de nadie. Igual que hoy pasa con
  la bandeja del supervisor: repartir a una bandeja no abre episodio, porque una bandeja
  no es un asesor.
- Cuando el vendedor **lo saca a su pipeline**, esa asignación es real: nace el episodio,
  y el lead entra al divisor **de ese mes**. Que es exactamente lo que Miguel quiere —
  eligió trabajarlo, así que le cuenta.

Con esto **se descarta el motivo `carga_historica`** que iba a proponer (excluir del
divisor un tipo de apertura). Sobra: la base fría ya lo consigue sin excepciones, y una
fórmula sin excepciones es una fórmula que nadie va a «arreglar» mal dentro de seis meses.

⚠️ **Requisito que hereda quien programe C2**: sacar un lead de la base fría debe pasar
por el camino normal de asignación (fijar `vendedor_id` sobre `crm.leads`). El trigger del
ledger dispara en cualquier UPDATE de la tabla, así que se cumple casi sin esfuerzo — pero
queda escrito para que nadie lo implemente por un atajo que se salte el ledger y deje esos
leads sin contar.

---

## 3. Backend — cuatro migraciones

### 3.1 Migración A — la conversión nueva (100 % ADITIVA)

`AAAAMMDDHHMMSS_crm_conversion_mensual_ponderada.sql`

Crea 1 tabla, 3 funciones y 4 índices. **No toca ni un byte del payload de ninguna
función existente**, por eso puede ir servidor primero sin regresión posible.

**(a) El 15 %, versionado por mes.** Una constante haría que cambiar el peso
**recalculara todo el histórico** y los meses ya enseñados dejaran de coincidir con lo
que se presentó.

```sql
create table crm.conversion_pesos (
  vigente_desde date primary key
    check (vigente_desde = date_trunc('month', vigente_desde)::date),
  peso_referido numeric(4,3) not null check (peso_referido >= 0 and peso_referido <= 1),
  nota text,
  creado_en timestamptz not null default now()
);
alter table crm.conversion_pesos enable row level security;
revoke all privileges on table crm.conversion_pesos
  from public, anon, authenticated, service_role;

insert into crm.conversion_pesos values (date '2026-07-01', 0.150,
  'Acordado con Miguel 2026-08-10: el referido pesa 1 en el divisor y 0,15 en el numerador.');
```

RLS ON, **cero policies y cero grants**: se lee solo desde funciones `SECURITY DEFINER`.

**(b) El nombre del mes, sin depender del locale del servidor.**
`to_char(fecha,'TMMonth')` depende de `lc_time`, que es un GUC de sesión; una función con
`search_path` vacío no lo controla, y el mismo payload diría «August» o «agosto» según
quién conecte.

```sql
create or replace function private.etiqueta_mes_es(p_mes date)
returns text language sql immutable set search_path = ''
as $$ select (array['enero','febrero','marzo','abril','mayo','junio',
                    'julio','agosto','setiembre','octubre','noviembre','diciembre'
             ])[extract(month from p_mes)::int]; $$;
```

**(c) Los índices.** Ya existen y sirven sin tocarse
`lead_asignaciones_analista_fecha_idx` y `lead_asignaciones_cohorte_idx` (divisor).
Faltan cuatro:

```sql
-- NUMERADOR por asesor. NO se reutiliza lead_asignaciones_terminal_analista_idx:
-- está ordenado por finalizado_en y el predicado natural es sobre resultado_en.
-- El CHECK los iguala, pero el planner NO deduce esa igualdad.
create index if not exists lead_asignaciones_convertido_analista_idx
  on crm.lead_asignaciones (analista_id, resultado_en) where resultado = 'convertido';

-- NUMERADOR global. Sin él, seq scan sobre una tabla append-only que solo crece.
create index if not exists lead_asignaciones_convertido_fecha_idx
  on crm.lead_asignaciones (resultado_en) where resultado = 'convertido';

-- Sonda de integridad. Hoy NO hay ningún índice que contenga convertido_en
-- (verificado en producción por Codex).
create index if not exists idx_leads_convertido_en
  on crm.leads (convertido_en) where etapa = 'convertido';

-- Bloque de referidos, rama «dados de alta por él».
create index if not exists idx_leads_creado_por_referido
  on crm.leads (creado_por, creado_en) where origen = 'referido';
```

Sin `CONCURRENTLY`, mismo criterio que `20260809144930` y `20260810024404`: el ciclo
aplica en branch y el merge lo reproduce con las tablas aún pequeñas.

**(d) La aritmética, en UN solo sitio.** Set-returning en `private`, sin gate propio: no
la publica PostgREST y solo la llaman funciones que ya hicieron el suyo. Existe separada
de la RPC porque **cuando dos funciones deciden sobre el mismo conjunto, ese conjunto se
define una vez** — es exactamente la lección que costó que las metas no se pudieran
guardar.

```sql
create or replace function private.conversion_mensual_por_vendedor(
  p_ini timestamptz, p_fin timestamptz,
  p_global boolean, p_visibles uuid[], p_factor numeric)
returns table (
  analista_id uuid, divisor integer, divisor_aproximado integer,
  divisor_por_motivo jsonb, cierres_no_referidos integer, cierres_referidos integer,
  numerador numeric, conversion_pct numeric, procedencia jsonb,
  referidos_recibidos integer, referidos_aporta_pct numeric)
language sql stable security definer set search_path = ''
as $$
with recibidos as (
  -- DIVISOR: «V RECIBIÓ el lead en M» = tiene un episodio con asignado_en en
  -- [ini, fin) hora de Lima. ENTRA TODO, sin un solo filtro: todos los canales,
  -- REFERIDOS enteros, abiertos y DESCARTADOS. Como el ledger no tiene columna
  -- `activo`, la LEY («la conversión no filtra activo») se cumple por construcción.
  -- group by (analista, lead) = count(distinct lead_id): un A→B→A dentro del mes
  -- le pesa UNO a A (T5). Lo contado es el LEAD, no el episodio.
  select la.analista_id, la.lead_id,
    (array_agg(la.origen order by la.asignado_en desc))[1] = 'referido' as fue_referido,
    (array_agg(la.motivo_apertura order by la.asignado_en desc))[1] as motivo,
    bool_or(la.aproximado) as aproximado     -- episodios del backfill: se cuentan aparte
  from crm.lead_asignaciones la
  where la.asignado_en >= p_ini and la.asignado_en < p_fin
    and (p_global or la.analista_id = any(p_visibles))
  group by la.analista_id, la.lead_id
),
cierres as (
  -- NUMERADOR: atribuido por analista_id de la fila inmutable que cerró (T2),
  -- fechado por resultado_en (T3), y «era referido» desde el SNAPSHOT (T4).
  select la.analista_id, la.lead_id, (la.origen = 'referido') as fue_referido,
    date_trunc('month', la.asignado_en at time zone 'America/Lima')::date as mes_origen
  from crm.lead_asignaciones la
  where la.resultado = 'convertido'
    and la.resultado_en >= p_ini and la.resultado_en < p_fin
    and (p_global or la.analista_id = any(p_visibles))
),
agg_div as (
  select r.analista_id,
    count(*)::int as divisor,
    count(*) filter (where r.aproximado)::int as divisor_aproximado,
    count(*) filter (where r.fue_referido)::int as referidos_recibidos,
    (select jsonb_object_agg(m.motivo, m.n) from (
       select r2.motivo, count(*)::int as n from recibidos r2
       where r2.analista_id = r.analista_id group by r2.motivo) m) as divisor_por_motivo
  from recibidos r group by r.analista_id
),
agg_cie as (
  select c.analista_id,
    count(*) filter (where not c.fue_referido)::int as cierres_no_referidos,
    count(*) filter (where c.fue_referido)::int as cierres_referidos
  from cierres c group by c.analista_id
),
proc as (
  -- Procedencia en CONTEOS, nunca en porcentajes (T6). Los meses de más de 11
  -- atrás caen en un cubo «anteriores» para que el payload no crezca sin techo.
  select c.analista_id,
    case when (extract(year from p_ini at time zone 'America/Lima')::int * 12
             + extract(month from p_ini at time zone 'America/Lima')::int)
             - (extract(year from c.mes_origen)::int * 12
             + extract(month from c.mes_origen)::int) <= 11
         then c.mes_origen end as mes_origen,
    count(*)::int as cierres,
    count(*) filter (where c.fue_referido)::int as cierres_referidos
  from cierres c group by 1, 2
),
proc_json as (
  select p.analista_id, jsonb_agg(jsonb_build_object(
      'mes', case when p.mes_origen is not null
                  then pg_catalog.to_char(p.mes_origen,'YYYY-MM') end,
      'mes_nombre', case when p.mes_origen is not null
                        then private.etiqueta_mes_es(p.mes_origen) else 'anteriores' end,
      'anio', case when p.mes_origen is not null
                   then extract(year from p.mes_origen)::int end,
      'cierres', p.cierres, 'cierres_referidos', p.cierres_referidos
    ) order by p.mes_origen desc nulls last) as procedencia
  from proc p group by p.analista_id
)
select
  coalesce(d.analista_id, c.analista_id),
  coalesce(d.divisor, 0), coalesce(d.divisor_aproximado, 0),
  coalesce(d.divisor_por_motivo, '{}'::jsonb),
  coalesce(c.cierres_no_referidos, 0), coalesce(c.cierres_referidos, 0),
  -- Numerador FRACCIONARIO y sin redondear (T6). numeric es decimal exacto:
  -- con float8 daría 12,449999...
  (coalesce(c.cierres_no_referidos,0) + p_factor * coalesce(c.cierres_referidos,0))::numeric,
  -- NULL, nunca 0, cuando no recibió nada: un 0 se leería como «0 % de conversión».
  case when coalesce(d.divisor,0) > 0 then round(
    100.0 * (coalesce(c.cierres_no_referidos,0) + p_factor * coalesce(c.cierres_referidos,0))
    / d.divisor, 2) end,
  coalesce(pj.procedencia, '[]'::jsonb),
  coalesce(d.referidos_recibidos, 0),
  case when coalesce(d.divisor,0) > 0 then round(
    100.0 * p_factor * coalesce(c.cierres_referidos,0) / d.divisor, 2) end
-- FULL OUTER JOIN: un asesor puede tener divisor sin cierres (mes normal) o
-- cierres sin divisor (arrastra cartera vieja y no recibió nada). El segundo es
-- justo el que hay que distinguir; un INNER JOIN lo haría desaparecer.
from agg_div d
full outer join agg_cie c on c.analista_id = d.analista_id
left join proc_json pj on pj.analista_id = coalesce(d.analista_id, c.analista_id);
$$;
```

**(e) La RPC de pantalla**, `crm.conversion_mensual_fn(p_periodo date)`. **Mensual por
contrato**: la definición habla del «mes M» y el desglose «de qué mes venía cada cierre»
no significa nada sobre un rango de 63 días. Con la firma `date` (primer día del mes), la
pregunta «qué devuelve fuera de un mes exacto» es **inexpresable**.

Contrato de denegación, fijado **antes** de escribir los tests:

```
vendedor      → su propia fila           alcance 'propio'
supervisor    → su subárbol recursivo    alcance 'equipo'
gerencia      → la empresa               alcance 'global'
lector global → la empresa               alcance 'global'
coordinador / membresía inactiva / ajeno al CRM / anon → 42501 DURO
  Nunca payload de ceros: un cero se leería como «0 % de conversión».
periodo inválido → 22023, pero SOLO después del gate, para que el código de error
  no funcione como oráculo de pertenencia.
```

El gate puede estar abierto al vendedor porque el payload **no lleva ni un agregado de
empresa**: `total` se recalcula sobre el ámbito recortado. Es la regla estructural de la
casa: *gate relajado ⟺ payload sin agregados globales*.

Estructura del payload:

```jsonc
{
  "version": 1,
  "alcance": "global",                       // lo decide el SERVIDOR, que conoce el recorte
  "periodo":   { "mes": "2026-08", "mes_nombre": "agosto", "zona": "America/Lima", … },
  "ponderacion": { "referido": 0.15, "fuente": "crm.conversion_pesos" },
  "fuentes": {                               // contrato fail-closed para el front
    "divisor":   "crm.lead_asignaciones.asignado_en",
    "numerador": "crm.lead_asignaciones.resultado_en",
    "referido":  "crm.lead_asignaciones.origen" },
  "cobertura": {
    "medible": true,                         // distingue «0 %» de «sin datos» (H1)
    "suelo_historico": "2026-07-17T…",       // se CALCULA, no se escribe a mano
    "motivo_no_medible": null,
    "divisor_aproximado": 0,                 // episodios del backfill
    "divisor_por_motivo": { "ingreso": 90, "reasignacion": 4 },   // detecta H3
    "cierres_sin_episodio": 0,               // sonda: avisa en vez de mentir
    "fuera_de_roster": { "analistas": 0, "divisor": 0, "cierres": 0, "numerador": 0 }
  },
  "total": { "divisor": 110, "numerador": 17.80, "conversion_pct": 16.18, … },
  "responsables": [ {
      "vendedor_id": "…", "supervisor_id": "…",
      "divisor": 110, "cierres_no_referidos": 16, "cierres_referidos": 12,
      "numerador": 17.80, "conversion_pct": 16.18,
      "estado": "medible",                   // medible | solo_arrastre | sin_actividad
      "procedencia": [ { "mes":"2026-08","mes_nombre":"agosto","cierres":12 },
                       { "mes":"2026-07","mes_nombre":"julio","cierres":3 },
                       { "mes":"2026-06","mes_nombre":"junio","cierres":1 } ],
      "referidos": { "recibidos":20, "cerrados":12, "dados_de_alta":20, "aporta_pct":1.64 }
  } ]
}
```

Detalles que sostienen ese payload:

- **`total` se recalcula**: `sum(numerador) / sum(divisor)`. **No** es la media de los
  porcentajes de las filas — promediar porcentajes da un número que no corresponde a
  ningún lead real.
- **`estado` explícito**: con esta definición «divisor 0» ya **no** significa «sin
  muestra». Un asesor puede no haber recibido nada y tener numerador > 0 por arrastre; hoy
  el front lo rotula «Sin muestra» y lo saca del ranking. Con `solo_arrastre` sigue dentro.
- **Orden**: `conversion_pct desc nulls last, numerador desc, divisor desc` — quien no
  recibió nada no encabeza el ranking por tener el porcentaje en NULL.
- **`fuera_de_roster` sin identidad**: quien se dio de baja a mitad de mes, o el supervisor
  con cartera propia, ni se pierde ni se le atribuye a nadie: se declara como agregado.
  Devolver su UUID sería filtrar la identidad de alguien sin rol efectivo.
- **Ámbito materializado en array**: `= any(array)` es indexable; un `in (select srf())`
  se ejecuta como SubPlan por fila y nunca usa índice (razón ya documentada en
  `20260809144920`).
- Se cierra con `private.filtrar_desglose_sujetos_crm(...)` como defensa en profundidad.
  Es **idempotente** aquí porque el roster ya salió de `private.rol_crm` — y esa
  idempotencia es lo que hace que `total` cuadre con `responsables`.

**(f) Preflight y postflight.** El preflight exige que exista `trg_leads_asignaciones`:
sin ese trigger el ledger deja de registrar quién cierra y **la métrica contaría de menos
en silencio**, que es la peor forma de fallar para un informe. El postflight verifica
`SECURITY DEFINER` + `STABLE` + `search_path` vacío, que `service_role` y `anon` **no**
puedan ejecutar la RPC, que `authenticated` **sí**, que el núcleo `private` no sea
ejecutable, que `crm.conversion_pesos` no sea legible por la Data API, y que
`crm.lead_asignaciones` siga cerrado a `authenticated`.

### 3.2 Migración B — unificar `cumplimiento_metas_fn`

`AAAAMMDDHHMMSS_crm_cumplimiento_conversion_ponderada.sql` (`create or replace`).
**Se aplica SOLO cuando el front nuevo ya esté en producción** (ver §7). Es la que evita
que el mismo asesor tenga dos porcentajes en pantallas contiguas (H5).

No reimplementa nada: la CTE `conversiones` pasa a **consumir la misma función** que
alimenta la pantalla.

```sql
), conversiones as (
  select cm.analista_id as vendedor_id,
         cm.divisor as resueltos,                                      -- ahora: RECIBIDOS
         (cm.cierres_no_referidos + cm.cierres_referidos) as convertidos,  -- entero, sin ponderar
         cm.numerador, cm.cierres_no_referidos, cm.cierres_referidos,
         cm.conversion_pct as conversion_real
  from private.conversion_mensual_por_vendedor(
    v_ini, v_fin, true, '{}'::uuid[], v_factor) cm
  -- p_global => true a propósito: el recorte de sujetos lo hace la CTE `visibles`
  -- (metas_vendedor ∩ vendedor_ids_visibles). Recortar dos veces dejaría fuera a
  -- quien esté en el snapshot pero no en el ámbito vivo — que es justo el analista
  -- que se fue, y cuyo progreso Miguel quiere que siga contando.
), …
```

Cambios de payload, elegidos para minimizar destrozo:

- `resueltos` **conserva el nombre** aunque cambie de significado: renombrar la clave
  rompe el `strictObject` del front.
- `convertidos` sigue siendo **entero** (cierres totales sin ponderar).
  ⚠️ **`convertidos` puede ser mayor que `resueltos`** (0 recibidos, 4 arrastrados). Ese
  invariante se rompe a propósito y ningún consumidor puede asumir lo contrario.
- `conversion_real` es **lo único que cambia de fórmula**, y **puede superar 100**.
- Se **añaden** `numerador`, `cierres_referidos`, `cierres_no_referidos` y
  `ponderacion_referido` — sin ellos el front no puede agregar supervisor ni empresa.
- `fuentes_reales.conversion` pasa de `'leads_resueltos'` a `'leads_recibidos_ponderado'`.

El resto de la función se copia **byte a byte** de `20260808183527`.

### 3.3 Migración C — la vuelta atrás, escrita ANTES de aplicar B

`AAAAMMDDHHMMSS_crm_cumplimiento_conversion_rollback.sql`: `create or replace` de
`crm.cumplimiento_metas_fn` con el cuerpo **verbatim** de `20260808183527`. Se escribe y
se deja lista en el branch **antes** de aplicar B; no se commitea a `main` salvo que haga
falta. Razón: el modo de fallo de B es «metas caídas para los tres roles», y su MTTR sin
esto son decenas de minutos (branch → aplicar → gate → advisors → merge asíncrono ~90 s).

### 3.4 Migración D — sellar `crm.leads.origen` (decisión de Miguel del 2026-08-10)

`AAAAMMDDHHMMSS_crm_origen_inmutable_correccion_gerencia.sql`

Ni el workflow ni Codex la conocían: es la decisión que Miguel tomó después de lanzarlos.
Con el 15 %, el origen deja de ser una etiqueta informativa y pasa a tener **consecuencia
económica**: mover un lead a «referido» o sacarlo de ahí cambia la conversión de alguien.

Estado real verificado: `origen` es una columna normal de `crm.leads`, y el trigger de
inmutabilidad `private.leads_before_update` protege hoy **solo** `id`, `creado_por` y
`creado_en`. El ACL de `crm.leads` es de **tabla** (`authenticated=arw`), así que un
`revoke update (origen)` sería un **no-op silencioso**: la inmutabilidad la tiene que
sostener el trigger, igual que ya pasa con `tenencia_desde`.

```sql
create or replace function private.leads_before_update()
returns trigger language plpgsql security definer set search_path = crm, public
as $$
declare
  v_priv boolean := coalesce(current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  new.id := old.id;  new.creado_por := old.creado_por;  new.creado_en := old.creado_en;
  new.actualizado_en := now();

  -- ── NUEVO: el ORIGEN se sella al nacer ────────────────────────────────────
  -- Única excepción: gerencia puede corregirlo dentro de las 24 h siguientes a la
  -- creación del lead. Misma ventana que crm.deshacer_descarte, que el equipo ya
  -- conoce. Garantiza que al cerrar el mes ningún origen se haya podido mover en
  -- las últimas semanas: la conversión de agosto no cambia en septiembre por una
  -- reclasificación.
  if new.origen is distinct from old.origen then
    if not (private.rol_crm((select auth.uid())) = 'gerencia'
            and old.creado_en > now() - interval '24 hours') then
      new.origen := old.origen;   -- se restaura en silencio, igual que id/creado_en
    end if;
  end if;
  … resto idéntico …
```

Dos decisiones dentro de esta migración:

1. **Restaurar en silencio, no lanzar excepción.** Es el patrón que la casa ya usa para
   `id`, `creado_por`, `creado_en`, `perfil_id` y `tenencia_desde`. Una excepción haría
   fallar el UPDATE **entero** de cualquier cliente que reenvíe el lead completo en el
   body (PostgREST manda todas las columnas del formulario), rompiendo ediciones legítimas
   de nombre o teléfono. La corrección de gerencia dentro de plazo sí pasa; fuera de
   plazo, el campo simplemente no se mueve.
2. **La auditoría ya existe: no hay que escribir nada.** `trg_audit_leads` inserta en
   `public.audit_log` cada UPDATE de `crm.leads` con `data_antes` y `data_despues`
   completos y `usuario_id`. Toda corrección de origen queda registrada por ese canal,
   con quién y cuándo. **Ninguna DDL sobre `public`.**

Verificado además: el edge `crm-importar-leads` **solo hace INSERT** (deduplica por
teléfono y descarta, no hace upsert), así que sellar `origen` no rompe la importación ni
el repegado del `.gs`. Y en `public.audit_log` hay **0** cambios históricos de origen: el
sellado no invalida nada de lo que ya está.

⚠️ Esta es la **única migración del plan que toca un camino de escritura**, y encima el
más caliente del CRM. Va con auditoría de `auditor-rls` antes del gate y con su propio
bloque en el oráculo transaccional.

### 3.5 Ledger

Entrada en `supabase/migrations/MIGRACIONES.md` por cada migración: qué cierra, decisión
de reloj (T3), decisión de roster (T7), el aviso del orden de despliegue en tres pasos, y
el hecho de que D toca el trigger de escritura.

---

## 4. Front — fichero por fichero

**Contrato nuevo**

- `app/src/lib/conversion-mensual.ts` — **NUEVO**. `ConversionMensualSchema` con
  **`v.object` (no strict)** a propósito: así una clave nueva del servidor no rompe
  bundles viejos, al revés que el cumplimiento.
  - `conversion_pct`: `v.nullable(v.pipe(NumeroRpcSchema, v.minValue(0)))` — **sin
    `maxValue`**.
  - `estado`: `v.picklist(['medible','solo_arrastre','sin_actividad'])`.
  - `fuentes.divisor`: `v.literal('crm.lead_asignaciones.asignado_en')` — es el
    fail-closed que impide que un servidor viejo cuele otra definición.
  - Helpers puros con su `.test.ts`: `lineaProcedencia()` → `"de agosto 12, de julio 3,
    de junio 1"` y `lineaReferidos()` → `"20 registrados · 12 cerrados · aporta 1,6 %"`.
- `app/src/data/crm-api.ts` — `obtenerConversionMensual(periodo, signal?)` con
  `safeParse` + verificación de que el periodo devuelto es el pedido; error
  `CONVERSION_MENSUAL_CONTRACT`. Mismo patrón que `listarMetricasConversiones`.
- `app/src/data/crm-queries.ts` — `crmQueryKeys.conversionMensual(periodo)` y
  `useConversionMensual(habilitada, periodo)`.

**Cumplimiento (el punto delicado)** — `app/src/lib/objetivos.ts`:

- `CumplimientoVendedorSchema.conversion_real`: **quitar `v.maxValue(100)`**.
  ← *Este es el cambio que impide que la migración B apague las metas de los tres roles.*
  Lo encontraron los tres revisores: la definición supera el 100 % por diseño, y ese cap
  vive dentro de un `v.strictObject` **fail-closed**.
- Añadir `numerador`, `cierres_referidos` y `cierres_no_referidos` como **`v.optional`**
  — obligatorio: el `strictObject` también falla por clave **faltante**, y entre el
  release de front y la migración B el servidor viejo no las manda.
- `fuentes_reales.conversion`: `v.picklist(['leads_resueltos','leads_recibidos_ponderado'])`.
- `agregarCumplimientos`: `conversionReal = resueltos > 0 ? redondear2(100 *
  sum(numerador) / sum(resueltos)) : null`. Sumar `convertidos` crudos deja de dar la
  conversión acordada.
- `metaVigente` y `metaConversionAplicable`: **no se tocan**.

**Ranking y adaptadores** — `app/src/lib/conversion-vendedores.ts`: `estadoConversion`
gana `'solo_arrastre'` y deja de mandarlo a «Fuera del ranking»; el desempate baja a
`numerador` y luego `divisor` (el entero `clientes` ya no ordena con numerador
ponderado); `adaptarConversionMensual` con el mismo fail-closed de siempre (colección
incompleta ⇒ bloque `indisponible`, **jamás** ceros).

**Pantallas**

| Fichero | Qué cambia |
|---|---|
| `hoy/inteligencia-comercial.tsx` | Fila de **procedencia** en `DetalleVendedor`; bloque **Referidos** con el aviso «los referidos cuentan enteros como leads recibidos y aportan el 15 % al cerrarse»; chip de `cobertura.medible=false` que sustituye el % por «Sin datos de asignación para este mes» |
| `hoy/ranking-vendedores.tsx` | Sub-renglón de procedencia; columnas `Leads`→**`Recibidos`** y `Clientes`→**`Cierres`**; rótulo del tab → «Cierres del mes (referidos al 15 %) ÷ leads recibidos en el mes»; barra con `min(conversion/maximo, 1)` para tolerar >100 % |
| `hoy/resumen-gerencia.tsx`, `hoy/gerencia.tsx` | Hero y «Mejores vendedores» al payload nuevo; «Todavía no hay leads resueltos» → **«Todavía no hay leads recibidos este mes»** |
| `hoy/equipo-gerencia.tsx` | **Deja de calcular el % a mano** (hoy es el único sitio donde el navegador divide enteros; con numerador ponderado sería una definición divergente y silenciosa). Lee `total.conversion_pct` |
| `hoy/vendedor.tsx`, `hoy/supervisor.tsx` | Tile → **«Conversión del mes»**; vacío correcto: «Sin leads recibidos este mes» (y con arrastre: «3 cierres arrastrados · sin leads recibidos») |
| `equipo.tsx` | Las filas viejas de `inteligencia.ts` se **re-rotulan** «Convertidos · últimos 45 días» para que no compitan con el ranking nuevo a 300 px |
| `hoy/distribucion-leads-gerencia.tsx` | **No se toca** (mide otra pregunta y ya lo declara en pantalla) |
| `lead-drawer.tsx` | El selector de origen pasa a **solo lectura** salvo gerencia dentro de 24 h, con el motivo escrito al lado. La UI debe decir la regla, no solo obedecerla |

**Alertas** — `app/src/lib/alertas-gerencia.ts`: el umbral pasa a
`LEADS_RECIBIDOS_MINIMOS_ALERTA_CONVERSION_VENDEDOR = 20` (con divisor = recibidos, un
umbral de 10 deja de filtrar: todos lo pasan todos los meses). Y `porcentajeValido` se
parte en dos: `porcentajeMetaValido` (0..100, para el objetivo) y
`porcentajeConversionValido` (≥0, sin techo) — si no, **todo asesor por encima del 100 %
se saltaría con `continue` y desaparecería del motor de alertas**, un fail-open
silencioso.

**Limpieza** — **borrar** `app/src/lib/cierres-del-mes.ts` y su test: es una definición
huérfana, con 100 líneas de doctrina convincente, que contradice la LEY. Dejarla es
garantizar una divergencia futura. `series-comerciales.ts`, `inteligencia.ts` y
`metricas-vendedores.ts` **no se tocan**: se re-rotulan en pantalla y se les añade un
comentario de cabecera diciendo qué miden y que **no** son la conversión del asesor.

**Tipos** — `app/src/lib/database.types.ts`: **delta a mano**, una firma
(`conversion_mensual_fn: { Args: { p_periodo: string }; Returns: Json }`).
**No correr `gen:types` completo contra prod**: reformatea el archivo curado y rompe
100+ tipos. Este delta es **bloqueante del release**: sin él, `npm run check` no pasa.

---

## 5. Modo demo — la demo cuenta igual que producción

Hoy la demo **no puede** reproducir la definición: `LEADS_DEMO` no tiene espejo del
ledger. No basta con retocar porcentajes a mano.

- `app/src/lib/demo-asignaciones.ts` — **NUEVO**. Episodios para los universos `d-v*` y
  `demo-v*`, que deben contener **obligatoriamente** los tres casos de la LEY:
  **A→B** (A 0/1, B 1/1) · **arrastre** (recibido en julio, cerrado en agosto) ·
  **referido** recibido y cerrado, para que `aporta_pct` no sea 0.
- `app/src/lib/demo-conversion-mensual.ts` — **NUEVO**. Implementa **la misma
  aritmética** y produce el payload. El fixture **se deriva, no se escribe a mano**: es
  la única forma de que la demo no enseñe otro negocio.
- `demo.ts`: `cumplimientoDemo(...)` cambia de firma a
  `(meta, capPEN[], capUSD[], cierresNoReferidos, cierresReferidos, recibidos)`.
- `screens/equipo.tsx`: `conversionDisponible={!yo?.demo}` **pasa a `true`** — ya hay
  fixture del payload del supervisor, que hoy no existía.

---

## 6. Tests

### 6.1 Oráculo SQL transaccional — `supabase/scripts/test-conversion-mensual.sql`

Autocontenido, `begin; … rollback;`, fixtures con prefijo `40000000-…`, mismo estilo que
`test-lead-asignaciones.sql`. Los bloques `raise exception 'CONV-xx: …'` van **antes** del
token final, así que `CONVERSION_MENSUAL_OK` solo se imprime si pasan los 16.

| # | Caso | Esperado |
|---|---|---|
| CONV-01 | A recibe y suelta en agosto; B recibe y cierra | A `0 de 1`, B `1 de 1` |
| CONV-02 | A→B→A dentro del mes | A divisor **1**, no 2 |
| CONV-03 | Recibido julio, cerrado agosto | numerador de agosto +1; divisor de agosto sin cambio; `procedencia` con `mes_nombre='julio'` |
| CONV-04 | Referido: 20 recibidos, 12 cerrados, divisor 113 | `aporta_pct = 1.59`; numerador `= no_ref + 1.80` |
| CONV-05 | Descartado con dueño | sigue en el divisor |
| CONV-06 | Descartado por coordinador en cola global | **no** entra en el divisor de nadie |
| CONV-07 | Lead soft-borrado (`activo=false`) | sigue en el divisor |
| CONV-08 | Divisor 0 + 3 cierres arrastrados | `conversion_pct = null`, `estado='solo_arrastre'` |
| CONV-09 | Mes flojo (divisor 2, 4 cierres) | `200.00`, sin recorte |
| CONV-10 | Convertir con A y luego reasignar a B (H2) | la conversión de A y de B **no se mueve** |
| CONV-11 | Julio-2026 | `cobertura.medible = false` con `motivo_no_medible` |
| CONV-12 | Numerador fraccionario | `0.15*3 = 0.45` exacto, no 0 |
| CONV-13 | Vendedor fuera de roster con producción | sale en `fuera_de_roster`, **no** en `responsables`, y `total` sigue cuadrando |
| CONV-14 | Cierre sin episodio | `cierres_sin_episodio = 1` y **no** suma al numerador de nadie |
| **CONV-15** | **Gerencia corrige `origen` a las 2 h** | el cambio **se aplica** y queda una fila en `public.audit_log` |
| **CONV-16** | **Gerencia corrige a las 26 h · supervisor corrige a las 2 h · vendedor corrige** | el `origen` **no se mueve** en los tres casos, y el resto del UPDATE **sí** se aplica |

Además, ampliar `test-tenencia.sql` con «reasignar lead terminal no crea fila» para dejar
el hueco H2 fijado por test.

### 6.2 `supabase/scripts/test-rls.mjs` — bloque nuevo

```
A · permitidos y forma
    gerencia → 200 'global' · directorio → 200 'global', MISMO conjunto de ids
    sup1 → 200 'equipo', subárbol RECURSIVO, NO ve la rama de sup2 ni a vendInactive
    vend1 → 200 'propio', EXACTAMENTE 1 fila y es la suya
B · denegaciones DURAS (42501, jamás payload de ceros)
    coordinador · vendInactive · clientBank · ajeno · anon
C · orden de errores
    coordinador + periodo basura → 42501 (NO 22023): el código de error no es
    un oráculo de pertenencia · gerencia + día 15 → 22023 · mes futuro → 22023
D · PARIDAD  (la invariante que la casa se comprometió a custodiar)
    la fila de vend1 que ve vend1 == la que ve sup1 == la que ve gerencia, campo a campo
E · invariantes aritméticas
    numerador == cierres_no_referidos + 0.15*cierres_referidos
    sum(procedencia[].cierres) == cierres_no_referidos + cierres_referidos
    total.* == sum(responsables[].*)   (incluido tras filtrar_desglose_sujetos_crm)
F · forma del contrato
    cada responsable trae SOLO las claves del contrato (un campo de más es
    superficie sin auditar)
```

### 6.3 Front (Vitest) — **con el gate de REALIDAD aplicado**

Cada pantalla lleva su caso en el **estado de producción** además del fixture lleno.

- `lib/conversion-mensual.test.ts` — **NUEVO**: parseo, `lineaProcedencia`,
  `lineaReferidos` (debe rendir exactamente `20 registrados · 12 cerrados · aporta
  1,6 %`), y rechazo cuando `fuentes.divisor` no es el literal esperado.
- `lib/objetivos.test.ts` — **caso nuevo obligatorio**: un vendedor con
  `conversion_real = 200` **parsea sin error** (es el que habría tumbado producción); y
  otro con las tres claves nuevas **ausentes** (servidor viejo) también parsea.
- `lib/conversion-vendedores.test.ts` — invertir «leads 0 es sin muestra»: ahora divisor 0
  + cierres > 0 ⇒ `solo_arrastre` **dentro** del ranking.
- `lib/alertas-gerencia.test.ts` — umbral en 20 recibidos; caso frontera de un asesor al
  120 % que **sí** entra al motor.
- **ESTADO REAL DE PRODUCCIÓN (nuevos, obligatorios)**: payload con `responsables: []`,
  `total.divisor = 0` y `cobertura.medible = false` → las tres pantallas renderizan sin
  excepción, **sin ceros inventados** y con el aviso de degradación correcto.
  *Este es exactamente el estado que hay hoy en la base: 1 lead, 0 cierres.*

### 6.4 Gate de realidad

Dos supuestos nuevos en `supabase/scripts/gate-realidad.mjs`: «episodios con `asignado_en`
en el mes en curso > 0» y «cierres con `resultado='convertido'` en el mes en curso > 0».
Hoy **fallarían los dos** — que es justo la información que el gate existe para dar.

---

## 7. Orden de despliegue y vuelta atrás

**Cuatro pasos, en este orden. No se puede comprimir.**

**Paso 0 — desplegar lo que ya está listo y sin publicar** (`04393f8`, `2f05698`,
`eb89df8`). Es lo que hace que la meta de conversión se pueda pactar de verdad, y lo que
pone en pantalla los arreglos de las metas de gerencia y supervisor. Va primero porque no
depende de nada de este plan.

**Paso 1 — SERVIDOR: migraciones A y D.** A es seguro precisamente porque es **100 %
aditiva**: crea RPC, tabla, helpers e índices, y no cambia el payload de ninguna función
existente. Nadie la lee todavía. D va aquí, no después: una vez que el 15 % está vivo, un
origen sin sellar es una palanca. Ciclo obligatorio: branch → aplicar → `seed:demo` →
`test-rls.mjs` → `test-conversion-mensual.sql` → advisors (0 ERROR) → merge.
**Prohibido `apply_migration` directo a producción.**
*Rollback*: `drop function crm.conversion_mensual_fn(date)` y `create or replace` de
`private.leads_before_update` con el cuerpo anterior.

**Paso 2 — FRONT (release completo).** Contrato nuevo + pantallas + **el cap
`maxValue(100)` fuera** + las claves nuevas como `v.optional` + los dos literales
aceptados + el delta manual de `database.types.ts`. El front nuevo **convive con el
servidor viejo**: el cumplimiento aún manda la definición antigua y el front la sigue
aceptando.
*Rollback*: redesplegar el ZIP anterior de `releases/`. El servidor sigue entero.

**Paso 3 — SERVIDOR: migración B.** Va **la última** porque `CumplimientoMetasSchema` es
`v.strictObject` y fail-closed: sus claves nuevas y el literal nuevo, contra un bundle
viejo, dejan **sin metas a los tres roles**. Con el paso 2 ya en producción, ese riesgo
no existe.
*Rollback*: aplicar la migración C (escrita **antes**) por el ciclo de branch. El front
nuevo tolera el literal viejo, así que revertir el servidor **no** rompe la pantalla —
esa tolerancia es lo que hace la reversión barata.

**Por qué A va servidor primero y B va front primero** — regla del vault
[[Orden de deploy del CRM: depende de la DIRECCIÓN|crm-orden-deploy-front-primero]]:
clave nueva en la **respuesta** de una RPC que el front ya valida estricto ⇒ **front
primero**. RPC nueva que nadie lee todavía ⇒ **servidor primero**, sin riesgo.
Por eso A y B van en **dos ficheros distintos**, con el orden en el nombre y una nota al
principio de B.

---

## 8. Riesgos aceptados

1. **El repegado del `.gs`** (H3) hunde la conversión del mes de importación para todos.
   Mitigado por `divisor_por_motivo` + acuerdo operativo (D7).
2. **Registrar referidos baja la conversión.** Consecuencia conocida y aceptada por
   Miguel. Efecto secundario: quien más registre, más alertas recibirá — por eso el umbral
   sube a 20.
3. **El divisor ya no lo controla el asesor**: se lo llena el reparto. Un mes de mucha
   entrada hunde a quien trabajó igual de bien. Mitigación: `recibidos` se pinta
   **siempre** al lado del %; el número solo miente por omisión.
4. **Los meses anteriores a agosto-2026 dirán «sin datos»** donde hoy hay un número. Se
   percibe como regresión: hay que explicarlo en el copy, no solo en el payload.
5. **`convertidos` puede superar a `resueltos`** en el cumplimiento. Invariante roto a
   propósito.
6. **`dados_de_alta` es el único número no reproducible en el tiempo** (usa
   `crm.leads.origen`). Está aislado: no entra en la aritmética.
7. **Siguen vivas otras definiciones de conversión** (`metricas_conversiones_fn` por
   cohorte de alta, `inteligencia.ts` a 45 días, `series-comerciales.ts`). Este ciclo
   **no las unifica**: las re-rotula para que no compitan, y **deja de añadir una más**.
   Unificarlas es el ciclo siguiente.

**Lo que NO se toca (decisión explícita)**: el trigger del ledger y el guard de tenencia;
`metricas_conversiones_fn` y `_equipo_fn` (siguen sirviendo embudo, orígenes, capital y
tendencia — solo pierden el papel de «quién convierte cuánto»); `metaVigente`;
`distribucion-leads-gerencia.tsx`; y ningún objeto de `public` (solo se **lee**
`public.perfiles` por los helpers de siempre, y se **inserta** en `public.audit_log` por
el trigger que ya existía). **Ninguna columna nueva en `crm.leads`** ⇒ ningún GRANT por
columna que olvidar.

---

## 9. Lo que falta decidir (con recomendación)

| # | Decisión | Recomendación |
|---|---|---|
| ~~**D1**~~ | ~~¿Se pacta **meta** de conversión sobre la definición nueva?~~ | ✅ **DECIDIDO por Miguel, 2026-08-10: este mes NO.** La conversión de agosto es **informativa**; la meta se pacta desde **septiembre**, con un mes real de datos delante. Hoy la base tiene 1 lead: fijar un número sería fijarlo a ciegas. **Consecuencia para la implementación:** la migración B deja de ser urgente — su razón de ser (H5, dos porcentajes distintos del mismo asesor a 300 px) solo muerde cuando hay una meta de conversión publicada contra la que medir. Sigue en el plan y sigue yendo la última, pero puede esperar al mes siguiente sin dejar nada incoherente. |
| **D2** | ¿El **supervisor con cartera propia** aparece como fila del ranking? | **No** (queda en `fuera_de_roster`), por paridad con las demás pantallas. Revisar a los 30 días: si `fuera_de_roster.cierres` no es cero, cambiar. |
| **D3** | «**Registrados**» en el bloque de referidos: ¿recibidos o dados de alta? | **Los recibidos.** Es la población que está en su divisor y la única con la que el «aporta 1,6 %» cuadra. Los dados de alta viajan al lado: cambiar el rótulo cuesta una línea de front y cero SQL. |
| **D4** | **Reapertura** de un descartado en otro mes: ¿vuelve al divisor? | **Sí**: es una oportunidad de trabajo nueva en un mes nuevo. |
| **D5** | Umbral de alerta de conversión baja | **20 leads recibidos**, y a partir del **día 10** del mes. Con 10 no filtra nada. |
| ~~**D6**~~ | ~~Ventana operativa para las cargas desde la hoja~~ | ✅ **DECIDIDO por Miguel, 2026-08-10: `FECHA_CORTE = "2026-08-15"`.** Nada entra al CRM hasta el 15 de agosto; lo anterior se queda fuera. ⚠️ **El corte por sí solo no basta**: las filas sin fecha legible lo esquivan por diseño (regla del 2026-07-27), así que hay que **pausar el temporizador del puente** hasta el 15 y reactivarlo ese día. Consecuencia: **agosto cuenta desde el día 15** — medio mes de ingreso, y por eso el primer mes completo de verdad es **septiembre**, que es justo donde D1 puso la meta. |
| **D7** | La corrección de origen de gerencia, ¿restaura en silencio o avisa? | **Restaura en silencio en la BD** (patrón de la casa) **pero la UI lo dice antes**: el selector sale bloqueado con el motivo. Que el usuario nunca descubra la regla por un cambio que no se guardó. |

---

**Alcance total**: 4 migraciones (A conversión · B cumplimiento · C rollback escrita por
adelantado · D origen sellado), 1 RPC nueva, 2 funciones modificadas, 1 tabla nueva,
4 índices, 3 helpers `private` nuevos, ~20 ficheros de front, 3 fixtures de demo
derivados, 1 oráculo SQL con 16 casos, 1 bloque nuevo en `test-rls.mjs`, 2 supuestos
nuevos en el gate de realidad y 1 fichero borrado.

**Decidido y cerrado**: D1 (meta desde septiembre, agosto informativo) · D6 (corte el
15/08/2026 + puente pausado hasta ese día) · T9 (la data vieja va a base fría, sin
excepciones en la fórmula). **Falta el OK de Miguel al plan entero para empezar a
escribir.** D2–D5 y D7 van con la recomendación de la tabla salvo que diga otra cosa: son
todas reversibles y de código.

Relacionado: [[Conversion mensual - definicion cerrada]],
[[Como se mide la conversion del asesor]], [[Por que el CRM nunca tuvo metas publicadas]],
[[CRM plan de escalabilidad a data gigante|crm-escalabilidad-plan]].
