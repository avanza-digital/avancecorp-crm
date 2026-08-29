---
tipo: cierre-ux
estado: desplegada-verificada
fecha: 2026-08-29
serial_continuidad: GC-ANALISTA-20260828-8DDF91B
---

# Mejoras UX Ficha 360 — desplegada 2026-08-29

Relacionado: [[Ficha 360 - candidata integrada 2026-08-29]],
[[Deploy Ficha 360 2026-08-29]],
[[Terminología comercial del CRM]] y
[[Cierre Mi cartera operativa 2026-08-25]].

## Estado

Se cerró y desplegó una ronda de pulido UX sobre la Ficha 360. Los cambios
quedaron publicados en `crm.miavance.com` y verificados con readback íntegro
del artefacto más un smoke autenticado.

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

## Deploy y readback

- Commit publicado: `e8ac4262b75d17b07f588d7ed098e1fa82554b90`.
- Release: `crm-20260829T220216Z-e8ac4262b75d`.
- Build remoto: `build-20260829T220216363Z`, confirmado en tres lecturas
  consecutivas después del deploy.
- SHA-256 del ZIP:
  `62fef1480825f2a682387bf2c0d0b26b0dc04c66e8107e1bbede239708da4841`.
- Integridad remota: 62 archivos no gráficos idénticos byte a byte, 12 imágenes
  raster servidas correctamente tras optimización de la CDN y `.htaccess`
  protegido con HTTP 403. El ZIP de release devuelve HTTP 404 tanto en el
  subdominio CRM como en el dominio principal.
- Cabeceras verificadas: CSP, HSTS, `nosniff`, `DENY` y `no-store` continúan
  activas.
- Smoke autenticado: Cartera, acciones **Aumentar inversión** y
  **Registrar nueva inversión**, Ficha 360, cuentas plegables, detalle de
  contrato y resumen del cronograma operativos. La ficha no muestra
  **Vendedor** ni **Asesor**; el rol visible es **Analista**.
- No hubo cambios de backend, esquema ni migraciones en esta release.

## Rollback

Si fuera necesario revertir, volver a
`crm-20260829T195236Z-7cfc31bb8ea8` (`build-20260829T195235854Z`), cuya huella
SHA-256 es
`ba7516b1bb0b7d72e0dd117c7875deb2f881126ec021635e0eab13dfc2cbceb8`.

## Próximo paso

Monitorear el uso real de la Ficha 360 por los analistas y registrar cualquier
hallazgo funcional como una nueva incidencia, sin modificar esta evidencia de
release.
