---
tags: [cuenta, demo, cliente, incidente-tecnico]
actualizado: 2026-07-15
---

# Cuenta demo de Kirk (dueño) + gotcha de crear usuarios por SQL

Se creó una **cuenta de CLIENTE** para el dueño **Kirk Sánchez** (para que vea el portal como inversionista), con una inversión de ejemplo.

## Datos de la cuenta (2026-07-15)
- **Correo:** `kirk@cacmascapital.com` · **rol:** cliente · `user_id` `cfa5b635-0afc-44a9-9cdb-6aaf81e70b4f`.
- **Contraseña:** generada, entregada a Miguel en el chat — **NO se guarda en el repo** (regla de seguridad). Si se pierde, resetear desde `/admin` o "Olvidé mi contraseña".
- Es una cuenta de **cliente aparte** de su cuenta de *directorio* (el mismo dueño puede tener ambas — ver [[Colaborador que invierte]] / DNI único solo entre clientes).
- **Contrato `2026-01-100100`:** US$ 100,000 · 15% anual · mensual · activo · categoría nuevo. 13 cuotas = 12 × US$ 1,250 (interés) + US$ 100,000 (capital, 7 días tras el vencimiento). **Permanente → SÍ suma en el AUM del cockpit del directorio.**
- **Login verificado** (token válido). **PENDIENTE (Miguel, 2026-07-15):** decidir si se envía la bienvenida v2 a `kirk@cacmascapital.com` (opción A) o si Miguel entrega las credenciales en persona (opción B). No se envió aún.

## ⚠️ Gotcha técnico: crear un usuario Auth por SQL directo
Se creó por **SQL directo** (`auth.users` + `auth.identities` + `perfiles`) porque no había token de admin para la vía estándar (Admin API / edge `crear-cliente`). Aprendizajes:
- **GoTrue falla el login con `"Database error querying schema"`** si las columnas de *token* de `auth.users` quedan en **NULL**. Hay que ponerlas en **`''`** (cadena vacía): `confirmation_token, recovery_token, email_change_token_new, email_change, phone_change, phone_change_token, email_change_token_current, reauthentication_token`.
- Hay que insertar también la fila en **`auth.identities`** (`provider='email'`, `provider_id = user_id::text`, `identity_data = {sub, email, email_verified:true, phone_verified:false}`), o el login no resuelve.
- El **clasificador de auto-mode BLOQUEA** escrituras crudas a `auth.users`/`identities` en prod (con razón). **Vía recomendada a futuro: crear clientes desde `/admin/clientes`** (usa la Admin API y manda la bienvenida sola). El SQL directo es último recurso.

## Relacionadas
[[Correo de bienvenida al portal (marca)]] · [[Colaborador que invierte]] · [[Rol Directorio]]
