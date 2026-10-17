# Evaluación PRIMARY del review final

16/10/2026 Lima. Reviewer: Claude SECONDARY_REVIEWER, wrapper aislado del
repositorio. Dictamen original CHANGES_REQUESTED conservado íntegro. Codex
investiga, decide y ejecuta los checks; no se solicitó una tercera consulta.

| Observación | Decisión y evidencia |
| --- | --- |
| P1: relectura monetaria distinta del stock canónico | Hipótesis descartada para el núcleo vigente. El cuerpo productivo guardado de capital_episodios selecciona c.moneda, c.capital y c.fecha_cierre_comercial para stock; los adicionales son otra rama medida=desglose, excluida por capital_operaciones_base. En contratos no existe una fecha de episodio stock independiente de la comercial. Cooperativas sí separan fecha comercial/imputación y la relectura utiliza ese mismo COALESCE. M2 fija MD5 c87bec9506d8b9d2ce0f215895a34e18. Se añadió una aserción por todas las fuentes de las semillas (renovación, upgrade, cooperativa de septiembre imputada en octubre); PASS. No simular una proyección incompatible con el negocio nativo para justificar otro algoritmo. Cualquier cambio futuro del cuerpo rechaza la migración por su guarda. |
| P2: escala mayor de dos decimales revierte al escribir | Hipótesis descartada: public.contratos.capital es numeric(12,2), crm.cierres_externos.monto numeric(14,2), verificados en catálogo restaurado. Nueva aserción PASS. Las RPC nativas/constraints fijan la fuente antes de valorar. Se conserva rollback ante integridad rota; no capturar todos los errores y confirmar una operación corrupta. La ausencia de TC ya se difiere sin error y tiene prueba F4/Auth real. |
| P2: materialización grande mientras cierre bloquea escrituras | Aceptada. Nueva candidata CLI 20261017033241 reemplaza solo preparar_sello_capital: precheck de pendientes antes de SHARE, exige reconciliación del worker, revalida bajo bloqueo y limita lock_timeout a 5 s. Elimina el bucle de hasta 100 000 revisiones bajo locks. PASS con 600 ventas PEN conocidas diferidas sin crear valoraciones, tasa aceptada aún sin materializar y posterior reconciliación/cierre. Las cuatro carreras cierre/corrección siguen PASS. |
| P2: cierre durante suspensión impide reactivar | Guarda deliberada que preserva sellos previos; runbook ampliado para hacer explícito el efecto. Suspender no pausa el cron existente. Si se cierra un mes desde octubre con régimen anterior, no se promete reactivación automática ni se reescribe ese mes. Recuperación eventual requiere decisión/migración explícitas. Prueba de suspensión, cierre legado y rechazo de activación ya PASS. |
| P3: algunas anclas solo comprueban presencia | No se amplía el cambio. Hashes exactos de los cuerpos originales fijan su cardinalidad/layout. Se inspeccionó capital_autorizada nativa: autorización, periodo y medida se validan antes del segmento extraído; entre las anclas solo estaban global/visibles y rechazo de conjunto vacío, ahora en ambito_capital_confirmado. No se eliminó otra validación. Paridad de payloads v2 con filas y permisos, once meses y matriz HTTP ejecutadas PASS. Toda modificación ajena del cuerpo obliga a rebasar y repetir comparación. |
| P3: auditoría de reservas/reintentos crece durante caída | Riesgo operativo aceptado: se conserva auditoría de cambios y reintento indefinido por la política sin tasa de emergencia. Un trabajo por fecha/política, no por venta; observar volumen/antigüedad y aplicar retención operativa del proyecto por flujo autorizado. No limitar reintentos para ocultar atascados. |

## Test gaps contrastados

- Coordinación: cumplimiento_metas_fn nativa ya usa es_coordinador_reportes
  como lector global mensual. El ámbito general de capital es otra puerta
  con permiso distinto. HTTP añadió al coordinador real de la semilla (actor4):
  personas v2 son productores que ya ve v1; ocho ámbitos mensuales PASS.
- Sin primer corte: objetivos.ts acepta capital_valorado opcional y nullable
  en vendedores/fuera_ranking; personas es un array vacío. SQL/fixtures/modelo/
  UI acreditan estado sin_corte sin total cero ni puestos ficticios.
- La suite E2E completa terminó con un guard de compatibilidad fallido y un
  timeout intermitente. Se corrigió el guard para validar exactamente PGRST202;
  los cinco tests del archivo pasaron al repetir en Docker. Resumen original
  preservado en ESTADO.md, sin convertir su exit1 en PASS retrospectivo.
- Censo actualizado a 116 operaciones, nueve fechas BCRP y total numeric
  S/4 650 700,67, repetición0; replay histórico con las diez candidatas.
- No se atribuye evidencia al render/subida de PDF ni a un navegador F4 con
  Auth real: se ejecutaron las RPC de preparar/revisar/confirmar y escritores
  con Auth HTTP; reserva/rollback PDF en el gate SQL. Los recorridos UI afectados
  de esta tarea tienen E2E propios.

Riesgo residual: las guardas MD5 deben contrastarse otra vez con el esquema
vivo antes del despliegue; este worktree no es un artefacto de publicación.
Leer ACTIVACION.md. No se activó ni se modificó producción.
