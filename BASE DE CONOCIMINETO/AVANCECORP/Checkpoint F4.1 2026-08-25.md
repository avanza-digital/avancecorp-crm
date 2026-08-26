---
tags: [crm, ficha-360, checkpoint, continuidad]
actualizado: 2026-08-26
estado: validado-listo-para-preview
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
9. Preview y aceptación: pendiente.

Avance estimado: **95 %**.

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
- Producción no fue modificada.

## Qué falta al retomar

1. Cerrar los veredictos independientes sobre la fuente estable.
2. Crear el commit y subir la rama.
3. Publicar únicamente la URL de preview en el proyecto Vercel aislado.
4. Verificar URL, ausencia de Supabase y `noindex`.
5. Registrar URL/commit y entregar la explicación comercial.

## Punto técnico de continuación

- Rama: `feature/ficha-cliente-360-preview-20260825`
- Worktree:
  `/private/tmp/crm-ficha-cliente-360-preview-20260825/CRM-Avance-Corp`
- La preview debe desplegarse desde `app/dist` al proyecto aislado
  `avancecorp-crm-preview`, con destino `preview`; nunca usar producción,
  `promote` ni conectar la preview al Supabase productivo.
- Los servidores locales de prueba quedaron detenidos.

Relacionado: [[Ficha comercial 360 de clientes - plan]],
[[Cierre de seguridad Ficha 360 2026-08-26]] y
[[Gestión comercial de clientes - renovaciones y upgrades]].
