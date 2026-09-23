# Dos deudas de la conversión, para otra sesión

**Escrito el 23/09/2026**, justo después de unificar las doce puertas.
La tercera —fusionar Metas con la oficial— tiene su propio documento:
`FUSIONAR-METAS-CON-LA-OFICIAL.md`.

---

## Contexto en cinco líneas

La conversión pondera los cierres: un lead **no referido pesa 1**; un **referido
pesa 0,15 y no entra en el divisor**. El peso vive en `crm.conversion_pesos`
(columna `peso_referido`), versionado por `vigente_desde`, y lo lee
`private.peso_referido_conversion(date)`.

**Por qué 0,15** (decisión de Miguel del 10/08/2026, anotada en la propia tabla):
la primera versión ponía el referido **1 abajo y 0,15 arriba**, así que registrar
referidos **bajaba** la conversión del analista. El sistema castigaba justo lo que
se quiere premiar. Con la regla actual, recibir un referido es gratis y cerrarlo
solo puede sumar.

---

# 1. 🔴 El peso de la RENOVACIÓN — hay una ventana que se cierra al sellar

**El problema.** La renovación se pondera con el **mismo número** que el referido.
Cambiar el peso del referido —decisión comercial razonable— mueve el de la
renovación sin que nadie se entere. El **upgrade no está acoplado**: su peso es el
literal 1.

**Dónde exactamente.** En un solo punto: el parámetro escalar `p_factor` de
`private.conversion_episodios`, que hace **doble oficio** — peso del referido en
`conversion_cierres`, y peso de la renovación en la rama `'operacion'`.

## 🔴 LO URGENTE, Y ES IRREVERSIBLE

`crm.periodos_cerrados` guarda **solo `ponderacion_referido`**. No tiene columna
de renovación: el peso de renovación de un mes sellado se **reconstruye** a partir
del referido.

**Hoy la tabla está VACÍA (0 meses sellados).** En cuanto se selle el primero, ese
mes guarda solo el peso del referido y **su peso de renovación queda reconstruido
mal para siempre**. La ventana para arreglarlo sin pérdida **está abierta ahora
mismo** — y Miguel está a punto de sellar agosto.

👉 **Esto se hace ANTES del primer cierre de mes, o ya no se puede hacer bien.**

## Lo bueno: es más barato de lo que parece

- El front **ya está preparado**: `conversion-vendedores.ts:272` hace
  `peso_renovacion ?? peso_referido`, y el esquema es `v.object` con la clave ya
  declarada como opcional.
- **Tres funciones ya publican** la clave `peso_renovacion` en su payload — solo
  que alimentada con el mismo valor del referido. El contrato ya está separado;
  falta que el valor lo esté.
- `crm.conversion_pesos` tiene RLS ON, sin policies, grants solo a postgres, y se
  lee exclusivamente por la función definer. **No hay riesgo de grant por
  columna** (a diferencia de `crm.leads`).
- La tabla tiene **una sola fila** y no hay histórico: `vigente_desde=2026-07-01`,
  `peso_referido=0.150`.

## Las opciones

**A — la recomendada.** Añadir `peso_renovacion` a `crm.conversion_pesos` con
`default 0.15` (para que el histórico reproduzca el comportamiento actual), una
lectora análoga a `peso_referido_conversion`, y usarla en la rama `'operacion'`.
**No cambia la firma de `conversion_episodios`**, así que ningún llamador hay que
redeclararlo en cascada, y esa función **no está censada** (no exige re-sello).

**B — la cara.** Un séptimo parámetro en `conversion_episodios`. Cambia la firma →
hay que redeclarar sus ~8 llamadores directos, con riesgo de dejar dos overloads
del mismo nombre (ambigüedad) o algún llamador sin redeclarar. El beneficio sobre
la A es pequeño.

**C — obligatoria ANTES del primer cierre, vaya A o B.** Añadir
`crm.periodos_cerrados.ponderacion_renovacion`, redeclarar `crm.cerrar_periodo`
para que la escriba, y que la lectura mensual la use. **Dos funciones censadas**
(`crm.cerrar_periodo` y `crm.conversion_mensual_sin_cartera_fn`, las dos
`analitica`) hay que redeclarar y **re-sellar**. Hoy es baratísimo porque la tabla
está vacía.

⚠️ **NO añadas `peso_renovacion` al bloque `sondas` de Distribución**
(`metricas-distribucion.ts:337`): es `v.strictObject` y tumbaría la pantalla
entera.

**Verificación mínima:** que la cifra de hoy no se mueva ni un decimal con los
pesos separados pero iguales. Después, cambiar solo el de renovación y comprobar
que el referido no se inmuta.

**Volumen afectado hoy:** 12 renovaciones (agosto y septiembre) y 100 upgrades
(59 elegibles, de enero a septiembre).

---

# 2. «Conversión por origen» pinta los referidos al 100 %

**El problema.** En Resumen de Gerencia, el panel «Resultados por origen» muestra
la conversión de cada origen **sin ponderar**, mientras el número grande de arriba
pondera los referidos a 0,15.

**Lo que se ve hoy en pantalla** (medido, rango 01→22/09):

```
  héroe:                      4.32 %
  Resultados por origen:      referido — 72.70 %   ← primera fila, barra llena
                              formulario — 3.20 %
                              landing — 1.70 %
```

El 72,7 % es `8 contratos / 11 leads` sin ponderar. En el héroe, esos 8 cierres
aportan `8 × 0,15 = 1,2` y sus 11 leads **no están en el divisor**. La lista se
ordena por ese porcentaje y la barra se escala al máximo mostrado, así que **el
referido sale siempre primero y con la barra al 100 %**.

**Dónde:** `app/src/screens/hoy/resumen-gerencia.tsx:330-333` (orden y máximo),
`:549-550` (la fila y la barra). El 72,7 lo calcula el servidor en
`20260904210831_crm_conversion_llegadas_unicas.sql:709`.

## 🔑 El servidor YA publica lo que hace falta — no hay que añadir nada

En el bloque `origenes` viajan **`peso_en_nucleo`** (0.150 para referido, 1 para
el resto) y **`fuera_del_divisor_del_nucleo`** (true solo para referido). Se
añadieron el 04/09 precisamente «para que la barra se pueda rotular sin recalcular
nada». Verificado en la función viva, no solo en la migración.

**El front nunca consume `peso_en_nucleo`.** Solo aparece en el esquema de
validación y en un fixture de test. **El 0,15 no se ve en ninguna pantalla.**

## Está parcialmente atendido, y no basta

El 04/09 se añadió un pie de nota y el 07/09 un subtítulo. Pero el pie es de
**11 px**, va al final del panel, y **no dice el 0,15**: solo dice «queda fuera de
la base general».

## Y está DUPLICADO en la otra pestaña

El mismo defecto vive en **Inteligencia comercial**
(`inteligencia-comercial.tsx:652, :665, :902`), allí con una gráfica ECharts.
Los dos paneles se montan desde `hoy/gerencia.tsx`. **Arregla los dos o no
arregles ninguno.**

**Tests que fijan el comportamiento actual:** el describe «gráfica por origen —
publicación fail-closed» en `resumen-gerencia.test.tsx:670`.

---

## Herramientas que ya existen y te ahorran el susto

| Para qué | Dónde |
|---|---|
| ¿Quién HEREDA el payload de esta función? (un `grep` no lo ve) | `supabase/scripts/conversion/quien-me-envuelve.sql` |
| ¿Sigue cuadrando todo? Sella un mes de verdad y lo deshace | `supabase/scripts/conversion/ensayo-cierre-unificacion.sql` |
| El vigilante de las cinco vías | `crm.alarma_conversion_fn()` → `cuadra: true` |
| Antes de dar por bueno un arreglo de pantalla | `npm run gate:realidad` |

## Lo que NO se toca sin hablarlo con Miguel

El 0,15 en sí, cartera 1, oficina 0, la asimetría del registro manual y la
definición del divisor (leads no referidos recibidos en el mes, descartados
incluidos).

## La regla que más caro sale olvidar

**Medir gana a leer.** El 23/09, leer el código me dio dos conclusiones falsas.
Plantar una deuda de 2 puntos en una transacción que se deshace las corrigió en un
minuto.
