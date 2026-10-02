**VERDICT: CHANGES_REQUESTED**

**SUMMARY:** Los tres hallazgos concretos de la ronda 1 están resueltos en los fragmentos. No identifico una nueva fuga de RLS. Quedan problemas en la predicción alrededor de las 05:40, la comprobación del job y la garantía de restaurar la bandera.

**FINDINGS: 3 P2; ningún P0/P1 identificado.**

1. **P2 — Las 05:40 no implican que la última pasada haya ocurrido.**

   Evidencia: [migración](/Users/usuario/Desktop/DESARROLLO/DESARROLLO/wt-potencial-lead/supabase/migrations/20261001151704_crm_potencial_lead_lectura.sql), `potencial_proxima_corrida`:

   ```sql
   when (...)::time < time '05:40' then ...::date
   else ...::date + 1
   ```

   Contraejemplo: Estrella marcada el 05/10, reabierta el viernes 16/10 a las 05:20. Una lectura a las **05:40:00**, antes de que el worker arranque, devuelve `frio@2026-10-17`. La pasada programada para las 05:40 puede comenzar inmediatamente después y aplicar **`tibio` el 16/10**.

   No requiere contactos, marcas nuevas, bloqueo del lead ni agotamiento del lote. El horario programa el inicio; no acredita ejecución ni finalización.

   Para conservar el contrato actual, hay que contemplar la pasada pendiente o en curso. Alternativamente, explicitar que se calcula desde el siguiente horario nominal y que una pasada de hoy todavía puede producir otra bajada. Mover el corte unos segundos solo desplaza el problema.

2. **P2 — El postflight permite aprobar sin haber comprobado el supuesto operativo del calendario.**

   Evidencia: `$postflight$`, en la misma migración:

   ```sql
   if pg_catalog.to_regclass('cron.job') is not null then
     ...
   end if;
   ```

   Con las funciones de fase 2 presentes y sin `cron.job`, la migración pasa y anuncia **«horario del job comprobado»**. Sin embargo, no ha acreditado que exista la tarea que sustenta `baja_el`.

   Cuando la tabla existe, solo se comprueban `jobname`, `schedule` y `active`. Un job con ese nombre y horario, pero con otro comando o destino, también satisface el predicado. Tampoco se verifica que el horario se interprete en GMT.

   Son **falsos verdes posibles del comprobador**, no configuraciones incorrectas demostradas en el banco. Exigir el job operativo esperado para el despliegue; si se permite instalar sin cron en bancos, distinguir expresamente ese resultado y no anunciar la comprobación como realizada.

3. **P2 — La restauración de la bandera sigue siendo condicional.**

   Evidencia: [test-rls.mjs](/Users/usuario/Desktop/DESARROLLO/DESARROLLO/wt-potencial-lead/supabase/scripts/test-rls.mjs), `fijarBandera(true)` fuera de banda y:

   ```js
   finally {
     try {
       fijarBandera(false);
     } catch (error) {
       fail(...);
     }
   }
   ```

   Si el encendido se confirma y falla la conexión durante la reposición, la bandera puede quedar encendida. El bloque informa el fallo, pero no restaura el estado. Una terminación abrupta del proceso tampoco ejecuta necesariamente el `finally`.

   En una base compartida, además, el `false` incondicional puede sobrescribir un encendido legítimo concurrente. El fragmento no muestra exclusión ni una restricción a bancos desechables.

   Limitar esta fase a un banco desechable y exclusivo, o establecer una recuperación independiente y comprobable. Si el runner ya impone ese aislamiento, su evidencia permitiría tratar esto como una limitación documentada del banco.

**Riesgos y test gaps:**

- **Calendario:** entre las 05:10 y las 05:40, devolver hoy es coherente porque queda la segunda pasada. El cambio de medianoche también es continuo: 23:59 y 00:00 apuntan a la misma fecha siguiente. El problema identificado es confundir el horario con el estado de ejecución.
- **Permisos y configuración:** la igualdad exacta de `proconfig` corrige el hallazgo anterior. Los permisos efectivos consideran correctamente la herencia; el acceso heredado del puente documentado no contradice esa comprobación.
- **Excepción esperada:** `WHEN insufficient_privilege` acepta cualquier `42501`, no acredita por sí solo que provenga de la guarda del actor. Conviene comprobar también una llamada válida desde el mismo contexto de despliegue; no afirmo que actualmente esté capturando otro error.
- **Actor:** no encuentro ruptura de un uso legítimo de la puerta. Esta obtiene `auth.uid()` y lo pasa al núcleo dentro de la misma llamada. Los usos internos con una identidad distinta quedan expresamente excluidos por el nuevo contrato.
- **Ronda 1:** ACL nula, configuración adicional, grant option y duplicados están corregidos en los fragmentos correspondientes. La comparación con RLS ya es alcanzable en el gate, pero su ejecución con sesiones reales continúa **NOT RUN**.
- No se transcribe el cuerpo de `potencial_caducar` ni el comando efectivo del job; la equivalencia completa con la tarea permanece condicionada a esa evidencia.

**NEXT ACTIONS:** Cubrir una pasada de las 05:40 todavía pendiente, endurecer la comprobación operativa del job y acreditar el aislamiento o recuperación del gate. Añadir casos de ausencia de cron y fallo de reposición. Ejecutar después el gate con sesiones reales en el banco autorizado.

**CONFIDENCE:** Alta en los comportamientos derivados de los fragmentos; limitada para ejecución real. Los PASS del banco son evidencia aportada. Pruebas ejecutadas por este revisor: **NOT RUN**.
