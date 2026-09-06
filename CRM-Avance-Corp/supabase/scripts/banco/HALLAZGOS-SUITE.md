# Primera corrida completa de `test:rls` — 2026-09-01

**Resultado: 1 274 de 1 279 aserciones en verde · 6 fallos.**

> **Actualización (noche del 01/09):** los 6 fallos + el falso verde del §7 quedaron
> corregidos con «ATR-4 manda» de Miguel y **dos rondas de refutación de Codex** (4 de los 5
> arreglos tenían su propio agujero — hasta el arreglo de un falso verde puede fabricar
> otro). De la re-corrida salieron además los hallazgos **8, 9 y 10** de abajo.
>
> **Veredicto de la re-corrida (tercera, con reset): 1 287 ✓ · 5 ✗ — y los 6 arreglos
> aprobados pasaron TODOS.** Los 5 rojos restantes son: los 2 del hallazgo 9 (decisión de
> Miguel, va por migración de policy), los 2 del hallazgo 10 (cambio de suite pendiente de
> OK), y 1 del D3 que desmintió a Codex: afirmó que el gate de `cerrar_contrato` respondía
> P0001 sin ERRCODE y la corrida midió **42501 al literal** (el `USING ERRCODE = '42501'`
> está en el prosrc vivo). Corregido a lo MEDIDO — ni el auditor se cree sin re-medir.

Es la **primera vez** que la suite entera corre desde que se escribieron muchas de sus
aserciones: producción no tiene cuentas demo, así que hasta hoy no había dónde ejecutarla.
Los 6 fallos son, por eso, valiosos: son la deuda que llevaba meses invisible.

🔴 **Ninguno se ha tocado.** Tocar la suite de seguridad para ponerla verde es exactamente lo
que este proyecto no hace. Cada uno lleva abajo su diagnóstico y qué haría falta decidir.

⚠️ **Contexto imprescindible:** el banco está a **paridad 9/9 con producción**, permisos de
tabla y de columna incluidos (830 y 44 entradas, huella idéntica). Así que un fallo aquí
**no** es «el banco está mal montado»: o la aserción caducó, o el fixture no construye el
mundo que la aserción supone.

---

## 1 y 2 · La etiqueta de anulación de tareas: aserciones MUERTAS desde un endurecimiento

```
✗ vend1 intenta escribir cancelada_por="sistema" en una tarea viva
✗ vend1 intenta firmar una tarea viva como si la hubiera anulado sup1
    42501 · permission denied for table tareas
```

**Diagnóstico: la suite se quedó atrás de una defensa MÁS FUERTE.** Las dos usan
`positive(...)`: esperan que el UPDATE **funcione** y sea un no-op silencioso (el trigger
BEFORE reescribe la columna desde `old`). Hoy `authenticated` **no tiene UPDATE sobre
`crm.tareas`** —medido, idéntico en banco y producción: solo `INSERT` y `SELECT`—, así que
el intento muere antes, en la capa de permisos, y el trigger ni se ejecuta.

No es un agujero: es lo contrario. Pero deja **sin probar** el contrato que decían probar —
que la etiqueta y la firma son infalsificables.

**Lo que haría falta:** mantener las dos cosas. Aserción nueva de que el UPDATE directo se
rechaza en la capa de permisos (42501), **y** el no-op del trigger ejercitado por un llamador
que sí tenga UPDATE (`service_role` lo tiene) — que además es el caso más exigente.

## 3 · La ventana de reuniones del fixture

```
✗ reuniones: la ventana del fixture contiene al menos una cita pactada
```

**Diagnóstico probable: fecha, no seguridad.** La cita que siembra `seed-demo` cae fuera de
la ventana que consulta la pantalla. Las dos aserciones anteriores del mismo bloque (versión
del payload y forma del resumen) pasan, así que la puerta responde bien; lo que falla es que
no hay nada dentro. Pendiente de confirmar con las fechas exactas del seed.

## 4 y 6 · El actor de la Opción B no pertenece al equipo comercial

```
✗ analista vigente registra para cliente ajeno: la Opcion B ya NO cierra el alta por cartera
    22023 · Elige el analista de la venta · Quien registra no forma parte del equipo comercial
✗ D3 vend1 NO cierra contratos
```

**Diagnóstico probable: el fixture, no la regla.** El rechazo que llega dice literalmente que
*quien registra no está en el equipo comercial* — es decir, la venta se frena por una razón
distinta de la que la aserción quería medir. La Opción B (cualquier analista vigente registra
para cualquier cliente activo) es de la F5.c y está en producción desde el 30/08.

**Lo que haría falta:** revisar qué actor usa el bloque y con qué membresía queda tras los
bloques anteriores — la suite reasigna y desactiva miembros por el camino.

## 5 · 🔑 Una aserción que contradice la regla publicada HOY

```
✗ el cierre anulado salio de los totales (no es dinero)
    [{"moneda":"PEN","capital":1500,"cierres":1,"cooperativa":"prodelco"}]
```

**Diagnóstico: la aserción quedó obsoleta el 01/09, hace unas horas.** Exige `!enTotales`:
que tras anular, el cierre **desaparezca** del capital.

Eso era la regla vieja. **ATR-4** (registro 193, publicada hoy) decidió lo contrario y lo
dejó escrito: *«solo la conversión, siempre»* — anular es una **sanción al analista**, le baja
la conversión, y **el capital no se toca jamás**, ni el suyo ni el de la empresa. Su
refutación adversarial encontró y corrigió justamente **cuatro lentes del dinero** que
seguían borrando ese capital; que el cierre anulado **siga** en los totales es el
comportamiento que ATR-4 instaló a propósito.

**Lo que haría falta:** invertir la aserción — el cierre anulado sigue en los totales **y**
figura marcado; y comprobar que lo que sí baja es la conversión del analista. Es un cambio de
contrato del negocio, así que **lo confirma Miguel** antes de tocarlo.

---

## 7 · 🔑 El falso verde de `cerrar_contrato` (salió al arreglar el D3)

El «D3 vend1 NO cierra contratos» fallaba y su gemelo «gerencia SÍ» pasaba. Al arreglarlo se
midió la causa: la pareja llamaba a la RPC con **nombres de parámetros inventados**
(`p_contrato_id`, `p_contrato_destino`; la firma viva es `p_id, p_resultado,
p_contrato_nuevo_id`). PostgREST devolvía PGRST202 «no matching function»: el NO fallaba
honesto, y el SÍ llevaba tiempo **pasando en falso** — nunca llegó a la función, pero «no
denegado» daba verde. Corregidos los nombres y clavados **código y mensaje exactos** en las
dos mitades (P0001 `No autorizado` / P0001 `Contrato no encontrado`; el `RAISE` vivo no
lleva ERRCODE — si el contrato debe ser 42501, el cambio va en la FUNCIÓN, por migración).

## 8 · La suite asumía un banco DESECHABLE

En la segunda corrida contra el MISMO banco aparecieron rojos nuevos que la primera no tuvo:
choque con `uq_leads_telefono_vivo` (la bolsa F2 queda VIVA con teléfono fijo a propósito),
conteos contaminados por transitorios de la corrida anterior, y el bloque de domicilio —
que **documenta** que deja escrito `public.perfiles.domicilio` y no puede deshacerlo (el
trigger `perfiles_domicilio_legal_no_borrar` prohíbe volver a NULL).

La suite nació para branches de un solo uso (crear → correr → destruir); un banco
persistente necesita **reset entre corridas**. Está en `reset-gate-banco.sql` (solo-banco:
baja UN trigger nombrado dentro de la transacción para limpiar el residuo de test) y el
arranque de la suite ahora desactiva la bolsa F2 de una corrida anterior por su huella fija.

## 9 · 🔑 El lector global ve los leads DESACTIVADOS (asimetría real de la política)

El reset dejó exactamente 7 leads vivos (verificado con recibo). Gerencia vio 7 ✓ —
**directorio vio 55**, incluidos todos los transitorios ya desactivados. Medido en la
política viva `leads_select`:

```
( activo = true AND (propio | bandeja-supervisor | gerencia) )
OR es_lector_global()          ← esta rama NO filtra activo
```

Analistas, supervisores y gerencia solo ven leads vivos; el **lector global (Directorio) ve
también los soft-borrados**, con su PII (DNI, fecha de nacimiento). En producción hoy casi
no hay leads desactivados, así que no se nota — pero un lead «eliminado» por limpieza queda
legible para ese rol. **¿Es deliberado?** Decide Miguel; el arreglo sería una migración de
policy (`or (es_lector_global() and activo)`), nunca un retoque del test. Mientras tanto,
las dos aserciones «directorio ve 7» quedan rojas **diciendo la verdad**.

## 10 · El ledger de asignaciones hace que D8 no sea re-corrible en el mismo mes

Los dos rojos del bloque «fuera de roster» (D8) en la re-corrida:

```
fuera_de_roster antes {divisor 4, analistas 2} → después {divisor 5, analistas 2}
                                    esperado: +1 divisor ✓, +1 analista ✗ (delta 0)
```

**Causa, y es por diseño:** el divisor de conversión bebe del **ledger de asignaciones**,
que es INSERT-only — la garantía que la propia suite custodia («ni el gate perfora esa
garantía con hard-delete»). El reset no puede ni debe vaciarlo. Así que `sup1`, el productor
fuera-de-roster que el bloque siembra, **ya era** analista fuera-de-roster del mes por la
corrida anterior: su `divisor` sí suma +1 por corrida, pero `analistas` (conteo de
DISTINTOS) satura en la primera y el delta «+1 analista» sale 0 para siempre.

**Arreglo pendiente de OK (cambio de suite, no de servidor):** que D8 siembre un productor
**único por corrida** (perfil aleatorio) en vez de reutilizar a `sup1`; entonces el delta de
`analistas` vuelve a ser +1 en toda corrida. Mientras tanto, los 2 rojos dicen la verdad
sobre un mundo con historia — que es exactamente el mundo real.

## 11 · 🔑 El bloque de conversión CONSUME un analista ocioso por corrida (decisión pendiente)

Generalización del hallazgo 10, y la razón por la que el arreglo del D8 **aún no se ha
podido ejercitar de punta a punta**.

El bloque de conversión necesita, cada corrida, **un analista del roster con divisor 0 en el
mes** — es el sujeto del tercer estado (`solo_referidos`). Lo elige del payload y acto
seguido le da un referido… que entra en el ledger `crm.lead_asignaciones`. **Cada corrida
quema uno.** Medido tras cinco corridas del 01/09:

```
analistas del roster ociosos este mes: 0 de 6
```

Y entonces el bloque aborta con dos rojos honestos («la línea base tiene al menos una fila
sin_actividad», «hay un analista del roster sin actividad al que darle SOLO un referido»),
saltándose el resto — incluidas las aserciones del D8 que se acaban de arreglar.

**Por qué NO lo arreglé por mi cuenta.** La salida obvia sería limpiar el ledger en el
reset. El candado es explícito y absoluto:

```
trg_lead_asignaciones_00_inmutables  BEFORE INSERT OR DELETE OR UPDATE
  → 'Los episodios de asignacion no se eliminan'
```

Es **la garantía que la propia suite custodia** («ni el gate perfora esa garantía con
hard-delete»). Bajarla para poder ensayar es exactamente lo que este proyecto no hace, y a
diferencia del domicilio de la sonda —residuo de test sin valor— aquí el candado protege la
integridad de un ledger de auditoría.

**Las opciones, para que decida Miguel:**

| | Qué implica | Coste |
|---|---|---|
| **A. Analista ocioso rotatorio** | El reset crea un `GATE OCIOSO` fresco por corrida y retira el anterior | Toca el roster: hay que revisar toda aserción que cuente miembros |
| **B. Banco nuevo por mes** | Se acepta que el bloque corre una vez por banco y mes | Ninguno en código; el gate deja de ser re-corrible sin re-montar |
| **C. Limpiar el ledger en el reset** | Solo filas de leads transitorios, por psql | 🔴 Baja el candado que la suite custodia — **no recomendado** |

Mi recomendación es **A**, con el censo de aserciones afectadas hecho antes de tocar nada.
Mientras tanto los dos rojos dicen la verdad: el banco ya gastó sus analistas ociosos.

---

## Cómo repetir la corrida

```bash
export SUPABASE_URL=... SUPABASE_ANON_KEY=... SUPABASE_SERVICE_ROLE_KEY=...
export CRM_BANCO_PSQL_URL="$(cat $S/banco-pooler.txt)"   # pooler en SESIÓN, 5432
export CRM_DEMO_PASSWORD='...'
psql "$CRM_BANCO_PSQL_URL" -f supabase/scripts/banco/reset-gate-banco.sql  # hallazgo 8
npm run seed:demo        # ⚠️ ver abajo
#   → correr el bloque «Baja historica de vendInactive» de LEEME-seed.md
npm run test:rls
```

⚠️ **El seed necesita un permiso prestado.** `private.definir_periodo_comercial_contrato()`
es SECURITY INVOKER y lee `crm.periodos_cerrados` (deny-by-default), así que el INSERT del
contrato fixture muere con `permission denied for table periodos_cerrados`. Es un hallazgo
**preexistente** (29/08) y **producción está a salvo**: `crear_contrato` es la única vía que
inserta contratos allí. En el banco se resuelve prestando el permiso y **devolviéndolo**:

```sql
grant select on crm.periodos_cerrados to service_role;   -- antes del seed
revoke select on crm.periodos_cerrados from service_role; -- después (restaura la paridad)
```

## 04/09/2026 — «tercer estado» (conversión mensual) sin sujeto en banco a paridad 206

**Síntoma:** `testConversionMensual` falla «hay un analista del roster con divisor y cierres en cero al que darle un referido (sujeto del tercer estado)»: todos los analistas del roster aparecen `medible` con divisor > 1000.

**Aislamiento (banco-f7 llevado a paridad con prod, 206 versiones):** falla IGUAL con el lote Contrato-F2 aplicado (1195/1196) y SIN él (banco revertido: 36/1223, de los cuales 35 son el bloque de identidad — control negativo — y el otro es este). **No imputable al lote.** El 01/09 (paridad 196) el mismo fixture sí encontraba sujeto; entre medio entraron las migraciones del 02/09 (`ranking_poblacion_mes_calendario`, `conversion_total_analistas_solo_ranking`, `ranking_foto_mensual_coherente`) que redefinen población/divisor.

**Qué sigue:** quien mantenga la suite debe ajustar el fixture del «tercer estado» a la nueva semántica de población (o sembrar explícitamente un analista sin recibidos en el mes). No bloquea el lote. Referencia: `test-rls-f3b.log` / `test-rls-f3e-revertido.log` en el scratchpad de la sesión del 03/09.

## 04/09/2026 — deriva ajena en la suite (P-058, `7f6e1d4`)
El bloque «P04: matriz completa de offboarding» abortaba la suite entera con `client.schema is not a function`: las
tres llamadas nuevas de P-058 a `assertAccess(...)` pasaban `sessions.X` en vez de `sessions.X.client`. Corregido en la
rama `feat/multiempresa-f2b-cola` (`sessions.X.client`). Con el código de `main` tal cual, la suite no llega a los
bloques posteriores (identidad incluida).

## 05/09/2026 — el banco es UNO y lo comparten las sesiones (ensayos rojos en cascada sin bug)
Dos ciclos de D-13 (`20260905160000`, v4.2 y v4.3) salieron rojos en cascada (43/31 y 45/29 en el oráculo; b1 11/20
cuando una hora antes daba 31/31) con un síntoma común: a mitad del ensayo `resolver_en_puertas` estaba APAGADA
(«Identidad unificada apagada: usa la reserva por lead») o los fixtures chocaban con `uq_leads_dni_vivo`. La migración
estaba bien (el mismo oráculo, solo, dio 74/74 minutos antes): otra sesión de Claude estaba usando banco-f7 a la vez
(53 leads de un `seed:demo` entre 18:42 y 18:46, `ficha_360_neutral` tocada a las 19:05, cliente PostgREST activo), y
la suite de esa sesión fija `resolver_en_puertas=false` en el bloque bancario (`c6796ea`).
Reglas: (1) antes de un ciclo largo, mirar `crm.multiempresa_flags.actualizado_en` y `pg_stat_activity` (clientes
PostgREST = alguien corre la suite) y `ListAgents` + `SendMessage` para pedir turno; (2) el `flag()` de los oráculos
RELEE y reintenta (si no lo consigue cuenta rojo) — antes escribía a ciegas; (3) un resumen «68/74» venía de un log
VIEJO por un nombre de archivo mal cambiado en el script de banco: el conteo se lee del MISMO archivo que se escribe;
(4) no editar la migración ni un oráculo mientras un ciclo los está leyendo (bash lee el script a medida que avanza).

## 05/09/2026 — dos rojos que no eran del código (ciclo de D-13 v4.4)
1. **`oraculo-f2b-b2.sh` 34/35 «resumen () ≠ cola»** desde que existe: el aserto leía `crm.resumen_reparto_fn()->'por_origen'`
   y la función devuelve `{cola: {por_origen: [...]}}` (la suite, `b2 #9`, sí lee `cola.por_origen`). El diagnóstico anterior
   («salida vacía intermitente del pooler») era falso: `sum()` sobre un jsonb nulo da NULL y el oráculo lo imprimía vacío.
   Corregido en el oráculo (ruta `->'cola'->'por_origen'`). Lección: un rojo que se repite IGUAL en cada corrida no es
   intermitente; leer la forma real de la respuesta antes de culpar a la red.
2. **Suite: `metricas_conversiones_fn` → 57014 statement timeout** (y dos asertos en cascada del mismo bloque). El banco
   acumula **14 250 leads / 13 774 asignaciones** de meses de oráculos append-only y la RPC tarda **8,1 s** como Gerencia,
   por encima del `statement_timeout=8s` del rol `authenticated`. No es D-13 (no toca métricas): es el volumen del banco.
   Señal para producción: esa RPC escala mal con los leads (14 k → 8 s); si prod se acerca a esa cifra, habrá que
   indexar/materializar antes ([[crm-escalabilidad-plan]]). Mientras, el banco necesita una poda de fixtures viejos
   (`D13 %`, `F3 %`, `B1 %`… con RUN antiguo) o aceptar ese rojo como ambiental.

## Hallazgo (06/09, madrugada) — `testConversionMensual`: 4 rojos nuevos al cierre del bloque 2 de F2.b

En la última corrida de la noche (suite 1588/1597) aparecieron 4 rojos en el bloque `testConversionMensual` (`total.analistas == responsables + fuera_de_roster.analistas` para gerencia/directorio/sup1/sup2, `{"total":12,"filas":12,"fuera":5}`, y «el payload trae SOLO las 11 claves del contrato») y la suite pasó de 1480 a 1597 aserciones. Ese bloque no lo toca el bloque 2 (D-9/D-3/D-2 no transforman `metricas_conversiones_fn` ni el ranking) y estuvo VERDE en las tres corridas anteriores de la misma noche con las tres migraciones aplicadas. Lo que cambió entre corridas: el día (06/09) y más cierres de cooperativa acumulados por los actores F3 de los oráculos (`F3 VENDEDOR` y los vendedores `V2`/`V3` que crea `oraculo-f2b-d2.sh`), que quedan «fuera del roster» del seed. Sin diagnosticar: hay que ver si el invariante del ranking cuenta mal a los analistas fuera de roster cuando son varios (es de la sesión del tablero de Gerencia) o si es solo residuo del banco. Los otros 5 rojos son los ambientales conocidos (timeout de `metricas_conversiones_fn` con 14 250 leads, +2 en cascada, y el «tercer estado»).
