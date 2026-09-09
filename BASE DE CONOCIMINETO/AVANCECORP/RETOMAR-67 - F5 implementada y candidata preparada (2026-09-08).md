---
tags: [crm, cartera, F5, retomar]
fecha: 2026-09-08
estado: candidata-implementada-sin-encendido-productivo
---

# CARTERA — F5 implementada y candidata preparada

Miguel retomó el desarrollo de [[Plan de implementacion F5 - cartera y ficha multiempresa (2026-09-08)]].
Se implementaron cartera única, ficha neutral y nueva inversión en Avance,
Qorilazo y Prodelco mediante F4. Monedas y fuentes separadas, sin perfil ficticio
para cooperativas. Las comisiones siguen calculándose fuera del sistema.

## Guardado y evidencia

Rama de trabajo: `codex/f5-cartera`, carpeta aislada
`/private/tmp/avancecorp-f5-desarrollo`. Se incorporaron los commits de Citas
`c06949b`, `2a1516f` y posteriormente `2135fa4` de Main y se verificó el CRM conjunto.

Commits del desarrollo: `0d6aa4d`, `9789ca2`, `cc555ce`, `9e1b012`, `3b6c7ab`,
`e07cdeb`, merge `4dd25d5` y correcciones revisadas `f7a425f`. La preparación
SQL/evidencias se guardó en `257af26`; la actualización del plan principal tiene
un commit documental posterior. El manifiesto del paquete identifica
el commit final verificado; no usar una captura anterior como release.

Main se integró y subió a `avancecorp/main`. Los 244 archivos pendientes de las
otras tareas se respaldaron y conservaron; los dos archivos compartidos se
combinaron sin conflictos. Respaldo durable:
`/Users/usuario/Desktop/DESARROLLO/DESARROLLO/RESPALDOS-CARTERA/cierre-f5-20260908-210909`.
Contiene bundle verificable, trabajo ajeno pendiente, banco sintético y paquete.
El manifiesto privado de cierre identifica las huellas y el commit definitivo.

- 38 pruebas locales de Auth, PostgREST, RLS, Storage, finanzas y recuperación: PASS.
- Gate completo CRM tras integrar Citas `2135fa4`: 3.127 pruebas unitarias,
  147 E2E y 26 omisiones existentes; incluye los siete recorridos F5: PASS.
- PDF PEN/USD: mismo contrato, job, snapshot y bytes al recuperar. Plantilla v8,
  assets y fuentes conservados; ocho páginas revisadas.
- SQL exacto y reversa probados en una copia sintética nueva. Tipos cotejados;
  ningún contrato, capital, identidad, Auth o función publicada ajena cambiado.
- Claude revisó sin editar. Dictamen CHANGES_REQUESTED evaluado y corregido con
  pruebas; no se presenta como un PASS automático ni reemplaza la verificación.
- CI detectó ocho capturas antiguas de Seguimiento con rutas exclusivas de macOS.
  Se corrigieron en `f621915`; la suite de 14 casos y el gate completo pasan.
  Se conservan el fallo original y el resultado remoto posterior en el respaldo.

Acta técnica y capturas: `CRM-Avance-Corp/supabase/scripts/f5/ACEPTACION.md`.
Contrato, instalación futura y reversa: `CRM-Avance-Corp/supabase/scripts/f5/README.md`.
La migración candidata es `20260908230249_crm_f5_cartera_ficha_multiempresa.sql`.

## Decisiones que deben conservarse

- Responsable actual decide acceso; atribución histórica no devuelve PII al anterior.
- Directorio conserva alcance Avance; sin documentos privados, cuentas ni escritura.
- La auditoría agrupa la consulta continuada cada 60 segundos y revalida permisos
  cada 15. Un lead bloqueado por otra edición no tumba la ficha.
- Reintentos conservan UUID, contenido y revisión. Se recuperan correcciones,
  acceso y PDF por separado; la inversión solo se anuncia tras confirmación.
- El borrador/token vive en la sesión del navegador. Al revocar se purga PII y
  puede conservarse únicamente su referencia opaca para revisión autorizada.
- La fusión vigente no admite dos perfiles Avance. La fusión permitida conserva
  el perfil contractual; el aumento heredó la tasa y el origen correctos.

## Lo siguiente

No se instaló SQL F5 ni se publicó/encendió F5 en producción. F4 permanece
publicada; sus escritores y la ficha F5 siguen OFF. La preparación de F5 no
habilita un piloto económico. Siguen las puertas de F6, F7/G6, F8/G7 y F9/G8.

Queda la revisión personal de Miguel de las capturas; no se ejecutó una sesión
manual de VoiceOver. Advisors, carga y gates del destino se ejecutan al publicar.
Antes del encendido se concilian los huecos del censo con los lotes F4 revisados;
no usar backfill global ni aceptar totales parciales.

Los cambios ajenos aún sin commit en la carpeta principal deben conservarse.
Main debe seguir `avancecorp/main`; nunca `origin/main` o el antiguo `tronco`.

Relacionados: [[RETOMAR-66 - F5 desarrollo pausado (2026-09-08)]],
[[RETOMAR-65 - CARTERA F4 publicada y plan F5 (2026-09-08)]],
[[F4 cerrada - comisiones fuera del sistema (2026-09-08)]],
[[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].
