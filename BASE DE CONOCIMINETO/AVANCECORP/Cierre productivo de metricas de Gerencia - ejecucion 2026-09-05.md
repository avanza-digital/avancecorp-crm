---
tags: [crm, gerencia, metricas, deploy, main, seguimiento]
requerimiento: REQ-GER-MET-001
fecha: 2026-09-05
estado: preparacion-validada-confirmacion-sql-exacto-pendiente
---

# Cierre productivo de métricas de Gerencia — ejecución

Relacionado con [[Plan de correccion de metricas de Gerencia - requerimiento vigente]], [[Plan por fases - cuatro datos de Gerencia - aprobado 2026-09-05]], [[Contrato tecnico de ampliaciones N1-N4 de Gerencia - 2026-09-05]], [[Auditoria final de Gerencia - punto 5 - avance 2026-09-05]] e [[Inicio]].

## Orden vigente

Miguel pidió ejecutar los seis pasos hasta publicar las mejoras, conservar el acceso y verificar las métricas, con núcleos intactos y sin calculadoras independientes. La publicación del frontend y el guardado/sincronización de Main están autorizados por esa orden. Sigue vigente la regla de mostrar primero el SQL exacto y recibir su confirmación antes de modificar producción: el GO conceptual anterior no sustituye esa confirmación.

## Preparación comprobada el 5 de septiembre

- `git fetch avancecorp main`: remoto actualizado sin divergencia; al comenzar, Main local `6a0d839` estaba un commit por delante de `avancecorp/main`. `origin` es otro proyecto y no se usa.
- Migración de Gerencia: `CRM-Avance-Corp/supabase/migrations/20260905155129_gerencia_contrato_cuatro_datos.sql`, SHA-256 `2b8430679c77219fd3de8df8fe3c23ee3a4c8b24147d34363473d9959d902bd0`. Coincide con el artefacto auditado; no se editó ni aplicó.
- Rollback: `CRM-Avance-Corp/supabase/scripts/rollback-gerencia-contrato-cuatro-datos.sql`, SHA-256 `c7886e7f3369d801e9f6845948c949d2f975eabc31d334e6e787bf395f24e021`. La prueba aislada mantiene SHA-256 `65957b31642e9779ac2a3c558e0a7c2ed9482b7ce9a9bdd34806ba97c5afb18d`.
- Consulta productiva de sólo lectura: las siete definiciones y sus propietarios/permisos coinciden con el preflight esperado. Los tres núcleos y las dos fachadas siguen intactos. Las declaraciones de los dos agregadores y el sello conservan el estado previo esperado. El censo global mantiene las incidencias heredadas documentadas; no se reparan ni se presentan como resueltas.
- Historial productivo: Gerencia N1–N4 aún no aparece aplicada. La exclusión de contratos de prueba del punto 3 sí está aplicada; no se reaplica.
- `npm run check`: salida 0 sobre el árbol actual; lint sin errores, tipos, cobertura, pruebas de configuración, build, bundle y duplicación aprobados. Caché de Vitest: 195 archivos y ninguno fallido. Las advertencias previas de accesibilidad y tamaño/importaciones del bundle no son nuevas. El número histórico de 2.819 pruebas no se reutiliza como recuento de esta nueva ejecución.
- Recorridos E2E completos con backend simulado loopback: salida 0, 121 aprobados y 26 omitidos por configuración, sin fallos (3,7 minutos). No ejecutan escrituras productivas.
- Revisión focal inicial de secretos en 61 archivos modificados/no versionados: cero coincidencias de llave privada, token GitHub, llave Supabase privilegiada/PAT o JWT service_role. No equivale a auditoría universal de secretos.
- Revisión repetida antes de preparar el commit: 65 archivos y cero coincidencias; se comprobó que cada contenido preparado coincidiera con su huella revisada. `git diff --cached --check` sólo observó siete líneas vacías finales en documentación/definiciones SQL del trabajo F2.b ajeno; se preservan sin reescribir sus fuentes verbatim.
- HTTP público sigue sirviendo `assets/index-CzsdYbLC.js`, correspondiente a la entrega anterior. La sesión existente de Gerencia entra y carga Resumen. Esta comprobación previa no certifica todavía el paquete nuevo ni un inicio de sesión nuevo con contraseña.

## Trabajo concurrente y alcance de publicación

Se preserva el trabajo de contratos/idempotencia y F2.b encontrado en Main. Guardar sus archivos no autoriza ejecutar sus migraciones, reparar duplicados, activar banderas ni modificar datos comerciales. El frontend de contratos transporta la clave opcional dentro del JSON existente y es compatible con el servidor anterior; su respuesta tolerante también conserva ese contrato. La idempotencia productiva no se afirmará como instalada por esta entrega.

La única migración candidata a aplicar en este requerimiento es `20260905155129_gerencia_contrato_cuatro_datos.sql`, después de su confirmación exacta. No se usa una aplicación global de migraciones. No se publica el portal `miavance.com`, ni Edge Functions, ni se cambia de Hostinger a otra plataforma.

## Estado de los seis pasos

1. Preparación y confirmación: preflight/reversión comprobados; SQL exacto pendiente de confirmación.
2. Main y artefacto: pruebas locales aprobadas; guardado, sincronización y paquete verificable en curso.
3. Servidor: pendiente del paso 1; no se aplicó SQL.
4. Frontend público: pendiente de verificar el servidor; no hubo deploy nuevo.
5. Conciliación real de N1–N4: pendiente de las versiones nuevas en producción.
6. Cierre: evidencia de preparación guardada; el requerimiento sigue abierto.

El objetivo permanece completo: no marcar 100 % por aprobar pruebas locales o guardar el código. Antes de aplicar se vuelve a leer el estado externo, porque hay trabajo concurrente.
