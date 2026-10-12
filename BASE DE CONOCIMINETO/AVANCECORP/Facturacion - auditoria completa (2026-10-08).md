---
tags: [facturacion, auditoria, crm]
fecha: 2026-10-08
---

# Facturación — auditoría completa (08/10/2026)

Auditoría de **solo lectura** del módulo Facturación tal como quedó publicado hoy (commit `0d9f8f3b`, build
`build-20261008T152511280Z`, ver [[Tope de referidos y publicar Facturación - RETOMAR (2026-10-08)]]; historia del
módulo en [[Facturacion - modulo del dueno en produccion (2026-09-13)]]).
Cinco frentes en paralelo con agentes y worktrees aislados: cifras · mundo de producción · seguridad por rol ·
pantalla y accesibilidad · código, mutantes y velocidad. Luego Miguel corrió en producción seis consultas
`begin transaction read only; … rollback;` (exit 0) y Codex revisó los hallazgos (r1: BLOCK por Directorio,
rechazado con evidencia; ajustes de severidad aceptados). **No se tocó código ni datos.**

## Veredicto
Las **cifras son verdad**: el servidor cuadra con la fuente al céntimo (sep y oct, por mes × moneda × tipo y por
analista) y Facturación «Todos» = Resumen de Gerencia = Gráficas. La **seguridad por rol** está bien en producción
(4 supervisores sin fuga ni faltantes; analista, coordinador, cliente y dado de baja → vacío; anon → 42501; huella
viva = migración). **Velocidad** sobrada (32 ms en el servidor; PostgREST media 46 ms, máx. 150 ms; 184 de 1000
filas). Lo flojo es la **pantalla** (un % engañoso, móvil del supervisor, cabecera, reglas de Miguel), un fallo
**latente** de atribución al dar de baja a un supervisor, y **datos de origen** mal etiquetados.

## Hallazgos (severidad final, tras Codex)

### P1
1. **El % del primer KPI no es de su cifra.** En «Soles» o «Dólares», con dólares en el mes, el titular es el total
   unificado en soles y el % se calcula sobre la moneda de la vista (`facturacion.tsx:694-715` vs `725-741`). Misma
   cifra S/ 6.914.310 con −11,9 % / −15,4 % / +10,5 % según la vista. Sin test.
2. **Baja de supervisor con reemplazo → ventas mal atribuidas (LATENTE).** `crm.fijar_membresia_activa_fn`
   (`20260925180145:520-522`) mueve a los subordinados con UPDATE directo y solo registra `membresia_desactivada`;
   Facturación reconstruye el «supervisor de entonces» solo con `jerarquia_actualizada`
   (`20260916205617:148-180`). Efectos: ventas nuevas al supervisor que salió; quien no tiene eventos (14 activos)
   pasa al reemplazo con toda su historia (meses cerrados cambian de equipo); el reemplazo ve ceros sin aviso.
   Producción hoy: 0 bajas con traslado, pero ya hay 2 derivas de jerarquía sin evento (Carmen Jaramillo y Jorge
   Marzano: jefe hoy «Administrador» y según su último evento «Carlos Valles»).
3. **Supervisor en celular no ve ningún día**: nombres (208 px) + total (128 px) llenan la región; el ajuste móvil
   (`pwa-gerencia.css`) solo vive en el diseño de Gerencia.
4. **En escritorio la cabecera de días no queda fija** (región `overflow-auto` sin altura máxima, `:1339`); el
   texto de ayuda dice que sí (`:1658`).
5. **Ningún número lleva a sus contratos** (regla «todo número se abre»): solo la celda analista×día y el nombre
   abren un desglose por tipo y moneda. Debe cubrir TODOS los números (KPI, %, promedio, total convertido).

### P2
6. **«Capital nuevo» lleva upgrades**: 12 contratos con `categoria='nuevo'` que en cartera son upgrades —
   **S/ 2.092.254 + US$ 54.971**— (septiembre muestra solo S/ 729.173 en Upgrades). Es dato de origen compartido
   con Metas/Ranking; sube a P1 si Miguel decide que manda la operación de cartera.
7. **Sin tipo de cambio**: el KPI muestra solo soles rotulado «Total facturado» y el pie «—»; el aviso con
   «Reintentar» (`:1306-1322`) es código muerto. La Edge del TC ya falló en septiembre.
8. **Perfil vendedor de pruebas `d731f284` cuenta**: S/ 5.000 + US$ 5.000 (sep) y S/ 3.800 + US$ 21.000 (oct)
   (contratos 2026-01-001391, 001463, 001549, 455468 + una cooperativa de S/ 800). Además 2026-01-111111 (S/ 1.000,
   notas de prueba). Miguel confirmó el 23/09 que ese perfil es solo de pruebas (memoria del proyecto); falta su
   decisión sobre estas ventas.
9. **Posible duplicado** S/ 90.000: mismo cliente y mes, contratos 2026-01-001490 y 001484.
10. **Cooperativa mezcla reinversiones**: 10 no iniciales (S/ 97.300 + US$ 10.000) entran enteras.
11. **Reglas de pantalla**: KPI en tarjetas de 196 px (no pastillas), sin columna #, sin tarjetas en celular,
    letra 9–13 px, 23 columnas de días futuros vacías, vista Día con ~930 px vacíos, siglas «TC», «SBS · prom. 7d»
    y «M» (martes/miércoles), «Todo S/» sin decir que lleva dólares convertidos, panel de celda que no cuadra en
    Todo S/, contraste 4,24:1 y 3,55:1.
12. **Pruebas**: 11 de 43 mutantes sobreviven (3 sobre reglas visibles: promedio del mes en curso, % con filtro,
    detalle en Todo S/); sin spec e2e (la RPC ni está simulada: 500); fuera del gate de realidad;
    `supabase/scripts/test-facturacion.sql` no está enganchado a ningún script ni CI; `listarFacturacionDiaria`
    sin test.

### P3
Promedio = S/ 0 en un tramo de solo domingo (hubo ventas los domingos 13/09 y 20/09); semana que cruza de mes cuenta
días futuros; divisor según el mes del ancla; «Sin supervisor» repetido si el supervisor pierde el rol (0 casos);
el mes de comparación bloquea la malla; ~40 ms de formateo sin memo; mes cerrado re-pedido cada 5 min; trabajo
descartado en el servidor; código muerto y componente de 1.333 líneas; septiembre se mueve por borrados duros
(≥9 contratos borrados y recreados; 2026-01-001378 S/ 60.000 sin recrear); comentario «espejo» de `roles.ts`
inexacto (Directorio); a11y menores (foco 1,81:1, h1→h3, `ul` sin `role=list`).

### Rechazados (con evidencia)
- **Codex P1 «Directorio ve todo»**: decisión documentada en `20260910230000:26-30` («solo Gerencia describe el
  menú, no la RPC»); `private.es_lector_global()` = rol `directorio` (`20260828210351:173-196`) y 139 migraciones
  lo tratan como lector global. Queda P3 por el comentario.
- **«Lo anulado suma»**: decisión ATR-4 (`lib/facturacion.ts:17-20`), no defecto.

## Plan de arreglos (orden ajustado con Codex)
0. **Decisiones de Miguel (sin código)**: ¿el tipo lo manda la operación de cartera (12 contratos)? ¿el perfil de
   pruebas y 2026-01-111111 son pruebas? ¿001490/001484 es duplicado? ¿abrir Facturación a Directorio?
   → ✅ **decididas el 08/10**: [[Facturacion - fase 0 decisiones de datos (2026-10-08)]] (manda la operación de cartera;
   las ventas de prueba son pruebas; 001490/001484 NO son duplicado; Directorio SÍ ve Facturación, hecho en la PR #229).
   Las correcciones de datos esperan su OK sobre las filas exactas.
1. **Solo pantalla**: % coherente con el titular (1), sin-TC coherente con reintento visible (7), móvil del
   supervisor (3), cabecera fija (4), siglas/rótulos/contraste, domingo y semana cruzada, tests que maten los 3
   mutantes y spec e2e mínimo con la RPC simulada. → ✅ **PR #229** (CI verde, falta fusionar y publicar).
2. **Servidor, LEVEL 3 con plan y OK**: (2) evento de jerarquía en TODA vía que cambie `crm.equipo`, en la misma
   transacción y sin duplicar las vías que ya emiten; **sin relleno a ciegas** (un evento inventado reasigna meses
   cerrados: el primer `antes` rige desde `-infinity`, y `antes = NULL` cae al supervisor de hoy); caso en
   `test-facturacion.sql` enganchado al gate; RPC de alarma solo `service_role` para el gate de realidad.
   → 📋 plan escrito: [[Facturacion - plan fase 2 jerarquia en toda via (2026-10-08)]] (6 vías, solo 2 emiten;
   recomienda un trigger en `crm.equipo` como único escritor; 4 decisiones de Miguel).
3. **Servidor + pantalla**: (5) detalle de TODOS los números + rediseño tipo Excel (pastillas, #, tarjetas, letra).
   → 📋 plan escrito: [[Facturacion - plan fase 3 numeros y hoja Excel (2026-10-08)]] (núcleo único para cifra y lista,
   pantalla en 8 pasos, 7 decisiones de Miguel) · pieza visual `ui-playground/facturacion-hoja-excel.html`.

## Fase 1 (solo pantalla) — ✅ PUBLICADA 08/10 ~19:07 Lima (`build-20261009T000618000Z`, `faa65d1c`, PR #229, incluye Directorio)

Release `crm-20261009T000618Z-faa65d1ccb35` (157 archivos): check 6.460 PASS, manifiesto OK, preflight OK (vivo `0d9f8f3b` → `faa65d1c`), MCP de la sesión; smoke: home 200, `index-LLpoNkpB.js` = dist, 144 archivos idénticos (los 12 PNG los recomprime el CDN).

Rama `crm/facturacion-fase1-pantalla`, commit **`c0bff295`** sobre `0d9f8f3b`, en el worktree
`AVANCECORP-desktop-worktrees/facturacion-fase1-20261008` (7 archivos, +1.034 / −91). Cierra los hallazgos 1, 3, 4, 7 y
el % (11), siglas, promedio, rótulos de «Todo S/», panel con la suma y contraste. Las reglas móviles de la malla pasan
de `pwa-gerencia.css` (solo Gerencia) a `screens/facturacion-movil.css` (todo rol).
- `npm run check` PASS (6.460 tests); 16 tests nuevos (11 fallan con el código anterior; 4 matan mutantes que
  sobrevivían); e2e `e2e/facturacion-realidad.spec.ts` en Docker local: 7 passed (6 fallan con el código anterior).
- Revisor a11y: 4 P2 aplicados (foco al reintentar, foco bajo la cabecera fija, cabeceras de fin de semana opacas,
  contraste del pie). Codex r1: BLOCK → 2 aceptados (días futuros marcados en el divisor, singular de la tasa) y 1
  rechazado con evidencia (el e2e busca el «Reintentar» del panel de error, `estado-panel.tsx:38-41`).
- El primer `git push` lo frenó el hook `pre-push` con «1 error» suelto de vitest; repetido a mano: 6.460 tests sin
  error. Con el OK de Miguel («sigamos») se subió (el `pre-push` pasó limpio) y se abrió la **PR #229**: https://github.com/avanza-digital/avancecorp-crm/pull/229
- Pendiente fuera de la fase: «SBS» se deja (nombre de institución); aviso translúcido en modo comparar, «Equipo de…»
  a 4,2:1, `ul` sin `role=list` y el anillo de foco sistémico (previos al cambio).

## Lecciones
- Un agente dejó un script local **destructivo** (`drop schema if exists crm cascade`) dentro de la carpeta de SQL
  que iba a producción. El runner tenía guarda (solo corre archivos que abren con `begin transaction read only;` y
  cierran con `rollback;`) y lo habría saltado, pero se apartó a `repro-local-NO-PROD/`. Separar siempre repro
  local y SQL de producción, y no confiar en una sola guarda.
- Al encargar a Codex una auditoría de permisos, **transcribir las decisiones aceptadas** (cabeceras de las
  migraciones): sin ellas marcó como P1 una apertura deliberada.
- Leer producción lo deniega el clasificador: se resuelve con consultas de solo lectura que Miguel corre con `!`
  (`correr-sql-prod.sh`), nunca rodeándolo.

## Evidencia (scratchpad de la sesión, no versionado)
Informes `1-cifras.md` … `5-codigo.md`, SQL `sql/*.sql`, salidas de producción `salida/*.json`, 13 capturas,
tests de reproducción `repro/`, encargo y respuesta de Codex (`encargo-codex.md`, `codex-r1.txt`).
