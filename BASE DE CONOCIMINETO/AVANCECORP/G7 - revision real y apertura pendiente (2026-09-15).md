---
tags: [crm, multiempresa, f8, g7, conciliacion, retomar]
fecha: 2026-09-15
estado: revision-real-y-ensayos-locales-g7-abierto
---

# G7: revisión real y preparación de apertura

**Actualización 15/09, 21:08 Lima:** la apertura operativa fue autorizada después
por Miguel y está ejecutada/verificada en [[F9 - apertura general autorizada (2026-09-15)]].
F4/F5/F6 ON para el equipo, F8 OFF y F7 OFF. El contenido siguiente conserva los
cortes y pendientes históricos de esta preparación; no revoca la apertura ni
atribuye firmas financieras que no existen. G8 sigue en observación.

Continúa [[Ficha rapida - publicada y verificada (2026-09-15)]] y el
[[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].
Miguel pidió abrir Multiempresa a los 18 analistas y autorizó revisar la evidencia.
La mejora de velocidad sigue terminada; este trabajo prepara el siguiente paso.

Corte 15/09, 15:07 Lima, comprobado de nuevo a las 15:16: **613 inversiones reales,
467 personas canónicas**, cero diferencias internas entre Cartera, Capital y F7.
Se comprobaron 19 fichas con sus 25 inversiones, desde una muestra de 20 fuentes
reales (10 Avance/5 Prodelco/5 Qorilazo). Datos marcados como verificados en la BD;
no autenticación física de documentos ni conformidad financiera.

Las 24 cuentas de equipo están vigentes: 18 analistas, 3 supervisores, 2 Gerencia
y 1 coordinador. F5/F6 siguen habilitados solo para los cuatro nominales.
Dos personas sin responsable son legibles por Gerencia y no admiten otra inversión
hasta asignación. Agosto conserva las 16 filas y sus huellas. Datos y banderas
productivas no se modificaron. Se usaron SQL/roles y ROLLBACK, no sesiones humanas.

Solo hay una persona multiempresa, Prodelco → Qorilazo, y una confirmación F4 del
piloto. Diez altas Avance posteriores fueron creadas por otros analistas. No hay
cotitularidad, retiros ni anulaciones reales que completen los casos. Las nueve
renovaciones históricas sin desglose siguen documentadas; las tres completas
coinciden con las seis filas del núcleo. No se inventan importes ni se calculan
comisiones.

**G7 abierto; método de evidencia aprobado.** Tras explicar la propuesta, Miguel
respondió «sii claro hazlo» el 15/09: acepta usar las veinte inversiones reales
existentes y completar los recorridos/casos faltantes con datos ficticios en una
copia aislada, sin esperar nuevas ventas. No es firma financiera ni autorización
del SQL de activación; las pruebas y su revisión deben terminar primero.

**Ensayos técnicos completados el 15/09:** diez reintentos, cinco carreras
económicas y veintiún contextos de permisos del modo general PASS. Coordinación,
cuentas inactivas y Directorio conservan sus límites. Cinco controles de
transición/reversa PASS; estado visible íntegro tras COMMIT y dieciséis
superficies conservadas. Copia local propia `g7_cierre_20260915`, sin coste remoto,
con 65 definiciones seleccionadas iguales a producción. La copia fuente no se
modificó; piloto/miembros de la copia de ensayo quedan OFF.

**Complemento aprobado terminado:** 15 grupos HTTP con sesiones Auth/REST/Storage
locales reales y 3 financieros SQL PASS. Incluyen las seis rutas, cuatro pérdidas
de respuesta Auth recuperadas sin duplicados, identidad provisional, cotitular,
retiro, anulación, upgrade reasignado y sello no vacío conservado. La matriz
ampliada comprueba todos los contextos del banco acumulado (56 al corte final,
no casos independientes). Se rechaza la reanudación por usuarios ajenos y se
comprueban todas las páginas de Directorio. El cotejo ampliado cubre 203 funciones,
tres auxiliares y columnas/restricciones de tres tablas, con captura productiva
fechada y hashes de evidencia; no es paridad total del esquema.
Refresco de producción a las 18:32 Lima: 614 inversiones y 468 personas, cero
diferencias; una alta Avance adicional normal, banderas y sello intactos.
Soporte, procedimiento productivo exacto y conformidades siguen pendientes.
El ensayo local de transición no es el SQL exacto de activación productiva.
[Casos complementarios y límites](../../CRM-Avance-Corp/supabase/scripts/multiempresa-f8/cierre-g7-2026-09-15/CASOS-COMPLEMENTARIOS.md).
[Pruebas y límites](../../CRM-Avance-Corp/supabase/scripts/multiempresa-f8/cierre-g7-2026-09-15/PRUEBAS-LOCALES.md).

Claude entregó CHANGES_REQUESTED. Se ampliaron autoría, ancla temporal, desglose
y procedencia de las lecturas; se preservó el dictamen y se evaluaron sus límites.
La segunda revisión del suplemento también pidió cambios: negativos de acceso,
procedencia e integridad de recibos y oráculos. Se corrigieron y reensayaron;
[evaluación y límites](../../CRM-Avance-Corp/supabase/scripts/multiempresa-f8/cierre-g7-2026-09-15/EVALUACION-CASOS.md).
No se declara aprobada la apertura general ni se cambia un requisito sin Miguel.

[Informe y recibos](../../CRM-Avance-Corp/supabase/scripts/multiempresa-f8/cierre-g7-2026-09-15/README.md),
[ruta de apertura](../../CRM-Avance-Corp/supabase/scripts/multiempresa-f8/cierre-g7-2026-09-15/APERTURA.md)
y [acta G7](../../CRM-Avance-Corp/supabase/scripts/multiempresa-f8/ACTA-G7.md).

No se creó banco remoto de pago. Para continuar los ensayos hay una copia local
propia `g7_cierre_20260915` en `supabase_db_avancecorp-f5-bank`, clonada de
`ficha_rapida_20260915` sin alterar la fuente. Se instala allí el código productivo
vigente antes de medir reintentos/carreras; los resultados están registrados en
los informes anteriores. La copia y su volumen conservan los datos sintéticos;
los servicios HTTP propios terminaron detenidos y eliminados.
