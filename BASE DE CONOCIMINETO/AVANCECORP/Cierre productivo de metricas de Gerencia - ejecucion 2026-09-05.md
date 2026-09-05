---
tags: [crm, gerencia, metricas, deploy, main, seguimiento]
requerimiento: REQ-GER-MET-001
fecha: 2026-09-05
estado: sql-productivo-verificado-publicacion-frontend-en-curso
---

# Cierre productivo de métricas de Gerencia — ejecución

Relacionado con [[Plan de correccion de metricas de Gerencia - requerimiento vigente]], [[Plan por fases - cuatro datos de Gerencia - aprobado 2026-09-05]], [[Contrato tecnico de ampliaciones N1-N4 de Gerencia - 2026-09-05]], [[Auditoria final de Gerencia - punto 5 - avance 2026-09-05]] e [[Inicio]].

## Orden vigente

Miguel pidió ejecutar los seis pasos hasta publicar las mejoras, conservar el acceso y verificar las métricas, con núcleos intactos y sin calculadoras independientes. La publicación del frontend y el guardado/sincronización de Main están autorizados por esa orden. Posteriormente respondió **«si» a la pregunta expresa de aplicar el SQL exacto enlazado**. Esa confirmación ya se recibió y ejecutó; no volver a pedirla ni confundir los estados históricos siguientes con el estado actual.

## SQL productivo aplicado y comprobado — 12:53 Lima

- Se aplicó únicamente el contenido aprobado mediante una migración individual, sin ejecutar las migraciones ajenas. Supabase la registró como `20260905175342_gerencia_contrato_cuatro_datos`; el archivo local se renombró al mismo identificador para mantener el historial alineado. El contenido conserva exactamente SHA-256 `2b8430679c77219fd3de8df8fe3c23ee3a4c8b24147d34363473d9959d902bd0`; su nombre al presentarlo era `20260905155129_gerencia_contrato_cuatro_datos.sql`.
- Preflight, transacción y postflight terminaron correctamente. Lectura posterior: agregador de conversión `be4e1c283a1f3042828cbb8c66332252`, agregador de citas `6e8935eae3cf1a4c049a93cb20e1f3bd`. Los tres núcleos y dos fachadas mantienen sus cinco huellas anteriores, propietarios y ACL. El postflight confirmó censo ajeno intacto y sólo dos declaraciones actualizadas.
- Advisors posteriores idénticos a la línea base: 180 de seguridad y 77 de rendimiento, sin alertas agregadas ni retiradas.
- Consultas de sólo lectura por las fachadas, con rol `authenticated` y perfil activo de Gerencia: del 1 al 3, base automática 176, llegadas únicas 185, 8 manuales y 1 referido; numerador 9, conversión 5,11 %. Del 1 al 5: base 298, llegadas 312, numerador 9 y conversión 3,02 %.
- N1: 4 leads de septiembre con cita registrada como realizada; no los 24/25 inferidos por avance. N2: presencial 2/13 computables = 15,4 %; virtual 4/19 = 21,1 %, con 4 cancelaciones de sistema excluidas. Total operativo de citas: 37 pactadas y 6 realizadas; es otra población, no una contradicción con N1. N3: dos upgrades seleccionados, aporte total 2, sin renovaciones en este rango. N4: 7 cierres y aporte 7, sin mezclar las dos operaciones ni atribuir residuales a otros analistas.
- La conexión anterior del navegador integrado dejó de estar disponible antes de la comprobación visual posterior. Se pidió reconectarla mientras continúan las pruebas y el deploy; no afirmar acceso visual posterior todavía.
- Las 113 pruebas focales de los cambios concurrentes del frontend aprobaron. La primera ejecución falló por el `localStorage` nativo de Node 26, no por la lógica; se repitió con `NODE_OPTIONS=--no-experimental-webstorage` para que los procesos de prueba usen el almacenamiento de jsdom. No se modificó la aplicación por ese conflicto del entorno.

## Preparación comprobada el 5 de septiembre

- `git fetch avancecorp main`: remoto actualizado sin divergencia; al comenzar, Main local `6a0d839` estaba un commit por delante de `avancecorp/main`. `origin` es otro proyecto y no se usa.
- Migración de Gerencia: `CRM-Avance-Corp/supabase/migrations/20260905155129_gerencia_contrato_cuatro_datos.sql`, SHA-256 `2b8430679c77219fd3de8df8fe3c23ee3a4c8b24147d34363473d9959d902bd0`. Coincide con el artefacto auditado; no se editó ni aplicó.
- Rollback: `CRM-Avance-Corp/supabase/scripts/rollback-gerencia-contrato-cuatro-datos.sql`, SHA-256 `c7886e7f3369d801e9f6845948c949d2f975eabc31d334e6e787bf395f24e021`. La prueba aislada mantiene SHA-256 `65957b31642e9779ac2a3c558e0a7c2ed9482b7ce9a9bdd34806ba97c5afb18d`.
- Consulta productiva de sólo lectura: las siete definiciones y sus propietarios/permisos coinciden con el preflight esperado. Los tres núcleos y las dos fachadas siguen intactos. Las declaraciones de los dos agregadores y el sello conservan el estado previo esperado. El censo global mantiene las incidencias heredadas documentadas; no se reparan ni se presentan como resueltas.
- Historial productivo: Gerencia N1–N4 aún no aparece aplicada. La exclusión de contratos de prueba del punto 3 sí está aplicada; no se reaplica.
- `npm run check`: salida 0 sobre el árbol candidato; lint sin errores, tipos, cobertura, pruebas de configuración, build, bundle y duplicación aprobados. El hook posterior de push repitió la suite y confirmó **194 archivos / 2.819 pruebas aprobadas**. La caché acumulada de Vitest no se usa como recuento de ejecución. Las advertencias previas de accesibilidad y tamaño/importaciones del bundle no son nuevas.
- Recorridos E2E completos con backend simulado loopback: salida 0, 121 aprobados y 26 omitidos por configuración, sin fallos (3,7 minutos). No ejecutan escrituras productivas.
- Revisión focal inicial de secretos en 61 archivos modificados/no versionados: cero coincidencias de llave privada, token GitHub, llave Supabase privilegiada/PAT o JWT service_role. No equivale a auditoría universal de secretos.
- Revisión repetida antes de preparar el commit: 65 archivos y cero coincidencias; se comprobó que cada contenido preparado coincidiera con su huella revisada. `git diff --cached --check` sólo observó siete líneas vacías finales en documentación/definiciones SQL del trabajo F2.b ajeno; se preservan sin reescribir sus fuentes verbatim.
- HTTP público sigue sirviendo `assets/index-CzsdYbLC.js`, correspondiente a la entrega anterior. La sesión existente de Gerencia entra y carga Resumen. Esta comprobación previa no certifica todavía el paquete nuevo ni un inicio de sesión nuevo con contraseña.

## Versión candidata guardada y paquete comprobado

- Commit realizado y subido: `5ada0c566517fc4b3296508cf7d6c166655f642d`, 65 archivos. Main local y `avancecorp/main` coincidían, con árbol limpio; se confirmó también por `git ls-remote` antes de construir. Push normal, sin ramas nuevas ni force push.
- Construcción desde checkout separado y limpio en `/tmp/crm-gerencia-release.50pzcp`, HEAD detached de ese mismo commit. `npm ci` usó el lockfile; sólo se inyectó la configuración pública de producción, con llave `anon` y demo deshabilitada. No se copiaron archivos `.env` ni se imprimieron credenciales.
- Release candidato: `crm-20260905T173351Z-5ada0c566517`; build `build-20260905T173351122Z`; ZIP de 1.878.922 bytes y SHA-256 `bf2f075374b47a287e8c6e256422ec47967312f1f1b2866e423d9742c9009826`, conservado junto a su manifiesto en `CRM-Avance-Corp/releases/`.
- Se verificaron **76/76 archivos del ZIP**, sus tamaños/huellas y ausencia de entradas extra. La configuración pública exacta está incorporada; no se encontraron credenciales privilegiadas; `.htaccess` coincide con el release vivo. El gate existente confirma Ficha 360 y ausencia de fixtures demo/pdfmake en producción.
- Preview del artefacto: pantalla «Inicia sesión», correo/contraseña y botón Entrar habilitado. No se introdujeron credenciales. Preview detenido después; checkout y artefactos conservados.
- Reversión frontend actual verificada: `crm-20260905T043212Z-50f33a59b92b.zip`, SHA-256 `131f17db0f2cf1fe1d0dc33d57cea1cd5209269e5a13c329b457469a83e1ef67`. Se comprobó que su commit sea antepasado del candidato.
- CI del candidato: `CRM RLS preflight` [33981243445](https://github.com/avanzadigitald/avancecorp-crm/actions/runs/33981243445) aprobado; `CRM app quality` [33981243470](https://github.com/avanzadigitald/avancecorp-crm/actions/runs/33981243470) **terminó con success**, tanto calidad como E2E. Se consultó el mismo run vivo hasta comprobar su estado terminal; no se reinició.
- Advisors previos de producción: seguridad 0 ERROR, 141 WARN, 39 INFO; rendimiento 0 ERROR, 5 WARN, 72 INFO. Son la línea base anterior al cambio, no incidencias reparadas ni certificación global de seguridad.
- El SQL exacto se presentó a Miguel mediante enlace al archivo auditado. **Confirmación aún pendiente.** La autorización de publicar el frontend ya existe; no volver a pedirla.

Después de guardar y construir aparecieron nuevas ediciones concurrentes de contratos/idempotencia y pruebas F2.b. Se preservaron sin sobrescribirlas. El paquete anterior sigue siendo una fotografía comprobada de `5ada0c5`, no una certificación de esas ediciones posteriores: antes del deploy final se debe revisar/integrar lo nuevo, comprobar nuevamente Main y reconstruir si cambia el código que va a publicarse. No afirmar que el árbol de trabajo actual permanece limpio.

Revisión de continuidad: la v2 de contratos conserva la RPC y añade persistencia de la clave de reintento y mensajes de confirmación; su propio handoff declara pruebas adicionales pendientes. No se la certifica por el CI de `5ada0c5` ni se implementa/aplica su SQL dentro de Gerencia. Las referencias a `main:tronco` de ese handoff no son el destino vigente: prevalece `AGENTS.md`, exclusivamente `avancecorp/main`. La migración y rollback de Gerencia conservan sus huellas exactas. Sigue sin existir una confirmación humana del SQL de Gerencia; una continuación automática del objetivo no la sustituye.

## Trabajo concurrente y alcance de publicación

Se preserva el trabajo de contratos/idempotencia y F2.b encontrado en Main. Guardar sus archivos no autoriza ejecutar sus migraciones, reparar duplicados, activar banderas ni modificar datos comerciales. El frontend de contratos transporta la clave opcional dentro del JSON existente y es compatible con el servidor anterior; su respuesta tolerante también conserva ese contrato. La idempotencia productiva no se afirmará como instalada por esta entrega.

La única migración candidata a aplicar en este requerimiento es `20260905155129_gerencia_contrato_cuatro_datos.sql`, después de su confirmación exacta. No se usa una aplicación global de migraciones. No se publica el portal `miavance.com`, ni Edge Functions, ni se cambia de Hostinger a otra plataforma.

## Estado de los seis pasos

1. Preparación y confirmación: completadas; confirmación humana del SQL recibida.
2. Main y artefacto: versión candidata guardada, sincronizada, construida y comprobada, con CI completo aprobado; falta revisar los cambios concurrentes posteriores antes de la versión final.
3. Servidor: SQL aprobado aplicado y respuestas, núcleos, permisos y advisors comprobados.
4. Frontend público: pendiente de verificar el servidor; no hubo deploy nuevo.
5. Conciliación real de N1–N4: pendiente de las versiones nuevas en producción.
6. Cierre: evidencia de preparación guardada; el requerimiento sigue abierto.

El objetivo permanece completo: no marcar 100 % por aprobar pruebas locales o guardar el código. Antes de aplicar se vuelve a leer el estado externo, porque hay trabajo concurrente.
