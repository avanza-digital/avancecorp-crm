# F6 — evaluación independiente y decisiones

Codex PRIMARY, único escritor. Claude SECONDARY_REVIEWER mediante el wrapper
`scripts/claude-review`, sin herramientas, persistencia ni delegación. Riesgo
LEVEL 3. Dos consultas: arquitectura y revisión del cambio sustancial. Ambas
devolvieron **CHANGES_REQUESTED**; no se atribuye a Claude un PASS posterior.
Codex comprobó los hallazgos y verificó las correcciones. No hubo tercera consulta.

La segunda revisión recibió el SQL completo, el código crítico de integración,
el diff y CodeGraph. Algunos DTO, hooks y pruebas quedaron fuera del paquete del
revisor: la falta de esos archivos limita su afirmación de ausencia de pruebas.
Los prompts y dictámenes completos saneados permanecen en el respaldo privado.

## Cambios aceptados

| Hallazgo | Decisión y evidencia posterior |
|---|---|
| Ámbito F5/F6 diferente | Confirmado en la cola de supervisor sin responsable. F5 permite ver esa persona y F6 reserva la cola a Gerencia. `inversionista_ficha_fn` aplica `postventa_visible` antes de incluir historia/tareas/capacidad F6. `revision.test.mjs` comprueba ambos ámbitos y ausencia de filtración |
| Rechazo F6 revoca toda la ficha | El panel conserva su error local y no borra el borrador F4. La propia lectura F5 conserva su revalidación de permisos. E2E: un 42501 de postventa no cierra una ficha F5 autorizada |
| Transición de banderas bloquea F5/Agenda | La contención exclusivamente durante la lectura del modo F6 deshabilita esa sección y devuelve agenda neutral vacía. Prueba real con otra sesión sosteniendo la fila de bandera; F5 sigue abriendo. Las escrituras continúan rechazando el conflicto sin commit parcial |
| Serialización completa y agenda sin cota | Proyección explícita `postventa_tarea_json`, enlaces de perfiles de lectura y límite de 2.000 pendientes ordenados. Prueba con 2.001 tareas; alarma de tope del frontend. No existe fuga actual por grants: el catálogo demuestra SELECT concedido en las 29 columnas anteriores, contrario a la inferencia del review. La proyección previene ampliaciones accidentales futuras |
| Seguimiento por perfil pierde tareas neutrales | `postventa_perfil_ids` permite a `tareasDeCliente` incluir la agenda de la identidad canónica sin cambiar el sujeto físico ni fabricar perfiles. Pruebas de servidor, store y mezcla de ambas rutas |
| Veto sin explicación en lead | Nota enlazada al registro de postventa en cada lead afectado. La ficha unificada reconoce el enlace y muestra una sola gestión. Prueba de motivo visible en lead e historial sin duplicación |
| Lectura canónica de sincronización sin candado | Se añade `FOR SHARE NOWAIT`; no invierte el orden esperando mientras sostiene tareas/leads. Fusión, baja y carreras siguen pasando |
| Respuesta de reinversión distinta en replay | Devuelve `reinversion_origen_id` tanto al crear como al recuperar. La misma empresa/persona/origen continúan siendo inmutables |
| Cancelación con contacto siguiente por API | Rechazada antes de cambiar la tarea; prueba de estado pendiente y ausencia de recibo parcial |

## Recomendaciones no aplicadas y motivos

- **No absorber cualquier fallo de la agenda F6 o resolver un perfil por una ruta
  legada tras error de red.** Eso puede ocultar pendientes o crear una gestión bajo
  otro sujeto cuando F6 está encendida. Se degradó el caso concreto de transición
  en el servidor; autorización, red y contratos inválidos siguen siendo errores
  visibles. La resolución del perfil hace una lectura vigente al abrir, no decide
  una escritura por una bandera posiblemente obsoleta en caché. Pruebas MSW y del
  formulario cubren el fallo cerrado y el camino F6 encendido.
- **Confirmación silenciosa:** no reproducible. `persistirConDetalle` ya informa
  el rechazo mediante toast y resincroniza. Agenda es el único llamador productivo
  de `confirmarTarea`. El nuevo E2E fuerza un rechazo real del adaptador, observa
  el error y verifica que la tarea no aparezca confirmada. Añadir otro toast
  duplicaría el aviso.
- **Declarar STABLE el lector interno:** se mantiene VOLATILE para obtener el
  snapshot actualizado después del candado D-19. No usa bloqueos de filas y es
  compatible con GET/ICS de solo lectura, probado con sesión sin `auth.uid()`.
- **Exigir enlace virtual:** el contrato vigente permite una cita virtual sin
  enlace. Los CHECK existentes exigen ubicación presencial no vacía, HTTPS válido
  si hay enlace y coherencia entre campos. No se cambiaron esas reglas.
- **Recibo/solicitud de retiro concurrentes:** la persona está bloqueada antes de
  comprobar/crear la solicitud; el índice único es una segunda barrera. El INSERT
  de recibo con conflicto espera al competidor; si este aborta, puede insertar,
  no queda necesariamente sin fila como suponía el review.
- **Reinversión cruzada de empresas:** la reinversión enlaza una fuente de la
  misma empresa. Para Qorilazo→Prodelco se utiliza “Nueva inversión” sobre la misma
  persona. No se mueve capital entre empresas. F8 conserva ese recorrido.
- **Cierre y próxima acción cuando falta responsable:** deben confirmar juntos
  o rechazarse juntos. Se conserva la atomicidad, sin prometer un cierre parcial.
- **Auditoría del contexto efímero:** se conserva la regla del proyecto de auditar
  todas las tablas CRM nuevas; el contexto queda vacío al terminar cada comando.
- **Cancelar retiro en revisión:** la gestión puede registrar que el cliente
  desistió mientras estaba pendiente o en revisión; conserva historial y nunca
  revoca una resolución terminal ni realiza un pago.

Los triggers AFTER de tareas no reescriben tareas neutrales: el de SLA y el de
avance exigen `lead_id`; el restante audita. El test compara revisión y contador
devueltos con los persistidos después de reprogramar. La prueba de recuperación
tras rechazo en el segundo intento ya existía en `postventa-envios.test.ts`; el
revisor no recibió ese archivo. La protección de actor se valida además en SQL.

Los gates posteriores, sus cantidades y sus límites están en
[ACEPTACION.md](ACEPTACION.md). La revisión y estos ensayos no autorizan por sí
solos una instalación productiva, un piloto o una firma humana.

## Ensayo remoto y cierre productivo posterior

Una revisión independiente Codex de sólo lectura examinó las correctivas PT409,
journal y pruebas; su PASS pertenece a ese alcance y no es un tercer dictamen
Claude. Se añadió la consulta F4 de recuperación al perímetro protegido.
El cierre operativo conserva la observación de Auth y la matriz general FAIL;
[acta, pruebas y límites](PUBLICACION-2026-09-10.md).
