---
tags: [crm, multiempresa, metricas, f7, g6, retomar]
fecha: 2026-09-11
estado: sql-aprobado-coste-banco-instalacion-y-g6-pendientes
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

## Autorización y preparación posterior — 11/09/2026

Miguel respondió **«sii»** al SQL concreto y a ensayarlo e instalarlo
inicialmente apagado. Su SHA-256 continúa siendo
`7b9cb56992dea24ead99d2d14c8ac79f9dabc7e9b40765f666117a5986e3c8e7`.
No se debe volver a pedir autorización de ese mismo SQL.

Se integró Main `4bfae49` en `8dd0a14`, conservando el filtro de tipo de capital
de Facturación y el ajuste del aviso push. La consulta productiva de solo
lectura a las 20:26 UTC confirmó **274 migraciones**, las cuatro huellas
esperadas, F7 ausente y las banderas anteriores sin cambios. El frontend
vigente corresponde a Main `4bfae49`; se identificó y verificó su ZIP anterior.

Supabase informó **US$0.01344/h** por una nueva rama en PortalAvanceCorp.
La pregunta de coste sigue pendiente de respuesta; **no se creó una rama**.
Conservar el antiguo `banco-f7` de altas: no pertenece a esta fase multiempresa.
Gates actualizados y evidencia:
[preparación de la instalación](../../CRM-Avance-Corp/supabase/scripts/multiempresa-f7/PREPARACION-INSTALACION-2026-09-11.md).
Capturas privadas: `/private/tmp/avancecorp-f7-publicacion-20260911`.

## Siguiente paso concreto

1. Resolver la respuesta pendiente al coste del banco; el SQL ya fue aprobado
   conforme a [[Inicio]]. Confirmar coste y crear una rama propia solo si se autoriza.
2. Ensayar el paquete en la rama Supabase autorizada, completar gates remotos
   y publicar desde Main/remoto/artefacto con el mismo commit verificado.
3. Verificar la instalación apagada y realizar la revisión de cifras reales.
4. Completar y firmar
   [G6](../../CRM-Avance-Corp/supabase/scripts/multiempresa-f7/ACTA-G6.md).
5. Solo entonces solicitar el piloto económico F8 y seguir F9 con su ciclo
   operativo mensual. Este ensayo no sustituye esas fases ni sus firmas.
