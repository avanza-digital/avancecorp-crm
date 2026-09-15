---
fecha: 2026-09-15
tags: [hostinger, publicacion, herramientas]
---

# Hostinger — publicar con la sesión de VS Code

Hostinger Connector `hostinger-official.hostinger-connector` 1.3.3 estaba conectado mediante OAuth en VS Code aunque las herramientas de Hosting no estaban expuestas en esta sesión de Codex. La ausencia de `HOSTINGER_API_TOKEN` no significa que falte acceso: el servidor oficial reutiliza la sesión guardada por la extensión.

El README instalado documenta `npx --package=hostinger-api-mcp@latest hostinger-hosting-mcp`. El paquete instalado 1.59.0 se utilizó directamente, sin instalar otro ni cambiar ajustes. Su cliente MCP descubre `hosting_deployStaticWebsite`, que recibe `domain`, `archivePath` y `removeArchive: false` para subir un ZIP estático ya compilado. La autenticación y su renovación quedan a cargo del servidor oficial; no imprimir, copiar ni convertir las credenciales en variables o argumentos.

El wrapper antiguo `_DEV_NO_SUBIR/deploy-hostinger-mcp.mjs` exige un API token para publicar, pero su modo `preflight` funciona sin él y se conserva. Para esta entrega se usó el adaptador privado `_dev_artifacts/citas-ticket-soles/hostinger-extension-publicar.mjs`, vinculado al artefacto y commit de Citas: no reutilizar su modo de publicación para otra entrega sin preparar y verificar su candidato. Verifica Main local/remoto, copia limpia, manifiesto y preflight antes de invocar el servidor.

La respuesta «Request accepted» exige verificar después `version.json` y los archivos por HTTP. El archivo publicado se construyó desde el commit verificado y conservó fuera los cambios de otras sesiones que aún no tenían commit. No fue necesario reiniciar VS Code.

Relacionado: [[Citas Gerencia - etapa Deposito 2026-09-15]], [[Main unico - sincronizacion y publicacion 2026-09-04]].
