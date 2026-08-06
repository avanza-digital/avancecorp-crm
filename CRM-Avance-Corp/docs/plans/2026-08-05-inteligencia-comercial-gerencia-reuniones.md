# Inteligencia comercial de Gerencia y reuniones auditables

Fecha: 2026-08-05

Estado: implementado y validado localmente; pendiente de orden explícita de
liberación.

## Objetivo

Entregar a Gerencia una superficie de inteligencia comercial completa, sin
convertir ese rol en un operador del CRM, y registrar el ciclo de reuniones con
datos suficientes para medir pactadas, realizadas, no-show, cancelaciones,
reprogramaciones y conversión real.

## Alcance implementado

- Dashboard Gerencia con periodo compartido.
- Lectura por cohorte y por producción del periodo.
- Embudo, conversiones, origen, categoría, contrato y capital real.
- Reuniones por modalidad, resultado, responsable, equipo y origen.
- Metas mensuales editables por Gerencia.
- Capacidad de analistas editable por Gerencia.
- Ocultamiento y bloqueo de superficies operativas no relevantes.
- Modalidad presencial/virtual, lugar/enlace, resultado y motivo estructurados.
- Reprogramación enlazada sin sobrescribir la cita original.
- Google Calendar e ICS con modalidad y destino.
- Compatibilidad explícita para historia anterior mediante `sin_clasificar`.

## Fronteras de seguridad

- Solo vendedor y supervisor pueden cerrar o reprogramar reuniones.
- Gerencia activa o lector global pueden ejecutar métricas globales.
- Las RPC de métricas no devuelven PII de leads.
- Gerencia no puede insertar, actualizar ni eliminar leads, tareas o actividades.
- Los helpers privados no son ejecutables por `anon`, `authenticated` ni
  `service_role`.
- El feed ICS solo es ejecutable por `service_role`.
- Todas las funciones `SECURITY DEFINER` nuevas fijan `search_path` vacío.
- Enlaces de reuniones virtuales requieren HTTPS y no admiten credenciales.
- Las filas cerradas y las originales reprogramadas son inmutables.

## Semántica de conversión

- Cliente es un hito intermedio.
- Contrato confirmado y capital real son la conversión final.
- Cohorte responde qué ocurrió con los leads que ingresaron en el periodo.
- Producción responde qué se cerró realmente dentro del periodo.
- La conversión posterior a una reunión se atribuye solo si cliente/contrato
  ocurren después de esa reunión.
- Se usa la última reunión realizada por lead para no duplicar capital.

## Semántica de reuniones

- `pendiente`: pactada y aún abierta.
- `completada`: realizada con resultado comercial obligatorio.
- `no_show`: el cliente no asistió.
- `cancelada`: no se realizará y conserva motivo/autor.
- `reprogramada`: fila original histórica; la nueva fecha vive en otra fila.
- `sin_clasificar`: únicamente historia o compatibilidad del bundle anterior.
- El porcentaje de realización excluye cancelaciones automáticas y originales
  reprogramadas.
- La asistencia compara realizadas contra realizadas más no-show.

## Archivos principales

- `supabase/migrations/20260805180000_crm_inteligencia_comercial_reuniones.sql`
- `supabase/scripts/test-inteligencia-comercial-reuniones.sql`
- `app/src/screens/hoy/gerencia.tsx`
- `app/src/screens/hoy/inteligencia-comercial.tsx`
- `app/src/screens/hoy/reuniones-gerencia.tsx`
- `app/src/lib/metricas-conversiones.ts`
- `app/src/lib/metricas-reuniones.ts`
- `app/src/lib/reunion-operativa.ts`
- `app/src/components/app/campos-reunion.tsx`

## Puerta de entrega

- Migración reproducible desde una base PostgreSQL 16 vacía con el oráculo
  autocontenido.
- Pruebas adversariales de roles, privilegios, inmutabilidad y contratos.
- TypeScript sin errores.
- Lint sin errores.
- Suite Vitest completa aprobada.
- Build de producción aprobado.
- Cero despliegues o escrituras de producción antes de la orden de liberación.

El procedimiento de release y rollback vive en
`docs/operacion-inteligencia-gerencial.md`.
