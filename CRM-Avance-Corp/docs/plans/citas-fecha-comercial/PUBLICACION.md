# Publicación de Citas por fecha comercial — 17/10/2026

Miguel autorizó «publica» y el costo de la rama temporal US$0,01344/h.
Fuente integrada con el TC por venta ya publicado: `6f176603`; integración
`3c5a566f`. Producción todavía pendiente en esta etapa del acta.

## Gates de la fuente integrada

- PASS `npm run check`: 439 archivos / 7061 tests, lint, tipos, cobertura,
  build, bundle y duplicación. El código de aplicación no cambió después.
- Docker completo: 445 PASS / 1 FAIL / 26 omitidos. El único fallo esperaba
  el rótulo anterior «Fecha de conversión». Se actualizó a fecha comercial
  y registro; se esperó el menú de escritorio al cambiar el viewport para
  eliminar una carrera del test. Repetición final: **12 PASS, 0 FAIL**.
- PASS 89 aserciones Auth/PostgREST reales en rama, con siete cuentas
  ficticias: Gerencia, dos supervisores, dos vendedores, Coordinación e
  inactivo. Ambas RPC, septiembre/octubre, ámbito exacto, fechas exactas,
  fuente sin acreditar y anon denegado. Incluye la presentación de capital
  por corte activa; no reconvierte sus importes.
- PASS 34 pruebas de conciliación: doce respuestas HTTP atraviesan
  `cargarCitasGerencia` y el cálculo real; Gerencia concilia ambos meses.
  Se conservan las 22 pruebas de datos reales saneados y reglas combinadas.
- PASS SQL cloud: compatibilidad exacta anterior, permisos, cohorte,
  exclusiones y ambigüedad con hechos reales del núcleo. Las 16 variantes
  de configuración se prueban en Docker: cloud impide cambiar
  session_replication_role dentro de ese bloque de simulación.
- PASS compatibilidad TC + Citas en Docker; cuatro fixtures de capital se
  regeneraron desde las respuestas SQL combinadas.
- PASS seed:preflight, test:rls:preflight, check:scripts y gate:realidad.
  Realidad: diez supuestos medidos, cero errores y dos divergencias previas
  (ventas de bajas y domicilio legal), ajenas al cambio de fecha en Citas.

## Banco cloud y alcance del merge

Rama propia `citas-fecha-comercial-20261017` / `wtmbakkjaihlflpfoxkm`.
El bootstrap del historial antiguo falló. Se restauró el esquema productivo
sin filas, conservando owners, ACL, atributos y dependencias Auth/Storage.
Se excluyeron solo doce DEFAULT PRIVILEGES de supabase_admin en public,
que el servicio no permite reescribir. No afecta a esta migración: reemplaza
funciones existentes en private y no crea objetos persistentes ni en public
ni en crm. No usar este banco como evidencia de futuros objetos de public.

Base 501 migraciones; candidata 502. Una sola diferencia: SQL exacto
20261017043000, MD5 e851dd57616e27c67e845fc93b628703. La versión técnica
asignada por MCP se alineó con guardas de nombre, contenido y ausencia del
destino. Ninguna restauración o fixture pertenece al historial del merge.
Las 24 Edge coinciden con producción en slug, SHA256 y verify_jwt.

Advisors: sin nuevos problemas de objetos de base. Seguridad 390→391 por
el aviso de configuración Auth de contraseña filtrada de la rama temporal
([referencia](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection));
rendimiento 356→339 al usar los índices con las pruebas. No se alteró Auth.
Detalle en publicacion-servidor.json. La rama se elimina al terminar.

## Evaluación PRIMARY de la revisión de publicación

La revisión independiente pidió cambios; se evaluó con evidencia, sin buscar
otro dictamen favorable. Esta consulta cubrió la integración nueva con TC y
la restauración cloud posterior a la tarea local.

- El riesgo P1 de recertificar una huella de consulta_corte caducada ya está
  impedido por el EXCEPT ALL del censo completo: incluye declarada/huella_ok.
  Se alteró el cuerpo manteniendo todas las anclas en Docker y se reprodujo
  el rechazo POSTFLIGHT con rollback íntegro. No se edita la migración
  commiteada. Antes del merge se exige además el prosrc exacto de los cuatro
  lectores/núcleos y las tres declaraciones correctas del estado vivo.
- La ventana de gestion.conversiones sí es global: el cuerpo anterior
  usa -infinity hasta v_ahora+1µs. La fixture existente combina episodio
  histórico de agosto y acreditación de septiembre y rechaza ambigüedad
  en ambos lectores/roles. No existe la diferencia de ventana hipotética.
- k.fecha es el instante comercial del núcleo/corte, no el registro de
  carga. Se conserva el filtro en Lima y el esquema estricto previo de TC.
  Las fechas de venta nuevas son date y se prueban sin desplazamiento UTC.
- Se cerraron los huecos HTTP: fechas exactas en ambos arrays, lectura
  valorada activa, parseo por la frontera real y conciliación completa.
  Tanto v1 como v2 deniegan anon. Las altas son ficticias y la matriz
  focalizada no pretende repetir todas las operaciones de escritura del CRM.
- La marca cerrado conservaba el significado de cierre posterior a la cita
  independientemente de su estado; ahora compara día comercial. No se cambia
  ese significado ni se exige asistencia para marcar una recuperación.

## Orden autorizado

Main/remoto iguales y fuente limpia → artefacto/manifest verificados →
preflight vivo → merge de la única migración → conciliación productiva →
frontend Hostinger → HTTP/bytes y acceso básico → borrar rama temporal.
La versión anterior de pantalla es compatible con el SQL aditivo. El
artefacto anterior publicado se preserva como recuperación; no se revierte
la base ni se reescriben fechas o contratos.
