---
tags: [feature, seguridad, auth, incidente]
actualizado: 2026-07-15
---

# Recuperación de contraseña ("Olvidé mi contraseña")

Flujo de **autoservicio** para que un usuario recupere su acceso sin que intervenga el admin. Es distinto del **primer ingreso** ([[Clave temporal = DNI]], que NO manda correo) y del **reseteo por admin** (edge `resetear-password`).

## Cómo funciona
1. `index.html` → botón "Olvidé mi contraseña" → `login.js` (`recoverSubmit`) llama `supabase.auth.resetPasswordForEmail(email, { redirectTo: '<origin>/reset-password.html' })`.
2. **Supabase Auth genera el enlace y envía el correo por su propio SMTP** — NO por las edge functions. El SMTP de Auth está configurado con **Resend** (`smtp.resend.com`).
3. El usuario abre el enlace (`#access_token=...&type=recovery`) → `reset-password.js` procesa el hash (evento `PASSWORD_RECOVERY`), muestra el formulario y llama `updateUser({ password })`.
4. Éxito → `signOut` → `/index.html?reset=ok` (toast "Contraseña actualizada").

> ⚠️ Clave para no confundirse: el correo de recuperación **NO** sale por la ruta Resend‑vía‑edge (como bienvenida / comunicados / pagos, que mandan desde `info@miavance.com` con `RESEND_API_KEY`). Sale por el **SMTP de Auth** de Supabase, que es una **configuración aparte** en el panel (Authentication → Emails → SMTP Settings). Por eso podían fallar los correos de recuperación mientras los demás llegaban bien.

## Incidente 2026-06-12 — el correo de recuperación no se enviaba (RESUELTO)
**Síntoma:** los usuarios pedían recuperar su clave y no llegaba el correo; el portal devolvía error. Un cliente real (`gdelzocollado@gmail.com`) lo intentó 2 veces sin éxito.

**Causa raíz (vista en los logs de Auth):** el SMTP de Auth estaba mal configurado, en **dos** campos:
- **Sender email** = una dirección `@gmail.com`. Resend solo está autorizado para `miavance.com` → `550 This API key is not authorized to send emails from gmail.com` → `500: Error sending recovery email`.
- **Username** ≠ `resend` (había quedado un correo). Para Resend el Username es la **palabra literal `resend`**, no un correo → `535 Invalid username`. *(Este 2º error se destapó recién al corregir el sender, porque la autenticación SMTP ocurre antes que la validación del remitente.)*

**Config correcta del SMTP de Auth** (Authentication → Emails → SMTP Settings):

| Campo | Valor |
|---|---|
| Host | `smtp.resend.com` |
| Port | `465` |
| Username | `resend`  *(palabra literal, NO un correo)* |
| Password | la API key de Resend (`re_…`) |
| Sender email | `info@miavance.com`  *(dominio verificado en Resend)* |
| Sender name | Avance Corp |

**Verificación (2026-06-12):** disparando `POST /auth/v1/recover` contra una cuenta de prueba → `HTTP 200` y `auth.users.recovery_sent_at` avanza a la hora actual. Antes se quedaba clavado en `2026-05-21` porque el envío fallaba. **`recovery_sent_at` solo se marca cuando el envío tiene éxito → es el indicador fiable** para verificar este flujo sin necesidad de abrir una bandeja.

**Pendiente de confirmar (chequeo humano):** abrir el enlace del correo y verificar que cae en `reset-password.html` con el formulario (no "enlace inválido"). Si fallara, agregar `https://miavance.com/reset-password.html` a las **Redirect URLs** permitidas de Auth.

## Diseño del correo con identidad de marca (2026-07-15)
El correo de recuperación por defecto de Supabase era "muy sencillo y feo" (un `<h2>` + enlace azul). Se rediseñó con la identidad de Avance Corp.

- **Dónde vive la plantilla:** el correo de "Olvidé mi contraseña" **NO** es una edge function ni HTML del portal → es la **plantilla interna de Supabase Auth**. Se personaliza pegando HTML en **Authentication → Emails → Templates → "Reset Password"** (asunto en un campo aparte). NO se puede editar por el MCP de Supabase (solo por el panel o la Management API `PATCH /v1/projects/$REF/config/auth` con un access token personal).
- **Fuente de la plantilla (repo, NO se sube a Hostinger — prefijo `_`):** `_plantillas-correo/recuperar-contrasena.html`. Copia de preview con enlace de ejemplo: `_plantillas-correo/_preview-recuperar-contrasena.html` (solo para ver, no se usa).
- **Variable del enlace:** `{{ .ConfirmationURL }}` (confirmado en la doc oficial de Supabase para la plantilla RECOVERY; también existen `{{ .Token }}` y `{{ .TokenHash }}`). Es el mismo enlace de siempre → cae en `reset-password.html`. **El flujo NO cambió, solo el diseño.**
- **Decisión de marca:** navy (`#0f1e3d`) + **verde** de marca (`#2fa855`/`#1f8a4a`) — se usó el verde del logo real (navy+verde), NO el dorado "premium" interno del dashboard. Logo real desde `https://miavance.com/img/avance-logo-full.png` (público, 200 OK).
- **Robustez de email:** tablas + estilos inline, botón bulletproof con fallback VML para Outlook, responsive, dark-mode-aware, preheader oculto, `alt` en el logo. Asunto sugerido: `Restablece tu contraseña — Avance Corp`.
- **Estado: CONFIRMADO EN PROD (2026-07-15).** Miguel pegó la plantilla en el panel de Supabase y probó. **Verificado end-to-end vía Resend** (no por suposición): el correo enviado a las 16:22 UTC a `migueljbr89@gmail.com` salió con `From: "AvanceCorp" <info@miavance.com>`, **Subject "Restablece tu contraseña — Avance Corp"**, **Status delivered**, y el **HTML es exactamente la plantilla de marca** (logo, badge candado, botón navy, caja verde, footer con RUC 20611392088). La variable `{{ .ConfirmationURL }}` renderizó al enlace real `.../auth/v1/verify?token=...&type=recovery&redirect_to=https://miavance.com/reset-password.html` → **el flujo sigue intacto**. Antes de las 16:22 los correos salían con la plantilla vieja "Reset Your Password" (inglés) → el cambio quedó activo en esa prueba. La expiración "60 minutos" del texto es el default de Supabase; ajustar si se cambió.
- **Cómo re-verificar sin suponer:** el SMTP de Auth manda por Resend → con el MCP de Resend, `list-emails` + `get-email` muestran asunto y HTML REAL de cada correo de recuperación enviado (indicador objetivo del estado de la plantilla en prod).
- **Correo de bienvenida:** ✅ hecho el 2026-07-15 — el correo de bienvenida al cliente (que NO es de Auth: sale de la edge `crear-cliente`) se rediseñó con este mismo lenguaje navy+verde. Ver [[Correo de bienvenida al portal (marca)]]. Los correos de **Auth** restantes (magic link, cambio de correo) siguen pendientes si algún día se usan.

## Notas relacionadas
[[Clave temporal = DNI]] · [[Arquitectura del portal]] · [[Inicio]]
