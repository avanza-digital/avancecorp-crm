# F8 — verificación local del 13/09/2026

## Resultado

**PASS local. Producción sin cambios. Rama Supabase, advisors e instalación:
NOT RUN.**

La migración exacta se instaló repetidamente desde cero en PostgreSQL 17, base
sintética `multiempresa_f8_20260913`, reconstruida desde el banco F7 dentro del
contenedor cerrado `supabase_db_avancecorp-f5-bank`. El runner no acepta una URL
ni un destino suministrado externamente.

## Gates ejecutados

| Comando | Resultado |
|---|---|
| `npm run check:multiempresa:f8` | PASS |
| `npm run test:multiempresa:f8` | PASS: 11 pruebas |
| `npm run check:scripts` | PASS |
| `npm run seed:preflight` | PASS con valores locales ficticios; cero conexiones |
| `npm run test:rls:preflight` | PASS con valores locales ficticios; cero conexiones |
| `npm run test:edge-preflight` | PASS |
| `VITEST_MAX_WORKERS=2 npm run check` en `app` | PASS: 237 archivos, 3.424 pruebas, cobertura, build, bundle y duplicación |
| `git diff --check` | PASS |
| Parseo de `package.json` y enlaces Markdown F8 | PASS |

El lint conservó cuatro advertencias en `coverflow-carousel.tsx`, archivo fuera
del diff F8. El build conservó sus avisos de tamaño de chunk e import dinámico;
no hubo errores.

Los tipos se generaron desde la base local con la CLI Supabase 2.117.0 y se
integraron únicamente las dos tablas nuevas F8. TypeScript y el build completos
pasaron después.

## Cobertura específica

- instalación OFF, fila única, cero miembros y banderas globales intactas;
- RLS y ausencia de ACL Data API en tablas, columnas y funciones privadas;
- equipo incompleto, quinto miembro futuro, miembro fuera de ventana y perfil
  inactivo rechazados;
- cuatro actores nominales habilitados y supervisor ajeno excluido;
- pérdida de integridad del equipo suspende a todos; revocación nominal apaga;
- ventana máxima, extensión activa e aislamiento incorrecto rechazados;
- sincronización relacional de altas legadas sin conceder la operación F4 nueva;
- cobertura F5 rota bloquea también una llamada directa del servidor;
- INSERT/UPDATE de rollout global incompatibles con F8;
- cinco carreras concurrentes dejan exactamente un modo activo;
- vencimiento automático y reversa cortan capacidades;
- contratos, cierres externos, inversiones, inversionistas, titulares, meses
  sellados y Auth conservan las mismas huellas.

## Revisión independiente

Claude devolvió `CHANGES_REQUESTED`. Se corrigieron el quinto integrante futuro,
la extensión indefinida, la integridad del equipo, la separación entre espejo y
autorización F4, el gate de cobertura, INSERT/isolation y el postflight de
permisos/triggers. [Evaluación detallada](REVISION.md).

## Pendientes remotos y reales

- resolver 14 enlaces de cobertura actuales: diez reales y cuatro demo;
- elegir el equipo nominal;
- crear y pagar una rama Supabase autorizada;
- aplicar la candidata, regenerar/verificar tipos, ejecutar matriz RLS y advisors;
- integrar e instalar OFF por el ciclo de rama;
- configurar y autorizar el encendido;
- completar toda la evidencia real y firmas de G7.
