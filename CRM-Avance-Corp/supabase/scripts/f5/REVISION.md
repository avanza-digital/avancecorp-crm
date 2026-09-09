# Evaluación de la revisión independiente F5

Codex implementó y verificó. Claude actuó solo como `SECONDARY_REVIEWER` mediante
el wrapper del repositorio. La primera consulta no entregó un dictamen válido;
la segunda revisó nueve archivos y funciones publicadas de contexto. Su dictamen
fue **CHANGES_REQUESTED**, no PASS. Se conserva [el resultado íntegro](evidencias/revision-claude.txt).
No se abrió una tercera consulta ni se pidió que aprobara sus propias propuestas.

| Hallazgo | Evaluación y resultado del PRIMARY |
|---|---|
| P1: locks de la validación F4 abortaban la ficha | Corregido: `55P03`/`40P01` desactivan la capacidad con explicación, conservando la ficha. Prueba HTTP con otro proceso reteniendo el lead: PASS. Se conserva la autoridad F4 para no duplicar sus reglas; sus locks siguen siendo breves y acotados. |
| P1: auditoría multiplicada por polling | Corregido: un evento por actor/persona/categoría en 60 segundos, serializado solo al registrar. Diez consultas agregan como máximo un evento. Índice adicional por persona. La segunda comprobación documental queda deduplicada. |
| P2: descarga cancelada dejaba el control ocupado | Corregido por identidad del AbortController. Prueba de descargar, abrir inversión, volver y descargar otra vez: PASS. |
| P2: cuentas remontadas cada 15 segundos | Se retiró `dataUpdatedAt` de la clave React; cada consulta bancaria conserva su propia validación vigente. Prueba de refetch sin otra carga: PASS. |
| P2: comparación sensible al orden JSONB | Comparación recursiva de claves normalizadas; preserva orden de cuotas. Pruebas de no-op y cambio real: PASS. No se intenta reproducir incorrectamente la serialización del hash PostgreSQL. |
| P2: borrador ilegible sin salida | Recuperación por referencia y descarte explícito del borrador local, sin cancelar solicitudes del servidor. Prueba de recuperar sin nueva alta: PASS. |
| P2: referencia perdida al revocar | Se conserva solo la referencia opaca en el aviso; se elimina contenido/token y caché de la persona. Prueba: PASS. No se diferencia inexistencia de fuera de ámbito. |
| P2: `es_demo` NULL / cambiar marcador externo | Hipótesis descartada por catálogo: `contratos.es_demo` y `cliente_id` son NOT NULL. El UUID demo externo es la exclusión económica vigente ATR-4; cambiarla o añadir otra fuente de verdad queda fuera de F5. Paridad por fuente/moneda: PASS. |
| P2: perfiles de staff en enlaces | Se limitan los perfiles que aportan datos personales a `rol='cliente'`; la autoridad del documento y la inversión sigue siendo neutral. |
| P2: Directorio y varios perfiles | La fusión publicada ya bloquea dos perfiles; además se limita su proyección al conjunto de clientes permitido al lector. No se relaja la fusión para construir un caso imposible por la puerta vigente. |
| P2: cotitularidad | Se aplica también capacidad documental vigente a su PII. El PDF v8 no imprime cotitulares; no se cambió su texto ni se concedió acceso a otras personas. |
| P2: historial/tareas de Directorio | Las policies publicadas sí permiten actividades de ficha y tareas de clientes Avance. Se documentó esa diferencia con los antecedentes de leads, que siguen excluidos. |
| P2: cobertura global y coste | El bloqueo global es requisito explícito del plan para impedir totales incompletos. Se conserva y prueba; se elevó fuera del predicado por fila el rol lector. Materializar una autorización/cobertura obsoleta no es una corrección segura. La medición con carga productiva corresponde al despliegue gradual. |
| P3: UUID/formato, fecha, monedas e integridad | Regex UUID corregida. Avance no tiene otra fecha de imputación en su fuente; cooperativas sí, y está probada. PEN es el contrato de escritura cooperativa F4. Se documenta el alcance distinto del SHA archivado y del SHA de transporte. |

La objeción sobre creación legacy no contemplaba `gestionarSolo`: el acceso
«Gestión Avance» conserva mantenimiento, sin abrir otra alta contractual desde
esa pantalla F5. Las puertas de conversión inicial mantienen los triggers F3/F4.
Revisión final del PRIMARY: sin P0/P1 pendiente dentro de F5; pruebas y límites
en [ACEPTACION.md](ACEPTACION.md). Un dictamen de IA no sustituye estos gates.
