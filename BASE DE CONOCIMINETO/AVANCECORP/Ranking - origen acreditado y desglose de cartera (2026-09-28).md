---
tags: [crm, ranking, origenes, cartera, diagnostico]
fecha: 2026-09-28
estado: SQL y frontend publicados; verificación productiva PASS
---

# Ranking — origen acreditado y desglose de cartera

Miguel reportó una ficha de septiembre con Formulario S/ 7.500, Referido S/ 0
con conversión 7,50 %, Cartera S/ 90.000 y Sin origen S/ 190.000. Pidió
corregir el problema y ver renovación/upgrade dentro de Cartera.

## Causa comprobada con lecturas productivas

- S/ 130.000 de Formulario y S/ 15.000 de Referido tienen acreditaciones
  explícitas de la misma fuente y fecha comercial. Sus leads fueron cargados
  después del cierre, sin contrato_id. El lector de capital ignoraba el nuevo
  vínculo acreditado y seguía exigiendo un lead previo al cierre para el fallback
  por perfil. La conversión ya usa la acreditación: por eso podía verse porcentaje
  sin el capital correspondiente.
- Los S/ 45.000 restantes pertenecen a dos contratos categoría `nuevo` sin lead
  por contrato, perfil, documento ni inversionista, y sin operación de cartera
  vinculada. Ambos clientes tienen contratos anteriores activos en Avance.
  No tienen un predecesor renovado hacia esos contratos. Esto descarta una
  renovación registrada, pero NO demuestra que no sean aportes adicionales
  mal clasificados. Miguel pidió verificar, no conoce el canal; no se inventó
  un origen ni se recategorizaron contratos/operaciones.
- Cartera S/ 90.000 concilia con categorías confirmadas: Renovación S/ 10.000,
  Upgrade S/ 80.000. El frontend anterior agrupaba todo sin mostrar el reparto.

## Cambio publicado

`20260928163532_crm_ranking_origen_acreditado.sql`: helper de lectura privado,
acreditación activa/elegible, fuente y fecha exactas; fallback únicamente después
de vínculo directo, perfil anterior y cartera legada. Ambigüedades conservadas.
Sin nuevas claves RPC ni cambios a importes, categorías, vendedor, conversión o
fotos selladas. Actualiza solo la huella de la declaración analítica existente.

UI: lee las categorías del cumplimiento existente, recupera ajustes de cierre
para comparar con el bruto de orígenes y muestra Renovación/Upgrade solo cuando
cuadran por moneda en céntimos. Si cartera legada conserva categoría financiera
`nuevo`, informa que el desglose no está disponible, sin fabricar un reparto.
Walking queda escrito correctamente. No se instala una segunda fórmula monetaria.

SELECT candidato READ ONLY sobre el universo real: 143 filas antes/después,
36 canales recuperados, cero diferencias en capital, moneda, categoría,
operación o vendedor. Para la captura, el resultado productivo verificado es:

| Grupo | Importe |
|---|---:|
| Landing | S/ 0 |
| Formulario | S/ 137.500 |
| Referido | S/ 15.000 |
| Walking | US$ 25.000 |
| Cartera | S/ 90.000 |
| Sin origen identificado | S/ 45.000 |

Con TC 3,3776 conserva S/ 371.940. Porcentajes intactos.

## Verificación y límites

- `npm run check`: PASS, 4.740 pruebas/313 archivos, typecheck, build, bundle y
  duplicación. Cuatro avisos de accesibilidad preexistentes en coverflow.
- E2E Docker focal: 2/2 PASS; capturas escritorio/móvil, móvil inspeccionado.
- SQL local de componentes: 13 casos, política inactiva, paridad monetaria y ACL
  del helper PASS. Dependencias sintéticas; NO es replay íntegro de la migración.
- Preflight de lectura productivo: inventario analítico sin pendientes,
  sello válido, declaración existente y techo 14.
- `gate:realidad`: NOT RUN por falta de URL/service role en su entorno.
  El diagnóstico productivo puntual sí se ejecutó con MCP en READ ONLY.
- Miguel autorizó expresamente el deploy desde esta conversación; esa autorización
  incluye la corrección preparada y sustituye la necesidad de invocar literalmente
  `$release-crm`. Ensayo remoto, merge nativo y publicación completados.

## Revisión independiente

Claude, una revisión efectiva (el primer intento falló por entorno de red):
CHANGES_REQUESTED, confianza media. PRIMARY incorporó guardas de ocurrencia única
en los reemplazos, recuento exacto de la actualización de huella, casos de 15:30 y
23:30 Lima y un grupo accesible alrededor del dl de cartera.

El P1 era condicional a una cadena SECURITY INVOKER: se cerró con lectura viva
de las tres funciones (RPC, ranking_origen_live y lector), todas SECURITY DEFINER
propiedad de postgres; el helper también declara ese propietario. El preflight
ahora comprueba esa cadena. RLS HTTP posterior PASS en rama, incluidos escenarios acreditados activos.

La hipótesis de modificación retroactiva de meses sellados se rechazó con el
cuerpo de ranking_origen_vendedor_fn: su rama cerrada lee exclusivamente
cierre_mes_vendedor.origenes_ranking. No recalcula mediante ranking_origen_live.
El tipo de fecha ya es date por conversión explícita America/Lima; se añadieron
los casos de hora extrema para comprobarlo. No se pidió otra opinión para
obtener PASS; el dictamen original se conserva como CHANGES_REQUESTED con los
hallazgos evaluados por PRIMARY.


## Publicación del 28/09/2026

- SQL integrado con **merge nativo** de la rama exclusiva
  `ranking-origen-acreditado-20260928` (`1a6cefa5-a746-4e59-9337-24ba6b058469`).
  Producción pasó de 380 a 381 migraciones: solo `20260928163532` añadida.
  SHA-256 SQL: `df4eb9e7496a8406a60a24ba13717286d2ae1f802bf1a50430d055e13755fa40`.
- Snapshot inmediatamente antes/después: 144 filas de septiembre, **36 canales
  recuperados**, cero cambios de importes/monedas/categorías/operaciones/vendedor.
  Huellas completas de contratos, cuotas, acreditaciones y fotos cerradas idénticas.
  Las 22 Edge Functions conservaron versiones, fechas, JWT y hash de artefacto.
  Control analítico: 0 pendientes antes/después. Lector final MD5
  `2770f326df798e511a1d81b1e0ca8af7`.
- Rama reconstruida sin copiar clientes: el replay histórico se detiene en la
  versión 86. Se importaron estructura, historial y controles actuales, dejando
  Cron apagado. El exportador omitió seis líneas de comentario de una función;
  se restauró su definición exacta antes de verificar el sello. Datos de prueba
  exclusivos y ficticios; no se incluyeron en las migraciones.
- `apply_migration` ejecutó el DDL pero falló al registrar el historial por faltar
  el índice único de idempotencia de la rama reconstruida. Se verificó el
  postflight y la huella aplicada; se reparó únicamente ese índice y se registró
  el mismo SQL exacto en la rama. No se repitió el DDL ni se aplicó SQL directo
  a producción. Merge nativo asíncrono, confirmado por lectura posterior.
- Matriz RLS de Ranking, baseline y candidata: PASS. Auth/PostgREST real:
  gerencia/supervisor permitidos; ajeno/inactivo/cliente/anónimo denegados;
  SQL de conciliación, cierre y permisos PASS. Caso adicional: tres contratos
  acreditados tardíos, PEN y USD, paridad exacta con política activada; HTTP de
  gerencia, supervisor y vendedor PASS, equipo ajeno denegado.
- Advisors sin avisos nuevos: seguridad 306 → 306; rendimiento 304 → 286
  (18 índices dejaron de aparecer como no utilizados al ejercitar el banco).
  No se afirma que el inventario global esté libre de deuda preexistente.
- Suite Docker completa: 275 passed, 4 flaky, 26 skipped, 1 failed. El fallo era
  un recorrido antiguo de Gerencia, corregido para abrir «Registro general»,
  como la pantalla ya publicada requiere. Focal final Gerencia/Ranking:
  **11 passed, sin reintentos**. Un intento intermedio se atascó limpiando
  resultados antiguos del bind mount; con salida aislada en `/tmp` pasó en 25,9 s.
  El producto es el mismo que pasó `npm run check` (4.740); el commit posterior
  solo cambia ese test E2E. No se deshabilitó ningún test ni se amplió su timeout.
- Front publicado con [release-crm](../../.agents/skills/release-crm/SKILL.md).
  URL: https://crm.miavance.com. Fuente limpia: `c33e94d26cf41c3467265b8cfb2ef97c1bc1fc0c`.
  Copia limpia: `/private/tmp/ranking-release-20260928`.
  Build: `build-20260928T171106059Z`.
  ZIP: `CRM-Avance-Corp/releases/crm-20260928T171107Z-c33e94d26cf4.zip`.
  SHA-256: `ac0be5c7b969bcdfd32354a093a19beb595814ebb97c4e9dc8ab74f05d6cd0c3`.
- Artefacto y preflight PASS contra el vivo `4e85c9038728`. Hostinger aceptó
  la publicación vía operación oficial `hosting_deployStaticWebsite` de la
  instalación local, con sesión OAuth existente renovada; ninguna configuración
  MCP ni proveedor cambiados. El adaptador temporal conserva el preflight.
- **Smoke HTTP PASS a las 12:27:51 Lima**: portada 200; 80 archivos JS/CSS/index/
  version con bytes y SHA-256 idénticos al manifiesto, sin cache-busting.
  No se crearon datos reales para probar. Recorrido visual autenticado en
  producción NOT RUN; prueba de pantalla Docker y verificación HTTP sí PASS.
- Recuperación conservada: `crm-20260928T155351Z-4e85c9038728.zip` y manifiesto.
  No se ejecutó rollback.
- Se conserva la decisión previa de Miguel de mantener Gloria/portal solo en
  local. Main local y GitHub tienen historiales distintos por esa exclusión:
  no se hizo push del main local completo. Integración CRM sobre `avancecorp/main`,
  con `app/` byte a byte idéntico al commit publicado y sin los archivos excluidos.
- Rama temporal eliminada tras el smoke PASS. Inicio 16:59 UTC, eliminación
  alrededor de 17:29 UTC: costo estimado cercano a US$0,007, no una factura.
  Evidencia privada: `/private/tmp/ranking-acreditado-remoto-20260928`.

Los S/45.000 sin origen siguen pendientes de evidencia comercial. No se presentan
como renovación/upgrade ni se recategorizan automáticamente.

Relacionado con [[Ranking - capital por canal de llegada (decision 2026-09-25)]],
[[Ranking cartera - publicacion verificada (2026-09-26)]],
[[Conversion - publicacion verificada (2026-09-27)]] y
[[Plan por fases - inversion por empresa y ranking de cartera (2026-09-26)]].
