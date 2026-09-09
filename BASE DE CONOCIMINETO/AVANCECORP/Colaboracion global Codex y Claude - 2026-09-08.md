---
tags: [agentes, codex, claude, configuracion, verificacion]
actualizado: 2026-09-08
estado: instalado-global-verificado
---

# Colaboración global Codex y Claude

El usuario solicitó que el sistema sirva para cualquier proyecto que desarrolle.
Se instaló a nivel de su cuenta en esta Mac; no requiere copiar archivos a cada
repositorio. No se sincroniza automáticamente con otras máquinas o contenedores.

## Ubicaciones y alcance

- `~/.codex/AGENTS.md` y `~/.claude/CLAUDE.md`: reglas globales añadidas sin borrar
  las instrucciones anteriores.
- `~/.config/ai-collaboration/`: protocolo, gate genérico, guía y seis grupos de
  pruebas de instalación. La guía contiene resultados y límites concretos.
- `~/.local/bin/claude-review`: Claude reviewer sin herramientas/MCP, con evidencia
  adjunta y verificación del inventario real de inicio.
- `~/.local/bin/codex-review-mcp`: servidor Codex reviewer read-only, sin shell,
  subagentes, plugins ni MCP heredados. Usa una carpeta neutral; el PRIMARY
  adjunta las reglas y evidencia del proyecto.
- `~/.claude/settings.json`: permisos y tres hooks globales; conserva modelo,
  modo normal, plugins y ajustes anteriores. No copia políticas de negocio del CRM.
- `~/.claude.json`: añade `codex` de alcance usuario y preserva los otros MCP.

Cada tarea tiene un solo PRIMARY que escribe. El otro agente únicamente revisa.
La cadena termina PRIMARY → SECONDARY_REVIEWER → PRIMARY. LEVEL 1 no consulta;
LEVEL 2 normalmente una vez; LEVEL 3 una vez cuando sea razonablemente posible.
Máximo habitual dos, con evidencia que justifique la segunda consulta.

El gate identifica los comandos reales de cada proyecto. No supone npm, no
instala CI genérico ni crea worktrees. Dos PRIMARY simultáneos en tareas distintas
necesitan working trees separados. AvanceCorp mantiene sus reglas, wrappers,
gates y configuración específica; las entradas MCP locales pueden prevalecer.

## Hallazgos y verificación

Los plugins de Claude podían resolver otra CLI Codex mediante PATH; se fijaron
las rutas verificadas de ambas CLIs en los wrappers globales. Desde una carpeta
ajena al proyecto, Claude confirmó el MCP `codex` conectado y de alcance usuario.
El launcher también pasó su comprobación de configuración efectiva y handshake.

Claude global usa `dontAsk` y cero herramientas en lugar del flujo de planes.
Su salida stream-json debe contener un solo inicio con herramientas/MCP vacíos
y un resultado único con VERDICT válido. Se probó el rechazo de un inventario
con Bash. Seis grupos de tests, sintaxis de cinco scripts y los JSON pasaron.

Se realizaron dos consultas de Claude; ambas devolvieron CHANGES_REQUESTED.
Se atendieron los hallazgos reproducibles de CLIs anidadas y flujo de planes.
La segunda indicó que el texto genérico del harness todavía menciona herramientas;
la verificación externa del inventario efectivo pasó. No se solicitó otro review
para obtener aprobación ni se presentó ese dictamen como PASS.

No se ejecutó un turno adicional de modelo Codex desde Claude ni tests/build de
producto. Se preservaron los cambios previos del CRM y no hubo commits, push,
despliegues ni modificaciones en otros repositorios. Los respaldos originales
están en un directorio privado dentro de la instalación global.

Para activar: abrir nuevas sesiones de Codex y Claude, o reconectar `codex` en
`/mcp`. Tras cambiar versiones/MCP/plugins/settings, reconectar y repetir los
checks antes de otra consulta. No cambiar estas configuraciones durante un review.

Relacionado con [[Inicio]] y
[[Sistema de colaboracion Codex y Claude Code 2026-09-07]].
