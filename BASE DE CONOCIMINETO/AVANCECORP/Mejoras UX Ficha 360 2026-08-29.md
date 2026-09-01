---
tipo: cierre-ux
estado: candidata-local-verificada
fecha: 2026-08-29
serial_continuidad: GC-ANALISTA-20260828-8DDF91B
---

# Mejoras UX Ficha 360 — candidata local 2026-08-29

Relacionado: [[Ficha 360 - candidata integrada 2026-08-29]],
[[Deploy Ficha 360 2026-08-29]],
[[Terminología comercial del CRM]] y
[[Cierre Mi cartera operativa 2026-08-25]].

## Estado

Se cerró una ronda de pulido UX sobre la Ficha 360 ya desplegada. Los cambios
quedaron implementados y verificados en la rama aislada de release; todavía no
se publicaron en producción.

## Decisiones cerradas

- Las acciones visibles de la cartera usan lenguaje de negocio:
  **Aumentar inversión**, **Registrar nueva inversión** y
  **Registrar primera inversión**. `Upgrade` permanece únicamente como nombre
  de la categoría contractual.
- La sección operativa se llama **Seguimiento**. El riel superior conserva
  **Siguiente contacto**, evitando repetir el mismo título inmediatamente.
- Las cuentas bancarias son información secundaria: inician plegadas y el
  resumen siempre muestra la cantidad en soles y dólares. Un error abre el
  bloque para que el reintento quede visible.
- Correo, número de cuenta y CCI se presentan sin partir el identificador y
  ofrecen una acción de copia de al menos 40 px.
- Las etiquetas y ayudas operativas de la ficha y del contrato usan un mínimo
  visual de 11 px.
- El detalle contractual resume antes de la tabla: cuotas vencidas, próxima
  cuota y saldo por pagar. El pie conserva avance y monto pagado sin repetir el
  saldo.
- La terminología visible continúa siendo **Analista**. Los identificadores
  técnicos heredados no se convirtieron en vocabulario de la interfaz.

## Verificación

- Pruebas focales: 131 aprobadas.
- Suite integral: 184 archivos y 2.490 pruebas aprobadas; lint, typecheck,
  cobertura, build, verificación del bundle y duplicación aprobados.
- Recorridos E2E afectados: 17 aprobados, 0 fallas.
- Revisión visual manual: escritorio 1440 × 1000 y móvil 390 × 844; ficha
  cerrada/expandida, cuentas y resumen contractual sin errores de consola.

## Próximo paso

Crear el artefacto de release, verificar su huella y publicar solo con una
autorización explícita de Miguel. Después del deploy deben repetirse el
readback del build y el smoke autenticado de Analista.
