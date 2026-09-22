# Unificar las doce puertas de la conversión

**Estado:** plan v4 · **Ola 0 y Ola 1a escritas y ensayadas, ninguna aplicada**
**Fecha límite:** antes de sellar un mes
**Escrito:** 21/09 · **Remedido:** 22/09 · **Revisado por Codex:** 22/09 ·
**Olas remedidas con deuda plantada en producción:** 22/09 (v4)

> ⚠️ **Historial de errores de este documento, a propósito.**
> **v1 (21/09)** clasificó las puertas de memoria: **tres clasificaciones falsas**.
> **v2 (22/09)** las midió contra el cuerpo vivo, pero Codex la devolvió
> `REFUTADO EN PARTE` con **cinco P1**: el oráculo de verificación estaba mal, el
> hallazgo C6 atribuido al objeto equivocado, el core de la #5 mal identificado,
> a la #10 le faltaban dos anclajes y la #7 tenía un camino bruto sin ver.
> **Esta v3 incorpora esas correcciones.** Lo que sigue sin verificar va marcado.

---

## 🧪 LA MEDICIÓN QUE DECIDE LAS OLAS (22/09, deuda de 2 puntos plantada y deshecha)

Hasta la v3 las olas se repartieron leyendo los cuerpos. La v4 las reparte
**plantando una deuda de anulación de 2 puntos en producción** (dentro de una
transacción que termina en `raise`, sin escribir nada) y mirando quién cambia y
quién no, para el MISMO analista y el MISMO mes.

| # | Puerta | ¿publica una TASA? | De dónde sale | SIN deuda → CON deuda | ¿Discrepa? |
|---|---|---|---|---|---|
| 4 | `metricas_conversiones_fn` | sí, la grande | vivo | 4,24 % → 4,24 % | 🔴 **SÍ** (la oficial baja a 4,08 %) |
| 5 | `metricas_distribucion_leads_v3_fn` | sí | vivo | 4,24 % → 4,24 % | 🔴 **SÍ** |
| 6 | `metricas_conversiones_equipo_fn` | sí, por vendedor | vivo | numerador 6 → **6** | 🔴 **SÍ** |
| 7 | `cumplimiento_metas_fn` | numerador | oficial, CON ajuste | numerador 6 → **4** | no |
| 8 | `cumplimiento_metas_sin_cartera_fn` | sí | oficial, CON ajuste | numerador 6 → **4** | no |
| 9 | `series_comerciales_fn` | sí | **delega** en `private.conversion_mensual_pct_para_series` | — | no |
| 10 | `metricas_multiempresa_fn` | sí | vivo | **no se puede llamar** | ⚪ no llega a pantalla |
| 11 | `resumen_cartera_fn` | **no** | vivo | cuenta cierres, no pondera | no |
| 12 | `cerrar_periodo` | escribe la foto | bruto, correcto por diseño | — | no |

Oficial, para el mismo analista: **6 → 4**. Las tres primeras no se mueven; el
resto sí, o no publica tasa.

**Dos correcciones a la v3, las dos por medición:**

1. **La #7 NO tiene un camino bruto.** La v3 la dejaba en Ola 2 «solo para
   declarar» y yo llegué a sospechar lo contrario leyendo su cuerpo (usa
   `private.conversion_mensual_por_vendedor`, que sirve el bruto, y no se ve un
   `conversion_con_ajuste`). **La medición lo refuta:** publica 4 con la deuda
   puesta y una clave `ajuste: {pendiente: 2}` en cada fila, igual que la #8.
   Leer el cuerpo no bastaba: el ajuste entra por otro camino.

2. **La #10 no puede discrepar hoy: está detrás de una bandera apagada.**
   `crm.metricas_multiempresa_fn` empieza por
   `if not coalesce((select activo from crm.multiempresa_flags where nombre='metricas_multiempresa_sombra'), false)`
   y responde `P0409 · El informe multiempresa está en preparación`. Ninguna
   pantalla la ve. Sigue siendo la única que calcula por su cuenta **y** no
   llama a la mensual, así que hay que arreglarla **antes de encender esa
   bandera** — pero no compite con las de gerencia.

**Conclusión sobre el reparto:** Ola 1 = #4, #5, #6 era correcto, y ahora está
medido en vez de razonado. Ola 2 se reduce a **#10 (antes de encender su
bandera)** y a las declaraciones de #7, #8, #9 y #12. La #11 no publica ninguna
tasa: declarar `fuente` ahí sería inventar un contrato que esa puerta no tiene.

### Estado real al 22/09

| Paquete | Qué | Estado |
|---|---|---|
| Ola 0 | `20260922225649` la alarma concilia bruto y neto | ensayada · **sin aplicar** |
| Ola 1a | `20260922232553` #4 declara | ensayada · auditada · **sin aplicar** |
| Ola 1a | `20260922233257` #6 declara | ensayada · **sin aplicar** |
| Ola 1a | `20260922233545` #5 declara (con pestillo de front) | ensayada · **sin aplicar** |
| Ola 1b | las tres delegan en `crm.conversion_mensual_fn` | sin escribir |

El front del contrato ya está en `main` (`c2c9274b`) pero **no publicado**: el
bundle vivo es `build-20260922T221442353Z` = `7d65fcdb484f`.

---

## El problema

Doce puertas publican conversión sobre un núcleo único
(`private.conversion_episodios`) y cada una le pregunta a su manera. Hoy todas
dan el mismo número **por casualidad**: `crm.periodos_cerrados` está VACÍO.

### La formulación correcta del riesgo (corregida por Codex)

La v2 decía «hay una discrepancia que no necesita el sello». **Impreciso.** El
registrador de la deuda sale antes si el mes no está cerrado
(`20260901180000:402`: `if not exists (select 1 from crm.periodos_cerrados …) then return null`).

> **Lo correcto:** un mes **abierto** puede discrepar por deuda procedente de un
> mes **previamente sellado**. Sin ningún sello, nunca hay deuda.

Y el descuento **no vive en el núcleo**: se aplica en la LECTURA mensual
(`20260904210831:1641` — *«se descuenta aquí, en la lectura, y no dentro de
`conversion_mensual_por_vendedor` […] se descontaría dos veces»*). Decir «el
núcleo entrega ya neto» describe mal la arquitectura.

---

## 🔴 OLA 0 — arreglar el oráculo (antes de tocar ninguna puerta)

**Esto es nuevo y es lo primero.** El plan v2 iba a verificarse con un criterio
que la propia corrección haría fallar.

### El problema, reproducido por Codex

`crm.alarma_conversion_fn` (`20260921182011:114`) toma el núcleo directo como
`sum(e.aporte_numerador)` —el **bruto**— y exige **igualdad** entre los cuatro
caminos. `coherencia.mjs:35` hace lo mismo: `const base = c.nucleo_directo`.

> Reproducción: núcleo bruto 3; mensual, rango y distribución correctamente
> delegados al neto 2 → **el gate devuelve ROJO, con seis diferencias.**

**Hacer el trabajo bien pondría la alarma en rojo.** El criterio «gate en verde y
ni un número movido» que escribió la v2 **es incorrecto**: vale para el caso sin
deuda, no para aquel en que precisamente se corrige una discrepancia.

### Y el mutante propuesto no prueba nada

Codex ejecutó el mutante de la v2 —forzar `es_mes_calendario: true → false`—:
**ambas fotos verdes y `sin_cambios: true`.** Ni el gate ni la alarma leen esa
declaración.

### Qué hay que hacer en la Ola 0

1. **Rediseñar el oráculo** para distinguir tres situaciones, en vez de exigir
   igualdad a ciegas:
   - igualdad oficial (sin deuda pendiente),
   - recálculo **declarado** (`fuente: 'rango_vivo'`),
   - conciliación **bruto ↔ neto** (la diferencia debe ser exactamente el ajuste).
2. **Mutantes que muerdan de verdad**, con diferencias numéricas reales: deuda
   mayor que el bruto, cambio de roster, mes abierto contra mes cerrado.
3. **C6, localizado con precisión (22/09) y con su razón leída.**
   `crm.cerrar_periodo` **NO menciona** `cierres_sin_episodio`. El literal vive
   en `crm.conversion_mensual_sin_cartera_fn`, y esa misma función tiene **las
   dos** ramas:

   | Rama | Qué publica |
   |---|---|
   | mes **SELLADO** | `'cierres_sin_episodio', 0` ← el literal |
   | mes **ABIERTO** | `(select s.cierres_sin_episodio from sonda s)` ← la medida real |

   Y el código explica por qué: *«la sonda se calculaba sobre datos vivos; en un
   mes sellado no se recalcula (mentiría sobre el momento del sello) y se
   declara en cero, que es lo que la foto puede afirmar»*.

   🔑 **El razonamiento es medio correcto y por eso el arreglo no es obvio.** Es
   cierto que recalcular sobre datos vivos mentiría sobre el momento del sello.
   Pero declarar **cero** es afirmar «no hubo cierres sin episodio», y eso no se
   sabe: la foto no puede afirmarlo, solo puede callarlo. Las tres salidas, de
   peor a mejor:

   - dejar el cero → **un mes puede sellarse con la sonda en rojo y salir en
     verde para siempre**. Es el defecto.
   - publicar `null` → honesto («no medido»), y no cuesta nada. Pero pierde el dato.
   - **capturar la sonda AL SELLAR y guardarla en la foto** → es lo correcto, y
     es lo que hace falta de verdad. Exige tocar `crm.cerrar_periodo` (el
     escritor) **y** la rama sellada del lector.

   ⚠️ Y hay un orden que resolver, que también señaló el revisor: `cerrar_periodo`
   inserta en `periodos_cerrados` **antes** que las filas de la foto. Leer la
   mensual entre ambos pasos observaría una foto incompleta. La sonda hay que
   capturarla **antes** de marcar el período como cerrado, o después de escribir
   todas las filas — pero no en medio.

   Para los meses ya sellados antes de este cambio, la clave debe ser `null`, no
   0: no se puede inventar hacia atrás lo que nunca se midió. **Hoy no hay
   ninguno** (`crm.periodos_cerrados` está vacío), así que es la mejor ventana
   para arreglarlo y no se repite.
4. **Decidir cuándo se captura la sonda del sello.** La #12 inserta
   `periodos_cerrados` **antes** que las filas de la foto: leer la mensual entre
   ambos pasos observaría una foto incompleta.

**Sin la Ola 0, las demás olas no se pueden verificar.**

---

## Inventario (medido, con las correcciones de Codex)

| # | Puerta | ¿Discrepará? | Qué le falta | Ola |
|---|---|---|---|---|
| 1 | `conversion_mensual_fn` | — | es la fuente | — |
| 2 | `metricas_vendedores_fn` | — | ✅ delega | — |
| 3 | `cierre_mes_estado_fn` | — | ✅ delega | — |
| 4 | `metricas_conversiones_fn` | 🔴 sí | fuente + declaración | 1 |
| 5 | `metricas_distribucion_leads_v3_fn` | 🔴 sí | fuente + declaración | 1 |
| 6 | `metricas_conversiones_equipo_fn` | 🔴 sí | fuente + declaración | 1 |
| 7 | `cumplimiento_metas_fn` | 🔴 **sí** (corregido) | **camino bruto + declaración** | **1** |
| 8 | `cumplimiento_metas_sin_cartera_fn` | ✅ no | declarar | **1** |
| 10 | `metricas_multiempresa_fn` | 🔴 sí | fuente + **tres sellos** | 2 ·flag OFF |
| 11 | `resumen_cartera_fn` | 🔴 sí* | declarar y rotular | 2 |
| 9 | `series_comerciales_fn` | ✅ no | declarar | 2 |
| 12 | `cerrar_periodo` | — **es el escritor** | rediseño, no declaración | **0** |

\* Sirve dos cifras al mismo actor sin decir cuál manda.

### Las correcciones de Codex, una a una

**#7 sube a Ola 1 — ✅ CONFIRMADO Y MEDIDO (22/09), ya no es hipótesis.**

Su cuerpo ramifica explícitamente, y su propio comentario lo dice: *«Para un mes
cerrado salen del JSON append-only del sello; para uno abierto se proyectan en
vivo desde los mismos núcleos»*.

```sql
if v_global and v_cerrado then
    select pc.cobertura->'fuera_ranking' ... from crm.periodos_cerrados   -- ✅ la foto
elsif v_global then
    with conv as materialized (
      select cm.* from private.conversion_mensual_por_vendedor(...) cm )  -- 🔴 EL BRUTO
```

y publica `'numerador', coalesce(cv.numerador, 0)` (`p7.sql:103`).

**El conteo que lo cierra:**

| | `conversion_con_ajuste` | `ajuste_pendiente_por_vendedor` |
|---|---|---|
| la mensual (`conversion_mensual_sin_cartera_fn`) | **2** | **1** |
| **#7** | **0** | **0** |

**La #7 no descuenta la deuda en ninguna parte de su cuerpo.** Con un mes
abierto y deuda de un mes previamente sellado: analista del roster sin meta
publicada, divisor 10, bruto 3, deuda 1 → **#7 publica 3 y la mensual 2, en la
misma pantalla.** Su arreglo **no es «solo declarar»: le falta el descuento.**

**#8 y #9 se sostienen.** Codex no logró demostrar discrepancia: la #8 sirve
`v.conversion_pct` de la foto cerrada y aplica ajuste en abierto; en la #9,
`conversion_mensual_pct` recibe `nm.pct` de la mensual oficial.

**#12 baja a Ola 0 y cambia de naturaleza.** No admite «declaración mínima». Su
cuerpo explica por qué recalcula: *«`conversion_mensual_fn` recorta por
`auth.uid()` y el cierre necesita la foto completa»* (`p12.sql:136`). Y **no
olvida el descuento**: liquida con `private.saldar_ajustes` y guarda
`numerador - sal.aplicado_numerador`. Es el **escritor**, y define la evidencia
irreversible que consumirán las demás.

**#10 necesita TRES sellos, no uno.** Verificado hoy: además de su exención, está
anclada en `auxiliares_analitica_lc_auditados` con
`md5(pg_get_functiondef) = 4ab8a07f4794c015c4bb7264206dafcf` —**idéntico al
vivo**— y el assert del 22/09 fija además la definición del propio helper
(`e43357800b6d79050c7ca7af6c6844b8`). Cadena completa: **función → helper de
auxiliares → anclaje del assert → sello agregado de exenciones.**

**#5: el core estaba mal identificado.** Verificado: existen **tres** cores
(`_core`, `_v2_core`, `_v3_core`). El despachador manda V3 a
`private.metricas_distribucion_leads_v3_core`, y ahí se asigna
`'nucleo_numerador', v_num_total`. **El volcado de la v2 era el core base:
aquella parte del análisis hay que rehacerla.** Conservar además la frontera
`private.sanitizar_sujetos_distribucion_crm`.

---

## Las trampas (corregidas y ampliadas)

1. **`v.strictObject` fail-closed** en el front de #5, #7 y #8 ⇒ **front primero
   es bloqueo, no consejo.** Codex reprodujo el rechazo.
2. 🔴 **`v.object` NO conserva las claves nuevas: las ELIMINA del resultado.** No
   basta con que el servidor declare la fuente — el esquema y el consumidor deben
   conservarla. Y `metricas-conversiones.ts:284` fija `version: v.literal(1)`:
   cambiar versión rompe también a los laxos.
3. **Tocar el cuerpo caduca la declaración** en el trinquete. Censadas: #6, #9,
   #10, #11, #12, más **la implementación de #4**, que la v2 omitió. Ojo:
   *declarada* no es *censada* — #6 y #11 son declaraciones históricas fuera del
   censo.
4. **Solo #5 es de `crm_metricas_bridge`.** El canal de publicación no puede
   asumir ese rol (42501).
5. **`test-rls.mjs:6969`** (no 6949) afirma `d.version === 2`, y es específica de
   la #9. Además **`--preflight` sale antes** (`process.exit(0)` en la línea 243):
   **el preflight no prueba esa aserción.**
6. ~~`p4i.sql:52` acepta `or p_hasta = v_hoy`~~ **✅ NO ES UNA TRAMPA, medido el
   22/09 — y esto abarata toda la Ola 1.**

   El revisor avisó de que reutilizar ese indicador «clasificaría mal el mes
   hasta hoy». Se comprobó y es al revés: **ese test ES la regla de Miguel**.
   «Mes completo», para el mes vigente, es del día 1 a hoy — y `v_hoy` está en
   **hora de Lima** en las tres puertas (`(now() at time zone 'America/Lima')::date`),
   no en UTC.

   🔑 **Las TRES puertas de la Ola 1 ya calculan ese test, y lo hacen idéntico:**

   | Puerta | Línea | Variable |
   |---|---|---|
   | #4 `metricas_conversiones_implementacion` | 48–54 | `v_periodo` |
   | #5 `metricas_distribucion_leads_v3_core` | 54–60 | `v_periodo` |
   | #6 `metricas_conversiones_equipo_fn` | 63–69 | `v_periodo` |

   ```sql
   v_periodo := case
     when p_desde = date_trunc('month', p_desde)::date
      and date_trunc('month', p_hasta)::date = date_trunc('month', p_desde)::date
      and (p_hasta = (date_trunc('month', p_desde) + interval '1 month' - interval '1 day')::date
           or p_hasta = v_hoy)
     then p_desde
   end;
   ```

   **Consecuencia práctica:** `es_mes_calendario` NO hay que inventarlo ni
   endurecerlo. Es `v_periodo is not null`, una expresión, en las tres. Y la
   rama de delegación tiene su condición ya escrita:
   `if v_periodo is not null and p_origen is null then …`.

   La Ola 1 deja de ser «escribir lógica nueva» y pasa a ser **«publicar una
   variable que ya existe, más la rama que la usa»**.
7. **Guardar la alarma en la #12 rompería el cierre manual**: la alarma
   (`20260921182011:76`) rechaza claims que no sean `service_role`, y la #12
   admite Gerencia. `SECURITY DEFINER` no transforma los claims.

---

## Orden de ejecución

| Ola | Contenido | Por qué |
|---|---|---|
| **0** | Oráculo y alarma · diseño y pruebas de **#12** · C6 en escritura **y** lectura | Define la evidencia irreversible que consumen las demás. **No sellar todavía.** |
| **1** | #4, #5, #6, **#7**, #8 | Los lectores oficiales. **#7 sube: su camino bruto está MEDIDO** |
| **2** | #10, #11, #9 | #10 baja: su flag está apagado (medido). Las otras dos, solo declarar y rotular |
| **Después** | El primer sellado | Solo tras verificar lectores, escritor, deuda y alarmas **juntos** |

**Sobre #10: ✅ MEDIDO (22/09) — el flag `metricas_multiempresa_sombra` está
`false`.** La puerta está bloqueada, así que **baja a Ola 2**, como Codex
condicionó. Sigue necesitando sus **tres sellos** cuando le toque.

### Por cada migración, sin excepción

- Preflight con el **md5 exacto de `pg_get_functiondef`**. Acreditar por
  fragmentos **no vale**.
- Re-sellado de **todas** sus declaraciones, con su `clase`.
- Postflight: huella candidata, propietario, ACL, y que las claves viajen.
- `auditor-rls` · banco Docker · `npm run check` · advisors.

---

## Qué NO entra

- **Los pesos y las reglas cerradas no se tocan**: referido 0,15 · cartera 1 ·
  oficina 0 · la asimetría del registro manual.
- Las dos cifras de `series_comerciales`: se rotulan, no se unifican. Su
  declaración necesita alcance **por medida y por mes**.
- ⚠️ **Riesgo de doble descuento** si se trasladara el ajuste al núcleo: hoy se
  aplica en la lectura, a propósito.

## Cómo se sabrá que está hecho

1. El oráculo nuevo distingue las tres situaciones, y **hay un mutante con
   diferencia numérica real que lo hace saltar**.
2. Con un mes sellado, Resumen y Conversiones sirven **la foto**.
3. Ninguna pantalla divide.
4. `cierres_sin_episodio` publica la **medida real**, no el literal cero.
5. Las nueve declaran `es_mes_calendario`. Hoy: **cero**.

## Lo que falta antes de implementar

1. Volcar en vivo: base mensual, `_v3_core` y su despachador, helper de series,
   `conversion_mensual_sin_cartera_fn`, y los asserts afectados.
2. ~~Resolver el contraejemplo de #7~~ ✅ **HECHO 22/09: confirmado y medido.**
3. ~~Medir el flag `metricas_multiempresa_sombra`~~ ✅ **HECHO 22/09: `false`.**
4. Rediseñar alarma y C6 **antes** de implementar ninguna ola. ← **lo que sigue**
