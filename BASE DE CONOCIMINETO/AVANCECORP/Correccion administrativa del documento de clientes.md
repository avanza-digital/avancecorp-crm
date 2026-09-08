# Corrección administrativa del documento de clientes

Desde 2026-09-07, el tipo y número de documento de un cliente solo pueden corregirse por un usuario `admin` o `superadmin`. La operación está disponible desde **Mi cartera > Corregir cliente** del CRM y desde **Administración > Clientes** del Portal.

- CRM y Portal solicitan un motivo y usan `crm.corregir_documento_cliente_admin_fn`.
- Si el cliente ya está reconocido como [[Identidad unificada del CRM]], la corrección sincroniza el identificador, `public.perfiles`, el lead y la auditoría.
- Analistas, Operaciones, clientes y Gerencia CRM sin rol Portal `admin`/`superadmin` no pueden cambiar el documento.
- CRM permite corregir los demás datos del cliente según su autoridad habitual y solo habilita el documento cuando la sesión trae el rol Portal administrativo.

Relacionado: [[Bienvenido]]
