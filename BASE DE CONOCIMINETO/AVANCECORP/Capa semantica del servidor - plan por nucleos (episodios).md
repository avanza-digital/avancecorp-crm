# Capa semántica del servidor — plan por núcleos (episodios)

Objetivo de Miguel: que **cada métrica tenga su propio núcleo**, con el sistema en capas — tablas crudas (capa 1) → núcleo de hechos **como función** (capa 2) → funciones por pantalla (capa 3) — y un **contrato/ventana** entre capas por donde pasa todo. Decisión tomada: la tabla de hechos es **función, no tabla física** (calcula fresco siempre; materializarla queda como optimización futura detrás de la ventana, invisible para las pantallas).

El molde ya existe y está en producción: `private.conversion_episodios` + su despachador autorizado (ver [[Auditoria conversion CRM - inventario y diseno de unificacion (2026-08-26)]]). Este plan replica ese molde para el resto de métricas. Inventario de consumidores: [[Auditoria servidor Supabase - duplicacion y deuda (2026-08-28)]] (D8). Las tandas T1–T3 del [[Plan de saneamiento del servidor (P-053) - implementacion por tandas]] van ANTES y son independientes; la T7 (gates por contagio) queda absorbida aquí: cada consumidor reescrito migra su gate a helpers en el mismo pase.

---

## Las tres reglas del contrato (valen para todos los núcleos)

1. **El núcleo no autoriza.** Recibe `p_visibles`/`p_global` y devuelve filas-hecho. `SECURITY DEFINER`, `search_path=''`, sin grants a la API (solo el dueño lo alcanza).
2. **La ventana autoriza UNA vez.** Un despachador por métrica (molde: `private.metricas_distribucion_leads_autorizada`) que resuelve el actor, valida rol con `private.rol_crm`/`es_lector_global`, calcula visibilidad con `private.vendedor_ids_visibles` y llama al núcleo. Nada llega al núcleo sin pasar por su ventana.
3. **La pantalla no calcula.** Los `crm.*_fn` de capa 3 suman/filtran/agrupan hechos y dan forma al payload de SU pantalla. Cero reglas de negocio: si una pantalla necesita una regla nueva, la regla se agrega al núcleo (una vez) y todas las pantallas la heredan.

---

## F0 — El contrato escrito + el trinquete (una sesión, sin tocar producción)

1. **Nota-registro «Contrato de la capa semántica»** en el vault: una ficha por métrica con la forma exacta de su fila-hecho (columnas, tipos, qué significa cada aporte), su ventana, y sus consumidores de capa 3. Se llena por fases: conversión ya se puede fichar hoy.
2. **Diseño de capital/leads/citas:** ⚠️ los diseños «P-050/051/052» **no están escritos en el vault** (solo existe el de conversión — verificado). F0 los produce con el método del de conversión: leer los 16/21/6 consumidores vivos, extraer la semántica real (qué cuenta, qué ventana temporal, qué excluye), y decidir la fila-hecho. Máximo 5 decisiones de negocio por métrica para Miguel, como siempre.
3. **Trinquete en la suite del CRM:** pruebas de guardia que consultan `pg_proc` y fallan si nace duplicación nueva — hoy 16 funciones suman capital (whitelist congelada: el número solo baja), 21 cuentan leads, 6 cuentan citas, 20 gates inline, 47 con `America/Lima`. El trinquete es lo que vuelve capa a las piezas: nadie puede escribir una métrica fuera de la ventana sin que la suite grite.

---

## F1 — Capital: primer núcleo nuevo (~3–4 sesiones)

1. **`private.capital_episodios(p_ini, p_fin, p_periodo, p_global, p_visibles)`** con el molde de conversión. Filas-hecho candidatas (se cierra en F0): tipo (`confirmado`, `renovado`, `adicional`, `ajuste`), cliente, vendedor, **moneda** (PEN/USD jamás sumados — regla vigente), monto, período comercial, fecha. Fuentes: `contratos` + `operaciones_cartera` + `ajustes_mes_cerrado` + `cierres_externos`.
2. **Ventana:** `private.capital_autorizada(...)`.
3. **Migrar los 16 consumidores en 3 tandas de paridad** (cada tanda = rama + release):
   - a) Pantallas de gerencia: `metricas_capital_mes_fn`, `metricas_cartera_fn`, `metricas_vendedores_fn`, `metricas_vencimientos_fn`.
   - b) Cartera/ficha: `resumen_cartera_clientes_fn`, `contratos_por_periodo_comercial_fn`, `metricas_cartera_por_vendedor`, `produccion_mes_por_vendedor`, implementaciones de conversiones/reuniones.
   - c) Portal: `dashboard_admin_metricas`, `directorio_ranking_analistas`, `directorio_top_clientes`.
4. **Las 2 escritoras van AL FINAL y después del 10/09:** `crm.cerrar_periodo` y `private.registrar_ajuste_si_mes_cerrado` sellan capital con su propia copia de la fórmula. Se migran a leer del núcleo (siguen escribiendo el ledger), pero **no antes del primer sellado real del 10/09** — no se cambia el motor del sellado la semana de su estreno.
5. Trinquete de capital se aprieta: whitelist 16 → 0 (solo el núcleo).

---

## F2 — Leads contados (~4–5 sesiones)

Mismo molde: `private.leads_episodios` + ventana + los 21 consumidores por tandas. Dos cuidados que la historia ya cobró: la definición de cohorte/roster (el hallazgo D8: «HOY» y los motores diferían porque parte estaba fuera de roster — la fila-hecho debe traer el criterio de pertenencia explícito) y la decisión vigente de Miguel de **UN solo contador visible**. Los contadores incidentales dentro de funciones de acción (`derivar_leads_equipo_fn`, etc.) no son métricas: se marcan en el registro como «operativos» y quedan fuera de la capa.

---

## F3 — Citas (~2 sesiones)

`private.citas_episodios` sobre `crm.tareas` (las citas son filas de tareas con columnas `*_reunion`; no existe tabla citas — el criterio de «qué cuenta como cita» queda escrito UNA vez). 6 consumidores.

---

## F4 — El resto entra al patrón y se cierran ventanas viejas

- Distribución ya tiene su ventana (`metricas_distribucion_leads_autorizada`): se ficha en el registro y, con el trinquete activo y tráfico cero re-verificado, se retiran v1 y luego v2 (protocolo REVOKE→observar→DROP, OK de Miguel).
- SLA, producción y cualquier métrica futura: nacen directamente como núcleo+ventana+pantalla — el trinquete no permite otra cosa.
- El criterio «producto seleccionable» (T4-F1 del saneamiento) se ficha también en el registro: es capa semántica no-métrica.

---

## Método común de CADA tanda de migración (no negociable)

1. **Rama de banco** con la receta de [[banco-branch-replay-manual]]; seed con la FORMA real de prod.
2. **Oráculo de paridad:** capturar el payload de cada función consumidora ANTES y DESPUÉS (md5 del jsonb agregado), **en la misma transacción** (lección: dos lecturas separadas pueden diferir porque prod se movió). Deben ser idénticos byte a byte.
3. **Mutantes:** alterar el núcleo (p. ej. quitar un filtro) debe romper la paridad de TODOS los consumidores migrados; si uno no se rompe, no está consumiendo el núcleo.
4. auditor-rls sobre la migración + **gate RLS 1175** en banco.
5. Release al byte con el checklist de siempre (llaves en el ZIP, worktree limpio con `.env`).
6. **Nada viejo se borra:** las funciones reemplazadas quedan vivas hasta su retiro programado (REVOKE primero). Regla de Miguel.

---

## Orden global

| Paso | Qué | Cuándo |
|---|---|---|
| 0 | Saneamiento T1 (rastro) + T2 (anti-NaN) | esta semana, antes del 10/09 |
| 1 | F0 contrato + diseños capital/leads/citas + trinquete | 1 sesión; las decisiones de negocio a Miguel por fases |
| 2 | F1 capital (tandas a→b→c) | tras F0; escritoras del sellado DESPUÉS del 10/09 |
| 3 | F2 leads | tras F1 |
| 4 | F3 citas | tras F2 (o en paralelo, es chica) |
| 5 | F4 cierre de ventanas viejas + retiros | al final, con OK de Miguel |
