# Categorización de inversiones (Nuevo / Renovación / Upgrade)

> Fecha: 2026-06-12 · Estado: **Diseño aprobado por Miguel — pendiente de implementar**

> Actualización 2026-08-24: la operación quedó implementada y su definición
> vigente está en [[Gestión comercial de clientes - renovaciones y upgrades]].
> En particular, renovación nace desde un contrato vencido y el aumento de
> capital se separa como `capital_adicional`; no se deduce la categoría solo por
> comparar montos.

## Qué
Etiquetar cada **contrato de inversión** con una categoría: 🟢 **Nuevo**, 🔵 **Renovación** o 🟣 **Upgrade**, para poder segmentar la cartera y (más adelante) medir la captación por periodo.

## Significado de cada categoría
- **Nuevo** — el inversionista invierte con Avance Corp por primera vez (su primer contrato).
- **Renovación** — su contrato vence y decide reinvertir en vez de retirar (capital similar).
- **Upgrade** — vuelve a invertir aumentando el capital aportado.

## Decisiones de diseño
- **Dónde vive:** en el **contrato de inversión** (tabla `contratos`), no en el inversionista. Así se conserva el historial (Nuevo → Renovación → Upgrade) y se pueden sacar reportes por periodo.
- **Valores:** `nuevo`, `renovacion`, `upgrade`.
- **Asignación:** **MANUAL**. El asesor (o admin) elige la categoría al registrar/editar el contrato. **Obligatoria** al crear. Se eligió manual y no automática porque hay situaciones reales que no caben en una regla (reinversión con menos capital, cambio de modalidad, etc.).
- **Quién la pone:** el **asesor** (en los contratos de sus inversionistas) y el **admin**.
- **Dónde se ve:** badge de color en la **lista de inversionistas** (categoría del contrato más reciente); **historial** por contrato en la ficha; **filtro** por categoría.
- **Reportes por periodo** (conteo mensual de nuevos/renovaciones/upgrades): **fase 2 opcional**, no bloquea lo principal.

## Relacionado
- [[Bienvenido]]
- Modelo de negocio: Avance Corp es **inversiones**, no créditos. Inversionistas aportan capital y reciben rendimiento.
