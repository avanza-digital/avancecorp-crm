# Control de Citas pendiente — huella de excepción

Estado: **detectado y documentado; no corregido en producción**. Hallazgo de la verificación ampliada posterior al despliegue de [[Plan de avisos por accion y rol - 2026-09-07]]. No impide las lecturas SLA verificadas, pero el control global no está aprobado.

`private.assert_analitica_leads_citas()` rechaza la excepción declarada de `private.metricas_reuniones_implementacion(date,date)`: `declarada=true`, `huella_ok=false`. Su cuerpo actual coincide exactamente con la migración de [[Citas de Gerencia - correcciones comerciales y bases 2026-09-07]] (`20260907194622_crm_citas_gerencia_bases_y_alcance.sql`, SHA-256 `615e9e8cb8dc63729899ca6e719755bbfdfcd9947583f8ad64164b7b86f42665`), ya publicada antes del cambio SLA. MD5 anterior `6e8935eae3cf1a4c049a93cb20e1f3bd`, actual `cec7ee9ec1c31ddd8fa17f1d42e88fc1`.

La entrega SLA solo sustituyó sus tres funciones y no tocó esta declaración ni el agregador de Citas. Los otros seis controles de vigencia, auditoría, F7 y SLA, y el cierre de reconstrucción, pasaron. No se actualizó una huella a ciegas, ni se eliminó la excepción, ni se debilitó el control.

Siguiente trabajo: revisar que la razón de la excepción siga siendo válida con la ampliación de Citas; preparar su ajuste mínimo, probar el rechazo antes y el control completo después, mostrar el SQL concreto conforme a [[Inicio]] y aplicarlo tras la confirmación correspondiente. El despliegue SLA no autoriza una modificación comercial nueva de Citas.

Evidencia: `CRM-Avance-Corp/PROPUESTA DE SLA PARA ETAPAS/avisos-accion-rol-20260907/produccion-verificacion.json`. El esquema integral local empleado en las pruebas SLA contenía la versión anterior del agregador de Citas; sus pruebas de SLA no acreditan paridad de todos los objetos ajenos con producción.
