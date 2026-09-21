# GESTIÓN DIARIA — el documento único

> **Este archivo es el ÚNICO que hay que leer para retomar el módulo.** Reúne el estado, el plan
> por fases y el diseño técnico de los cortes, que antes vivían en tres documentos separados.
> Unificado el 20/09/2026 a petición de Miguel.
>
> **Para retomar, di: «retomemos gestión diaria F4».**

Al lado, en la misma carpeta, quedan las fuentes que NO se editan:

| Archivo | Qué es |
|---|---|
| `PLAN.md` | El encargo original de Miguel, tal como llegó. Histórico. |
| `UI-UX-playbook.pdf` | El playbook de diseño del proyecto. |
| `mockups/` | Los 6 mockups del encargo. **`4-analista-mi-dia.html` está SUPERADO** por el rediseño del 20/09: no es la referencia de «Mi día». |

## Índice

1. **Dónde estamos y cómo retomar** — estado por fase, decisiones selladas, qué falta.
2. **El plan por fases** — F0 a F6, con los objetivos de las seis etapas de F4 y el añadido F4.1 de TypeSafe. Dentro: «Lo que la Fase 3 cambió del plan» (gobierna F4 y F5) y «Lo que este plan YA NO dice».
3. **Diseño técnico — los cortes del día (F4)** — modelo de datos, puerta y cálculo, revisado por Codex.

---

# 1 · Dónde estamos y cómo retomar

Este archivo es el punto de entrada para seguir el módulo en otra sesión. El plan aprobado
completo está al lado: `PLAN.md` (el encargo original del handoff,
los 6 mockups y el playbook UI/UX en `mockups/` y `UI-UX-playbook.pdf`). Para retomar, di:
**«retomemos gestión diaria F4»**.

### Último punto de control — solicitud de publicación del 21/09/2026

Miguel aclaró «Implementar F4 etapa 3 y preparar su publicación» y autorizó
ensayar el candidato únicamente en `gestion_diaria_f4_vista_chvrqh`, incluida
su reversión. La solicitud no se registra como una publicación realizada.

**F4 etapas 1–2:** publicadas; la última entrega funcional de este módulo sigue
siendo `baa63aea` / PR #64. No repetir sus migraciones ya instaladas.

**F4 etapa 3:** implementada y verificada en local; publicación preparada, no ejecutada.
Candidato `20260921214018_crm_gestion_diaria_cortes.sql`: política versionada OFF,
cálculo de servidor con horas Lima, mínimos, base fija, cartera vacía y pruebas
de límites/permisos. Instalación, mutantes, regresiones, tipos, censo y reversión
ensayados; la base local termina sin cortes instalados. Aplicación: 4.073 tests
y `npm run check` PASS. [Entrega y límites](F4-CORTES-JORNADA.md). Después
corresponden alertas y aplazamiento (etapa 4), configuración (etapa 5) y validación/
activación (etapa 6). No ejecutar una migración ajena ni un `db push` general.

**F4.1:** banco ficticio local preparado, 38 pruebas offline y `check:scripts` PASS
en `8f1d009d`; no es una integración productiva. Su servidor local A/B no autentica
supervisores ni implementa permisos de equipo. Compartirlo fuera de la máquina es
otro alcance que debe precisarse, no una sustitución de `crm.miavance.com` por el
banco de práctica. Faltan comprobación en navegador y sesión humana; para notas
reales siguen pendientes clave renovada y condiciones acordadas.

**Acción de esta solicitud, ya aclarada:** implementar y verificar la etapa 3,
con Claude como reviewer, y preparar su publicación; no compartir el banco ficticio.
El ensayo del SQL candidato recibió autorización sobre la copia local exacta.
No se publica ni se activa todavía. La publicación posterior del CRM
mantiene el flujo humano `$release-crm`, sus gates y la conciliación con
`avancecorp/main`, preservando el trabajo concurrente.

### Objetivos y estado por fase

**F0 — Cimientos.** Preparar una base visual y técnica común para todo el módulo: Plus
Jakarta Sans, pestañas, selección de opciones y exportación CSV reutilizables, con su
documentación. Entregada en producción; evidencia: PR #29.

**F1 — Módulo y registro de actividad.** Permitir consultar qué se registró durante el día,
filtrar por analista, tipo y etapa, y revisar la evidencia dentro del ámbito autorizado.
Incluye paginación y exportación CSV para gerencia. Entregada en producción; evidencia:
PR #34, puerta `crm.registro_actividad_fn` y SQL `20260919211958`, instalada y registrada
el 20/09.

**F2 — Resultado tipificado de llamada.** Conseguir que cada llamada tenga uno de los siete
resultados definidos y que su siguiente paso quede resuelto: seguimiento, descarte con
submotivo, «No insistir» o las opciones aplicables al caso. Incluye Deshacer durante 24 horas
para los efectos admitidos. Entregada en producción; evidencia: PR #38, acta PR #41,
puertas `crm.registrar_llamada_v3` y `crm.deshacer_resultado_llamada`, SQL `20260920005000`
instalada el 20/09, frontend `crm-20260920T034405Z-afc391974382` y build
`build-20260920T034404914Z`.

Ampliación aprobada el 21/09: **resultado y descarte se separan**. El formulario
contrae los otros seis resultados al elegir uno, ofrece «Cambiar resultado» y
permite agendar desde «No le interesa» y «Pide otro producto». **PUBLICADA el
21/09/2026** tras autorización expresa del SQL y del release, aprobación e
integración del PR #62. Puerta `crm.registrar_llamada_v4`, migración
`20260921153654_crm_resultado_llamada_seguimiento.sql` instalada y registrada.
Fuente publicada: `526e728e31ff64adaf9b737fa5e408ebe32005a2`. Detalles, revisión,
pruebas y límites: [RESULTADO-LLAMADA-SEGUIMIENTO.md](RESULTADO-LLAMADA-SEGUIMIENTO.md).
No confundir esta mejora transversal de F2/F3 con el cierre de F4.

**F3 — Analista «Mi día».** Ayudar al analista a saber a quién atender ahora y qué le queda
pendiente, con una única acción principal y una cola completa en cuatro pestañas. Su actividad,
horas y descartes quedan en un segundo nivel, conservando un piso tipográfico de 16 px.
Completa en producción el 20/09; evidencia: SQL `20260920041500`, tres releases de frontend
y PRs #42, #44, #47, #50 y #51.

**F4 — Supervisor «Mi equipo hoy».** Permitir que el supervisor detecte quién tiene actividad
registrada, quién tiene pendientes y dónde debe intervenir, sin ocultar a los analistas con
cero actividad. Se construye en seis etapas: vista del equipo, detalle del analista, cortes
de jornada, alertas y seguimiento, configuración gerencial, y validación y activación.
La etapa 1 está **PUBLICADA el 21/09**, con SQL `20260921040335` instalado y
registrado. Main local y `avancecorp/main` coincidieron en `526e728e` antes de
construir y publicar una copia limpia de ese commit. Acta de publicación,
verificaciones y límites: [PUBLICACION-2026-09-21.md](PUBLICACION-2026-09-21.md).
La etapa 2 está **PUBLICADA Y VERIFICADA el 21/09**, fuente `baa63aea`, PR #64.
Acta vigente: [F4-ETAPA2-PUBLICACION-2026-09-21.md](F4-ETAPA2-PUBLICACION-2026-09-21.md);
implementación: [F4-DETALLE-ANALISTA.md](F4-DETALLE-ANALISTA.md).
Queda el recorrido de negocio con el supervisor. Etapa 3 implementada y ensayada
localmente, sin publicar; etapas 4–6 pendientes.
Sus criterios de cierre se desarrollan en §F4.
Reutiliza `private.gestion_diaria_llamadas`, que ya admite varios analistas.

**F4.1 — Revisión asistida con TypeSafe.** Comprobar primero si ayuda a detectar posibles
contradicciones entre el resultado de una llamada y su nota; incorporar las sugerencias a la
revisión del supervisor solo si el piloto demuestra utilidad. Son dos etapas: evaluación y
posterior integración condicionada. El 21/09 se verificó el acceso a la API y se preparó un
ensayo técnico sintético: 19/20 coincidencias con notas aisladas, una falsa alerta. El piloto
humano y la integración visible siguen pendientes; no bloquea F4 ni F5. Miguel confirmó
que ambos supervisores validarán las notas reales anonimizadas, cada uno únicamente
las de su propio equipo; no queda pendiente elegir a uno solo. Estado y evidencia:
[F4.1-TYPESAFE-ARRANQUE-2026-09-21.md](F4.1-TYPESAFE-ARRANQUE-2026-09-21.md).

**F5 — Gerencia «Toda la operación».** Dar una visión global del día frente a ayer y a los
últimos siete días con actividad, identificar equipos que requieren atención y profundizar
hasta el registro. El reporte de hábitos debe orientar la capacitación y aportar evidencia
para ajustar las reglas. Pendiente; alcance y criterios en §F5.

**F6 — Absorber Seguimiento.** Dejar Gestión Diaria como punto único para este trabajo,
conservar los accesos antiguos mediante redirección y retirar la vista duplicada sin perder
funcionalidad. Pendiente, después de al menos una semana de F3–F5 en producción sin
incidencias; se aplica la secuencia cerrar → observar → derribar descrita en §F6.

**Añadido acordado el 20/09/2026: F4.1 — Revisión asistida con TypeSafe.** Se documenta como
un piloto y una integración condicionada a sus resultados. El 21/09 Miguel pidió ambos usos:
ayuda en Gestión Diaria y apoyo técnico a las revisiones. Este último se probó con Jev;
el arranque sintético de F4.1 no equivale a integración productiva. No condiciona el cierre
de F4 y no bloquea F5. Los objetivos y criterios de cierre están escritos
en texto en las secciones F4 y F4.1. La pantalla de configuración de gerencia pertenece a F4;
el tablero global y el reporte de hábitos pertenecen a F5.

### Decisiones de Miguel que gobiernan (no re-preguntar)

1. «Hoy» se queda igual; Gestión Diaria es un módulo distinto (grupo Operación).
2. Cola del analista: lead nuevo sin primer intento primero, luego vencidas, luego las de hoy.
3. Plus Jakarta Sans sí; verde no (navy sobre fondo tenue para «Bien»).
4. **Actualización 21/09:** «Contestó · no le interesa» registra el resultado y el submotivo; NO descarta por elegirlo. El analista puede conservarlo y agendar una próxima acción o marcar el descarte expresamente.
5. **Actualización 21/09:** «Pide otro producto» tampoco descarta automáticamente. Solo si se marca «Descartar y enviar al Centro de rescate» aplica el motivo `pide_credito`. El descarte explícito conserva el rescate y Deshacer 24 h. «No volver a contactar» sigue bloqueando nuevas acciones; no se elimina al deshacer.
6. Número errado / no es la persona: el analista decide (2.º número hoy · descartar por datos inválidos · reintento a 7 días · solo registrar). No entran en la tasa.
7. Tasa: el % siempre con el conteo al lado; chip y alerta solo con ≥ 5 llamadas útiles.
8. Supervisor y gerencia ven llamadas por rango de horas (08–20 Lima) por analista (F3/F4).
9. **TypeSafe, aclaración del 21/09:** ambos supervisores participan en la validación; cada uno responde por las notas y sugerencias de su equipo. No hay revisión cruzada entre equipos ni un único supervisor global del piloto.
- Submotivos: sin fondos ahora → `sin_fondos` · ya invirtió con otro → `competencia` · desconfianza / no le interesa invertir / otro → `sin_interes` · préstamo / crédito / otro → `pide_credito`.
- Umbrales de arranque: Bien ≥ 45 %, Atención 25–44 %, Bajo < 25 %, con mínimo 5 llamadas útiles para calificar. En F4 los cortes sustituyen «sin llamadas a las 11:00»; «parado» = más de 2 h sin llamar dentro de la jornada (L–V 09:00–18:00, sábado 09:00–13:00, domingo sin avisos de jornada). «Tasa muy baja» nace sin umbral y desactivada hasta que gerencia lo publique con evidencia; los 15 pp del plan inicial no se aplican por defecto.

### Lo que F2 dejó escrito (importa para F3)

- Quién registra: vendedor, supervisor y gerencia. El supervisor registra «volver a llamar» / «agendó cita» sin agendar; al dueño se le exige la tarea.
- Deshacer es una REAPERTURA (compone sobre `crm.reabrir_lead_fn`): ciclo nuevo, SLA reiniciado, el descarte queda en el ledger. `reunion_agendada` se restaura como `contactado`. «No insistir» no se deshace. La tarea que la llamada cerró no se reabre.
- Llamada útil (para la tasa) = resultado ∉ (`numero_errado`, `no_es_la_persona`); el histórico sin resultado cuenta como útil. Una llamada deshecha sigue contando; su descarte no.
- **Deudas para F3:** la lista blanca de `private.registro_actividad_core` (F1) no expone `deshecho_en` / `descartado` / `no_insista` → el registro muestra un resultado deshecho como vigente hasta que F3 amplíe la lista (exige re-sellar el md5 en `assert_gestion_diaria_registro`); el Centro de rescate no marca los descartes deshechos; el «Deshacer» solo vive 15 s en el toast (el servidor admite 24 h) → F3 lo ofrece en «Descartados hoy».
- Gate paraguas `private.assert_gestion_diaria()` = `_registro()` (F1) + `_resultado()` (F2); cada fase añade el suyo. Sella por md5 lo que compone: si otra sesión reescribe `reabrir_lead_fn`, `marcar_no_contactar`, `cerrar_tarea`, `sla_ejecutar_comando` o los triggers de leads, el gate se pone en rojo y hay que re-sellar a conciencia.

### Cómo retomar (receta)

1. **Main único:** `avancecorp/main` (espejo del `main` local del taller). Integrar el remoto sin sobrescribirlo y exigir igualdad de commits antes de construir/publicar. El preflight comprueba la ancestría del despliegue anterior: `node _DEV_NO_SUBIR/deploy-hostinger-mcp.mjs preflight crm.miavance.com <zip>`.
2. **Taller y aislamiento:** comprobar `git status`, `git worktree list` y las notas de esta entrega. La candidata F4 se ha trabajado en `/private/tmp/avancecorp-gd-f4-vista.chvRqh`; no crear otro worktree ni reutilizar una rama antigua automáticamente. Preservar los cambios ajenos sin commitear.
3. **Banco local F4:** `gestion_diaria_f4_vista_chvrqh` dentro de `supabase_db_avancecorp-f5-bank`. Los scripts en `supabase/scripts/gestion-diaria-equipo/` fijan ese destino; sus fixtures terminan en ROLLBACK. No ejecutar estos ensayos contra producción.
4. **Servidor:** `20260921040335_crm_gestion_diaria_equipo_vista.sql` y `20260921153654_crm_resultado_llamada_seguimiento.sql` ya están instaladas y registradas: no editarlas ni reinstalarlas. Miguel autorizó expresamente estas dos SQL y `$release-crm`. Esa autorización no se extiende a otras migraciones, cortes o TypeSafe.
5. **Front y tipos:** la firma F4 ya está cotejada contra los tipos generados de la copia local; no usar el antiguo fallo de `gen:types` como permiso para inventar contratos. Repetir `npm run check` y `npm run test:e2e` tras cambios de integración. La publicación requiere invocación humana de `$release-crm` o `/release-crm`.
6. **Revisión:** aplicar `.ai/REVIEW_PROTOCOL.md` y `.ai/VERIFICATION.md`: un solo PRIMARY escribe; Claude revisa mediante `scripts/claude-review`, con evidencia saneada, sin herramientas ni recursión. No encadenar revisiones automáticas ni confundir su dictamen con checks reales.
7. **Trampas conocidas:** el hook de Bash bloquea comandos con `.env` o `*_KEY=` literales; los radios del panel llevan su descripción en el nombre accesible (Playwright: regex); un `div` envoltorio dentro de `Dialog` rompe el scroll del cuerpo (`flex min-h-0 flex-1 flex-col`); con un Sheet modal abierto los toasts no reciben clic sin la regla `[data-sonner-toaster]`.

### Punto de reanudación y pendiente de Miguel

**Publicación completada:** PR #62 aprobado e integrado por `miguejbs98`;
release `crm-20260921T170501Z-526e728e31ff`, build `build-20260921T170500239Z`,
en `https://crm.miavance.com/`. CI del PR y de Main, gates SQL, artefacto y
archivos ejecutables servidos PASS. Los 36 archivos ajenos al release conservaron
su contenido; las 101 líneas del ledger de temperatura siguen íntegras y sin
commitear. No repetir conciliación, aprobación ni instalación de estas dos SQL.

**Checkpoint solicitado por Miguel (21/09):** después de la publicación confirmó
«perfecto ahora si me gusta mas» y pidió guardar todo el progreso. Se registra
su conformidad con la mejora visible del formulario; no se interpreta como una
matriz completa de pruebas de negocio ni como aprobación de nuevas etapas.
Este guardado conserva el plan, actas, ledger y memoria en Git local, sin otro
deploy, SQL ni activación. En ese checkpoint la versión productiva era `526e728e`;
la entrega posterior de la etapa 2 se registra a continuación.

**Retoma del 21/09 — etapa 2 implementada localmente:** se amplió el detalle de
cada fila con llamadas por hora, reutilizando la foto F4 y el registro F1. El
recorrido analista → actividad → ficha conserva filtros y foco, e hidrata la
ficha bajo los permisos existentes aunque no esté en la caché inicial. Incluye
estados de carga, vacío filtrado, error y revocación. No se creó otro historial
ni se modificaron SQL, cortes o TypeSafe.

La candidata se preparó en `codex/gestion-diaria-f4-detalle-analista`, en el taller
existente `/private/tmp/avancecorp-gd-f4-vista.chvRqh`, basada en `b0d2ff89`.
Se preservaron los trabajos concurrentes de Main. Evidencia:
[F4-DETALLE-ANALISTA.md](F4-DETALLE-ANALISTA.md).
Miguel expresó conformidad visual tras revisar la vista local el 21/09; después
autorizó la publicación por separado. Esa conformidad no se presenta como una
prueba integral de negocio ni como la autorización que permitió el despliegue.
La siguiente implementación de F4 es la etapa 3. Las tres decisiones de cortes
se cerraron después el 21/09 (ver abajo); implementación y activación siguen separadas.

**Etapa 2 publicada y cerrada técnicamente:** Miguel invocó `$release-crm` y
aprobó el PR #64. Se publicó `baa63aeac71e5a074309aae92a064b67756189f1`, build
`build-20260921T200508459Z`, a las 15:07 Lima del 21/09. Main y remoto iguales,
fuente limpia, `npm run check`, CI del PR (4.051 pruebas y 232 E2E/26 omitidos),
preflight SQL de cinco identidades y 110 comprobaciones HTTP finales PASS.
Los 68 archivos JS/CSS servidos coinciden con el manifiesto. Artefacto,
recuperación y límites en
[F4-ETAPA2-PUBLICACION-2026-09-21.md](F4-ETAPA2-PUBLICACION-2026-09-21.md).
Sin nuevas SQL, cortes ni TypeSafe. Sigue el recorrido humano productivo y la
implementación de la etapa 3; no se anuncia F4 completa.

**TypeSafe, avance separado posterior al release:** API verificada con `jev-1.13.0`,
ensayo sintético reproducible y apoyo técnico comprobados localmente. No se enviaron
notas reales ni se modificaron SQL, Edge, cron o frontend. La evaluación aislada obtuvo
19/20, con una falsa alerta en una nota genérica; no es calibración productiva.
Miguel confirmó que ambos supervisores validarán el piloto humano, cada uno dentro
de su equipo. Falta preparar la muestra anonimizada y los criterios de validación,
no designar un único responsable. Sigue preparado el ensayo, no los avisos del CRM. Ver
[F4.1-TYPESAFE-ARRANQUE-2026-09-21.md](F4.1-TYPESAFE-ARRANQUE-2026-09-21.md).

- **Prueba de negocio pendiente:** confirmar como supervisor que aparecen todos sus analistas, incluidos quienes no registraron actividad; revisar pendientes y abrir el registro. Miguel ya expresó conformidad con la mejora visible del formulario; queda observar el seguimiento y descarte durante el uso normal. No se crearon registros reales para el smoke.
- **Límites de la verificación:** pruebas SQL productivas de solo lectura bajo roles; no equivalen a la matriz Auth/HTTP completa. No había navegador conectado para la inspección visual productiva. El oráculo histórico F1 conserva su fallo previo de whitelist; véase el acta.
- **F4 posterior:** reglas cerradas el 21/09: sábado mínimo 3, analistas sin leads abiertos fuera de los avisos de corte pero visibles en tabla, y un aplazamiento de una hora por aviso/supervisor/día sin reaviso al cierre o después. Falta implementar y verificar etapas 3–6; no se activaron cortes.
- **Resuelto para esta integración:** el nivel «Bajo» conserva el ámbar publicado en PR #55. Se reconciliaron las dos variantes de «Mi día»: desplegables y flujo horizontal del taller, junto con los arreglos de caché, pestañas y permisos publicados.

### Lo que F3 dejó escrito (importa para F4)

**El plan maestro lo tiene entero**, en la sección «Lo que la Fase 3 cambió del plan». Lo corto:

1. **Dos paneles, no una columna.** Piso tipográfico **16 px** con un e2e que lo mide sobre el
   estilo calculado. Una sola acción primaria por pantalla. Lo secundario se **pliega** a un
   segundo nivel, no se encoge. `Tabs`, `AccionesContacto` y `PanelVacio` ya tienen tamaño grande.
2. **Nada de «SLA» en pantalla**: se dice el tiempo. `referencia_en` YA es el vencimiento, así que
   el chip se calcula en el navegador — salvo `sin_conversacion`, que no lleva límite.
3. **La regla de la caché parcial:** *una ausencia en una colección parcial significa
   «desconocido», nunca «no existe»*. Costó cinco bugs, uno en producción. `gestion_diaria_equipo_fn`
   debe ser una proyección autosuficiente, o la pantalla hidrata por id. Todo estado remoto
   distingue cargando / vacío / error / sin autorización.
4. **El teléfono NO viaja en la cola.** Si F4 quiere contacto directo desde la tabla del equipo,
   hay que decidir si lo trae la puerta o se hidrata.
5. **El núcleo de F4 ya existe:** `private.gestion_diaria_llamadas` acepta varios analistas.

### Referencias

PRs: #29 (F0), #34 (F1), #38 (F2), #41 (acta F1+F2), #42 (F3). Migraciones: `20260919211958`, `20260920005000`, `20260920041500` (ledger `supabase/migrations/MIGRACIONES.md`). Vault: «Gestion Diaria - modulo nuevo y absorcion de Seguimiento 2026-09-19», «Gestion Diaria F2 - resultado tipificado de llamada (2026-09-20)» y «Gestion Diaria F3 - el dia del analista (2026-09-20)». Memoria de sesión: `gestion-diaria-plan-por-fases.md`, `gestion-diaria-f2-resultado-llamada.md` y `gestion-diaria-f3-analista.md`.

---

# 2 · El plan por fases

> **Estado al 21/09/2026:** F0–F3, ampliación de resultado v4 y F4 etapas 1–2 EN PRODUCCIÓN. Sigue el recorrido de negocio y F4 etapa 3; F4 no está cerrada. F4.1 tiene API y ensayo sintético comprobados; piloto humano e integración productiva pendientes. Dónde estamos y cómo retomar: sección 1.


Fuente: `CRM-Avance-Corp/GESTION DIARIA/gestion-diaria-handoff.zip` (PLAN.md 18–19/09/2026, 6 mockups, UI-UX-playbook.pdf). Diagnóstico del 19/09 leyendo el código real (front, 295 migraciones, vault): 67 elementos de los mockups mapeados a su fuente, y el plan sometido a tres refutadores independientes (SQL, front, fidelidad al negocio). Todo lo que sigue cita archivo y línea verificados.

### Context

**Problema.** «Seguimiento» no permite decidir nada porque la captura de llamadas es pobre: dos tipos (`llamada_realizada` / `llamada_no_contestada`), `detalle` en texto libre (31 % vacío), `metadata` 100 % vacío, compromisos («prox. llamada 21-09») que viven en prosa sin tarea. La tasa de contacto está contaminada.

**Meta.** Un módulo nuevo, **Gestión Diaria**, que responde una sola pregunta: *¿qué está pasando hoy y qué hay que hacer ahora?* Tres vistas por rol (analista / supervisor / gerencia) y la pieza que lo desbloquea: **el resultado de llamada tipificado y obligatorio** (7 opciones aprobadas en el mockup 5), guardado en `crm.actividades.metadata` sin tocar el CHECK de `tipo`.

**Decisiones de Miguel (19/09, esta sesión):**
1. **«Hoy» se queda igual.** Gestión Diaria es un módulo DISTINTO en el menú (grupo Operación, donde hoy está Seguimiento). La pantalla de entrada de cada rol no cambia.
2. **Cola del analista: el lead nuevo sin primer intento va primero**, luego vencidas, luego las de hoy (regla del 25/08).
3. **Plus Jakarta Sans sí, verde no.** Se carga la tipografía en todo el CRM; los estados «Bien» van en navy sobre fondo tenue (el azul `#2563eb` se reserva a enlaces, selección y foco, como manda el mockup 6 «un significado, un color»).
4. **«Contestó · no le interesa» registra el resultado con submotivo obligatorio, sin descarte automático** (decisión que sustituye la anterior, 21/09). Puede acompañarse de una próxima acción.
5. **«Pide otro producto» también separa el resultado del descarte**. En ambos casos, descartar es una elección expresa e incompatible con crear una próxima acción en ese guardado. Solo el descarte alimenta el **Centro de rescate** existente (`crm.rescate_descartes_mes`) y su deshacer/reapertura. La carpeta sigue excluyendo a propósito `datos_invalidos`.
6. **«Número errado» / «No es la persona»: el analista decide.** Si el lead tiene segundo número, el panel propone la tarea «llamar al segundo número» hoy; si no, el panel ofrece «Descartar por datos inválidos» (con deshacer 24 h) o «Mantener con reintento a 7 días» y el analista elige. Estas llamadas cuentan como intento pero NO entran en la tasa de contacto.
7. **Tasa de contacto: el % se muestra siempre con el conteo al lado** («100 % · 2 llamadas», como el mockup 3). Con menos de 5 llamadas no hay chip Bien/Atención/Bajo ni alerta, y esas filas van al final del orden por tasa.

8. **Llamadas por rango de horas del analista** (pedido el 19/09 tras la medición): supervisor y gerencia ven cuántas llamadas hace cada analista por franja horaria del día (barras por hora, 08–20 Lima). Sale del mismo núcleo; se muestra en la tabla de equipo (fila expandible) y en el registro.

**Decisiones previas del ZIP que se respetan:** lista de 7 resultados · cuota diaria FUERA de v1 · el supervisor SÍ ve el texto de su equipo · la alerta «SLA de primer CONTACTO» está eliminada (§11); la de «primer INTENTO» (§4) NO fue eliminada y se conserva · playbook UI-UX es norma.

### Lo que el código real cambia respecto al PLAN.md y los mockups (verificado)

| PLAN.md / mockup dice | Realidad verificada | Consecuencia |
|---|---|---|
| §12: metadata resuelve el resultado «sin tocar el CHECK» | Cierto para el CHECK; pero `crm.registrar_actividad_v2` inserta solo `(id, lead_id, tipo, detalle, creado_por)` (`20260907025220:147-149`) y su firma está SELLADA por `private.assert_sla_comandos` (`:710-735`) | Puerta nueva `crm.registrar_llamada_v3` que COMPONE sobre las selladas, patrón `cerrar_reunion_v3` (`20260918213000:198-297`) |
| §7.1 «obligatorio al cerrar la llamada» | Hay DOS caminos: `registrar_actividad_v2` (id de la actividad = `p_operacion_id`) y `cerrar_tarea_v2` (el id vuelve en la clave `actividad_id` de la respuesta, `:357-359`); `cerrar_tarea_v2` YA exige resultado (contestó/no contestó, `:305-308`) | La v3 cubre los dos caminos; en el segundo toma `actividad_id` de la respuesta y aborta si viene nulo |
| «Deshacer» del mockup 4/6 | El log es inmutable, pero el mockup pide deshacer los EFECTOS (tarea creada, descarte), no el log. El único deshacer de descarte hoy (`crm.deshacer_descarte`) es de coordinación y solo para leads SIN dueño (`20260723120000:531-541`, `20260807203740:383-392`); el analista solo tiene `reabrir_lead_fn`, sin ventana y que devuelve el lead a `nuevo` | Se construye `crm.deshacer_resultado_llamada` (24 h, autor, restaura la etapa previa) y el toast lleva «Deshacer» sobre la tarea creada y el descarte. La actividad queda en el log |
| §4 «reusar `alertas_reconocimientos`, no armar otro mecanismo» | `alerta_id` con CHECK regex cerrado a 4 tipos en singular (`20260823204930:43-45`); el uuid del id debe ser el del ACTOR (`:105-113`); gerencia no puede insertar; el 07/09 se decidió que los avisos SLA nuevos NO se reconocen | La base reconoce `tarea_vencida` y `por_repartir` como UN grupo por supervisor (`grupo:<tipo>:<supervisorId>`, `lib/alertas.ts:434,506`). F4 añade explícitamente reconocimiento y aplazamiento de una hora a los cortes mediante migración compatible, con identidad por supervisor, jornada y corte. Los demás avisos se retiran al resolverse. |
| §5 «conversiones de hoy» y «rango normal 42–52 %» | No hay núcleo diario por fecha de conversión (cambiando ahora); el rango es ilustrativo (§13) | Fuera de v1, dicho en pantalla. El pulso compara con ayer y con el promedio de los últimos 7 días con actividad |
| Mockup 1: fila «Sin equipo · coordinador» | El ámbito de gerencia es TODO `crm.equipo` (`20260803164348`); el mockup cuadra 35+46+2 = 83 | Se conserva como fila de CUADRE «Fuera de equipos comerciales» (llamadas y contestadas, sin tasa ni «Ver equipo»). Coordinador y directorio no ENTRAN al módulo como usuarios |
| Mockup 5: panel lateral de 520 px | El drawer del lead ya es un `Sheet` (`lead-drawer.tsx:167`); no hay precedente ni test de Sheet dentro de Sheet; el probado es `Dialog` dentro de `Sheet` (`ui/dialog.test.tsx:26`) | El formulario del mockup 5 se monta en `Dialog` (mismo contenido, misma jerarquía) |
| Mockup 5: «En llamada · 00:42», «4.º intento» | No hay duración (§2.4); el ordinal sí es derivable | Sin cronómetro; «N.º intento» lo devuelve el servidor |
| Mockup 2: «Marcar para revisión», «Crear tarea», «Avisar al supervisor» | Sin dónde persistir la marca; sin canal de aviso | «Marcar para revisión» = nota correctiva (`nota` con `metadata.evento='revision'`). Los otros dos, fuera de v1 |
| Mockup 1: nav «Métricas» | No existe ese módulo | Sin ese ítem en v1 |
| Mockups 4/5: «agendó reunión», «Reuniones» | Decisión del 27/08: en la interfaz se dice **cita** (vault «Terminologia de citas en el CRM»); las claves técnicas (`reunion`) no cambian | Etiquetas «Contestó · agendó cita», «Citas agendadas» desde la Fase 2 |
| §2.6: `resultado_reunion` tiene 4 valores | Tiene 6 (`20260805180000:83-90`) | Catálogo nuevo separado (desenlace de llamada ≠ de cita) |
| §3 Bloque 1: «vencidas arriba de todo» | Contradice la regla del 25/08 protegida por 35 pruebas (`prioridades-vendedor.ts:32-84`) | Decisión #2 de Miguel: lead nuevo primero |
| Riesgo «dos colas»: «misma RPC, mismo orden» (borrador anterior) | FALSO: Hoy usa `cola_accion_fn` v1 + un TOP-3 plano por severidad (`seleccionarPrioridadesVendedor`, `prioridades-vendedor.ts:41-70`); Gestión Diaria usará `cola_accion_v2_fn` agrupada por bucket | Son DOS presentaciones distintas y se declara: Hoy = «las 3 cosas de ahora», Gestión Diaria = la cola completa. Test compartido: el primer ítem de Hoy (speed-to-lead) es también el primero de Gestión Diaria |

### Definiciones fijadas por escrito (una sola vez, en el servidor)

- **Llamada** = actividad con `tipo in ('llamada_realizada','llamada_no_contestada')`. **Contacto** = `llamada_realizada`. **Llamada útil** = llamada cuyo resultado no es `numero_errado` ni `no_es_la_persona`. **Tasa de contacto** = contactos / llamadas útiles. En pantalla toda cifra se rotula «Llamadas», nunca «gestiones» ni «toques», con pie fijo: «Llamadas = marcadas + no contestadas. No incluye WhatsApp ni citas (eso son «toques», en Agenda)». Los 5 toques de `metricas_agenda_fn` (`20260727032429:359-366`) son otro concepto y no se mezclan.
- **Tarea vencida** = `estado='pendiente' and activo and vence_en < now()` (comentario canónico de la tabla, `20260718180001:87-89`). El «735» se remide con esta definición.
- **Jerarquía** = `crm.equipo.supervisor_id` de HOY vía `private.vendedor_ids_visibles`. **Roster activo** = `crm.equipo.activo = true` con `private.rol_crm` = vendedor (nunca `vendedor_ids_visibles`, que incluye inactivos a propósito).
- **Parkeado del equipo** = `l.activo and l.vendedor_id is null and l.asignado_supervisor_id in (visibles)` (NO `leads_por_repartir`, que es la cola global del coordinador y daría siempre cero: `20260903250000:50-79`).
- **Resultado tipificado** (claves): `no_contesto` · `volver_a_llamar` · `agendo_reunion` · `no_interesado` · `numero_errado` · `no_es_la_persona` · `pide_otro_producto`. Viaja en `metadata` como `{evento:'resultado_llamada', resultado, submotivo?, intento_n, etapa_anterior}` (vocabulario ya usado por otros writers: `evento`, `etapa_anterior`, `motivo`).
  - Tipo de actividad: `no_contesto`, `numero_errado`, `no_es_la_persona` → `llamada_no_contestada` (no avanzan etapa ni sellan contacto; sí sellan primera gestión: `trg_zy`, `20260807203757:1038-1046`). Los otros cuatro → `llamada_realizada`.
  - Efectos: `no_contesto` → siguiente intento propuesto por la cadencia existente (`sugerirSiguiente()` de `lib/motor-siguiente.ts`, editable; al 6.º intento ofrece «marcar perdido: no responde») · `volver_a_llamar` → tarea `llamada` obligatoria con fecha · `agendo_reunion` → tarea `reunion` con fecha/modalidad (`campos-reunion.tsx`) · `no_interesado` → submotivo + descarte `sin_interes` (+ casilla opcional «Pidió que no lo vuelvan a llamar» → puerta existente `crm.marcar_no_contactar`, Ley 29571) · `pide_otro_producto` → submotivo + descarte `pide_credito` · `numero_errado` / `no_es_la_persona` → decisión #6.
  - Submotivos APROBADOS por Miguel (19/09): no_interesado → `sin_fondos_ahora` (motivo `sin_fondos`), `ya_invirtio_con_otro` (motivo `competencia`), `desconfianza`, `no_le_interesa_invertir`, `otro` (motivo `sin_interes`); pide_otro_producto → `prestamo`, `credito`, `otro` (motivo `pide_credito`). El submotivo elige el motivo real del catálogo existente y no lo duplica.
- **Ventana legal** de toda fecha propuesta: L–S 07:00–20:00 Lima (`slotHabil()`, `lib/motor-siguiente.ts:45-66`).
- **Umbrales** (un solo sitio: `private.gestion_diaria_umbrales()`): chip Bien ≥ 45 %, Atención 25–44 %, Bajo < 25 %, con mínimo 5 llamadas útiles. Son los valores de arranque aprobados y pasan a política versionada en F4. Los cortes sustituyen «sin llamadas a las 11:00»; «parado» = más de 2 h sin llamar dentro de 09:00–18:00 L–V o 09:00–13:00 sábado, sin avisos de jornada el domingo. «Tasa muy baja» nace sin umbral y desactivada; los 15 pp del planteamiento inicial no son un valor predeterminado.
- **Frescura**: sin realtime; refresco cada 60 s y «Corte HH:MM» visible.

### Arquitectura (4 capas)

```
1. Tablas   crm.actividades sin columnas nuevas + CHECK de FORMA sobre metadata (NOT VALID + VALIDATE)
            + índice actividades_llamadas_autor_dia_idx (creado_por, creado_en desc) where tipo in (llamadas)
2. Núcleo   private.gestion_diaria_llamadas(p_ini, p_fin, p_vendedor_ids)  ← UNA definición de llamada/contacto/tasa (registrada como auxiliar auditado del censo)
            private.llamada_registrar(...)  ← efectos del resultado, atómico, con pre-chequeo de replay
            private.gestion_diaria_umbrales()
3. Puerta   crm.registro_actividad_fn(p_desde, p_hasta, p_supervisor_id, p_analista_id, p_tipo, p_etapa, p_limite, p_cursor)   [F1]
            crm.registrar_llamada_v3(...) · crm.deshacer_resultado_llamada(p_actividad_id)                                     [F2]
            crm.gestion_diaria_analista_fn(p_dia)                                                                                [F3]
            crm.gestion_diaria_equipo_fn(p_dia, p_supervisor_id)                                                                 [F4]
            crm.gestion_diaria_pulso_fn(p_dia)                                                                                   [F5]
4. Pantalla vista 'gestion-diaria' → screens/gestion-diaria.tsx (switch por rol como screens/hoy.tsx:13-27)
            components/gestion-diaria/: registro-actividad, registrar-resultado, tabla-equipo-diaria, alertas-del-dia
```

**Reglas que aplican a todas las fases.** Puertas `SECURITY DEFINER` + `STABLE` (lecturas) + `search_path=''` + `revoke all … from public, anon, authenticated, service_role` + `grant execute … to authenticated`; preflight con md5 de lo vivo (incluido el md5 de `crm.cola_accion_v2_fn`, que NO está sellada por ningún gate y se acuerda no tocar); postflight que llama SOLO a `assert_sla_*` (verdes) más el propio `private.assert_gestion_diaria()`. **Censo analítico** (`assert_analitica_leads_citas`, en rojo, tope 30 que solo baja y ya desbordado: `20260912181045:152-163`): las puertas nuevas NO usan `count(` ni `sum(1)` (delegan al núcleo) y el núcleo se registra en `private.auxiliares_analitica_lc_auditados()` (definición + owner + ACL) para no subir `v_n`; el postflight exige que el conjunto rojo quede idéntico (patrón `20260919170500:73-75, 271-272`, adaptado para no exigir «mismo número» si el censo cambia por lo declarado). `gen:types` está roto → cada RPC nueva se añade A MANO a `app/src/lib/database.types.ts`. Clave nueva en RESPUESTA → front tolerante con `v.optional`; RPC nueva → SQL primero, front después. Terminología visible: «Analista», «cita». Cobertura: medir `npm run test:coverage` antes de cada PR de pantalla (umbrales 26/23/30/29, `vitest.config.ts:43-48`) y ajustar en la misma entrega si hace falta.

---

### Fase 0 — Cimientos · LEVEL 1–2 · 2 PR front, 0 SQL

**Qué obtiene Miguel:** el CRM con la letra correcta, umbrales y submotivos confirmados con datos reales, y las decisiones escritas en el vault.

1. **Medición en producción (solo lectura, `DO` que termina en `raise`):** modo de `crm.sla_operacion_control` y cuántas filas devuelve hoy `cola_accion_v2_fn` con bucket `primera_atencion` (de eso depende el orden prometido); 735 vencidas con la definición canónica; tasa real por analista/equipo de 14 días aplicada a los umbrales propuestos (antes/después sobre las filas del mockup 3); distribución horaria. Miguel confirma umbrales y submotivos.
2. **Tipografía:** `npm i @fontsource/plus-jakarta-sans`, importar 400–800 en `app/src/index.css:2-5`; `--font-sans` ya la declara (línea 101). PR + release.
3. **Primitivas UI:** `components/ui/tabs.tsx` (APG, de `ranking-vendedores.tsx:801-818`), `components/ui/radio-group.tsx` (fieldset/legend/label de `rescate-descartados.tsx:192-208`, 44 px, borde 2 px), `lib/exportar-csv.ts` (de `citas/avance-mensual.tsx:85-99`, BOM + anti-inyección). Con tests. No se refactorizan las copias viejas.
4. **Documentación:** copiar `docs/gestion-diaria/` del ZIP a `CRM-Avance-Corp/docs/gestion-diaria/`; nota del vault «Gestion Diaria - modulo nuevo y absorcion de Seguimiento 2026-09-19.md» que declara qué deroga (Seguimiento del 07/09) y qué NO (orden del 25/08, «Hoy»), con wikilinks a Seguimiento, Hoy del vendedor, Núcleo SLA, Plan de avisos por acción y rol, Acceso y roles, Fundamentos UX, Terminologia de citas, capa semántica, Agenda comercial (plan v2). Bullet en `Inicio.md`.

Verificación: `npm run check`. Codex: no.

---

### Fase 1 — Alta del módulo + Registro crudo compartido · LEVEL 3 · 1 migración + 1 PR

**Qué obtiene Miguel:** el módulo existe en el menú y el supervisor puede leer HOY el texto íntegro de las llamadas de su equipo (4 889 históricas), con pestañas, paginación y exportación para gerencia. Es solo lectura, no toca ninguna puerta sellada y adelanta la conversación de calidad con los analistas sin esperar al resultado tipificado.

**Servidor (`…_crm_gestion_diaria_registro.sql`, skill `nueva-migracion`):** `crm.registro_actividad_fn(p_desde date, p_hasta date, p_supervisor_id uuid default null, p_analista_id uuid default null, p_tipo text default null, p_etapa text default null, p_limite int default 50, p_cursor jsonb default null)` con rango desde el primer día (Gestión Diaria lo llama con hoy; Métricas lo reutilizará). Devuelve `id, creado_en, lead_id, lead_nombre, etapa_actual, etapa_en_ese_momento` (derivada en SQL de los `cambio_etapa` previos del lead vía `metadata->>'etapa_nueva'`, que existe desde `20260709000001:342-345`; nunca parseando prosa), `tipo, detalle, metadata, creado_por, autor_nombre`, keyset como `cola_accion_v2_fn`. Ámbito por AUTOR cruzado con `vendedor_ids_visibles` (la policy `actividades_select` filtra por dueño del lead, por eso es definer); vendedor solo lo suyo; gerencia global. Sin `count(`. Índice nuevo. Coordinar con la sesión paralela de «historial por lead» (`actividades_de_lead_fn`, `20260919185718`): son entradas distintas (por lead vs por ámbito) con la misma forma de fila; pedirles que añadan `metadata` a la suya. `assert_gestion_diaria` inicial. `test-rls.mjs`: copiar `testFacturacionDiaria` (línea 7262): supervisor A no ve equipo B; vendedor solo autor propio; gerencia global. `auditor-rls`. Ensayo en banco (contenedor local, plantilla `supabase/scripts/cartera-procedencia/`). Línea base de `test:rls` antes/después.

**Front:** alta de la vista `gestion-diaria` en TODOS los registros: `lib/router.ts` `VISTAS` (insertar DESPUÉS de las tres primeras entradas: `router.test.ts:126` fija `['hoy','alertas','seguimiento']`) y `VISTAS_LEADS` (línea 87); `App.tsx` lazy + `PANTALLA_POR_VISTA`; `lib/vistas.ts` DOS cosas: entrada `'gestion-diaria': 'verLeads'` (línea ~24) y el early-return espejo de la línea 100 (`rol === 'gerencia' || 'supervisor' || 'vendedor'`), porque `directorio` también tiene `verLeads`; `vistas.test.ts:12-14`; `sidebar.tsx` `NAV_META` + `GRUPO_GERENCIA` (grupo Operación) y `sidebar.test.tsx:117-130` (lista ordenada); `topbar.tsx` `TITULOS`; `ayuda-vendedor-panel.tsx` `ETIQUETA_VISTA` (línea 20) y el ternario `contextoAyuda` (líneas 65-67) → `'hoy'` (el servidor tiene lista blanca cerrada, `20260818034822:1142-1149`). Regla #10: cada rol debe poder abrirla con el gate de leads cerrado igual que Seguimiento. `screens/gestion-diaria.tsx` (switch por rol) con, en esta fase, la sección «Registro» para los tres roles. `components/gestion-diaria/registro-actividad.tsx`: pestañas Llamadas/WhatsApp/Notas/Todo (`ui/tabs.tsx`), filtros analista/tipo/etapa (+ equipo y buscador de analista para gerencia), «Ver más» por cursor, «Exportar CSV» solo gerencia (incluye `detalle`: requisito «ver absolutamente todo»), acción «Nota de revisión» (vía `registrar_actividad_v2`, tipo `nota`). `data/gestion-diaria-api.ts` + `data/use-registro-actividad.ts` (real/demo/fail-closed), clave bajo `crmQueryKeys`, `database.types.ts` a mano. Datos demo en `lib/demo.ts`. Tests con fixture y con estado real (31 % sin detalle); `revisor-a11y`; e2e demo por rol. `npm run check:all` (navegación nueva).

**Despliegue:** SQL primero (Miguel `!`), front después (`/release-crm`). Codex: 1 (diff; visibilidad entre equipos).

---

### Fase 2 — El resultado tipificado · LEVEL 3 · 1 migración + 1 PR

**Qué obtiene Miguel:** cada llamada del CRM, en cualquier pantalla, se registra con uno de los 7 resultados; la elección contrae los demás. «Volver a llamar» crea la tarea; «No le interesa» y «Pide otro producto» permiten conservar el lead y programar llamada, WhatsApp, cita o tarea. El descarte es una decisión aparte y explícita, con motivo real y los efectos de Deshacer admitidos por el servidor durante 24 h.

**Ampliación del 21/09, publicada:** `registrar_llamada_v4` y su núcleo
versionado aplican la nueva decisión. La puerta v3 y su núcleo se conservan literalmente
para clientes anteriores y recibos pendientes: nunca reinterpretar un guardado viejo como
una solicitud v4. El panel de guardados reenvía la puerta, UUID y contenido originales.
Motivo compacto; título, tipo, fecha, hora y campos de cita compartidos con la ficha;
descarte y veto eliminan la próxima acción del envío sin borrar el borrador visible al
desmarcarlos. Pruebas y orden de activación en el acta enlazada arriba.

**Diseño original de F2 que sigue como antecedente:** las firmas v3 y los detalles que
siguen explican lo entregado el 20/09. Donde contradigan el desacople, gobierna la
ampliación v4; no editar retrospectivamente la migración instalada de F2.

**Servidor (`…_crm_gestion_diaria_resultado_llamada.sql`):**
- CHECK de FORMA sobre `crm.actividades.metadata` (`metadata->>'resultado' is null or … in (catálogo)`), `NOT VALID` + `VALIDATE` (patrón `actividades_creado_en_finito`, `20260818045032:248-252`). De forma, no de presencia: `registrar_actividad_v2` y `cerrar_tarea_v2` siguen insertando sin metadata. Gobierna también el INSERT directo de `insertarActividad` (`crm-api.ts:2163-2166`).
- Núcleo `private.llamada_registrar(p_actor, p_operacion_id, p_lead_id, p_resultado, p_submotivo, p_detalle, p_siguiente, p_tarea_id, p_descartar boolean, p_no_insista boolean) returns jsonb`. Orden fijo: (1) **pre-chequeo de replay** copiado de `cerrar_reunion_v3` (`20260918213000:251-266`): si `crm.sla_operacion_recibos` ya tiene respuesta para `(actor, operacion_id)`, devuelve la guardada sin tocar nada (el recibo no guarda resultado/submotivo, así que sin esto un reenvío pisaría metadata y descartaría dos veces); (2) valida catálogo y coherencia (fecha futura en ventana legal, submotivo obligatorio); (3) delega en la puerta sellada: `crm.registrar_actividad_v2` (actividad con `id = p_operacion_id`) o, si `p_tarea_id`, `crm.cerrar_tarea_v2` con `p_resultado_tipo` (el id vuelve en `respuesta->>'actividad_id'`; abortar si nulo); (4) `update crm.actividades set metadata = …` sobre ese id (verificado: ningún trigger lo bloquea; `trg_audit_actividades_cambio_baja` solo audita, `20260831055000:3369-3371`; el único veto es gerencia, `trg_00_gerencia_solo_lectura`, que tampoco podrá registrar llamadas por aquí); (5) si `p_descartar`: `update crm.leads set etapa='descartado', motivo_descarte=…` (columnas exactas que hoy toca el store en `store.tsx:2525`; `descartado_en/por` los sella `private.trg_leads_zz_sello_descarte`; la cascada del ledger asienta el episodio que lee el Centro de rescate) DESPUÉS de la actividad (el comando SLA rechaza leads cerrados, `20260907025220:143-145`); (6) si `p_no_insista`: `crm.marcar_no_contactar`. Sobre de respuesta `{ok:true, version:2, operacion_id, comando:'registrar_llamada', lead_id, actividad_id, siguiente_id, descartado}` (lo exige `ejecutarComandoSla`, `data/sla-operacion-comandos.ts:160`).
- Puerta `crm.registrar_llamada_v3(p_operacion_id uuid, p_lead_id uuid, p_resultado text, p_submotivo text default null, p_detalle text default null, p_siguiente jsonb default null, p_tarea_id uuid default null, p_descartar boolean default false, p_no_insista boolean default false) returns jsonb`.
- Puerta `crm.deshacer_resultado_llamada(p_actividad_id uuid)`: solo el autor, ≤ 24 h, revalida ámbito; cancela la tarea creada (`siguiente_id`, por la puerta de cierre existente con estado `cancelada`), y si hubo descarte lo revierte componiendo sobre `crm.reabrir_lead_fn` (que verifica ledger, identidad y «No insistir») y restaurando `etapa_anterior` guardada en metadata; deja `nota` con `metadata.evento='resultado_deshecho'`. La actividad de la llamada permanece.
- `assert_gestion_diaria` ampliado; `test-rls.mjs`: permitido/denegado por rol, lead ajeno, lead cerrado, resultado fuera de catálogo, fecha pasada, sin submotivo, replay idéntico, replay con otro resultado, deshacer ajeno, deshacer a las 25 h. `auditor-rls`. Ensayo en banco. **Revisión Codex de arquitectura ANTES de implementar** (consulta 1) y de diff después (consulta 2).

**Front (PR `gestion-diaria/f2-resultado-llamada`):**
- `components/gestion-diaria/registrar-resultado.tsx`: el formulario del mockup 5 dentro de `Dialog` (ver tabla): `RadioGroup` de 7 opciones con atajos 1–4, paso 2 condicional (fecha con atajos legales `slotHabil()`/`camposDeSugerencia`/`isoDeCampos`; cita con `campos-reunion.tsx`; submotivo; para número errado la elección de la decisión #6; casilla «Pidió que no lo vuelvan a llamar»), nota opcional, `BotonGuardar`. Con el lead en `contactado`/`propuesta_enviada` el descarte muestra «Saldrá de tu cartera; puedes deshacerlo durante 24 h». El botón «Omitir» (`contacto.tsx:526-529`) NO se retira (en móvil no hay Esc y `ui/dialog.tsx` no pinta X): se renombra «Cerrar sin registrar» y el toast dice qué NO quedó registrado.
- `contacto.tsx`: la rama `OPCIONES.tel` (`:274-283`) de `DialogResultado` (`:341-536`) pasa a montar el panel nuevo; la rama `wa` (WhatsApp) se conserva tal cual. Se aplica en todas las superficies (drawer, cola, agenda, Hoy) → una sola definición de «resultado de llamada». `tareaQueCierra` (`lib/contacto-tarea.ts:45-57`) sigue decidiendo `p_tarea_id`.
- Toast con `avisoDe()` (`contacto.tsx:292-316`) enumerando lo ocurrido + acción «Deshacer» 15 s (patrón `repartir.tsx:255-268`) → `deshacer_resultado_llamada`.
- Capa de datos: `registrar_llamada_v3` y `deshacer_resultado_llamada` en `gestion-diaria-api.ts`; `data/sla-operacion-comandos.ts`: union `Comando`, set `COMANDOS` y **`clave()` (líneas 28-30) con cubo nuevo `'llamada'` y sujeto = `lead_id`** (si no, colisiona con `cerrar_tarea_v2` y bloquea el guardado con `SLA_CONFIRMACION_PENDIENTE`); `NOMBRES` de `guardados-sla-pendientes.tsx`; `database.types.ts` a mano; `ActividadRowSchema` (`crm-api.ts:1498-1505`, ya es `v.object`, tolerante) y `Actividad` (`tipos.ts:342-356`) ganan `metadata` opcional; `store.registrarLlamada(...)` con espejo optimista coherente con `avancePorContacto` (`avance-automatico.ts:56-59`); `lib/resultado-llamada.ts` (catálogo, etiquetas «cita», mapeo resultado→tipo, test que fija el espejo del servidor).
- Los chips de resultado se pintan donde la fila trae `metadata` (registro de la Fase 1; el timeline del drawer cuando `actividades_de_lead_fn` lo devuelva).
- Nota de corte en el pulso (Fase 5): «desde el DD/MM las llamadas llevan resultado».
- Tests: catálogo, panel (estado real: 100 % del histórico sin resultado), `contacto.test`, e2e demo «llamar → resultado → tarea creada → deshacer». `npm run check:all`.

**Despliegue:** SQL primero, front después. Codex: 2.

---

### Fase 3 — Analista «Mi día» · ✅ COMPLETA EN PRODUCCIÓN (20/09/2026)

> **Cerrada el 20/09.** SQL `20260920041500` instalada y registrada; front publicado en tres
> releases el mismo día: la pantalla original (`crm-20260920T062207Z-12230ee2ea0f`), el rediseño
> por densidad (`crm-20260920T193711Z-6fd1252e5689`) y la familia de bugs de caché parcial
> (`crm-20260920T203400Z-438b94cee902`). Lo que sigue describe lo PLANEADO; debajo, lo que
> cambió al construirlo y lo que F4 y F5 heredan.


**Qué obtiene Miguel:** el analista ve a quién llamar ahora, su marcador del día, sus compromisos y sus descartes de hoy (con deshacer), y salta al siguiente al guardar.

**Servidor (`…_crm_gestion_diaria_analista.sql`):** núcleo `private.gestion_diaria_llamadas(p_ini, p_fin, p_vendedor_ids)` (llamadas, útiles, contestadas, tasa, leads únicos, ratio, primera/última, desglose por resultado, **llamadas por hora Lima**, citas agendadas con la definición de `metricas_agenda_fn:128-135`), registrado como auxiliar auditado del censo. Puerta `crm.gestion_diaria_analista_fn(p_dia date default null)` (gate: molde `metricas_vendedores_fn:793-835`): `marcador`, `compromisos` (tareas pendientes futuras llamada/cita sobre leads en `contactado`/`propuesta_enviada`), `sin_conversacion` (estrena `crm.politica_abandono.dias_abandono` con `greatest(última conversación real, tenencia_desde)`; los intentos no protegen), `telefonos` por lead de la cola (teléfono, segundo número, última observación de número errado), `intentos`, `descartados_hoy` (para el deshacer), `generado_en`. La cola sigue saliendo de `crm.cola_accion_v2_fn` (md5 en el preflight).

**Front — LO QUE SE CONSTRUYÓ.** La descripción original de este punto describía la pantalla
apilada, que se rehízo el mismo día (ver «Lo que la Fase 3 cambió del plan»). Lo que hay:
`screens/gestion-diaria/analista.tsx` con DOS paneles —`tarjeta-ahora.tsx` y `cola-de-hoy.tsx`— y
el segundo nivel `mi-actividad.tsx`. La cola sigue saliendo de `listarColaSla` (v2) ordenada por
`ordenarColaDiaria()`, la función pura del plan, que NO cambió. `chip-tiempo.tsx` dice el tiempo en
palabras. `GuardadosSlaPendientes` se monta una vez en `App.tsx`. **Descartados:** la `StatStrip`
(nace a 12 px) y el salto automático a la fila siguiente (ahora «Ahora» avanza por derivación).

**Despliegue:** SQL primero, front después. Codex: 1.

---

### Lo que la Fase 3 cambió del plan, y que GOBIERNA de aquí en adelante

Escrito el 20/09/2026, después de construirla, enseñarla y corregirla con los analistas.

#### 1. Densidad: el layout es de DOS paneles, no una columna

El plan y el mockup `4-analista-mi-dia.html` apilaban cola, marcador, seguimiento y descartes.
Se construyó así y los analistas devolvieron: **«demasiada información, muchas letras pequeñas»**.
27 entidades en pantalla, texto hasta 10 px, scroll para ver la mitad y 16 botones azules.

Lo que quedó, y que **F4 y F5 nacen así**:

- **Dos paneles en una fila.** «Ahora» (la persona que toca, su contexto y la ÚNICA acción
  primaria) y la lista, con los grupos como PESTAÑAS y su conteo: una sola lista a la vista.
- **Cuatro tamaños de letra y NINGUNO por debajo de 16 px** — 24/32-700, 20/28-600, 18/28-500,
  16/24-400. Hay un e2e que lo mide sobre el estilo CALCULADO de cada nodo con texto, no sobre
  la clase escrita: si alguien mete un `text-xs` dentro, el test se cae.
- **Una sola acción primaria visible por pantalla.** El resto, secundario o detrás de «···».
- **Lo secundario se pliega a un segundo nivel**, no se encoge. El marcador, el gráfico por
  hora, el seguimiento y los descartes viven en «Mi actividad», que conserva pestaña, página y
  persona elegida al volver. La `StatStrip` del plan NO se usa: nace a 12 px.
- **Sin huecos grises:** los paneles y las filas estiran para llenar el alto.

Las primitivas `Tabs` y `AccionesContacto` ya tienen tamaño grande (`tamano="grande"`, `grande`)
sin cambiar cómo se ven en el resto del CRM. `PanelVacio` tiene `tamano="grande"`.

#### 2. La sigla «SLA» no se dice en pantalla

Se dice el tiempo: «Quedan 40 min», «Se pasó hace 45 min», «El tiempo corre desde que te lo
asignaron». La sigla puede seguir en nombres de funciones y columnas. Hay un test que la prohíbe
en las ayudas de los grupos.

Y un hallazgo que F4 y F5 reutilizan: **`referencia_en` YA es el vencimiento** que manda
`cola_accion_v2_fn`, así que el chip se calcula en el navegador, sin pedir nada nuevo al
servidor. La EXCEPCIÓN es `sin_conversacion`, cuya referencia es la última conversación y no un
límite: lleva su propio texto. Y el tono «vencido» equivale exactamente a `severidad = 'critica'`,
por eso el chip «Crítica» desapareció sin perder información.

#### 3. LA REGLA DE LA CACHÉ PARCIAL (la que más caro salió)

> **Una ausencia en una caché o colección parcial significa «desconocido», nunca «no existe».**
> La caché puede cambiar la latencia, pero nunca lo que la pantalla muestra ni lo que deja hacer.

Desde la Fase 4 «sin topes» el store **ya no carga todos los leads**: los trae por demanda. La
cola viene de OTRA consulta que **no trae el teléfono**. Cruzar las dos tratando la parcial como
completa produjo CINCO bugs, uno de ellos en producción:

| # | Síntoma | Arreglo |
|---|---|---|
| 1 | Sin «Llamar» hasta abrir la ficha (reportado por Miguel) | se pide el lead al elegir la fila, con deduplicación y guarda de carrera |
| 2 | El resultado podía cerrar OTRA tarea, o ninguna | `tarea_id` de la fila es autoritativa: se pide por id, nunca se adivina |
| 3 | Con la cola caída, «Vencidas (0)» | dice «?»: no está vacío, no se sabe |
| 4 | Un lead sin `senal` salía «sin gestiones» | «Historial no cargado» ≠ «Sin gestiones previas» |
| 5 | «Registrar resultado» navegaba a la ficha para cargar | queda en «Abriendo…» mientras pide |

**Para F4 y F5:** `gestion_diaria_equipo_fn` y la de gerencia tienen que ser **proyecciones
autosuficientes** —traer lo que la pantalla pinta— o la pantalla debe **hidratar por id** de
forma explícita. Y todo estado remoto distingue cuatro cosas: cargando, vacío de verdad, error y
sin autorización. Nunca un `?? []` que las mezcle.

#### 4. Lo que el plan decía y NO se hizo

- **`telefonos` por lead en la puerta**: la puerta no lo devuelve. El teléfono se hidrata desde
  el store. Si F4 necesita contacto directo desde la tabla del equipo, hay que decidirlo: o la
  puerta lo trae, o se hidrata igual.
- **`StatStrip`**: descartada por tamaño (ver 1).
- **El salto automático a la fila siguiente al guardar**: ahora «Ahora» pasa al siguiente por
  derivación, y el lead recién cerrado se oculta hasta que el servidor contesta.

#### 5. Decisión de color ya resuelta

El nivel **«Bajo»** conserva el ÁMBAR publicado en PR #55. El rojo se reserva a plazos
vencidos; no se vuelve a presentar esta decisión como pendiente.

---

### Fase 4 — Supervisor «Mi equipo hoy» · LEVEL 3 · 1 migración + 1 PR

**Objetivo general:** que el supervisor detecte a tiempo los problemas de su equipo, pueda
investigarlos y sepa dónde intervenir desde una misma pantalla. Se reutilizan el registro de
actividades de F1, los resultados tipificados de F2 y el núcleo diario construido en F3.

**Estado al 21/09:** etapa 1 publicada desde `526e728e`, PR #62. SQL
`20260921040335_crm_gestion_diaria_equipo_vista.sql` instalado y registrado;
etapa 2 publicada desde `baa63aea`, PR #64; etapas 3–6 pendientes. Conserva las dos columnas y desplegables del taller,
caché parcial y tarea autoritativa, paginación y pestañas vacías, avance tras llamada,
legibilidad de 16 px y protección de los avisos de supervisión.
Historial de implementación: `F4-VISTA-EQUIPO-IMPLEMENTACION.md`.
Evidencia productiva y recuperación: `PUBLICACION-2026-09-21.md` (etapa 1) y
`F4-ETAPA2-PUBLICACION-2026-09-21.md` (etapa 2 vigente).

Las seis etapas siguientes organizan la entrega de F4; no son seis fases globales nuevas
ni exigen una migración por etapa. Sus objetivos y
criterios de cierre se acordaron con Miguel el 20/09/2026. TypeSafe se incorpora después como
F4.1 y no participa en los cálculos ni permisos de esta fase.

#### F4 · Etapa 1 — Vista «Mi equipo hoy»

Publicación del 21/09: `npm run check` y CI PASS (4.016 pruebas); navegador
completo PASS (231 aprobadas, 26 omisiones). Puerta productiva comprobada como
dos Gerencia y tres Supervisores: roster exacto de 18/18/10/0/8 analistas,
fechas hasta 365 días y denegación de ámbitos ajenos. No se crearon datos de
negocio para estas comprobaciones. El recorrido humano sigue pendiente.

Validación local tras reconciliar: `npm run check` PASS (3.991 pruebas); navegador completo, 225 pruebas aprobadas y
26 omisiones preexistentes; tres oráculos SQL bajo identidad autorizada, nueve mutantes
nuevos y 48 previos, cotejo de tipos y advisors PASS. Se reprodujo y corrigió el hallazgo
de Claude sobre descendientes activos bajo un supervisor intermedio inactivo. Incluye
cero actividad y cartera vacía, orden por tasa con muestras pequeñas al final, foco de
teclado y recuperación ante errores. No acredita aún un recorrido humano en producción.

El objetivo es que el supervisor identifique quién tiene actividad registrada hoy, quién
tiene pendientes y quién necesita atención, incluyendo a los analistas sin actividad. Los
registros aportan evidencia del trabajo registrado; no acreditan que alguien esté trabajando
en este instante ni explican por sí solos una ausencia. La pantalla reúne un resumen y una tabla
con llamadas, contestadas, llamadas útiles, tasa de contacto, leads distintos trabajados,
llamadas por lead, primera y última llamada, tiempo sin llamar, tareas vencidas, primeros
intentos fuera de plazo y citas del día. La situación frente a los cortes y los avisos se
incorporan al completar las etapas 3 y 4; no son requisito para cerrar esta primera etapa.

Se considera lograda cuando el supervisor puede buscar y ordenar analistas, filtrar «Con
problema hoy» y ver también a quienes tienen cero actividad. La tasa lleva porcentaje y
conteo; Bien/Atención/Bajo solo se aplica con al menos cinco llamadas útiles, según la política
vigente. Su ámbito se limita al equipo autorizado y la proyección procede del servidor.

#### F4 · Etapa 2 — Detalle y registro del analista

**Estado al 21/09:** publicada y verificada desde `baa63aea`, con conformidad
visual de Miguel en local y cierre técnico. Acta de publicación:
[F4-ETAPA2-PUBLICACION-2026-09-21.md](F4-ETAPA2-PUBLICACION-2026-09-21.md).
Implementación: [F4-DETALLE-ANALISTA.md](F4-DETALLE-ANALISTA.md). No requiere una
migración nueva: utiliza `marcador.por_hora` de F4 y el registro paginado de F1.
Cada fila mantiene sus indicadores y añade conteos legibles de llamadas y
contestadas por hora (08–20 Lima), declarando también las llamadas fuera de la
franja. «Ver llamadas del día» abre Llamadas; «Ver registro» abre Todo, del
analista seleccionado. La selección fija no muestra un filtro engañoso de
«Todos los analistas». El registro conserva texto íntegro, tipos, etapas y
acceso a ficha; su cuerpo y controles respetan 16 px.

El recorrido comprobado incluye una ficha ausente del boot, retorno de foco,
paginación, actualización real desde página 2 y retirada de páginas acumuladas
al recibir una revocación. No atribuye ausencia a un vacío filtrado ni sustituye
por ceros un desglose horario inconsistente. Los avisos automáticos de cortes
siguen pendientes de las etapas 3–4; el acceso actual parte de la fila y su
motivo de atención. La revisión visual local está conforme; permisos y
paginación real de solo lectura y comprobación HTTP/hashes productiva PASS.
Queda el recorrido humano autenticado; no se atribuye una matriz Auth/HTTP
ni una auditoría de paridad entre las dos lecturas del servidor.

El objetivo es explicar los indicadores mediante las actividades que los originan. Cada fila
permite desplegar llamadas por hora de Lima, abrir el registro del día y llegar a la ficha
del lead: alerta → analista → actividad concreta → ficha.

Se considera lograda cuando el supervisor puede investigar una situación sin buscar por
separado al analista o al lead. Se reutiliza el registro de F1 y se conserva la legibilidad
aprendida en F3. Cargando, vacío real, error y sin autorización son estados distintos; una
ausencia en una caché parcial nunca se convierte en «no hizo nada».

#### F4 · Etapa 3 — Cortes de la jornada

**Estado:** implementada y verificada únicamente en local; publicación pendiente.
Candidato `20260921214018_crm_gestion_diaria_cortes.sql`, política inicial OFF.
La base de ensayo terminó restaurada; no hay instalación productiva ni cambios
visibles de pantalla. [Detalle, checks y límites](F4-CORTES-JORNADA.md).

El objetivo es detectar un ritmo de llamadas inferior al esperado durante el día con reglas
explícitas y configurables. De lunes a viernes se evalúa a las 11:30 un mínimo inicial de tres
llamadas y a las 16:00 el acumulado del primer corte multiplicado por 2,5, redondeado hacia
arriba, con piso de ocho y techo de treinta. Estos son valores iniciales de la política
configurable, no constantes permanentes. La base es el acumulado registrado hasta las 11:30:
no aumenta con las llamadas posteriores ni cuando se resuelve el primer aviso. Son acumulados
del día, no llamadas adicionales exigidas exclusivamente por la tarde. Con base cero se
exigen ocho; con ocho, veinte; con
veinte, treinta por el techo.

Se considera lograda cuando los cálculos del servidor respetan `America/Lima`, cuentan toda
llamada registrada, incluyen a quien lleva cero si tiene leads abiertos asignados,
aplican el sábado solo el corte de las 11:30 con mínimo inicial de tres y no emiten
avisos de jornada el domingo. Sin cartera abierta, el analista permanece en la tabla
pero queda excluido del aviso de corte. El primer aviso se retira
si el analista alcanza el mínimo antes de las 16:00; el resultado del segundo corte permanece
aunque llame después. La política aplicable queda fijada al inicio de la jornada consultada.

#### F4 · Etapa 4 — Alertas y seguimiento del supervisor

El objetivo es que el supervisor conozca los problemas y pueda actuar desde el aviso. El
pop-up agrupa a los analistas afectados por corte y muestra quién, cuánto lleva y cuánto se
esperaba, con acceso a su registro. Reutiliza el `Dialog` existente, espera mientras haya
otro diálogo abierto o el supervisor esté escribiendo y no reaparece en cada refresco.

Se considera lograda cuando el reconocimiento y el aplazamiento de una hora se guardan en
servidor, se respetan entre dispositivos y se reflejan igual en el pop-up, la campana y la
lista. Los reavisos pedidos expresamente al posponer se distinguen de una aparición duplicada.
Se permite un solo aplazamiento por aviso, supervisor y día Lima. No hay reaviso
a las 18:00 o después entre semana, ni a las 13:00 o después el sábado; el pendiente
sigue visible sin convertirse en resuelto. No se arrastra un reaviso al día siguiente.
Los avisos de inactividad, tareas vencidas, primeros intentos fuera de plazo y leads por
repartir se agrupan sin repetir el mismo problema. La alerta de tasa muy baja empieza
desactivada. No se silencian feriados por inferirlos de una baja actividad.

#### F4 · Etapa 5 — Configuración gerencial

El objetivo es que gerencia ajuste las exigencias a la operación sin cambiar código. La
pantalla propia de Gestión Diaria permite configurar horas, mínimos, incremento, piso y
techo del segundo corte, mínimo del sábado y umbrales de contacto. Presenta ejemplos del
cálculo, la política vigente y las revisiones programadas.

Se considera lograda cuando solo gerencia puede publicar cambios, cada publicación crea una
versión con vigencia desde una jornada futura y dos ediciones simultáneas no se pisan. Un
cambio no modifica las reglas de días anteriores. El histórico avisa que usa el equipo y la
jerarquía actuales. Esta pantalla es parte de F4; no se difiere al tablero global de F5.

#### F4 · Etapa 6 — Validación y activación

El objetivo es poner en uso una funcionalidad confiable y comprobar el recorrido completo del
supervisor. El orden de construcción comienza por reglas, cálculos y autorización en servidor;
continúa con tabla y detalle, cortes y alertas, y configuración; termina con verificación y
activación. Esta secuencia técnica sostiene las seis etapas de producto anteriores.

Se considera lograda con pruebas de permisos por identidad, equipos ajenos, cero actividad,
límites horarios de Lima, sábado y domingo, recuperación del primer corte, permanencia del
segundo, reconocimiento entre dispositivos y vigencias históricas. Se comprueban las
regresiones de F1–F3, los estados de consulta y la accesibilidad del pop-up; se ejecutan los
gates del repositorio y una prueba de negocio del flujo completo. Claude apoya la revisión
mediante el wrapper del proyecto; sus hallazgos se contrastan con evidencia y no reemplazan
las pruebas.

La base se instala con cortes desactivados en la versión histórica inicial. Después del
servidor se publica el frontend; comprobado el funcionamiento, gerencia publica la versión
que activa los cortes desde una jornada futura. F4 se puede cerrar y operar por completo con
TypeSafe desactivado.

#### Decisiones cerradas por Miguel el 21/09/2026

El sábado, de 09:00 a 13:00, hay un único corte a las 11:30 con mínimo inicial
de **tres llamadas**. Sigue siendo una perilla independiente de gerencia.

Los analistas **sin ningún lead abierto asignado no reciben el aviso de ritmo
de los cortes**, aunque permanecen visibles en la tabla. No se extiende esta
exclusión por inferencia a tareas vencidas ni a todas las demás alertas.

**«Posponer 1 hora» se permite una sola vez por aviso, supervisor y día Lima**,
guardado en servidor y respetado entre dispositivos. No se reavisa al llegar
el cierre o después (18:00 L–V; 13:00 sábado), ni se difiere al siguiente día.
El pendiente permanece visible, sujeto a las reglas de resolución del primer
y segundo corte ya acordadas. Ejemplos: sábado 11:30 → 12:30 puede reavisar si
sigue vigente; sábado 12:15 → 13:15 no; entre semana 17:00 → 18:00 tampoco.

Estas decisiones ya no son bloqueos de negocio. **No equivalen a implementación,
instalación de SQL ni activación.** Los cortes siguen apagados hasta verificar
etapas 3–6 y publicar una política futura. Se añaden pruebas de cartera vacía,
aplazamiento repetido/concurrente, cambio de dispositivo y límites exactos del cierre.

#### Contrato técnico de la entrega

**Qué obtiene Miguel:** el supervisor ve, ordenado por problema, quién se está cayendo hoy y la tabla de su equipo con el ratio llamadas/lead; desde cada fila abre el registro de la Fase 1.

**Servidor (`…_crm_gestion_diaria_equipo.sql`):** `crm.gestion_diaria_equipo_fn(p_dia date default null, p_supervisor_id uuid default null)` (supervisor: su subárbol; gerencia: cualquier equipo; vendedor: 42501). Devuelve `equipo` (una fila por analista activo del núcleo + `vencidas` canónicas + `citas_hoy` + `primer_intento_vencido` + `llamadas_por_hora` [24 enteros, hora Lima, decisión #8]), `resumen`, y `alertas[]` en servidor con `private.gestion_diaria_umbrales()`: `tasa_baja` (nace VACÍA), `parado_2h`, los CORTES DEL DÍA (abajo; sustituyen al `sin_llamadas_hoy` de las 11:00), `primer_intento_vencido` (asignaciones con `primera_gestion_en is null` y `primera_gestion_limite_en < now()`, leídas del núcleo SLA por definer), `tarea_vencida` y `por_repartir` (estos dos como UN grupo por supervisor, con `miembros[]`, `tipo` en singular exacto). Postflight que ensaya identidad por identidad (`set_config('request.jwt.claims')`, patrón `20260916205617:240-379`). `auditor-rls`, `test-rls`.

**Front:** `components/gestion-diaria/tabla-equipo-diaria.tsx` (UNA tabla para supervisor y Nivel 3 de gerencia; `jscpd` 0,8 % vigila) sobre `common/tabla.tsx`, orden por columna con `aria-sort` (pocas llamadas al final), chips con texto («55 % · Bien», «100 % · 2 llamadas»), fila expandible con las barras «llamadas por hora» del analista (decisión #8), patrón responsive de `ranking-vendedores.tsx`, buscador de analista y chip «Con problema hoy» (filtros de cliente). `components/gestion-diaria/alertas-del-dia.tsx`: 1 rojo por decisión, máx. 2 ámbar; conservar Reconocer/Posponer en `tarea_vencida` y `por_repartir` mediante `alertaDiariaAAlertaCRM()`, `reconocerAlertaSupervisor` y `aplicarReconocimientos`. Extender ese mecanismo para los cortes, con identidad por supervisor, jornada y corte, y aplazamiento propio de una hora. Los demás avisos siguen retirándose al resolverse. `screens/gestion-diaria/supervisor.tsx` con resumen legible, tabla y detalle del registro; `config-gestion-diaria` para gerencia dentro de esta misma fase. Tests + estado real + e2e Supervisor.

**Despliegue:** SQL primero, front después. Codex: 1.

---

#### F4 · Los CORTES DEL DÍA y sus perillas (decisiones de Miguel, 20/09/2026)

Sustituyen a la alerta «sin llamadas a las 11:00» del plan original, que nunca se probó contra
datos reales. Miguel fijó dos cortes y una regla: **los números los pone GERENCIA, no el código.**

##### Los dos cortes

| Corte | Hora (Lima) | Qué exige | Si no se cumple |
|---|---|---|---|
| **Primero** | **11:30** | un mínimo de llamadas, configurable | avisa al supervisor con un aviso que **exige atención** |
| **Segundo** | **16:00** | **150 % MÁS** que lo que tenía en el primer corte | avisa al supervisor |

**«150 % más» es la lectura literal, confirmada:** con 20 llamadas a las 11:30, el segundo corte
exige **50** (20 + el 150 % de 20 = ×2,5). Para que nadie vuelva a dudar, **la pantalla de
gerencia muestra la cuenta en vivo** mientras se escribe el número: «con 20 llamadas al primer
corte, exige 50 al segundo». La perilla se guarda como el porcentaje, no como el multiplicador.

Ese ejemplo explica la multiplicación **antes de aplicar el techo**. Con el techo inicial de
30, el objetivo final del ejemplo es 30, no 50. La pantalla muestra el cálculo y el objetivo
final acotado, para que no parezcan dos exigencias distintas.

##### Los valores de arranque, medidos contra producción (20/09/2026)

Se midieron **90 días reales: 22 analistas, 399 días de trabajo** (lectura de solo lectura sobre
`crm.actividades`, llamadas realizadas + no contestadas, hora de Lima, sin domingos).

**Lo que hace el equipo HOY:**

| | A las 11:30 | A las 16:00 | Todo el día |
|---|---|---|---|
| La mitad de los días | **2** | **7** | **10** |
| 1 de cada 4 (los buenos) | 5 | 13 | 17 |
| 1 de cada 10 (los muy buenos) | 10 | 22 | 28 |
| Récord | — | 56 | **70** |

**Por qué los números de arranque son los que son.** Se simularon contra esos 399 días:

| Mínimo a las 11:30 | Días que fallarían |
|---|---|
| 8 | **82 %** |
| 5 | 71 % |
| **3** | **54 %** |
| 2 | ~35 % |

Un mínimo de 8 —la primera intuición— haría saltar la alerta **8 de cada 10 días**. Eso no es una
alerta: es ruido, y el supervisor la apaga mentalmente en una semana. **Miguel fijó 3** el
20/09/2026: señala a la mitad peor, que es algo real, sin quemar la alerta.

El **techo casi no cambia nada**: con 25 recortaría el 8 % de los días, con 30 el 6 %. Se pone en
**30** porque sin él la cuenta llegaría a pedir **73** llamadas en la tarde de una mañana
excepcional, que es más que el récord absoluto del equipo en un día entero.

**Valores con los que nace la versión 2 (los que gerencia publica el primer día):**

| Perilla | Arranque | Por qué |
|---|---|---|
| Hora del primer corte | **11:30** | decisión de Miguel |
| Mínimo de llamadas al primer corte | **3** | fallaría el 54 % de los días; con 8 sería el 82 % |
| Hora del segundo corte | **16:00** | decisión de Miguel |
| Crecimiento exigido | **150 %** | decisión de Miguel: con 20 exige 50 |
| Piso absoluto del segundo corte | **8** | decisión de Miguel: caza al que llegó a mediodía con cero |
| Techo absoluto del segundo corte | **30** | sin él la cuenta pediría hasta 73, más que el récord del equipo |
| Mínimo del sábado (medio día) | **3** | aprobado por Miguel el 21/09/2026 |
| Tasa muy baja | **vacía** | no hay dato; la produce el reporte de F5 |

**Todos son perillas: gerencia los sube cuando el equipo suba.** Ese es el punto de que sean
configurables y no constantes en el código.

##### Dos cosas que la medición dejó a la vista, y que no son de F4

- **Diez llamadas al día de media es poco** para un equipo comercial. Puede que llamen más de lo
  que registran — y entonces el problema es de REGISTRO, no de actividad. Lo aclara el reporte de
  hábitos de F5.
- **399 días con llamadas entre 22 analistas en 90 días** son unos 18 días por persona. O no todos
  llaman a diario, o no todos registran. Mismo reporte.

##### Qué configura gerencia, y qué NO

Configurables desde la pantalla de gerencia, con valores de arranque:

- **Hora del primer corte** — 11:30.
- **Llamadas mínimas al primer corte** — **3** de arranque, medido (ver arriba).
- **Hora del segundo corte** — 16:00.
- **Crecimiento exigido en el segundo corte** — 150 %, con **piso 8** y **techo 30**.
- **Mínimo del sábado** — independiente; **3** de arranque, aprobado el 21/09/2026.
- **Umbrales de contacto** — 45 / 25 / 5 de arranque, dentro de la misma política versionada.
- **Tasa muy baja** — **nace VACÍA y esa alerta NO salta hasta que se ponga.** Decisión explícita
  de Miguel: «todavía no hay esa data». El reporte de F5 (abajo) es el que la va a producir.

NO configurable: **«parado» = más de 2 horas sin llamar**, dentro de 09:00–18:00 L–V y
09:00–13:00 sábado; domingo sin avisos de jornada.

##### La semana laboral (decisión de Miguel, 20/09/2026)

| Día | Jornada | Cortes |
|---|---|---|
| Lunes a viernes | 09:00 – 18:00 | **dos**: 11:30 y 16:00 |
| **Sábado** | **09:00 – 13:00** | **UNO: 11:30** |
| **Domingo** | no se trabaja | **ninguno**; no salta ninguna alerta |

**Por qué el sábado lleva un solo corte:** la jornada acaba a las 13:00, así que un corte a las
16:00 no existe. El de las 11:30 sí encaja — cae a dos horas y media de empezar, exactamente igual
que en un día entre semana. El sábado tiene su **propio mínimo de llamadas**, también configurable:
Miguel fijó **3** el 21/09/2026; no hay segundo corte de tarde.

El domingo la pantalla no calcula cortes ni pinta alertas de este tipo. Si un analista trabaja un
domingo, sus llamadas se registran igual: lo que no se hace es juzgarlas contra un corte.

**Ojo con la ventana de «parado»:** hoy es 09:00–18:00 todos los días. El sábado tiene que cerrarse
a las 13:00, o marcará como «parado» a todo el equipo cada sábado por la tarde.

##### El aviso: un POP-UP (decisión de Miguel, 20/09/2026)

Miguel lo pidió así de claro: *«un aviso tipo pop-up para que se les haga complicado ignorar»*.
Un chip en una lista se ignora; un diálogo, no.

Reglas para que sea eficaz y no odioso — todas obligatorias:

- **Una vez por corte y por día.** Salta al llegar el corte, o la primera vez que el supervisor
  abre la pantalla después de esa hora si el problema sigue vigente. No se repite por un
  refresco o cambio de dispositivo; el reaviso solicitado expresamente al posponer se trata
  por separado: una sola vez por aviso/supervisor/día Lima, sin reaviso al cierre o después.
- **Se reconoce, y el reconocimiento se guarda EN EL SERVIDOR.** Si viviera en el navegador,
  volvería a saltar al cambiar de equipo o de máquina, y eso es lo que mata una alerta.
- **Dice quién y cuánto**, no «hay incumplimientos»: la lista de analistas con su cifra y lo que
  se esperaba. Desde ahí se entra a su día.
- **Nunca interrumpe algo a medias:** si hay otro diálogo abierto o el supervisor está escribiendo,
  espera. Un pop-up que se come una tecla se gana el odio el primer día.
- **No salta en domingo**, ni por un corte que no aplica a ese día.
- **Se puede posponer una hora, una sola vez por aviso/supervisor/día**; queda registrado
  quién lo hizo. Al cierre o después no se reavisa ni se agenda para el siguiente día:
  el pendiente sigue visible sin marcarlo como resuelto.

Va sobre el `Dialog` que ya existe en el CRM (Radix, con trampa de foco, `Escape` por capas y
retorno de foco), no sobre uno nuevo.

**Lo que la revisión añadió, y que es lo que hace que funcione:** hoy en esta app no existe nada
bloqueante, y Codex desaconseja un modal que no se pueda cerrar. Pero encontró la razón por la que
el pop-up **necesita** el reconocimiento en servidor, y no es un detalle técnico:

> El corte de las 16:00 **no cesa**: es un hecho del pasado. Sin una forma de cerrarlo, el aviso
> sería papel pintado a las 16:05 — y una alerta que no se puede apagar deja de ser una alerta.

El de las 11:30 sí puede apagarse solo, si el analista se pone al día antes del segundo corte.
Así que: **pop-up que exige reconocer, reconocimiento guardado en el servidor, y el aviso de las
11:30 se retira solo si se resuelve.** Además, contador en la campana del topbar, que ya existe.

##### Las dos reglas que Miguel cerró (20/09/2026)

**1 · El corte cuenta TODA llamada, no solo las «útiles».**

Entran `llamada_realizada` y `llamada_no_contestada`; NO se descuenta el número errado ni el «no
es la persona». El corte mide **actividad**: si marcó, marcó. La **calidad ya la mide la tasa de
contacto**, que es otra cosa y tiene su propio umbral.

Y hay una razón práctica: si el corte descontara las llamadas inútiles, un analista con una lista
de números malos aparecería como si no hubiera trabajado — y el problema de esa lista no es suyo.

*(La medición del 20/09 que fijó los valores de arranque se hizo con esta definición: toda llamada.
Si se cambiara a «solo útiles», esos números dejan de valer y hay que volver a medir.)*

**2 · El fallo de las 11:30 SE BORRA si se pone al día antes de las 16:00.**

El primer corte es un empujón, no un expediente. Si a las 11:30 lleva 1 llamada y a las 13:00 ya
lleva 6, el aviso **se retira solo** y no deja rastro en la pantalla del supervisor.

El de las 16:00 **no se borra**: cierra el día. Es lo que justifica que ese sí exija reconocer y
el otro no (ver el apartado del pop-up).

Consecuencia para el pop-up de las 11:30: se comprueba si el fallo **sigue vigente** en el momento
de pintarlo, no si ocurrió. Un supervisor que abre el CRM a las 15:00 no debe ver un aviso de las
11:30 que el analista ya resolvió a mediodía.

##### Quien tiene CERO llamadas entra en el aviso del corte

Parece obvio y es justo lo contrario de lo que salía a la primera: si a quien no ha llamado nada
se le deja solo en la alerta «sin llamadas», **el que peor está recibe el aviso más débil**. Entra
en el grupo del corte, y es «sin llamadas» lo que se calla para no decir dos veces lo mismo.

##### Los feriados: la alerta NO se silencia sola

El CRM no conoce el calendario laboral peruano, y **no se va a inferir**. La tentación era
silenciar el aviso cuando casi nadie del equipo llamó — pero eso apaga la alarma exactamente el día
en que nadie llamó, que es el día que más importa. En su lugar: **el aviso sale siempre**, y cuando
la actividad de todo el equipo está por los suelos lleva una marca de contexto («actividad
excepcionalmente baja en todo el equipo — revisa si hoy es feriado o hubo una incidencia») y se
presenta como UNA alerta de equipo, no como N individuales. Silenciar un día es una decisión
explícita de alguien, nunca una deducción del código.

##### Cómo se guarda, y por qué VERSIONADA y no una perilla que se pisa

Diseñado con Codex el 20/09/2026. Tabla nueva `crm.politica_gestion_diaria`, con el molde
**versionado con vigencia** de `crm.sla_politicas`, **no** el singleton de `crm.politica_abandono`.

**El motivo es uno y es duro:** la puerta de F3 ya admite consultar **días pasados** (hasta un año
atrás). Con una fila que se pisa, el martes pasado se re-juzgaría con la perilla de hoy — y eso
convierte un historial en una ficción. Absorbe además los tres umbrales que hoy están a fuego
(45 / 25 / 5), para que siga habiendo **una sola** fuente.

Reglas que salieron de la revisión y que no son negociables:

- **La versión 1 se siembra con los umbrales de hoy y los cortes APAGADOS.** Los cortes nacen en la
  versión 2, la que Miguel publique. Sembrarlos desde el principio haría parecer que la obligación
  existía antes de inventarla, y juzgaría hacia atrás a gente que no la conocía.
- **La política del día se resuelve al AMANECER de esa jornada**, no con la hora actual. Publicar
  al mediodía no puede cambiar las reglas de un corte que ya ocurrió esa mañana. Y `vigente_desde`
  tiene que ser el inicio de una jornada futura: **las reglas del día se fijan al amanecer y no se
  mueven**.
- **Solo gerencia escribe**, y por una función con `expected_version`: dos personas editando a la
  vez no pueden pisarse. Ninguna escritura directa por la API.
- **El cálculo vive en el núcleo**, no en la puerta ni en la pantalla, componiendo
  `private.gestion_diaria_llamadas` que ya está en producción. Una sola definición de «llamada».

##### El objetivo del segundo corte, con sus bordes

`objetivo = min(techo_absoluto, max(redondear_hacia_arriba(base × (1 + incremento_pct / 100)), piso_absoluto))`.

La base es el acumulado al primer corte; el resultado se compara con el total acumulado al
segundo corte. Con los valores iniciales, base 0 → 8, base 8 → 20 y base 20 → 30.

- **Se redondea hacia ARRIBA.** «Al menos un 150 % más» de 8 llamadas es 20; pero si el porcentaje
  fuera 30 %, 8 × 1,3 = 10,4 y «al menos» significa **11**, no 10. Con 150 % el error queda oculto
  porque salen enteros — por eso conviene fijarlo ahora.
- **Un piso absoluto**, porque si a las 11:30 lleva **cero**, la cuenta siempre se cumple (0 × 2,5
  = 0) y el que peor está sería el único que aprueba.
- **Un techo absoluto**, porque si la mañana fue excepcional —40 llamadas— exigir 100 por la tarde
  no es una meta, es una trampa.

##### Lo que hay que resolver al construirlo

- **Dónde se guarda (resuelto).** Política versionada e inmutable con vigencia, siguiendo
  `crm.sla_politicas`, con RLS y escritura solo de gerencia por función. La recomendación de
  `singleton` quedó superada. `private.gestion_diaria_umbrales()` leerá la política vigente.
- **Quién calcula el corte.** El SERVIDOR, nunca la pantalla: los dos cortes son hora de Lima y el
  navegador del supervisor puede estar en otro huso.
- **El analista que entró a media mañana.** Con permiso, una capacitación o media jornada: el
  corte no se prorratea en esta primera entrega; se muestra la primera llamada para aportar
  contexto al supervisor. No se deduce de las llamadas el motivo de una ausencia o un permiso.
- **Dónde se guarda el reconocimiento del pop-up.** La tabla de reconocimientos que ya existe tiene
  los tipos cerrados por CHECK: ampliarla exige una migración a propósito, que es lo correcto.
- **Decisiones de negocio cerradas el 21/09:** sábado mínimo 3, exclusión de cartera vacía
  solo en los avisos de corte y aplazamiento único sin reaviso al cierre o después. Falta
  implementar/verificar y activar con vigencia futura; no volver a pedir estas decisiones.
- **Un día pasado se recalcula con el equipo y la jerarquía de HOY**, no con los de entonces. Hay
  que decirlo en pantalla. Si algún día esto se usa para evaluar desempeño, hará falta guardar la
  evaluación del día, que es un contrato distinto y más caro.
- **El riesgo de siempre:** una alerta que salta de más se ignora a la semana, y entonces da igual
  lo bien construida que esté. Por eso los números los pone gerencia y no el código.

---

### Fase 4.1 — Revisión asistida de registros con TypeSafe

**Objetivo general:** reducir el esfuerzo del supervisor al revisar registros, señalando
posibles contradicciones entre el resultado tipificado de una llamada y la nota escrita por
el analista. El añadido al plan fue aceptado por Miguel el 20/09/2026. **Estado al 21/09:
arranque técnico local implementado y acceso a la API verificado; piloto humano e integración
del CRM pendientes.** Miguel pidió también apoyo técnico de Jev a las revisiones y confirmó
que ambos supervisores validarán las notas, cada uno las de su propio equipo.
La responsabilidad queda definida por el equipo; no se espera elegir a uno solo.
No se enviaron registros reales.

**Preparación humana local posterior:** guía de clasificación y banco ciego de veinte
casos ficticios para ambos supervisores, con exportación/reanudación por espacio y
comparación de acuerdo. No autentica identidades ni admite notas reales; las revisiones
humanas aún no se ejecutaron. Protocolo, tratamiento de datos y criterios propuestos:
[F4.1-GUIA-REVISION-HUMANA.md](F4.1-GUIA-REVISION-HUMANA.md). Ni acuerdo sintético ni
confianza del modelo habilitan producción.

Es una entrega posterior y separada de F4. Su activación depende de la utilidad demostrada
por el piloto; no es requisito para cerrar F4 ni para construir F5. TypeSafe interpreta
texto: los conteos, cortes, tasas, horarios, permisos y decisiones oficiales siguen en el
código del CRM.

#### F4.1 · Etapa 1 — Piloto de utilidad

El objetivo es comprobar si TypeSafe detecta contradicciones útiles con pocas falsas alarmas
en las notas reales del negocio. Se prepara una muestra anonimizada de aproximadamente
100–200 registros en español, con resultado y nota, revisada por una persona. Debe incluir
casos compatibles, contradicciones, notas cortas, ambigüedad, negaciones y referencias a
conversaciones anteriores. Primero se confirma que el volumen y la calidad de las notas
permiten evaluar el caso; una nota como «se llamó» puede no aportar evidencia suficiente.

Antes de extraer o transferir esa muestra se acuerdan con ambos supervisores la
anonimización, los criterios de aceptación y la resolución de desacuerdos. Antes de la
primera transferencia real se debe rotar la clave expuesta y confirmar/aceptar la
retención y tratamiento aplicables a la cuenta; la política pública no acredita ZDR.
Primero ambos supervisores practican con el mismo banco ficticio sin ver la salida de
la IA. Las dudas sobre la guía no cuentan como acuerdos ni como notas insuficientes. La muestra
total de 100–200 notas debe representar a ambos equipos: cada supervisor recibe y
etiqueta solo las de su equipo, respetando el ámbito autorizado del CRM. La evidencia
de revisión conserva quién revisó y a qué equipo corresponde; se mide el resultado
por equipo, además del agregado, sin convertir el piloto en evaluación de personas.
Se separan por lead los ejemplos de ajuste de las notas reservadas para validación,
incluidos duplicados. Se mide por equipo con mínimos de casos positivos, denominadores
e intervalos de incertidumbre; muestra insuficiente no equivale a PASS. Un cambio de
modelo/pregunta exige nueva validación independiente. El ensayo técnico del
21/09 usa exclusivamente 20 fixtures sintéticos escritos por Codex, sin etiquetas humanas:
primera consulta por lote 20/20; control aislado v2 19/20 con una falsa alerta en «Se gestionó».
Se conserva el desacuerdo, sin rebajar umbrales para obtener un PASS. No cierra esta etapa.

Se usa una pregunta acotada de `Choice` con tres salidas: compatible, posible contradicción
e información insuficiente. Ejemplo sintético: resultado «No contestó» y nota «Conversamos
y confirmó la cita». «No le interesa» con una próxima llamada NO es una contradicción
por sí solo desde la decisión del 21/09. Se devuelve una sugerencia de revisión; el modelo no puede comprobar
que la llamada ocurrió ni que una de las dos versiones sea verdadera.

Se considera lograda esta etapa cuando existe una evaluación humana con aciertos, falsas
alarmas, contradicciones omitidas, cobertura, casos sin información suficiente, costo y
tiempo de respuesta. Se definen y calibran los criterios de aceptación antes de activar la
funcionalidad, sin convertir la confianza del modelo en garantía de exactitud. Si no aporta
valor o produce demasiado ruido, se documenta el resultado y la integración queda apagada.

#### F4.1 · Etapa 2 — Revisión asistida para el supervisor

El objetivo es llevar al registro del supervisor las sugerencias que hayan demostrado ser
útiles. La interfaz muestra «Posible inconsistencia — revisar», el resultado seleccionado y
la nota original, con acceso al registro y acciones para confirmar la observación o descartar
la sugerencia. La decisión se refiere a la sugerencia; no cambia automáticamente el resultado
de la llamada. Cualquier corrección del dato sigue los permisos y mecanismos del CRM.

Cada supervisor consulta, confirma o descarta únicamente sugerencias de su propio
equipo. La implementación debe comprobar ese ámbito en el servidor, tanto al leer
como al guardar la revisión, y probar que el otro supervisor no puede acceder o
resolver esas sugerencias. Se conserva la jerarquía y los permisos existentes;
esta aclaración no amplía el acceso de ningún rol.

Se considera lograda cuando las sugerencias se pueden revisar con evidencia, las respuestas
del supervisor permiten medir su utilidad y el servicio funciona sin interrumpir el trabajo.
La evaluación se ejecuta en segundo plano desde el servidor, con credenciales fuera del
navegador, contexto mínimo anonimizado o redactado, presupuesto acotado y permisos por equipo.
Se identifica la versión del registro, del modelo y de la pregunta para no mostrar resultados
obsoletos ni reevaluar lo mismo en cada apertura de pantalla. Un error o una indisponibilidad
de TypeSafe no bloquea registrar llamadas ni consultar Gestión Diaria.

Los mensajes de interfaz se construyen a partir de etiquetas y evidencia existente; no se
esperan explicaciones narrativas generadas por Jev. Las sugerencias no alteran indicadores,
no suprimen alertas de corte, no descartan leads ni califican automáticamente a trabajadores.
Tener instalada la skill de TypeSafe orienta la implementación, pero no conecta por sí solo
el CRM a la API ni acredita que exista una cuenta configurada.

#### Ampliaciones que se evalúan después del piloto

Una siguiente posibilidad es identificar compromisos escritos y comprobar si tienen
seguimiento. La comprobación de tareas se hace sobre datos completos y autorizados del
servidor, incluyendo su estado y contexto temporal, sin deducir que falta una tarea por su
ausencia en una caché parcial. No se duplican las reglas de seguimiento obligatorio de F2.

Para F5 se puede evaluar la clasificación de objeciones expresadas en las notas, por ejemplo
desconfianza, falta de fondos o dudas del producto, para orientar capacitación. Es una
posibilidad condicionada al piloto, no una clasificación ya disponible. Las horas de inicio,
huecos entre llamadas, tasas y cumplimiento de cortes de F5 se calculan con datos estructurados
y no requieren TypeSafe. No se infieren causas de baja actividad solo a partir de esas cifras.

#### Fuentes y verificación de F4.1

Diseño orientado por la skill local `typesafe-ai`, la documentación oficial de
[System One](https://docs.typesafe.ai/concepts/how-to-build-with-system-one), el patrón de
[verificación contra evidencia](https://docs.typesafe.ai/cookbooks/citation_check) y la guía de
[confianza](https://docs.typesafe.ai/confidence), consultadas el 20/09/2026. Antes de integrar
se consulta el contrato vigente de la API o SDK elegido y se valida con datos del dominio.

La consulta inicial del 20/09 a Claude sobre TypeSafe no produjo un dictamen válido;
no se registra como PASS. El 21/09 se consultaron el contrato HTTP y `Choice` vigentes y
se implementó el ensayo aislado sin datos reales. API y 14 tests del ensayo **PASS**;
comparación sintética aislada **FAIL (19/20, una falsa alerta)**, evidencia conservada.
Piloto humano, servidor de sugerencias e interfaz **NOT RUN / no implementados**.
No se autoriza transferir datos de clientes sin preparar el conjunto y las condiciones
de uso correspondientes. Detalle de revisión con Claude, checks y resultados:
[F4.1-TYPESAFE-ARRANQUE-2026-09-21.md](F4.1-TYPESAFE-ARRANQUE-2026-09-21.md).

**Apoyo técnico:** Jev se probó para ordenar extractos de código como ayuda a Codex y
Claude, no como autoridad de aprobación. Las 22 pruebas del toolkit existente pasan;
en el ensayo de relevancia ninguno de los tres extractos superó el corte existente de
2 puntos. Se preserva esa incertidumbre y se verifican las conclusiones con código y
tests. No sustituye `scripts/claude-review` ni los gates del proyecto.

En la revisión documental del 21/09, Claude devolvió `CHANGES_REQUESTED` sobre el resumen
aportado, no sobre código. Se incorporaron las aclaraciones de la base fija de las 11:30 y
de los valores iniciales configurables. La propuesta de inventar valores provisionales para
sábado o analistas sin cartera no se aceptó entonces: estaban pendientes de Miguel.
Posteriormente el propio Miguel cerró esas tres reglas (apartado de decisiones de F4);
no se usaron valores inventados. Los horarios de Lima, feriados y la independencia de F6
respecto de TypeSafe ya están definidos en el plan. Las comprobaciones documentales del
PRIMARY pasan; esto no constituye una aprobación del piloto ni una verificación de producto.

---

### Fase 5 — Gerencia «Toda la operación» · LEVEL 3 · 1 migración + 1 PR

**Objetivo:** entender los problemas recurrentes de toda la operación y orientar la
intervención y la capacitación mediante el pulso global, las comparaciones por equipo y el
reporte de hábitos. Se considera lograda cuando gerencia puede detectar qué equipo requiere
atención y bajar hasta su registro. Reutiliza la tabla de F4 y su configuración ya publicada.
Una posible clasificación de objeciones con TypeSafe se evalúa después de F4.1 y no bloquea
las métricas ni el reporte de hábitos de F5.

**Qué obtiene Miguel:** «¿Hoy es un día normal?» sin un clic; el supervisor con el problema; su equipo (misma tabla); el registro crudo exportable.

**Servidor (`…_crm_gestion_diaria_pulso.sql`):** `crm.gestion_diaria_pulso_fn(p_dia date default null)` (gerencia / `es_lector_global`): Nivel 1 = llamadas, útiles, contestadas, tasa, sin actividad (activos vs roster activo), leads únicos + ratio, citas agendadas, cada uno contra AYER completo y contra el promedio de los últimos 7 días con actividad (una pasada del núcleo sobre 8 días); Nivel 2 = fila por supervisor activo (organigrama de hoy): tasa, llamadas, contestadas, sin actividad, dispersión mejor→peor (analistas con ≥ 5 llamadas útiles), vencidas, **primera gestión fuera de plazo**; fila de cuadre «Fuera de equipos comerciales»; `vencidas_global` canónico. Sin conversiones ni «rango normal» (dicho en pantalla). Niveles 3 y 4 reutilizan las puertas de las fases 1 y 4.

**Front:** `screens/gestion-diaria/gerencia.tsx` con selector de DÍA único (por defecto hoy Lima; `validarPeriodoGerencia`), pulso con `StatStrip`/`KpiCard` (número que responde la pregunta en 32/800), tabla por equipo peor primero → «Ver equipo» → `TablaEquipoDiaria` → «Ver registro» → `RegistroActividad`. Drill-down enlazable: ampliar `RutaHash` (`router.ts:93-98`), `hashDe`/`leerHash` (`:132-156`) con `#/gestion-diaria/equipo/<uuid>` y `#/gestion-diaria/analista/<uuid>` (precedentes `:133-134`); el día vive en estado de sesión (v1). Banner «N tareas vencidas siguen pendientes» → desglose por equipo. Nota de corte del resultado tipificado. Tests + e2e Gerencia + protocolo `design-qa.md`.

**Despliegue:** SQL primero, front después. Codex: 1.


#### F5 · El reporte de HÁBITOS para capacitar (decisión de Miguel, 20/09/2026)

**Qué obtiene Miguel:** no el pulso del día, sino **dónde está el problema de fondo** — para saber
a quién capacitar y en qué.

Por analista, sobre los últimos N días:

- **A qué hora hace su primera llamada.** Quien arranca a las 11 no tiene el mismo día que quien
  arranca a las 9.
- **Su hueco más largo sin llamar**, y a qué hora ocurre.
- **Cómo se reparte su tasa de contacto** frente a la de su equipo y la de la operación.
- **Cómo le fue en los dos cortes del día** (F4), cuántas veces los cumplió.

**Este reporte cierra un círculo:** es el que produce el dato que hoy falta para poner el número de
la alerta «tasa muy baja», que nace vacía en F4. Gerencia mira el reparto real, decide el umbral y
lo publica en la misma pantalla de configuración.

El núcleo vuelve a ser `private.gestion_diaria_llamadas`, que ya acepta varios analistas y rangos
de fechas: no hace falta un contador nuevo.

---

### Fase 6 — Absorber Seguimiento y cerrar (CERRAR → OBSERVAR → DERRIBAR) · LEVEL 2 · 1 PR

**Objetivo:** reunir la operación diaria en un solo módulo, sin perder las capacidades de
Seguimiento ni romper los enlaces existentes. Se considera lograda cuando los accesos antiguos
llevan a Gestión Diaria, la vista duplicada se ha retirado y las pruebas confirman que las
funciones y los permisos conservados siguen funcionando. La retirada comienza solo después
del período de estabilidad de F3–F5; TypeSafe no es una condición para este cierre.

Cuando las fases 3–5 lleven al menos una semana en producción sin incidencias: `#/seguimiento` a `ALIAS_HEREDADO` → `gestion-diaria` (`router.ts:111-119`); retirar `'seguimiento'` de `VISTAS`, `CAPACIDAD_POR_VISTA` (línea 24) y su early-return (línea 100), sidebar, `App.tsx`, `TITULOS`; repuntar `lib/sla-avisos-presentacion.ts:22`, `screens/hoy/supervisor.tsx:836`, `ayuda-vendedor-panel.tsx:65-67`, `e2e/sla-operacion.spec.ts`; `ColaSlaPanel` sigue vivo. Actualizar los ~10 tests que mencionan `seguimiento`. `npm run check:all`. Vault, `Inicio.md`, actas en `MIGRACIONES.md`, PLAN.md del repo con «Lo construido vs lo planteado».

### Fuera de v1 (escrito para no perderlo)

Cuota diaria (§7.2) · reconocer/posponer para `tasa_baja` (nace VACÍA), `parado_2h` y `primer_intento_vencido` · columna de estado del teléfono en `crm.leads` · «Crear tarea» sobre lead ajeno desde el registro · «Avisar al supervisor» · conversiones de hoy · «rango normal» de la tasa · alternancia de canal de la cadencia (llamada fallida → WhatsApp) más allá de lo que ya propone `sugerirSiguiente` · entrada por rango del registro desde un módulo Métricas · refactor de las 4 copias artesanales de tabs · fecha en el hash · medición del abandono del panel (paneles abiertos vs resultados).

Los cortes, su reconocimiento y su aplazamiento de una hora **sí pertenecen a F4**. La revisión
con TypeSafe pertenece a F4.1, condicionada al piloto; sus ampliaciones posteriores no son
requisitos para cerrar F4.

### Riesgos que quedan aunque el plan se cumpla

- **Dos colas del día conviven** (Hoy = 3 cosas de ahora; Gestión Diaria = cola completa), por decisión de Miguel. Se declara en ambas pantallas y un test las mantiene coherentes en el primer ítem.
- **Fase 2 cambia el diálogo de llamada de TODO el CRM.** Es lo que pide §7.1 y es el cambio de mayor exposición: e2e completo y ventana de publicación con Miguel disponible.
- **Deshacer** es nuevo código sobre un descarte que hoy es irreversible para el analista; se apoya en `reabrir_lead_fn` y en una ventana de 24 h propia.
- **Histórico sin resultado**: 4 889 llamadas con `metadata = {}`; los tableros dicen «sin resultado» para lo anterior a la Fase 2.
- **Gates rojos ajenos** (4 de 8): el módulo solo puede demostrar «conjunto rojo idéntico».
- **`gen:types` roto**: 6 RPC nuevas a mano en `database.types.ts`.
- **Codex no conectó en esta sesión** (`CONNECTION_CLOSED`): reconectar antes de la Fase 1.
- **Banco compartido** entre sesiones y sesión paralela de «historial por lead»: pedir turno por `SendMessage` y coordinar `metadata` en `actividades_de_lead_fn`.

### Verification (punta a punta)

**SQL (por migración):** `npm run check:scripts` · `npm run test:rls:preflight` · `auditor-rls` · ensayo en banco (`banco.mjs`/`ensayar.mjs`: preflight md5 en verde, postflight fila por fila, reversa y registrador generados, `verificacion.json`) · `test:rls` línea base antes/después (sin regresiones; hay fallos de base conocidos) · `assert_sla_*` + `assert_gestion_diaria` en verde y censo rojo idéntico · advisors si hay rama · acta en `MIGRACIONES.md` · en prod: `db query --linked --file` por Miguel con `!`, registrador, objetos contados, prueba read-only con identidad real (`DO` + `set_config(jwt)` + `raise`).

**Front (por PR):** `npm run test:coverage` antes · `npm run check` · `npm run check:all` en las fases que cambien flujos de usuario, navegación o roles, incluida F4 · `gate:realidad` · `revisor-a11y` · `design-qa.md` en fases 3–5 · preflight `node _DEV_NO_SUBIR/deploy-hostinger-mcp.mjs preflight crm.miavance.com <zip>` · PR con merge commit ANTES de construir · `/release-crm` por Miguel · bundle vivo contrastado · `git push avancecorp main` el mismo día.

**Prueba de negocio (Miguel, tras cada fase):** F1: como supervisor, leer el texto de una llamada de su equipo y comprobar que NO ve otro equipo; como gerencia, exportar CSV. F2: elegir un resultado y ver contraídas las demás opciones; «No le interesa» + motivo + próxima acción conserva el lead y crea la tarea; solo al marcar descarte aparece en el Centro de rescate; «Deshacer» dentro de 24 h revierte los efectos admitidos, nunca el veto de contacto. F3: como analista, comprobar que el primer ítem coincide con «Ahora» de Hoy. F4: tabla y detalle del equipo, cortes, pop-up, reconocimiento/aplazamiento entre dispositivos y publicación gerencial de reglas futuras; conservar el reconocimiento de vencidas y por repartir. F4.1: piloto contra etiquetas humanas y sugerencias confirmables/descartables sin alterar registros ni bloquear F4. F5: pulso y cuadre remedidos, drill-down hasta el registro.

### Acciones manuales de Miguel

**Hechas** (20/09/2026): confirmar submotivos y umbrales · reconectar el MCP de Codex · autorizar
el ensayo en banco · instalar y publicar F1, F2 y F3.

**Hechas después (21/09):** publicar F4 etapas 1–2; confirmar ambos supervisores por
su equipo; fijar sábado en 3 llamadas; excluir cartera vacía de avisos de corte;
aprobar un único aplazamiento por aviso/supervisor/día, sin reaviso al cierre o después.
Autorizar también el ensayo y reversión local del candidato de F4 etapa 3;
no es permiso de producción.

**Pendientes:**

1. **Prueba de negocio de F3:** como analista, que el primer ítem de «Mi día» coincida con «Ahora» de Hoy.
2. **Prueba de negocio de F4 etapas 1–2:** recorrido productivo del supervisor; no sustituido por smoke HTTP ni conformidad visual local.
3. **Autorizar la SQL candidata y publicación de F4 etapas 3–6 cuando estén verificadas**, y después F5. Las reglas de negocio ya están cerradas. El piloto F4.1 no bloquea estas entregas.
4. **F4.1:** realizar el banco ficticio con ambos supervisores, acordar criterios/presupuesto/retención y rotar la clave antes de transferir notas reales. Después autorizar/preparar la muestra de ambos equipos y sus etiquetas independientes. La guía y el banco ya están preparados, no la evaluación humana. Decidir la integración visible solo tras el piloto y verificar aislamiento por equipo también en cola/caché.
5. **El repositorio fusiona por SQUASH por defecto**, y eso ya costó un rescate el 20/09 (la PR #47 entró con una foto anterior a su último commit). Cambiar el ajuste en GitHub.

### Lo que este plan YA NO dice, y por qué

Para que nadie construya contra algo superado:

- **El mockup `mockups/4-analista-mi-dia.html` está SUPERADO.** Describe la pantalla apilada que se
  rehízo el 20/09. Se conserva como histórico del encargo; **no es la referencia de «Mi día»**.
- **La `StatStrip` y el «salto a la fila siguiente»** de la Fase 3: descartados al construir.
- **La alerta «sin llamadas a las 11:00»** de la Fase 4: la sustituyen los dos cortes del día.
- **Los umbrales 45 / 25 / 5 como constantes en el código**: desde F4 son perillas de gerencia,
  versionadas y con fecha de vigencia.
- **La barra persistente como aviso principal y la prohibición de posponer los cortes:**
  sustituidas por el pop-up con reconocimiento en servidor y aplazamiento de una hora.
- **La configuración gerencial diferida a F5:** pertenece a F4. F5 entrega el tablero global
  y el reporte de hábitos.
- **TypeSafe como requisito de los cálculos de F4:** queda como F4.1, con piloto previo y
  activación condicionada; no modifica métricas, cortes ni permisos.
- **El «telefonos por lead» en la puerta de F3**: no se construyó. El teléfono se hidrata desde el
  store, y eso es lo que produjo los cinco bugs de la caché parcial.

---

# 3 · Diseño técnico — los cortes del día (F4)

**Estado al 21/09:** etapa 3 implementada en el candidato `20260921214018` y
verificada sólo en la copia local autorizada. Claude hizo revisión asesora;
evidencia y límites en [F4-CORTES-JORNADA.md](F4-CORTES-JORNADA.md). Los apartados
de editor gerencial, reconocimiento, aplazamiento y activación siguen siendo
diseño de etapas 4–6, no capacidades ya publicadas.

---

### 0 · Decisiones vigentes y pendientes reales

Las preguntas del primer diseño se resolvieron durante el 20/09 y se recogen en la sección
F4. La base es el acumulado a las 11:30; el mínimo entre semana es tres; cuentan todas las
llamadas; el primer aviso se retira si se resuelve antes del segundo; el segundo conserva
el resultado del corte. El sábado tiene un corte a las 11:30 dentro de la jornada 09:00–13:00;
el domingo no tiene avisos de jornada. Se usa pop-up con reconocimiento en servidor y
aplazamiento de una hora; las nuevas políticas rigen desde una jornada futura. No volver a
preguntar esas decisiones ni usar las propuestas anteriores que las contradigan.

El 21/09 Miguel cerró las tres definiciones restantes: sábado mínimo tres; sin
leads abiertos asignados, fuera de avisos de corte pero visibles en tabla; un solo
aplazamiento por aviso/supervisor/día sin reaviso al cierre o después. El pendiente
sigue visible. Cálculo y contrato de etapa 3 ensayados; faltan la publicación
del candidato y la implementación/validación de etapas 4–6 para activar.
El aviso requiere CRM abierto; no se incluye push con la aplicación cerrada.

---

### 1 · Cálculo acordado

«150 % más» significa multiplicar por 2,5 antes del piso y el techo. Se guarda el porcentaje
y la pantalla explica tanto la cuenta como el objetivo final acotado. La base es siempre el
acumulado al primer corte, inicialmente 11:30, no a las 11:00. El mínimo inicial de ese
corte entre semana es tres; el del sábado también arranca en tres, como perilla independiente.

---

### 2 · Modelo de datos

**Tabla nueva `crm.politica_gestion_diaria`, molde VERSIONADO CON VIGENCIA** — el de `crm.sla_politicas` (`supabase/migrations/20260807203757_crm_metas_sla_versionados.sql:386-421`), **no** el singleton de `crm.politica_abandono`.

Absorbe **también** los tres umbrales que hoy están a fuego, para que la fuente siga siendo una sola:

```
id uuid pk
version integer not null unique
version_anterior_id uuid references crm.politica_gestion_diaria(id)
vigente_desde timestamptz not null            -- SIN unique (ver §3, corrección Codex F11)
-- lo que hoy vive en el cuerpo de la función (…041500…sql:186-197)
bien_min_pct / atencion_min_pct numeric not null
minimo_llamadas_utiles integer not null
-- lo nuevo
cortes_activos boolean not null default false
corte_1_hora time                             -- 11:30
corte_1_minimo integer
corte_2_hora time                             -- 16:00
corte_2_incremento_pct numeric                -- 150
corte_2_piso integer                          -- piso absoluto
corte_2_techo integer                         -- techo absoluto
sabado_minimo integer                        -- arranque 3, independiente
tasa_baja_diferencia_pp numeric               -- NULL; todavía sin consumidor
creado_por uuid / creado_en timestamptz / motivo text
-- horas/mínimos obligatorios incluso OFF; rangos en el CHECK de la candidata
```

Este es el modelo del candidato de etapa 3, todavía no productivo. El calendario de evaluación
respeta L–V 09:00–18:00, sábado 09:00–13:00 con solo el primer corte y domingo sin avisos de
jornada. Esos límites también gobiernan «parado». La política no activa el sábado sin su
mínimo; una tasa baja nula significa desactivada, no cero ni quince puntos por defecto.
El aviso principal es el pop-up de F4; no se construye la antigua barra persistente.

- **Inmutable** por `private.trg_config_versionada_inmutable()` (el mismo trigger de SLA, `:299-313`), que lanza `55000` «publica una nueva revisión».
- **Versión 1 sembrada con `vigente_desde = '-infinity'` lleva SOLO 45/25/5 y `cortes_activos = false`.** Corrección de Codex (F1): sembrar los cortes desde `-infinity` haría parecer que la obligación existía antes de inventarla. Los cortes nacen en la **versión 2**, con la jornada en que Miguel los enciende.
- **RLS ON.** Requiere `puede_acceder_crm()` y rol CRM efectivo o lector global. Sin policies de INSERT/UPDATE/DELETE; todavía sin función de publicación (etapa 5).
- **Grants:** revocación total a PUBLIC/anon/authenticated/service_role y SELECT por columna sólo de parámetros para authenticated. Motivo, autor y fecha administrativa no se leen directamente por API, ni siquiera como gerencia; el editor futuro tendrá una puerta autorizada específica.
- **Vigencia ordenada:** versión siguiente, autor obligatorio y jornada futura no anterior a la última programada. Se admite la misma jornada para corregir una revisión pendiente: gana la versión mayor.
- Trigger de auditoría `private.log_audit_crm()`.

**Por qué versionada y no singleton (y dónde Codex me corrigió el argumento).** El motivo válido es uno solo: **la puerta F3 ya admite consultar días pasados** (`p_dia` hasta un año atrás, `…041500…sql:534-535`) y con una fila que se pisa, el martes pasado se re-juzgaría con la perilla de hoy. El argumento que yo daba de que `dias_auto_bolsa` lleva un mes sin consumidor **no prueba nada** sobre singleton vs versionado (Codex, aceptado): prueba otra cosa, que una perilla sin pantalla se muere.

**Dónde vive la tabla.** Se mantiene en `crm` con lectura RLS de parámetros porque
los umbrales ya viajan al día del analista. La revisión de Claude añadió la
restricción por columna para no exponer motivos ni atribución administrativa.
El resolutor proyecta sólo parámetros; sigue INVOKER, sin SELECT `*`.

---

### 3 · La puerta gerencial — pendiente de etapa 5

**Lectura del editor** — `crm.configuracion_gestion_diaria_fn()`, DEFINER con `search_path = ''`, calco de `crm.configuracion_sla_fn` (`20260807203757…:571-607`). Devuelve `expected_version`, `puede_editar` (= `rol_crm = 'gerencia'`, **calculado en servidor**), la política vigente con autor, la frase de ejemplo ya calculada, y —corrección de Codex F11— **`revisiones_pendientes[]`**: las versiones con `vigente_desde` futuro. Sin eso, gerencia edita a ciegas sobre valores antiguos y pisa lo que ya estaba programado.

**Escritura** — `crm.publicar_politica_gestion_diaria(p_expected_version integer, p_vigente_desde timestamptz, p_config jsonb)`, DEFINER, calcando `crm.publicar_politica_sla` (`:470-560`):

- `rol_crm(auth.uid()) = 'gerencia'` o **42501**.
- Forma exacta del jsonb: `?&` con todas las claves **y** `p_config - array[...] <> '{}'` para rechazar claves de más.
- Rangos base del candidato: `0 <= atencion_min_pct < bien_min_pct <= 100`; mínimos, piso y techo 1–500, techo no menor al piso; incremento 0–1000. Primer corte después de 09:00 y antes de 13:00; segundo después del primero y antes de 18:00. La antigua propuesta 06:00–22:00 no respeta el calendario aprobado y no se aplica.
- **Vigencia**: `p_vigente_desde` debe ser el **inicio de una jornada Lima futura** (no una hora cualquiera). Ver §4.
- `pg_advisory_xact_lock(hashtext('crm.politica_gestion_diaria'), 1)` + `p_expected_version <> v_actual` → **40001**.
- **Sin `unique` en `vigente_desde`, y el resolutor ordena `(vigente_desde desc, version desc)`.** Es la única desviación deliberada del molde SLA y la razón es la que levantó Codex (F11): con `unique`, una revisión ya programada para mañana **no se puede corregir** sin romper la inmutabilidad. Sin `unique`, la corrección es simplemente una versión mayor para la misma jornada, y gana. `private.sla_politica_vigente` ya desempata así (`:562-569`), o sea que el patrón de lectura no se inventa.

**Resolución** — `private.politica_gestion_diaria_vigente(p_instante timestamptz)`.

**Encaje con `private.gestion_diaria_umbrales()` (hoy a fuego, `…041500…sql:186-202`) — corregido por Codex (F2).** Mi plan original («le pongo un parámetro con default») **no funciona**: en Postgres una función de cero argumentos y otra de un argumento con default son firmas distintas, y `create or replace` no puede añadir un parámetro. Diseño corregido:

- Se **añade** `private.gestion_diaria_umbrales(p_instante timestamptz)` — sin default — que lee la vigente.
- La de cero argumentos **se conserva** como envoltorio que resuelve a medianoche Lima del día actual. Su cuerpo y el de F3/F4 quedaron re-sellados en el candidato; no se editan migraciones anteriores ni se reemiten grants heredados.
- **`private.gestion_diaria_analista_core` deja de llamarla sin argumento** (`:331`) y pasa `p_ini` explícito. Su cuerpo cambia → **re-medir y re-sellar su md5 (`:800`)**.
- **Mutantes de etapa 3:** 15 alteraciones deliberadas de RLS, grants por tabla/columna, cuerpos, triggers, redondeo y umbrales legacy detectadas por el gate. El 42501 de publicación, `expected_version` y claves extra tendrán pruebas propias cuando exista la puerta de etapa 5.
- La migración `20260920041500` **está en producción y registrada** (acta en `supabase/migrations/MIGRACIONES.md`, sección «20260920041500 — Gestión Diaria (F3)», 20/09 ~06:19 UTC): **no se edita**. Todo esto va en migración nueva.

**Autorización, explícita y no «por calco»** (Codex F6, aceptado como vacío de diseño): por cada RPC hay que escribir quién tiene `execute`, qué comprueba dentro cada DEFINER, cómo se acota `p_supervisor_id` a la jerarquía del actor (`private.vendedor_ids_visibles`), y qué ven gerencia, directorio y lector global. Se prueba identidad por identidad en el postflight con `set_config('request.jwt.claims')`, patrón `20260916205617:240-379`.

---

### 4 · El cálculo de los cortes

**Dónde vive:** `private.gestion_diaria_cortes(p_dia date, p_analistas uuid[], p_ahora timestamptz)`
resuelve la política al inicio del día. El núcleo de equipo añade `cortes` usando
su roster autorizado y su único reloj de servidor. La firma RPC no cambia ni
admite reloj del navegador. Reconocer/posponer tampoco podrá admitirlo en etapa 4.

**Cómo se mide.** Componiendo `private.gestion_diaria_llamadas` sin modificarla:
`[día,corte_1)`, `[día,corte_2)` y `[día,min(ahora,límite_recuperación))`.
El límite de recuperación es el segundo corte entre semana y 13:00 el sábado.
No se usa el desglose por hora entera: no distingue las 11:30. Una llamada
exactamente al corte no pertenece a su ventana anterior; esos límites se prueban.

**Zona horaria.** Todo con `at time zone 'America/Lima'`, como `…041500…sql:578-580`; nunca `-05:00` a mano. Perú no observa horario de verano desde 1994, pero da igual: al usar el nombre de zona, el cálculo es correcto aunque cambiara. Codex no pudo confirmarlo con la evidencia pegada y lo dejó como pregunta abierta; queda anotado.

**El instante que resuelve la política — lo que Codex bloqueó (F1).** La política se resuelve **al inicio de la jornada Lima evaluada** (`v_ini`), no con `now()` ni con `least(v_fin, now())`. Tres razones, las tres suyas:
- con `now()` por defecto, un día pasado se juzgaría con la perilla de hoy;
- `least(v_fin, now())` devuelve la **medianoche del día siguiente**, así que una revisión que entre en vigor justo entonces contaminaría el día anterior;
- publicar al mediodía cambiaría las reglas de un corte que **ya ocurrió** esa mañana.

Resolviendo en `v_ini` y exigiendo que `vigente_desde` sea el inicio de una jornada futura, **las reglas del día se fijan al amanecer y no se mueven**. Es una decisión ya cerrada en F4.

**Las reglas.**
- **Corte 1 (11:30):** falla si `llamadas_acumuladas < corte_1_minimo`.
- **Corte 2 (16:00):** objetivo = `max(ceil(base × (100 + incremento)/100), corte_2_piso)`, acotado por `corte_2_techo`. **`ceil`, no `round`**: con base 8 e incremento 30 %, se exigen **11**.
- **Base cero:** si el acumulado del corte 1 es 0, la razón siempre pasa (0 × 2,5 = 0) y con base 1 pide 3 — por eso el **piso absoluto** manda en ese caso.
- **Sábado:** jornada fija 09:00–13:00, sólo primer corte a las 11:30 y `sabado_minimo` independiente, inicialmente **3**. No se añade una perilla para suprimirlo; no fue solicitada. Domingo sin avisos de jornada.
- **Feriados: no existe calendario laboral en el repo** (`grep feriado|festivo|dias_no_laborables|calendario_laboral` sobre `supabase/migrations/` y `app/src/` → **0 resultados**) y **no propongo crearlo**. Mi heurística de «día atípico» (silenciar si menos de un tercio del roster registró llamadas) **la retiro**: Codex (F3) demostró que apaga la alarma exactamente el día en que nadie llamó, que es el día que más importa. En su lugar: la alerta **se emite siempre**, y cuando la participación del equipo entero está por los suelos lleva una marca de contexto («actividad excepcionalmente baja en todo el equipo — revisa si hoy es feriado o hubo una incidencia») y se presenta como **una** alerta de equipo, no como N individuales. Silenciar un día requiere una decisión explícita, no una inferencia.
- **Analista que entró a media mañana:** no se prorratea. La alerta incluye `primera_llamada_en` (ya lo devuelve el núcleo, `:483-484`) para que el supervisor lea el contexto. **Quien tiene cero llamadas SÍ entra en el grupo del corte** — corrección de Codex (F4): mi deduplicación original lo dejaba solo en `sin_llamadas_hoy` y fuera del aviso fuerte, o sea que el que peor está recibía el aviso más débil. `sin_llamadas_hoy` se suprime **en la presentación** para quien ya está dentro del grupo del corte, no en el cálculo.
- **A quién se evalúa:** roster activo (`crm.equipo.activo = true` y `rol_crm` = vendedor, definición fijada en `GESTION-DIARIA.md`). Miguel aprobó excluir del aviso de corte a quien no tenga ningún lead abierto asignado, sin ocultarlo en tabla. Cero llamadas no excluye por sí solo a un analista con cartera abierta. No extrapolar esta exclusión a las demás alertas.

**Historia.** Todo se deriva del log de actividades; **no hay tabla de «evaluaciones de corte»**. Limitación que hay que decir en pantalla (Codex F10, aceptado): un día pasado se recalcula con **el equipo y la jerarquía de hoy**, no con los de entonces. Reproducir «lo que el supervisor vio aquel día» es un contrato distinto y más caro; si Miguel lo quiere para evaluaciones de desempeño, entonces —y solo entonces— hace falta un registro derivado, que **no** es automáticamente «otro origen de verdad». Pendiente de verificar: que ningún escritor fije `creado_en` a mano en `crm.actividades` (inserciones tardías romperían el recálculo).

---

### 5 · El aviso «que le tenga que prestar atención»

**Presentación acordada: pop-up sobre el `Dialog` existente**, más contador en la campana y
lista de alertas. No se construye una barra persistente ni un modal que no pueda cerrarse.
El diálogo muestra analistas, cifras y objetivo, y permite entrar en su día. Si hay otra
interacción en curso, espera; antes de aparecer vuelve a comprobar si el problema sigue vigente.

El servidor conserva el reconocimiento y el aplazamiento de una hora. La identidad del corte
debe distinguir **supervisor + jornada Lima + corte**. Así un reconocimiento de ayer nunca
oculta el de hoy y un refresco o cambio de dispositivo no produce otra aparición del mismo
aviso. El reaviso tras posponer es explícito: **una sola vez por aviso/supervisor/día**,
sin reaviso al cierre o después (18:00 L–V, 13:00 sábado), ni traslado al día siguiente.
El pendiente sigue visible. Validar el límite y la concurrencia en servidor, sin
confundir reconocimiento o supresión del pop-up con resolución del problema.

**Extensión del mecanismo existente.** `crm.alertas_reconocimientos` restringe los tipos por
CHECK y valida el actor a partir del identificador (`20260823204930…:44-46,105-113`). Ampliar
los tipos exige una migración nueva compatible con los asientos anteriores. Para un
identificador de corte con fecha, por ejemplo
`grupo:corte_manana:<supervisor_uuid>:<YYYY-MM-DD>`, la validación ya no puede asumir que el
último segmento es el supervisor. Debe validar tipo, UUID, jornada y propiedad de forma
explícita y rechazar formatos desconocidos. Se prueba que un supervisor no pueda reconocer ni
posponer un corte de otro equipo. Las reglas vigentes de alertas anteriores se conservan;
no se reutiliza el aplazamiento genérico a mañana ni se amplía su límite para acomodar cortes.

La lista de `miembros[]` permite agrupar los analistas y actualizar el detalle sin multiplicar
pop-ups. Pop-up, campana y pantalla de alertas comparten el mismo estado de reconocimiento.
El primer corte se retira de la presentación cuando se resuelve antes del segundo; el de
las 16:00 conserva el resultado de ese corte y se puede reconocer aunque después haya más
llamadas. Cerrar el diálogo por sí solo no inventa un reconocimiento ni modifica el resultado.

`SeveridadAlerta` **no gana un tercer valor**: el pop-up es una decisión de presentación.
`TipoAlerta` incorpora `corte_manana` y `corte_tarde`. La identidad y el estado de
presentación deben ensayarse también entre dos dispositivos y ante reintentos.

**Alcance:** los avisos se reciben con el CRM abierto y con el retraso del refresco
(`refetchInterval: 60_000`, `crm-queries.ts:1216-1229`). Push, correo, WhatsApp y aviso con
la aplicación cerrada quedan fuera de F4; requerirían una ejecución programada y otra entrega.

---

### 6 · La pantalla de gerencia

**Sección propia `config-gestion-diaria`.** No dentro de `config-sla`: son dos contratos versionados distintos y «Tiempos de atención» significa otra cosa.

Los siete archivos con `Record<Vista,…>` exhaustivo (si falta uno, el typecheck se cae): `lib/router.ts:11-41` (VISTAS) y `:53-60` (VISTAS_CONFIGURACION), `lib/vistas.ts:21-50`, `App.tsx:65-71` y `:74-102`, `components/app/topbar.tsx:48,73-74`, `components/app/ayuda-vendedor-panel.tsx:20,45-46`, `screens/config.tsx:39-46`. El sidebar no se toca (`sidebar.tsx:66-70` excluye `esVistaConfiguracion`). Más: `lib/politica-gestion-diaria.ts` (Valibot `strictObject`, calco de `lib/control-citas.ts:1-21`), `data/crm-config-api.ts` con `parsear()` y **eco campo a campo** tras el RPC calcando `:455-491`, `data/crm-config-queries.ts` con `mutacionSoloReal` (`:42-55`) e invalidación **también** de la clave de Gestión Diaria, y clave nueva en `crm-queries.ts:90-97`.

**No entra en el riel de estado** de `config.tsx:155-206` — eso exigiría un doble demo en `lib/demo-config.ts`, y por eso mismo `config-rentabilidad` y `config-citas` tampoco están.

**Qué valida el cliente** (espejo de §3; la que manda es la del servidor): horas dentro de 06:00–22:00 Lima, `corte_2 ≥ corte_1 + 60 min`, enteros y rangos, `atencion_min_pct ≤ bien_min_pct`, y **la frase calculada visible mientras se edita**: «si a las 11:30 lleva 8 llamadas, a las 16:00 deberá llevar al menos 20».

**Cómo se publica:** diálogo de confirmación «Publicar política de Gestión Diaria v{expected_version + 1} — rige desde la jornada del DD/MM; las versiones publicadas no se editan», con las **revisiones pendientes** a la vista. Mapeo de errores ya existente (`crm-config-api.ts:102-124`): `40001 → CONFLICTO_CONFIG`, `42501 → SIN_PERMISO`, `22023/23514 → REGLA_SERVIDOR`. Gate de acceso: `lib/vistas.ts:89-92` (gerencia y directorio; directorio en solo lectura por `puede_editar` del servidor). El formulario incluye el mínimo del sábado y permite mantener vacía la alerta de tasa baja. Esta pantalla se entrega en F4.

---

### 7 · Riesgos

1. **El ruido.** Mitigaciones: **una** alerta por corte por supervisor con `miembros[]` (no N alertas — regla «una alerta por DECISIÓN», `lib/alertas.ts:405-411`); el corte 1 se retira si se resuelve; techo «1 rojo por decisión, máx. 2 ámbar» del playbook; pop-up sin repeticiones por refresco y con reconocimiento en servidor. La exclusión de analistas sin leads abiertos de los avisos de corte ya fue aprobada el 21/09. Los cortes se activan con política futura tras verificar el flujo, sin convertir la antigua barra persistente en un requisito. Sin ejecución programada y sin CRM abierto no hay muestra completa de avisos; no prometer observación exhaustiva.
2. **La injusticia del objetivo relativo** (la levanta Codex y es de negocio, no técnica): con ×2,5, quien llevaba 20 necesita 50 y quien llevaba 8 necesita 20. El primero puede acabar con 30 llamadas y **fallar**, mientras el segundo cumple con 20. Por eso propongo `corte_2_techo_llamadas`: quien ya superó un volumen absoluto no falla la regla relativa. El piso solo no lo arregla.
3. **Re-sellado de md5 y mutantes** (`…041500…sql:800-801`, `:907`, `:912`): si se re-sella sin re-medir en producción, el gate deja de proteger y nadie se entera.
4. **Deriva del duplicado del front**: `app/src/lib/gestion-diaria-analista.ts:300` repite 45/25/5 a mano para el modo demo y `analista.test.tsx:46` los fija en el fixture. Al hacer configurables los umbrales, ese duplicado se convierte en mentira. Hay que anotarlo como demo explícita.
5. **`database.types.ts` a mano**: `gen:types` está roto (riesgo ya declarado en el plan); dos RPC nuevas se escriben a mano.
6. **Reproducibilidad histórica incompleta**: se versiona la política, no el roster ni la jerarquía (§4).
7. **Alcance del aviso**: hasta 60 s de retraso y cero aviso con el CRM cerrado.
8. **Doble alerta** con `sin_llamadas_hoy` y `parado_2h`: resuelto por presentación, pero es donde más fácil se cuela el ruido.
9. **Banco compartido entre sesiones** y sesión paralela de «historial por lead»: pedir turno antes del ciclo de pruebas.

---

### 8 · Qué NO haría

- **Modal bloqueante.** No existe `alertdialog` en el repo y `Dialog` no tiene modo no-cerrable (`ui/dialog.tsx:19-27`). Construirlo es pelearse con la arquitectura de la app para conseguir que el supervisor odie la funcionalidad en dos días.
- **Tabla de feriados.** No existe calendario laboral (0 resultados) y crearlo es asumir un mantenimiento anual para un beneficio que se resuelve con contexto en la alerta.
- **Heurística de «día atípico» que silencia.** Retirada por la refutación de Codex (F3).
- **Push, correo o WhatsApp en v1.** El molde de push existe pero dispara por INSERT, no por reloj.
- **Cuota diaria por analista.** Está **fuera de v1 por decisión escrita** (`GESTION-DIARIA.md`, «Fuera de v1»; `PLAN.md:256-258`). Los cortes no son la cuota: miden ritmo, no volumen objetivo.
- **Perilla por analista** (molde `crm.equipo.capacidad_leads_objetivo`). Empieza global; si hace falta individualizar, es otra fase.
- **Meter los cortes en `config-sla`** ni escribirlos por PostgREST al estilo `politica_abandono`.
- **Tabla de snapshots de corte en v1** — pero **sin descartarla por principio**: si Miguel quiere «lo que el supervisor vio aquel día» como evidencia, un registro derivado es legítimo (corrección de Codex, F10).
- **Tocar la migración `20260920041500`**, que está en producción y registrada.

---

### REVIEW · Codex (SECONDARY_REVIEWER, `sandbox: read-only`, `approval-policy: never`)

**Acta histórica del primer diseño.** Se conserva como evidencia de la revisión, no como
requisitos adicionales. Las decisiones posteriores recogidas en F4 y F4.1 prevalecen; en
particular, la antigua prohibición de posponer cortes quedó superada por el aplazamiento de
una hora, y el pop-up sustituyó a la barra persistente como presentación principal.

**Veredicto de Codex: REQUEST CHANGES.** Sin P0. Doce hallazgos P1–P2.

**Aceptados e incorporados (11):** F1 resolución temporal por jornada y semilla `-infinity` sin cortes · F2 el parámetro con default no reemplaza la firma (envoltorio + función parametrizada, y el llamador pasa el instante) · F3 retirar la supresión por «día atípico» · F4 el de cero llamadas entra en el grupo del corte · F5 la identidad del reconocimiento lleva jornada y corte, y `posponer` se prohíbe · F6 escribir la autorización explícita de cada RPC · F7 devolver a Miguel las decisiones de negocio (hora base, sábado, mínimo, piso, sin-cartera) · F9 `ceil` en vez de `round` · F10 declarar la limitación de reproducibilidad y no descartar el registro derivado · F11 revisiones pendientes visibles y `vigente_desde` **sin unique** · F12 el modo observación es parcial y es una perilla, no un calendario. Más su observación de negocio sobre la injusticia del objetivo relativo → `corte_2_techo_llamadas`.

**Aceptado a medias (1):** F8. Acepto bajar el cálculo al núcleo. **Rechazo** mover la tabla a `private`, con evidencia: los valores ya viajan hoy a cualquier analista autenticado en `…041500…sql:460`, así que esconderla no compra confidencialidad y obligaría a convertir `gestion_diaria_umbrales` de invoker a definer.

**Confirmado por Codex tal cual (no tocar):** D1 (×2,5 con ejemplo numérico), la elección de configuración versionada e inmutable, el control de gerencia en servidor con bloqueo y `expected_version`, la reutilización de `gestion_diaria_llamadas` con ventanas exactas evitando `por_hora`, descartar el modal bloqueante, y la estructura completa de la pantalla de §6.

**Abierto:** Codex no pudo confirmar con la evidencia pegada que `America/Lima` no tenga DST (es un hecho —Perú no lo observa desde 1994— y el código usa el nombre de zona, así que es indiferente); y pide verificar que el índice `actividades_llamadas_autor_dia_idx` exista de verdad y no solo en el plan.

**VERIFICATION: NOT RUN** — es un diseño; no hay lint, typecheck, tests ni build que correr todavía.

**Archivos citados (rutas absolutas):**
`/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop/CRM-Avance-Corp/supabase/migrations/20260920041500_crm_gestion_diaria_analista.sql` · `.../20260807203757_crm_metas_sla_versionados.sql` · `.../20260816221500_crm_lead_libre_f1_verificacion.sql` · `.../20260823204930_crm_alertas_reconocimientos.sql` · `.../20260910225540_crm_notificaciones_push_tasa.sql` · `.../supabase/migrations/MIGRACIONES.md` · `.../docs/gestion-diaria/GESTION-DIARIA.md` · `.../docs/gestion-diaria/PLAN.md` · `.../app/src/lib/alertas.ts` · `.../app/src/lib/reconocimientos-alertas.ts` · `.../app/src/lib/motor-siguiente.ts` · `.../app/src/lib/vistas.ts` · `.../app/src/screens/config.tsx` · `.../app/src/screens/config-sla.tsx` · `.../app/src/components/app/guardados-sla-pendientes.tsx` · `.../app/src/App.tsx` · `.../app/src/data/crm-config-api.ts` · `.../app/src/data/crm-config-queries.ts` · `.../app/src/data/crm-queries.ts`

---
