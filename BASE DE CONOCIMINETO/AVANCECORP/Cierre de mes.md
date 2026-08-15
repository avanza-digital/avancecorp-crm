---
tags: [feature, crm, cierre-mes, decision]
actualizado: 2026-08-15
---

# Cierre de mes

**Estado: ✅ EL SERVIDOR, EN PRODUCCIÓN desde el 2026-08-15.** Las siete migraciones
`20260815*` aplicadas en orden, con todas sus autopruebas activas. Falta la **Fase 2**,
que es el front.

Verificado después de aplicar, no supuesto: producción queda **byte a byte igual** a la
copia que aprobó el gate (misma huella de las 203 funciones,
`b32dec06f4e5e97e7735bb01c60660e2`), el gate de permisos dio **1007 aserciones y 0
fallos**, y los advisors dan **0 ERROR** con exactamente los 5 avisos nuevos previstos.
El cron `crm-cierre-mes-diario` corre a las **09:20 de Lima**, todos los días.

Sella el resultado de un mes para que deje de moverse. Es la pieza que faltaba desde que
existe [[Conversion mensual - definicion cerrada]]: el CRM **no guardaba** el resultado de un
mes, lo recalculaba en cada consulta.

## El problema, medido

El 14/08 se midió: **el agosto de un vendedor pasó de 38,33 % a 5,00 % en dos horas** por una
anulación de gerencia. Esa la decidió Miguel. Las que preocupan son las que no decide nadie:

- el total de empresa se calcula sobre quien está en el equipo **hoy**, así que una baja en
  octubre cambiaría agosto;
- las metas se pueden **republicar** sobre un mes pasado (agosto ya lleva 7 revisiones) y el
  cumplimiento se recalcula contra las nuevas;
- la anulación es retroactiva y de una sola dirección.

Mientras nadie cobre por esos números da igual. En cuanto deciden un pago, es un problema
contable.

## Las decisiones de Miguel

| Pregunta | Su respuesta | Fecha |
|---|---|---|
| ¿Cuándo se cierra un mes? | El **día 10** del siguiente. Del 1 al 10, ventana de ajuste. | 14/08 |
| ¿Quién lo cierra? | **Solo**. Automático. | 14/08 |
| ¿Qué se sella? | **Todo lo que decide pago**, no solo la conversión. | 14/08 |
| ¿Un mes cerrado se puede corregir? | **Nunca se reescribe.** Lo que haya que corregir se descuenta del mes vivo, como una planilla. | 14/08 |
| ¿Y si el descuento no cabe en el mes? | **Se arrastra** hasta saldarse. | 14/08 |
| ¿La deuda caduca? | **No por tiempo. Desaparece al saldarse.** | 15/08 |
| ¿Se puede cerrar antes del día 10? | **No.** Ni gerencia. | 15/08 |
| ¿Y cerrar *tarde*? | **Sí** — el candado es un suelo, no una fecha exacta. | 15/08 |
| ¿El sistema calcula comisiones? | **No.** Eso será otro apartado el día que exista. Aquí solo se muestra bien lo que lleva el asesor en capital y conversión. | 15/08 |
| Un cierre que llega tarde a un mes ya sellado | **No se construye.** No ha pasado nunca; se maneja de forma interna. | 15/08 |

## El candado del día 10 — por qué existe

Las guardias originales decían **quién** y **qué**, y ninguna decía **cuándo**. Con el momento
de cerrar libre, quien cierra elige **de qué mes sale el dinero** de una corrección:

- si el mes está **abierto**, anular recalcula ese mes ahí mismo;
- si está **cerrado**, nace una deuda que se descuenta del **mes vivo**.

Es la misma segunda puerta que cierra [[Conversion mensual - definicion cerrada]], abierta
desde el otro lado. Y además, cerrar el día 2 se comería la ventana de ajuste.

## Cómo funciona ahora

Un ciclo corre **todos los días** a las 09:20 de Lima (cron `crm-cierre-mes-diario`, justo
detrás del ciclo de contratos) y cierra los meses que ya deben cierre y cuya ventana abrió,
**del más antiguo al más nuevo**. Correr a diario —y no «el día 10»— es lo que lo hace
auto-reparable: si el 10 falla, el 11 cierra igual y el mes no queda atascado.

Y el servidor publica el estado (`crm.cierre_mes_estado_fn`) con **tres** situaciones, no dos:
`en_ventana` (del 1 al 10, todavía se puede corregir), `hoy` (le toca sellarse y el ciclo aún no
ha pasado) y `atascado` (pasó un día entero y sigue abierto → **la alarma**). El estado del medio
no es un detalle: la ventana abre a medianoche y el ciclo corre a las 09:20, así que sin él la
alarma sonaría nueve horas cada día 10 con todo funcionando — y una alarma que suena cuando no
pasa nada deja de mirarse. Sin la alarma, un cron roto es invisible: nadie mira los logs.

## Lo que hay que saber antes de tocarlo

⚠️ **Un fallo de dinero que las pruebas no vieron.** La primera versión marcaba el descuento
de capital como saldado y **no lo restaba de ninguna cifra**: el asesor cobraba igual y la
deuda desaparecía. Lo cazó un análisis adversario, no el oráculo. Corregido, y el bloque 6bis
del oráculo existe para que no vuelva. Lección: se probó el camino de la conversión y se dio
por bueno el del capital sin tocarlo.

⚠️ **Dos calcos del banco local mentían** y con ellos el oráculo bendecía cosas falsas. Es
[[Ejecutar contra la forma real]] otra vez, del lado del calco.

⚠️ **Lo que encontró la auditoría del 15/08, y que yo no vi.** Tres fallos de razonamiento,
no despistes — los tres nacen de mirar una pieza sin mirar con qué convive:

1. **La puerta lateral de las metas retroactivas.** El candado del día 10 cerraba el *cuándo*,
   pero «mes que debe un cierre» se definía solo como «tiene metas publicadas» — y las metas se
   pueden publicar sobre **cualquier** mes. Publicar hoy las metas de un mes viejo lo convertía
   en pendiente con la ventana abierta hace meses, y **el cron lo sellaba solo**, por detrás de
   meses ya pagados. Nadie tenía que apretar nada. Cerrado por los dos lados.
2. **La carrera entre cerrar y anular, que pierde dinero en silencio.** Si una anulación
   arranca mientras el cierre está a medias, ve el mes todavía abierto, decide que no hay deuda
   — y la foto ya contó ese cierre. Un cierre anulado que queda pagado para siempre. Era
   teórica; el ciclo automático la convierte en una **cita fija, mensual y a hora conocida**.
   Cerrado con un cerrojo que toman las dos puertas.
3. **El ciclo no paraba: retrocedía.** Si un mes fallaba, se perdía también el sellado del
   anterior, que había ido bien. Y como esos fallos son deterministas, el sistema se habría
   quedado atascado para siempre rehaciendo y descartando el mismo trabajo bueno cada día.

⚠️ **Una prueba que solo puede correr ciertos días no prueba nada.** La ventana del mes
pasado solo está cerrada del 1 al 9, así que la rama que importa —la que **rechaza**— no se
ejercita el resto del mes. Se resolvió separando la aritmética (probada exhaustivamente, sin
reloj) del reloj, y empujando la ventana dentro de la propia prueba. Comprobado con **diez
mutantes** —los diez caen, con corrida de control sin mutar en verde—: cada arreglo se rompió a
propósito para verlo caer.

Y mutar destapó **tres** cosas que ni escribiendo ni auditando aparecieron:

- **Un arreglo tapaba el test de otro.** La subtransacción nueva se comía la excepción que otra
  prueba usaba de señal, y esa prueba seguía verde con el freno quitado.
- **El banco mentía por omisión.** No daba a `authenticated` el permiso de *entrar* a los
  esquemas, cosa que producción sí hace. Resultado: toda prueba de «esta tabla no se puede leer»
  moría en la puerta de la calle y no llegaba nunca a la de la tabla — un mutante que abría la
  tabla de par en par pasaba en verde. Es [[Ejecutar contra la forma real]] otra vez, pero por
  lo que al calco le **faltaba**, no por lo que tenía mal.
- **Hay fallos que ningún test puede cazar.** Una carrera necesita dos sesiones a la vez y el
  oráculo corre en una, así que el cerrojo se cierra por estructura y se dice, en vez de
  aparentar una cobertura que no existe.

**Quién ve el aviso.** Vendedor, supervisor, gerencia, directorio (por la vía del «lector
global») **y también el coordinador**. Lo del coordinador es deliberado y va al revés que en la
conversión: la pantalla de metas (`cumplimiento_metas_fn`) sí le deja ver un mes cerrado, así que
negarle el aviso le dejaría el banner en error. Y no hay nada que proteger — el aviso no devuelve
cifras, ni PII, ni quién cerró: solo etiquetas de mes, fechas y un estado.
Ver [[Acceso y roles del CRM]].

🔴 **Dos nombres que se parecen demasiado.** `crm.cierres_estado_fn` (existente, en producción)
es de los **cierres de venta** — es la que pinta el chip «CIERRE ANULADO» en la cartera, y en el
front vive en `app/src/lib/cierre-estado.ts`. `crm.cierre_mes_estado_fn` (nueva) es del **cierre
de mes**. Cuando la Fase 2 toque el front, su módulo NO debe llamarse `cierre-estado`: los
nombres parecidos en un esquema en español ya costaron un despliegue una vez.

## Qué pasa ahora que está aplicado

Comprobado contra producción el 15/08, no supuesto: el único mes con metas publicadas es
**agosto 2026**, que es el mes en curso, y el ledger arranca el 05/08. Así que **al aplicar
esto no se cierra nada de golpe**. El primer cierre real será el de agosto, el 10 de
septiembre, y nacerá marcado `mes_parcial` porque el ledger empieza a mitad de mes.

Miguel avisó de que **no van a pagar comisiones con esto hasta que el sistema esté operando**,
así que el 10 de septiembre no es una fecha comprometida con nadie.

## Falta

Del lado del **servidor no queda nada por escribir, ni ningún hueco de cobertura conocido**.
Los dos que quedaban se cerraron: el **ámbito del supervisor en un mes cerrado** (que salga de
quién era su equipo *entonces*, no de quién lo es hoy) y los **permisos por rol** de las tres
tablas nuevas, ambos probados ejecutando, y ambos con mutante que lo demuestra.

✅ **Desplegado el 15/08.** Ciclo completo: copia de la base → las 7 aplicadas → gate
(1007/0) → advisors (0 ERROR) → producción. La copia se borró al terminar.

Queda la **Fase 2, el front**: enseñar la marca de mes cerrado, el descuento del asesor
con su motivo, y el aviso del 1 al 10 con su alarma de ciclo atascado.

🔴 **El despliegue apagó la pantalla de metas, y hay que saber por qué.** El servidor
entró primero y empezó a mandar **cuatro datos nuevos**; el front tiene esa pantalla
configurada para rechazar el paquete entero si trae algo que no reconoce —una defensa
deliberada, para no pintar cifras de una fórmula que no entiende—, así que gerencia,
supervisores y vendedores se quedaron sin cumplimiento a la vez. Nadie llegó a verlo:
se reparó antes de que ningún usuario abriera el CRM.

La regla que lo habría evitado ya estaba escrita: **cuando una consulta gana un dato
nuevo en su respuesta, el front se publica primero**. Fuimos al revés.

⚠️ **Y leyendo el código solo encontré 2 de los 4.** Los otros dos solo viajan en la foto
de un mes ya sellado —una situación que nadie vive hasta el **10 de septiembre**— y
aparecieron al *generar* la prueba ejecutando el cierre de verdad contra una base local.
De ahí sale `supabase/scripts/fixture-cumplimiento-cierre.sql`: siembra un mes, lo sella
y escupe los dos paquetes reales. Sin eso, el mismo apagón habría vuelto ese día.

La reparación **añade** los cuatro datos; no afloja la defensa. Hay una prueba puesta a
propósito para que nadie la afloje «para que no vuelva a pasar».

🔴 **Una trampa del despliegue que hay que recordar.** La fusión automática de Supabase
respondió **«éxito» y no aplicó nada**: escribió las siete migraciones en el índice de
producción sin crear un solo objeto, dejando el índice mintiendo. Se cazó **contando
objetos**, no leyendo la respuesta, y se revirtió. Después de una fusión, la respuesta no
es prueba de nada. La vía que sí funcionó fue el CLI ejecutando cada fichero
(`supabase db query --linked --file`), y ⛔ **`supabase db push` no se usa jamás en este
repo**: el historial local y el remoto divergieron hace tiempo y un push intentaría
reproducir ~40 migraciones que ya están vivas con otro número.

Ver [[Conversion mensual - definicion cerrada]] · [[Anulación de cierres de Avance]] ·
[[Como se mide la conversion del asesor]] · [[Inicio]]
