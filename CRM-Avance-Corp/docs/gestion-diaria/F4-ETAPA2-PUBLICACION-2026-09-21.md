# F4 · Etapa 2 — preparación de publicación (21/09/2026)

Estado: **publicación autorizada; todavía no desplegada**.
Miguel revisó la vista local, expresó conformidad visual y después invocó
humanamente `$release-crm`. La autorización cubre el frontend de la etapa 2,
no nuevas migraciones, activación de cortes, TypeSafe ni las etapas 3–6.

Implementación y revisión de Claude: [F4-DETALLE-ANALISTA.md](F4-DETALLE-ANALISTA.md).
Plan: [GESTION-DIARIA.md](GESTION-DIARIA.md).

## Fuente e integración

Trabajo en el taller preexistente `/private/tmp/avancecorp-gd-f4-vista.chvRqh`,
rama `codex/gestion-diaria-f4-detalle-analista`. Implementación `4226faeb`;
conformidad local `43822955`; integración de Main `1dd5b095`.

Main contenía los cierres ya confirmados `d4480b8c` (Pipeline publicado) y
`8bad4ede` (eliminación administrativa de contratos ya instalada). Se conservan
ambos sin ejecutar su SQL ni alterar su funcionamiento. El único conflicto
estaba en el índice del vault y se resolvió conservando las tres entradas.
Los cambios sin confirmar del taller principal no se incluyen ni se tocan.

El árbol de `CRM-Avance-Corp/app` es idéntico entre `43822955` y `1dd5b095`:
`8f7045f48eb963e196cf132e73e6e6cfc38e933b`. El frontend probado no cambió al
integrar. `npm run check` se repitió después de integrar: **PASS**. El banco de
la misma fuente comprende 4.051 pruebas y los E2E anteriores 232 PASS/26 omitidos.
GitHub deberá comprobar además la candidata final y exigir su revisión externa.

## Producción: comprobaciones previas de solo lectura

Destino exclusivo: Supabase `dctqcbznekcyxhjujuci`. Transacciones `READ ONLY`
con `ROLLBACK`; no se crearon ni modificaron leads, llamadas, tareas o permisos.

**PASS:** gates `assert_gestion_diaria` (F1–F4 y resultado vigente),
`assert_sla_nucleo`, `assert_sla_operacion`, `assert_sla_comandos` y
`assert_sla_avisos`. Huellas de F4, núcleo y `registrar_llamada_v4` coinciden con
las de la entrega anterior; el registro conserva su contrato INVOKER.

**PASS:** cinco identidades con claims SQL y `SET LOCAL ROLE authenticated`:
dos de gerencia ven 18 analistas; los tres supervisores ven 10, 0 y 8. La foto
coincide exactamente con el roster autorizado, incluidos analistas sin llamadas.
Los desgloses horarios satisfacen el mismo contrato que el frontend y el registro
solo devuelve actividades del analista pedido, del día de Lima y de leads visibles.

Con el límite real de 26, ningún analista necesitaba segunda página al corte.
Se repitió con límite 2 para ejercitar el cursor con datos reales: 15 analistas
por gerencia, 7 en un equipo y 8 en el otro generaron segunda página, sin
repetir la última fila entregada. El equipo vacío siguió vacío, no omitido.
Siete rechazos esperados `42501`: analista ajeno para cada supervisor, ambas
puertas sin identidad y ambas puertas como `anon`. Todo **PASS**.

Estas son pruebas de permisos SQL; **no son una matriz de JWT/Auth por HTTP**.
No se exportaron nombres, documentos, teléfonos ni IDs de las identidades.

## Realidad de datos y deuda previa

Al corte 19:35 UTC: 21 periodos de metas, 0 vendedores sin supervisor activo,
2.098 leads activos, 14.203 actividades, 1.215 tareas pendientes, 21 miembros
operativos (18 analistas/3 supervisores) y 0 revisiones bajo el sello. Son
consultas agregadas de lectura: no se infiere actividad individual ni presencia.

Se midieron los supuestos por SQL, sin obtener claves privilegiadas para el
script HTTP. `npm run gate:realidad` queda **NOT RUN** por esa configuración;
además su consulta histórica de domicilio apunta a `crm.perfiles`, que no existe.
El predicado sobre la fuente real `public.perfiles` devuelve 291 clientes activos
sin domicilio: deuda previa del alta de contratos, no requisito de esta pantalla.
No se anuncia un PASS global del script ni se incorpora la ampliación de ese
script que otra tarea mantiene sin confirmar. Las pruebas F4 cubren roster vacío,
cero actividad, caché incompleta, error y pérdida de autorización.

SQL y resultados saneados conservados fuera del código publicable en
`CRM-Avance-Corp/releases/f4-detalle-analista-20260921/` del taller aislado:
`preflight-solo-lectura.sql`, `preflight-paginacion-solo-lectura.sql` y
`preflight-produccion.json`.

## Puertas pendientes

Revisión externa y CI de GitHub; sincronización final Main/`avancecorp/main`;
construcción limpia y verificación de ZIP/manifiesto; publicación por el conector
oficial Hostinger y comprobación HTTP/hashes del código efectivamente servido.
No se ha ejecutado aún `hosting_deployStaticWebsite` para esta candidata.

Recuperación prevista: última entrega efectivamente publicada, Pipeline
`crm-20260921T175252Z-b0d2ff89e288`, SHA-256
`a6b8f33e21118759d2c77e471c13ea9d172ad6472bac2c4dfcd8dce740055d18`.
Antes de publicar se verificará otra vez el ZIP y su correspondencia con la web.
No se autoriza revertir SQL como parte de la recuperación del frontend.

Siguen **NOT RUN** el recorrido humano autenticado en producción, VoiceOver
y la matriz general Auth/HTTP. La conformidad visual local de Miguel y los
fixtures E2E no sustituyen esas comprobaciones.
