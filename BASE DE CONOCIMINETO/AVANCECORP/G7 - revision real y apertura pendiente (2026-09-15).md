---
tags: [crm, multiempresa, f8, g7, conciliacion, retomar]
fecha: 2026-09-15
estado: revision-real-pasada-g7-abierto
---

# G7: revisión real y preparación de apertura

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

**G7 abierto.** Miguel tiene pendiente decidir si acepta la muestra existente
para el volumen y los casos faltantes en pruebas aisladas, o mantiene la
recolección de casos reales del maestro. «Retoma este objetivo» reanuda trabajo,
no firma ese ajuste. Las pruebas técnicas aisladas de reintentos/concurrencia
pueden continuar porque ya forman parte del plan autorizado.

Claude entregó CHANGES_REQUESTED. Se ampliaron autoría, ancla temporal, desglose
y procedencia de las lecturas; se preservó el dictamen y se evaluaron sus límites.
No se declara aprobada la apertura general ni se cambia un requisito sin Miguel.

[Informe y recibos](../../CRM-Avance-Corp/supabase/scripts/multiempresa-f8/cierre-g7-2026-09-15/README.md),
[ruta de apertura](../../CRM-Avance-Corp/supabase/scripts/multiempresa-f8/cierre-g7-2026-09-15/APERTURA.md)
y [acta G7](../../CRM-Avance-Corp/supabase/scripts/multiempresa-f8/ACTA-G7.md).

No se creó banco remoto de pago. Para continuar los ensayos hay una copia local
propia `g7_cierre_20260915` en `supabase_db_avancecorp-f5-bank`, clonada de
`ficha_rapida_20260915` sin alterar la fuente. Se instala allí el código productivo
vigente antes de medir reintentos/carreras; los resultados se registrarán aparte.
