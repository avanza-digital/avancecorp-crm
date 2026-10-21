# SLA por filas: paso 3a en producción (17/10/2026)

Relacionado: [[Nucleo operativo SLA - arquitectura y consumidores 2026-09-06]] · [[Plan final SLA - seguimiento compromisos y etapas 2026-09-06]]

## Qué cambió
La caída del 13/10 se debió a la memoria. `private.sla_operacion_autorizada` armaba **un solo jsonb** con todas las filas, y su
`jsonb_agg` ocupa unas 7 veces el tamaño del JSON. `work_mem` no lo acota. Desde el 17/10 a las 16:58 la ventana operativa se lee
**por filas**:
- **`private.sla_operacion_ambito(uuid[],boolean)`:** la ÚNICA pieza que decide quién ve qué (lee `auth.`), para los dos modos.
- **`private.sla_operacion_autorizada_filas(uuid[])`:** una fila por lead, más una cabecera que existe siempre.
- **Usan las filas:**
  - `crm.avisos_sla_resumen_v2_fn` cuenta sobre ellas;
  - `crm.cola_accion_v3_fn` pagina sobre ellas y arma el jsonb solo de la página.
- **`private.sla_operacion_autorizada`** queda como envoltorio del mismo jsonb, para los consumidores viejos.
- **Los guardianes** `assert_sla_nucleo`, `assert_sla_avisos` y `assert_cola_v3` sellan por md5 las piezas nuevas. Fue una excepción
  autorizada por Miguel a «la foto no toca controles».

El resultado es el mismo byte a byte: 9.193 comparaciones y 5.733 páginas encadenadas, con 0 diferencias.

## Cifras
- **Gerencia, cada llamada sola:**
  - avisos: de 104–123 MiB a 35–48 MiB;
  - cola: de 210–235 MiB a 41–55 MiB.
- **Carga con unas 40 consultas a la vez:** el pico del servidor baja de 1,56 a 1,12 GiB. En el peor caso, de 2,24 a 1,78 GiB.
  Avisos y cola son entre un 24 % y un 28 % más rápidos.
- **Decisión de Miguel:** aceptó una excepción. La ficha de SLA («estado») espera algo más en plena tormenta. La regla del arnés da
  «NO PASA», pero gasta la misma CPU: es ruido de cola de CPU.

## Lo que queda (Fase 4)
- **Siguen sobre el envoltorio**, sin la mejora: Gestión Diaria, `cola_accion_v2_fn` y `estado_sla_leads_v2_fn`.
  - Gestión Diaria escribe unos 5 MiB más de temporales por llamada (10 MiB gerencia) hasta pasarla a `_filas`.
- **Cambiar cualquiera de las piezas selladas** exige re-sellar su guardián y regenerar las reversas del kit
  `CRM-Avance-Corp/supabase/scripts/sla-por-filas/`.
- **Las reversas** se aplican como migraciones nuevas, que se registran solas (LEEME del kit).

## Dónde está todo
- Las 3 migraciones son `20261017054425/26/27`, en la PR #320.
- El acta está en `sla-por-filas/evidencia/13-acta-produccion-20261017.md` (PR #321, fusionada el 17/10 a las 17:20).
- El plan completo, «foto del SLA», está en la copia aislada `~/dev/avancecorp-crm-foto-sla/…/scripts/foto-sla/`.
