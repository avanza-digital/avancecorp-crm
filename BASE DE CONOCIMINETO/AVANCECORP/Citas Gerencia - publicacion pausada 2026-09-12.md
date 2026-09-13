---
fecha: 2026-09-12
estado: pausado-por-miguel-sin-publicar
tags: [crm, citas, gerencia, publicacion, retomar]
---

# Citas Gerencia — preparación de publicación pausada

Miguel autorizó cerrar las validaciones, los cuatro bloqueos del control de métricas y preparar commit/artefacto. Después pidió **«pausa el trabajo porfa»**. Se detuvo el desarrollo. **No hay commit ni artefacto de esta entrega y no se aplicó SQL ni se publicó frontend en producción.**

Continúa [[Citas Gerencia - conexiones corregidas en local 2026-09-12]]. Las nuevas metas, ticket y proyección siguen fuera de esta reparación y pendientes de decisiones de negocio.

## Estado guardado

- Rama Supabase exclusiva `citas-validacion-20260912`, ID `07531654-e80e-47ef-ac36-02ce61d93d41`, proyecto `xhgsjtzpmwlqfkninphl`, padre `dctqcbznekcyxhjujuci`. Creada el 12/09 a las 17:47:21 UTC, coste informado US$0,01344/h. Se solicitó su pausa al detener el trabajo; consultar el estado actual antes de reanudar. Conservar las ramas ajenas `banco-f7` y `leads-recibidos-20260912-codex`.
- El replay automático se detuvo en 86 migraciones. Se restauró en la rama vacía el esquema actual `public,crm,private`, el historial de 275 migraciones y metadatos de configuración. Sin usuarios ni datos de clientes de producción. Cron del banco desactivado.
- Captura: 623 funciones idénticas, 828 restricciones; tres CHECK cambian sólo la asociación de paréntesis AND. Columnas, índices, triggers, RLS, vistas y permisos de tabla/columna coinciden. **La paridad completa todavía no pasa:** el montaje concedió CREATE temporal a `crm_metricas_bridge` sobre `crm/private` y falta retirarlo; el padre sólo concede USAGE. No declarar paridad PASS hasta repetir la comprobación.
- Se aplicaron **sólo en esa rama**, transaccionalmente, las candidatas `20260912151320_crm_citas_consulta_nucleos.sql` y `20260912181045_crm_analitica_auxiliares_verificados.sql`. Sin entradas nuevas de historial; se ensayan antes de registrar la migración definitiva.
- El gate en la rama devuelve **34 candidatos declarados, 30 sujetos al techo 30, cuatro auxiliares verificados**. El censo completo permanece intacto. Los diez mutantes clásicos fueron rechazados y se revirtieron.
- El nuevo test `test-analitica-auxiliares.sql` es **INCOMPLETO/FAIL del ensayo**: las primeras alteraciones del primer auxiliar fueron rechazadas, pero el caso DELETE de declaración encontró el trigger existente `trg_analitica_lc_exenciones_no_borrar` antes de llamar al gate. Debe probarse esa protección como rechazo directo, conservando el trigger, y continuar los casos restantes. Toda la transacción de prueba se revirtió. No es un fallo demostrado del producto.

## Corrección del control de métricas

Las cuatro alertas adicionales son falsos positivos del detector sintáctico respecto a leads/citas: historial de solicitudes usa el nombre del lead, conciliación histórica cuenta titulares/entradas JSON y bloquea referencias, y multiempresa usa leads para el veto de contacto mientras obtiene conversión del núcleo. Se preserva su runtime.

La nueva candidata clasifica exclusivamente esas cuatro firmas con definición completa, propietario y ACL efectivos exactos. El gate verifica el helper, sus permisos, la lista exacta y todas las declaraciones/huellas, y descuenta sólo esos cuatro auxiliares del techo. **Es una recalibración explícita del significado del techo, no una reducción de los 34 candidatos ni una auditoría completa de los otros 30.**

Además, dos declaraciones habían caducado: `crm.cierres_externos_fn(date)` y `private.metricas_conversiones_implementacion(date,date,text)`. Sus cuerpos coinciden exactamente con la migración F4 publicada `20260908211349_crm_f4_publicacion_compatible_rentabilidad.sql`. Los diffs contra sus versiones declaradas están guardados y revisados: fecha de imputación, relación canónica para teléfono, cierre independiente de lead y cierre inicial como rastro. La candidata actualiza sus declaraciones sin cambiar funciones ni cifras.

Claude no completó dos intentos del wrapper. El revisor independiente de sólo lectura `auditor_rls` emitió CHANGES_REQUESTED sobre la arquitectura; recomendó mantener el inventario completo y fijar propietario/ACL además de la definición. Requisitos incorporados a la candidata; falta revisión de implementación tras las pruebas. No hubo PASS independiente.

## Retoma exacta

1. Reanudar sólo el banco propio, verificar configuración y retirar los dos CREATE temporales del montaje. Corregir el caso del test de borrado según la protección real y completar mutantes; no desactivar guardas para obtener verde.
2. Completar rollback de ambas candidatas, paridad con el padre y comparación antes/después en el esquema completo. Para restaurar las declaraciones tener en cuenta el trigger anti-DELETE.
3. Sembrar datos ficticios, ejecutar matriz RLS/Auth/PostgREST antes/después y casos Citas/conversión/volumen. Ejecutar advisors. **Todavía NOT RUN.** Los guiones SQL locales antiguos tienen guardas de base local y algunos dobles de esquema; no ejecutarlos directamente en la rama ni presentarlos como pruebas de infraestructura real.
4. Revisar la implementación y cerrar evidencia. Ejecutar frontend y E2E sobre el commit aislado de esta entrega; el árbol principal incluye borradores de Superadmin y otro trabajo de leads diarios que deben conservarse.
5. Actualizar ledger, guardar únicamente esta entrega, integrar `avancecorp/main`, verificar igualdad y construir artefacto limpio. Publicación/instalación productiva siguen pendientes; no considerar que la preparación ya las hizo.

Evidencia versionable: `UX-UI-GERENCIA/citas-publicacion-2026-09-12/`. Banco y logs privados: `/private/tmp/citas-publicacion-20260912/`. Allí `banco.py` verifica el destino, usa credenciales en archivo 0600 sin imprimirlas y envía cada lote como un mensaje mediante psql `gexec`; no copiar `branch-access.json` a Git. `restaurar.py` es sólo para un banco totalmente vacío y rechaza bancos con usuarios/datos: no reejecutarlo a ciegas sobre la rama existente.

Problemas de montaje ya resueltos: políticas Storage capturadas con nombres no cualificados necesitaron `search_path=public,extensions` al reconstruirse; el primer intento revirtió todo. `--keep-comments` preserva las definiciones exactas. Las credenciales originales, datos, banderas y esquemas de producción no se modificaron.
