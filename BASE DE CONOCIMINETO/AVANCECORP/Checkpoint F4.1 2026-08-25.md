---
tags: [crm, ficha-360, checkpoint, continuidad]
actualizado: 2026-08-26
estado: preview-publicada-pendiente-aceptacion
serial: AVC-F41-360-20260825-R2
---

# Checkpoint F4.1 — 2026-08-25

Serial de continuación: **AVC-F41-360-20260825-R2**

## Resultado alcanzado

La ficha comercial 360 ya está construida y revisada en escritorio y móvil. El
vendedor puede consultar a sus clientes, comprender inversiones, historial y
próxima acción, y continuar con seguimiento, renovación, aumento o nueva
inversión usando lenguaje comercial.

También quedó protegida contra dos riesgos:

- vendedor y supervisor solo pueden operar dentro de la cartera que les
  corresponde actualmente;
- si otra persona cambia un contrato mientras está abierto, Corregir o Renovar
  se detienen antes de guardar, y piden volver a abrir la información vigente.

El cierre R2 agregó serialización de autoridad, separación entre lectura y
materialización PDF, reautorización final antes de firmar URLs y preparación
segura/adoptable del hard-delete. El detalle y los residuales están en
[[Cierre de seguridad Ficha 360 2026-08-26]].

## Estado del plan de nueve pasos

1. Diseño y lenguaje comercial: completado.
2. Experiencia común con la ficha de Leads: completado.
3. Información comercial mínima y segura: completado.
4. Ficha lateral adaptable: completado.
5. Seguimiento desde la ficha: completado.
6. Renovación, aumento y nueva inversión: completado.
7. Permisos y protección frente a cambios simultáneos: completado.
8. Pruebas técnicas, adversarias y paquete de preview: completado.
9. Preview publicada; aceptación comercial: pendiente.

Avance estimado: **98 %**.

## Evidencia ya aprobada

- 2,347 pruebas de aplicación aprobadas en 175 archivos.
- 27 pruebas Deno de Edge y renderer aprobadas.
- 43 carreras deterministas, una aserción same-TX y matrices de autoridad aprobadas en una base local
  desechable, eliminada con verificación de OID y marcador.
- TypeScript, compilación, control de calidad y tamaño del paquete aprobados.
- El paquete productivo excluye los clientes ficticios y el generador PDF demo.
- La migración preserva OID/owner/ACL de firmas públicas y privatiza los cuerpos
  canónicos clonados.
- El oráculo de permisos y transacciones terminó en
  `FICHA_CLIENTE_SECURITY_HARDENING_SQL_OK` y deshizo su base completa.
- El paquete de preview demo aislado se construyó y verificó sin credenciales de
  Supabase, con `noindex` y sin datos reales.
- La URL publicada responde `200`, declara `target: preview`, sirve el build
  `f41-preview-20260825` y conserva `connect-src 'self'`.
- El smoke test interactivo abrió Mi cartera y la ficha 360 como Vendedor; como
  Directorio confirmó solo lectura, sin cuentas ni acciones comerciales y sin
  errores de consola.
- Producción no fue modificada.

## Qué falta para la aceptación

1. Revisar con Miguel la comprensión visual y los recorridos comerciales usando
   los datos demo controlados.
2. Registrar la aceptación o los hallazgos de esa revisión.
3. Preparar una publicación controlada únicamente con autorización explícita;
   este cierre no autoriza cambios en producción.

## Punto técnico de continuación

- Rama: `feature/ficha-cliente-360-preview-20260825`
- Commit de implementación: `6702444`
- Preview:
  <https://avancecorp-crm-preview-295ehzulp-avancecorp26-1551s-projects.vercel.app>
- Deployment: `dpl_GNBm6cTeWrwWKrKo2UpiDqDjaJMV`, destino `preview`.
- Worktree:
  `/private/tmp/crm-ficha-cliente-360-preview-20260825/CRM-Avance-Corp`
- La preview se desplegó desde `app/dist` al proyecto aislado
  `avancecorp-crm-preview`. No usar `--prod`, `promote` ni conectarla al Supabase
  productivo durante la aceptación.
- Los servidores locales de prueba quedaron detenidos.

Relacionado: [[Ficha comercial 360 de clientes - plan]],
[[Cierre de seguridad Ficha 360 2026-08-26]] y
[[Gestión comercial de clientes - renovaciones y upgrades]].
