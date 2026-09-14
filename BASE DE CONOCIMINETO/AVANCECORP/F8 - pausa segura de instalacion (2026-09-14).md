---
tags: [crm, multiempresa, f8, pausa, retomar]
actualizado: 2026-09-14
---

# F8 — pausa segura de instalación

Miguel pidió «pon en pausa el trabajo en un momento seguro» el 14/09/2026.
**Trabajo pausado por el usuario. No reanudar automáticamente.** Continúa
[[F8 - instalacion autorizada en curso (2026-09-14)]].

## Estado comprobado al parar

- Producción: 279 migraciones, última `20260913213842`. Control F8, membresías
  y helper de exclusión demo **ausentes**. No hubo instalación ni merge de F8.
- F3 ON; F4/F5/F6/F7 OFF. Ningún participante configurado ni piloto encendido.
- Los diez enlaces reales anteriores siguen siendo trabajo completado; no repetir
  ese lote. No se copió información de clientes reales a la rama.
- La rama exclusiva `nyfufsyrtukwhbaezley`, ID
  `cf0f8eb1-1930-47f2-b81a-f8e8e46b54af`, fue **eliminada**. Se comprobó su
  ausencia. Termina su cómputo temporal; las ramas de Citas y banco-f7 se conservan.
- Claude terminó su revisión antes del cierre: `CHANGES_REQUESTED`. No es un
  PASS de instalación. No quedaron pruebas, restauraciones ni reviews corriendo.

## Avance guardado

El replay histórico se detuvo en 86 migraciones. Se obtuvo una copia privada de
estructura actual del padre y su historial exacto, sin filas de negocio. La
comparación de las 19 Edge y sus 55 archivos, JWT, entrada, import map y paquete
fue PASS para ese corte. No es una comprobación reutilizable tras la pausa.

La simulación inventarió 770 objetos externos. Tres ensayos de restauración
fallaron **dentro de transacciones revertidas**: permiso SET ROLE del propietario
de métricas, CREATE sobre crm para ese propietario y permisos por defecto de
supabase_admin. La rama conservó sus 86 migraciones tras las reversiones.

Se preparó una alternativa que conserva el schema public y sus permisos
administrados ya idénticos. El borrador `restaurar-rama-v2.sql` **NO se ejecutó**.
Debe corregirse/verificarse con evidencia antes de usarlo; no está aprobado como
procedimiento final por Claude ni por los checks. Los dos SQL de producto siguen
inmutables y ya autorizados por Miguel; no pedir de nuevo esa confirmación.

Evidencia saneada en
`CRM-Avance-Corp/supabase/scripts/multiempresa-f8/instalacion/pausa-2026-09-14/`:
dictamen y pedido de review, paridad Edge y estado del cierre. La revisión evalúa
el método propuesto, no el código del borrador completo. Algunas observaciones
son hipótesis o interpretaciones de su orden textual, no defectos reproducidos.

## Retomar cuando Miguel lo indique

1. Leer este punto y el dictamen; resolver cada observación con evidencia.
   No manipular directamente `pg_default_acl` por sugerencia del reviewer: usar
   DDL permitido y verificar los permisos efectivos. El borrador ya coloca las
   políticas Storage después de las funciones; la afirmación contraria del
   review procede del texto del pedido, no de una inspección del script.
2. Completar la comprobación de dependencias de la limpieza revisada, defaults
   propios antes de CREATE, atributos/permisos externos, membresías del bridge y
   correspondencia exacta del dump. No convertir omisiones en paridad aparente.
3. Crear una nueva rama exclusiva dentro del costo autorizado, leer de nuevo el
   padre y generar capturas actuales. No reutilizar accesos de la rama eliminada.
   No usar los dumps viejos si producción avanzó. `pg_net` difiere realmente:
   padre 0.20.0/public y rama anterior 0.20.4/extensions; la excepción queda abierta.
4. Completar reconstrucción equivalente, historial exacto, dos migraciones,
   pruebas SQL/Auth/RLS, advisors y revisión pertinente. La reversa va en copia
   separada; no ensayar reversa alterando el historial de la rama mergeable.
5. Integrar Main vigente sin pisar Citas, verificar Main local/remoto y construir
   desde ese commit; luego merge autorizado OFF y comprobación posterior.
   Equipo, encendido y casos reales G7 siguen fuera de esta instalación.

Worktree: `/private/tmp/avancecorp-f5-publicacion`, rama `codex/f8-piloto`, remoto
`avancecorp/codex/f8-piloto`. Aprobación ya respaldada en `fecf657`.
Temporales privados: `/private/tmp/avancecorp-f8-instalacion-20260913/`, 0700.
Contienen dumps, fixtures sintéticas, accesos ya caducados/eliminados y borradores;
no imprimirlos ni subirlos a Git. La conexión de la nueva rama deberá usar su
ref real y las guardas deberán cambiar explícitamente. El acceso nativo funciona
mediante el pooler de sesión en puerto 5432; el endpoint directo IPv6 no resolvió.

Plan: [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].
