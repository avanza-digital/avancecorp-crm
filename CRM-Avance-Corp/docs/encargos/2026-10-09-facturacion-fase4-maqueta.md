# Encargo (agente) — Facturación fase 4: maqueta de la hoja lateral «todo número se abre»

Maqueta visual: un HTML autónomo, solo pantalla y datos falsos, para que Miguel la apruebe viéndola a escala real ANTES
de programar la fase 4.
- **Único archivo a escribir:** `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/ui-playground/facturacion-lista-operaciones.html`.
  Esa carpeta ya está servida en http://127.0.0.1:8765/.
- **Base visual:** la maqueta APROBADA de la fase 1,
  `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/ui-playground/facturacion-hoja-excel.html` (también en
  `docs/encargos/maqueta/facturacion-hoja-excel.html`). Léela entera y reutiliza su lenguaje visual exacto.

## Qué debe mostrar

1. **La hoja de Facturación, en compacto:** 2–3 equipos como bandas, unos 8 analistas y unos 10 días.
   - Cada número es un `<button>` con un `aria-label` descriptivo: pastillas, celda analista×día, total de fila, de día,
     de equipo y la vista Día por tipo.
2. **La hoja lateral, desde la derecha y NO modal** (≈46 % del ancho a 1440 px):
   - un título en palabras, por ejemplo «Betzabeth Ramos · lunes 5 oct · todas las operaciones»;
   - cerrar con Esc, y el foco vuelve al número pulsado;
   - subtotales por moneda en pastillas pequeñas (S/ y US$ jamás sumados) y el número de operaciones;
   - la lista como hoja de Excel: N.º de fila, encabezado y primera columna fijos.
     - Columnas: Fecha · Tipo · Cliente · N.º de contrato / Cooperativa · Analista · Supervisor · Monto.
     - Las anuladas llevan «Anulada · cuenta igual».
   - las filas «Cliente de otro equipo»: apagadas, sin N.º ni cooperativa, con su importe y la línea explicativa «El
     cliente hoy lo atiende otro equipo: ves el importe, no sus datos»;
   - paginación de 25 / 50 / 100, con «Mostrando 1–25 de 87»;
   - un cero abre «Sin operaciones en este número»;
   - un promedio o un % abre su base, con una línea que explica la cuenta;
   - el aviso «Hay cifras nuevas · Actualizar», sin recarga automática.
3. **En celular (≤ 640 px):** un panel inferior a pantalla completa con tarjetas, una por operación.
4. **Un panel de revisión discreto** para cambiar de estado: normal · con «otro equipo» · cero · promedio · cifras nuevas
   · vista celular.

## Reglas de diseño de Miguel

- **Colores y letra:** navy `#111e3d` + azul `#2563eb`, tema claro, Plus Jakarta Sans, sin verde, y colores sólidos que
  se distingan.
- **Tamaños:** nombres de 16 px o más y detalle de 14 px o más.
- **Animación:** suave (panel de ~200 ms y hover que sigue al mouse), respetando `prefers-reduced-motion`.
- **Disposición:** horizontal, nunca vertical. Sin siglas.
- **Montos:** formato «S/ 25 000» y «US$ 1 000». PEN y USD nunca se suman.
- **Datos:** falsos pero realistas, y la suma de la lista igual al número pulsado.
- **Accesibilidad:** botones reales, foco visible, Tab/Enter/Esc, el panel como región etiquetada y `<table>` semántica
  con `scope`.

## Contrato que simula (servidor de la fase 3B)

```
{ version, pagina, tamano, total, totales: [{moneda, operaciones, monto}],
  filas: [ { n, fecha, tipo: contrato_nuevo|contrato_upgrade|contrato_renovacion|cooperativa, moneda, monto, anulado,
             analista_id, analista_nombre, supervisor_id, supervisor_nombre, visible, cliente_nombre,
             si visible: contrato_id, numero_contrato, cliente_id | cierre_externo_id, cooperativa, lead_id } ] }
```

Las filas con `visible: false` llevan `cliente_nombre` 'Cliente de otro equipo' y ningún id.

## Verificación

Capturas con Playwright a 1440×900 y a 390×844, sin errores en la consola. Comprobar también que Esc cierra el panel y
que el foco vuelve al número pulsado.
