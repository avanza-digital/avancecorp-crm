---
tags: [feature, seguridad, auth, incidente]
actualizado: 2026-06-12
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

## Notas relacionadas
[[Clave temporal = DNI]] · [[Arquitectura del portal]] · [[Inicio]]
