---
tags: [feature, email, marca, edge-function]
actualizado: 2026-07-15
---

# Correo de bienvenida al portal (identidad de marca)

El correo que recibe un CLIENTE nuevo al ser dado de alta. Rediseñado con la identidad de marca del portal (**navy + verde**), a juego con el de [[Recuperación de contraseña]].

## Dónde vive (importante)
- **NO** es una plantilla de Supabase Auth (el portal crea los clientes por edge con `service_role`, sin el signup de Auth).
- Vive **DENTRO de la edge function `crear-cliente`** → función `plantillaBienvenida()`. Cambiar el correo = editar esa función y **redesplegar la edge**.
- Fuente de diseño / preview (no se sube a Hostinger, prefijo `_`): `_plantillas-correo/bienvenida.html`.

## Rediseño 2026-07-15
- De navy + **dorado** + crema → navy + **verde** (color del logo real), mismo lenguaje visual que el correo de recuperación (barra de acento verde, logo sobre blanco, botón navy bulletproof, cajas con borde-izq verde).
- **Se conservó toda la info funcional**: saludo por nombre, credenciales (correo + clave temporal, dinámico según `claveTemporal`), botón "Acceder al portal", guía de instalación de la app en 3 pasos + `miavance.com/instalar`, contacto del asesor + `info@miavance.com`, footer con RUC/Grupo MasCapital.
- Robustez de email: tablas + estilos inline, botón bulletproof con VML para Outlook, responsive, dark-mode-aware, preheader oculto, `alt` en el logo. **Asunto sin cambios:** `Bienvenido(a) a tu portal de inversiones Avance Corp`.
- **Cambio quirúrgico**: solo se reemplazó `plantillaBienvenida()`; la lógica de creación/seguridad (validación de rol, documento, insert de perfil, auto-asignación de analista) quedó **byte-idéntica** (git diff confirma que todos los hunks caen dentro de la función).

## Deploy y verificación (todo hecho el 2026-07-15)
- Edge `crear-cliente` **v17 → v18** desplegada por MCP (`deploy_edge_function`), **`verify_jwt: true` preservado**, mismos 2 archivos (`crear-cliente/index.ts` + `_shared/documento.ts`).
- Verificado: deploy **ACTIVE v18** (compila) + smoke test sin auth → **HTTP 401** (gateway/verify_jwt activo) + **correo real por Resend a `migueljbr89@gmail.com` → Status `delivered`** con el HTML de marca (ejemplo José / 00AB1234).
- El correo real de cada cliente nuevo se confirmará en la próxima alta real (la lógica de interpolación de `nombre`/`correo`/`clave` no cambió).

## Claude Design (nota de marca)
- El sistema de diseño de Miguel en claude.ai/design (**"Avanza Design System"**, projectId `9317f3b2-67df-485a-aa08-a048508a302c`) es el del **CRM** (violeta `#7C3AED`, tipografías Outfit/Inter) → **otra identidad ≠ portal**. Por eso los correos a clientes NO usan el violeta, sino navy+verde del logo.
- Las 2 plantillas de correo se subieron a ese proyecto como sección **"Correos"** (`emails/recuperar-contrasena.html`, `emails/bienvenida.html`) vía la tool DesignSync, como galería/documentación.

## Actualización v2 + Sistema de Correos en Claude Design (2026-07-15b)
- **Correo bienvenida v2 → edge `crear-cliente` v18→v19** (MCP, `verify_jwt:true` preservado): mejora de diseño pedida por Miguel ("mejora con Claude Design"). Cambios: **lista de beneficios con checks verdes** ("Con tu portal puedes"), **credenciales refinadas** (ícono 🔑, micro-labels, clave temporal en pastilla verde), botón con flecha "→", copy más cálido, ritmo pulido. Cambio quirúrgico (solo la plantilla; lógica byte-idéntica). Verificado: v19 ACTIVE (compila) + smoke 401.
- **Método de deploy:** se intentó el CLI de Supabase pero quedó logueado en **otra cuenta** (`avanzadigitald`/proyecto `jionwkulrmgiegqirjxq`) que NO tiene acceso a `dctqcbznekcyxhjujuci` → se usó el **MCP** (autorizado al proyecto correcto). Para usar el CLI a futuro, hacer `supabase login` con la cuenta dueña de la BD de producción.
- **Sistema de Correos en Claude Design** ("Avanza Design System", `emails/`): se subió una biblioteca reutilizable — `_tokens.html` (Fundamentos), 7 componentes (`components/`: header, boton, beneficios, credenciales, aviso, pasos, footer), las 2 plantillas y un `README`. Fuente local: `_plantillas-correo/_ds/`. Para los próximos correos (pagos/comunicados) reusar estas piezas.

## Relacionadas
[[Recuperación de contraseña]] · [[Importador de clientes]] · [[Clave temporal = DNI]]
