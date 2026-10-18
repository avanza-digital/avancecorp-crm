# Resolución de la revisión de la integración

Codex PRIMARY; Claude SECONDARY_REVIEWER, solo lectura mediante el wrapper del
repositorio. Una consulta, sin recursión. Dictamen recibido:
**CHANGES_REQUESTED / MEDIUM**. No se presenta como PASS del reviewer.

| Hallazgo | Decisión y evidencia final |
| --- | --- |
| P1: una identidad sin conversión ocultaba todas las conversiones | Aceptado. `filasMensualesJornada` consume responsables canónicos cuando la cobertura permite mostrarlos y une por id a capital/metas. Test con responsable sin meta y persona con meta sin conversión; también cobertura no disponible. El contrato RPC valida previamente el cuadre del total. |
| P2: meta aún cargando parecía inexistente | Aceptado. Estado «Meta por confirmar» antes de afirmar «Sin meta fijada». Test de pantalla. |
| P2: fallo de objetivos parecía ausencia de meta de conversión | Aceptado. Estado «Meta no disponible»; test de pantalla junto al estado de carga. |
| P2: posible cartera antigua al fallar el resumen | El hook existente `useResumenCarteraOperativo` ya retira el resumen al fallar. Se añadió además el guard explícito en la nueva vista y un test que inyecta error junto a data anterior; oculta entrevistas, potencial y leads por repartir. |
| P3: ordenar capitales parcialmente convertidos | Aceptado. Primero capitales comparables; los no comparables quedan después, con monedas separadas. |
| P3: tipo de cambio en vuelo | Se conserva la presentación de cantidades conocidas por moneda, con «sin convertir». No publica un total ni avance falsos. No se añade otra consulta de TC. |
| P3: etapa y citas pendientes | Confirmado en el dominio: `propuesta_enviada` se rotula «Entrevista realizada» en `lib/tipos.ts`. La consulta de Gestión Diaria cuenta reuniones pendientes con fecha de hoy en `citas_hoy`; el bloque de Citas usa todos los estados de su propia fecha prevista. No son cifras equivalentes. |
| P3: primeras gestiones en equipo vacío | Cero corresponde a una foto completa y vacía. Una fuente ausente continúa en `null`, cubierto por test. |
| P3: consultas no usadas | Aceptado. `conConsultaOperativa: false` evita ranking y agenda semanal en esta pantalla. El valor predeterminado mantiene las pantallas previas; sus pruebas pasan. |

Los supervisores tienen `verCitasEquipo` según el catálogo de roles existente;
se reutiliza el lector autorizado. No se modificó acceso, RLS ni contratos RPC.

La pérdida de la agenda semanal en la portada es parte de la dirección elegida.
Se mantienen los accesos a los módulos completos. La implementación anterior
queda en el código como referencia, sin afirmar que siga siendo la ruta activa.

Comprobaciones posteriores a las correcciones: **118 pruebas específicas PASS**,
lint, typecheck, build y verificación de bundle PASS. El gate productivo continúa
NOT RUN por configuración ausente; consultar `ADAPTACION-CRM.md` para el estado
de E2E local. No se solicitó otra revisión para obtener un dictamen favorable.
