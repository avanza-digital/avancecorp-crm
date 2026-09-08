---
tags: [retomar, cartera, F4, multiempresa]
fecha: 2026-09-08
estado: pausado-por-Miguel
codigo: RETOMAR-63
---

# CARTERA — F4 guardada para la siguiente sesión

Miguel pidió parar y seguir mañana. **Desarrollo pausado a petición del usuario. F4/G4 sigue abierto.**

- Commit del avance recuperado: **`79fda66` — Guarda avance F4 con históricos recuperables y banco aislado**.
- Rama: **`codex/f4-cierre`**. Worktree: **`/private/tmp/avancecorp-f4-desarrollo`**.
- El commit está en el repositorio Git principal, aunque el worktree esté en `/private/tmp`. No hubo push, integración a main ni publicación.
- Banco ficticio: `/private/tmp/avancecorp-f4-bank`; contenedor `supabase_db_avancecorp-f4-bank`; API 56321 y PG 56322. Escritor F4 apagado, cero lotes históricos permanentes en el banco original.
- Checkpoint: **7 grupos de censo + 19 de lote + 7 de concurrencia PASS**, 37 funciones cotejadas. Preflights del backend y Deno check satisfactorios. Limitaciones registradas, sin declarar G4 cerrado.

## Retomar

Abrir el worktree y leer [[F4 multiempresa - historicos recuperables y commits (2026-09-08)]], su matriz `CRM-Avance-Corp/supabase/scripts/f4/ESTADO-ACEPTACION.md` y `2026-09-08-continuacion-historicos.json` en `scripts/evidencia-f4/`.

El directorio original tenía cambios de otra tarea; no copiar esta rama encima ni descartar esos cambios. Conservar sus fuentes no versionadas hasta una conciliación explícita. Si ya no existe el worktree temporal, recuperar **la rama `codex/f4-cierre`** desde el repositorio principal en un worktree nuevo; el avance está comprometido en Git. La candidata SQL de construcción se regenera con el generador documentado; aún no se versiona como migración ni está registrada como aplicada.

Sigue cerrar los límites del histórico (corpus F2, escritores concurrentes y lote máximo), titularidad neutral, permisos, corrección trazable de solicitudes, paridad financiera y reconstrucción/reversa. PDF intacto; cualquier texto de cotitulares exige mostrar propuesta a Miguel antes de editarlo. No reejecutar F2 productiva ni activar F4/F5.

Relacionadas: [[RETOMAR-62 - identidad unificada ENCENDIDA, sigue F4 (2026-09-07)]], [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].
