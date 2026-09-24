# Supervisor horizontal — entrega H6

**H6.1–H6.3 CERRADAS. SQL y frontend publicados y comprobados. H6.4 pendiente de aceptación humana.**

[CRM publicado](https://crm.miavance.com/#/gestion-diaria) · [Evidencia y huellas](SUPERVISOR-HORIZONTAL-H6-ENTREGA-2026-09-24.json).
El plan suma **70/72 tareas completas**. El recorrido técnico con una sesión
real de supervisor no sustituye su conformidad de uso.

## H6.1 · PR integrado

[PR #87](https://github.com/avanza-digital/avancecorp-crm/pull/87), integrado el
24/09 a las 05:42:18 UTC, reúne H1–H5: tabla compacta, panel lateral y franja
de avisos. Conserva el ámbito del supervisor y las reglas de negocio.
[H5](SUPERVISOR-HORIZONTAL-H5-EVIDENCIA-2026-09-24.md): **4.274 pruebas / 287 archivos**,
gate integral PASS; Docker local **249 aprobadas / 0 fallos / 26 omitidas**,
sin retries. La revisión H5 y sus correcciones están documentadas allí.

## H6.2 · Fuente, artefacto y recuperación

Main limpio y `avancecorp/main` coincidían en
`bbe341f6752b29e5e3e9305db3e0076d3cc11ce1` al construir y justo antes de publicar.
Su árbol completo `8e71ad9a2dc642eb63ac03ea674cd98ae39ef145` coincide con el
producto probado `788834cc`. CI, `release:crm` y `release:crm:verify` PASS.
La publicación identifica ese commit; las actas posteriores no cambian su fuente.

- ZIP publicado: `crm-20260924T054601Z-bbe341f6752b.zip`, 2.300.351 bytes, 116 archivos.
- Build: `build-20260924T054600240Z`.
- SHA-256: `80ec656216a7404f033f7696b943aaba8a9d93524a17c3d622ef4c1d58bde8d2`.
- Respaldo anterior: `crm-20260923T204458Z-e8e4f35f9ea1.zip`, fuente `e8e4f35f9ea1bc1b88da469ff45a998d7d40bb91`.
- SHA-256 del respaldo: `ab631a4fac25c53c3d32bd49514c99d92c6420dd2c9b92c1a823a88a46f22de6`.
- Respaldo cotejado por 114 controles HTTPS; ZIP y manifiesto fuera del web root.

El release usó únicamente configuración pública del cliente y
`VITE_ENABLE_DEMO=false` para ese proceso. El `.env` del taller principal no
se modificó. Los primeros empaquetados fallidos se conservan en las evidencias
previas. La copia aislada es `/private/tmp/avancecorp-release.hvdub4/repo`;
no se mezcló trabajo ajeno del taller principal.

## H6.3 · Backend primero, frontend después

Miguel autorizó explícitamente H6.3, banco hasta US$1, la SQL exacta y
`$release-crm`, y después confirmó continuar de forma autónoma.

**Migración inmutable:**
[`20260923234404_crm_gestion_diaria_pendientes_supervisor.sql`](../../supabase/migrations/20260923234404_crm_gestion_diaria_pendientes_supervisor.sql),
SHA-256 `a61d0b30be5781f9f04b6486b2eaa1599c9bcada5d2e5ce35ddab2bc7acdba73`.
Se ejecutó el ciclo **rama Supabase propia → apply exacto → RLS → advisors → merge nativo**.
No se aplicó directamente a producción ni se hizo un `db push` general.

El banco `lqongqxaviavfusnzojv` se creó sin datos. Su replay histórico inicial
falló; se reconstruyó la base sintética y se cotejaron **740 funciones, 122 tablas
y las 347 entradas históricas** antes de H3. Se compararon cuerpos, propietarios,
ACL, RLS, políticas, roles, Storage/Auth y controles técnicos. Sólo se normalizó
la asociación de paréntesis de tres CHECK; se preservó su predicado. Las consultas
de metadatos usaron UTC. Cron del banco permaneció deshabilitado.

- **RLS alojada:** baseline **2.226/0** y candidato **2.226/0**.
- **SQL específico:** paridad de todo el JSON de equipo para supervisor,
  gerencia/global, puente inactivo y ciclo; 1.008 tareas, 11 páginas, tres anclas,
  errores, revocación, concurrencia y siete mutantes PASS.
- **Auth/API reales del banco:** cinco actores sintéticos; 1.008 tareas en 11
  páginas, referencia mínima, roles/ámbito ajenos denegados y revocación con el
  mismo JWT PASS. El primer intento devolvió 1.007 porque la matriz dejaba
  `resolver_en_puertas=false` y ocultaba postventa. Se corrigió la preparación
  del fixture, manteniendo las aserciones, y se restauró la bandera al terminar.
  No cambió código de producto ni se usaron datos reales.
- **Tipos:** generados desde el banco instalado; contrato H3 idéntico al cliente.
- **Advisors:** ningún hallazgo nuevo de seguridad o rendimiento al cierre.
  Persisten avisos anteriores; esto no significa cero advertencias. Los INFO
  sobre índices sin uso variaron por la restauración y por la matriz.
  [Resumen y enlaces de remediación](evidencias-h6-2026-09-24/publicacion/advisors-resumen.json).
- **Revisión:** la misma SQL ya tenía revisión H3 PASS. El intento adicional
  con `scripts/claude-review` terminó con salida incompleta, sin VERDICT válido;
  se registra **INCOMPLETE**, no PASS. No se omitió el wrapper ni se repitió para
  obtener un dictamen favorable. El PRIMARY decidió con la evidencia de los gates.

El merge nativo fue asíncrono. La primera lectura aún veía el esquema anterior;
se esperó `FUNCTIONS_DEPLOYED` y se verificó la instalación real.
Producción: **348 migraciones y 744 funciones**. Las 347 entradas anteriores,
incluidas sus seis columnas de metadatos, siguen idénticas. La nueva entrada
contiene 22 sentencias: el merge divide el fichero, pero cada fragmento conserva
literalmente su contenido; sólo cambian delimitadores y espacios entre sentencias.
Las cuatro funciones nuevas y las tres modificadas coinciden con el candidato;
el resto del catálogo, tablas, permisos y 21 Edge Functions permanece intacto.
Gates productivos de Gestión Diaria, Pendientes, analítica y vigencia PASS.

La pantalla anterior cargó el equipo correctamente con H3 instalada.
Después, Hostinger aceptó el ZIP a las **07:13:31 UTC (02:13:31 Lima)**.
[Verificación HTTPS](evidencias-h6-2026-09-24/publicacion/publicacion-https.json):
**116/116 PASS**, portada y JS principal correctos, 104 hashes exactos,
11 imágenes transformadas por CDN y `.htaccess` bloqueado. ZIP fuera del acceso
público (404); versión descargada idéntica al manifiesto.

[Recorrido productivo](evidencias-h6-2026-09-24/publicacion/recorrido-supervisor-publicado.json):
Chrome con sesión preexistente de supervisor y su equipo propio. Diez filas
visibles de 44 px a 1512 × 805, panel lateral y ausencia de desborde horizontal;
Resumen, atención, Registro y Pendientes funcionan. Pendientes amplía 25 → 50;
abrir una ficha y volver conserva persona, pestaña y las 50 tareas. Búsqueda y
orden conservan el panel; a 1200 px el detalle adaptado se cierra con Escape.
Registro mostraba el vacío real de hoy. No se crearon gestiones ni se ejecutaron
reconocimientos/posposiciones para probar. Las capturas con datos reales no se
copiaron a Git ni a Figma; se conserva sólo evidencia anonimizada.

**Banco eliminado y ausencia verificada a las 07:13:47 UTC.** Tarifa cotizada
US$0,01344/h; coste estimado **US$0,01743**, por debajo del tope US$1 (no es factura).
`banco-f7` quedó intacto. También se retiraron el archivo privado de credenciales
y el clon local exclusivo H6; los bancos H3/F4 anteriores se conservaron.

## H6.4 · Siguiente paso

Faltan la conformidad del supervisor sobre comparar personas, detectar atención
y consultar actividad con menos desplazamiento, y los ajustes que surjan de
esa revisión. **No atribuir aceptación humana al recorrido técnico anterior.**
VoiceOver/NVDA, Safari y CLI `gate:realidad` siguen NOT RUN con los límites de H5.

El mismo Figma, el plan y el vault registran **70/72**: H6.3 cerrada, dos tareas
H6.4 pendientes y 76 casillas históricas intactas. El seguimiento real de F4
(24/09 a las 11:30 y 16:00 Lima y sábado 26/09) permanece separado. Tasa baja OFF;
TypeSafe/Jev sin cambios.

[PR #88 de actas](https://github.com/avanza-digital/avancecorp-crm/pull/88)
conserva la entrega documental y requiere la revisión humana de GitHub.
La publicación de producto ya está realizada; no se publica otra vez sólo por
integrar estas actas. Directorio durable:
`/Users/usuario/.local/share/avancecorp-checkpoints/supervisor-horizontal-h6-2026-09-24/`.
Incluye ambos ZIP/manifiestos, evidencias saneadas, bundle Git y `entrega-final.json`.
