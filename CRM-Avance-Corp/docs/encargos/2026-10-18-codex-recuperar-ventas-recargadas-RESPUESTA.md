**VERDICT: CHANGES_REQUESTED**

**SUMMARY**

La v2 corrige la carrera sobre las tres filas bloqueadas, pero todavía no demuestra que pueda aplicarse con los referidos reales. El tope puede hacer incompatibles sus dos garantías: «cada recuperada aporta» y «ningún otro aporte cambia».

No encuentro una ruta demostrada que confirme parcialmente los cambios de datos. Sí encuentro limitaciones en la prueba de concurrencia y mutantes que mueren antes de comprobar lo que anuncian.

Revisión estática sobre la transcripción. Referencio bloques y sentencias exactas; no atribuyo números de línea del repositorio que no he verificado.

**FINDINGS**

**[P1] El tope puede impedir la recuperación incluso sin concurrencia — pregunta 1**

Archivo: `supabase/migrations/20261018032400_crm_recuperar_ventas_recargadas.sql`, `$postflight$`, comprobaciones «exactamente un cierre» y `EXCEPT ALL`.

Evidencia:

- `conversion_episodios` calcula el límite usando **todos** los referidos válidos del analista y mes.
- Recuperar uno aumenta `total_referidos`.
- También incorpora su aporte bruto a `aporte_anterior_referidos` de los posteriores.
- El postflight exige aporte positivo para el recuperado y compara el aporte de todos los demás.
- `test-recuperar-ventas.sql`, `pg_temp.cliente_y_lead`, siembra tanto el lead como su asignación con origen **`landing`**. No reproduce los casos referidos 1 y 2.

Contraejemplo permitido por el fragmento: un referido existente con aporte bruto `1` y tope `15 %` aporta `0,15`. Al recuperar otro con bruto `1`:

| Orden comercial | Existente después | Recuperado | Rechazo |
|---|---:|---:|---|
| Existente, recuperado | 0,30 | 0 | Ambos controles |
| Recuperado, existente | 0 | 0,30 | `EXCEPT ALL` |

No afirmo que esos sean los valores actuales de producción: demuestra que las garantías no se deducen del código ni del banco.

**Acción:** proyectar el reparto completo de octubre para Astrid y Nayra antes de aplicar. No basta consultar el aporte actual ni comprobar que actualmente hay margen. Incluyo una consulta abajo.

---

**[P2] El corte fijo no garantiza que las altas concurrentes queden fuera de la comparación — pregunta 2**

Archivos:

- Migración, `recuperar_corte` y comparación final.
- `test-recuperar-ventas.sql`, V2.
- Fragmento de `private.conversion_episodios`, rama `recibido`.

V2 inserta expresamente `creado_en = clock_timestamp()` después del corte y sin asignación. Prueba ese caso concreto.

La función también consulta la **primera asignación actual**, sin limitar `lead_asignaciones.asignado_en` por `p_fin`. Escenario:

1. La foto inicial incluye un lead ajeno, creado antes del corte, todavía sin asignación.
2. Otra transacción inserta y confirma su primera asignación.
3. La foto final devuelve otro `analista_id` para ese mismo episodio.
4. `EXCEPT ALL` aborta la recuperación.

Los locks mostrados no bloquean esa tabla ni ese lead ajeno. Falta el cuerpo del escritor de asignaciones para determinar si otra exclusión impide realmente esta intercalación.

Además, una inserción concurrente con `creado_en` anterior al corte —por ejemplo, si utiliza `now()` de una transacción iniciada antes— tampoco queda excluida necesariamente.

**Impacto:** posible aborto completo, no corrupción parcial. La afirmación del comentario «un lead que entre durante la migración no cambia la comparación» es demasiado amplia.

---

**[P2] Parte de los mutantes muertos no acredita la defensa anunciada — pregunta 6**

Archivos: `mutantes.py`, `probar.sh` y ayudantes de `test-recuperar-ventas.sql`.

1. **«cierre_anulado … lo atrapa D1» no demuestra D1.**  
   Desactiva también la huella y «exactamente un cierre», pero conserva I2/I3, que exigen precisamente esos rechazos. El log muestra que muere esperando un rechazo de `POSTFLIGHT`, antes de D1. Puede morir por quitar esas defensas aunque la conducta que supuestamente debe detectar D1 fuese correcta.

2. **«tabla: sin RLS, con postflight apagado» no demuestra una comprobación independiente de RLS.**  
   I5a exige que el postflight rechace un `GRANT`. Al apagarlo, ese test mata el mutante antes de llegar a D2. Ese resultado tampoco demuestra que quitar solamente RLS sea detectado por D2.

3. **«sin inmutabilidad» no permite UPDATE/DELETE como afirma su etiqueta.**  
   Un trigger `BEFORE ROW` que devuelve `NULL` omite la modificación de esa fila. El test muere porque falta la excepción, aunque UPDATE/DELETE sigan sin cambiar datos. TRUNCATE sí requiere una prueba separada: el retorno de un trigger de sentencia no lo cancela.

4. **«sin la nota» muere en V1, no en D8.**  
   Transformar el INSERT en `SELECT * FROM (VALUES (..., NULL)) ... WHERE false` introduce resolución de tipos distinta: ese `NULL` dentro de `VALUES` puede resolverse como `text`, incompatible con una columna UUID. El filtro falso no evita validar los tipos. El error esperado sería `42804`, ausente de `es_error_de_ensayo`; `aplicar_ok` lo envolvería como `FALLA` y el runner lo contaría como muerto.  
   El log truncado no permite confirmar ese SQLSTATE, pero sí confirma que **no lo mató D8**. Hace falta conservar el error completo y eliminar realmente la sentencia para probar ausencia de nota.

Las cuatro sustituciones con huellas recalculadas y muerte por D6 corrigen su problema específico. No corrigen los anteriores.

**RISKS — respuestas restantes**

**2. Atomicidad y deadlocks.** Todos los cambios persistentes mostrados están dentro de la segunda transacción. Un rechazo, timeout o deadlock antes del COMMIT los revierte conjuntamente. No veo un COMMIT intermedio que deje dos ventas arregladas y tres pendientes.

Para los locks **mostrados**, tampoco encuentro un ciclo inevitable con `conversion_acreditar_fuente`:

- Si otra operación posee un mes, el `try-lock` aborta.
- Si posee una de las tres filas y espera el mes que tiene la migración, `FOR UPDATE NOWAIT` aborta la migración.
- Después del preflight, esas filas permanecen bloqueadas hasta terminar.

No puedo descartar otros ciclos: se adjunta la huella del escritor, pero no su cuerpo completo ni todos los locks de sus llamadores.

Hay una salvedad operativa concreta: **el lock de sesión de migraciones sobrevive al rollback**. Si el error impide ejecutar el `pg_advisory_unlock`, solamente el cierre del backend o una liberación explícita lo elimina. El informe anterior supone que la sesión termina; aquí no hay evidencia del ciclo de vida de la conexión de `db query`. No queda data parcialmente aplicada, pero podría quedar bloqueada otra migración si el backend se conserva.

**3. Excepción por fila.** Para otra copia con distinto `ie.id`, otra anulación con distinto `ca.id` y el canal externo no modificado, **no refutable con lo dado**: los predicados añadidos no los exoneran. D3 sí prueba otra copia del mismo lead en `cierre_anulado`.

Una futura anulación de Avance del mismo lead 3/4 queda **prohibida**, conforme a lo declarado; no se acepta y luego se ignora silenciosamente.

Dos límites:

- La validación de correspondencia ocurre al INSERT. Que esos IDs nunca puedan reasignarse posteriormente a otro lead depende de la inmutabilidad de las tablas referenciadas, cuyo DDL no está transcrito.
- En `altas_nuevas_por_analista_fn`, el filtro elimina **toda la expansión** de `private.contratos_afectados_por_anulacion(ca.lead_id)`. Si ese ayudante devuelve otros contratos elegibles además del recargado, también dejan de excluirse por esa anulación. El postflight de conversión no comprueba este informe y D6 siembra solamente su escenario conocido. Es un riesgo condicionado, no un efecto demostrado en producción: hay que verificar el conjunto que devuelve el ayudante considerando el nuevo enlace.

D7 demuestra además que un INSERT privilegiado posterior puede rehabilitar un sexto lead. La restricción a cinco es la de esta ejecución y sus permisos, no una lista permanente de cinco IDs. No lo considero una vía de explotación desde la API con los grants mostrados.

**4. Dependencias de la fecha comercial.** Se demuestra que se actualizan contrato, inversión y valoración, y el informe anterior aporta que el observador diferido de tasa no se dispara por esa columna. **Cronograma, rentabilidad y demás consumidores: no refutable con lo dado.** No están sus cuerpos ni un inventario de dependencias.

Tampoco hay evidencia para recomendar regenerar cronogramas: cambiar una fecha comercial no implica cambiar el inicio financiero. Falta contrastar el paso 3a con el cuerpo completo de la puerta oficial y sus consumidores. D1 comprueba expresamente la valoración de B; no hace esa misma comprobación individual para E.

**5. Reversa.** Su promesa principal es honesta y parcial: restaura funciones, vuelve a anular 3/4 y conserva enlaces, fechas e historia. No veo un empeoramiento adicional demostrado respecto de ese alcance.

Quedan límites operativos:

- No se ejecuta en la batería adjunta.
- Tras revertir, no se puede reaplicar directamente la migración original: la tabla y las funciones auxiliares siguen existiendo.
- El gate de sellos usa un `INNER JOIN` con acreditaciones y no comprueba que encuentre las cinco. Como el ledger deliberadamente no tiene esa FK, una acreditación ausente quedaría fuera del control. No se demuestra aquí una vía normal para borrarla, pero tampoco existe una defensa de cardinalidad en la reversa.
- Comparte el posible lock de sesión retenido tras un error.

**TEST GAPS**

No quedan probadas por esta batería ni por los mutantes listados:

- Contención real de los locks global, mensuales y de filas; orden de adquisición con dos backends.
- Adquisición/liberación del lock de sesión por el archivo completo: el arnés sustituye esa envoltura.
- COMMIT real y validaciones diferidas pendientes: la aplicación base termina en ROLLBACK.
- Los dos referidos reales, con otros referidos anteriores, posteriores y parcialmente admitidos.
- Efectos de «Altas nuevas» sobre otros contratos afectados por las anulaciones rehabilitadas.
- Reversa completa y sus rechazos.
- Las cláusulas individuales de guards compuestos. Matar «sin validar la acreditación», por ejemplo, no prueba por separado `incluida_en_sello`, `ajuste_anulacion_en_sello` y cada condición restante.

También conviene reproducir los **353 000 PEN** del caso 5: el banco usa **35 300**. Sin el cuerpo de valoración no se puede descartar una diferencia por reglas dependientes del importe.

**NEXT ACTIONS**

1. Resolver primero la proyección de referidos. La siguiente consulta compara antes/después sobre el mes completo y muestra los aportes dentro del corte.

   **Condición necesaria:** confirmar en `conversion_cierres` el aporte bruto que producirían los candidatos con `p_factor = 1`. Su cuerpo no está adjunto. Los dos `1::numeric` siguientes son una hipótesis explícita; deben sustituirse si el cuerpo establece otro aporte. No presentar el resultado como certificación sin esa comprobación.

```sql
begin isolation level repeatable read read only;

select pg_catalog.pg_get_functiondef(
  'private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])'
  ::regprocedure
);

with
corte as (
  select statement_timestamp() as fin
),
casos(lead_id, analista_id, fecha_numerador, bruto) as (
  values
    ('0f091c66-89f1-4dc9-9d4a-120da8499a24'::uuid,
     '2ec5954f-0490-44f2-87cd-af6210f3426f'::uuid,
     timestamptz '2026-10-05 00:00:00-05', 1::numeric),
    ('3851878c-b5fb-4372-b45e-5f89d39afc85'::uuid,
     'ad36b962-5175-4e4e-b644-e546897c3a85'::uuid,
     timestamptz '2026-10-01 00:00:00-05', 1::numeric)
),
base as materialized (
  select c.lead_id, c.analista_id, c.fecha_numerador,
         ca.acreditado_en as registrado_en,
         c.aporte_numerador as bruto
  from private.conversion_cierres(
    timestamptz '2026-10-01 00:00:00-05',
    timestamptz '2026-11-01 00:00:00-05',
    null, true, null, 1, null::uuid[]
  ) c
  left join crm.conversion_acreditaciones ca
    on ca.lead_id = c.lead_id
  where c.fue_referido and not c.anulado
    and c.analista_id in (select analista_id from casos)
),
versiones as (
  select 'antes'::text as foto, false as recuperado, b.*
  from base b
  union all
  select 'despues', false, b.*
  from base b
  union all
  select 'despues', true, c.lead_id, c.analista_id,
         c.fecha_numerador, k.fin, c.bruto
  from casos c cross join corte k
),
ventanas as (
  select v.*,
         count(*) over (
           partition by foto, analista_id
         ) as total,
         coalesce(sum(bruto) over (
           partition by foto, analista_id
           order by fecha_numerador, registrado_en, lead_id
           rows between unbounded preceding and 1 preceding
         ), 0) as previo,
         private.tope_referidos_conversion(date '2026-10-01') as pct
  from versiones v
),
aportes as (
  select v.*,
         case when pct is null then bruto
              else least(bruto,
                greatest(0::numeric, total * pct / 100.0 - previo))
         end as neto
  from ventanas v
)
select d.analista_id, d.lead_id, d.recuperado,
       a.neto as aporte_antes, d.neto as aporte_despues,
       case when d.recuperado then d.neto > 0
            else d.neto is not distinct from a.neto
       end as cumple_postflight
from aportes d
left join aportes a
  on a.foto = 'antes'
 and a.analista_id = d.analista_id
 and a.lead_id = d.lead_id
cross join corte k
where d.foto = 'despues'
  and d.fecha_numerador < k.fin
order by d.analista_id, d.fecha_numerador, d.registrado_en, d.lead_id;

rollback;
```

   Deben aparecer ambos candidatos y todas las filas deben cumplir. La simulación supone que la reacreditación ordena los candidatos después de las acreditaciones existentes con igual fecha comercial; comprobar timestamps futuros y ejecutar cerca de la aplicación. Es una proyección de esa instantánea, no una exclusión de concurrencia.

2. Añadir los escenarios de referidos reales y una prueba con dos sesiones. Mantener la protección de «otros aportes» hasta conocer qué redistribución exige el tope.

3. Corregir los mutantes descritos y registrar **qué aserción mata cada uno**, conservando SQLSTATE y error completo.

4. Ensayar el archivo completo con COMMIT en un banco desechable, seguido de la reversa; comprobar además el conjunto de contratos afectado en «Altas nuevas».

**CONFIDENCE: MEDIUM**

Alta para el contraejemplo del tope, la limitación del corte y los problemas identificados en mutantes. Media para concurrencia integral y dependencias financieras: faltan cuerpos de escritores y consumidores. Ejecución independiente de pruebas: **NOT RUN**. Los PASS comunicados se consideran evidencia aportada, no resultados verificados por esta revisión.
