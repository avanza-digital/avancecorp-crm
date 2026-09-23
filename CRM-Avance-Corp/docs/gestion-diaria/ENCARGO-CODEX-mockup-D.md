# Encargo para Codex — construir el mockup «Opción D» de «Mi día»

Pégale esto a Codex tal cual (en su CLI o en su sesión). Devuelve DOS archivos HTML completos.
Claude los publica verbatim en el lienzo `https://claude.ai/artifact/SLrWQnh8TKV8bD7Pi4MMv5`.

---

Eres el AUTOR de este entregable. Devuelve el código COMPLETO en bloques de código, del
`<!doctype html>` al `</html>`. Nada de fragmentos ni «…igual que arriba». Responde en español.

## Qué entregas
1. `OpcionD.dc.html` — vista inicial de «Mi día».
2. `OpcionD-actividad.dc.html` — segundo nivel «Mi actividad».

## Formato obligatorio (.dc.html) — si falla, la página no renderiza
Esqueleto exacto de cada archivo:

```
<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<title>…</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
body{margin:0;font-family:'Plus Jakarta Sans',system-ui,sans-serif;background:#f6f8fc;color:#111e3d}
a{color:#111e3d;text-decoration:none}a:hover{color:#0a142c;text-decoration:underline}
</style>
</helmet>
<div style="width: 1440px; height: 900px; box-sizing: border-box; …">
  … todo el contenido …
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{"$preview":{"width":1440,"height":900}}'>
class Component extends DCLogic {
  renderVals() { return {}; }
}
</script>
</body>
</html>
```

Reglas que rompen el render:
- La línea `<script src="./support.js"></script>` va EXACTA en el `<head>`.
- El elemento raíz dentro de `<x-dc>` lleva tamaño FIJO 1440×900 y `box-sizing: border-box`.
- TODO el estilo visual va INLINE en `style="…"`. El `<helmet><style>` solo lleva `body` y `a`/`a:hover`.
  Nada de clases propias, nada de `:hover` fuera de `a`, nada de `@media`.
- Cerrar todos los elementos no vacíos; entrecomillar todos los atributos.
- Maquetar con flex o grid + `gap`. Grid en la forma `repeat(N, minmax(0, 1fr))`.
- Sin `{{holes}}`, sin `<sc-for>`, sin `<sc-if>`: maqueta estática con contenido literal.
- Sin `<iframe>`, `<object>`, `<embed>`, sin emoji, sin red salvo el `<link>` de Google Fonts.
- Iconos: SVG inline de trazo (`stroke="currentColor"`, `fill="none"`, `stroke-width="2"`), `aria-hidden="true"`.
- Accesible: `<button type="button">` y `<a href>` reales; nunca `onClick`/`role` sobre `div` o `span`;
  `aria-label` en botones de solo icono; pestañas con `role="tablist"` + `role="tab"` + `aria-selected`;
  la fila seleccionable es un `<button type="button" aria-pressed>` a ancho completo.

## Tokens (nada fuera de esta lista)
Fondo `#f6f8fc` · tarjeta `#ffffff` · borde `#e4e9f2` · borde fuerte `#d5ddec` ·
navy `#111e3d` · azul acción `#2563eb` · azul texto/tinte `#1d4ed8` / `#e5ecfd` ·
rojo `#991b1b` sobre `#fbe5e5` (SOLO «vencido») · ámbar `#92400e` sobre `#faefe1`, punto `#d97706` ·
gris secundario `#475569`. SIN VERDE. Un significado = un color; el estado nunca va solo en color.
Espaciado solo de la escala 4 / 8 / 12 / 16 / 24 / 32 / 48.

## Tipografía — 4 roles, MÍNIMO ABSOLUTO 16 px
| Rol | px / line-height | peso |
|---|---|---|
| Título de pantalla | 24 / 32 | 700 |
| Título de sección | 20 / 28 | 600 |
| Cuerpo | 18 / 28 | 500 |
| Etiqueta y dato secundario | 16 / 24 | 400 |
Ningún texto bajo 16 px, ni en chips ni en gráficos ni en botones. Nada de `opacity` para atenuar.

## Archivo 1 — `OpcionD.dc.html`
`<title>`: «Mi día — cómoda a la vista». Padding 24, columna con `gap:24px`.

**Cabecera (alto 64, `flex-shrink:0`):** h1 «¿A quién llamo ahora?» (24/32, 700). A la derecha UN
botón secundario (`min-height:48px`, blanco, borde `#e4e9f2`, radio 12, padding `0 20px`) que abre el
segundo nivel, con `gap:16px`: «Mi actividad» (16, `#475569`), «29 llamadas · 45 % contacto» (18, 500,
navy) y chip ámbar con punto «Atención».

**Cuerpo:** `display:flex; gap:24px; flex-grow:1; min-height:0`. Dos paneles hermanos.

**Panel «Ahora»** (ancho fijo 320, `flex-shrink:0`, blanco, borde, radio 16, padding 24, columna
`gap:16px`, `aria-label="Ahora"`), en orden:
1. «Ahora» (16, 600, navy).
2. h2 «Rosa Quispe Mamani» (20/28, 600), puede ocupar dos líneas.
3. «Primer contacto · Nuevo» (16, `#475569`).
4. Chip `#1d4ed8` sobre `#e5ecfd`, radio 999, padding `2px 12px`, `align-self:flex-start`: «Quedan 1 h 20 min».
5. Nota (16, `#475569`) recortada a 2 líneas con `-webkit-line-clamp:2`:
   «Le interesa el plazo a 12 meses y prefiere que la llamen por la tarde.»
6. `<div style="flex-grow: 1;"></div>` para pegar lo siguiente al pie.
7. Teléfono «987 654 321» (18, 500, navy, `font-variant-numeric: tabular-nums`).
8. Fila `gap:12px`: `<a href="#llamar">` que ocupa el resto (`min-height:48px`, fondo `#2563eb`,
   texto blanco 18/28 peso 500, radio 12, icono de teléfono SVG + «Llamar») y `<button>` 48×48
   blanco con borde `#d5ddec`, radio 12, «···» y
   `aria-label="Más acciones: WhatsApp, registrar resultado, ver ficha"`.
NO incluir: «1 de 16», «es la misma que verás en Hoy», «Landing», la hora de asignación, el rótulo «Celular».

**Panel «Cola de hoy»** (`flex-grow:1; min-width:0`, blanco, borde, radio 16, padding 24, columna
`gap:16px`, `aria-label="Cola de hoy"`):
1. Fila: h2 «Cola de hoy» (20/28, 600) y a la derecha «14 pendientes, de izquierda a derecha por
   urgencia» (16, `#475569`).
2. `role="tablist"` `aria-label="Grupos de la cola"`, `gap:8px`, `border-bottom:1px solid #e4e9f2`.
   Cuatro pestañas de 48 px, padding `0 16px`, fondo transparente, `border-bottom:3px solid`:
   activa navy 600 con filete `#111e3d`; inactivas `#475569` 400 con filete transparente.
   «Sin primer intento (6)» (activa) · «Vencidas (4)» · «Hoy (3)» · «Sin conversación (1)».
3. `<ol>` sin viñetas, columna, `gap:8px`, `flex-grow:1`. CINCO `<li>`, cada uno con
   `<button type="button" aria-pressed>` de ancho 100 %, `box-sizing:border-box`, alto 88, padding 16,
   radio 12, fondo blanco, `text-align:left`, fila con `justify-content:space-between` y `gap:16px`.
   Dentro, columna `gap:4px`: nombre (18/28, 500, navy, una línea con
   `white-space:nowrap; overflow:hidden; text-overflow:ellipsis`) y chip de tiempo (16/24, radio 999,
   padding `0 12px`, `white-space:nowrap`, `align-self:flex-start`).
   La PRIMERA va seleccionada: `aria-pressed="true"`, borde `2px solid #111e3d`, y a la derecha un SVG
   de check en círculo con `stroke="#111e3d"`. Las otras cuatro: `aria-pressed="false"`,
   borde `1px solid #e4e9f2`, sin icono. Contenido:
   - Rosa Quispe Mamani — chip azul «Quedan 1 h 20 min» (seleccionada)
   - Julio Cárdenas Soto — chip azul «Quedan 40 min»
   - Elena Vargas Ríos — chip azul «Quedan 15 min»
   - Diego Rojas Paredes — chip ROJO «Se pasó hace 45 min»
   - Carmen Díaz Romero — chip azul «Quedan 2 h 05 min»
   Las filas NO llevan etapa, ni nota, ni intentos, ni chip «Crítica», ni botones.
4. Pie: «1–5 de 6» (16, `#475569`) a la izquierda; a la derecha `gap:12px`, dos botones
   `min-height:48px`, padding `0 20px`, radio 12: «Anterior» inerte (`aria-disabled="true"`, texto
   `#475569`, borde `#e4e9f2`, `cursor:default`) y «Siguiente» activo (navy, borde `#d5ddec`).

## Archivo 2 — `OpcionD-actividad.dc.html`
`<title>`: «Mi día — Mi actividad». Padding 24, columna `gap:24px`.
- **Cabecera 64:** botón «Volver a mi día» (`min-height:48px`, blanco, borde `#d5ddec`, radio 12,
  16/24 peso 500) con flecha SVG, al lado h1 «Mi actividad de hoy» (24/32, 700); a la derecha botón
  «Actualizar» del mismo estilo.
- **Panel único** (`flex-grow:1; min-height:0`, blanco, borde, radio 16, padding 24, columna `gap:24px`):
  1. `role="tablist"` `aria-label="Secciones de mi actividad"`, mismas medidas de pestaña:
     «Resumen» (activa) · «Llamadas por hora» · «Seguimiento (6)» · «Descartados hoy (2)».
  2. Rejilla `repeat(6, minmax(0, 1fr))` `gap:24px`: seis tarjetas (borde `#e4e9f2`, radio 12,
     padding 24) con etiqueta (16, `#475569`) y valor (18/28, 500): Llamadas 29 · Contestadas 13 ·
     Llamadas útiles 29 · Tasa de contacto 45 % (valor `#92400e` + chip ámbar «Atención» con punto) ·
     Leads tocados 21 · Citas agendadas 3.
  3. Párrafo 16 `#475569`: «Bien desde 45 %, Atención desde 25 %. El nivel se juzga a partir de 5
     llamadas útiles. Primera llamada 09:12, última 13:50 (Lima).»
  4. Bloque que ocupa el resto, alineado abajo: «Llamadas por hora» (20/28, 600) y gráfico de 12
     columnas (08 a 19) con flex, `gap:16px`, alto 220. Cada columna: valor arriba (16, `#475569`),
     barra (`background:#475569; opacity:.55; border-radius:6px 6px 0 0`, ancho 100 %) y hora abajo
     (16, `#475569`). Valores: 08→2 (34px) · 09→5 (85px) · 10→8 (136px) · 11→9 (153px) · 12→4 (68px) ·
     13→1 (17px); de 14 a 19 sin llamadas: valor «–», barra 4 px con `opacity:.2`.

## Criterios que debe cumplir
- Regla de los 5 segundos: se entiende a quién llamar y con qué botón, sin leer nada pequeño.
- Ley de Hick: una sola acción primaria visible; el resto tras «···».
- Todo cabe en 1440×900 SIN scroll y SIN huecos grises: paneles y filas estiran con `flex-grow`.
- Contraste WCAG AA en todo texto.

Al final, máximo 6 líneas: decisiones donde la especificación dejaba margen, y riesgos.
