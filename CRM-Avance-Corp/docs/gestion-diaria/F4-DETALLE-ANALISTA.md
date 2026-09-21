# F4 · Etapa 2 — Detalle del analista

Fecha: 21/09/2026. Estado: **PUBLICADA Y VERIFICADA; etapa 2 cerrada técnicamente**.
Plan principal: [GESTION-DIARIA.md](GESTION-DIARIA.md).
Publicación anterior: [PUBLICACION-2026-09-21.md](PUBLICACION-2026-09-21.md).
Miguel invocó `$release-crm`, aprobó el PR #64 y se publicó la fuente
`baa63aea`. Conformidad visual local registrada; recorrido humano productivo
pendiente. Preflight real, artefacto y verificación HTTP en
[F4-ETAPA2-PUBLICACION-2026-09-21.md](F4-ETAPA2-PUBLICACION-2026-09-21.md).

## Alcance y decisiones

Se completa el detalle de la fila del supervisor, no se crea una segunda
pantalla de «Mi día». La foto del equipo ya contiene `marcador.por_hora`; el
registro F1 ya pagina las actividades y `abrirLead` ya relee la ficha bajo RLS.
Se reutilizan esas puertas y no se crea ni modifica ninguna migración.

El detalle muestra los indicadores existentes y el reparto de llamadas y
contestadas de 08 a 20 horas de Lima. Las horas exteriores se enumeran con sus
conteos. El gráfico y el texto proceden de la misma foto; si los conteos horarios
no cuadran, se muestra un aviso y el acceso al registro, no barras falsas a cero.

«Ver llamadas del día» abre la pestaña Llamadas del analista. «Ver registro» en
su fila abre Todo, para no ocultar notas o WhatsApp bajo un título general.
«Ver registro del equipo» conserva Llamadas, igual que la versión publicada;
no se cambió la entrada de gerencia. No se ofrece
«Todos los analistas» cuando la entrada está fijada a una persona. La ficha se
abre por el flujo existente, incluso fuera de la carga inicial; volver conserva
el registro, sus filtros, la fila desplegada y el foco.

Cada apertura explícita reaplica la pestaña solicitada, aunque se hubiera
cambiado manualmente antes. Un fallo transitorio de la consulta del equipo no
desmonta el registro ni roba su foco al recuperarse. Una revocación o salida
confirmada del equipo sí lo cierra, anuncia el motivo y devuelve el foco si
estaba dentro; no lo reabre automáticamente después.

La tipografía del registro compartido pasa a 16 px y sus acciones a un mínimo
de 44 px, con las pestañas grandes ya existentes. Cargando, vacío filtrado,
vacío del ámbito consultado, error de lectura y falta de autorización son
estados distintos. Un `42501` oculta y elimina la memoria de páginas anteriores;
los filtros/cursor tampoco cruzan identidad, rol, modo demo, día o ámbito.

Se detectó mediante E2E un fallo real en el refresco: al regresar desde página 2,
la primera podía seguir fresca durante los 30 segundos de la caché general y no
salía una petición. El hook de registro fija `staleTime: 0` y una prueba protege
la reconsulta al volver a esa página. No cambia el intervalo de un minuto.

Diseño: se mantienen los tokens del CRM (navy `#111e3d`, azul `#2563eb`, blanco
`#ffffff`, fondo claro `#f6f8fc`, ámbar `#d97706` como referencia de familia,
con su token de texto contrastado). Plus Jakarta Sans; alineación izquierda;
indicadores en rejilla y desglose horario bajo una separación dentro del mismo
detalle, sin añadir otro tablero. Los conteos no dependen de color ni tooltip.
La región horaria admite foco y desplazamiento con las flechas; cada hora tiene
texto para lector de pantalla. En móvil las pestañas forman dos columnas para
no recortar «WhatsApp» al mantener los 16 px.

### Semántica confirmada en el SQL existente

`private.gestion_diaria_llamadas`, en
`20260920041500_crm_gestion_diaria_analista.sql`, usa la misma ventana semiabierta
del día de Lima y los tipos `llamada_realizada`/`llamada_no_contestada` que el
registro. No obstante, el total `contestadas` excluye número errado/otra persona
y el desglose horario cuenta por tipo. Para datos históricos pueden diferir:
se admite y explica esa diferencia sólo si no supera las llamadas no útiles.
Totales de llamadas incompletos, horas repetidas, valores inválidos o diferencias
de contestadas imposibles siguen mostrando aviso, nunca barras inventadas.

`private.registro_actividad_core` también hace `JOIN crm.leads` bajo RLS; la foto
de llamadas no hace ese JOIN. El registro tiene otro instante de lectura y sólo
puede listar actividades de leads actualmente visibles. No se promete igualdad
absoluta de conteos entre ambas RPC: el detalle explica esta limitación y el
registro dice «gestiones cargadas», no un supuesto total definitivo. El fixture
E2E de 26 llamadas verifica navegación/paginación, no paridad SQL productiva.

## Aislamiento y fuente

Trabajo en `/private/tmp/avancecorp-gd-f4-vista.chvRqh`, el taller preexistente;
no se creó un worktree nuevo. Rama local `codex/gestion-diaria-f4-detalle-analista`,
base `b0d2ff89`. Este commit remoto y la base inicial `5e538358` tienen el mismo
árbol Git (`ebe80f2a90591dc20a7b28bcc109604b3ce8a336`); se conservó el checkpoint
y la corrección de Pipeline sin escribir en el taller principal concurrente.

La candidata se reconcilió con Main preservando sus cierres previos y las
ediciones ajenas. La autorización nueva `$release-crm` y la aprobación del
PR #64 permitieron publicar `baa63aea` desde una copia limpia, con Main y
remoto iguales. No se reutilizó la autorización de la entrega anterior.

## Verificación

- PASS: `npm run check`, 271 archivos y 4.051 pruebas; lint, tipos, cobertura,
  configuración de release, push, build, bundle y duplicación. Permanecen cuatro
  warnings de accesibilidad preexistentes en `coverflow-carousel.tsx`; no se
  introdujeron warnings en los archivos de esta entrega. Lint se repitió tras
  documentar la excepción de foco necesaria para desplazar la región horaria
  con teclado. El build conserva su aviso de tamaño de chunk; no bloquea el gate.
- PASS: tres E2E de equipo, incluido detalle → registro → ficha ausente del boot
  → vuelta con foco, denegación al releer una ficha ya conocida, paginación y
  revocación; comprobación tipográfica de 16 px y ancho móvil de 390 px.
- PASS: suite E2E completa, 232 pruebas aprobadas y 26 omisiones preexistentes,
  cero fallos, con cuatro workers y backend de pruebas interceptado en loopback.
- PASS: `git diff --check` y los 12 enlaces nuevos del plan, acta y vault.
- NOT RUN: `npm run gate:realidad` no pudo medir (falta `SUPABASE_URL` y no se
  introdujeron credenciales). Comprobación complementaria de solo lectura vía
  conector: 2.095 leads activos, 14.135 actividades, 1.205 tareas pendientes,
  18 analistas activos, 3 supervisores y 488 actividades del día al corte. No
  sustituye todos los supuestos del gate ni prueba permisos de cada identidad.
- NOT RUN: nuevo smoke visual humano, VoiceOver y matriz Auth/HTTP productiva.
  No había navegador interactivo conectado; se inspeccionaron las capturas
  generadas por Playwright. Las pruebas de backend interceptado son pruebas de
  frontend y no se presentan como ensayos nuevos de RLS real.

Capturas regenerables con `npm run test:e2e -- e2e/gestion-diaria-equipo.spec.ts`:
`detalle-horario.png`, `registro-detalle.png`, `registro-detalle-movil.png` y las
vistas de equipo de escritorio/móvil y `registro-actividad-movil.png`, dentro de
`app/test-results/`. Son
artefactos locales ignorados, no evidencia de publicación.

## Revisión independiente y decisión del PRIMARY

Se realizó una revisión con Claude Code mediante `scripts/claude-review`, como
`SECONDARY_REVIEWER` sin herramientas ni permisos de escritura. Dictamen sobre
la primera candidata: **CHANGES_REQUESTED**, confianza MEDIUM-HIGH. No se repitió
la consulta buscando un PASS; Codex contrastó cada hallazgo con código y pruebas.

Se aceptaron y corrigieron la reapertura que conservaba otra pestaña, el desmontaje
por error transitorio y la falta de desplazamiento horario con teclado. Se
añadieron pruebas unitarias y E2E para esos recorridos, más el cierre con aviso
al perder ámbito. Se centralizó la franja 08–20, se añadieron tests directos del
predicado horario, encabezados identificados por analista, texto accesible por
hora y aviso no urgente. Se restauró Llamadas para el registro general del equipo.

No se aceptó como defecto demostrado la hipótesis de una caché de equipo sin
rol: `data/gestion-diaria-equipo-queries.ts::claveDiaEquipo` ya incluye actor,
rol y día; el hook sólo devuelve la foto a un supervisor y separa demo de real.
`lib/query-client.ts::instalarLimpiezaCacheAutenticacion` borra la caché al perder
sesión/rol. El discriminador adicional del registro es defensa en profundidad;
no se rediseñó la fábrica de claves de F3 sin una reproducción del supuesto fallo.

La hipótesis de escala `NaN` se descartó: `barrasPorHora` ya usa `Math.max(1, …)`;
ahora una prueba protege el caso de todas las llamadas fuera de franja. La fecha
ya está contrastada por `data/gestion-diaria-api.ts::obtenerDiaEquipo`, que
rechaza una respuesta con día o supervisor diferente. El barrido tipográfico
del E2E de equipo ya incluía el detalle desplegado; se conserva junto con el del
registro. La paleta utiliza los tokens existentes de navy y azul, sin verde.

El riesgo del selector global de analistas es previo: la entrada nueva usa el
ID de la fila autorizada y oculta ese selector, sin reconstruir conteos desde el
store. No se amplía esta etapa a rediseñar el ámbito global F1. Se mantiene
`staleTime: 0` en el registro para volver a consultar al abrir/actualizar; una
prueba reproduce el fallo con caché fresca y verifica su corrección. No se
cambian el intervalo ni el comportamiento de las otras consultas.

La observación sobre diferencias entre RPC se resolvió leyendo el SQL y
explicando sus límites arriba y en pantalla, no forzando conteos iguales.
Además, una comprobación móvil nueva reprodujo el recorte de «WhatsApp» y
verifica que el texto queda dentro del botón tras la corrección de la rejilla.

## Límites y siguiente paso

Sin nuevas SQL, Edge Functions, reglas de contacto, tareas o datos de negocio.
No se modificó el formulario de llamada aprobado ni la ficha de supervisión.
No se implementaron cortes, avisos automáticos, configuración de gerencia ni
TypeSafe. La vista sigue siendo «hoy», sin añadir selector histórico.

Miguel revisó la vista local y expresó conformidad visual el 21/09 («ok listo si
me gusta que sigue?»). La publicación se autorizó después por separado y ya
está verificada. Los permisos y la paginación se comprobaron con cinco
identidades SQL reales, sin escrituras. Siguen NOT RUN el recorrido humano
autenticado, VoiceOver, la matriz general Auth/HTTP y el script `gate:realidad`
completo; sus causas y la evidencia alternativa constan en el acta de publicación.
La siguiente implementación del plan es F4 etapa 3. Su activación conserva las
decisiones pendientes: mínimo del sábado, analistas sin cartera y límites del
aplazamiento. No se inventan esas decisiones ni se adelanta la activación.
