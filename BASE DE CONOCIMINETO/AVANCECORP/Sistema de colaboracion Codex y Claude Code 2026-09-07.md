---
tags: [agentes, codex, claude, seguridad, verificacion]
actualizado: 2026-09-07
estado: implementado-local-verificado
---

# Sistema de colaboración Codex y Claude Code

Se formalizó un flujo bidireccional con un solo escritor: Codex o Claude puede ser `PRIMARY`, y el otro participa únicamente como `SECONDARY_REVIEWER` read-only. La profundidad termina al volver al `PRIMARY`; el reviewer no consulta, delega ni inicia otra cadena.

La fuente de verdad operativa es `.ai/REVIEW_PROTOCOL.md`. El cierre de tareas se rige por `.ai/VERIFICATION.md`: escribir código o recibir un `PASS` de IA no basta sin los checks proporcionales al riesgo.

Codex consulta a Claude únicamente mediante `scripts/claude-review`. Claude consulta a Codex mediante el MCP `codex`, pasando `sandbox=read-only` y `approval-policy=never`; un hook rechaza llamadas que omitan esas fronteras. Las tareas se clasifican como LEVEL 1, 2 o 3 y tienen un presupuesto normal de 0 a 2 consultas.

La configuración conserva los gates existentes del CRM, Lefthook, los workflows y los reviewers especializados. Se añadió un workflow pequeño para validar JSON, sintaxis shell y los contratos críticos de los hooks.

Durante la implementación se retiraron de `.claude/settings.local.json` cuatro permisos locales que contenían asignaciones sensibles inline. La comprobación posterior precisó el alcance: tres repetían un mismo token de Hostinger; el cuarto contenía valores explícitamente ficticios para `npm run test:rls:preflight`, con destino `ficticio.supabase.co`. No eran cuatro credenciales reales.

Se comprobó el token afectado con una petición GET autenticada al endpoint oficial de listado de VPS de Hostinger: respondió HTTP 401. Ese valor tampoco aparece en las configuraciones activas revisadas (`~/.codex/config.toml`, `~/.claude.json` y `.claude/settings.local.json`). El token ya no es válido; no fue necesario regenerar accesos de producción. No se registran valores de credenciales en esta nota.

El wrapper ahora analiza exclusivamente evidencia saneada adjunta por el PRIMARY. Deshabilita herramientas, MCPs y personalizaciones de esa invocación e incorpora el protocolo completo al prompt. La configuración interactiva se conserva. Se corrigió también una comprobación de texto vacío que se atascaba con prompts largos en Bash de macOS; el test del wrapper cubre ese caso.

El hook local ignorado `.codex/hooks.json` se conservó, pero su recordatorio obsoleto de Graphify se cambió por CodeGraph para alinearlo con las reglas vigentes del proyecto.

Relacionado con [[Inicio]] y [[Main unico - sincronizacion y publicacion 2026-09-04]].

## Cierre de la reanudación

Se retomó el trabajo tras el cierre de VS Code, conservando cambios ajenos y sin
commits, push, despliegues ni worktrees. El reporte completo quedó en
`.ai/IMPLEMENTATION_REPORT.md`.

La comprobación de configuración efectiva detectó que `mcp_servers={}` y
`plugins={}` se fusionaban con la configuración personal: quedaban 15 MCP
heredados. Se añadió `scripts/codex-review-mcp`, que enumera y deshabilita cada
MCP y apaga plugins/herramientas solo en la invocación del reviewer. Se verificó
cero MCP habilitados, once flags apagados y handshake real del servidor.

También se corrigieron el acceso histórico `git show HEAD:.env`, los casos
destructivos con `git -C`, la validación individual de todos los hooks y los
contratos de los reviewers especializados. Las reglas nativas de secretos
incluyen `.env.example`: la plantilla se gestiona manualmente.

Ocho grupos de pruebas y todos los pasos locales del workflow nuevo pasaron.
Se recibieron dos reviews reales de Claude, ambos con cambios solicitados;
el PRIMARY evaluó y corrigió los hallazgos reproducibles y documentó los límites.
No se ejecutó el banco completo del CRM ni CI remoto: esta tarea no cambió
código de producto ni autorizó publicación.

Para activar la configuración en una sesión ya abierta, reconectar `codex`
desde `/mcp` o iniciar Claude desde la raíz. Tras cambiar MCP/plugins/settings,
reconectar antes del próximo review; el inventario se fija al arrancar y no
debe modificarse la configuración mientras se revisa.
