---
tags: [crm, multiempresa, metricas, f7, g6, retomar]
fecha: 2026-09-11
estado: candidata-local-instalacion-y-g6-pendientes
---

# F7 — informe por empresa preparado en local

Continúa [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]],
después de [[F6 - cierre y ajustes publicados (2026-09-11)]].

## Qué se construyó

Nueva pantalla **Empresas** de Gerencia, con componentes y aspecto del CRM:

- capital y cantidad de inversiones por Avance/Qorilazo/Prodelco y PEN/USD;
- contratos nuevos, renovaciones y upgrades separados en el detalle;
- personas en una/dos/tres empresas, incluidos cotitulares sin duplicar dinero;
- primera y posterior registradas según historia conocida del titular principal;
- conversión y atribución conservando los núcleos actuales;
- vencimientos de treinta días y oportunidades que respetan No contactar;
- comparación de cifras y advertencias de identidad incompleta/repeticiones.

El capital completo de una renovación no se presenta como dinero nuevo.
La consulta de un mes cerrado se identifica como proyección actual en sombra;
su foto firmada no cambia. Las comisiones permanecen fuera del sistema, según
[[F4 cerrada - comisiones fuera del sistema (2026-09-08)]].

SQL aditivo: cuatro funciones nuevas y bandera `metricas_multiempresa_sombra`
apagada. Comprueba Gerencia vigente y perfil activo en cada RPC. Ninguna
tabla nueva, escritura financiera, cambio Auth o modificación de los núcleos.
La admisión no depende del rol que declare el navegador. El demo es local,
no crea cuentas Auth y está excluido de builds productivos.

Paquete y pasos reproducibles:
[README F7](../../CRM-Avance-Corp/supabase/scripts/multiempresa-f7/README.md).
SQL concreto:
[20260911163243_crm_multiempresa_f7_metricas_sombra.sql](../../CRM-Avance-Corp/supabase/migrations/20260911163243_crm_multiempresa_f7_metricas_sombra.sql).
Revisión/evidencia:
[evaluación de Claude](../../CRM-Avance-Corp/supabase/scripts/multiempresa-f7/REVISION.md).

## Qué se verificó y corrigió

Banco independiente dentro del contenedor local F5/F6, base
`multiempresa_f7_20260911`; la base original `postgres` se conserva.
Datos exclusivamente sintéticos. PostgreSQL, Auth y PostgREST reales en las
pruebas de servidor. Valibot y la integridad de la pantalla validan también
el JSON real del banco, no solo ejemplos de frontend.

Claude revisó arquitectura e implementación como SECONDARY_REVIEWER, con
herramientas y escritura deshabilitadas. Sus dictámenes CHANGES_REQUESTED
quedan archivados; Codex contrastó los hallazgos, corrigió los confirmados
y rechazó las hipótesis contrarias al esquema/contrato real. No se atribuye
a Claude un PASS que no emitió.

El gate encontró un fallo reproducible de F6: Escape al reabrir una revisión
podía cerrar la ficha inferior. La corrección local pasó la misma secuencia
8/8 veces sin añadir esperas. Al integrar Main llegó la solución `e01aea1`
para ese mismo problema: se conserva intacta y se retira la propuesta local,
sin duplicar mecanismos de cierre. Se verificó el conjunto integrado:
3.329 pruebas unitarias, 168 E2E y 25 pruebas de servidor PASS; 26 E2E SKIP.
La revisión manual F6 previamente aceptada y su excepción de VoiceOver
conservan su alcance; no se inventó otra aprobación manual.

El estado preciso de los gates y sus límites se registra en
[aceptación F7](../../CRM-Avance-Corp/supabase/scripts/multiempresa-f7/ACEPTACION.md).

## Estado para retomar

- Rama de trabajo: `codex/f7-metricas`, worktree `/private/tmp/avancecorp-f5-publicacion`.
- Código F7 guardado en `2a9ff19`; la evidencia se incorpora en un commit posterior.
- Se integró `avancecorp/main` hasta `5d49bcf`, conservando Facturación,
  notificaciones de tasa, corrección Escape y notas/evidencias ajenas.
  No usar `origin/main` ni `tronco`.
- Vista previa solo local: `http://127.0.0.1:5227/#/informes-empresas`, modo demo
  → Gerencia. API loopback sin credenciales reales. Cifras ficticias.
- Evidencia privada de sesión: `/private/tmp/avancecorp-f7-20260911`.
- Respaldo duradero: `/Users/usuario/.codex/backups/avancecorp-f7-20260911`.
- **No se instaló ni publicó F7 en producción.** La lectura productiva previa
  confirmó 273 migraciones y cuatro huellas iguales a las ensayadas; F7 ausente.
- F3 permanece ON; F4/F5/F6 permanecen OFF. Los quince huecos históricos no se
  trataron ni se hizo backfill en esta fase.

## Siguiente paso concreto

1. Aprobar el SQL exacto F7 antes de instalarlo, conforme a [[Inicio]].
2. Ensayar el paquete en la rama Supabase autorizada, completar gates remotos
   y publicar desde Main/remoto/artefacto con el mismo commit verificado.
3. Verificar la instalación apagada y realizar la revisión de cifras reales.
4. Completar y firmar
   [G6](../../CRM-Avance-Corp/supabase/scripts/multiempresa-f7/ACTA-G6.md).
5. Solo entonces solicitar el piloto económico F8 y seguir F9 con su ciclo
   operativo mensual. Este ensayo no sustituye esas fases ni sus firmas.
