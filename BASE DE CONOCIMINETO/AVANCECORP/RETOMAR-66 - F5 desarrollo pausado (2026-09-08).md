---
tags: [crm, cartera, F5, retomar]
fecha: 2026-09-08
estado: desarrollo-pausado-por-Miguel
---

# Retomar F5

Miguel pidió pausar el 08/09 a las 18:31 Lima y continuar aproximadamente una
hora después. No declarar F5 terminada. Retomar al recibir su indicación.

Objetivo vigente: desarrollar completa [[Plan de implementacion F5 - cartera y ficha multiempresa (2026-09-08)]],
con commits, aceptación G5 y preparación de publicación. Comisiones fuera del
sistema. F4 ya está publicada; producción mantiene F4/F5 apagadas y F3 encendida.

## Dónde está el avance

- Rama `codex/f5-cartera`, worktree `/private/tmp/avancecorp-f5-desarrollo`, base
  `fa33e375f7c2839ad322307743a9aa5c3e608d7a`. Los otros cambios de Main son ajenos.
- Contrato F5.1 guardado en `CRM-Avance-Corp/supabase/scripts/f5/CONTRATO.md`,
  commit `0d6aa4d`. CodeGraph se intentó primero; el worktree no tiene índice.
  No indexar automáticamente.
- Módulo SQL de desarrollo `supabase/scripts/f5/01-lecturas.sql`: lista y ficha
  canónicas, paginación/total del servidor, capacidades, banca y descriptores
  documentales separados, auditoría sin texto de búsqueda/contacto/documentos.
- Adaptadores, tipos neutrales y consultas React en `app/src/lib/inversionistas.ts`
  y `app/src/data/inversionistas-{api,queries}.ts`; componente
  `app/src/components/app/inversionista-ficha.tsx`, reutilizando la cabecera,
  secciones y banca publicadas. Compilan, pero todavía NO están conectados a Mi cartera.
- `Paginacion` admite conservar los controles visibles. Comportamiento anterior
  se mantiene por defecto.

## Banco y comprobaciones

Banco F5 exclusivo `/private/tmp/avancecorp-f5-bank`: API 58321, DB 58322,
contenedor `supabase_db_avancecorp-f5-bank`, red `avancecorp-f5-bank-red`.
Se restauró únicamente la copia sintética `f4_pub_compatible_3205f8811493`;
ninguna fila productiva. Auth y API reales funcionan. Credenciales y dumps quedan
privados en ese directorio; no copiarlos al repositorio ni imprimirlos.

- PASS: `node --test CRM-Avance-Corp/supabase/scripts/f5/lecturas.test.mjs`
  (12 pruebas, última ejecución 18:31). Cubre OFF, roles, búsqueda ajena,
  paridad histórica, filtros, Directorio, cooperativa sin Portal, cambio de
  responsable, baja del actor y auditoría/grants cerrados.
- PASS: `npm run typecheck` y `npm run lint` del frontend. Lint conserva cuatro
  advertencias anteriores de `coverflow-carousel.tsx`, ajeno a F5.
- Tipos: seis nodos introspectados con postgres-meta v0.99.0 en el banco F5,
  integrados sin reemplazar contratos TypeScript de otras tareas.
- Revisión Claude intentada mediante `scripts/claude-review`, pero terminó con
  «resultado incompleto o sin VERDICT válido». No acredita revisión aprobada.
  Queda una consulta útil para el cambio completo con evidencia y pruebas.
- NOT RUN: gate integral, pruebas UI/F5, accesibilidad, revisión visual,
  ampliación de matriz SQL/HTTP, F4 desde el formulario, build final, advisors
  y paquete de publicación. Las 12 pruebas no sustituyen G5.

El CLI reservó `20260908230249_crm_f5_cartera_ficha_multiempresa.sql`; está vacío,
sin versionar y NO se aplica. Ensamblar una candidata exacta tras completar G5,
registrarla en MIGRACIONES.md y preparar una reversa por flags, sin borrar datos.

## Decisiones y próximos pasos

1. Completar y probar las lecturas: cobertura incompleta, paginación con varias
   páginas, fusiones/multirrol, sin responsable, documento faltante, No contactar,
   baja de persona, PEN/USD, anulación comercial y fechas de imputación.
2. Revisar la semántica de capital activo frente al estado del perfil Avance,
   y no etiquetar como inversión adicional un antecedente sin clasificación.
3. Completar descarga de documentos: el PDF vive en `private.contrato_pdfs` y
   `private.contrato_pdf_jobs`, bucket `contratos-generados`; `public.documentos`
   es un antecedente distinto (vacío en producción al comprobar). La lectura PDF
   mantiene `private.puede_leer_contrato_pdf`; no ampliar permisos bancarios.
4. Conectar la lista neutral y la ficha con Mi cartera bajo la bandera F5,
   preservando filtros, estados honestos, foco y purga de caché al revocar acceso.
5. Implementar Nueva inversión: empresa → datos → preparación/revisión F4 →
   confirmación con revisión devuelta → recuperación Auth/PDF/comprobante.
   Reutilizar `ContratoNuevo`, cuenta, tasa y cronograma; no crear perfiles ficticios.
6. Probar aumento después de fusión: `private.inversion_persona_contexto` usa
   el perfil canónico, mientras el contrato origen puede conservar otro perfil
   histórico. Resolver correctamente sin cambiar el propietario legal ni aceptar
   un origen de otra persona. Todavía NO se investigó ni corrigió ese posible caso.
7. Completar G5, segunda revisión evaluada, commits, integración de Main y remoto
   sin pisar cambios concurrentes, artefacto/manifiesto y documentación.

Lectura productiva de referencia: 440 identidades, 540 contratos, 14 enlaces,
13 contratos sin identidad por perfil y 2 cierres sin identidad. La lectura F5
resuelve enlaces explícitos y perfiles históricos; su gate debe bloquear una
cobertura incompleta. Conciliación productiva queda antes de activar, mediante
lotes F4 revisables, sin backfill global ni encendido durante el desarrollo.

Directorio conserva el alcance vigente: Avance de solo lectura, sin filas
cooperativas ni banca/PDF. `cierres_externos_fn` no se modifica. Los demás roles
leen por responsable actual; el origen comercial no recupera acceso a PII.

Relacionado: [[Inicio]], [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]],
[[F4 cerrada - comisiones fuera del sistema (2026-09-08)]].
