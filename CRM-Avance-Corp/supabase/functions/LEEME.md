# supabase/functions/ — edge functions del CRM (prefijo `crm-`)

**Vacía a propósito** (se llena desde F1).

Previstas en el plan:
- `crm-crear-vendedor` — alta con cuota + anti-escalación (fusión de `admin-crear-usuario` de
  VITANOVA con las convenciones del portal: CORS allowlist, dry_run, imports jsr:).
- `crm-convertir-lead` — conversión transaccional lead→cliente (extiende `crear-cliente` v12).
- `crm-enviar-push` — notificaciones a vendedores vía Expo Push Service.
- `crm-whatsapp-enviar` / `crm-whatsapp-webhook` — Cloud API con plantillas utility + ventana
  24 h (patrón dual-cliente RLS + secretos en Vault + HMAC tiempo-constante).
- `crm-importar-cartera` — import masivo server-side por lotes.

Regla dura: **toda función desplegada tiene su fuente versionada aquí** (prohibido el drift
tipo `intake-lead`/`diagnostico-push`). service_role jamás sale de las functions.
