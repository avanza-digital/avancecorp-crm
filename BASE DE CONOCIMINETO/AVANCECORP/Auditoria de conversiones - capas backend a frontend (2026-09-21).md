---
tags: [crm, conversion, auditoria, gerencia, nucleo-unico]
actualizado: 2026-09-21
estado: auditoria-cerrada-por-Miguel-con-lo-que-hay · correcciones PENDIENTES de aprobación
---

# Auditoría de conversiones — de las tablas a la pantalla (2026-09-21)

Miguel pidió el 21/09: *«audita las conversiones de mi CRM y asegúrate de que estén
bien conectadas a todos para que el resultado que vea gerencia sea verídico; audita
cada capa desde backend hasta frontend, y hazlo con Codex también»*. A media
auditoría pidió cerrar con lo que había. Esta nota es el resultado.

Código auditado: `main` local en `40f2501b` (producción sirve `build-20260920T223425954Z`).
Definiciones SQL vivas según la última migración que define cada función (regla: el
texto anterior está muerto). Ver método y límites al final.

## Resumen para gerencia

1. **El núcleo único existe y casi todo bebe de él.** De 11 cifras trazadas de punta a
   punta (Resumen, Conversiones, Ranking, Metas, Rendimiento, Distribución, Gestión de
   equipo, HOY supervisor/analista, Directorio y portal, foto sellada), **10 salen de
   `private.conversion_episodios`**. La excepción es **Citas** («Se hicieron clientes»,
   «Depósito %»), que cuenta `crm.leads.etapa='convertido'` por su cuenta y divide en el
   navegador.
2. **Pero hoy existen DOS verdades para el mismo mes**, y ninguna sonda lo declara:
   - Ranking, Metas, HOY y el panel superior de Rendimiento sirven la lectura **mensual**
     (foto sellada si el mes está cerrado; numerador **neto** de anulaciones de meses ya
     pagados).
   - Los héroes de **Resumen** y **Conversiones** y la **Distribución** (panel inferior de
     Rendimiento) sirven un **recálculo vivo y bruto**: ignoran `crm.periodos_cerrados` y
     no restan el ajuste por anulación.
   - Basta **una anulación pendiente** o **mirar un mes sellado** para que Rendimiento
     muestre dos porcentajes distintos del mismo mes, uno encima del otro.
3. **La «verificación» que autoriza pintar el % es un sello de goma**: la sonda de paridad
   compara el núcleo consigo mismo (la misma llamada, los mismos argumentos), así que
   nunca puede detectar las dos divergencias anteriores.
4. **La deuda por cierres anulados se descuenta dos veces** entre el día 1 y el 10 de cada
   mes (conviven dos meses abiertos y la deuda no lleva período), y la deuda de quien salió
   del roster nunca se salda ni se declara.
5. **El front todavía divide en dos sitios**: el selector de fuentes (Landing + Formulario
   + Upgrade…) y todo el módulo de Citas. Y hay varias pantallas que **fabrican ceros o
   saltan la guarda** (portal admin, alertas, héroe de Conversiones sin núcleo).
6. **Ningún gate protege «un solo núcleo»**: el vigía prometido nunca fue gate, el CI no
   corre las pruebas SQL de conversión, el oráculo de llegadas asevera contra una función
   ya reemplazada y no existe ninguna sonda M = R = V = D contra producción.

## Hallazgos confirmados por verificación adversarial (3 lentes: código, negocio, escenario real)

| # | Sev. | Qué pasa | Dónde (archivo:línea) | Quién lo ve |
|---|---|---|---|---|
| C1 | **P1** | Un **mes sellado se recalcula en vivo**. `private.metricas_conversiones_implementacion` y `private.metricas_distribucion_leads_v3_core` no consultan `crm.periodos_cerrados` ni `private.cierre_mes_visible`; la mensual sí corta y sirve la foto. | `20260908211349:2145-2881` (rango) · `20260904210831:1065-1324` (v3_core) vs `20260904210831:1383-1389` (mensual) | Resumen, Conversiones y Distribución muestran para agosto un % distinto al de Ranking/Metas/HOY del mismo agosto. |
| C2 | **P1** | **Bruto vs neto.** La mensual resta la deuda por anulaciones (`private.conversion_con_ajuste`); el rango y Distribución publican el numerador bruto. La alerta «Cayó la conversión general» también usa el bruto. | `20260904210831:1640-1665` (neto) vs `20260908211349:2346-2372, 2518-2519` y `20260904210831:1144-1160, 1276-1281` (bruto); `alertas-gerencia.ts:291-326` | Rendimiento: «Conversión del mes» arriba y «Conversión del rango» abajo, del MISMO mes, con cifras distintas en cuanto hay un ajuste pendiente. |
| C3 | P2 | **La sonda de paridad es tautológica**: compara `conversion_episodios` agregado inline contra `private.conversion_mensual_por_vendedor`, que es la misma llamada con los mismos argumentos. `cuadra=true` siempre; es lo único que el front exige para pintar. | `20260908211349:2346-2391, 2665-2673` · `20260904210831:1128-1145, 1177-1204` · `app/src/lib/sondas-conversion.ts:20-26` | «Cifra verificada» que no puede fallar; no detecta C1 ni C2. |
| C4 | **P1** | **La deuda se descuenta en todos los meses abiertos a la vez.** `private.ajuste_pendiente_por_vendedor()` no recibe período y la CTE `pendientes` no mira `v_es_historico_abierto`. Entre el día 1 y el 10 conviven dos meses abiertos: la misma deuda rebaja ambos. | `20260815002100:196-221` · `20260904210831:1640-1676` | Gerencia abre agosto y septiembre en la primera decena y ve la misma deuda restada dos veces. |
| C5 | P2/P3 | **La deuda de quien salió del roster nunca se salda ni se declara**: `private.saldar_ajustes` solo corre sobre filas de `foto`; en la lectura viva `pendientes` solo se cruza con `roster`. | `20260904210831:2206-2210, 2288-2294` · `20260810163458:48-51` | Deuda invisible que jamás se cobra ni se explica. |
| C6 | P2 | **La foto sellada declara `cierres_sin_episodio: 0` como literal** y `crm.cerrar_periodo` no guarda la sonda al sellar: un mes puede sellarse con la sonda roja y salir en verde para siempre. | `20260904210831:1480` (literal) vs `1713-1737` (rama viva) · `cerrar_periodo 2029-2034` | Metas/Ranking de un mes cerrado muestran «foto definitiva» aunque al sellar hubiera cierres sin episodio verificable. |
| C7 | P3 | **La dedupe de cartera recorta por rango DESPUÉS de elegir la primera operación del cliente/mes**: si la primera cayó antes del rango, la del rango aporta 0. Es la regla decidida el 04/09 (mes calendario), pero en rangos parciales el héroe puede omitir una operación real. | `20260904210831:115-127` | Rango parcial de Resumen/Conversiones. |
| C8 | P2/P3 | **Ritmo semanal**: la serie ubica los cierres por semana de LLEGADA y madura hasta hoy; la última semana lleva días madurando y la primera semanas. Está rotulado como cosecha («Resultados por semana de ingreso»), pero el bloque no publica `madura_hasta`. | `20260908211349:2848-2869, 2181, 2214-2221` | Conversiones · detalle por analista. |

## Hallazgos con evidencia literal, verificación incompleta (el workflow se cortó)

Encontrados por uno o más lectores/trazas con archivo:línea y código citado; la
verificación adversarial no llegó a ellos. Se ordenan por impacto en lo que ve gerencia.

**El front divide o degrada la cifra**
- **P1 · Selector de fuentes divide en el navegador.** `conversion-vendedores.ts:196, 240-242, 289-297` hace `100 * numerador / nucleo.divisor`. El número está definido (aporte de esas fuentes sobre la base global, rotulado «Aporte de X»), pero viola la regla «el front nunca divide» y no tiene sonda propia. Además, con fuente activa, el chip «arrastra N conversiones de anulaciones» se sigue pintando junto a un % que NO tiene esa deuda restada (`:619-628`).
- **P1 · Héroe de Conversiones pinta la COSECHA bajo el rótulo «Índice comercial»** cuando el payload llega sin `nucleo` (`inteligencia-comercial.tsx:750-758`). Cosecha = cerraron ÷ llegaron, sin pesos ni cartera: otra pregunta bajo el nombre del índice.
- **P1 · Índice por analista cambia de período sin cambiar rótulo**: `inteligencia-comercial.tsx:596-605` pasa siempre `datos?.periodo`; si el rango falla, el gráfico pinta el MES bajo el rótulo del rango.
- **P1 · Resumen**: el número grande es del RANGO (`resumen-gerencia.tsx:178-181`) y la barra «Cumplimiento de la meta de conversión» es del MES (`:232-240`). Y `gerencia.tsx:533` llama `semanticaMetaMensual(periodoRanking, ahora, periodoRanking)` → `comparable` siempre true (guarda muerta); `gerencia.tsx:264` excluye `resumen` de `vistaMensual`, así que Resumen nunca sabe que el mes está sellado.
- **P1 · Rendimiento** oculta «—» sin decir por qué cuando `cierres_sin_episodio > 0` (`equipo-gerencia.tsx:71, 103-109`) y, con filtro de fuente, la cabecera sortea la guarda de cobertura (`:75, 83-92`).
- **P1 · Distribución** publica el héroe con fuente activa sin exigir `sondas.mostrarNucleo` (`distribucion-leads-gerencia.tsx:366-452`).

**Alertas y ceros fabricados**
- **P1 · Alerta «Conversión bajo meta»** afirma un % sin consultar cobertura ni sondas (`alertas-gerencia.ts:240-285`), mientras Ranking/HOY ocultan esa misma cifra con «Cifras en revisión».
- **P1 · HOY analista**: el tile «Convertidos» rotula «ventana de 45 días» un número que el servidor ya sirve como cierres del MES del núcleo (`vendedor.tsx:922, 1439-1451` vs `20260913213842:226-240`). La nota «Recibidos N · cierres M» omite las operaciones de cartera que SÍ están en el numerador (`vendedor.tsx:1539-1543`).
- **P1 · Ranking**: un analista activo sin supervisor activo deja TODA la pestaña «Conversión» en «No disponible» sin explicación (`conversion-equipo.ts:54-63`, `store.tsx:1423`). Precedencia de estados: quien cerró de arrastre pero recibió un referido sale rotulado «Solo recibió referidos» y pierde el puesto (`20260904210831:1832-1837`).
- **P1 · Gestión de equipo**: «Este equipo aún no tiene leads asignados» borra un 0 % real con divisor > 0 (`equipo.tsx:950-957, 1213-1227`).
- **P1 · Caché**: la foto de Distribución V3 es la única que ninguna mutación de conversión invalida (`crm-queries.ts:149-150, 260-294`, `store.tsx:1142-1162`).
- **P0/P1 · Portal admin y Directorio** (capital, no conversión, pero es lo que ve el Directorio): `dashboard.js:172-179` escribe «0» en todos los KPI cuando la RPC falla; `directorio.js:26-29` convierte nulos en 0 y capa la variación a ±100; `public.metricas_directorio` devuelve `var_pct` 0 con divisor 0 y `pct_al_dia` 100 sin cuotas (`20260901180000:699-701, 717-722`); el gráfico principal del Directorio suma renovaciones y contratos ya renovados como capital nuevo (`:657-665, 745-757`); el ranking por analista atribuye por asesor ACTUAL del cliente, no por el analista del núcleo (`:621-638`); el selector de período solo afecta a dos gráficos (`directorio.js:613-619`).

**Citas (la única traza fuera del núcleo)**
- **P1** «Se hicieron clientes» y «Depósito %» se leen de `crm.leads.etapa='convertido'` + perfil `rol='cliente'`, no del ledger (`20260913225755:186-193, 226-245`); Depósito %, ticket, cumplimiento y «% a depósito» se dividen en el navegador (`components/citas/avance.ts:117-129, 146, 171-172`; `depositos.ts:88`). El «Capital asociado a estos cierres» de Reuniones es el capital histórico completo del cliente, sin ventana (`20260907194622:89-101`). Ojo: la definición viva de `private.citas_gerencia_consulta` es la de `20260913225755` **parcheada en sitio** por `20260914044939` y `20260915170018`; leer solo el archivo base engaña.

**Escritores del ledger (lo que alimenta el numerador)**
- **P0 · HIPÓTESIS, verificar en producción**: desde `20260919161807` (19/09) la única puerta de conversión pasa por `private.inversiones_escritura_bajo_candado()` y, si la bandera global `inversiones_escritura` está apagada, solo el piloto F8 puede cerrar (`20260913215240:344-359`). El vault dice que la apertura general F9 se activó el 15/09, así que probablemente no bloquea a nadie; **una sola consulta lo confirma** (`select nombre, activo from crm.multiempresa_flags`).
- **P1** Las puertas legacy siguen en el front (`crm-api.ts:2683` edge `crm-convertir-lead`; `:5937` `convertir_lead_externo`, con su hook `useConvertirLeadExterno`) y el trigger nuevo las rechaza con P0409. No se encontró pantalla que aún las llame, pero no se descartó.
- **P1** Una inversión de Cartera sobre una persona con lead abierto NO enlazado (sin `inversionista_id` ni puente canónico) se confirma sin cerrar el lead (`20260919161807:364-379`): venta real, cero en el numerador.
- **P1** `crm.operaciones_cartera` no tiene canal de anulación (`20260824231133:80-131`): una renovación/upgrade errónea suma al numerador para siempre si el mes ya se selló.
- **P1** Anular un cierre Avance no anula la inversión F4 (`20260908211349:1199-1298` vs `3953-3970`): la conversión baja, el capital no.
- **P1** La `fecha_comercial` pasada separa el mes del capital del mes de la conversión del mismo hecho (`20260919161807:675-678, 1273-1298, 1376`).
- **P1** Un mes sin metas publicadas no puede sellarse nunca (`20260815102000:165-180` + `20260904210831:1975-1993`): queda abierto para siempre y su % sigue moviéndose.

## Refutados por los verificadores (no son problemas)

«`metricas_conversiones_equipo_fn` no publica total» (el front no calcula % de equipo con
él) · «la meta de la empresa es media simple» (hay una sola meta replicada) ·
«`cierres_por_semana` filtrado vs `nucleo` global» (el front valida `origen_filtrado`; el
«Aporte» es global por diseño) · «cartera con fecha futura del mes» · «etapas del embudo
inferidas» (decidido y rotulado) · «`conversion_pct` legacy = 0 en `metricas_vendedores_fn`»
(el front ya no lo lee) · «doble regla de mes en `cierres_de_arrastre`» · «el agregado sin
analista viaja mal» · «cobertura `medible`».

## Pruebas y gates: lo que hoy no protege nada

- El **vigía** del plan («toda función `crm.*` con conversión consume el núcleo») vive en
  `supabase/scripts/archivo/aplicar-f1-conversion-episodios-prod.sh:127-150` y solo imprime.
  El trinquete `private.assert_analitica_leads_citas` exige que Reuniones consuma
  `citas_episodios` pero no exige nada de las 7 funciones de conversión.
- **Ningún CI** corre `test-conversion-llegadas.sql`, `test-conversion-episodios.sql` ni
  `test-conversion-mensual.sql` (`package.json:11`, `crm-rls-preflight.yml:60-80`).
- `test-conversion-llegadas.sql:107-116` asevera contra `metricas_conversiones_implementacion`
  **del 04/09**; la F4 (`20260908211349:2144-2145`) la reemplazó el 08/09. El cuerpo vivo del
  héroe nunca fue ejercitado por su oráculo.
- `test-rls.mjs:8457-8460` acepta `paridad_nucleo === null` como aprobado.
- **No existe sonda M = R = V = D contra producción**: `gate-realidad.mjs` no contiene la
  palabra «conversion».

## Sonda de paridad contra producción — PENDIENTE (bloqueada por permisos)

Queda escrita y lista, solo lectura (`begin transaction read only` … `rollback`, patrón de
`prueba-contrato-cierre-mes-estado-prod.sql`), en
`CRM-Avance-Corp/supabase/scripts/sonda-paridad-conversion-prod.sql`. Compara septiembre en
las 6 RPC (núcleo directo, mensual, rango, cumplimiento, vendedores, distribución, cosecha),
revisa la integridad del ledger (convertidos sin fila en el ledger, cierres sin fecha, meses
distintos entre ficha y ledger, clientes con varias operaciones elegibles el mismo mes) y
contrasta agosto mensual vs rango. El clasificador de permisos de la sesión la bloqueó como
«Production Reads». Para correrla:

```
! supabase db query --linked --file CRM-Avance-Corp/supabase/scripts/sonda-paridad-conversion-prod.sql
```

Si `M_conversion_mensual_fn_sep.pct` ≠ `R_metricas_conversiones_fn_sep_1_21.pct` ≠
`D_distribucion_v3_sep_1_21.pct` con `cuadra=true`, C1–C3 quedan demostrados con datos reales.

## Revisión secundaria (Codex, `ROLE: SECONDARY_REVIEWER`, read-only)

Codex (gpt-6-astra, `codex exec` en sandbox read-only, sin shell ni MCP, solo con los
extractos adjuntos) devolvió **VERDICT: CHANGES_REQUESTED · CONFIDENCE: MEDIUM** sobre los 12
hallazgos TOP. Dictamen íntegro en
`CRM-Avance-Corp/docs/auditorias/conversion-2026-09-21/evidencia/codex-secondary-review-veredicto.md`.
Resumen y decisión del PRIMARY (Claude) sobre cada punto:

| Hallazgo | Codex | Decisión del PRIMARY |
|---|---|---|
| C1 mes sellado recalculado | Mecanismo CONFIRMADO; la discrepancia publicada, hipótesis (no vio los cuerpos completos). P1 «cuando un mes completo sellado se publique como el mismo índice». | **Aceptado como P1** para rango = mes calendario. Los verificadores sí leyeron los cuerpos completos (grep de `periodos_cerrados`/`cierre_mes_visible` = 0 en el rango). Para rangos parciales o multi-mes hay que definir primero cómo interviene la foto (decisión de Miguel). |
| C2 bruto vs neto | CONFIRMADO en superficies que presentan el mismo índice mensual. Aviso: la regla reserva el ajuste a la lectura mensual, así que **no** es defecto en cualquier rango; y no trasladar la deuda al núcleo. | **Aceptado con ese matiz**: el problema es Rendimiento (arriba neto, abajo bruto, mismo mes) y la alerta «Cayó la conversión»; un rango parcial bruto es legítimo si se rotula. |
| C3 sonda tautológica | HIPÓTESIS (le faltó el cuerpo de `conversion_mensual_por_vendedor`). | **Se mantiene P2**: el cuerpo (`20260904210831:136-232`) llama al mismo `conversion_episodios` con la misma ventana y ámbito; la diferencia de `p_periodo` no cambia el peso dentro del mismo mes. Prueba pedida por Codex, válida: introducir una discrepancia conocida y comprobar que la sonda la detecta. |
| C4 deuda en todos los meses abiertos | Saldo sin período CONFIRMADO; distinguir doble imputación VISIBLE (demostrada) de doble liquidación PERSISTIDA (no demostrada). | **Aceptado**: lo que se afirma es la doble imputación visible. La deuda de quien salió del roster queda como P3 pendiente de una prueba con `cerrar_periodo`. |
| C6 foto declara `cierres_sin_episodio: 0` | HIPÓTESIS (no adjuntado). | **Se mantiene P2**: verificado 3/3 con el archivo (`20260904210831:1480` vs `1713-1737`). |
| Selector de fuentes divide en el navegador | CONFIRMADO, **rebajado a P2**: la aritmética no produce hoy un % incorrecto; el defecto es duplicar el cálculo en el cliente. | **Aceptada la rebaja a P2.** |
| Héroe de Conversiones pinta la cosecha | CONFIRMADO P1; además tiene precedencia sobre `rangoError`. | **Aceptado.** Primera corrección a hacer. |
| Resumen titular rango / barra mes; guarda `comparable` muerta | Parcialmente confirmado; falta el helper y el rótulo de la barra. | Queda **P2 pendiente** de leer `periodo.ts:105-108` (el lector lo citó: `comparable = desde===desde && hasta===hasta`, true si se pasa dos veces el mismo período). |
| Alerta «bajo meta» sin cobertura | HIPÓTESIS P1: falta ver de dónde vienen `cumplimientosVendedores`. | **Pendiente**: prueba propuesta por Codex (cobertura con `cierres_sin_episodio > 0` → ¿se publica la alerta?). |
| Portal admin escribe «0» | CONFIRMADO P1 en `dashboard.js`; el resto del paquete Directorio, hipótesis. **Sin sustento para P0.** | **Aceptado**: P1, no P0. |
| Gates inexistentes | HIPÓTESIS (no se adjuntaron workflows ni tests). | Se mantiene con la evidencia del lector (`package.json:11`, `crm-rls-preflight.yml:60-80`, `test-conversion-llegadas.sql:107-116`); comprobable en un minuto. |
| F12 bandera de inversiones | HIPÓTESIS P1 provisional; **comprobación urgente**. | De acuerdo: es la primera consulta de la sonda de producción (`puertas_conversion`). |

**Riesgos nuevos que aportó Codex (aceptados):**
- **P1 · Otro fallback temporal en Resumen**: en `resumen-gerencia.tsx:178-181`, con fuente
  global, payload sin `nucleo` y carga terminada, `conversionPrincipal` cae a `conversionMes`:
  si el rango no es el mes, publica una cifra de OTRO período bajo el rótulo del rango.
- El `catch` del dashboard admin engloba métricas, contratos y pagos (`dashboard.js:165-178`):
  un fallo de una consulta auxiliar fabrica ceros en indicadores cuya consulta sí era válida.
- **Cuidado al unificar el neto**: aplicar el «suelo en cero» por vendedor y luego sumar no
  equivale a descontar la deuda total del bruto total (brutos 1,1 con deudas 2,0 → neto 1 por
  filas, 0 global). La corrección de C2 debe fijar cuál regla manda y qué pasa con la deuda
  no absorbida.

**Orden de corrección recomendado por Codex y aceptado**: (1) los fallbacks que cambian de
significado o de período (héroe de Conversiones, Resumen) y el «0» del portal; (2) comprobar
F12 en producción; (3) la asignación temporal y liquidación de la deuda (C4) ANTES de unificar
lecturas; (4) fijar el contrato de los rangos con meses sellados y corregir C1/C2; (5) % por
fuente servidos, cobertura conservada en las fotos, guardas en alertas, y gates acreditados.

## Qué corregir primero (propuesta consensuada con Codex; SQL requiere el OK de Miguel)

1. **Fallbacks que cambian de significado o de período (solo front, sin SQL)**: héroe de
   Conversiones sin la rama cosecha (`inteligencia-comercial.tsx:750-758`); Resumen sin caer a
   `conversionMes` bajo rótulo de rango (`resumen-gerencia.tsx:178-181`) y con barra y titular
   del mismo período; portal admin sin ceros fabricados (`dashboard.js:172-179`, `directorio.js:26`).
2. **Comprobar F12 en producción** (bandera `inversiones_escritura`, piloto, cierres del ledger
   desde el 19/09): sonda `puertas_conversion`. Si está apagada, es P0 operativo.
3. **Deuda con período** (C4/C5): `ajuste_pendiente_por_vendedor(p_periodo)` aplicada solo al
   mes vivo; declarar la deuda de quien salió del roster. Decidir la regla del suelo (por
   vendedor vs global) antes de tocar C2.
4. **Contrato de los rangos con meses sellados y una sola lectura publicable** (C1 + C2): cuando
   el rango sea un mes calendario, el `nucleo` del rango y el `nucleo_*` de Distribución sirven
   la MISMA cifra que `crm.conversion_mensual_fn` (foto si sellado; neto si hay ajuste), o
   declaran `sellado`/`ajuste_aplicado=false` y el front lo rotula «recálculo vivo, bruto».
   Requiere que Miguel decida qué pasa con rangos parciales y multi-mes.
5. **Sonda con testigo independiente** (C3): comparar contra la cifra PUBLICADA del mes;
   `cuadra=null` cuando no aplique; probarla introduciendo una discrepancia conocida.
6. **Front sin divisiones**: aportes por fuente servidos desde el núcleo; alerta «bajo meta» con
   guarda de cobertura; cobertura conservada en la foto sellada (C6).
7. **Gates reales**: vigía como `private.assert_conversion_un_solo_nucleo()` en el trinquete;
   las tres pruebas SQL en CI; `gate-realidad` con el supuesto `conversion_un_solo_nucleo`
   (M = R = V = D del mes vigente con sesión de gerencia).
8. **Citas al núcleo**: `v_conversiones` desde `private.conversion_cierres`; numerador, divisor
   y pct servidos.
9. **Escritores**: retirar las puertas legacy del front; canal de anulación para
   `operaciones_cartera`; anular cierre Avance ⇒ anular inversión.

## Método y límites

- Workflow de 23 agentes lectores (12 por capa + 11 trazas verticales), modelo Opus 5, sobre
  el repo local; verificación adversarial de 3 lentes por hallazgo (código, negocio, escenario
  real). Miguel pidió cerrar a media verificación: **41 de ~200 hallazgos crudos verificados**
  (13 sostenidos, 28 refutados); el resto se reporta con su evidencia literal pero sin el
  contraste adversarial.
- **No se consultó producción**: la sonda quedó bloqueada por permisos. Todo lo dicho es sobre
  código; los importes y porcentajes de ejemplo son escenarios, no cifras reales.
- Codex participó como revisor secundario aislado (CLI `codex exec`, sandbox read-only, sin
  shell ni MCP, directorio neutral), porque el MCP `codex` falló al conectar en esta sesión.
  Una sola consulta (LEVEL 3), sobre los 12 hallazgos TOP con extractos literales; dictamen
  CHANGES_REQUESTED / MEDIUM, incorporado arriba. No se repreguntó.
- Cómo retomar desde otra cuenta (requisitos, permisos, comandos, scripts y evidencia):
  `CRM-Avance-Corp/docs/auditorias/conversion-2026-09-21/RETOMAR-EN-OTRA-CUENTA.md`.
- No se cambió código de producto, SQL ni configuración. Un archivo nuevo: la sonda de
  paridad (solo lectura). Esta nota.

Relacionadas: [[Conversion unica en todo el CRM - plan de migraciones]] ·
[[Nucleo de conversion - diagnostico de llegadas y asignaciones 2026-09-04]] ·
[[Inventario de indicadores de Gerencia - Comercial]] ·
[[Auditoria Gerencia frontend y consumo backend 2026-09-07]] ·
[[Correccion de los siete hallazgos de Gerencia 2026-09-07]] ·
[[Conversion mensual - definicion cerrada]] · [[Inicio]]
