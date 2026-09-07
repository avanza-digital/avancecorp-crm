# Regla general: avisos cuando corresponde atender la próxima acción

Estado: **PREPARADO Y PROBADO. SQL PENDIENTE DE CONFIRMACIÓN; NO APLICADO EN PRODUCCIÓN**.

El reporte de Miguel es general. Una oportunidad ya gestionada, con siguiente intento válido programado, sigue recibiendo «Contacta al cliente y registra el resultado» porque el núcleo aún exige el primer contacto efectivo. El aviso ignora la cobertura que ya reconoce para seguimiento. El ajuste anterior de caché, publicado en `8a31692`, no resolvía esta regla comercial.

La consulta de producción fue exclusivamente de lectura. En el corte observado había 366 oportunidades en primera atención; 29 reunían gestión previa de ciclo/asignación y cobertura activa. El recuento identifica el patrón en la cartera, no una corrección particular de la ficha de la captura.

## Comportamiento propuesto para todo el sistema

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

## Paso pendiente

Presentar este SQL a Miguel y recibir confirmación conforme a la regla del vault. Después: revalidar la fuente viva, aplicar exclusivamente esta migración, comprobar los estados autorizados por rol y la concordancia de las tres superficies, y registrar su publicación. No ejecutar otras migraciones pendientes del repositorio.
