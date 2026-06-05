# Alta de los 3 analistas — fusión asesor → analista

Crear cada uno en: **Portal → `/admin/clientes` → "+ Nuevo miembro del equipo" → tipo "Analista"**.
El formulario ya tiene los campos de **WhatsApp** y **cargo** (lo que el cliente verá como su asesor).

Todo está pre-llenado **salvo lo marcado 【TÚ】** (DNI / tu correo / contraseña).

| Campo | MIGUEL BRICEÑO | CARMEN JARAMILLO JULCA | LISSETH NUÑEZ GARCIA |
|---|---|---|---|
| Tipo | Analista | Analista | Analista |
| Nombre completo | MIGUEL BRICEÑO | CARMEN JARAMILLO JULCA | LISSETH NUÑEZ GARCIA |
| **DNI** | **【TÚ】** | **【TÚ】** | **【TÚ】** |
| Teléfono | (opcional) | (opcional) | (opcional) |
| WhatsApp | 51986567788 | 51986799209 | 51940559974 |
| Cargo | Asesor de Inversiones | Asesor de Inversiones | Asesor de Inversiones |
| **Correo** | **【TÚ】** (tu correo) | carmen@cacmascapital.com | lisseth@cacmascapital.com |
| **Contraseña inicial** | **【TÚ】** (mín 8) | **【TÚ】** (mín 8) | **【TÚ】** (mín 8) |

> Para los analistas la contraseña se escribe a mano (no es automática como en los
> clientes). Si quieres, usa el DNI como contraseña inicial (tiene 8 dígitos) y que
> la cambien luego desde su perfil.

## Después de crearlos
1. En **Clientes**, reasigna estos **5 clientes** a "MIGUEL BRICEÑO" con el botón "Asignar analista" (⇆):
   - CARLOS CARO DIAZ
   - CLARISA MANRIQUE CAMPOS
   - ELIANA NELLY BARRIGA PALOMINO
   - GIANINA BERNUY MONTES
   - SARA LUZ LIMACHE CORTEZ
2. Avísame y corremos juntos el **SQL de limpieza final** (`FUSION_asesor_analista_LIMPIEZA_FINAL.sql`).
