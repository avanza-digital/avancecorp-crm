ROLE: SECONDARY_REVIEWER.

Do not modify files. Do not implement the task. Do not invoke Claude. Do not
delegate to another coding agent. Do not create another review chain.

Tu único trabajo es **intentar REFUTAR el plan** que hay en
`CRM-Avance-Corp/pendientes/unificar-puertas.md`. Léelo entero primero. No lo
confirmes por cortesía: búscale el fallo. Si no lo encuentras, dilo, pero solo
después de haberlo intentado en serio.

El repo está en `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop`
(el CRM en `CRM-Avance-Corp/`). **No tienes acceso a la base de datos.** Los
cuerpos VIVOS de producción, volcados hoy 22/09, están en el directorio que se te
añadió con `--add-dir`: ficheros `p<N>.sql` (y `p4i.sql`, `p5i.sql` para las
implementaciones). **Ésa es la verdad sobre lo que corre; el árbol puede diferir.**
`p1.sql` es `crm.conversion_mensual_fn`, la definición oficial: léelo primero.

---

## EL PROBLEMA

Doce puertas publican conversión sobre un único núcleo
(`private.conversion_episodios`), y cada una le pregunta a su manera. Hoy todas
dan el mismo número **por casualidad**: `crm.periodos_cerrados` está VACÍO
(medido) y no hay deuda de anulación viajando entre meses.

La regla que decidió Miguel el 21/09 y que **no se discute**: mes calendario
completo y sin filtro de fuente → se pide el bloque a `crm.conversion_mensual_fn`
(foto sellada + descuento por anulaciones). Cualquier otro caso → cálculo en vivo
**declarado** en el paquete.

## LO QUE MEDÍ EN PRODUCCIÓN (22/09) Y QUE PUEDES DAR POR CIERTO

| # | Puerta | ¿divide? | ¿llama a la mensual? | dueño |
|---|---|---|---|---|
| 4 | `metricas_conversiones_fn` → `private.metricas_conversiones_implementacion` | SÍ | sí, **solo en el CTE de la sonda** | postgres |
| 5 | `metricas_distribucion_leads_v3_fn` | no | no | **crm_metricas_bridge** |
| 6 | `metricas_conversiones_equipo_fn` | SÍ | sí | postgres |
| 7 | `cumplimiento_metas_fn` | no | sí | postgres |
| 8 | `cumplimiento_metas_sin_cartera_fn` | SÍ | sí (1 en código, 1 en comentario) | postgres |
| 9 | `series_comerciales_fn` | no | sí | postgres |
| 10 | `metricas_multiempresa_fn` | **SÍ** | **NO** | postgres |
| 11 | `resumen_cartera_fn` | no | no | postgres |
| 12 | `cerrar_periodo` | no | sí | postgres (md5 `9efc07b35e9b`) |

Ninguna de las nueve declara hoy `es_mes_calendario`. Cero de nueve.

## LAS AFIRMACIONES DEL PLAN QUE DEBES ATACAR

**A1 — El reparto en olas.** Ola 1 = #4, #5, #6 (lo que ve gerencia y puede
discrepar ya). Ola 2 = #7, #8, #10, #11. Ola 3 = #9, #12.
¿Alguna está en la ola equivocada? En particular: ¿es defendible que **#10**, que
calcula por su cuenta, NO sea ola 1? ¿Y que **#12**, que escribe la foto, sea
ola 3?

**A2 — «Estas cuatro no discreparán: solo les falta declarar» (#7, #8, #9, #12).**
🔴 **ÉSTE ES EL FALLO CARO Y ES POR DONDE MÁS QUIERO QUE ATAQUES.** Si una de
esas cuatro sí puede publicar una cifra distinta de la oficial, el plan la deja
para el final creyéndola inofensiva. Busca en su cuerpo vivo cualquier camino en
que su cifra se calcule en vivo mientras la mensual sirve la foto, o en que no
reste la deuda de anulación.

**A3 — «Hay una discrepancia que no necesita el sello».** El plan afirma que el
núcleo entrega el numerador ya neto del ajuste por anulaciones y que las puertas
que calculan no lo restan, así que basta la primera deuda cruzando de mes.
¿Es cierto? ¿O el ajuste solo existe cuando hay un mes sellado, y entonces la
afirmación es falsa y el plan asusta de más?

**A4 — Las cinco trampas.** (1) `v.strictObject` fail-closed en el front de #5,
#7 y #8 ⇒ front primero es bloqueo, no consejo. (2) Tocar el cuerpo caduca la
declaración en `private.analitica_leads_citas_exenciones` (censadas: #6, #9, #10,
#11, #12). (3) Solo #5 es de `crm_metricas_bridge`. (4) `crm.alarma_conversion_fn`
se pondría en rojo con el cambio mínimo de alguna puerta. (5)
`test-rls.mjs:6949` afirma `d.version === 2` a pelo.
¿Alguna es falsa? **¿Falta alguna trampa que el plan no vio?**

**A5 — Dónde se interviene.** El plan dice tocar la IMPLEMENTACIÓN en #4 y #5, y
la función misma en las demás. ¿Es correcto en cada caso? ¿Hay alguna donde
intervenir ahí rompa un borde de privacidad o un filtro de sujetos?

**A6 — Lo que el plan declara fuera de alcance**: los pesos (referido 0,15,
cartera 1, oficina 0), la asimetría del registro manual, y las dos cifras de
`series_comerciales`. ¿El plan respeta eso, o alguno de sus cambios mínimos las
toca sin darse cuenta?

## CONTEXTO QUE NO DEBES IGNORAR

- **Acreditar un cuerpo por FRAGMENTOS no vale**: hay que fijar el md5 exacto de
  `pg_get_functiondef`. (Lección pagada hoy: un preflight que comprobaba nueve
  trozos habría sellado un cuerpo con el candado roto.)
- **Cada trinquete sella a su manera**: F5.a y F6.a sellan el cuerpo SIN
  comentarios; la F7 en CRUDO. Leer la fuente del assert antes de calcular nada.
- «Llama a X» **no** significa «publica la cifra de X»: mira qué se ASIGNA a la
  clave de salida.
- **NO HAY HALLAZGO SIN EVIDENCIA**: archivo:línea y cita literal. Distingue
  hecho de hipótesis y dilo cuando sea hipótesis.

## FORMATO DE SALIDA

VERDICT (REFUTADO / NO REFUTADO / REFUTADO EN PARTE) · SUMMARY · FINDINGS P0–P3
(cada uno con archivo:línea y cita) · **REPARTO EN OLAS QUE TÚ DEFENDERÍAS**, con
el motivo de cada cambio respecto al del plan · RIESGOS Y TEST GAPS · NEXT
ACTIONS · CONFIDENCE. Di explícitamente qué NO pudiste verificar.
