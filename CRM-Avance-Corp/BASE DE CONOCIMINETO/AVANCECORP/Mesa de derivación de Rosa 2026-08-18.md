# Mesa de derivación de Rosa — 2026-08-18

Relacionado con [[Configuración operativa CRM 2026-08-07]] y [[Presentación CRM local con datos demo 2026-08-18]].

## Decisión de negocio

Miguel aprobó enriquecer exclusivamente la experiencia del rol `coordinador` (Rosa) para que tenga más contexto al derivar leads.

El objetivo es que Rosa **vea mejor**, no medir su productividad ni construir reportes sobre sus propias derivaciones.

## Alcance aprobado

- Ficha de cada lead con capital, moneda, categoría de interés, origen, distrito, fecha/hora de ingreso, antigüedad en cola y comentario.
- Filtros adicionales por categoría, moneda, rango de capital (solo después de elegir moneda), distrito, antigüedad y presencia de comentario.
- Resumen de leads que ingresaron al CRM durante el mes seleccionado, desglosado por semanas calendario de Lima.
- El total mensual se define por `crm.leads.creado_en`: repartir o descartar un lead no borra que ingresó durante ese período.
- La lectura histórica es agregada y no expone teléfono, correo ni DNI.

## Fuera de alcance por decisión explícita

- Carga o capacidad de equipos/supervisores adicional a lo que ya existía.
- Rankings o destinos recomendados.
- Reportes de desempeño de Rosa.
- Seguimiento de si aceptó o rechazó sugerencias.
- Reparto masivo o automático.

## Implementación

- Pantalla: `app/src/screens/repartir.tsx`.
- Filtros puros: `app/src/lib/cola-reparto.ts`.
- RPC agregada: `crm.ingresos_reparto_mes_fn(date)`.
- La RPC conserva el gate vivo de Coordinación/Gerencia y devuelve solo totales semanales sin PII.

## Despliegue en producción

- Supabase `PortalAvanceCorp`: migración remota
  `20260818181756_crm_ingresos_reparto_mes` aplicada.
- Validación con identidad de Coordinación: agosto de 2026 devolvió 68 ingresos,
  distribuidos en 4 semanas cuya suma también fue 68.
- Validación negativa: un vendedor recibió `42501`.
- Frontend publicado en `crm.miavance.com` mediante el release
  `crm-20260818T181951Z-704d25e6f19a`.
- Caché de Hostinger purgada.
- `index.html`, el JavaScript principal, el CSS principal y el chunk
  `repartir-CYKn1Wqw.js` servido por producción coincidieron byte por byte con
  el paquete aprobado.
