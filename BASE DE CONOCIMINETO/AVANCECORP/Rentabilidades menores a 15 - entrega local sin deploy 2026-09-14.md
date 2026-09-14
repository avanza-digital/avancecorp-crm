---
tags: [crm, rentabilidad, preparacion, no-deploy]
fecha: 2026-09-14
estado: verificado-local-pendiente-ciclo-remoto
---

# Rentabilidades menores a 15 — entrega local sin deploy

Miguel pidió preparar el cambio sin desplegar. Después de reanudar retiró la orden
de publicación: **«todavia no hagas deploy»**. Esta es la instrucción vigente.
No se instaló la candidata ni se publicó frontend/Edge; no se hizo push.

## Resultado de negocio

El analista puede escribir una tasa positiva con hasta dos decimales para una
inversión nueva, desde 0,01 % hasta la base vigente (actualmente 15 %).
Arranca en 15, acepta coma o punto y conserva la elegida desde el lead al contrato.
Superar la base mantiene la aprobación de Gerencia para la misma intención;
escribir una menor no evita solicitudes pendientes. Renovaciones/upgrades conservan
el mínimo heredado y no se habilitan rebajas de contratos emitidos.

## Verificación y revisión

- PASS: gate frontend completo tras integrar Main, 244 archivos y 3.540 pruebas, con build incluido.
- PASS: Playwright, 182 aprobados y 26 omitidos preexistentes; tres nuevos casos
  a 12,5/13,5 %. Escritorio y móvil inspeccionados. Siete E2E de tasas repetidos.
- PASS: Edge/preflights; 14 casos de tasa ejecutan el handler con dobles.
- PASS: PostgreSQL local con analista authenticated, tasas válidas/invalidas,
  precisión sin redondeo silencioso, herencia, PDF, pendientes y conversión completa.
- PASS: instalación/reversa exacta conservando permisos de cuatro funciones;
  dos sesiones verifican ambas carreras de reversa/reserva y sus rechazos seguros.
- Dos reviews de Claude terminaron CHANGES_REQUESTED sin P0/P1. Codex evaluó sus
  hallazgos, corrigió precisión/preselección/reversa/mensajes y verificó. No se
  presenta a Claude como un PASS final ni se pidió una tercera confirmación.
- NOT RUN: candidata en rama remota, matriz general Auth/PostgREST de 13 roles,
  advisors de candidata instalada y smoke productivo. La validación local y los
  E2E simulados no sustituyen esos controles. La entrega está preparada en local;
  falta el ciclo remoto antes de considerarla publicable.

## Código y respaldo

Clone aislado: `/private/tmp/avancecorp-tasas-bajas-20260913`, rama main con
upstream avancecorp/main. Se integró sin conflictos el ajuste publicado de
Facturación y su nota; base remota final:
`5ec99dbbf6122acc7cf98473aa76575e4b3e3d6d`. El commit de preparación queda local,
sin push. El manifiesto del paquete identifica su commit exacto.

Paquete, fuente y logs duraderos en
`CRM-Avance-Corp/releases/tasas-inferiores-20260914/` del workspace principal,
fuera del web root y sin .env/credenciales. Incluye bundle de Git, ZIP frontend,
manifiesto y acta local. El respaldo de pausa anterior en
`_DEV_NO_SUBIR/pausas/tasas-inferiores-20260914/` conserva el estado histórico
anterior a las últimas correcciones; no confundir sus hashes con esta entrega.

SQL:
`CRM-Avance-Corp/supabase/migrations/20260914042114_crm_tasas_inferiores_nuevas_inversiones.sql`.
Instrucciones, revisiones y evidencia:
`CRM-Avance-Corp/supabase/scripts/tasa-baja/README.md` y `verificacion.md`.

El trabajo sin commit de Citas del workspace principal permanece separado.
No se sobrescribieron su Inicio.md, tipos, código ni candidatas.

## Retoma

Esperar la instrucción de Miguel para publicar. Completar el ciclo autorizado del
banco remoto (seed previo, candidata, oráculos, RLS, advisors), integrar Main con
avancecorp/main sin perder las otras tareas, repetir las cuatro huellas productivas
y reconstruir desde el mismo commit sincronizado. No hacer db push general ni
aplicar directamente a producción. Servidor antes que frontend.

La reversa SQL solo es válida antes de contratos o conversiones comprometidas a
tasa inferior. Después se corrige hacia delante. Tiene guardas de huella/uso,
candados y timeout; nunca borrar datos para permitirla.

Relacionadas: [[Rentabilidades menores a 15 - propuesta 2026-09-13]],
[[Rentabilidades menores a 15 - pausa segura 2026-09-14]],
[[Solicitud de tasa en el lead - publicada 2026-09-09]],
[[Alertas de respuestas de tasa para analistas - 2026-09-11]],
[[Main unico - sincronizacion y publicacion 2026-09-04]], [[Inicio]].
