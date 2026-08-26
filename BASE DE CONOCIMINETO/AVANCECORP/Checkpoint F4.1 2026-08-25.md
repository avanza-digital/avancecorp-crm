---
tags: [crm, ficha-360, checkpoint, continuidad]
actualizado: 2026-08-25
estado: pausado-listo-para-continuar
serial: AVC-F41-360-20260825-R1
---

# Checkpoint F4.1 — 2026-08-25

Serial de continuación: **AVC-F41-360-20260825-R1**

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

## Estado del plan de nueve pasos

1. Diseño y lenguaje comercial: completado.
2. Experiencia común con la ficha de Leads: completado.
3. Información comercial mínima y segura: completado.
4. Ficha lateral adaptable: completado.
5. Seguimiento desde la ficha: completado.
6. Renovación, aumento y nueva inversión: completado.
7. Permisos y protección frente a cambios simultáneos: completado.
8. Pruebas técnicas y visuales: casi completado; falta repetir la última revisión
   visual con el paquete final.
9. Preview y aceptación: pendiente.

Avance estimado: **85 %**.

## Evidencia ya aprobada

- 2,344 pruebas automáticas aprobadas.
- TypeScript, compilación, control de calidad y tamaño del paquete aprobados.
- El paquete productivo excluye los clientes ficticios y el generador PDF demo.
- La migración local se aplicó y reaplicó correctamente.
- El oráculo de permisos y transacciones terminó en
  `FICHA_CLIENTE_SCOPE_TX_OK` y deshizo todos sus datos de prueba.
- Producción no fue modificada.

## Qué falta al retomar

1. Construir la preview demo aislada, sin conexión a Supabase ni datos reales.
2. Repetir la revisión visual final en 320, 360, 390 y escritorio.
3. Confirmar que la preview no realiza solicitudes a Supabase y mantiene
   `noindex`.
4. Actualizar el estado final del plan y del vault.
5. Crear el commit, subir la rama y publicar la URL de preview en Vercel.
6. Verificar la URL y entregar la explicación comercial.

## Punto técnico de continuación

- Rama: `feature/ficha-cliente-360-preview-20260825`
- Worktree:
  `/private/tmp/crm-ficha-cliente-360-preview-20260825/CRM-Avance-Corp`
- La preview debe desplegarse desde `app/dist` al proyecto aislado
  `avancecorp-crm-preview`, con destino `preview`; nunca usar producción,
  `promote` ni conectar la preview al Supabase productivo.
- Los servidores locales de prueba quedaron detenidos.

Relacionado: [[Ficha comercial 360 de clientes - plan]] y
[[Gestión comercial de clientes - renovaciones y upgrades]].
