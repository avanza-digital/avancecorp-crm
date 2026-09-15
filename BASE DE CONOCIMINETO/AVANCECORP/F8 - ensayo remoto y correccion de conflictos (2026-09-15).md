# F8 — ensayo remoto y corrección de conflictos

Continúa [[F8 - ajustes de cartera y condiciones COOPAC preparados (2026-09-14)]] y [[F8 - piloto nominal activado (2026-09-14)]].

Estado: tres migraciones ensayadas en el banco autorizado, publicación pendiente. Se respetan el límite total US$1 y la eliminación del banco propio al terminar. La pausa anterior eliminó su primer banco; esta retoma usa una rama nueva.

Cartera conserva el núcleo canónico, Ficha 360 recupera sus componentes y COOPAC registra plazo en meses y porcentaje anual manual. Las pruebas remotas cubren Auth/roles, Storage, fechas, condiciones históricas NULL, reintentos y compatibilidad del CRM anterior. No se calculan comisiones.

La prueba real HTTP detectó que PostgREST 14.5 reintentaba indefinidamente los errores 40001 usados para revisiones obsoletas. La nueva migración 20260915015315 cambia cuatro rechazos manuales a PT409 en confirmar/corregir inversiones. Respuesta HTTP409 en unos160–175ms, datos intactos. Claude PASS; prueba de dos confirmaciones concurrentes crea una sola inversión.

Durante el ensayo otra tarea publicó PDF v9. Se actualizó el banco por rebase y se conserva ese cambio: los nueve archivos del PDF coinciden con producción y el repositorio. El nuevo frontend se construirá desde Main vigente, no desde el artefacto anterior c08.

Historial: 287 filas previas exactas, PDF concurrente segmentado en22 sentencias literales, más3 SQL de esta entrega. Fuente20260914213634→registro20260915010349; fuente20260914213928→20260915010350; corrección20260915015315 conserva versión. No se repara ni renumera historia ajena.

Hay otros usos manuales de40001 inventariados para investigar por recorrido; no equivalen a fallos HTTP demostrados ni justifican reemplazo global. Se documentan en `CRM-Avance-Corp/supabase/scripts/multiempresa-f8/ajustes-2026-09-15/RIESGO-40001.md`.

Acta técnica, pruebas y evaluación de Claude: `CRM-Avance-Corp/supabase/scripts/multiempresa-f8/ajustes-2026-09-15/README.md`. G7 requiere la comprobación productiva y conformidad visual del solicitante; no se da por cerrado con el banco sintético.
