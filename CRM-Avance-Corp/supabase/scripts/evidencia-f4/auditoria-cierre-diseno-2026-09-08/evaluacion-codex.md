# Evaluación del diseño por Codex PRIMARY

08/09/2026. Una consulta de arquitectura para el encargo de terminar F4;
Claude actuó sólo como SECONDARY_REVIEWER mediante `scripts/claude-review`.
Dictamen recibido: CHANGES_REQUESTED. No es aprobación de la implementación final.

Se incorporaron controles de versión de datos separados del responsable,
idempotencia de la corrección antes de comprobar una versión que ya avanzó,
conservación de las referencias originales del contrato y los datos Auth ya
reservados, ruta de comprobante inmutable, historial privado con auditoría
redactada y snapshot de la procedencia documental. La confirmación ya concluida
conserva su replay de lectura incluso si llega una versión antigua. La espera
por una identidad de cotitular deja un pendiente recuperable sin rehacer PDF.

Tres hipótesis del reviewer se descartaron por evidencia que faltaba en su
extracto: `04-avance.sql` contiene el trigger AFTER INSERT que ya crea la
inversión antes de reservar PDF; `private.inversion_persona_autorizada` empieza
con la capacidad comercial y valida ámbito/membresía; la puerta de eliminación
ya rechaza con 55000 contratos vinculados a inversiones antes de reservar el
borrado de Storage. Por ello la FK RESTRICT de procedencia conserva historia
sin romper un borrado financiero que F4 permitiera. No se amplió el borrado.

Ensayos independientes del dictamen: `probar-cotitulares-neutrales.mjs` y
`probar-correccion-solicitud.mjs`. La columna de clave de corrección se llamó
`id` para que el auditor existente registre `fila_id`; los datos y sus huellas
se redactan como `***` según el contrato del auditor. La revisión integral final,
reconstrucción y matriz financiera siguen pendientes de este checkpoint.
