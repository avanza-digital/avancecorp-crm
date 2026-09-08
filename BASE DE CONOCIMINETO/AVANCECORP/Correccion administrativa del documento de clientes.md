# Corrección administrativa del documento de clientes

Desde 2026-09-07, el tipo y número de documento de un cliente solo pueden corregirse por un usuario `admin` o `superadmin` desde **Administración > Clientes** del Portal.

- El Portal solicita un motivo y usa `crm.corregir_documento_cliente_admin_fn`.
- Si el cliente ya está reconocido como [[Identidad unificada del CRM]], la corrección sincroniza el identificador, `public.perfiles`, el lead y la auditoría.
- Analistas, Operaciones, clientes y Gerencia CRM no pueden cambiar el documento.
- CRM permite corregir los demás datos del cliente, pero muestra el documento bloqueado.

Relacionado: [[Bienvenido]]
