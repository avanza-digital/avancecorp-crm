---
tags: [crm, gestion-diaria, supervisor, f4, verificacion]
estado: etapa 1 publicada — etapas 2–6 pendientes
fecha: 2026-09-21
---

# Gestión Diaria F4 — vista del equipo validada localmente

**Actualización productiva:** el 21/09 Miguel autorizó las dos SQL y `$release-crm`,
y aprobó/integró PR #62. F4 etapa 1 y resultado v4 están publicados desde
`526e728e`, release `crm-20260921T170501Z-526e728e31ff`. SQL instalado y registrado;
CI, gates productivos y recursos ejecutables verificados. No repetir aprobación,
integración ni instalación. Retomar recorrido de negocio y F4 etapa 2.
Ver [[Gestion Diaria - publicacion de equipo y resultado (2026-09-21)]].

Lo que sigue conserva el historial de preparación, anterior a esa autorización;
sus referencias a «sin publicar» no describen el estado vigente.

La etapa 1 permite ver a todos los analistas activos autorizados, incluso sin
actividad ni cartera, con sus pendientes y motivos de atención. No demuestra
presencia en tiempo real. Los cortes, pop-ups, configuración y TypeSafe quedan
fuera de esta entrega.

Fuente conservada en el commit `997e1290a34877541868bc9b1a083505584f9eaf`, rama
`codex/gestion-diaria-f4-vista-equipo`, basada en `avancecorp/main` (`37a936c7`).
Worktree de preparación: `/private/tmp/avancecorp-gd-f4-vista.chvRqh`.
El 21/09 Miguel autorizó reconciliar las ramas, preservando los cambios de ambas;
no autorizó instalación SQL ni publicación.

El plan principal sigue siendo `CRM-Avance-Corp/docs/gestion-diaria/GESTION-DIARIA.md`.
El acta de esta entrega está incorporada a Main local, en
`CRM-Avance-Corp/docs/gestion-diaria/F4-VISTA-EQUIPO-IMPLEMENTACION.md`, con capturas,
comandos y límites. SQL exacto: `20260921040335_crm_gestion_diaria_equipo_vista.sql`.

## Verificación

PASS: gate integral del frontend; 39 pruebas focalizadas; navegador completo con
224 aprobadas y 26 omisiones preexistentes. PASS: scripts del CRM, tres oráculos
SQL, nueve mutantes nuevos y 48 de F1–F3, contrato PostgreSQL→frontend, tipos
cotejados con generación local y advisors sin incidencias. Banco exclusivo:
`gestion_diaria_f4_vista_chvrqh`, en `supabase_db_avancecorp-f5-bank`.

Claude revisó sin escribir. Su hallazgo de jerarquía se reprodujo antes del arreglo:
un puente inactivo ocultaba descendientes activos. Corregido recorriendo aristas
bajo RLS e intersectando el roster autorizado. También se mejoraron cabeceras de
tabla, foco y orden por tasa. El dictamen de la candidata anterior fue
CHANGES_REQUESTED; no se inventa una aprobación final del reviewer.

## Pendiente para uso productivo

La integración local ya está completada. Mostrar y aprobar el SQL antes de instalarlo y
publicar con invocación humana de `$release-crm` o `/release-crm`. Completar el
recorrido de negocio con el supervisor. No hubo instalación, push ni deploy.
La matriz HTTP general y la validación humana en producción no se acreditan con
los oráculos locales o los mocks del navegador.

## Reconciliación autorizada el 21/09

Los nueve conflictos con Main `40f2501b` están resueltos: se conservan el layout en
dos columnas y desplegables del taller, los arreglos publicados de caché parcial,
tarea autoritativa, paginación, pestañas vacías, semántica y permisos. «Llamar» y
el menú abren ahora el mismo panel con la tarea de servidor. El contacto anterior
no abre un resultado si su validación vuelve después de desmontarse.

El supervisor, su migración y la protección de avisos del lead no cambian respecto
de `997e1290`. Se retiraron dos componentes duplicados sin consumidores; su código
se recupera del historial Git. Se conserva la posición del lead dentro del grupo.
La vista móvil permite recorrer las cuatro pestañas sin etiquetas superpuestas.

Claude emitió CHANGES_REQUESTED sobre el primer diff de integración. Se aplicaron
los hallazgos de tarea y accesibilidad pertinentes; la hipótesis de desmontaje por
refetch se descartó con la definición del estado y una prueba con caché presente.
No se inventa un PASS final del reviewer. El acta registra gates y estado final.
Los cambios ajenos de temperatura/TypeSafe del taller no forman parte de F4 etapa 1.
Verificación final de integración: `npm run check` PASS, 270 archivos y 3.991 pruebas;
navegador completo PASS, 225 aprobadas y 26 omisiones preexistentes. Tres oráculos
SQL locales y contrato PostgreSQL→frontend repetidos PASS. Capturas de analista
en escritorio/móvil inspeccionadas; ninguna instalación ni publicación productiva.

Main local avanzó por fast-forward al merge `03249ba9` (padres `997e1290` y
`40f2501b`). Se verificaron por huella los 22 archivos ajenos; las 101 líneas
pendientes del ledger de temperatura se restituyeron sin commitearlas. Respaldo
recuperable de los cinco archivos que se cruzaban: stash
`1af9b3b15b41e1d705593c331506c6533b0d52db`. No reaplicarlo entero: contiene también
versiones antiguas de documentos ya reconciliados. La próxima sesión debe retomar
el objetivo F4 desde la aprobación del SQL, no repetir la conciliación ni adelantar
TypeSafe o los cortes. Instalación y publicación siguen necesitando aprobación.

Relacionadas: [[Gestion Diaria F4 - objetivos y piloto TypeSafe (2026-09-20)]] ·
[[Gestion Diaria - modulo nuevo y absorcion de Seguimiento 2026-09-19]] · [[Inicio]].
