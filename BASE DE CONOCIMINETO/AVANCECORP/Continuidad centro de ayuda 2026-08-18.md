# Continuidad centro de ayuda 2026-08-18

Relacionado con [[Centro de ayuda del vendedor]] y [[Plan motor de búsqueda de ayuda del vendedor]].

## Estado confirmado al cierre

- El backend del centro de ayuda ya está desplegado en Supabase producción.
- La migración remota registrada es `20260818054949_crm_ayuda_vendedor_servidor`.
- Producción contiene 17 guías, 112 expresiones aprobadas y 3 reglas de aclaración.
- Las RPC públicas autenticadas son `crm.ayuda_vendedor_inicio(text)` y `crm.consultar_ayuda_vendedor(text,text)`.
- La interfaz compilada del centro de ayuda ya fue publicada en Hostinger sobre `crm.miavance.com`.
- Hostinger aceptó la carga y el despliegue del ZIP; después se solicitó la limpieza de la caché del sitio.
- Producción respondió `HTTP 200` y sirvió `assets/index-DVhmt7Ry.js` y `assets/index-a7hXt_lB.css`.
- Los SHA-256 del HTML, JavaScript y CSS servidos en producción coinciden exactamente con los archivos del ZIP aprobado.

## Paquete listo para publicar

- Archivo persistente: `releases/crm-ayuda-vendedor_20260818_012100.zip`.
- SHA-256: `5d021c6004f7c5f54f9bf5d0b0dc955161ef65f5a983e197d6f422a011055cd4`.
- El ZIP contiene archivos estáticos compilados en la raíz y puede extraerse directamente en `public_html`.
- El paquete fue revisado para incluir el centro de ayuda y excluir el texto retirado y otros cambios no relacionados.

## Conexión de Hostinger — resuelta

- La cuenta correcta de Hostinger sí muestra `crm.miavance.com` en hPanel.
- El administrador de archivos correcto es el de la cuenta `u318796122` y se abrió en `public_html`.
- La extensión de Hostinger se volvió a conectar con la cuenta correcta.
- La verificación posterior confirmó que el conector devuelve `crm.miavance.com`, activo, bajo la cuenta `u318796122`, con raíz `/home/u318796122/domains/crm.miavance.com/public_html`.
- Iniciar sesión en `hpanel.hostinger.com` no cambia automáticamente la cuenta OAuth del conector de Codex/ChatGPT.
- El primer intento de carga mediante el selector de archivos de Chrome no transmitió el ZIP ni alteró producción; el despliegue posterior mediante el conector sí concluyó correctamente.

## Despliegue concluido

1. Paquete publicado: `releases/crm-ayuda-vendedor_20260818_012100.zip`.
2. Caché de Hostinger limpiada después del despliegue.
3. Integridad verificada byte a byte para `index.html`, `assets/index-DVhmt7Ry.js` y `assets/index-a7hXt_lB.css`.
4. El bundle servido contiene `Centro de ayuda` y el manejo del estado `No se pudieron cargar las consultas frecuentes`.
5. Queda únicamente la validación de aceptación con una sesión CRM real: consulta exacta, ambigua y desconocida.

## Nota operativa

No volver a ejecutar la migración de Supabase ni volver a publicar el mismo ZIP. El despliegue técnico está completo; solo queda la validación de aceptación dentro de una sesión CRM real.
