---
tags: [crm, leads, analistas, cartera, asignaciones]
actualizado: 2026-09-13
estado: rama-aislada-verificada
---

# Leads recibidos por día para analistas — 2026-09-12

Relacionado con [[Nucleo de conversion - diagnostico de llegadas y asignaciones 2026-09-04]],
[[Reporte diario de derivaciones para Coordinación]] y [[Rol Analista]].

## Necesidad

Cada analista necesita escoger un rango y saber cuántos leads recibió en cada día,
además del total del período. El panel vive en **Leads / Mi cartera**, aparece solo
para el rol Analista y abre en **Hoy**. También ofrece Ayer, Últimos 7 días y un
rango manual.

## Regla acordada en la implementación

Este es un conteo **operativo de entradas a la cartera**, no la métrica empresarial
de captación. Por eso usa `crm.lead_asignaciones.asignado_en` en hora de Lima:

- un lead cuenta el día en que entró bajo responsabilidad de ese analista;
- una transferencia posterior no borra esa entrada histórica;
- si el mismo lead entra al analista en episodios distintos, cada entrada cuenta;
- una devolución inmediata `parqueado` a la misma bandeja no se considera carga;
- descartes y conversiones posteriores no cambian el día ya recibido.

La distinción es importante: en los reportes de Gerencia, «lead que llegó al
negocio» sigue siendo un lead único por `creado_en`, con la primera atribución.
Este panel responde otra pregunta: «¿cuánta carga recibió este analista por día?».

## Contrato y privacidad

La RPC candidata `crm.leads_recibidos_analista_fn(desde, hasta)` admite un rango
inclusivo de hasta 366 días, sin fechas futuras, y devuelve el total más una serie
diaria completa, incluidos los días en cero. Solo el vendedor autenticado y activo
puede leer sus propios números. No devuelve nombres, teléfonos, documentos, correos
ni identificadores de leads.

El selector modifica únicamente el contador histórico. La lista inferior continúa
siendo la cartera actual y mantiene su paginación y filtros habituales; la pantalla
lo explica para no hacer creer que está mostrando todos los leads históricos del
rango.

## Estado y verificación

- Frontend, contrato Valibot y RPC candidatos implementados localmente.
- TypeScript, lint y 19 pruebas específicas: PASS.
- Auditoría RLS: hallazgo sobre cierres `parqueado` sin bandeja corregido. Solo una
  devolución a una misma bandeja identificada deja de sumar.
- Migración y oráculo SQL determinista contra el banco local: PASS y `ROLLBACK`,
  sin persistir función ni datos. Cubre límites de fecha, día en cero, aislamiento
  de actores, vigencia de perfil/membresía y grants.
- Rama preview exclusiva `leads-recibidos-20260912-codex`
  (`dcbbakbrxpeaxbjuebgg`), no persistente y sin datos de producción: creada.
- El replay automático de la rama quedó en `MIGRATIONS_FAILED` por el problema
  histórico de migraciones antiguas con postflights que exigen datos. La rama se
  reconstruyó con los 275 cuerpos exactos de producción y terminó con paridad
  byte a byte en columnas, funciones, triggers, policies, RLS, índices,
  constraints, vistas y registro de migraciones. Los parches de orden usados
  para reconstruirla quedaron solo en el directorio temporal; no se incorporó
  código de otras sesiones.
- Migración `20260913173350_crm_leads_recibidos_analista.sql` aplicada de forma
  aislada sobre esa base equivalente a producción.
- Oráculo SQL remoto: PASS (`LEADS_RECIBIDOS_ANALISTA_TX_OK`) y `ROLLBACK`; los
  dos actores y las cinco filas sintéticas quedaron en cero tras la prueba.
- Data API con usuario Auth efímero: PASS. El analista autenticado recibió total
  1 y detalle diario 1; `anon` fue denegado; usuario y filas terminaron en cero.
- Advisors: sin hallazgos de rendimiento para la RPC. Seguridad informa que
  `authenticated` puede ejecutar una función `SECURITY DEFINER`; es el contrato
  intencional y la propia función vuelve a exigir perfil y membresía activos con
  `rol_crm = 'vendedor'`. `anon`, `service_role` y `public` siguen revocados.
- Tipos generados desde la rama: `Args { p_desde: string; p_hasta: string }` y
  `Returns: Json`, iguales al contrato local.
- La matriz RLS global conserva deuda previa y no queda verde: 33 de 1.830
  aserciones fallan. Se ejecutó un A/B completo en la misma rama y con el mismo
  seed: 33 fallos con la RPC y 33 sin ella, con los 33 nombres de fallo idénticos.
  Resultado de esta entrega: cero regresiones sobre la línea base; los fallos se
  concentran en contratos/ACL de métricas y funciones anteriores.
- Producción y publicación del frontend continúan pendientes hasta completar el
  commit, la integración de la rama y el gate de release desde un clon limpio.
