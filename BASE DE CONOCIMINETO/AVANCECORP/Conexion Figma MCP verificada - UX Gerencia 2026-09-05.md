---
fecha: 2026-09-05
estado: mcp-conectado-y-verificado
tags: [figma, mcp, ux, gerencia, continuidad]
---

# Conexión Figma MCP verificada

Relacionado con [[AVC-UX-GERENCIA-FIGMA-20260905-R1]] y [[Plan de mejora UX de Gerencia - revision 2026-09-05]].

Miguel pidió explícitamente conectar Figma mediante MCP. Se registró el servidor remoto oficial `https://mcp.figma.com/mcp` en `~/.codex/config.toml`, con el nombre `figma`, y se completó OAuth mediante `codex mcp add figma --url https://mcp.figma.com/mcp --oauth-resource https://mcp.figma.com/mcp`.

## Evidencia de conexión real

- El comando terminó con `Successfully logged in`.
- La consulta de configuración fuera del sandbox devolvió `enabled: true` y `auth_status: o_auth`.
- Se inicializó un cliente determinista del App Server de Codex con sólo Figma en su configuración temporal. No se inició ningún turno de modelo ni se delegó trabajo a otro agente.
- `mcpServerStatus/list` devolvió `authStatus: oAuth` y el catálogo real de herramientas.
- Una llamada `mcpServer/tool/call` a `figma.whoami` respondió con Miguel Briceño, equipo **El equipo de Avance Corp**, asiento **Full**, nivel **pro**, destino `team::1673045681873340799`.
- Herramientas confirmadas, entre otras: `create_new_file`, `use_figma`, `upload_assets`, `get_metadata`, `get_design_context`, `get_screenshot`, `get_variable_defs` y `get_libraries`.

La comprobación se realizó por MCP, además de la verificación anterior de cuenta en el navegador. No basta con la sesión web para verificar OAuth de MCP.

## Continuidad técnica

El catálogo de herramientas de la conversación ya abierta aún no se había actualizado. Eso no impidió la comprobación real mediante la interfaz documentada del App Server. El verificador quedó en `/private/tmp/avc-figma-verify.mjs`; es temporal y sólo lee configuración, catálogo e identidad. La configuración MCP y OAuth permanecen gestionadas por Codex. No se guardaron tokens en el proyecto.

Las skills de Figma se localizaron en `/Users/usuario/.codex/.tmp/plugins/plugins/figma/skills/`, incluyendo `figma-create-new-file` y `figma-use`. Volver a localizar su ruta si cambia la instalación; leer las correspondientes antes de crear archivos o editar el lienzo.

## Estado de F0 y F1

La conexión está completada. El archivo de diseño, tablero con las 14 capturas, componentes y piloto de Ranking **siguen pendientes**; la conexión no acredita esos entregables ni la validación con Gerencia.

Próximo paso del plan autorizado: inspeccionar un archivo apropiado o crear **Gerencia · UX de reportes · Avance Corp** en el equipo verificado; organizar la auditoría y preparar componentes y piloto de Ranking en escritorio y móvil, con detalle y regreso. La autorización para crear el tablero consta en la continuidad y no necesita solicitarse de nuevo.

En esta conexión no se modificaron archivos de aplicación, backend, permisos del CRM ni fórmulas, y no hubo publicación.
