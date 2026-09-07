# Regla general: avisos cuando corresponde atender la próxima acción

Estado: **APLICADO Y VERIFICADO EN PRODUCCIÓN** el 07/09/2026 a las 15:17 Lima, después de la confirmación de Miguel: «ok me gusta tu correcion hazla».

El reporte de Miguel es general. Antes del cambio, una oportunidad ya gestionada, con siguiente intento válido programado, seguía recibiendo «Contacta al cliente y registra el resultado» porque el núcleo exigía el primer contacto efectivo sin respetar la cobertura reconocida para seguimiento. El ajuste anterior de caché, publicado en `8a31692`, no resolvía esta regla comercial.

La consulta de producción fue exclusivamente de lectura. En el corte observado había 366 oportunidades en primera atención; 29 reunían gestión previa de ciclo/asignación y cobertura activa. El recuento identifica el patrón en la cartera, no una corrección particular de la ficha de la captura.

## Comportamiento vigente para todo el sistema

| Situación | Resultado operativo |
|---|---|
| Ya hubo un intento del analista asignado y existe compromiso comercial válido | Esperar a la próxima acción; quitar la insistencia de primera atención en ficha, cola y campana. |
| Llega la fecha y hora de la acción pendiente | Avisar que se revise esa actividad, aunque continúe el margen de seguimiento. |
| Se cancela la tarea o se completa sin dejar otra y no hubo respuesta | Volver a mostrar el contacto pendiente según el núcleo. |
| Se agendó sin realizar ninguna gestión inicial | Conservar el aviso de primera atención al llegar su plazo. |
| Datos incompletos, tarea administrativa, contexto ajeno, tercera reprogramación o techo agotado | Conservar los pendientes y las revisiones que correspondan. |
| Hay respuesta real del cliente | Conservar la resolución por el registro de contacto existente. |

La espera utiliza la cobertura ya calculada por el núcleo. No marca un contacto como conseguido ni cambia las fechas históricas de cumplimiento. Las tareas vencidas y las revisiones comerciales mantienen sus avisos independientes.

## SQL exacto y alcance

[Migración completa](../../supabase/migrations/20260907194756_crm_sla_primera_atencion_respeta_compromiso.sql).

Modifica únicamente la definición existente de `private.sla_operacion_leads`. Después de calcular el primer hito pendiente, añade esta condición:

```sql
if v_cobertura is true and h.asignacion_coherente is true
   and h.base->>'primera_gestion_en' is not null
   and h.base->>'asignacion_primera_gestion_en' is not null then
  v_primera:=null;
end if;
```

`v_primera` es la referencia interna del aviso operativo. Los hitos y plazos originales siguen en `estado.base` y en las lecturas v1. Al faltar esa insistencia, el mismo orden del núcleo elige la tarea que vence, la siguiente tarea o la revisión aplicable.

No hay nuevo núcleo, función auxiliar, cálculo frontend, columna ni tabla. No hay actualización de leads, actividades, tareas, etapas, políticas o hitos. Se mantienen firma, propietario, ACL, `STABLE`, `SECURITY INVOKER` y `search_path`. El frontend publicado ya consume estos avisos; no requiere otro despliegue de interfaz.

Guardia previa de función: MD5 `c0c7eb4b8e5b0c8a60eca3af3115ebe3`, verificada en producción. Guardia posterior comprobada en PostgreSQL 16 y 17: MD5 `d880268ef586322e0589586cb8cde30d`.

SHA-256 de la migración: `a0126d8089b07d743e58450145d4bb20b4e64da4c3cbf159f49a8b6428f29f89`.

## Pruebas y reversión

- [Antes del cambio](regresion-sin-cambio.json): cuatro escenarios fallan por el aviso indebido, incluido el mismo recorrido en cuatro roles (siete fallos/subcasos en nueve pruebas); sin errores de ejecución. El registro completo está en [regresion-sin-cambio.log](regresion-sin-cambio.log).
- [PostgreSQL 16](pruebas-pg16.json): 64 pruebas correctas.
- [PostgreSQL 17](pruebas-pg17.json): las mismas 64 pruebas correctas.
- [Reversión en PostgreSQL 17](reversion-pg17.json): nueve pruebas focalizadas correctas, incluida aplicación → reversión → reaplicación y rechazo de repetir cada cambio fuera de su versión esperada.

Se ejecutó el SQL real en bancos locales desechables. Los datos y la autoridad reducida son fixtures declarados; no equivalen a una prueba de escrituras con usuarios productivos. Las pruebas comprueban concordancia de ficha/cola/campana por rol, fronteras exactas de vencimiento y margen, cancelación, límites, permisos, lecturas v1 y conservación de los hechos.

[SQL de reversión](../../supabase/scripts/rollback-sla-primera-compromiso.sql), SHA-256 `e53e230471210c8ccab711dc706da8521596e75c904aae1b94acced8f533a0d3`. Solo admite la función corregida exacta y restaura la definición anterior. No revierte el ajuste de caché ni elimina historia.

## Aplicación y verificación productiva

Se aplicó exclusivamente el SQL aprobado desde el commit `9f7262c12d006f550656b50520cddf9c8e720e92`, previamente igual a Main y `avancecorp/main`. Supabase lo registró como `20260907201712`; se alineó a `20260907194756` actualizando solo `version`, tras exigir origen, nombre, SHA-256 exacto y destino libre. La lectura final confirma una única versión canónica y la fuente íntegra.

La función viva tiene MD5 `d880268ef586322e0589586cb8cde30d`. Firma, propietario, ACL, estabilidad y `search_path` son iguales. Las otras seis definiciones protegidas, el control activo/revisión 1 y la política de adopción permanecen intactos; el gate pasó. Advisors de seguridad: 210 antes y después, sin novedades.

Se compararon 1.271 filas al mismo instante SLA. En las 1.270 con hechos estables hubo exactamente 51 cambios previstos: 30 avisos vencidos de primera atención retirados y 21 acciones iniciales futuras sustituidas por la siguiente acción que correspondía. Se conservaron los demás avisos y los 11 casos con cobertura pero sin gestión inicial. Una oportunidad recibió una llamada y fue descartada entre las lecturas; se excluye de la atribución al cambio.

Las RPC se verificaron en transacciones de solo lectura bajo `authenticated` con identidades reales de analista, supervisor y gerencia: ficha sin aviso prematuro, tarea y contacto histórico intactos, ausencia de esa oportunidad en el filtro y conteos de filtro/campana iguales por ámbito. Chrome confirmó la ficha corregida, la próxima acción visible, el filtro paginado y la pantalla de pendientes actualizada. No se registraron gestiones de prueba. Los conteos varían con el trabajo diario.

[Evidencia productiva sin PII](produccion-verificacion.json). El frontend publicado consume el núcleo existente; no se construyó ni desplegó otra interfaz para esta corrección.
