# Sistema de Correos — Portal Avance Corp

Identidad de los correos que reciben los **clientes del portal** (miavance.com).
Distinto del CRM (violeta). Aquí manda la marca del logo: **navy + verde**.

## Fundamentos
- **Color:** navy `#0f1e3d` (títulos/botón) · verde `#2fa855` (acento/checks) · verde AA `#1f8a4a` (enlaces/micro-labels) · fondo `#eef1f7` · caja `#f4f7fb` · texto `#5a6480`.
- **Tipografía:** Segoe UI / Arial (pila segura para correo). Título 27/800, subtítulo 17/800, cuerpo 15/400, micro-label 10/700 +tracking, mono para credenciales.
- **Estructura:** contenedor 600px · barra de acento verde · tarjeta blanca radio 16 · logo sobre blanco.

## Componentes (`components/`)
`header` · `boton` (CTA bulletproof + VML Outlook) · `beneficios` (lista con checks) · `credenciales` · `aviso` (borde verde) · `pasos` (numerados) · `footer`.

## Plantillas (`.`)
- `bienvenida.html` — alta de cliente nuevo (vive en la edge `crear-cliente`).
- `recuperar-contrasena.html` — "Olvidé mi contraseña" (plantilla de Supabase Auth).

## Reglas de robustez (correo, no web)
Tablas + estilos inline · botón bulletproof con fallback VML · `max-width:100%` · dark-mode-aware · preheader oculto · imágenes con `alt` (URL absoluta en miavance.com) · sin flexbox/grid/JS.

## Fuente en el repo
`_plantillas-correo/` (prefijo `_` → NO se sube a Hostinger). Al cambiar un correo: editar la fuente y **redesplegar** (bienvenida = edge; recuperación = pegar en el panel de Supabase Auth).
