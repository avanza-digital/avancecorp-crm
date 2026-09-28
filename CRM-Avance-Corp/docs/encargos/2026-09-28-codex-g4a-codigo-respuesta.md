# Respuesta de Codex (28/09) — código G4a

Aplicado: afirmaciones con agregado (siempre corren), postventa presente/ausente en items y en todas las páginas, recorrido = conjunto esperado, ACL efectiva de anon explícita y llamada con un actor activo validado, ciclo del registrador con historial persistente, prueba del camino demo de Gerencia. check del front PASS (4686). test-rls.mjs: NOT RUN (requiere banco con semilla).

**VERDICT: CHANGES_REQUESTED**

**SUMMARY**

No encuentro una escalada demostrada en el núcleo mostrado: rechaza explícitamente el rol nulo, limita los roles, comprueba el roster y conserva `SECURITY INVOKER`. El sellado exige las huellas previstas y la reversa comprueba el resultado dentro de su transacción.

Los cambios solicitados afectan a pruebas que pueden aprobar sin acreditar lo que anuncian. No identifico P0/P1 con la evidencia disponible.

**FINDINGS**

**[P2] Las comprobaciones de cifra/lista y postventa admiten falsos positivos.**

Archivo: `supabase/scripts/g4/test-g4a.sql`, apartados 2 y 3.

Evidencia:

- La afirmación «cifra del detalle = lista» depende de un `LATERAL` que devuelve únicamente filas cuyo `analista_id = v1`. Si el detalle omite ese analista, devuelve cero filas y **no se ejecuta `pg_temp.afirmar`**. Sucede también en la comprobación con postventa apagada.
- La comprobación positiva de postventa usa `FROM g4_ids WHERE item->>'titulo' = 'G4A POSTVENTA'`: tampoco afirma nada si falta esa fila.
- «postventa oculta: fuera de la cifra y de la lista» comprueba solamente:
  ```sql
  (p#>>'{resumen,tareas_pendientes}')::int = 1005
  and (f->>'tareas_pendientes')::int = 1005
  ```
  No inspecciona los elementos devueltos.

Impacto: estas pruebas no detectan necesariamente la desaparición del detalle ni una regresión que mantenga los contadores correctos y exponga postventa en los elementos. **No afirmo que el núcleo actual produzca esa fuga.**

Recomendación: exigir exactamente una fila del detalle; afirmar expresamente la existencia de la tarea postventa con banderas activas y su ausencia en los elementos con la bandera apagada. Comparar los identificadores esperados en el recorrido paginado.

**[P2] La prueba de `anon` no distingue permisos de ejecución de una identidad desactivada.**

Archivo: `supabase/scripts/g4/test-g4a.sql`, apartados 6 y 7.

Evidencia: primero se ejecuta:

```sql
update crm.equipo set activo = false
where perfil_id = (select gerente from g4_actores);
select pg_temp.como(gerente) from g4_actores;
```

Después se cambia a `anon` sin sustituir esa identidad. `pg_temp.denegada` únicamente exige `42501`.

Impacto: si se concediera accidentalmente ejecución, la llamada podría seguir devolviendo `42501` por la identidad desactivada. La prueba continuaría aprobando sin acreditar la restricción de ejecución anunciada.

Recomendación: comprobar explícitamente los permisos efectivos de función y esquema previstos; complementar con llamadas bajo `anon` usando un `sub` de actor activo previamente validado. Separar la denegación por permisos de la denegación de negocio.

**TEST GAPS**

- `npm run check`: **NOT RUN**, según el PRIMARY. Los PASS comunicados de unitarias y banco no sustituyen este check.
- No se aporta ejecución del bloque nuevo de `test-rls.mjs`. Para esta entrega debe ejecutarse con `CRM_RLS_EXIGE_GESTION_DIARIA=1`, evitando que una RPC ausente termine solamente como «SALTADOS».
- Los tests añadidos del front acreditan presencia de pestaña y llamada al doble; no muestran apertura completa con respuesta validada ni cobertura del nuevo camino demo de Gerencia.
- El ensayo del registrador acredita una inserción exacta. No se aportan pruebas de segunda ejecución, rechazo de filas discordantes ni del ciclo completo **aplicar → registrar persistentemente → revertir → reaplicar → registrar**.

**REGRESSION RISKS**

- **Historial después de la reversa:** el script restaura H3 y conserva la fila `20260928043728` si ya estaba registrada. La reaplicación manual indicada puede funcionar; debe quedar explícita en la recuperación. **Hipótesis condicionada:** un publicador que omita versiones presentes en el historial podría mantener H3 y publicar el front que requiere G4a.
- **DDL concurrente:** las comprobaciones de huellas no constituyen exclusión mutua entre lectura y `CREATE OR REPLACE`. **Hipótesis condicionada:** otra modificación confirmada en ese intervalo podría ser sobrescrita. No se aporta evidencia de concurrencia real; mantener una única publicación sobre esas funciones cubre este riesgo.
- **Orden:** aplicar y verificar G4a, registrar y después publicar el front. La reversa documentada —front anterior primero, base después— es coherente. La publicación debe usar el artefacto del commit verificado conforme a las reglas de Main.

**RECOMMENDED NEXT ACTIONS**

1. Corregir las dos pruebas señaladas y repetir el banco.
2. Ensayar el ciclo con historial persistido y los rechazos del registrador.
3. Completar `npm run check`, la prueba RLS exigente y la verificación aplicable del front; reportar PASS/FAIL/NOT RUN antes de publicar.

**CONFIDENCE: MEDIUM**

Alta sobre los defectos de prueba señalados. La evaluación de producción se limita al código y resultados transcritos; no ejecuté comprobaciones ni dispongo de los cuerpos completos del ámbito, las políticas RLS o H3.
