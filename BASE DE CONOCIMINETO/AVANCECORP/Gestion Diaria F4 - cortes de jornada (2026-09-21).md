---
tags: [crm, gestion-diaria, f4, cortes]
estado: implementada y verificada localmente — sin publicación ni activación
fecha: 2026-09-21
---

# Gestión Diaria F4 — Cortes de jornada

Miguel aclaró: implementar la etapa 3 y preparar su publicación. La entrega
incluye política versionada inicialmente OFF, cálculo del servidor y contrato
de lectura compatible. No incluye pop-up/aplazamiento (etapa 4), pantalla de
configuración (etapa 5) ni activación (etapa 6).

Conserva las decisiones de [[Gestion Diaria F4.1 - banco humano y reglas de cortes (2026-09-21)]].
La base de las 11:30 no crece con llamadas posteriores; el segundo corte es
acumulado, no llamadas extra. Cartera abierta y jerarquía se evalúan al consultar:
el histórico no es una foto inmutable. Ventanas `[medianoche Lima, corte)`.
El sábado el primer aviso puede recuperarse antes de las 13:00.

Código y evidencia en `CRM-Avance-Corp/docs/gestion-diaria/F4-CORTES-JORNADA.md`.
Candidato `20260921214018_crm_gestion_diaria_cortes.sql`, SHA-256
`8563bf8bf66e97a4e328d54582bbcf74e17f63d3d6056c6f9ae2dc4b9f940ea5`.
Miguel autorizó sólo banco local `gestion_diaria_f4_vista_chvrqh` y reversa.
Ensayo completo PASS: negocio y RLS por identidad, paridad supervisor/gerencia/global,
umbrales de puertas F3/F4, cartera vacía/cerrada y revocación, calendario Lima,
15 mutantes, regresiones, tipos, censo y reversión de funciones. Base termina
sin objetos candidatos; fixtures revertidos y auditoría local conservada.

Aplicación: 4.073 tests y `npm run check` PASS; scripts y siete tests offline PASS.
Dos reviews Claude: último CHANGES_REQUESTED; PRIMARY incorporó permisos por
columna, autor/orden futuro, guardas y pruebas. Descartó hipótesis con evidencia:
F3 sí pasa medianoche Lima y umbrales legacy sí conserva su sello. No se pidió
otro review para obtener PASS. HTTP completo y carga/concurrencia con roster
productivo siguen pendientes antes de activar; local probó 6.000 llamadas por
analista con cartera en roster de tres. No se atribuye aprobación total a Claude.

La etapa 3 no cambia todavía la pantalla. Próximo producto: etapa 4, pop-up y
reconocer/posponer en servidor. Después editor gerencial y validación/activación.
Publicación requiere SQL exacto autorizado, integración en Main sin pisar trabajo
concurrente y `$release-crm`; no hubo push, PR, despliegue ni activación en esta entrega.

## Guardado y punto de retoma

### Retoma posterior: banco HTTP autorizado

Miguel retomó el objetivo y autorizó exclusivamente `gestion-diaria-f4-http`
(59321–59324), sin producción, pagos, despliegue ni activación. `9a101dcd` integra
el Main remoto `59dd1480`. Corrección del registro anterior: `43557bc9` era trabajo
local adicional de otra tarea, no ese remoto. No se tocó ni reseteó Main.

El banco nuevo está en `/private/tmp/gestion-diaria-f4-http.WQNCJc`, separado del
anterior. Servicios propios, puertos sólo loopback, sin ruta de salida por
defecto ni reinicio automático. Auth HTTP 200; salida TCP externa rechazada.
Esquema vigente y metadatos técnicos sin usuarios/filas comerciales de origen.
Paridad de 14 categorías del catálogo PASS después de corregir únicamente los
defaults ACL locales. Gates SQL preexistentes de Gestión Diaria PASS.

La semilla se completó, incluidos los dos contratos históricos. Primera matriz
general real: **2.149 aserciones, 86 FAIL**, antes del candidato; Gestión Diaria
F1–F3 PASS, F4.3 explícitamente no instalada. Miguel autorizó actualizar también
la matriz general: flujo de inversión vigente, rechazos legacy y configuración
técnica del banco. No cambiar negocio para hacer pasar pruebas.
La actualización quedó verificada: **baseline 2.164/0 fallos y candidato OFF
2.196/0 fallos**. Se mantuvieron las pruebas negativas, identidad y replay,
usando el circuito compartido real. Handler Avance en proceso, no Edge desplegada.
Se conservó la base ficticia inicial como `gd_f4_http_historial_20260922`, los
ensayos renombrados y los respaldos privados; no se truncó historia.

Atomicidad, instalación, reversión exacta con negocio/auditoría conservados y
reinstalación OFF PASS. Siete respuestas reales mantienen el contrato antes/después.
Navegador real con dos supervisores y analista PASS, también tras revertir servidor.
Compatibilidad de parsers antiguos/nuevos: 28 casos PASS. Con SLA activo, resultado
«No le interesa» + seguimiento WhatsApp dejó llamada/tarea reales sin descartar.
Modo SLA restituido; cuatro reglas sintéticas e historia conservadas, cortes OFF.
No se simularon API/Auth ni sesión demo en ese recorrido. La Edge de tipo de cambio
no está en el banco y se presenta indisponible, límite explícito del ensayo.

22 E2E existentes y `npm run check` PASS; scripts, seed/RLS preflight y Edge PASS.
Nuevos tests offline: 17 guardas + 8 helper de conversión. La interfaz 59323 se
cierra después de los recorridos. El banco queda instalado con una sola política OFF.
Claude recibió dos consultas acotadas (banco y ampliación de matriz), ninguna con
dictamen utilizable. Revisión no completada, no aprobación; settings intactos.

Validación técnica local cerrada; siguiente: preparar PR/integración y publicación
OFF mediante SQL exacto autorizado y `$release-crm`, sin iniciar etapa 4. No hubo
push ni publicación. Runbook: `docs/gestion-diaria/F4-PUBLICACION-RECUPERACION.md`;
resguardos y aprobación del destino se completan durante el release. No ejecutar
la reversa del banco en producción. TypeSafe sigue separado y apagado.
El plan principal conserva el checkpoint detallado y gobierna la continuación.

### Pausa anterior (histórico, ya retomada)

Miguel pidió guardar el plan y continuar aproximadamente una hora después.
La recomendación registrada es publicar la etapa 3 por separado **apagada**,
después de cerrar la matriz HTTP/Auth en pruebas, preparar la recuperación
productiva y verificar integración/artefacto desde Main = `avancecorp/main`.
Después se necesitan autorización del SQL exacto y el flujo humano `$release-crm`.
La reversa local no se debe ejecutar directamente en producción. El guardado
no autoriza despliegues ni activación durante la pausa.

La implementación está guardada en `19f8c180`, rama
`codex/gestion-diaria-typesafe-piloto`, en el taller existente. Al volver,
retomar los pendientes de publicación, no reconstruir la etapa 3 ni empezar
automáticamente la etapa 4. Secuencia: publicar la base OFF → avisos/reconocer/
posponer (4) → configuración (5) → validación integral y activación (6).
Estado y lista completa en el último punto de control del plan principal:
`CRM-Avance-Corp/docs/gestion-diaria/GESTION-DIARIA.md`.
Las pruebas consignadas son las de la entrega previa; este guardado sólo
actualiza documentación. TypeSafe continúa separado y sin activar en el CRM.

Relacionadas: [[Gestion Diaria F4 - objetivos y piloto TypeSafe (2026-09-20)]] · [[Inicio]].
