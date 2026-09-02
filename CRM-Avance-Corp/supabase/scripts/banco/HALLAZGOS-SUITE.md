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
