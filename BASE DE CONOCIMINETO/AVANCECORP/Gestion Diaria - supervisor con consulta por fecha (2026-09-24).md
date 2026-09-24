---
tags: [crm, gestion-diaria, supervisor]
fecha: 2026-09-24
estado: preparado y verificado en copia separada; sin publicar
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
jornada antigua se descarta. No hay cambios SQL, permisos ni publicación.

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
  `SUPABASE_URL` en el entorno del script. Aceptación humana y producción
  pendientes. Los E2E usan datos sintéticos y HTTP interceptado localmente.

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

## Retoma

- Rama local: `codex/supervisor-fecha-20260924`, base `a4d4775f`.
- Copia: `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop-worktrees/supervisor-fecha-20260924`.
- Evidencia durable y respaldo: `/Users/usuario/.local/share/avancecorp-checkpoints/supervisor-fecha-2026-09-24/`.
- La publicación y la integración con los cambios remotos siguen pendientes;
  no se construyó ni se publicó un artefacto de release.

[[Gestion Diaria - H6.3 publicada y aceptacion pendiente (2026-09-24)]] ·
[[Gestion Diaria - H5 verificada y H6 preparada (2026-09-24)]] · [[Inicio]]
