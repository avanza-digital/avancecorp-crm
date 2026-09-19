# Evaluación PRIMARY del review de conversión

19/09/2026. Codex es PRIMARY. Claude actuó como SECONDARY_REVIEWER mediante
`scripts/claude-review`; el dictamen adjunto es previo a estas correcciones.
Se usaron dos consultas: planificación e implementación. No se volvió a
consultar para obtener un dictamen favorable.

| Hallazgo | Decisión y evidencia |
|---|---|
| P1: cancelación inexistente/incompatible | Aceptado el problema. El catálogo no tenía una RPC de cancelación de inversiones. Nueva `cancelar_solicitud_inversion_fn` y acción en el formulario común. HTTP prepara PEN, cancela dos veces, prepara USD y confirma una sola conversión. Una cancelación contra una confirmada devuelve la confirmación; un Auth pendiente exige recuperación. |
| P2: lector con locks y pérdida del formulario | Corregido. Lectores generados desde los controles del escritor, sin locks de filas/documentos. HTTP mantiene persona y lead bloqueados en otra transacción y la lectura termina. Veto devuelve capacidad y motivo. Test UI verifica conservación del campo y archivo, bloqueo temporal y recuperación. |
| P2: UPDATE de reserva antigua podría saltar el corte | Hipótesis descartada para el escritor existente: `crm.reservar_conversion_lead(uuid,text,text,jsonb)` usa INSERT ON CONFLICT antes de Auth; el BEFORE INSERT se ejecuta también al renovar. La instalación bloquea la tabla y rechaza reservas abiertas activas/selladas. No se amplía un trigger de UPDATE a operaciones históricas sin evidencia de necesidad. |
| P2: bienvenida inaccesible tras perder la pestaña | Corregida la recuperación: el lead convertido abre su solicitud por consulta de servidor, sin volver a introducir documento ni depender del borrador. Test UI confirma recuperación y un solo intento de bienvenida; HTTP verifica la consulta sin persona/documento. La entrega incierta después de 23 h conserva revisión manual del proveedor, documentada como límite operativo. |
| P2: tasas CE/pasaporte | Se conserva la distinción requerida por las puertas actuales: `private.lead_tasa_bloquear` exige DNI de ocho dígitos; esos leads usan la aprobación por perfil dentro de `ContratoNuevo`. No se habilita una puerta DNI con otro tipo de documento. HTTP cubre ambas identidades; el oráculo SQL cubre las aprobaciones de primera inversión. Main actualizó los dos helpers de tasa y esas definiciones se conservaron. |
| P2: trigger rompe históricos/fusión | La UI sólo reabre descartados; el trigger se limita a una transición nueva hacia convertido. Actualizar un convertido no vuelve a exigir un origen histórico. Dos escenarios HTTP prueban fusión antes de confirmar y después, con persona canónica y una inversión inicial. No se crea una excepción general que habilite nuevas conversiones sin inversión. |
| P2: contraseña temporal en la bienvenida | Texto comprobado contra `crm-inversion-portal`: usa `claveTemporalDesdeDocumento` y obliga a cambiar contraseña. No se introduce una política de autenticación diferente de la ya usada por Cartera. El riesgo de esa política preexistente requiere un cambio independiente. |
| P3: actualización del token sin comprobar fila | Corregida: toma la identidad devuelta por la saga y exige `found`. La saga existente permite retomar un lease vencido después de validar ámbito; no se cambia esa política para exigir un token perdido. Los reintentos dentro del lease y pérdida de respuesta inicial se prueban con Auth real. |
| P3: Storage arroja conflictos de negocio | Corregido: los rechazos de estado/veto/lock devuelven false. `f4_comprobante_visible` es un lector independiente sin el contexto de escritura. El navegador pierde una respuesta de carga, reintenta y recupera los mismos bytes antes de confirmar. |
| P3: UUID y concurrencia | UUID de origen inválido devuelve 22023. Dos claves distintas simultáneas producen exactamente una solicitud y el segundo recibe P0409; no 23505. |
| P3: recuperar tras veto | La recuperación confirmada precede al veto de nuevas inversiones; el acceso desde el lead convertido usa el lector y no vuelve a reconocer identidad. |
| P3: identidad sin actividad explícita | La operación conserva los triggers de auditoría; no representa una conversión ni un hecho económico. Corregir identidad mantiene la puerta dedicada de Gerencia. |
| P3: cuerpo legacy inalcanzable | Se conserva el cuerpo de origen tras el rechazo para facilitar comparación exacta/reversa. Es una deuda de limpieza, no una ruta ejecutable. |

Se descartó la sugerencia de que el helper de Cartera de un argumento infiera
automáticamente un lead abierto. Eso ampliaría capacidades de otros consumidores
sin un origen explícito. Los escritores comunes usan el origen persistido de la
solicitud. Reinversión sigue exigiendo una fuente previa; no es conversión inicial.

Verificación posterior: oráculo SQL, 15 pruebas HTTP, replay/reversa con 33
permisos, `npm run check` integrado con Main (3.694 pruebas), fronteras de Edge
y navegador real escritorio/móvil. La regresión general y sus límites se registran
en `evidencia-final.json`. No se ejecutó SQL ni se envió correo en producción.
