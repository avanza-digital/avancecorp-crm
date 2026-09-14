# Evaluación del PRIMARY

Una consulta independiente completada mediante `scripts/claude-review`.
Dictamen: **CHANGES_REQUESTED**; no es aprobación ni cierre de G7. El primer
intento del wrapper terminó sin revisión en el aislamiento; el mismo pedido
saneado se completó al ejecutar el wrapper fuera de él. No se habilitaron
herramientas al reviewer ni se modificó producto en esta tarea.

| Punto de Claude | Decisión del PRIMARY y evidencia |
|---|---|
| P1 de rendimiento en ficha amplia | Aceptado como G7-R01, abierto. Supervisor/Gerencia exceden 20 s en la selección inicial del lector de personas. Requiere corrección y verificación antes de cerrar G7. |
| Listado amplio sin ensayo | Se ejecutó después del review, sin segunda consulta: ambos actores fallan con `57014` bajo límite local de 8 s. El resultado se añadió al recibo y al mismo hallazgo. |
| Fecha del adicional anterior a la conversión inicial | Se conserva como observación, sin declarar bug ni modificar el dato. La solicitud y la fuente coinciden en 11/09, mientras la primera conversión registrada es del 14/09. La intención comercial queda por contrastar con el solicitante. No se añade una nueva restricción temporal sin verificar el contrato de negocio. |
| Margen estrecho del analista | Se documentan las muestras y su límite. Se rechazan porcentajes de margen BD calculados con tiempo de pared de la API administrativa: incluyen red/herramienta. No hubo benchmark ni medición de concurrencia. |
| Alcance de las firmas | Se mantiene limitado a cinco tablas del caso. El corte final también conserva una reclamación y un evento de registro, igual que el corte inicial. No se afirma huella de toda la base, Storage o Auth. |
| Capital activo nulo de cooperativas | Comportamiento esperado, no defecto: `cartera_inversionistas_fn` e `inversionista_ficha_fn` solo producen `capital_activo` para Avance. La comparación usa `capital_registrado`. |

No se adopta la frase del review «en la UI fallará siempre». El fallo medido
es de los lectores SQL bajo los roles indicados; UI/Auth/HTTP no se ejecutaron.
El timeout de producto está demostrado, pero no una afirmación universal sobre
cualquier petición, caché o instante futuro.

La causa raíz sugerida (materialización de toda la cartera, búsquedas canónicas
correlacionadas y fuentes repetidas) permanece como hipótesis. La corrección
debe perfilarse y ensayarse sobre el núcleo compartido, preservando ámbitos,
fusiones e identidad y exclusión demo; no duplicar cálculos ni subir el límite
productivo para dar la prueba por aprobada.

G7 sigue abierto. Los datos de este caso concilian; no se da por completada la
matriz multirrol, las cuotas por empresa ni las firmas. Las observaciones del
solicitante siguen pendientes. UI, descarga/comprobante, Auth real, reintentos
y carreras económicas conservan NOT RUN.
