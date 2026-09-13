---
tags: [crm, citas, gerencia, verificacion, release]
fecha: 2026-09-13
estado: preparado-sin-publicar
---

# Citas Gerencia — preparación verificada

Miguel reanudó la preparación después de [[Citas Gerencia - publicacion pausada 2026-09-12]].
Se verificó la reparación de [[Citas Gerencia - conexiones corregidas en local 2026-09-12]]
sin instalarla ni publicarla en producción.

## Resultado

- Frontend aislado del resto de borradores: 3.413 pruebas, TypeScript, lint y
  build PASS. Playwright: 173 PASS, 26 omitidas bajo sus condiciones existentes.
- Banco Supabase propio: esquema completo contrastado con el padre, 32
  comprobaciones HTTP con Auth real, 52 comparaciones de núcleos/contratos,
  límite 10.000/10.001 y cohorte de 2.500 leads/10.000 citas/100 cierres PASS.
- Dos migraciones verificadas y registradas **sólo en la rama**
  `citas-validacion-20260912` (`xhgsjtzpmwlqfkninphl`):
  `20260912151320` y `20260912181045`. Gate analítico: 34 declarados, 30 sujetos
  al techo, cuatro auxiliares con cuerpo/propietario/ACL verificados.
- Deriva y fallo antes del COMMIT revierten íntegramente; mutantes rechazados.
  Revisión independiente de implementación PASS.
- Matriz RLS general A/B: mismos 49 fallos entre 1.827 comprobaciones;
  **sin regresiones, pero no PASS global**. Hay configuración incompleta en la
  semilla y casos que requieren diagnóstico; no se consideran todos inocuos.
  Advisors sin nuevos avisos de esquema o rendimiento de las candidatas.

La semilla general carecía del singleton de control SLA. Se completó después
del A/B copiando configuración de negocio y sustituyendo el actor por uno
ficticio; el recorrido HTTP de Citas sí se ejecutó con ese control activo.
No se cambió código productivo para acomodar la prueba.

## Alcance conservado

Conversión a cliente sigue siendo el hecho requerido para el indicador de
depósitos por lead. Una cooperativa sin perfil cliente no infla esa conversión.
Las anulaciones quitan el cierre del indicador conservando el historial;
las citas futuras respecto al cierre no reciben atribución retroactiva.

No se activan todavía la meta 1,25, las tasas del 70%, la proyección ni el ticket.
Siguen los pendientes de [[Citas Gerencia - avance y proyeccion mensual por analista 2026-09-11]]
y [[Citas Gerencia - control de Superadmin en borrador 2026-09-11]].
El enlace de navegación del borrador había llegado a HEAD sin su ruta: el
artefacto de esta reparación lo excluye, preservando el borrador en el workspace.
También se fijó el reloj de un fixture de Rentabilidad que caducaba el 13/09.

## Entrega y límites

Evidencia detallada: `UX-UI-GERENCIA/citas-publicacion-2026-09-12/README.md`.
El manifiesto del artefacto debe identificar el commit idéntico en `main` y
`avancecorp/main`; no usar `origin/main` ni `tronco`.

La deuda global queda expuesta para la decisión de publicación. Instalar SQL
productivo, publicar web y verificar el despliegue real son **NOT RUN** en esta
preparación. La autorización de preparar/ensayar no se presenta como una
instalación productiva realizada.

Relacionado: [[Citas Gerencia - auditoria de conexion a nucleos 2026-09-11]].
