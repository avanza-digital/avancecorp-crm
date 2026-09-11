---
tags: [crm, f6, retoma, pausa]
fecha: 2026-09-10
estado: pausada-antes-de-publicar-ajustes
---

# F6 — pausa segura antes de publicar los ajustes

Miguel pidió detener el trabajo en un punto seguro y continuar mañana.
La preparación de esta publicación quedó en lectura: no se inició integración,
build de release, despliegue ni modificación de base de datos o banderas.

## Trabajo guardado

- Rama de desarrollo: `codex/f6-postventa`.
- Worktree: `/private/tmp/avancecorp-f5-publicacion`.
- Último commit antes de esta nota: `d04236d`.
- Respaldo Git privado de la rama y esta nota:
  `/Users/usuario/.codex/backups/avancecorp-f6-pausa-20260910/cartera-f6.bundle`.
- Selector de archivos: `513effa`. Retorno de foco y mensaje de conexión: `d586b66`.
- Revisión manual cerrada con excepción autorizada: VoiceOver **NOT RUN / omitido**.
- Gate sobre los últimos ajustes: `npm run check:all` **PASS**, 3.188 tests,
  159 E2E PASS y 26 E2E omitidas. No se repitió para esta pausa documental.

Los últimos ajustes de frontend todavía no están publicados. El estado productivo
documentado mantiene F4/F5/F6 apagadas; no se volvió a consultar la base productiva
en esta preparación. F6 no se declara terminada mientras esa publicación siga pendiente.

## Punto exacto para retomar

1. Leer esta nota y [[F6 - pruebas delegadas y ajustes de accesibilidad (2026-09-10)]].
2. Consultar Git remoto y el build vivo del CRM. Al pausar, Main local estaba en
   `1b9db12`, con cambios recientes de Facturación y Reparto, y `avancecorp/main`
   en `774a04f`. Esas referencias pueden avanzar en otras sesiones.
3. Integrar los cambios vigentes en la rama de trabajo conservando lo ajeno;
   ejecutar el gate completo sobre el resultado integrado y consultar a Claude
   mediante `scripts/claude-review`. Esa integración y sus comprobaciones:
   **NOT RUN** en esta preparación.
4. Sincronizar Main local con `avancecorp/main`, verificar igualdad y construir
   el ZIP desde ese commit limpio. Confirmar que contiene la versión publicada
   más reciente antes de desplegar únicamente a `crm.miavance.com`.
5. Verificar publicación, acceso y banderas apagadas; guardar evidencia y commits.
   Publicación de estos ajustes y verificación posterior: **NOT RUN** por la pausa.

Conservar los archivos ajenos sin seguimiento del worktree principal. No publicar
en `origin`, no crear ramas de release, no forzar pushes ni encender F4/F5/F6.
No se deja una publicación automática programada.

Después sigue F7 del [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].
F8/F9 y los 15 registros de identidad mantienen sus requisitos. Las comisiones
se calculan fuera del sistema. Véase también [[F6 - publicada y apagada (2026-09-10)]].
