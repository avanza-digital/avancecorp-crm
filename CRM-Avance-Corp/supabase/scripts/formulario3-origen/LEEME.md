# Formulario 3 como origen propio

Estado: **publicado y verificado en producción el 15/10/2026**.
[Acta de publicación](../../../docs/FORMULARIO3-ORIGEN-NATIVO-PUBLICADO.md) y `publicacion-verificacion.json`: A/B registradas, web `597cab1c`, Edge v26, 116 nativos y cero legados. La captura humana confirma una sola identificación de origen. No repetir la instalación.
La clave es `formulario_3` en `crm.leads.origen`. No hay otra tabla de leads ni
otra política de permisos. Comparte el turno operativo Formulario y sus pesos:
alta automática 1, alta manual 0 en el divisor y cierre 1 en el numerador.

## Orden de instalación

1. Validar las dos migraciones en una rama Supabase autorizada, con matriz RLS
   HTTP y advisors. El banco local no sustituye estos gates.
2. Aplicar `20261015171407_crm_formulario3_origen_compatibilidad.sql` (A).
3. Publicar frontend y Edge compatibles mediante la invocación humana de
   release. El artefacto debe proceder del commit verificado de `avancecorp/main`.
4. Confirmar que el equipo terminó sus borradores y recargó las pestañas del CRM.
5. Ejecutar el preflight actualizado y aplicar
   `20261015173031_crm_formulario3_origen_activacion.sql` (B).
6. Conciliar orígenes, responsables, conversión y recibos de n8n; comprobar
   visualmente Cartera, Repartir, Coordinación y Gerencia. Retirar la rama temporal.

A admite importaciones con la clave nueva pero las guarda temporalmente como
`formulario` + campaña `Formulario 3`. Las altas manuales F3 esperan B con un
mensaje explícito. Los rankings vacíos no añaden un origen desconocido para
pestañas antiguas. Entre A y B, Cartera/Cola proyectan la campaña legada como F3;
los desgloses del servidor siguen el origen almacenado. Mantener esa ventana breve.

B cambia únicamente los orígenes de leads legados y, para clientes convertidos
coherentes en un mes abierto, el origen de su acreditación. Mantiene analista,
bandeja, etapa, veto, historial, tareas, inversiones, contratos, fuentes, fechas,
motivos y relojes acreditados. No toca los recibos ni las huellas de n8n.

El caso convertido se incorporó tras comprobar en producción que uno de los
116 leads ya tenía una inversión mientras se preparaba el cambio. La función
comercial vigente reconoce fuente/fecha/origen idénticos y retorna el recibo
anterior. B actualiza primero el origen acreditado y después el del lead, bajo
candados y con igualdad íntegra de las demás columnas. No se recalcula una venta.

## Ensayos locales

Cierre de interfaz: `npm run check` PASS (429 archivos, 6.915 pruebas; lint,
tipos, cobertura, build y gates de bundle). E2E completo en Docker: **419 passed,
26 skipped, 1 flaky**, exit 0. La prueba de foco de Gestión diaria pasó al
reintentarse y en otras **3 repeticiones sin retries** (12 s); se conserva la
incidencia, no se afirma que la primera ejecución fuera totalmente limpia.
Las suites focalizadas anteriores aprobaron 34 casos de Repartir y 10 de
Cartera/Coordinación/Gerencia. El hook pre-push repitió las 6.915 unitarias: PASS.
Véase `verificacion.json` para alcance, huellas de logs y límites.

Requieren Docker `avancecorp-coordinacion-pg-actual` y una copia exclusiva
`origen_f3_*` con esquema vigente, sin datos de clientes. Nunca admiten una URL
remota. El preflight de A exige las huellas de las 22 funciones y los CHECKs
vigentes. Preparar también las declaraciones del censo analítico y la columna
`conversion_acreditaciones.ajuste_anulacion_en_sello` de la migración ya productiva
`20261012220959`; una copia antigua sin esos objetos no es una base válida.

Desde la raíz CRM:

```sh
python3 supabase/scripts/formulario3-origen/probar_local.py origen_f3_copia_pre_a
python3 supabase/scripts/formulario3-origen/probar_local.py origen_f3_copia_pre_a --solo-b
python3 supabase/scripts/formulario3-origen/probar_convertidos.py origen_f3_copia_pre_a
python3 supabase/scripts/formulario3-origen/probar_rechazos.py origen_f3_copia_pre_a
```

El primer comando ensaya A/B/ROLLBACK, prueba el restablecimiento de cuerpos,
ACL, propietarios y comentarios, persiste solo A y vuelve a ensayar B con
ROLLBACK. **No repetirlo sobre A ya instalada**: usar `--solo-b`. Los dos siguientes
ensayos también revierten sus fixtures. Ninguno ejecuta una reversa productiva.

Las carreras necesitan **dos copias distintas, vacías y con A**, porque dejan
fixtures y B instaladas exclusivamente en esos bancos desechables:

```sh
python3 supabase/scripts/formulario3-origen/probar_concurrencia.py origen_f3_importacion
python3 supabase/scripts/formulario3-origen/probar_bloqueos_financieros.py origen_f3_finanzas
```

Las fixtures de inversión pasan por las puertas reales de persona, preparación,
confirmación y reintento como usuarios autenticados. Solo el objeto de Storage
es metadato ficticio. La plantilla mínima carecía de las ACL de Storage; se
reproducen los permisos de `postgres` verificados en producción, dentro de la
transacción de prueba. Los ensayos reversibles comprueban restaurar esas ACL.

## Cobertura y límites

- A compatible con cliente anterior; importación legada y canónica.
- Filtros exactos, cola sin asignados/inactivos/vetados, dos turnos y desglose por
  origen; destinos fuera de turno y orígenes sin turno.
- Roles de Coordinación, revocación de miembros y ACL privadas.
- Reintentos de identidad en ambos sentidos, sobre lead y sobre cliente sin lead;
  una sola solicitud y sin tareas/notas adicionales.
- Altas manuales y automáticas; primera atribución conservada al reasignar.
- Cierres nativos y de un lead legado después de B; cierres ya acreditados antes
  de B y sincronización posterior sin cambios en motivo, reloj ni responsable.
- Conversión de Coordinación, filtro de Gerencia y ranking por origen.
- Foto histórica conservada literalmente; un desglose F3 inexistente es NULL.
- Rechazo íntegro ante mes sellado, fecha de fuente o identidad incoherentes.
- Dos sesiones: B espera una importación anterior, la incluye y no duplica; ante
  mes/acreditación ocupados aborta rápidamente y conserva al escritor financiero.
- Tipos oficiales: nueve contratos CRM cotejados con postgres-meta v0.99.0;
  `tipos-contratos.json` registra el alcance. El cambio de retorno es
  `leads_por_repartir.Returns.campania_origen`.

## Ensayo Supabase completado y retirado

Rama autorizada `formulario3-origen-nativo-20261015`, ref `yefiownpxvembwvfbtfx`,
creada con datos el 15/10/2026. La copia contenía 479 migraciones y 3.861 leads;
coincidían las huellas de las 22 funciones. Se desactivaron sus 12 cron antes de
preparar fixtures. A y B se aplicaron correctamente. Los 116 F3 copiados quedaron
nativos, incluido un convertido, sin legados residuales.

Se compararon huellas de los 3.861 leads y sus dependencias antes y después:
responsables, historial, tareas, episodios, acreditaciones, contratos, inversiones,
solicitudes y fotos selladas se conservaron. Solo se excluyen de la comparación
`origen` y el timestamp técnico del lead; en la acreditación, solo `origen`.
Los postflights de B también verifican invariantes y la conversión agregada.

`test-rls.mjs --formulario3-origen` ejecutó 49 comprobaciones A y 51 B con ocho
sesiones Auth reales; el importador desplegado **solo en la rama** pasó otras
5 antes y 6 después de B. Total: **111 comprobaciones PASS**, más 9 pasos de setup.
Incluye alta manual, permisos por rol, lectura cruzada, contratos anteriores,
filtros disjuntos, cola, reparto/derivación y reenvíos sin alterar fichas completas,
historia ni tareas. Edge exige JWT y secreto y rechaza campañas incompatibles.

El gate RLS general presupone una base exclusivamente `seed-demo`: **NOT RUN**
sobre esta copia, para no sustituir datos. Se ejecutó su matriz focalizada HTTP.
Cloud conservó el reparto libre copiado; el turno estricto está probado en Docker.
Advisors: **cero hallazgos nuevos** de seguridad o rendimiento. Persisten los
avisos previos; 27 índices dejaron de figurar como no usados por la actividad del
ensayo. Esto no acredita haber corregido toda la deuda del sistema.

La rama fue eliminada a las **20:40 UTC** y se borraron sus credenciales efímeras.
La rama vacía inicial se había retirado al detectar un replay antiguo de solo 86
migraciones; no se usó como evidencia del esquema vigente. Las dos ramas se
usaron consecutivamente para la misma validación autorizada, sin modificar producción.

Evidencia saneada: `cloud-verificacion.json` y `http-cloud-*.json`. Los scripts
cloud quedan cerrados a la rama ya retirada: para repetir, autorizar otra copia y
adaptar/verificar su referencia; no reutilizar credenciales ni apuntar a producción.
La conexión SQL del harness usa la API de administración: la contraseña postgres
devuelta por `branches get` no funcionó tras la restauración. No se cambió ninguna
contraseña. Las sesiones humanas y sus aserciones siguen usando Auth/PostgREST.

**Publicación completada:** preflight vigente, A, Edge/frontend, recarga del equipo confirmada y B, en ese orden. n8n sigue activo con su contrato y 152 recibos originales. La evidencia de ensayo anterior se conserva como fotografía previa a la publicación.
El censo analítico tenía deuda previa: esta migración re-sella sus propias
declaraciones y exige no añadir anomalías; no declara saneado todo el censo.

Ante un rechazo B, la transacción se revierte completa y n8n puede continuar
con el formato legado. Corregir la causa y volver a verificar antes de reintentar.
Después de B confirmada no se publica un cliente antiguo ni se ejecuta una
reversa genérica: ya pueden existir nuevas altas/cierres F3. Hace falta una
corrección compatible y revisada según el estado real.
