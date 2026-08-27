---
tags: [crm, ficha-360, checkpoint, continuidad]
actualizado: 2026-08-25
estado: pausado-listo-para-continuar
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

## Estado del plan de nueve pasos

1. Diseño y lenguaje comercial: completado.
2. Experiencia común con la ficha de Leads: completado.
3. Información comercial mínima y segura: completado.
4. Ficha lateral adaptable: completado.
5. Seguimiento desde la ficha: completado.
6. Renovación, aumento y nueva inversión: completado.
7. Permisos y protección frente a cambios simultáneos: completado.
8. Pruebas técnicas y visuales: casi completado; el paquete final de preview ya
   compila y falta repetir la última revisión visual y de conexión.
9. Preview y aceptación: preparación avanzada; falta publicar la URL aislada y
   recibir la revisión comercial de Miguel.

Avance estimado: **88 %**.

## Evidencia ya aprobada

- 2,344 pruebas automáticas aprobadas.
- TypeScript, compilación, control de calidad y tamaño del paquete aprobados.
- El paquete productivo excluye los clientes ficticios y el generador PDF demo.
- El paquete local de preview demo ya fue construido correctamente, con datos
  controlados, variables de Supabase vacías y protección `noindex`.
- La migración local se aplicó y reaplicó correctamente.
- El oráculo de permisos y transacciones terminó en
  `FICHA_CLIENTE_SCOPE_TX_OK` y deshizo todos sus datos de prueba.
- Producción no fue modificada.

## Qué falta al retomar

1. Retirar automáticamente del paquete demo el archivo `.htaccess` heredado,
   porque menciona destinos del servidor real aunque la demo no los use.
2. Añadir a la preview una política que permita conexiones únicamente consigo
   misma y repetir la búsqueda completa del paquete, incluidos archivos ocultos.
3. Repetir la revisión visual final en 320, 360, 390 y escritorio.
4. Confirmar que la preview no realiza solicitudes a Supabase y mantiene
   `noindex`.
5. Cerrar las auditorías finales de seguridad y documentación.
6. Actualizar el estado final del plan y del vault.
7. Finalizar el commit, subir la rama y publicar la URL de preview en Vercel.
8. Verificar la URL y entregar la explicación comercial.

## Último punto guardado

- Commit de continuidad: `9ffc3e4`.
- La configuración preliminar de Vercel quedó guardada, pero todavía debe
  completarse con la restricción de conexiones indicada arriba.
- La revisión local del recorrido Vendedor → Mi cartera → Ver ficha funcionó.
- Durante esa revisión la demo realizó solicitudes únicamente al servidor local
  y no abrió conexiones en tiempo real.
- La preview **no fue publicada** y producción permaneció intacta.
- Todos los servidores y revisiones auxiliares quedaron detenidos al pausar.

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
