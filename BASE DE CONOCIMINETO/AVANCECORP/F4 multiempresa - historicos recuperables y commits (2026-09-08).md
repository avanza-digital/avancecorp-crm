---
tags: [crm, multiempresa, F4, historicos, retomar]
fecha: 2026-09-08
estado: construccion-local-G4-abierto
---

# F4 — históricos recuperables y punto de reanudación

Actualización: 08/09/2026, 00:09 Lima. Miguel pidió recuperar CARTERA tras el cierre de VS Code, continuar el desarrollo del plan y hacer commits mientras se avanza.

**F4 continúa; G4 sigue abierto.** La carpeta de desarrollo de esta continuación es `/private/tmp/avancecorp-f4-desarrollo`, rama `codex/f4-cierre`, basada en `52ec842`. La carpeta original tenía cambios simultáneos de otra tarea en frontend y configuración de colaboración: se creó este worktree para conservarlos separados. El banco ficticio sigue en `/private/tmp/avancecorp-f4-bank`. Los commits pertenecen a esa rama; no se ha integrado ni publicado en `avancecorp/main`.

## Bloque histórico

Se integraron el censo administrativo y el aplicador de lotes de 1–100 fuentes concretas, con mapa previo y huella, recenso bajo candados, acta inmutable por UPDATE/DELETE y rechazo diferido de actas incompletas. La auditoría enmascara mapa/resultado; los roles de la API no ejecutan estas funciones ni leen/escriben el acta. No se crean personas, no se copian importes a una fuente nueva y se conserva la atribución histórica, incluido un creador contractual desconocido.

Las tres funciones históricas están instaladas en el banco ficticio. Los 34 cuerpos anteriores se conservaron exactamente: total **37 funciones, 20 nuevas y cinco tablas nuevas**. El escritor local está apagado. No se aplicaron lotes permanentes al banco original; los ensayos transaccionales revierten sus fixtures y las carreras usan una copia SQL.

Pruebas del checkpoint: **7 grupos de censo, 19 grupos de lote y 7 de concurrencia**. Incluyen reserva real de eliminación, exclusión demo, auditoría enmascarada, aislamiento, mismo lote repetido, lotes distintos sobre la misma fuente, confirmación real detenida hasta el commit administrativo, fuente ocupada NOWAIT, deriva durante espera, fallo después de dos enlaces y desconexión real antes de COMMIT. La copia SQL no duplica Storage, cron ni replicación.

La revisión de Claude terminó con CHANGES_REQUESTED. La evaluación del PRIMARY conserva lo confirmado, refuta con evidencia las hipótesis incorrectas y deja abiertos inventario de escritores, lote máximo y aceptación integral. Fuentes: `CRM-Avance-Corp/supabase/scripts/evidencia-f4/auditoria-historicos-2026-09-08/` y `2026-09-08-continuacion-historicos.json`.

## Qué se guarda y cómo retomar

Se versionan los módulos SQL, generador, fixtures/oráculos, Edge de Portal, evidencia saneada y notas. **La migración final aún no se versiona ni se registra como aplicada:** sigue siendo un artefacto generado de construcción, no una migración aprobada. Se puede regenerar con el comando de `scripts/f4/README.md`. Las migraciones ya versionadas permanecen inmutables.

Abrir este worktree y leer `CRM-Avance-Corp/supabase/scripts/f4/ESTADO-ACEPTACION.md`. No ejecutar todos los oráculos económicos en paralelo; comparten banco y algunos encienden temporalmente su escritor. Las claves y fixtures privadas se leen únicamente del banco local y no están en los commits.

## Pendientes que siguen gobernando G4

1. Corpus F2 original y faltantes, inventario de escritores/lectores, carreras contra corrección/fusión y trabajos administrativos, lote máximo medido.
2. Titularidad neutral de cotitulares y su trazabilidad tras corrección/fusión. El PDF mantiene su contenido: antes de editar textos de cotitularidad, mostrar texto/ubicación y obtener aprobación de Miguel.
3. Permisos dinámicos, bajas/multirol y lectores legacy; corrección trazable de términos/datos de solicitudes preparadas.
4. Paridad completa de renovaciones ponderadas, atribución, demos, anulaciones iniciales/Avance, comisión liquidada y carrera con sello mensual.
5. Reconstrucción de la candidata completa, reversa/restauración integral y revisión adversaria del conjunto final.

La autorización vigente permite construir y ensayar localmente con datos sintéticos. No se realizó publicación, backfill real ni activación de F4/F5 en producción. El recenso productivo de 14 vínculos resueltos y un faltante sigue siendo la observación del 07/09 a las 11:32; no se presenta como un censo nuevo.

Relacionadas: [[RETOMAR-62 - identidad unificada ENCENDIDA, sigue F4 (2026-09-07)]], [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]], [[F4 multiempresa - PDF real, recuperacion y auditoria (2026-09-07)]], [[F4 multiempresa - objetivo de cierre y banco aislado (2026-09-07)]].

## Pausa solicitada por Miguel

El 08/09 Miguel pidió parar y seguir mañana. Se guarda el checkpoint local y se detiene el desarrollo después del commit. No hay publicación pendiente en ejecución. Retomar esta rama y esta matriz, sin repetir F2 ni interpretar las pruebas parciales como cierre de G4.

## Reanudación — 08/09/2026, 09:54 Lima

Miguel pidió continuar. Pasaron **seis carreras adicionales con las RPC reales de F3**: corrección de documento, fusión y reasignación, cada una antes y después del lote histórico. Si el cambio de identidad gana, el lote exige recenso; si el lote gana, la fusión exige una nueva previsualización. Se conserva una sola inversión y su titular principal, el dinero, los PDFs y la atribución histórica. Las funciones F3 no se modificaron.

Evidencia: `CRM-Avance-Corp/supabase/scripts/evidencia-f4/historicos-identidad-68cc610d-f23c-4c4e-928f-0facea7e6ba2.json`. Script: `scripts/f4/probar-historicos-identidad.mjs`. Se usó una copia SQL con rol/claims ficticios; el banco original quedó intacto. Continúa el inventario de mantenimiento F2 y la medición del lote máximo. G4 abierto.


## Mantenimiento y escala, continuación del 08/09

Se reprodujo un lote histórico que confirmaba mientras el mantenimiento F2 tenía
un mapa nuevo sin confirmar. La candidata ahora bloquea el conjunto del mapa con
SHARE NOWAIT; ocho cruces prueban INSERT/UPDATE/DELETE y las tablas relacionadas.
Las FK e índices existentes ya protegen las inserciones concurrentes de
inversión, identificadores y titulares. En el orden inverso, la inversión legado
espera y la unicidad rechaza el duplicado. No se amplió el bloqueo a todas esas
tablas ni se reejecutó F2 global.

Pasaron otra vez los 39 grupos de históricos/identidad. Se midieron 100 personas
distintas creadas por conversiones cooperativas SQL reales: 93.132 ms con enlace
previo y 112.545 ms reparando 100 enlaces. El privilegio temporal vuelve a off;
el dinero/PDF y el banco original permanecen iguales. Estas cifras no garantizan
producción ni representan 100 contratos Avance. La revisión secundaria y su
evaluación quedan en `supabase/scripts/evidencia-f4/auditoria-mantenimiento-2026-09-08/`.

El verificador exige igualdad módulo/candidata/base para los cuerpos SQL y
conserva las huellas de las 37 funciones. Sigue [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]]: corpus F2, titularidad
neutral, permisos, corrección de solicitudes, paridad financiera y reconstrucción
con reversa. G4 abierto; ningún despliegue ni bandera productiva cambiada.
