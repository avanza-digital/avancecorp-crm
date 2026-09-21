# F4 · Etapa 2 — publicación verificada (21/09/2026)

Estado: **PUBLICADA Y VERIFICADA; cierre técnico de la etapa 2**.
Miguel revisó la vista local, expresó conformidad visual y después invocó
humanamente `$release-crm`. La autorización cubre el frontend de la etapa 2,
no nuevas migraciones, activación de cortes, TypeSafe ni las etapas 3–6.

URL: <https://crm.miavance.com>. Publicación comprobada el 21/09 a las
15:07 Lima (20:07 UTC). Sigue pendiente el recorrido humano autenticado de
negocio; no se confunde el cierre técnico con esa conformidad.

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
GitHub comprobó la candidata final: `preflight`, `app-check`, `e2e` y `verify`
**PASS**. Miguel (`miguejbs98`) aprobó e integró el
[PR #64](https://github.com/avanza-digital/avancecorp-crm/pull/64) a las 15:01 Lima.
El [CI del PR](https://github.com/avanza-digital/avancecorp-crm/actions/runs/35646964386)
confirmó 4.051 pruebas / 271 archivos y 232 E2E / 26 omitidos, sin fallos.

Fuente integrada y efectivamente publicada:
`baa63aeac71e5a074309aae92a064b67756189f1`. Su árbol completo
`17f3e5c3bf3a0a5ccc09451eb2d0df15ea2a548e` es idéntico al de la candidata
aprobada `d60eafb0`; el árbol de app citado arriba no cambió. Se reutiliza esa
evidencia exacta, no pruebas de otro frontend. También terminaron en **PASS**
los controles repetidos por el push de Main:
[calidad](https://github.com/avanza-digital/avancecorp-crm/actions/runs/35648465660)
y [preflight](https://github.com/avanza-digital/avancecorp-crm/actions/runs/35648465477).

Main local y `avancecorp/main` coincidieron en `baa63aea` antes de construir
y de subir. La copia de construcción estaba limpia y sin modo demo. Se
preservaron por hash los 61 archivos ajenos al índice del vault; `Inicio.md`
conserva tanto F4 como la nueva entrada de CI de otra tarea. El respaldo local
de esa entrada está en el stash `d70a7035` y ya fue restituida: no debe aplicarse
de nuevo. Los commits locales previos se conservan en la rama de implementación;
el squash de GitHub conserva exactamente su contenido.

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

## Artefacto publicado y comprobación

`npm run release:crm` y `npm run release:crm:verify` **PASS**, incluidos los
cuatro tests de configuración, TypeScript, build productivo y guard del bundle.
Solo configuración pública del proyecto esperado; demo desactivada, sin
credenciales privilegiadas ni archivos de entorno en el ZIP.

Artefacto: `crm-20260921T200509Z-baa63aeac71e.zip`, 2.268.153 bytes,
107 archivos. SHA-256:
`d513d1265123d7c38f800ccec9805a9611749df5830dbf5909c2d505b81c20e3`.
Build servido: `build-20260921T200508459Z`.

Publicación por `hosting_deployStaticWebsite` del servidor oficial Hostinger:
subida y despliegue aceptados, sin cambiar proveedor, dominio o configuración.
Preflight de ancestría y protección de Ficha 360 **PASS**.

Smoke HTTP final: **110 PASS / 0 FAIL**. Portada, `index.html`, JS principal,
los 68 recursos JS/CSS y los restantes archivos no transformados coinciden con
el manifiesto. Once imágenes se sirven con transformación CDN y tipo de imagen
válido; no se atribuye igualdad binaria a esas imágenes. `.htaccess` y el ZIP
no son accesibles públicamente en el CRM.

La primera sonda dio 109/110 porque el verificador no normalizaba el prefijo
`./` de la referencia al JS principal, aunque sus bytes ya coincidían. Se
corrigió únicamente el script local de verificación y se repitió la sonda
completa: 110/110. No se modificó ni se volvió a desplegar el producto por ello.
Se conservan ambos informes para no ocultar esa corrección del verificador.

ZIP, manifiesto, recibo saneado `.hostinger.json` e informes `.http.json` y
`.http-final.json` se conservan en `CRM-Avance-Corp/releases/`; scripts y
preflight en `releases/f4-detalle-analista-20260921/`. Se mantiene la fuente
del manifiesto aunque un commit documental posterior actualice Main.

## Recuperación y límites

Recuperación disponible: entrega anterior efectivamente publicada, Pipeline
`crm-20260921T175252Z-b0d2ff89e288`, SHA-256
`a6b8f33e21118759d2c77e471c13ea9d172ad6472bac2c4dfcd8dce740055d18`.
Su ZIP/manifiesto se verificaron antes de publicar; no se borraron ni usaron
para revertir, porque la comprobación final de esta entrega fue correcta.
No se autoriza revertir SQL como parte de la recuperación del frontend.

Siguen **NOT RUN** el recorrido humano autenticado en producción, VoiceOver
y la matriz general Auth/HTTP. La conformidad visual local de Miguel y los
fixtures E2E no sustituyen esas comprobaciones.

Siguiente implementación: **F4 etapa 3, cortes de la jornada**. Continúan
pendientes las decisiones de mínimo del sábado, analistas sin cartera y
límites del aplazamiento. No se activaron cortes, avisos nuevos ni TypeSafe.
