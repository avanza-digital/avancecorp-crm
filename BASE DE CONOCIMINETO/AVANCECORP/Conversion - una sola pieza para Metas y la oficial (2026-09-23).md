---
tags: [crm, conversion, metas, ranking, capas, produccion]
fecha: 2026-09-23
estado: en produccion
---

# Conversión: una sola pieza para Metas y la oficial

**✅ EN PRODUCCIÓN desde el 23/09/2026.** Migración `20260923164903_crm_una_sola_pieza_de_conversion`,
aplicada por Miguel con `!`, commit `b9780a8d`.

## La decisión (Miguel, 23/09)

Metas **deja de calcular la conversión** y usa la de la oficial. No se fusionan los paquetes y no se
añade vigilancia: se quita la causa (dos textos que alguien tenía que mantener iguales para siempre)
en vez de vigilar el síntoma. Ver la memoria de trabajo «prevenir antes que vigilar».

## Cómo quedaron las capas (tabla → núcleo → puerta → pantalla)

| Capa | Qué hay |
|---|---|
| Tabla | Nada nuevo. |
| Núcleo | `private.conversion_neta_por_vendedor(mes, global, visibles)`: la cifra de cada persona (bruto, deuda de meses ya pagados, neto, porcentaje). `private.roster_conversion_mensual(...)`: quién sale nombrado en la oficial. |
| Puerta | La oficial (`crm.conversion_mensual_sin_cartera_fn`), la #8 (`crm.cumplimiento_metas_sin_cartera_fn`) y la lista «fuera del ranking» de la #7 (`crm.cumplimiento_metas_fn`) ya no calculan: autorizan, eligen su población y arman su paquete. |
| Pantalla | Sin cambios. Metas declara ahora `fuente: mensual`, y el front ya lo aceptaba. |

**Por qué no «Metas llama a la oficial»:** eso sería una puerta que le pide la cifra a otra puerta.
Además, la oficial solo nombra al roster **vivo**: a quien se va a mitad de mes lo suma sin nombre, y
Metas tiene que seguir mostrando su avance (regla de Miguel del 10/08). Y el gate de la oficial deja
fuera al coordinador, mientras que el de Metas no.

## Lo que se midió

- **Antes de decidir** (solo lectura): Metas y la oficial ya coincidían persona por persona. Eran 17/17 en septiembre y 16/16 en agosto: `conversion_real = conversion_pct`, `resueltos = divisor`, y también coincidían numerador, cierres y deuda.
- **La «fila 18» que asustaba al encargo** era el perfil vendedor de pruebas de Miguel, con un alta manual del 18/09. No era arrastre ni una decisión de población.
- **Ensayo en producción** (un solo `DO` con `raise`, nada escrito):
  - las 224 respuestas (28 personas × 2 meses × 4 puertas) salen idénticas por texto;
  - con agosto sellado, la pieza se niega a recalcularlo (22023) y Metas = oficial 16/16;
  - con 4 deudas plantadas, 17/17 iguales y las 28 identidades ven a las mismas personas;
  - el ciclo migración → reversa no deja ninguna diferencia.

## Efectos que hoy no se ven (no hay mes sellado ni deuda)

- Metas enseña la deuda de quien no tuvo actividad en el mes, igual que la oficial. Antes la perdía.
- «Fuera del ranking» publica, para cada persona, lo mismo que la oficial: **neto** a quien la oficial nombra y **bruto** a quien suma sin nombre (supervisores, bajas). Antes era bruto para todos: una cara del defecto C2 de la [[Auditoria de conversiones - capas backend a frontend (2026-09-21)]].

## Trampas para quien toque esto después

1. **La pieza rechaza un mes sellado** (22023): su cifra es la foto. Recalcularlo en vivo sería el C1.
2. **Nunca usar la pieza en el cierre de mes:** el sello descuenta la deuda al saldar, y la pieza la descontaría otra vez.
3. **Quien cambie la oficial pierde la reversa:** `supabase/scripts/conversion/reversa-una-sola-pieza.sql` fija los md5 que dejó esta migración y se niega a correr si cambiaron.
4. **Comprobar después de cualquier cambio de conversión:** `supabase/scripts/conversion/metas-vs-oficial.sql`, de solo lectura, tiene que dar PASS.
5. **Queda abierto:** ningún gate enumera a los llamadores de la pieza, igual que pasa con el núcleo `conversion_mensual_por_vendedor`.

Relacionado: [[Como se mide la conversion del asesor]] · [[Conversion - quien discrepa de verdad, medido con deuda plantada (2026-09-22)]] ·
[[Auditoria conversion CRM - inventario y diseno de unificacion (2026-08-26)]]
