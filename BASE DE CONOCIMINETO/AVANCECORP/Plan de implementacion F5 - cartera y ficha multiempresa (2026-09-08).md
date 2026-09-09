---
tags: [crm, cartera, multiempresa, F5, implementacion]
fecha: 2026-09-08
estado: implementada-candidata-sin-publicacion
---

# F5 — cartera y ficha única del inversionista

Actualización 08/09: implementación y evidencia sintética guardadas en
[[RETOMAR-67 - F5 implementada y candidata preparada (2026-09-08)]].
No se activó producción; se mantienen los límites y las puertas de este plan.

Miguel pidió publicar F4 y recibir el plan de implementación de F5. Este documento
define el trabajo siguiente; no declara F5 implementada ni autoriza por sí mismo
el piloto económico. Sigue [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]]
y [[F4 cerrada - comisiones fuera del sistema (2026-09-08)]].

## Resultado visible

Buscar a una persona, abrir su ficha, ver sus inversiones en Avance, Qorilazo y
Prodelco y registrar una nueva inversión en cualquiera de ellas. Cada inversión
conserva empresa, moneda, documentos, fechas, estado y origen comercial. La
persona y su historial no se duplican. Las comisiones se calculan fuera del CRM.

## Punto de partida que se reutiliza

- `app/src/screens/mi-cartera.tsx`: cartera actual, paginación, filtros y diálogos.
  Hoy agrupa perfiles Avance y contratos; las cooperativas aparecen aparte.
- `app/src/components/app/cliente-ficha.tsx` y `cliente-detalle.tsx`: ficha publicada,
  capacidad bancaria confirmada por servidor y cierre ante pérdida de acceso.
- `app/src/lib/cliente-ficha-modelo.ts`, `cartera-vista.ts`, `clientes-tipos.ts`:
  modelos y agrupaciones actuales; ampliar con tipos neutrales explícitos.
- `app/src/data/crm-api.ts` y `crm-queries.ts`: validación de respuestas, consultas,
  invalidación y estados de carga. No añadir otro cliente Supabase ni otro store.
- F4: preparar, consultar, corregir y confirmar solicitudes; vínculo de fuente,
  recuperación de acceso Avance y PDF. La interfaz consumirá estas puertas.
- Fuentes económicas: Avance usa `public.contratos` y `public.cronograma_pagos`;
  Qorilazo/Prodelco usan `crm.cierres_externos`. `crm.inversiones` enlaza cada
  fuente con la identidad. F5.1 inventaría las RPC vigentes, documentos y permisos
  de cada empresa antes de definir la nueva lectura; una fuente ausente bloquea
  su entrega. La lectura existente `crm.cierres_externos_fn` conserva su alcance.

La pantalla `screens/cartera.tsx` es cartera de **leads**, una superficie distinta.
No sustituir su listado por el de inversionistas ni eliminar el pipeline.

## Secuencia y entregables

| Paso | Implementación | Criterio de cierre |
|---|---|---|
| F5.1 — Contrato de lectura | Definir respuesta paginada por `inversionista_id`, detalle neutral y capacidades por actor. Revisar datos reales solo en lectura; construir casos sintéticos. | Campos, paginación, filtros, permisos, errores y fuentes documentados antes del código. |
| F5.2 — Lecturas del servidor | RPC de lista y detalle autorizadas para identidad canónica, empresa, moneda y responsable vigente. Los nombres finales se fijan al inventariar las RPC existentes. | Una persona aparece una vez; total real del servidor; sin duplicación por contratos, perfiles o roles; matriz de acceso positiva y negativa aprobada. |
| F5.3 — Cartera unificada | Adaptar Mi cartera con búsqueda por nombre/documento/contacto, filtros de empresa y responsable, etiquetas de empresas y paginación visible. | Avance y cooperativas aparecen en una lista; escritorio y móvil conservan la consulta al volver de la ficha; carga parcial y error no muestran cifras inventadas. |
| F5.4 — Ficha única | Reutilizar la ficha actual con identidad, responsable, inversiones por empresa/moneda, vencimientos, documentos y antecedentes. Cotitulares informativos. | Funciona para una persona solo de cooperativa, para multirrol y para quien carece de Portal; banca solo en Avance y bajo capacidad vigente. |
| F5.5 — Nueva inversión | Selección de empresa, formulario, revisión y confirmación mediante F4; Avance reutiliza contrato/cuenta/PDF y cooperativas su depósito/evidencia. | Un reintento recupera la misma solicitud; la UI anuncia éxito tras confirmación; una revisión antigua o reasignación obliga a revisar antes de confirmar. |
| F5.6 — Pruebas y aceptación G5 | Recorridos por rol, permisos que cambian con ficha abierta, fallos de red, accesibilidad y revisión visual. | Matriz sintética aprobada y demostración visual para Miguel; cero diferencias de capital ni operaciones duplicadas. |
| F5.7 — Preparación de publicación | SQL exacto, tipos, artefacto reproducible, flags y reversa operativa; integrar Main y remoto. | Paquete revisable con evidencias y commits; el encendido comercial conserva G6/G7 y el despliegue progresivo de F9. |

Cada paso se guarda en un commit revisable. Separar contratos/lecturas, cartera,
ficha, formulario y aceptación. Codex implementa; Claude revisa el contrato de
lectura/permisos o el cambio sustancial cuando aporte una segunda opinión.

## Reglas de implementación

1. La clave de navegación es la identidad neutral. `perfil_id`, `lead_id` y
   `contrato_id` son enlaces opcionales o específicos; nunca fabricar perfiles
   para mostrar una cooperativa. Resolver fusiones hacia la identidad canónica.
2. El servidor pagina y autoriza antes de devolver filas. Aplicar el mismo filtro
   al total y a las páginas; no anunciar totales a partir de un array parcial.
   Conservar controles Anterior/Siguiente y tamaño de página, sin scroll infinito.
3. Capital sigue saliendo de sus fuentes contractuales/externas. `crm.inversiones`
   agrupa relaciones y no constituye otra fuente de dinero. PEN y USD separados;
   Avance y cooperativas separados; primera conversión y operaciones adicionales
   conservan sus reglas vigentes. Los reportes globales nuevos pertenecen a F7.
4. Separar responsable actual de atribución histórica. El vendedor anterior no
   retiene contacto ni documentos por haber originado la operación. Sin responsable,
   aplicar el ámbito explícito de supervisión/Gerencia; no inventar propietario.
5. Consultas sensibles requieren respuesta posterior a abrir la ficha. Ante
   revocación, borrar datos/caché sensible y cerrar o bloquear acciones. Las claves
   de caché incluyen actor, identidad y filtros; Directorio no consulta bancos.
6. Usar `preparar_inversion_fn`, `solicitud_inversion_fn`,
   `corregir_solicitud_inversion_fn` y `confirmar_inversion_revisada_fn`.
   Conservar UUID, contenido y revisión durante recuperación; no generar otra
   solicitud para disimular un fallo. Auth reservado conserva sus datos originales.
7. Corrección documental sigue siendo exclusiva de Administración en el servidor
   vigente. Cotitularidad no otorga acceso, crea leads ni genera cuentas Auth.
8. Mantener el PDF publicado, incluida su versión vigente y sus bytes históricos.
   Imprimir cotitulares exige revisar y aprobar texto/ubicación por separado.
9. Actividades y tareas se presentan desde sus fuentes existentes. Automatismos,
   reglas de vencimiento y nuevas acciones de postventa corresponden a F6.
10. El buscador aplica el mismo ámbito autorizado que el listado, incluidos
    resultados y total. Fuera de ese ámbito no revela existencia por documento,
    nombre o contacto. F5.1 define el registro de accesos sensibles con el
    mecanismo de auditoría vigente, sin copiar documentos/contactos a los logs.
11. Una confirmación corresponde a una inversión por transacción. No agrupar
    altas Avance: el origen de rentabilidad publicado es de un solo uso.
    Verificar especialmente aumento después de fusión, conservando el perfil
    contractual al resolver la identidad canónica.

## Matriz mínima de aceptación

- Avance → Qorilazo; Qorilazo → Avance; Qorilazo → Prodelco; segunda inversión
  en la misma cooperativa; Avance en PEN y USD; persona con las tres empresas.
- Vendedor, supervisor, Gerencia y Directorio, incluyendo equipo ajeno,
  traslado, baja, sin responsable, persona fusionada y multirrol.
- Documento provisional/faltante, No contactar, cotitulares propios/ajenos,
  inversión anulada comercialmente, fecha comercial e imputación distintas.
- Red interrumpida antes/después de confirmar, depósito repetido, revisión
  obsoleta, Auth pendiente y PDF pendiente/recuperado sin duplicar la inversión.
- Búsqueda por documento ajeno sin filtración de existencia; acceso sensible
  auditado sin datos personales en logs; aumento posterior a fusión con tasa
  heredada del contrato correcto y rechazo de un origen de otra persona.
- Escritorio y móvil, teclado, foco de retorno, lector de pantalla, estados
  vacío/cargando/error/reintento, y revocación de acceso con la ficha abierta.
- Comparación por empresa y moneda contra fuentes: ningún dinero sumado dos veces.

Verificación: lint, typecheck, pruebas unitarias de dominio/adaptadores,
integración SQL/HTTP y matriz RLS en banco aislado, build y bundle, Playwright
de los recorridos, revisión visual y evaluación del reviewer. Registrar los
checks no ejecutados como NOT RUN. G5 termina por evidencia, sin un porcentaje
artificial ni plazo de calendario inventado.

## Límites y siguiente fase

F5 se desarrolla y acepta con datos sintéticos. Las tres empresas iniciales
conservan sus documentos y permisos. Quedan fuera las comisiones, transferencias
legales de titularidad, mezclar monedas, un Portal común para cooperativas y
reescribir el historial. Tras G5 sigue F6 y después F7/G6, F8/G7 y F9/G8.

Relacionados: [[RETOMAR-64 - CARTERA F4 terminada y avance guardado (2026-09-08)]],
[[Acceso y roles del CRM]], [[Ficha comercial 360 de clientes - plan]].
