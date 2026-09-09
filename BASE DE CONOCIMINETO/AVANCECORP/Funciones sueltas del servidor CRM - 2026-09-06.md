# Funciones sueltas del servidor CRM — 2026-09-06

Complemento de [[Mapa del servidor CRM en Figma - 2026-09-06]], solicitado por Miguel para reconocer funciones sin conexión y entender su efecto comercial. Se consultó Supabase en solo lectura; no se retiró ni modificó ninguna función.

## Tablero

- [07 · Conexiones pendientes](https://www.figma.com/board/f5AcRzzIk3KS6CCOmKC0df?node-id=32-395): No contactar, período comercial, resumen de Agenda y ventana común de capital.
- [08 · Candidatas a retiro y falsas alarmas](https://www.figma.com/board/f5AcRzzIk3KS6CCOmKC0df?node-id=34-395): puertas anteriores, fases preparadas, usos técnicos y dependencia externa.

El tablero sigue en la carpeta **SERVIDOR CRM** del equipo de Avance Corp.

## Hallazgos duraderos

- No se localizaron acciones del CRM que llamen a `crm.marcar_no_contactar` y `crm.levantar_no_contactar`; el CRM sí lee la marca. Con identidad encendida, el trigger habilitado `trg_leads_000_no_contactar_puerta` rechaza su cambio directo fuera de la operación privilegiada. Es una conexión funcional por resolver, no una falla actual demostrada.
- `crm.contratos_por_periodo_comercial_fn`, `crm.corregir_fecha_cierre_comercial` y `crm.resumen_tareas_fn` permanecen sin consumidor de pantalla localizado.
- `private.capital_autorizada` no tiene consumidor localizado. El núcleo `private.capital_episodios` sí se utiliza directamente por adaptadores con controles propios. No se demostró un error de cifras ni permisos.
- Cinco grupos reúnen diez puertas para revisar antes de un posible retiro: dos `public.pagos_admin_*`, dos puertas antiguas de PDF, `crm.registrar_candidato_usuario_fn`, cuatro `crm.*contrato*producto` y `crm.existe_cliente_por_dni`. Las funciones homónimas del esquema public no se incluyeron por analogía.
- La revisión actual corrige una lectura histórica de [[Plan de saneamiento del servidor (P-053) - implementacion por tandas]]: `resumen_cartera_clientes_fn` **sí aparece en el CRM publicado** y no se clasificó como huérfana.
- No retirar por nombre las versiones de Distribución: v3 llama motores internos v2 y base. La puerta v1 conserva EXECUTE para `crm_metricas_bridge`; su consumidor externo sigue sin aclarar.
- Las herramientas manuales, los rescates de identidad y las solicitudes de tasa preparadas no equivalen a funciones muertas. La identidad continúa apagada y rentabilidad en observación.

## Método y límite

476 firmas SQL, cuerpos de 16 Edge Functions, nueve tareas programadas, dependencias de base de datos, código local, archivos publicados del CRM y dos archivos del Portal. El filtro estático inicial dejó 44 firmas sin camino desde las pantallas o automatismos localizados; la clasificación incluye auxiliares, herramientas manuales y fases preparadas. **No son 44 errores.**

`track_functions=none`: no se dispone de contador de invocaciones SQL. No se revisó el Apps Script instalado en Google ni clientes SQL externos; se leyó su copia local. No declarar una función segura para borrar sin aclarar esos consumidores y observar uso.

Evidencia detallada en `SERVIDOR-CRM/funciones-sueltas-y-conexiones-pendientes.md`, `evidencia-funciones-conexiones.json`, `clasificacion-funciones-sin-entrada.json` y `referencias-frontend-publicado.json`.

Relacionadas: [[Periodo comercial de contratos]] · [[Plan de escalabilidad del CRM a data gigante]] · [[Contrato de la capa semantica - Capital (F4, 2026-08-29)]] · [[Plan Rentabilidad server-side - tasa decidida por politica 2026-09-06]].
