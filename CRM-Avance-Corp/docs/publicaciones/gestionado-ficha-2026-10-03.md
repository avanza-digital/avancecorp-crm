# Gestionado en ficha y vistas de leads — 03/10/2026

**PUBLICADO Y VERIFICADO en https://crm.miavance.com/.**
Miguel autorizó «Sí, probar y publicar todo» y retomó la ejecución tras la pausa.
Pendiente administrativo: aprobación de la PR #181 para integrar a Main; GitHub
exige una aprobación y no permite automerge. No se modificó esa protección.

## Comportamiento

La ficha (cabecera y recorrido de etapas), tabla de Leads sin filtro, tarjeta,
búsqueda global y diálogo de cierre de tarea muestran la misma gestión vigente.
Pipeline y filtro conservan su regla: Nuevo activo, asignado y contacto no deshecho
desde la tenencia actual. No hay nueva etapa guardada ni acción manual «Gestionado».
Un fallo de lectura muestra «Gestión sin verificar» y no marca Nuevo como paso
actual. Registrar, deshacer o reasignar actualiza la clasificación al resincronizar.

## Publicación

- Build: `build-20261004T025651347Z` (03/10, aproximadamente 22:13 Lima).
- Fuente: `6b1c25382d9e`, limpia, rama `rescue/gestionado-ficha-20261003`.
- Artefacto: `crm-20261004T025652Z-6b1c25382d9e.zip`.
- SHA-256: `66cd65c4e061965bbbe18f8e2fb40d7415d521a1824bb8975dd5a9361131cc35`.
- Preflight rechazó el candidato inicial porque no contenía el vivo `3e248407`.
  Se asentó el parche sobre ese vivo, conservando la ficha Base para gestión F2,
  y se repitieron check y Docker. Preflight final PASS.
- Hostinger aceptó la subida; verificación HTTPS posterior: **98/98 archivos
  HTML/JS/CSS/version con HTTP 200 y SHA-256 idéntico al manifiesto**.
- UI productiva con sesión de analista: filtro Gestionado con 8 filas, ficha real
  con Gestionado en cabecera y `aria-current="step"`. Consulta de solo lectura;
  no se crearon actividades, clientes ni tareas para esta comprobación.

## Servidor

Migración `20261003225551_crm_gestion_vigente_lectura.sql` **aplicada mediante
merge_branch** desde el banco propio. Solo dos funciones nuevas, puerta crm y
núcleo private, INVOKER/STABLE, RLS, lote máximo de 100, sin historial ni datos
de contacto en la respuesta. Solo authenticated tiene EXECUTE.
El adaptador comprueba titular y tenencia a precisión de microsegundos.

Postflight productivo: cuerpos de ambas funciones idénticos al banco; ACL,
volatilidad, search_path vacío y catálogo anterior intactos. Comparación bajo
RLS y transacción de solo lectura: gerencia 175, supervisor 151 y vendedor
66 resultados visibles, seis lotes, **cero diferencias** frente al predicado
canónico. Directorio: no había actor productivo elegible; cubierto en el banco.

Branch propia `gestionado-ficha-20261003` (`lyhyvgpzwngmptpboupk`), retirada tras
la publicación. Su replay histórico se detuvo en agosto; se reconstruyó con
esquema, 423 migraciones previas y configuración productiva, sin clientes reales.
Se completaron Storage, control SLA, control de avisos y el hito de rentabilidad.
Potencial empezó apagado como exige su fixture. Se actualizaron dos expectativas
del gate B1 al rechazo B4 ya vigente (42501 antes del CHECK); sin alterar permisos.

## Evidencia

- Front integral final: **PASS, 354 archivos / 5.690 pruebas**, lint, tipos,
  cobertura, build y bundle, con Base para gestión F2 incluida.
- Docker final: **21/21 PASS** (ficha, Pipeline Gestionado, cartera y ficha Base).
- SQL: seis roles, 100 leads transaccionales con rollback, cinco contactos,
  notas, deshechos, tenencia, sin titular, fuera de ámbito y entradas inválidas;
  comparación con cartera_filtrada_fn PASS.
- HTTP con sesiones reales de seed: **22 escenarios PASS**.
- Gate general RLS hospedado: **2.823 aserciones PASS**. Bloque de llamadas desde
  celular no instalado: SALTADO explícitamente por el gate.
- Scripts y preflights: PASS. GitHub app-check, verify y preflight: PASS para
  los commits de implementación de la PR #181.
- Review final independiente mediante scripts/claude-review: PASS, confianza alta.
  Posteriormente dos agentes de solo lectura ayudaron con diagnóstico del banco
  y preparación de integración; el PRIMARY conservó todas las escrituras.
- Advisors productivos: 323 hallazgos de seguridad preexistentes, **cero nuevos**.
  En el banco, diferencias de rendimiento limitadas a índices todavía sin uso.
- Catálogo anterior idéntico tras publicar: 1.348 columnas, 870 funciones con
  cuerpos/dueños/ACL, 488 índices, 108 policies, 134 tablas, 349 triggers e
  historial de las 423 migraciones anteriores.
- Gate de analítica global: FAIL preexistente en producción y banco por
  private.gestion_diaria_cola_hechos sin declarar. Este cambio no toca esa función
  ni incorpora contadores. Gate de realidad general: NOT RUN sin credencial
  de servicio productiva; contraste específico y recorrido real sí verificados.

## Integración y recuperación

PR propia: https://github.com/avanza-digital/avancecorp-crm/pull/181.
Solo el parche de Gestionado y sus pruebas; la ficha Base F2 se integra por
https://github.com/avanza-digital/avancecorp-crm/pull/180. Ambas necesitan aprobación.
No se mezclaron ni descartaron cambios del taller compartido.

Respaldo anterior:
`crm-20261004T020814Z-3e2484073368.zip`, SHA-256
`05db6428ee46111283f1f58252e3f5fd6acb2c31254a9e7362144ae1ca9fe9aa`.
Backend aditivo: el frontend anterior sigue funcionando. Retirar funciones
requeriría otra migración, después de volver al frontend anterior.
No revertir datos, actividades ni auditorías.
