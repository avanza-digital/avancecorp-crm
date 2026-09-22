# Unificar las doce puertas de la conversión

**Estado:** plan v3, sin ejecutar · **Fecha límite:** antes de sellar un mes
**Escrito:** 21/09 · **Remedido:** 22/09 · **Revisado por Codex y corregido:** 22/09

> ⚠️ **Historial de errores de este documento, a propósito.**
> **v1 (21/09)** clasificó las puertas de memoria: **tres clasificaciones falsas**.
> **v2 (22/09)** las midió contra el cuerpo vivo, pero Codex la devolvió
> `REFUTADO EN PARTE` con **cinco P1**: el oráculo de verificación estaba mal, el
> hallazgo C6 atribuido al objeto equivocado, el core de la #5 mal identificado,
> a la #10 le faltaban dos anclajes y la #7 tenía un camino bruto sin ver.
> **Esta v3 incorpora esas correcciones.** Lo que sigue sin verificar va marcado.

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
3. **C6, en su objeto correcto.** Verificado hoy: `crm.cerrar_periodo` **NO
   menciona** `cierres_sin_episodio`. El literal `'cierres_sin_episodio', 0` está
   en la LECTURA (`20260904210831:1480`), y quienes lo publican son
   `crm.metricas_vendedores_fn` y `crm.conversion_mensual_sin_cartera_fn`.
   **Arreglar la #12 no quitaría ese cero.** Hay que tocar escritura **y** lectura.
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
| 10 | `metricas_multiempresa_fn` | 🔴 sí | fuente + **tres sellos** | **1** |
| 11 | `resumen_cartera_fn` | 🔴 sí* | declarar y rotular | 2 |
| 9 | `series_comerciales_fn` | ✅ no | declarar | 2 |
| 12 | `cerrar_periodo` | — **es el escritor** | rediseño, no declaración | **0** |

\* Sirve dos cifras al mismo actor sin decir cuál manda.

### Las correcciones de Codex, una a una

**#7 sube a Ola 1.** La v2 la daba por inofensiva. En `p7.sql:103` publica
`'numerador', coalesce(cv.numerador, 0)` en la rama `fuera_ranking`, **sin el
descuento de la deuda**, mientras la mensual usa `roster_metas_vendedores()` y
descuenta por fila. Contraejemplo: divisor 10, bruto 3, deuda 1 → **#7 publica 3,
la mensual 2**. ⚠️ **Hipótesis respaldada por ambos recorridos, no medida**:
falta el cuerpo vivo de `conversion_mensual_sin_cartera_fn`. **Probarlo antes de
implementar.**

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
6. 🔴 **`p4i.sql:52` acepta `or p_hasta = v_hoy`** para `v_periodo`. Reutilizar ese
   indicador tal cual como `es_mes_calendario` **clasificaría mal el mes hasta
   hoy**. Hay que endurecerlo, no reciclarlo.
7. **Guardar la alarma en la #12 rompería el cierre manual**: la alarma
   (`20260921182011:76`) rechaza claims que no sean `service_role`, y la #12
   admite Gerencia. `SECURITY DEFINER` no transforma los claims.

---

## Orden de ejecución

| Ola | Contenido | Por qué |
|---|---|---|
| **0** | Oráculo y alarma · diseño y pruebas de **#12** · C6 en escritura **y** lectura | Define la evidencia irreversible que consumen las demás. **No sellar todavía.** |
| **1** | #4, #5, #6, **#7**, **#8**, **#10** | Los lectores oficiales. #7 sube por su camino bruto; #10 mientras no se acredite que su flag la deja inaccesible |
| **2** | #11, #9 | Solo declarar y rotular |
| **Después** | El primer sellado | Solo tras verificar lectores, escritor, deuda y alarmas **juntos** |

**Sobre #10:** `p10.sql:19` bloquea la puerta si `metricas_multiempresa_sombra`
está apagada. **No hay medición de ese flag.** Si está OFF, baja a Ola 2. Medirlo
es un prerrequisito barato.

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
2. **Resolver el contraejemplo de #7**: medirlo, no suponerlo.
3. Medir el flag `metricas_multiempresa_sombra`.
4. Rediseñar alarma y C6 **antes** de implementar ninguna ola.
