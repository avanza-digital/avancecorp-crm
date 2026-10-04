# Gestionado en ficha y vistas de leads — 03/10/2026

**Preparado; publicación pendiente del gate general del servidor.**
Miguel autorizó «Sí, probar y publicar todo» y retomó la ejecución tras la pausa.

## Comportamiento

La ficha (cabecera y recorrido de etapas), tabla de Leads sin filtro, tarjeta,
búsqueda global y diálogo de cierre de tarea muestran la misma gestión vigente.
Pipeline y filtro conservan su regla: Nuevo activo, asignado y contacto no deshecho
desde la tenencia actual. No hay nueva etapa guardada ni acción manual «Gestionado».
Un fallo de lectura muestra «Gestión sin verificar» y no marca Nuevo como paso
actual. Registrar, deshacer o reasignar actualiza la clasificación al resincronizar.

## Servidor

Migración `20261003225551_crm_gestion_vigente_lectura.sql`: dos funciones nuevas,
puerta crm y núcleo private, INVOKER/STABLE, RLS, lote máximo de 100, sin historial
ni datos de contacto en la respuesta. Solo authenticated tiene EXECUTE.
El adaptador verifica titular y tenencia a precisión de microsegundos.

Branch propia `gestionado-ficha-20261003` (`lyhyvgpzwngmptpboupk`), creada para
este trabajo. El replay histórico se detuvo en agosto; se reconstruyó desde el
esquema productivo, 423 migraciones y configuración, sin copiar clientes reales.
El primer gate general se detuvo por falta de buckets. Se completaron los cinco
buckets vacíos y policies originales; se reiniciaron exclusivamente datos de
prueba y se retiró el permiso temporal de seed antes de repetir.

## Evidencia

- Front integral: PASS, 351 archivos / 5.652 pruebas, lint, tipos, build y bundle.
- Docker focalizado: 19/19 PASS; repetir tras el último ajuste ISO antes de publicar.
- SQL: seis roles, 100 leads transaccionales con rollback, cinco contactos,
  notas, deshechos, tenencia, sin titular, fuera de ámbito, inactivos y posteriores;
  comparación con cartera_filtrada_fn PASS. Añadida matriz pequeña y ACL privada.
- HTTP con sesiones reales de seed: 21 escenarios PASS, ampliado a 22 con matriz.
- Review final independiente mediante scripts/claude-review: PASS, confianza alta,
  sin cambios obligatorios. Aplicadas recomendaciones sobre fecha ISO y pruebas.
- Advisors: cero alertas nuevas de seguridad. Rendimiento: solo índices todavía
  sin uso en el banco; índices existentes de actividades cubren lead_id/creado_en.
- Esquema: 1.348 columnas, 488 índices, 108 policies, 134 tablas, 349 triggers e
  historial previo idénticos. Dueños/ACL de 870 funciones iguales; dos cuerpos
  difirieron solo por comentarios quitados por el dump, restaurados desde producción.
- Gate de analítica global: FAIL preexistente tanto en producción como en banco,
  por private.gestion_diaria_cola_hechos sin declarar. Este cambio no toca esa
  función, no añade contadores y no modifica sus exenciones.
- Gate de realidad general: NOT RUN sin credencial de servicio productiva;
  pendiente contraste productivo de la consulta y recorrido real tras publicar.

## Recuperación

Antes de publicar, conservar ZIP/manifiesto vivo
`crm-20261003T221027Z-c489d48739ac`, SHA-256
`5843be8b58aa2fd38973af3c85ccecc1b5b9bea82f9da0ab94af03cf2cb1a363`.
Backend aditivo: frontend anterior sigue funcionando. La retirada de funciones,
si se decide, se hace en otra migración después de volver al frontend anterior.
No revertir datos, actividades ni auditorías.
