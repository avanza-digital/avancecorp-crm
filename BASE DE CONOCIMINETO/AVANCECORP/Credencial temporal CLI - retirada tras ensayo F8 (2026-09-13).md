---
tags: [supabase, seguridad, f8]
actualizado: 2026-09-13
---

# Credencial temporal CLI — retirada tras ensayo F8

Tras [[F8 - piloto economico preparado localmente (2026-09-13)]], Miguel
autorizó retirar una credencial que apareció en la salida técnica. Codex corrigió
su aviso inicial: correspondía al rol temporal `cli_login_postgres`, no a la
contraseña principal de base de datos.

El rol ya estaba caducado desde las 17:52 Lima. Se eliminó mediante la API de
Supabase a las 19:22 y se verificó su ausencia, cero conexiones abiertas y
proyecto saludable. Se conservaron contraseña principal, claves API, usuarios
y banderas del CRM. Claude revisó la contención; sus observaciones y las
verificaciones quedaron evaluadas en el acta técnica:
`CRM-Avance-Corp/supabase/scripts/multiempresa-f8/CIERRE-CREDENCIAL-CLI-2026-09-13.md`.

Regla para futuros ensayos: la salida de `supabase db dump --dry-run` contiene
credenciales. Capturarla en memoria y mostrar solo campos permitidos; evitar
argumentos de procesos, trazas y prompts con secretos. No se afirma que las
salidas históricas de la conversación puedan borrarse desde el repositorio.

La CLI recreará este rol con una credencial nueva cuando lo necesite. F8 sigue
sin instalar ni activar en producción; esta contención no cambia el plan.
