# F4-e — Supervisor y gerencia: plan corto (06/10/2026, solo análisis, para decidir con Miguel)

Salió de un análisis de solo lectura del 06/10. Las citas marcadas **[V]** las verificó ese análisis en el archivo y la
línea; Claude volvió a comprobar la fuga del latido, que ya se corrigió en la undécima. **No hay código. Antes hacen
falta dos cosas de Miguel: la decisión 4 de `F4-PLAN-CORTO.md` (F4 o F6) y el diccionario de abajo (propuesta #17).**

## En una línea

Una vista **de solo lectura del día (hora de Lima)** que cuenta, por analista y por equipo:
- las llamadas del celular;
- cuántas tienen resultado y cuántas no;
- cómo están los celulares.

**Dónde se ve:**
- **Gerencia:** tercera pestaña de «Toda la operación hoy», con una tabla por equipo y el panel «Necesitan atención».
- **Supervisor:** su equipo en «Mi equipo hoy», con un botón y el bloque «Su celular» en el panel del analista.

**Qué necesita:** una **puerta agregada nueva** (la duodécima migración) y **ningún índice nuevo**, porque los de la
novena y los de datos ya cubren cada cifra. Falta confirmarlo con EXPLAIN.

## F4 o F6 (decisión 4, de Miguel)

| | En F4 (F4-e) | En F6 |
| --- | --- | --- |
| Periodo | Solo hoy y el estado de ahora | Histórico (30 días o agregados) |
| Cifras | En el celular, con resultado, al colgar, descartadas, sin resultado, por revisar, celulares, con problema | Además: retrasos, cobertura y entrantes (#15) |
| Puerta | La nueva | F6 la **amplía**; no crea otra |
| Costo de esperar | — | Durante el piloto, ni gerencia ni supervisión ven qué llamadas quedan sin resultado ni qué celular calla |

**Recomendación: en F4**, como paso propio, pero **después de F4-d** (el latido probado en C1) y con el diccionario
aprobado antes.

## Diccionario de métricas (borrador para el OK de Miguel, #17)

**Base común:**
- Solo `direccion = 'saliente'`.
- El universo son las llamadas **guardadas**: una llamada a un número que no es de ningún lead no se guarda. Por eso
  **«en el celular» = «llamadas a leads detectadas», no «llamadas hechas»**.
- Nunca se usa `private.llamadas_celular_recepciones`, que cuenta también las personales (N1).

| Cifra | Definición | Reloj («hoy» de qué) | No cuenta |
| --- | --- | --- | --- |
| **En el celular** | Eventos salientes del analista | Día de la llamada (`ocurrio_en`; si falta o el reloj está corrido, `recibido_en`) | Sin lead, entrantes, leads de baja |
| **Con resultado** | Enlaces cuya actividad no está deshecha | **Fecha del resultado** (la regla de la cifra del día) | Deshechas sin corregir |
| **Al colgar** | Con resultado y `via = 'al_colgar'` (siempre con el conteo al lado) | Igual | `pestana` y `manual`: cada una es una falla del celular |
| **Descartadas** | `descartado_con_motivo` | Hora del descarte (como «Qué pasó hoy») | Nunca son gestión |
| **Sin resultado** | **Estado de ahora:** `requiere_resultado`, sin enlace, lead activo, abierto y contactable. Se separan las de hoy y las anteriores (con la más antigua) | Ahora; abarca hasta 30 días (purga) | `requiere_devolucion`, por revisar, leads cerrados después |
| **Por revisar** | `por_revisar` (ambiguas, de la bolsa, reutilizables) | Ahora | No es «sin resultado» |
| **Celulares / sin latido** | Asignaciones vigentes; «sin latido» = el `estado_latido` de la undécima | Ahora | Asignaciones cerradas |
| **Sin dato** | Celular vigente sin llamadas y sin latido del día → **«—», no «0»** | Hoy | «Sin eventos no prueba inactividad» (`PLAN.md:36`) [V] |

**Regla:** «sin resultado» **no** usa la atención efectiva, que depende de quién mira. Si la usara, el supervisor y
gerencia verían cifras distintas del mismo analista.

**Puntos de definición para Miguel (A1–A7)**

| # | Pregunta | Recomendación |
| --- | --- | --- |
| A1 | ¿A quién se atribuye la llamada cuando el lead cambia de dueño? | **A quien marcó** (`analista_id`; decisión 7 y F6.2.1). La pendiente se marca «pasó a otro analista» |
| A2 | «Con resultado»: ¿fecha del resultado o hora del enlace? | **Fecha del resultado**. Solo difieren en tres casos: intención cumplida tras medianoche, enlace manual y enlace movido |
| A3 | «En el celular»: ¿día de la llamada o día de recepción? | **Día de la llamada**, explicando el retraso |
| A4 | ¿Leads dados de baja? | **Excluirlos**, como hace la bandeja (nadie los ve) |
| A5 | ¿Lead cerrado después de la llamada? | **Deja de ser «sin resultado»** |
| A6 | Umbral de «sin latido» | **7 h**, el mismo de la undécima, para que la tarjeta de F4-c y esta vista digan lo mismo |
| A7 | El celular del supervisor | Una línea aparte en «Su celular»: «Mi equipo hoy» solo lista vendedores |

## Puerta propuesta (descripción, sin SQL)

**Firma:** `crm.llamadas_celular_operacion_hoy_fn(p_supervisor_id uuid default null) → jsonb`.

**Puerta:**
- DEFINER, STABLE, `search_path = ''` y EXECUTE solo para `authenticated`.
- Roles: `llamadas_celular_actor(array['supervisor','gerencia'])`. Los demás reciben 42501, directorio incluido.
- `p_supervisor_id`:
  - gerencia, nulo → toda la operación;
  - gerencia, con un id → ese equipo;
  - supervisor → nulo o el suyo; otro id → 42501.

**Núcleo:**
- `private.llamadas_celular_operacion_hoy(p_actor, p_supervisor_id, p_ahora)`, INVOKER, STABLE y sin EXECUTE.
- `p_ahora` sirve para el oráculo, como en la novena.

**Ámbito y equipos:**
- Los analistas salen de `private.vendedor_ids_visibles(actor)` y se filtran por `analista_id`. **No** se usa
  `llamada_celular_visible` fila por fila: sigue al dueño del lead y cuesta una consulta por fila.
- Los equipos de gerencia salen de `private.gestion_diaria_pulso_roster()`, que está sellada: solo se llama. Así las
  claves coinciden con «Actividad del día».

**Salud:** reutiliza `private.celulares_salud_listar`, que ya no trae horas exactas desde la undécima.

**Forma del jsonb:**
- totales;
- `equipos[]` con los contadores;
- `analistas[]` con los contadores y sus `celulares[]` (etiqueta, `estado_latido`, `horas_sin_latido`, cola, versión).
- **Sin** números, leads ni `evento_id`: solo cifras y etiquetas.

## Mapa de reuso (lo principal)

| Qué hace falta | Qué existe | ¿Se reutiliza? |
| --- | --- | --- |
| Actor y roles | `private.llamadas_celular_actor` (`nucleo.sql:163`) [V] | Sí, tal cual |
| Ámbito | `private.vendedor_ids_visibles` [V] | Sí, tal cual |
| Equipos de gerencia | `private.gestion_diaria_pulso_roster` (`pulso_habitos.sql:124`) [V] | Sí, tal cual (sellada). En el banco reducido hace falta un doble |
| Equipo del supervisor | Árbol de `private.gestion_diaria_equipo_core` [V] | Adaptado (el núcleo está sellado) |
| Ventana del día en Lima | La de la novena | Sí, el molde |
| Detalle al tocar una cifra | La bandeja y «Qué pasó hoy» | Sí, tal cual: el panel abre la lista |
| Pestañas de gerencia | `screens/gestion-diaria/gerencia.tsx` (`PESTANAS`, `Tabs`) [V] | Adaptado: una tercera pestaña |
| Tabla por equipo | `components/gestion-diaria/tabla-equipos-gerencia.tsx` [V] | Parcial: estilos y accesibilidad sí; las columnas no |
| Panel del analista | `PanelAnalistaSupervisor` [V] | Adaptado: el bloque «Su celular» |
| Consulta y demo | `data/gestion-diaria-pulso-queries.ts` (refresco cada 60 s) [V] | Sí, el molde |
| Gate y banco | El tramo de F4-b y las pasadas 15–18 | Sí, el molde |

## Pruebas previstas

- **Banco reducido** (pasada nueva + mutantes). Casos del oráculo:
  - ámbito por rol y por equipo;
  - `p_supervisor_id` ajeno;
  - borde del día de Lima;
  - llamada de ayer resuelta hoy;
  - deshecha sin corregir y deshecha corregida;
  - por revisar;
  - lead de baja y lead convertido después;
  - entrante insertada a mano;
  - latido al día, viejo y «nunca»;
  - el jsonb sin datos personales.
- **Gate:**
  - roles;
  - aislamiento (sup2 no ve a vend1);
  - cifras antes y después de ingerir, registrar y descartar;
  - las claves de equipo iguales a las de `gestion_diaria_pulso_fn`.
- **Pantalla:**
  - «—» frente a 0;
  - «solo hoy»;
  - estado de producción sin celulares;
  - E2E en Docker con la demo;
  - `revisor-a11y`;
  - `npm run gate:realidad`.

## Orden y dependencias

1. Fusionar y aplicar el #190; después el #198 (octava a undécima).
2. Decisión 4 y el diccionario (A1–A7), de Miguel.
3. F4-c y F4-d: el latido probado en C1. Antes de eso, «sin latido» no significa nada.
4. Plan corto con OK → migración, oráculo y mutantes → gate → `auditor-rls` → banco de Miguel → tipos → pantalla →
   checks y E2E → release.

**En qué PR va:** se acuerda en `COORDINACION.md` cuando toque. Hoy la regla es «dos PR y nada más».

## Riesgos y límites

- **Rendimiento:** el piloto tiene 2–3 celulares, como mucho unos 1.800 eventos al día. Todas las cifras leen ventanas
  con índice. El objetivo es menos de 100 ms, y está **por medir**.
- **No coincide con la cifra del día de Gestión Diaria:** esa cuenta toda actividad, deshechas incluidas. Nunca se suman
  detectadas y gestiones, y el diccionario va en la pantalla.
- **Privacidad:** solo cifras y etiquetas. La fuga del latido ya está cerrada (undécima y macro del 06/10).
- **Pocas llamadas:** un porcentaje engaña; el conteo va siempre al lado.
- **El analista no ve lo mismo que su supervisor:** su «Pendientes · N» sigue al dueño actual del lead y a la atención
  efectiva. Hay que explicarlo en la pantalla.

## En llano

Es la vista para supervisión y gerencia: cuántas llamadas del celular hubo hoy por analista y por equipo, cuántas ya
tienen resultado y cuáles no, y qué celular dejó de dar señal. Es solo lectura y necesita una consulta nueva en la base.
Conviene hacerla después de activar el celular y con las definiciones de cada número aprobadas por Miguel. La principal:
a quién se le cuenta una llamada cuando el lead cambia de dueño.
