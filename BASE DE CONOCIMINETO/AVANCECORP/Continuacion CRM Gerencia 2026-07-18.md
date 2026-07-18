# Continuación CRM Gerencia - 2026-07-18

## Estado guardado

- La pantalla de Gerencia usa una jerarquía visual más clara y textos más grandes.
- El resumen superior permite cambiar los montos entre **Soles** y **Dólares**.
- **Monto de leads activos** y **Monto ganado** cambian juntos de moneda.
- **Pagos a inversionistas** permite revisar Soles y Dólares por separado.
- La distribución incluye una **Vista rápida del equipo** con leads activos, recibidos, ganados, atención en 24 horas y alertas.
- La tabla completa por grupos de monto conserva encabezados visibles y desplazamiento controlado.
- El menú móvil se reduce a un riel de iconos para no comprimir el contenido.
- En modo demo, la distribución carga información ficticia automáticamente.
- En una sesión real vacía aparece **Ver ejemplo con datos**; el ejemplo no modifica información real.

## Cómo retomarlo

1. Entrar a `CRM-Avance-Corp/`.
2. Iniciar el CRM con `npm run dev` si no está ejecutándose.
3. Abrir `http://127.0.0.1:5173/`.
4. Para una demostración completa, usar **Explorar en modo demo -> Gerencia**.
5. En una sesión real sin distribución, pulsar **Ver ejemplo con datos**.

## Archivos principales

- `app/src/screens/hoy/gerencia.tsx`
- `app/src/screens/hoy/distribucion-leads-gerencia.tsx`
- `app/src/screens/hoy/graficas-gerencia.tsx`
- `app/src/lib/demo-metricas-distribucion.ts`
- `app/src/components/common/kpi-card.tsx`
- `app/src/components/app/sidebar.tsx`
- `app/src/App.tsx`
- `app/src/index.css`

## Precaución al continuar

El repositorio contiene otros cambios de agenda, clientes, configuración, migraciones y documentación. No hacer un commit general sin separar primero el alcance de Gerencia.

## Notas relacionadas

- [[Distribución de leads por capital y trazabilidad CRM]]
- [[Pasada de UX del CRM 2026-07-17]]
- [[Inicio]]
