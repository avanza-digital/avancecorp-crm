# F4 — aceptación todavía abierta

**Checkpoint vigente — 08/09/2026, 00:09 Lima:** históricos instalados en el banco ficticio; **37 funciones, 20 nuevas, cinco tablas nuevas**. Pasaron 7 grupos de censo, 19 de lote y 7 de concurrencia sobre la instalación actual. G4 sigue abierto. La matriz anterior se conserva como antecedente; esta ampliación cubre el lote administrativo y su recuperación, pero no el corpus F2 original ni todos los escritores concurrentes.

Evidencia: `../evidencia-f4/2026-09-08-continuacion-historicos.json` y `../evidencia-f4/auditoria-historicos-2026-09-08/evaluacion-codex.md`. El desarrollo y sus commits continúan en `/private/tmp/avancecorp-f4-desarrollo` (`codex/f4-cierre`). La candidata SQL final es regenerable y permanece sin versionar; no está aplicada ni activada en producción.


Actualizado: 07/09/2026, 22:09 Lima, recuperación PDF ampliada. Entorno exclusivo: `avancecorp-f4-bank`.
Se construyó, instaló y probó parte del motor; quedan requisitos de cierre pendientes.

## Objetivo completo

Una persona identificada registra nuevas inversiones en Avance, Qorilazo y
Prodelco sin duplicar identidad, lead ni Portal, con fuentes, documentos,
titularidad, atribución y reglas comerciales correctas. El cierre exige todos
los recorridos, permisos, concurrencia, recuperación y paridad del plan.
Las pruebas parciales siguientes **no aprueban G4**.

## Lo construido

- Migración candidata `20260907191832_crm_f4_inversiones_base_y_escritores.sql`:
  preparación por clave/contenido y confirmación transaccional; documentos de
  cooperativas mediante Storage privado; fuentes y titular principal atómicos.
- Cierres externos iniciales separados de inversiones adicionales. Índice
  único solo para el cierre inicial y adaptación acotada de lectores/escritores.
- Avance usa la puerta publicada `crear_contrato_con_cuenta_pdf_v2`, con flujo
  libre y snapshot técnico; catálogo opcional. No se vuelve obligatorio.
- Fecha comercial de cooperativa e imputación posterior cuando su mes está
  sellado, sin copiar dinero a la tabla relacional ni reescribir el sello.
- Anulación/corrección externa sincroniza el estado/empresa de la inversión y
  deja eventos; conserva las reglas ATR-4 de Capital.
- Contrato vinculado no puede preparar borrado de sus archivos. Una fuente
  cuyo borrado ya está reservado tampoco puede recibir un vínculo nuevo.
- `crm.acceso_inversion_fn` vincula el alta del Portal con la solicitud de
  inversión. Reutiliza la saga Auth de F3: marca de servidor, token, versión y
  lease. El perfil toma el responsable de la persona aunque registre un superior.
- Edge `crm-inversion-portal` con actor verificado por Auth y pasos SQL con su
  JWT. No recibe documento, asesor ni perfil arbitrarios; no almacena el token
  en claro ni manda correos. Conserva la política de clave temporal del Portal.
- `crm.revisar_solicitud_inversion_fn` acepta al responsable vigente desde su
  ámbito actual y registra una revisión inmutable. Conserva datos, hash y saga.
  Alinea el asesor del perfil bajo una excepción de una sola columna ligada a
  la revisión de esa transacción; las escrituras directas siguen protegidas.
- La solicitud conserva la identidad de origen y su contenido. Después de una
  fusión canónica, autorización, nuevas fuentes, titulares y lectura de
  comprobantes usan la identidad vigente. Un resultado repetido informa esa
  identidad sin reescribir la respuesta histórica almacenada.
- El contexto Auth nuevo conserva además la persona donde se reclamó el acceso.
  Se recupera su claim original incluso con dos fusiones posteriores; sigue
  admitiéndose el contexto anterior que no tenía ese campo.
- Generación PDF real con la plantilla vigente intacta; recuperación que consulta
  el objeto antes de repetir su subida y verifica sus bytes antes de sellar.
- Storage tiene un límite de 20 segundos por operación, incluida la lectura del
  cuerpo, con cancelación independiente por petición. La versión incompatible
  no toma reserva o devuelve la que pudo identificar; no modifica el documento.
  El tamaño se valida antes de calcular su huella.
- Relectura de inversiones confirmadas separada de las condiciones para crear
  otra inversión. Conserva ámbito vigente; No insistir continúa bloqueando altas
  nuevas y solicitudes pendientes. El origen se comprueba tras bloquear la solicitud.

## Evidencia y límites por requisito

| Requisito del objetivo | Evidencia actual | Veredicto y trabajo restante |
|---|---|---|
| Avance→Qorilazo, Qorilazo→Prodelco, segunda cooperativa | `probar-cooperativas.mjs`, informe `cooperativas-*.json`: tres recorridos con JWT y Storage reales | Probado para esas personas/equipo del banco |
| Repetir Avance en PEN/USD | `probar-avance-existente.mjs`, informes `avance-existente-*.json` | Probado con perfil Avance existente |
| Qorilazo→Avance, Auth/Portal una sola vez | Cortes Auth, Deno HTTP, cinco momentos de reasignación, siete de documento y cinco de fusión Avance | Probado en esos recorridos, también con doble fusión y un contexto Auth anterior real |
| Empresa, monto, moneda, fechas, depósito, referencia y titular principal | Aserciones SQL + HTTP en cooperativas/Avance; comprobante descargado con los mismos bytes | Probado en las operaciones nuevas ensayadas |
| Cotitularidad y titularidad neutral completa | Contrato y snapshot conservan cotitular; inversión tiene principal; la plantilla v7 no lo imprime | **Parcial**: completar vínculo neutral y corrección/fusión sin ampliar permisos. Miguel exige aprobar previamente texto y ubicación de cualquier incorporación al PDF; contenido actual intacto |
| Contrato, cronograma, cuenta y PDF | Regresión de 12 grupos/10 contratos, más 10 grupos/8 contratos de bordes; 42 pruebas (31 handler + 11 Storage); revisión visual previa de 14 páginas | **Probado en los casos ensayados**: peticiones sin respuesta, subida tardía, incompatibilidad recibida y dos antecedentes sin job. Un archivo/sello por contrato; la plantilla conserva su contenido. Integración final y cotitularidad siguen en sus requisitos propios |
| Históricos correctamente vinculados | Referencia económica de cuatro contratos y dos cierres anteriores; fuentes conservadas | **Incompleto**: ejecutar el proceso canónico F2 con casos ya enlazados/faltantes/conflictivos y preparar tratamiento acotado del faltante productivo |
| Misma clave y contenido, conflicto sin efectos | Reintentos SQL y dos ejecuciones Auth solapadas; el segundo proceso no roba un lease vigente | Probado en casos ensayados, incluido Auth y relectura confirmada tras veto con permisos actuales; completar cambios de rol/baja e inventario de puertas heredadas |
| Depósito único simultáneo entre empresas/personas | `probar-concurrencia.mjs`: una fuente y una reclamación, perdedora preparada sin inversión | Probado con dos solicitudes realmente coincidentes en PostgreSQL |
| Roles/ámbitos y evidencia | Rechazos estáticos y veto; ámbito actual tras reasignación/fusión; comprobantes conservan ruta y bytes con permisos de la canónica; campos privilegiados siguen protegidos | **Parcial**: falta cambio de rol, multirrol, sin responsable y lectores heredados |
| Recuperar errores sin finales incompletos | Cortes Auth, lease real, veto, cambio de equipo, documento y fusión; cuatro carreras reales con confirmación, en ambos órdenes; bordes PDF y regresión satisfactorios | **Parcial**: resta corrección de términos/datos del payload e integración de todos los recorridos sobre la candidata final |
| Detener nuevas confirmaciones | Apagado observado esperando la confirmación en vuelo; luego nuevas solicitudes rechazadas | Probado en banco; falta paquete de reversa/restauración completo |
| Capital y conversión previa | Paridad antes/después: seis fuentes, S/8000, 52 cuotas; upgrade mismo mes no aporta, uno elegible posterior sí y el segundo del mes no | **Parcial**: añadir renovaciones ponderadas, atribución reasignada, anulaciones iniciales, demos y comisión con su fuente vigente |
| Fechas anteriores y meses sellados | `probar-fechas-anulacion.mjs`: agosto abierto conserva fecha; julio sellado imputa después; sello/fotos intactos | Probado secuencialmente; falta carrera entre sello y alta y conciliación completa de consumidores |
| Anulación comercial | Inversión adicional anulada conserva S/450 y su historia; cierre inicial y conversión previa intactos | **Parcial**: extender a anulación inicial/Avance/ajustes y comisión liquidada |
| Candidata íntegra, permisos y recuperación | 34 funciones, 17 nuevas y cuatro tablas; nueve oráculos de regresión tras corregir la relectura; auditoría de Claude evaluada con evidencia | **Parcial**: reconstrucción limpia final, reversa completa, revisión adversaria integral e inventario completo de consumidores |

## Hallazgos que determinan la siguiente acción

1. **Auth ya integrado y ensayado.** `05-acceso-portal.sql` y el nuevo edge usan
   `saga_auth_reclamar` / `saga_auth_avanzar` vigentes. El perfil se inserta en SQL
   y su avance de saga se confirma en la misma transacción. El oráculo provoca
   pérdida de respuestas de servicios reales; nunca fabrica sus estados.
2. **Reasignación implementada y ensayada.** La revisión conserva el contenido
   original y el contexto Auth; la atribución de la nueva inversión utiliza al
   responsable aceptado en esa revisión. Dos revisiones previas a confirmar
   siguen conservando la huella inicial. Después de confirmar, otra reasignación
   no cambia la atribución de la fuente. El perfil creado pero aún no enlazado
   se alinea sin modificar los demás campos ni el token/versión/lease de Auth.
   La excepción del trigger exige ejecutor `postgres` y una revisión protegida
   del actor en la transacción actual, identificada por `xid8`; un GUC solo
   no concede ese permiso. Se probaron escrituras directas y contexto reutilizado.
3. **Documento y fusión recuperables en los casos ensayados.** Las RPC de F3
   permanecen iguales al volcado: mientras Auth no esté enlazado, la corrección
   y la fusión se rechazan sin efectos. Se recupera ese acceso y luego Gerencia
   corrige/fusiona antes de confirmar la misma solicitud. La clave no se resetea
   automáticamente (decisión del 06/09). También se probaron operaciones ya
   confirmadas, dos fusiones, corrección seguida de fusión, claims anteriores y
   cuatro carreras observadas en PostgreSQL. Si la confirmación gana la carrera,
   su atribución y reserva documental se conservan; si gana el cambio de identidad,
   se recarga/revisa antes de confirmar. La fusión con dos leads/perfiles mantiene
   los bloqueos de F3 y su tratamiento previsto en F5.
4. Revisar los lectores externos y RLS que autorizan por vendedor histórico:
   sus agregados de atribución y el acceso actual a datos de persona son ámbitos
   diferentes. La prueba estática de otro equipo no demuestra una reasignación.
5. La candidata tiene una ampliación Auth aditiva y revisiones locales posteriores
   a la primera instalación. Ensayarla completa desde una base nueva al terminar;
   no publicar ni registrar la candidata parcial como migración aplicada.
6. Los bordes PDF señalados por Claude se corrigieron y ensayaron localmente.
   Cuatro cortes de transporte terminaron en 20,195–20,269 segundos y pudieron
   recuperarse por Deno. Ante la subida tardía, el worker vencido recibió 409,
   la colisión devolvió 503 en 370 ms y el tercer intento selló el mismo job con
   un solo archivo. Se probaron tres incompatibilidades de metadata recibida,
   sin cambiar versión ni snapshot en SQL. Los dos antecedentes
   `F4-BASE-INICIAL` y `F4-BASE-UPGRADE-MISMO-MES` devuelven `sin_reserva`, no
   reintentable, sin modificar contrato ni crear job. Esto conserva su régimen
   documental; no demuestra todavía su vinculación histórica neutral. La
   plantilla, renderer, firma, fondo y fuentes no cambiaron. Antes de incorporar
   cotitulares, presentar texto/ubicación y obtener aprobación de Miguel.
   El límite de Storage no es un límite global de Auth, SQL o render; comprobar
   tamaño antes de la huella tampoco evita por sí solo descargar un objeto
   privilegiadamente alterado. La reconstrucción integral sigue pendiente.

7. Se reprodujo y corrigió el hallazgo S1 de Claude: relectura tras veto de una
   operación confirmada, conservando controles para operaciones nuevas/pendientes
   y equipo ajeno. El revisor no recibió la versión SQL posterior. Sus hipótesis
   sobre índices ausentes y uso financiero de `es_primera_conversion` se refutaron
   con el banco. S8/S9 permanecen pendientes del bloque de validación/correcciones.

## Fuentes y ejecución

- `base-funciones.json`: 15 originales; `base-funciones-adicionales.json`: dos,
  preparación de borrado y protección de perfiles, comparadas con el volcado.
- `ultima-migracion.json`: inventario de las 34 funciones, incluidos nombres
  con dígitos. El parser y la comparación exigen cobertura exacta del inventario.
- `../evidencia-f4/`: informes sin claves ni documentos reales; snapshots de
  prueba completos permanecen en `/private/tmp/avancecorp-f4-bank`.
- `2026-09-07-advisors-local.json`: seis advertencias sobre objetos previos
  de `public` (políticas múltiples y `pg_net`). No sustituye la revisión de las
  nuevas tablas CRM, cuyos grants/RLS se comprobaron por separado.
- `2026-09-07-advisors-portal-local.json`: resultado idéntico después del módulo
  Auth. No se interpreta como auditoría completa de G4.
- `2026-09-07-advisors-revision-local.json` y `2026-09-07-advisors-fusion-local.json`:
  mismas seis advertencias anteriores, sin nuevas en esos diagnósticos.
- `portal-nuevo-*.json`, `portal-lease-*.json`, `portal-edge-*.json` y
  `portal-veto-*.json`: recuperación Auth, lease real, Deno HTTP y veto dinámico.
- `revision-responsable-*.json` y `revision-controles-*.json`: cinco cortes,
  dos revisiones previas a confirmar, bloqueo real de ficha, historial inmutable,
  contexto no reutilizable y atribución conservada.
- `revision-lease-*.json`: cambio de equipo y recuperación sin token del anterior,
  después del plazo original real, con un solo Auth/perfil/contrato.
- `documento-*.json`: siete momentos de corrección, incluida DNI→CE, con historia,
  credencial inicial y atribución conservadas; corrección publicada sin cambios.
- `fusion-*.json`: cinco recorridos Avance y tres cooperativos; fuente/titular en
  la canónica, solicitud original, comprobante conservado y ámbito actual.
- `identidad-controles-*.json`: cuatro carreras reales, documento seguido de fusión
  y compatibilidad con un contexto Auth anterior realmente existente en el banco.
- `2026-09-07-continuacion-documento-fusion.json`: candidata y evidencias enlazadas
  por SHA-256. Las regresiones de Portal, revisión y cooperativas pasaron después
  de esta ampliación. Conserva expresamente los requisitos de G4 aún pendientes.
- `2026-09-07-continuacion-pdf-auditoria.json`: checkpoint anterior, SHA de
  candidata/worker, pruebas PDF, reintento confirmado y regresiones.
- `2026-09-07-continuacion-pdf-bordes.json`: checkpoint vigente, fuentes archivadas,
  42 pruebas, 10 grupos de bordes y regresión de 12 grupos sobre la candidata
  actual de 34 funciones. No hubo otra revisión de Claude de esta versión.
- `auditoria-claude-2026-09-07/evaluacion-codex.md`: informe original y decisión
  sobre cada hallazgo; entradas de la candidata anterior conservadas.
- La captura estructural antigua se sobrescribió por su nombre fijo; el checkpoint
  de documento/fusión explica la sustitución por una comprobación posterior y
  conserva la huella original. Las nuevas capturas no sobrescriben las anteriores.
- `README.md`: comandos y orden. Los oráculos que escriben se ejecutan uno
  después de otro; las cifras crecen al repetir recorridos ficticios.

No hubo publicación ni cambio de bandera en producción. El recenso productivo
de 14 enlaces resueltos y un faltante sigue siendo la observación de las 11:32
del 07/09; se deberá revalidar antes del tratamiento de datos real.

Al cerrar esta tanda el escritor local queda apagado y `functions serve` fue
detenido. El banco conserva los datos ficticios; los informes no afirman que
todas sus solicitudes preparadas o todos sus jobs PDF estén terminados.

## Ampliación de históricos — 08/09/2026, 09:54 Lima

**PASS:** seis carreras con corrección, fusión y reasignación mediante las RPC
reales de F3, ambas precedencias, sin duplicación ni alteración financiera/PDF.
Evidencia: `../evidencia-f4/historicos-identidad-68cc610d-f23c-4c4e-928f-0facea7e6ba2.json`.
Siguen pendientes el mantenimiento F2, el lote máximo, la reconstrucción y demás
requisitos de G4; la ampliación no cierra la fase.
