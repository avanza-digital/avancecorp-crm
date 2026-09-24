# Supervisor horizontal — entrega H6

**H6.1 y H6.2 CERRADAS. H6.3 pendiente; todavía no publicado ni aceptado.**

[Evidencia estructurada y huellas](SUPERVISOR-HORIZONTAL-H6-ENTREGA-2026-09-24.json).

## H6.1 · PR

[#87 — Comparar el equipo y consultar su actividad en una vista horizontal](https://github.com/avanza-digital/avancecorp-crm/pull/87)
quedó integrado el 24/09/2026 a las 05:42:18 UTC, Main `bbe341f6`, y reúne H1–H5. Explica el problema de filas altas/detalle inferior, el panel
lateral final, capturas antes/después con sus dimensiones y datos sintéticos,
decisiones de Pendientes/móvil y límites reales de validación.

El cambio conserva el ámbito del supervisor y las reglas de negocio. No
implementa F5/F6 históricas ni cierra la observación real de F4. La entrega
incluye el [acta H5](SUPERVISOR-HORIZONTAL-H5-EVIDENCIA-2026-09-24.md) y su
[revisión](SUPERVISOR-HORIZONTAL-H5-REVISION-2026-09-24.md).

## H6.2 · Fuente y recuperación

**PASS:** Main limpio y `avancecorp/main` idénticos en
`bbe341f6752b29e5e3e9305db3e0076d3cc11ce1`. Su árbol completo coincide con
el producto probado `788834cc`: `8e71ad9a2dc642eb63ac03ea674cd98ae39ef145`.
El PR #87 pasó app-check, preflight y verify en GitHub. Se conserva la
[evidencia de integración](evidencias-h6-2026-09-24/integracion-artefacto-bbe341f6.json).
La copia aislada mantiene el taller principal intacto:
`/private/tmp/avancecorp-release.hvdub4/repo`.

**PASS:** `npm run release:crm` y `release:crm:verify`, fuente limpia y destino
`crm.miavance.com`, con 116 archivos en el manifiesto.

- ZIP inicial: `crm-20260924T054601Z-bbe341f6752b.zip`, 2.300.351 bytes.
- SHA-256: `80ec656216a7404f033f7696b943aaba8a9d93524a17c3d622ef4c1d58bde8d2`.
- [Empaquetado](evidencias-h6-2026-09-24/release-bbe341f6-final.log) y
  [verificación](evidencias-h6-2026-09-24/verify-bbe341f6.log).
- ZIP y manifiesto preservados en el directorio durable indicado abajo.

El primer empaquetado se detuvo por configuración pública ausente. La copia
principal tiene demo habilitada para desarrollo: se reutilizaron sólo URL,
llave pública anon y DSN público opcional, con `VITE_ENABLE_DEMO=false` **sólo
para el proceso de release**. No se modificó su `.env`, no se imprimieron sus
valores ni se incorporaron credenciales privilegiadas. El gate productivo
confirmó URL/llave en el bundle y ausencia de fixtures demo. Los dos intentos
previos se conservan como fallos, no como aprobaciones.

Esta acta documenta el artefacto construido desde `bbe341f6`; no le atribuye
el commit posterior de documentación. Tras integrar las actas se reconfirmará
Main y se preparará, si cambia, otro paquete desde esa fuente limpia. El
manifiesto exacto de entrega y sus huellas se conservan también en
`entrega-final.json` del directorio durable. Revalidar fuente y servidor antes
de una publicación futura; un paquete preparado no es una publicación.

El respaldo inmediatamente anterior sí está identificado y preservado:

- Fuente viva: `e8e4f35f9ea1bc1b88da469ff45a998d7d40bb91`.
- Build: `build-20260923T204457952Z`.
- ZIP: `crm-20260923T204458Z-e8e4f35f9ea1.zip`.
- SHA-256: `ab631a4fac25c53c3d32bd49514c99d92c6420dd2c9b92c1a823a88a46f22de6`.
- [114 comprobaciones por HTTPS PASS](evidencias-h6-2026-09-24/respaldo-vivo-verificado.json):
  hashes de código/texto, imágenes servidas por CDN y bloqueo de `.htaccess`.
  `index.html` y `version.json` coinciden con el manifiesto. La fuente viva es
  ancestro del candidato; no se pierde una publicación paralela.
- ZIP y manifiesto copiados fuera de `/tmp` a
  `/Users/usuario/.local/share/avancecorp-checkpoints/supervisor-horizontal-h6-2026-09-24/`.

## H6.3 · Backend y publicación pendientes

SQL exacto revisable:
[`20260923234404_crm_gestion_diaria_pendientes_supervisor.sql`](../../supabase/migrations/20260923234404_crm_gestion_diaria_pendientes_supervisor.sql).
SHA-256 `a61d0b30be5781f9f04b6486b2eaa1599c9bcada5d2e5ce35ddab2bc7acdba73`.

Añade la lectura paginada de pendientes, extrae el helper común de ámbito y
adapta el núcleo del equipo a ese helper, con paridad verificada. No crea
tablas ni modifica políticas RLS. El 24/09, 04:58 UTC, la lectura del catálogo
productivo confirmó el MD5 previo requerido
`17b39a376af0f940f029937a6fa98186`; H3 no estaba instalada ni en el historial.
Ese [preflight](evidencias-h6-2026-09-24/sql-preflight.json) debe repetirse justo
antes de instalar, pues otra sesión puede cambiar el servidor.

Secuencia pendiente, en el entorno autorizado:

1. Ensayar la migración exacta en una rama Supabase propia, ejecutar la matriz
   RLS y advisors, y confirmar el presupuesto del banco antes de crearlo.
   La rama existente `banco-f7` es ajena y no se modifica. Los ensayos locales
   de H5 no se presentan como un gate hosted.
2. Integrar la RPC validada mediante el flujo aprobado del proyecto; evitar
   `apply_migration` directo a producción y un `db push` general.
3. Reconfirmar compatibilidad, fuente Main/remoto, manifiesto y respaldo.
   Publicar el ZIP compatible en **crm.miavance.com** mediante el skill de
   release y Hostinger; SQL primero, frontend después.
4. Verificar portada/assets/version tras recarga y acceso del supervisor a su
   equipo propio. Registrar lo observado sin sembrar llamadas o tareas reales.

El snapshot previo de [advisors de seguridad](evidencias-h6-2026-09-24/advisors-security-antes.json)
es una línea base, no un PASS del candidato instalado: 66 INFO y 224 WARN
agrupados, cero ERROR. Incluye funciones DEFINER accesibles por diseño,
extensión en public y configuración de contraseñas. No se alteran permisos o
configuración para hacer desaparecer avisos genéricos. Conservar los enlaces
de remediación del JSON al evaluar diferencias tras el ensayo autorizado.

La publicación está pendiente de la instrucción humana exigida por
[`CRM-Avance-Corp/CLAUDE.md`](../../CLAUDE.md):
«La publicación a crm.miavance.com se hace SOLO vía el skill de release, con
invocación humana: /release-crm en Claude o $release-crm en Codex».
El [skill](../../../.agents/skills/release-crm/SKILL.md) precisa:
«Esta habilidad publica frontend: no aplica migraciones pendientes ni un db push
general. Un backend incompatible pendiente debe resolverse con su autorización propia».
Preparar el PR y el artefacto no auto-invoca esa autorización.

## H6.4 · Aceptación real pendiente

El supervisor debe comprobar en su sesión: comparar personas sin perder la
tabla, identificar atención, abrir Registro/Pendientes y volver de una ficha
con menos desplazamiento. Falta registrar esa aceptación y cualquier corrección
derivada de uso real. Las capturas demo o el prototipo aprobado no la reemplazan.

El plan canónico, el mismo Figma y el vault reflejan **67/72 tareas completas**:
H1–H5 y H6.1/H6.2 cerradas, documentación H6.4 actualizada; cinco tareas
productivas/operativas pendientes. El seguimiento de F4 del 24/09 (11:30 y 16:00 Lima) y sábado 26/09
permanece separado; tasa baja sigue OFF. No hay cambios de TypeSafe/Jev.
