---
tags: [crm, multiempresa, metricas, f7, g6, retomar]
fecha: 2026-09-11
estado: publicada-instalada-off-g6-cerrado
---

# F7 publicada e instalada, apagada

Continúa [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]]
y [[F6 - cierre y ajustes publicados (2026-09-11)]]. La construcción y decisiones
iniciales quedan en [[F7 - informe multiempresa en sombra preparado (2026-09-11)]].

El informe **Empresas** quedó publicado con los componentes del CRM. Reúne
capital e inversiones por Avance/Qorilazo/Prodelco y PEN/USD, personas en varias
empresas, cotitulares, conversión, atribución, vencimientos y oportunidades.
Conserva los núcleos y no multiplica dinero por cotitular. Las comisiones
siguen fuera del sistema, según [[F4 cerrada - comisiones fuera del sistema (2026-09-08)]].

## Qué quedó terminado

- SQL exacto aprobado por Miguel e instalado por merge del banco Supabase.
  Archivo `20260911163243_crm_multiempresa_f7_metricas_sombra.sql`, registro
  remoto `20260911212526`. Cuatro funciones aditivas y bandera propia OFF.
- Frontend publicado desde el commit común de Main y `avancecorp/main`
  `32eae8a22cbeef8bc54c20e989c6612c0f201efe`. Release
  `crm-20260911T211821Z-32eae8a22cbe`; 90 recursos cotejados, portal conservado,
  demo deshabilitado y ZIP no accesible públicamente.
- 3.355 pruebas de frontend PASS; 172 E2E PASS / 26 SKIP preexistentes.
  Banco remoto: 16 SQL y 12 HTTP PASS; repetición final de los doce HTTP PASS.
- Las 619 funciones y 274 migraciones anteriores permanecen idénticas.
  Auth, datos financieros, cierres, Vault, cron y 19 Edge Functions conservados.
  Producción confirma F7 OFF y deniega peticiones anónimas.
- Banco temporal propio eliminado y ausencia comprobada a las 21:47:18 UTC
  del 11/09; se conserva el antiguo `banco-f7`, ajeno a esta tarea.
- Los cambios ajenos de Main se integraron y los cinco pendientes locales
  de otras tareas se conservaron. Commits y respaldo en
  `/Users/usuario/.codex/backups/avancecorp-f7-20260911`.

## Límites que no deben perderse al retomar

La matriz general RLS conserva **57 FAIL / 1.772 PASS** antes y después sobre
la misma semilla: **cero regresiones**, sin declarar el gate general aprobado.
Los dos WARN nuevos del banco son los previstos por las RPC F7 autenticadas
con permisos comprobados. No se declara un PASS global de seguridad.
Claude revisó dos veces; sus `CHANGES_REQUESTED` fueron evaluados y los hallazgos
confirmados se corrigieron. Detalles y evidencia:
[acta de publicación](../../CRM-Avance-Corp/supabase/scripts/multiempresa-f7/PUBLICACION-2026-09-11.md).

**F3 ON; F4/F5/F6/F7 OFF. G6 cerrado el 13/09/2026.** Miguel revisó las cifras
reales y dio conformidad financiera al corte; las pruebas ficticias no
sustituyen esa aceptación. Rendimiento con volumen real y VoiceOver F6: NOT RUN,
este último omitido por decisión de Miguel. Los quince huecos históricos no se
trataron.

## Siguiente paso

La aceptación humana/financiera quedó registrada en el [acta G6](../../CRM-Avance-Corp/supabase/scripts/multiempresa-f7/ACTA-G6.md).
Corresponde preparar y solicitar el piloto F8; F9 requiere activación
progresiva y un ciclo mensual completo. No volver a pedir aprobación del SQL
ya instalado ni recrear el banco cerrado para repetir esta publicación.
