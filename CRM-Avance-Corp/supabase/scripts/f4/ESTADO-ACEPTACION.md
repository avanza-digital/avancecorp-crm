# F4 — estado de aceptación

**08/09/2026: candidata técnica implementada, reconstruida y probada; G4 abierto.**
Falta identificar y contrastar la fuente de cálculo/registro de comisiones y
comisiones ya liquidadas. Se consultó a Miguel; no se inventó una regla ni un
registro de pagos. Las tablas de metas, cierres y ajustes de conversión fueron
trazadas y sus bases selladas comprobadas, pero no acreditan un abono de comisión.

Artefacto preparado/versionado: `20260907191832_crm_f4_inversiones_base_y_escritores.sql`.
48 funciones (18 adaptadas, 30 nuevas), 11 módulos y siete tablas nuevas.
Desarrollo en `codex/f4-cierre`, checkout `/private/tmp/avancecorp-f4-desarrollo`.
**Sin aplicación, publicación ni encendido productivos.**

## Matriz vigente

| Requisito | Resultado y evidencia |
|---|---|
| Avance→Qorilazo, Qorilazo→Prodelco y segunda inversión sin otro lead | PASS HTTP real: cooperativas, clave/contenido, depósito único y Storage privado; una fuente/inversión/principal. Ensayos originales y reconstrucción independiente. |
| Contratos Avance PEN/USD y paso Qorilazo→Avance | PASS: contrato, cuenta, cronograma, Auth/Portal y atribución del responsable. Respuestas perdidas y entradas simultáneas conservan una cuenta y fuente. |
| Permisos, baja, reasignación, sin responsable, lectores heredados | **19 grupos PASS**, [permisos](../evidencia-f4/permisos-dinamicos-6d36b142-c04a-4d80-a2e6-0d7027597c8c.json). Teléfono vivo sigue responsable actual, foto histórica permanece. Directorio solo agregados. Multirrol: 12 grupos, parejas de autoridad publicadas. |
| Cotitularidad neutral, corrección y fusión | **16 grupos PASS**, [cotitulares](../evidencia-f4/cotitulares-neutrales-ab46e469-e0f0-46ba-8ee6-4e0755f24ec0.json). Procedencia inmutable, duplicados documentales, identidad pendiente/ocupada/reutilizada, fusión y principal. Caso explícito: cotitular de equipo ajeno no obtiene lectura de contrato, inversión ni principal. |
| Corrección de solicitud preparada | **20 grupos PASS** en ambos bancos: revisión/hash/clave, replay, datos inválidos, autorización, Auth reservado y carreras confirmar/corregir/revisar. La confirmación versionada exige datos vistos; replay confirmado conserva resultado. |
| Corpus original F2 e históricos | **12 grupos PASS**, [corpus](../evidencia-f4/corpus-f2-d87a38ba-8e92-4a74-a0dd-e65aac22ed47.json): siembra y oráculo originales antes de F4, casos A/B/C/E, resueltos/faltantes/conflictivos, DNI/CE/pasaporte, mapa y capital intactos. Históricos: censo 7, lote 19, concurrencia 7, identidad 6, mantenimiento 8 y límite mixto 100. F2 global rechazado desde instalación. |
| Renovación, conversión, atribución, demos, anulaciones y fechas | **13 grupos PASS**, [finanzas](../evidencia-f4/finanzas-integral-dd43179a-8770-4d2e-8a5a-8ccffe75036b.json): peso 0.15, una operación elegible por cliente/mes, rango parcial, PEN/USD, anulación inicial Avance/cooperativa, stock conservado, cadena atribuida y ambas carreras sello/alta. Mes lejano abierto mantiene la regla comercial sin tocar sellos ni resultado de metas sellado. |
| Comisión y comisión ya liquidada | **PENDIENTE**: no se identificó fuente de pagos/regla de comisión. [Catálogo contrastado](../evidencia-f4/revision-integral-catalogo-2026-09-08.json) y evaluación explican por qué `ajustes_mes_cerrado` de conversión no demuestra liquidación. |
| Inventario de escritores/lectores | PASS: 546 funciones, 26 consumidores directos clasificados, 18 escritores financieros, 97 transitivos y 24 triggers. Guarda de instalación de 20 matches previos con huellas; nuevos consumidores/vistas provocan rollback comprobado por dos mutantes. SQL dinámico arbitrario no queda certificado por este inventario. |
| Recuperación de acceso y cambio de responsable | PASS Auth/API reales; dos ensayos de reserva de diez minutos reales completos. Regresión posterior al endurecimiento de Portal: alta/reintentos/concurrencia, cuatro vetos y entrypoint Deno PASS. Sin adoptar usuarios ajenos ni editar leases. |
| PDF real y bytes | **12 grupos / 10 contratos PASS**, [tanda completa](../evidencia-f4/pdf-real-56c6b388-fb71-4f40-8fdb-e3bf88535698.json): Deno, render/upload/download/firma, concurrencia, respuestas perdidas y lease real. Bordes anteriores: 10 grupos / 8 contratos, incluidos antecedentes sin job. |
| Recuperación después de WORKER_LIMIT | El ensayo `cb86e1fd` original sigue **FAIL tras nueve grupos**. Recuperados sus pendientes; [readback de diez trabajos](../evidencia-f4/pdf-recuperacion-cb86e1fd-b52a-4683-947e-3664d929ff46.json) PASS, mismo job/snapshot/fuente/objeto y bytes. No se modificaron renderer, CPU, reloj ni estado SQL. No se certifica rendimiento productivo. |
| Presentación documental | PASS inspección de 14 páginas PEN/USD; plantilla, textos, firma, fondo y fuentes intactos. Cotitularidad neutral no se imprimió. Cualquier texto/ubicación nuevos requieren aprobación previa de Miguel. |
| Compatibilidad con pantalla existente | PASS regresión: el parser admite `lead_id:null` explícito y fechas F4, conserva payload antiguo, rechaza ausencia/UUID inválido. La mini-ficha muestra fecha comercial y no afirma que la persona carece de Portal o genera otra conversión. No sustituye F5. |
| Reconstrucción y paridad | PASS banco Supabase independiente desde esquema sin datos; semilla Auth/RPC antes de aplicar; candidata íntegra. Cuatro contratos, dos cierres, 52 cuotas, PEN 8000 conservados. Instalaciones completas adicionales en copias pre-F4 para corpus y finanzas. |
| Reversa operativa/restauración | **6 grupos PASS**, [restauración](../evidencia-f4/restauracion-02a32c29-de01-4532-ab83-2f9d3dc719db.json): F4 OFF, 133 tablas + 27 archivos restaurados en DB/volumen nuevos, datos/cuerpos/ACL/RLS/bytes iguales. No es tercera pila HTTP ni restauración de cron/replicación. No hay DOWN destructivo que borre historia. |
| Revisión independiente | Claude **CHANGES_REQUESTED**; [evaluación Codex](../evidencia-f4/auditoria-cierre-integral-2026-09-08/evaluacion-codex.md) resuelve cada hallazgo con evidencia, acepta y corrige los confirmados. No hubo revisión adicional de Claude tras esos cambios. G4 no se declara aprobado por el revisor. |

## Gate de verificación

El manifiesto `../evidencia-f4/paquete-tecnico-2026-09-08.json` identifica hashes
del artefacto, módulos, worker, frontend y evidencia seleccionada.

- Cuatro gates backend (`check:scripts`, `seed:preflight`, `test:rls:preflight`,
  `test:edge-preflight`): PASS. Los preflight no sustituyen SQL/HTTP/RLS reales.
- Handler Portal: ocho tests nuevos de CORS, límite por bytes/stream, errores
  internos, errores contractuales y conservación del token. Integrados en preflight.
- Deno PDF: **43 pruebas PASS**; check y formato PASS. El test nuevo comprueba
  que el rechazo a borrar una inversión explica la conservación antes de Storage.
- Frontend: lint/typecheck, **3050 tests PASS con dos workers**, configuración
  de release, build, bundle y duplicados. Cuatro avisos de accesibilidad previos.
  La primera tanda con máxima concurrencia falló por timeouts; se conserva el
  hecho y no se cambiaron tests para conseguir la ejecución estable.
- Tipos DB: 17 nodos introspectados antes/después; se preservaron tipos de otras
  tareas ausentes del dump del 07/09. No se reemplazó el esquema frontend entero.
- Estructura: 48 cuerpos iguales a candidata, 30 funciones nuevas con permisos
  esperados, RLS/grants de siete tablas, auxiliar cotitular sin acceso API.
- **NOT RUN:** Playwright completo de UI F5 (no se implementó esa fase),
  aplicación/advisors/gates remotos productivos, comisiones pagadas. No se presentan
  como aprobados. El build local no constituye publicación.

## Criterio para cerrar G4

Localizar la fuente y regla de comisiones, contrastar inversiones adicionales,
renovaciones/anulaciones, fechas/atribución y una liquidación ya pagada; registrar
paridad o la corrección necesaria y su prueba. Si el requisito se considera ajeno
al producto actual, hace falta una decisión explícita del dueño para cambiar
el plan; no se elimina unilateralmente para dar F4 por terminada.

F3 productiva estaba ON y F4/F5 OFF en la observación previa. El censo productivo
de **14 resueltos + 1 faltante** es del 07/09 11:32 Lima, no un recenso actual.
La siguiente aplicación real requiere recenso, ciclo/gates del repositorio y
habilitación correspondiente. [Procedimiento de recuperación](RECONSTRUCCION-Y-RESTAURACION.md).
