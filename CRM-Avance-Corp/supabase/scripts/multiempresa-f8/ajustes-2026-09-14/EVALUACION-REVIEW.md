# Evaluación del PRIMARY — review de ajustes F8

Claude actuó como SECONDARY_REVIEWER mediante `scripts/claude-review`, con
código/diffs y pruebas saneadas, sin herramientas ni delegación. El primer
intento falló dentro del sandbox; el mismo wrapper se ejecutó con permiso y
entregó `CHANGES_REQUESTED`, sin P0/P1. No se buscó un dictamen favorable mediante
consultas repetidas. Codex evaluó el resultado y ejecutó los checks finales.

| Hallazgo | Decisión y evidencia final |
|---|---|
| P2: acciones nuevas de postventa con ficha desactualizada | Aceptado: `PostventaPersona.deshabilitado` bloquea agendar, responsable, veto y revisión de retiros. Nuevo E2E PASS con recuperación. Se conserva una gestión ya abierta: tiene su propia consulta F6 vigente y sus comandos revalidan autorización; desmontarla por una avería F5 perdería el borrador. No se borra `retiroElegido` por ese error transitorio. |
| P2: paridad ACL de la firma F3 sustituida | Verificado: comparación completa `aclexplode`, propietario, SECURITY DEFINER y configuración contra la firma anterior, para todos los roles. PASS; no hizo falta cambiar grants. El replay también conserva atributos/ACL de todas las otras funciones. |
| P2: fecha local/medianoche en el cierre inicial | Aceptado: el flujo inicial real deja de enviar `venceEn`; el servidor usa el día de Lima, plazo y tasa. La vista indica que es una previsualización. El hash usa el mismo `p_vence_en=NULL` en reintentos; prueba SQL inicial con NULL y reintento PASS. El test de conversión exige el objeto sin vencimiento. Demo conserva la fecha derivada local. |
| P2: accesibilidad de plazo y tasa | Aceptado: validador devuelve campo; `CondicionesCoopac` asocia `aria-invalid` y error con cada input, conserva ayuda de tasa y limpia el error al editar. Pruebas de cierre inicial y E2E adicional con `12,345` inválido PASS. |
| P2 hipótesis: vencido anterior oculta uno futuro | Verificada contra `cliente-ficha-modelo.ts:vencimientoDestacado`: la regla anterior elige primero el último vencido, luego el próximo futuro. Se conserva. Ensayo SQL ahora exige esa selección con una fuente vencida y otra futura. No inferir que otra inversión salda/renueva la anterior. |
| P3: corregir vencimiento después de confirmar | Documentado, fuera del alta solicitada. No se relaja la restricción: modificar sólo el vencimiento con plazo conocido debe fallar. Históricos NULL no cambian. Corrección de la solicitud antes de confirmar sí está implementada/probada. |
| P3: foco de enlaces deshabilitados | Aceptado: mantiene nodo `<a>`, rol link y tabIndex, retira href/target. Prueba de error conserva foco en WhatsApp, muestra aria-disabled y recupera. |
| P3: foco heredado al cambiar hash | Aceptado: el listener de hash reinicia `volverAInversiones`. |
| P3: texto de acción para Directorio | Aceptado: motivo no operable se muestra sólo si existe acción de inversión. |
| P3: límite superior arbitrario de tasa | No adoptado: el usuario definió porcentaje anual manual, no un techo. Se exige número positivo y hasta dos decimales; no reutilizar límites de rentabilidad Avance para COOPAC. |

El gap de reintento de una operación anterior se cubrió además con una prueba
que escribe usando la función vieja, sustituye por la nueva dentro de una
transacción y reintenta la llamada de 11 argumentos: mismo cierre y metadata NULL.

Gates finales: `npm run check` PASS (3.579 tests); 15 E2E F5/F6 PASS; SQL local
PASS. Los preflights sin entorno, banco Supabase/Auth HTTP y advisors constan
NOT RUN en el recibo. La sugerencia del reviewer de ejecutarlos antes de pedir
SQL no autoriza crear un banco de pago ni aplicar SQL sin aprobación. Siguen
siendo puertas obligatorias antes de merge/publicación, no un PASS implícito.

Riesgos residuales: rendimiento productivo/concurrencia por comprobar; lecturas
F5 aún hacen dos comprobaciones de ámbito; la compatibilidad de payload antiguo
se conserva sin fecha de retirada inventada. G7 permanece abierto.
