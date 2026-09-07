# Filtro por fuente de conversión comercial — 2026-09-07

## Decisión

Gerencia puede consultar el índice comercial completo o aislar el aporte de una fuente: **Landing, Formulario, Upgrade, Referido o Renovación**. La selección se conserva al pasar por Resumen, Conversiones, Ranking, Metas y Rendimiento. Citas no usa este filtro porque responde otra pregunta.

La interfaz muestra **“Aporte de [fuente] al índice”** cuando hay una fuente elegida. No presenta ese aporte como una segunda conversión ni lo compara por separado con la meta total.

## Regla comercial conservada

- Landing y Formulario: cada cierre aporta ×1.
- Upgrade: cada operación aporta ×1.
- Referido y Renovación: cada resultado aporta ×0.15.
- El divisor sigue siendo la base automática de prospectos de Landing/Formulario.
- Altas manuales, referidos y operaciones de cartera no aumentan el divisor.

El frontend no redefine elegibilidad ni ponderaciones. Para Landing, Formulario y Referido usa los aportes ya servidos en `cierres_por_semana`; para Upgrade y Renovación agrupa los aportes ya servidos en `conversion_operaciones`. Si el núcleo y sus sondas no están verificados, la cifra se oculta.

## Presentación

El selector se llama **“Conversión de”** y ofrece **“Todas las fuentes”** como lectura inicial. El total conserva el nombre de índice comercial. Una fuente muestra su cantidad de cierres u operaciones, su aporte ponderado y la misma base automática. Los porcentajes canónicos se presentan con dos decimales.

En Upgrade y Renovación se ocultan gráficos exclusivos del recorrido de prospectos. Ranking, Metas y Rendimiento reutilizan la selección y la misma lectura ponderada.

## Alcance técnico

El cambio es de frontend y consume contratos existentes; no agrega funciones independientes ni modifica núcleos de negocio o RPC.

## Publicación

Publicado en `crm.miavance.com` el 07/09/2026 desde el commit `543a5af5ce7a29bc6da8d5541f0b4242584d85e5`, ya sincronizado con `avancecorp/main`. Release `crm-20260907T062744Z-543a5af5ce7a`, build `build-20260907T062744295Z`, ZIP SHA-256 `c34f7f3e1734cdb58f0dba3e6add13b7b98c01c8244db79bd9740934c81ebb48`.

El gate de publicación pasó lint, tipos, cobertura, configuración pública, bundle y duplicación: 202 archivos y 2.944 pruebas. El pre-push completo pasó 209 archivos y 3.011 pruebas. La verificación viva terminó con 0 fallos: 65 archivos exactos, 12 imágenes optimizadas con HTTP 200, `.htaccess` protegido, ZIP 404 en CRM y portal, y tres lecturas estables del build. El shell productivo cargó sin errores de consola en la sesión disponible de Supervisor; la interacción específica de Gerencia se verificó antes en el checkout local y mediante pruebas de pantalla.

El ZIP, manifiesto y detalle HTTP quedan conservados fuera del web root en `CRM-Avance-Corp/releases/` para trazabilidad y rollback.

## Relacionado

- [[Conversion comercial - una sola tasa visible 2026-09-06]]
- [[Gestión comercial de clientes - renovaciones y upgrades]]
- [[Canales de origen de leads CRM]]
