---
fecha: 2026-09-15
estado: publicado-verificado
tags: [crm, citas, gerencia, deposito]
---

# Citas Gerencia — nombre de la etapa Depósito

Miguel pidió que la etapa posterior a Entrevistas se llame **Depósito**. Se actualizan el encabezado del avance mensual, sus etiquetas accesibles, el detalle por analista, la ayuda y la columna «Depósito %» del CSV.

Es un cambio de presentación: el depósito se sigue identificando cuando la persona se convierte en cliente. Se conservan las metas, fórmulas, fuentes, atribución y datos existentes; no se modifica SQL.

Verificación: `npm run check` PASS (3605 pruebas, lint, tipos, build y gates incluidos); los tres recorridos existentes de `citas-avance-mensual.spec.ts` PASS, con sus selectores actualizados al nombre nuevo. Captura de escritorio inspeccionada. LEVEL 1: sin revisión secundaria. Logs en `_dev_artifacts/citas-ticket-soles/deposito-{check,e2e}-20260915.log`.

## Publicación autorizada y verificada

Miguel indicó «publica» y después «tengo la extensión en VS Code, úsala». Se utilizó la sesión OAuth existente de Hostinger Connector mediante su servidor oficial, sin pedir una clave nueva ni cambiar conexiones. Véase [[Hostinger - publicar con la sesion de VS Code]].

Publicado desde Main local/remoto `b278d0ba40a634d46846e695c661654de5aa032f`, construido en copia limpia. Archivo `crm-20260915T215520Z-b278d0ba40a6.zip`, SHA-256 `15586597e182929d67153cc5a14bbc65c7fd5ec97c273f10d9b748bd9927d374`. Versión productiva `build-20260915T215515935Z`; 67/67 archivos de código/documentos coinciden por HTTP. Se conserva la reversa inmediata `crm-20260915T180647Z-2553466ee15a.zip`. Los cambios sin confirmar de otras sesiones se conservaron fuera del artefacto.

Evidencia: `UX-UI-GERENCIA/citas-deposito-2026-09-15/`. Acceso manual autenticado a Citas en producción NOT RUN; la evidencia visual procede del recorrido local y la publicación se verificó mediante hashes HTTP.

Relacionado: [[Citas Gerencia - decisiones finales para publicar 2026-09-14]], [[Citas Gerencia - ticket con todo el capital del mes 2026-09-15]], [[Citas Gerencia - ticket unificado en soles 2026-09-14]].
