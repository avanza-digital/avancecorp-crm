# Formulario 3 — fase 3 integrada y validada, sin publicar

Fecha local: 14/10/2026. Continuación de **N8N-AVANCE-141026**. Codex PRIMARY; Miguel opera las pantallas. Estado: **objetivo del ensayo aislado validado**. La publicación corresponde a fase 4 y sigue pendiente.

Relacionado: [[Formulario 3 - plan de integración en CRM y activación (2026-10-14)]] · [[Formulario 3 - fase 1 validada sin publicar (2026-10-14)]] · [[Formulario 3 - fase 2 validada sin publicar (2026-10-14)]] · [[Canales de origen de leads CRM]] · [[Carga de leads desde hoja de Google]].

## Qué quedó demostrado

- Instalación de dos migraciones y del Edge real en la rama autorizada; 98 comprobaciones SQL PASS (contrato, permisos, regresión de ficha viva y cartera/paginación).
- 49 casos de Auth/HTTP/permisos/reparto y 6 adicionales de reconocimiento, reingreso y conversión. Usuarios reales de Auth, datos ficticios y sesiones reales.
- UI de cuatro roles en Chromium/Docker local. Primera corrida: tres aprobados y Directorio con timeout de espera; repetición de Directorio aprobada tras ampliar solo la espera del ensayo.
- Google Sheets → n8n → importador real → CRM: alta, repetición, movimiento de filas, duplicados, rechazo, fallo HTTP, recuperación y recibo perdido. Cinco leads únicos en la hoja de prueba y siete recibos de resultados históricos; no son siete altas.
- Aviso automático real a Miguel: ejecución n8n 44, modo error; segundo aviso de la misma hora suprimido en 46.
- Legacy y Formulario 3 mantuvieron origen FORMULARIO y responsable; cada conversión aportó divisor 1/numerador 1. Confirmar de nuevo no creó otra inversión.
- 25 pruebas unitarias n8n PASS. Las 44 huellas de producto combinadas de fases 1–2 permanecen iguales; se conserva la validación integral previa sin atribuirla a una ejecución nueva.

## Revisión de Claude y evidencia

Dos revisiones independientes con dictamen **CHANGES_REQUESTED**, sin P0/P1. Codex aplicó las mejoras justificadas y documentó la resolución: medición de numerador real, reproducción de ajustes, estado/historial n8n, semántica de recibos y límites de avisos. El dictamen original no se cambia a PASS.

El primer intento de conversión Legacy había registrado el reingreso antes de fallar por omitir la referencia del certificado en el fixture. Se corrigió ese dato y se repitió; por eso la evidencia final dice «ya anotado» para Legacy y «registrado» para Formulario 3. No se presenta como corrida limpia única. La consulta equivalente del numerador se reconstruyó al cierre; no se afirma conservar exactamente el comando original.

Evidencia detallada: [LEEME de fase 3](../../CRM-Avance-Corp/supabase/scripts/formulario3-fase3/LEEME.md), [resolución de Claude](../../CRM-Avance-Corp/supabase/scripts/formulario3-fase3/revision-resolucion.md) y [verificación final](../../CRM-Avance-Corp/supabase/scripts/formulario3-fase3/verificacion.json).

[Figma actualizado](https://www.figma.com/board/JB4jRdmLXZXS0hBhEHxRbV?node-id=2-34): fases 1–3 validadas; fase 4 pendiente del control de publicación.

## Producción y retiro del ensayo

La rama `bxkborlvpmuwttzjrjqn` fue eliminada; hoja ficticia y tablas temporales eliminadas, tres workflows de prueba archivados y archivos locales privados retirados. La eliminación individual de comprobantes fue protegida por FK; se retiró la rama completa sin relajar esa protección. Los IDs del generador son históricos, no reutilizables.

Se detectó una selección en pantalla de la credencial temporal en el flujo principal, siempre inactivo y con HTTP deshabilitado. Codex restauró exclusivamente la referencia original `YNRHr2PjhfLXnKff`; primera restauración `95f649de-8cdc-43af-ba89-5cd4a3d74840`. La captura inicial confirmó esa versión; el autosave posterior y su resolución se registran a continuación. No hubo carga ni publicación de producto. La campaña todavía no está instalada en la base productiva y los recibos productivos siguen en cero.

Miguel eliminó la entrada temporal `Ag61FRD4BJjGI4hZ` y el listado MCP confirmó su ausencia, conservando la original. Al comprobarlo se detectó un segundo autosave de UI que había vuelto a referenciar la temporal. Miguel confirmó el cierre de las pestañas; Codex repuso exclusivamente la original y verificó diff vacío y ajustes idénticos. Versión vigente `29940eb5-d36c-49c7-bf7f-686b66cc3f76`; principal inactivo, HTTP y envío apagados. Evidencia: `cierre-credencial.json` y `limpieza.json`. Limpieza de fase 3 completada, Figma actualizado.

## Condiciones antes de fase 4

El gate de realidad original sigue **FAIL**: lectura de sellos denegada a service_role y timeout PostgREST. Un complemento SQL de solo lectura obtuvo cero desviaciones de sellos y coincidencia entre cinco caminos de conversión (6,3 % = 57,05 / 905). Esto no convierte el gate original en PASS. Reparar o enmendar formalmente el verificador y decidir el criterio para 45 ventas de analistas inactivos y 273 clientes sin domicilio, divergencias preexistentes ajenas a esta campaña.

Antes de publicar: releer historial/credencial/ajustes del flujo principal con pestañas antiguas cerradas o recargadas, definir retención de errores, probar el aviso productivo y actualizar su nombre antiguo, verificar el release desde el commit requerido. No activar ni cargar la hoja real hasta completar esa fase.

Entrega al menos una vez: si se pierde un recibo después del alta, el reintento se registra como duplicado. Contar altas de campaña desde CRM, no sumando recibos importado. Los avisos agrupan por hora de reloj, sin exclusión atómica ni ventana móvil. Un cambio solo del parser exige revisar y retirar exclusivamente los recibos rechazados afectados antes de reprocesar. NOT RUN remoto: 5xx/timeout específico, respuesta error_temporal y Error Trigger causado por fallo del recibo; se probaron la recuperación y aviso automático mediante los fallos detallados arriba.
