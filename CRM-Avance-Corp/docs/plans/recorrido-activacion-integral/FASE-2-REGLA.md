# Fase 2 — Regla para todas las primeras conversiones pendientes

Estado: **PASS local, 6/6 subfases**. No acredita instalación productiva. Candidato en dos migraciones aditivas, 20261019061000/61001; los ocho archivos anteriores permanecen intactos.

1. **Migración aditiva:** el inicio de exigencia se compara con el reloj del servidor, sin filtrar la antigüedad del lead/ciclo. Preflight de cuatro contratos y del control aún no activado. La prueba nueva falló contra el backend anterior precisamente porque dejaba exentos los tres ciclos antiguos; pasó tras instalar el candidato.
2. **Lectura coherente:** la RPC y los guards comparten fecha de inicio y alcance. Una activación programada no bloquea antes de la hora; al llegar incluye también al antiguo. No cambia la forma de la RPC publicada. `recorrido_confirmado` incorpora el alcance en su JSON interno, sin nuevos campos obligatorios de frontend.
3. **Borradores y reintentos:** un borrador anterior a la activación conserva datos, capital y comprobante; no confirma sin hechos. Al acreditar la misma cita confirma una vez y su reintento devuelve la misma inversión. Un antiguo sin ciclo tampoco queda exento.
4. **Activación y reversión:** se mantienen Gerencia efectiva, revisión optimista, motivo auditado y fecha inmutable. Apagar/observar elimina la exigencia sin borrar hechos; reactivar vuelve a cubrir nuevos y antiguos. Se conserva el flujo de inversiones ya confirmadas, adicionales, renovación y upgrade.
5. **Permisos/hardening:** RPC solo `authenticated`; helpers solo propietario `postgres`, SECURITY DEFINER con search_path vacío; RLS y auditoría conservados. Catálogo real en `evidencia/fase2-catalogo.json`.
6. **Revisión y correcciones Codex:** se aceptaron los dos P2 del auditor RLS. La instalación bloquea el singleton hasta COMMIT y el hardening rechaza cualquier grantee privado distinto del propietario. Ambas regresiones pasan, además del replay íntegro en copia desechable.

## Revisión especializada y resolución

Auditor RLS, SECONDARY_REVIEWER de solo lectura: **CHANGES_REQUESTED** sobre la primera versión. No identificó bypass por antigüedad, fecha programada ni ampliación del ámbito de lectura.

| Hallazgo | Decisión del PRIMARY | Evidencia de corrección |
|---|---|---|
| P2: comprobar control previo sin lock permite activación concurrente | Aceptado. `FOR UPDATE` en el preflight, conservado hasta COMMIT | El ensayo observa espera real de activación hasta terminar instalación; un control previamente activado es rechazado. |
| P2: hardening solo prohíbe cuatro destinatarios de EXECUTE | Aceptado. Rechaza todo grantee distinto del owner | Un grant sintético a `pg_monitor` hace fallar hardening; tras rollback, el archivo completo pasa. No existía ese grant en el banco real. |

El reviewer no ejecutó pruebas. Los resultados anteriores corresponden a verificaciones del PRIMARY; no se transformó su dictamen original en un PASS del reviewer.

## Evidencia

- `evidencia/fase2-test-rojo.log`: fallo de política esperado contra versión anterior (tras corregir un permiso del fixture, sin ampliar permisos de producto).
- `evidencia/fase2-instalacion-local.log`, `fase2-test-todos.log`, `fase2-catalogo.json`.
- `evidencia/fase3-test.log`, `fase3-test-oficina.log`, `fase3-test-conversion.log`, `fase3-test-revision.log`, `fase3-test-todos.log`: SQL real con rollback.
- `evidencia/fase3-concurrencia-conversion.log`: replay del paquete, instalación/activación concurrente, grant inesperado, pérdida de respuesta, rollback, invalidación y cambio de modo.

La comprobación de consumidores encontró solo los cinco callers privados/financieros ya conocidos. El frontend publicado no consume `recorrido_confirmado` como objeto estricto y la RPC de lectura conserva su forma. No cambian tablas, argumentos ni tipos generados en este bloque; la nueva clave queda dentro del tipo `Json` existente.

## Límite histórico

Los 78 registros ambiguos del censo no se convierten automáticamente en cumplidos. No se implementa certificación retrospectiva ni excepción masiva. Se debe registrar una atención real con evidencia trazable; no usar «Llegó sin cita» para inventar una visita anterior. La capacitación y el runbook quedan actualizados con el alcance aprobado.
