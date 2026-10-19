**VERDICT: PASS_WITH_NOTES — revisión estática.**

**SUMMARY**

No encuentro nuevos defectos P0–P2 en la enmienda:

- **Preflight:** `pg_get_functiondef` incorpora STRICT, SECURITY, SET y volatilidad; propietario y ACL se comprueban aparte. `p.oid is null` e `IS DISTINCT FROM` evitan aceptar funciones ausentes o valores nulos. La comparación textual de ACL puede rechazar una representación equivalente, pero falla hacia el rechazo.
- **Precondición 0b:** exigir ambas funciones con la identidad anterior evita sobrescribir una instalación modificada y rechaza reaplicar la enmienda.
- **Corte:** creación, asistencia y `generado_en` comparten exactamente `v_ahora`. La corrección satisface la coherencia temporal solicitada; no convierte los estados actuales en una reconstrucción histórica.
- **Reversión:** restaura explícitamente cuerpo y COMMENT, reafirma ACL y exige las huellas anteriores de núcleo y puerta. Las constantes son consistentes entre instalación y reversión.
- **Aserciones:** `IS DISTINCT FROM`, `RAISE EXCEPTION`, comprobación de 53 casos y `ON_ERROR_STOP=1` hacen que las discrepancias detectadas terminen el proceso con error.

El rechazo revierte **la transacción de la enmienda**. La 0b previamente confirmada permanece instalada hasta ejecutar la reversión manual indicada en el ledger; ambas instalaciones no son atómicas.

**FINDINGS P0–P3**

**P3 — El caso de regresión del corte depende del calendario al reutilizar la batería.**

Evidencia: la tarea `de` usa `creado_en = now() + interval '2 seconds'`, mientras las consultas de `r_on` tienen rangos fijos. El más amplio de Proyección, `rango-365`, termina el **2027-01-01**.

Por ejemplo, ejecutando el **2027-01-02**, `de` queda fuera de todos esos rangos incluso sin el nuevo predicado. La comprobación de ausencia pasa por el filtro de fechas, y la comprobación global de coherencia tampoco encuentra esa fila. La batería puede volver a dar **53/53 sobre la 0b sola**.

Esto no invalida el ensayo reportado del 19/10. Conviene añadir una consulta específica cuyo rango incluya siempre la fecha de `de`.

**TEST GAPS**

- **NOT RUN por mí:** banco, mutantes, concurrencia, tope y ciclos de reversión. Tampoco pude contrastar el commit `00c32abb` ni recalcular las huellas.
- El bloque del tope no está adjunto: puedo verificar las aserciones de los 53 casos, pero no que el ensayo separado exija específicamente `54000`.

**NEXT ACTIONS**

Hacer independiente del calendario el caso temporal y conservar junto a la evidencia el bloque que exige `54000`. No identifico cambios necesarios en el SQL de la enmienda o su reversión.

**CONFIDENCE**

Alta en las conclusiones estáticas; limitada para acreditar las huellas y los resultados de ejecución reportados.
