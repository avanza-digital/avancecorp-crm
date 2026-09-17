# Mapa de capas del servidor CRM — 17/09/2026

**Artifact interactivo (privado):** https://claude.ai/artifact/7rSe49eefhyVyuXgKZpg81
**Página en disco:** `mapa-capas-crm.html` (es el mismo HTML publicado; ábrelo con `file://`).

Regla que mide el mapa (del `CLAUDE.md`, «Arquitectura en 4 capas»): toda información recorre
**Tablas → Núcleo → Puerta → Pantalla**. Una conexión que se salta una capa existe y funciona,
pero rompe la arquitectura.

## Qué hay en esta carpeta

| Archivo | Qué es |
|---|---|
| `listas.txt` | Las tres listas del método: CAPAS (nodos por capa), SANAS y SALTOS con ID, tal como salieron del script. |
| `datos.json` | Nodos, líneas sanas, saltos y META que consume la página. |
| `evidencia-mapa.json` | Nivel objeto: los 810 objetos con su capa y módulo, y las 3 474 conexiones reales con su evidencia (`via`) y clasificación. |
| `evidencia/*.json` + `evidencia/sql/*.sql` | Consultas al catálogo VIVO (proyecto `dctqcbznekcyxhjujuci`) ejecutadas con `supabase db query --linked --file` el 17/09/2026 17:11 UTC, y su resultado íntegro. Solo lectura; sin filas de clientes. |
| `front-graph.json` | Análisis estático del front: pantalla → símbolos → `rpc`/`from`/`invoke`, con archivo y línea. |
| `edge-refs.json` | Referencias SQL dentro de cada Edge Function (esquema resuelto por cadena o por `createClient`). |
| `pantallas.json` | Raíces de cada pantalla (archivo y componente). |
| `scripts/` | `analyze-front.mjs`, `analyze-edges.mjs`, `mapa-datos.py`, `plantilla.html`. |

## Cómo se clasificó (sin inventar nada)

- **Tablas (capa 1):** relaciones de `crm`, `private` y `public` (118).
- **Núcleo (capa 2):** funciones de `private`, todas las funciones trigger (aunque vivan en `crm`), las 15 piezas
  F7 `cerrada_permanente` («órgano interno, jamás se derriba»), `pg_cron` y la Edge `ciclo-contratos` (solo la llama el cron).
- **Puertas (capa 3):** funciones de `crm`/`public` no trigger (abiertas si tienen EXECUTE para `authenticated`/`anon`,
  cerradas si no), las 3 vistas y las Edge HTTP.
- **Pantallas (capa 4):** las 26 rutas del CRM (Gerencia fusiona Hoy + 5 vistas porque `screens/gerencia.tsx` son
  envoltorios de `HoyGerencia`), el armazón de la app, el portal (solo sus llamadas directas por grep), la hoja
  comercial y el calendario externo.
- **Conexiones:** cuerpos SQL del catálogo (tablas solo si aparecen tras `from/join/into/update/delete/truncate/lock`;
  funciones solo si van seguidas de `(`), triggers, definiciones de vistas, `cron.job`, `net.http_post`, fuentes de las
  Edge y análisis estático del front (pantalla → hook → API → `rpc`/`from`; el store se resolvió por
  `useCRMData#propiedad`; `lazy(() => import())` se sigue).
- **Severidad de un salto:** **A** pantalla o Edge con `service_role` o puerta autónoma (sin ningún núcleo) que toca
  datos del negocio; **M** puerta mixta (usa núcleo pero además lee/escribe tablas directo) o inversión (núcleo que
  depende de una puerta); **B** catálogos y configuración; **D** vistas con `security_invoker` y el reloj interno
  que dispara puertas cerradas. Estado `corr` solo cuando TODOS los consumidores están en observación F7.
- Los nodos de Tablas/Núcleo/Puertas agrupan por módulo (17 módulos por prefijo de nombre; `mapa-datos.py`,
  lista `MODULOS`). Cada línea conserva la lista de conexiones reales que la componen.

## Doble criterio

Las referencias se sacaron dos veces: criterio laxo (`esquema.nombre`) y estricto (patrón de lectura o llamada).
Diferencias: 33 menciones de tablas sin patrón de lectura (tipos `%rowtype`, `to_regclass`, strings) y 6 menciones
de funciones sin paréntesis (mensajes de error). Se usó el estricto. Detalle en `datos.json → META.comparacion_detalle`.

## Regenerar

```sh
cd CRM-Avance-Corp
for f in evidencia/sql/*.sql; do supabase db query --linked --file $f > evidencia/$(basename $f .sql).json; done
node scripts/analyze-front.mjs app/src front-graph.json          # requiere pantallas.json al lado de la salida
node scripts/analyze-edges.mjs edge-refs.json ../_supabase_functions/functions supabase/functions
python3 scripts/mapa-datos.py                                     # escribe datos.json, evidencia-mapa.json, datos-artifact.json
python3 - <<'EOF'
d=open('datos-artifact.json').read().replace('</','<\\/'); open('mapa-capas-crm.html','w').write(open('scripts/plantilla.html').read().replace('__DATOS__', d))
EOF
```
