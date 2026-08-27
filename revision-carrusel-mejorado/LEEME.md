# Carrusel de beneficios PWA

## Vista principal

Abrir `beneficios-pwa-app.html` para probar la versión final directamente como
una PWA. Es un HTML autónomo, sin React ni el runtime DC, y usa los recursos
incluidos en `logos/`.

`Carrusel Beneficios Mejorado.dc.html` se conserva como presentación de diseño
con marco iOS; usa `support.js` e `ios-frame.jsx`.

La propuesta conserva:

- el marco iOS;
- los filtros por categoría;
- los siete aliados reales;
- el estado honesto «Convenio en negociación»;
- el detalle inferior y la consulta al asesor.

La variante refinada conserva el coverflow oscuro aprobado y añade:

- adaptación de pantalla completa para teléfonos y PWA;
- ajuste específico para anchos de 320 px y orientación horizontal;
- tarjeta vecina visible sin ensanchar en exceso la tarjeta activa;
- controles reunidos en una sola zona de pulgar, sin contadores duplicados;
- pausa mientras se arrastra y reanudación después de 1,4 s;
- navegación con flechas, Inicio y Fin desde el teclado;
- foco visible, soporte de movimiento reducido y safe area inferior;
- resumen honesto de aliados/categorías, sin inventar beneficios.
- tipografía nativa de aplicación: Avenir Next/SF Pro con fallback de sistema,
  sin dependencia de Google Fonts;
- CTA inferior y CTA de la ficha con tratamiento de WhatsApp y el texto
  «Consultar por WhatsApp».

La versión PWA fue comprobada en 320 × 568, 390 × 844, 430 × 932 y 844 × 390
px. No presenta desbordamiento horizontal, todos los logos cargan y los
controles principales tienen un área táctil mínima de 44 px.

## Componente React

La carpeta `react-component/` contiene:

- `components/ui/coverflow-carousel.tsx`;
- `components/ui/coverflow-carousel.demo.tsx`;
- `components.json`.

En el repositorio, la integración real está en
`CRM-Avance-Corp/app/src/components/ui/`. Esa aplicación ya incluye React,
TypeScript, Tailwind CSS 4, `lucide-react`, `clsx`, `tailwind-merge` y el
alias `@/* → src/*`; no requiere instalar dependencias adicionales.
