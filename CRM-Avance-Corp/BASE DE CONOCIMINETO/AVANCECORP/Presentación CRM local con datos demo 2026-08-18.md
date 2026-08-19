# Presentación CRM local con datos demo — 2026-08-18

Relacionado con [[Continuidad CRM 2026-08-06]], [[Centro de ayuda del vendedor]]
y [[Continuidad centro de ayuda 2026-08-18]].

## Objetivo

Existe un entorno local, de solo demostración y aislado de producción, para
presentar el CRM completo a vendedores. Usa los fixtures que ya viven bajo el
guard de desarrollo `VITE_ENABLE_DEMO=true` y permite cambiar entre Vendedor,
Supervisor, Gerencia, Directorio y Coordinador desde la pantalla de acceso.

## Arranque

Desde la raíz del repositorio, mantener estos dos procesos activos:

```bash
npm run demo:help
```

```bash
VITE_ENABLE_DEMO=true \
VITE_SUPABASE_URL=http://127.0.0.1:5173 \
VITE_SUPABASE_ANON_KEY=sb_publishable_crm_demo_local_2026 \
npm --prefix app run dev -- --host 127.0.0.1
```

Abrir `http://127.0.0.1:5173/`, pulsar **Explorar en modo demo** y elegir el
rol. El servidor se limita a loopback; no es un despliegue público ni un
servidor para otros dispositivos de la red.

## Centro de ayuda en la presentación

- `scripts/demo-help-server.mjs` sirve en `127.0.0.1:55431` solamente las dos
  RPC de lectura del Centro de ayuda.
- El servidor carga las 17 guías desde la migración versionada
  `20260818034822_crm_ayuda_vendedor_servidor.sql`; no duplica las respuestas
  dentro del bundle del navegador.
- Resuelve expresiones exactas aprobadas, las tres aclaraciones editoriales y
  devuelve `sin_resultado` para texto desconocido. El motor aproximado completo
  continúa siendo exclusivo de Supabase.
- Vite desvía `/rest/v1/rpc` al servidor local solo durante desarrollo. Las
  rutas de Auth responden 401 y nunca consultan producción.

## Evidencia

Se recorrieron visualmente Vendedor, Supervisor y Gerencia, además de Hoy,
Pipeline, Leads, Agenda, Mi cartera, Configuración, Nuevo lead y Centro de ayuda.
El manual cargó preguntas contextuales y mostró completa la guía **Quitar una
acción pendiente de tu agenda**.

- 21/21 pruebas focalizadas de fixtures demo aprobadas.
- `demo:help:test` validó 17 guías y los contratos `respuesta`, `aclaracion` y
  `sin_resultado`.
- Typecheck, build y verificador de bundle productivo aprobados.
- El verificador confirmó que el build productivo no contiene fixtures demo ni
  el renderer PDF de demostración.
