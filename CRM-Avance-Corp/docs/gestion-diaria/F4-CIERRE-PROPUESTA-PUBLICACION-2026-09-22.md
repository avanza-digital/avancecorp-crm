# F4 — propuesta de instalación y publicación

**Preparada para revisar; no ejecutada en producción.** La entrega incorpora los
avisos del supervisor y las reglas futuras de gerencia. Las migraciones conservan
los cortes apagados. La activación será una versión futura, después de publicar
y comprobar el funcionamiento. La alerta de tasa baja queda apagada hasta F5.

## Alcance de la autorización solicitada

1. Banco remoto temporal **sin datos productivos**, para probar los cuatro SQL
   y la matriz RLS con fixtures. Organización confirmada por Miguel:
   `AVANCECORP- CRM-PORTAL` / `fzxtxnkvslpcsscxqfbr`; proyecto padre
   `PortalAvanceCorp` / `dctqcbznekcyxhjujuci`.
2. Conciliar exclusivamente la versión administrativa de etapa 3, con el SQL
   exacto enlazado abajo; conservar las 33 sentencias y todas las demás columnas.
3. Aplicar los cuatro SQL exactos mediante rama Supabase → pruebas/advisors →
   merge, conservando política v1 OFF. No hacer `db push` general.
4. Publicar el frontend con `$release-crm`, desde Main/remoto coincidentes,
   conservando el cambio de Acceso Avance y el respaldo actualmente servido.
5. Después del smoke, publicar una política futura con gerencia y verificar la
   primera jornada. El cierre local por sí solo no completa F4.

**Coste cotizado por el MCP:** US$0,01344 por hora para una rama estándar.
Dos a cuatro horas equivalen a US$0,02688–0,05376 de ese cargo. Tope propuesto
**US$1**, eliminar el banco al terminar y, como máximo, a las 24 horas. Si el
servicio exige otra modalidad o excede el tope, no crearla sin nueva autorización.
No se usará `Include data`: copia datos productivos y puede aumentar disco y
cómputo según la [documentación de Supabase](https://supabase.com/docs/guides/deployment/branching/dashboard).
Producción tiene nueve trabajos Cron activos; no se copian su ejecución, secretos
ni colas a los fixtures. La rama ajena `banco-f7` no forma parte de esta tarea.

## SQL exacto, en orden

| Archivo | Efecto | SHA-256 |
|---|---|---|
| [20260922184459_crm_gestion_diaria_avisos.sql](../../supabase/migrations/20260922184459_crm_gestion_diaria_avisos.sql) | Entrega y reconocimiento persistentes; rol lector con RLS, controles, auditoría y guardas | `5146e68682c76377c34a2fbb6c4c6521673ba793fe1def87d056e65aa928ec74` |
| [20260922185138_crm_gestion_diaria_configuracion.sql](../../supabase/migrations/20260922185138_crm_gestion_diaria_configuracion.sql) | Editor gerencial, versión futura y control de concurrencia; tasa baja NULL | `8666a0944df9d4a5e62fda24c72cead5f181815ea17d5e73bdd2c9572557fd9a` |
| [20260922204125_crm_gestion_diaria_alertas_equipo.sql](../../supabase/migrations/20260922204125_crm_gestion_diaria_alertas_equipo.sql) | Grupos del núcleo SLA y contexto de llamadas del ámbito autorizado | `d13746a18c1fd8e171fc55ffeec66641054bcbdaf83f43892c6b8b7cf3bcdf1c` |
| [20260922220800_crm_gestion_diaria_avisos_lectura.sql](../../supabase/migrations/20260922220800_crm_gestion_diaria_avisos_lectura.sql) | SLA fuera del lock de presentar/reconocer; lectura completa por GET | `a7496835b1621967453c334b7d85d101bb245d143469ad979a4a38d995f3e32c` |

Corrección administrativa separada:
[conciliar-ledger-etapa3.sql](../../supabase/scripts/gestion-diaria-seguimiento/conciliar-ledger-etapa3.sql),
SHA-256 `c48f536ddf408adfebbbd1563f57fddd0ec50f6a84de47b67ca769db30349452`.
Cambia `20260922164159` → `20260921214018` bajo lock, comprobando nombre único,
destino libre, 33 sentencias y huella exacta. No reejecuta DDL ni modifica política.
Respaldo privado completo y ensayo con ROLLBACK/3 derivas PASS.

## Evidencia disponible y pendiente

- `npm run check`: 4.153 pruebas/277 archivos, lint, typecheck, cobertura,
  build y bundle PASS sobre `7c4a8d6c`, que integra Main `7d65fcdb`.
- Docker: primera corrida integrada con Main `8ad32d2b`, 232 PASS/26 SKIPPED.
  Segunda corrida tras integrar Acceso Avance: **232 PASS/26 SKIPPED, cero
  fallos, 9,0 minutos**. Logs `gd-f4-e2e-docker[-main72]-20260922.log` en `/private/tmp`.
- 25 mutantes SQL, seis roles HTTP/Auth, paridad de dos equipos, tres carreras
  con esperas simultáneas observadas, horarios y navegador real PASS.
- Reconocer/posponer del libro anterior mediante HTTP y nuevas sesiones PASS.
  GET completo y escrituras separados: un fallo SLA inyectado no impide escribir.
- Tipos oficiales cotejados y gate del vigilante nuevo junto con F4 PASS.
- Dos dictámenes de Claude recuperados CHANGES_REQUESTED, resueltos por el
  PRIMARY con evidencia. No se atribuye PASS a Claude ni se hará una tercera
  consulta para buscarlo. [Resolución](F4-CIERRE-REVISION-FINAL-2026-09-22.md).
- Rama remota, RLS remoto, carga representativa, advisors después de instalar,
  merge, smoke autenticado productivo y primera jornada: **NOT RUN**.

Los dos índices INFO de política se difieren: tabla productiva de una fila,
lector por índice de vigencia existente y sin consulta por esas claves. No son
avisos de seguridad. Decisión/evidencia en el [acta](F4-CIERRE-EJECUCION-2026-09-22.md).

## Procedimiento y recuperación

1. Reconfirmar versión del sitio, Main y gates productivos por lectura; respaldar
   ledger y definiciones afectadas. Aplicar la conciliación aprobada antes de
   preparar la rama y cotejar que no cambió nada salvo la versión administrativa.
2. Crear `gestion-diaria-f4-cierre-20260922` sin datos. Verificar esquema, roles,
   configuración e historial contra producción. Si el replay histórico falla,
   reconstruir solo esa rama con esquema/fixtures controlados; no modificar
   producción para hacer pasar el banco. Mantener inactivos automatismos externos.
3. Aplicar los cuatro archivos exactos en esa rama; alinear sus versiones de
   ledger con los nombres canónicos si MCP asigna otra fecha, cotejando contenido.
   Probar matriz RLS, Auth/API, concurrencia, volumen representativo y advisors.
4. Antes de merge, diferencia de historial limitada a estos cuatro archivos y
   mismas versiones Edge. No incluir cambios de fixtures, cron ni configuración
   de aislamiento como migraciones productivas. Fusionar solo tras PASS.
5. Si falla un paso, inspeccionar el historial y gates antes de reintentar. Cada
   SQL es transaccional; no suponer que el merge entero de cuatro es atómico.
   Mientras el frontend anterior siga publicado y la política OFF, los objetos
   instalados pueden permanecer sin activar. No borrar auditorías para revertir.
6. Integrar el PR en `avancecorp/main`, comprobar Main/remoto idénticos y construir
   el artefacto final limpio. Publicar por Hostinger mediante `$release-crm` y
   cotejar bytes/manifest, acceso y protección de archivos internos.
7. Recuperación del frontend: ZIP vigente de Acceso Avance
   `crm-20260922T221443Z-7d65fcdb484f.zip`, SHA-256
   `bd9dc6c8dc10a55d5a314f862f75a45d9720b755401b84394e2976f85d891932`.
   Sus 107 archivos coinciden con el origen y `.htaccess` leído por Hostinger.
   Manifest y ZIP copiados a `releases/` de la copia aislada, fuera de Git/web root.
   Si el sitio cambia otra vez, obtener su respaldo antes de publicar.
8. Si ya hubiera cortes activos y se detecta un problema, pausar el canal con
   la configuración gerencial antes de recuperar el frontend. Los cálculos y
   asientos quedan conservados; corregir SQL con nueva migración si hace falta.
9. Eliminar la rama propia y comprobar su ausencia. Registrar coste y resultado.

## Activación posterior

Política actual confirmada: v1 OFF; corte 11:30 mínimo 3; corte 16:00,
incremento 150 %, piso 8 y techo 30; sábado mínimo 3. Umbrales bien 45 %,
atención 25 %, mínimo de llamadas útiles 5; tasa baja NULL.

Gerencia publicará una versión con esos parámetros y cortes ON para el inicio
de una jornada **posterior a la publicación verificada**, nunca retroactiva.
La fecha exacta se fija al ejecutar; si la entrega se retrasa, se mueve el inicio.
Verificar en la primera jornada: ambos cortes hábiles, sábado cuando corresponda,
una entrega por supervisor/corte, persistencia entre sesiones, un aplazamiento
de una hora, límites de jornada y acceso al registro. Registrar observaciones
reales; no sustituirlas por el banco sintético.

## Paquete de revisión local

Fuente limpia `7c4a8d6c73f9`, anterior a las actas finales; producto ya integrado
con Main `7d65fcdb`. ZIP de revisión:
`/private/tmp/gd-f4-candidato-main72/crm-20260922T224135Z-7c4a8d6c73f9.zip`, SHA-256
`212847f16e59b9349b9e8e8b5326c67293ec22b3d2a32cbb25c0c99ece1a5675`.
Manifest verificado. **No publicado; deberá reconstruirse desde el Main final.**

Las reglas que requieren el último permiso están en
[CRM/CLAUDE.md](../../CLAUDE.md#deploy) («con invocación humana»),
[release-crm](../../../.agents/skills/release-crm/SKILL.md) y
[LEEME de migraciones](../../supabase/migrations/LEEME.md) (rama → RLS → advisors → merge).
