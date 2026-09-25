---
tags: [crm, gestion-diaria, supervisor]
fecha: 2026-09-24
estado: publicado y verificado en producción
---

# Gestión Diaria — consulta por fecha del supervisor

Miguel pidió que el supervisor pueda elegir el día que necesita para su gestión
comercial. Autorizó separar esta corrección al detectarse otra tarea modificando
el taller principal. Sus seis archivos iniciales se trasladaron por huella a la
copia autorizada y se retiró únicamente ese diff del taller.

La cabecera ofrece «Fecha de gestión» y «Hoy». Inicia en hoy, hora de Lima, y
consulta desde hoy hasta 365 días atrás: es el rango que ya admite el servidor.
La misma fecha alimenta indicadores, llamadas por hora, últimas gestiones,
registro individual, registro del equipo y resultados de los cortes. Se
conservan búsqueda y filtros; cambiar de fecha cierra y reinicia el detalle.

El equipo y los pendientes siguen siendo actuales, según el contrato existente;
se indica al consultar otro día. Los avisos operativos siguen correspondiendo
a hoy. Abrir su registro devuelve primero la consulta a hoy; un pedido de una
jornada antigua se descarta. No hay cambios SQL ni permisos.

La entrada nativa conserva el año parcial mientras se escribe y solo consulta fechas
válidas. Una fecha incompleta o fuera del rango vuelve a la última consulta al
salir del campo. La región anuncia el día con año. Las citas del detalle dicen
«Citas pendientes del día».

## Verificación

- **PASS:** `npm run check` en la copia separada: 287 archivos, 4.281 pruebas;
  lint, TypeScript, cobertura, configuración, service worker, build, bundle y
  duplicación. Advertencias de lint preexistentes, sin errores.
- **PASS:** 56 pruebas focalizadas: cambios de mes, rango y hora de Lima,
  respuesta tardía, conservación de filtros, reinicio de páginas, vacío/error,
  corte histórico → registro/foco, aviso de hoy durante carga y rechazo de
  pedidos antiguos.
- **PASS:** 20 E2E Docker focalizados, cero fallos, un worker y sin reintentos
  (1,6 minutos). Escritorio, móvil, teclado, indicadores y registro por fecha,
  regreso a hoy y regresiones de supervisor/cortes/pendientes. Capturas
  inspeccionadas. La pasada
  anterior con dos workers coincidió con el gate de cobertura y se detuvo al
  saturarse Docker; no se acredita como PASS.
- **NOT RUN:** `gate:realidad`, no llegó a consultar por falta de
  `SUPABASE_URL` en el entorno del script. Los E2E usan datos sintéticos y HTTP
  interceptado localmente; el recorrido técnico real posterior se registra abajo.
  No sustituye la aceptación humana general de H6.4.

Una revisión independiente con `scripts/claude-review` emitió
**CHANGES_REQUESTED / MEDIUM**. Su hipótesis P2 motivó conservar la edición
nativa del año y verificarla en Chromium. Una sonda mínima también detectó
que `locator.press` reenfoca el campo entre teclas y reinicia el año incluso
sin React: la prueba escribe con `page.keyboard.type` sobre el foco existente.
Se agregó el año al
anuncio, se mantuvo la restricción de avisos a hoy y se cubrieron sus caminos
de carga y los cortes históricos. Se conserva el refresco cada minuto porque
el equipo y los pendientes son actuales. El texto de día no laborable sirve
también para hoy. No se atribuye un segundo dictamen al reviewer.

CodeGraph se consultó primero, pero su índice no ubicó los símbolos nuevos;
se completó con lecturas puntuales del código y del contrato SQL existente.
No se actualizó el índice ni se modificaron migraciones.

## Publicación del 24/09/2026

Miguel autorizó publicar y eligió esperar la aprobación en GitHub, sin excepción
de administrador. El [PR #89](https://github.com/avanza-digital/avancecorp-crm/pull/89)
quedó integrado por `miguejbs98` el 24/09 a las 16:11:52 UTC. Los controles
`cambios`, `app-check` y `verify` terminaron **PASS**. La copia de publicación
tenía `main` limpio, siguiendo `avancecorp/main`, ambos en el mismo commit antes
de construir y antes de subir. El árbol completo del código probado en
`a58ffdbdacd23ef2d1dd8760a8279d10bc9195a7` coincide con el integrado.

- URL: <https://crm.miavance.com/#/gestion-diaria>.
- Fuente publicada: `929fbbcccb5710e1031f734a034e8ce90a79b0b2`.
- Build: `build-20260924T161347948Z`.
- ZIP: `crm-20260924T161348Z-929fbbcccb57.zip`, 116 archivos.
- SHA-256: `36892449306963561b85f5ed39ecc4fff6c48335aa72c6f7f140af5b59736991`.
- Manifiesto: `crm-20260924T161348Z-929fbbcccb57.manifest.json`.
- **PASS:** `release:crm`, `release:crm:verify` y preflight con respaldo publicado
  anterior identificado. Hostinger aceptó una sola publicación mediante
  `hosting_deployStaticWebsite`; la versión servida confirma el build indicado.

### E2E completo, cerrado en varios tramos

El inventario contiene 277 casos: **251 casos distintos aprobados y 26 omisiones
previstas; ninguno pendiente**. No fue una ejecución única sin interrupciones.
El intento principal terminó con 220 aprobados, 4 fallidos, 1 interrumpido,
26 omitidos y 26 sin ejecutar cuando coincidieron otras pruebas en Docker.
La recuperación exacta de los 31 casos restantes aprobó 4; una nueva ejecución
concurrente provocó un timeout y dejó otros 26 sin ejecutar.

Miguel autorizó dar prioridad a esta publicación. Se detuvo temporalmente solo
el contenedor de pruebas `avancecorp-venta-cruzada-e2e-dedicado`; no se detuvieron
las bases de datos. Los **27 restantes aprobaron en 3,7 minutos**, un worker,
cero reintentos y sin cambios de código. La prioridad temporal terminó con
esa ejecución. Se conservan también los logs fallidos e interrumpidos; no se
presentan como pruebas aprobadas.

### Verificación posterior

- **PASS:** portada, `index.html`, versión estable y 115 archivos públicos con
  HTTP 200. Los 77 JS/CSS y 103 de los 115 archivos públicos coinciden byte a
  byte con el manifiesto. Los 12 PNG restantes son variantes servidas por la
  CDN: PNG íntegros y sus originales en el servidor coinciden con el manifiesto,
  comprobados por HTTPS con TLS validado. `.htaccess` coincide mediante lectura
  Hostinger, restituyendo el salto de línea final recortado por la API.
- **PASS:** sesión real de supervisor en Chrome: fecha inicial 24/09; elección
  por teclado del 23/09 y carga de actividad histórica; «Registro del equipo»
  mostró «Registro de actividad del 2026-09-23»; «Hoy» restituyó el 24/09 y
  «Mi equipo hoy». Pantalla dejada en hoy. El aviso inicial se cerró con
  «Cerrar sin reconocer»; no se reconoció ni pospuso, ni se crearon datos.
- **NOT RUN:** `gate:realidad`, según el límite descrito arriba. La aceptación
  humana general de H6.4 conserva su estado en la nota correspondiente.

## Evidencia y recuperación

- Rama local: `codex/supervisor-fecha-20260924`, base `a4d4775f`.
- Copia: `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop-worktrees/supervisor-fecha-20260924`.
- Evidencia durable y respaldo: `/Users/usuario/.local/share/avancecorp-checkpoints/supervisor-fecha-2026-09-24/`.
- Cierre: `entrega-final.json`; recibo Hostinger, HTTP, PNG de origen, `.htaccess`,
  recorrido real y logs de los tres tramos E2E en esa carpeta.
- Respaldo publicado anterior: `crm-20260924T054601Z-bbe341f6752b.zip`, SHA-256
  `80ec656216a7404f033f7696b943aaba8a9d93524a17c3d622ef4c1d58bde8d2`;
  conservado con manifiesto en el checkpoint `supervisor-horizontal-h6-2026-09-24`.
- Esta acta posterior no cambia la fuente del artefacto publicado ni requiere
  otra publicación. El taller principal y los cambios de otras tareas se
  conservaron separados.

[[Gestion Diaria - H6.3 publicada y aceptacion pendiente (2026-09-24)]] ·
[[Gestion Diaria - H5 verificada y H6 preparada (2026-09-24)]] · [[Inicio]]
