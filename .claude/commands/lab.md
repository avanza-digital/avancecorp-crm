---
description: Arranca el UI Playground (galería + Remotion Studio) y muestra SIEMPRE la guía de uso
---

Arranca el laboratorio de animaciones (`/Users/usuario/Desktop/DESARROLLO/DESARROLLO/ui-playground/`):

1. Primero verifica si ya responden `http://localhost:5173` (galería) y `http://localhost:3000` (Remotion Studio) con curl. Si un puerto ya responde 200, NO dupliques ese servidor.
2. Lo que falte, arráncalo en background:
   - Galería: `cd /Users/usuario/Desktop/DESARROLLO/DESARROLLO/ui-playground/galeria && npm run dev`
   - Remotion: `cd /Users/usuario/Desktop/DESARROLLO/DESARROLLO/ui-playground/remotion && npx remotion studio --no-open`
3. Confirma con curl que ambos respondan 200.
4. **Cierra mostrando la GUÍA DE USO** (Miguel la quiere en cada arranque), con este contenido adaptado al estado actual:

---

## 🧪 Guía del laboratorio

**🎬 Remotion Studio — http://localhost:3000 → aquí se DISEÑA**
Este es el tablero de diseño de Miguel: las animaciones se crean y pulen aquí primero
(motion, colores, timing) como composiciones de video. Lista las composiciones que existan.

**🎨 Galería — http://localhost:5173 → componentes vivos**
Componentes de interfaz ya interactivos (hover, click, scroll) listos para revisar y aprobar.

**El flujo (regla de Miguel):** primero el DISEÑO en Remotion / la galería → Miguel revisa y
aprueba en el navegador → luego los modelos de lenguaje (las sesiones de IA) lo ADAPTAN al
destino real: componente para el CRM, port a vanilla para el portal, o MP4 para redes.

**Comandos:**
- `/componente <pedido>` — componente animado nuevo en la galería
- `/animacion <pedido>` — diseño de video nuevo en Remotion
- `/render [id]` — exporta el MP4 final
- `/promover <componente> al crm|portal` — adapta lo aprobado a su destino
