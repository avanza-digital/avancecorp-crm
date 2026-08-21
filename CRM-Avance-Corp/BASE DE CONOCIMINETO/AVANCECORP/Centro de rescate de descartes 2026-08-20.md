# Base para gestión de descartes — 2026-08-20

Relacionado con [[Historial de derivaciones de Coordinacion]] y [[Navegacion compacta de Agenda y Pipeline 2026-08-20]].

## Propósito

Un supervisor necesita revisar los leads descartados por su equipo, incluso los
de meses anteriores, y decidir si conviene devolverlos a gestión. No es una
papelera: cada descarte es una evidencia de gestión que debe sobrevivir a una
reactivación posterior.

## Fuente de verdad y alcance

- El historial no duplica datos en otra tabla. Se lee de
  `crm.lead_asignaciones`, donde cada cierre con `resultado = 'descartado'`
  es un episodio inmutable.
- El mes se determina por `resultado_en` convertido a hora Lima; por eso un
  descarte no cambia de mes si más adelante se edita el lead.
- La pantalla solo entrega información operativa: nombre, distrito, origen,
  categoría, monto, motivo, asesor y fecha. Teléfono, correo, DNI y notas
  libres no salen de las RPC.
- Supervisor ve episodios de su equipo actual; Gerencia ve todos. Vendedor y
  Coordinación no reciben esta vista.

## Experiencia de uso

La vista **Base para gestión** usa componentes y jerarquía visual del CRM:

- La cinta muestra cuatro meses a la vez, retrocediendo por ventanas; el
  selector permite saltar al historial completo.
- Cada mes presenta conteo total y pendientes recuperables. El mosaico muestra
  siempre todas las carpetas de motivos que existan en el filtro, aunque haya
  cientos de leads: nunca contiene filas de leads ni se pagina por el orden
  global del mes.
- Al abrir una carpeta se entra a su vista de trabajo propia, con búsqueda por
  lead/asesor/distrito/origen, filtro de recuperables o historial y tabla
  paginada de 25 en 25. Así una carpeta con 300 leads conserva el panorama
  compacto y no convierte la pantalla principal en scroll infinito.
- La vista de trabajo trata la carpeta como una bandeja operativa: separa
  **para repartir**, **ya repartidos** y **solo historial**; permite ordenar
  por recencia, antigüedad, asesor u origen; y distingue seleccionar la página
  actual de seleccionar todo el resultado filtrado. No ordena por capital,
  porque los episodios pueden mezclar PEN y USD y no corresponde comparar
  montos sin un tipo de cambio explícito.
- Abrir una carpeta crea una pestaña real del navegador y conserva intacto el
  mosaico de la pestaña original. No se vuelve a renderizar la pantalla
  general: `#/rescate` es Base para gestión y `#/rescate-carpeta` es una
  página interna distinta, deliberadamente oculta del menú lateral. La URL de
  la segunda conserva `rescate_carpeta` y `rescate_mes`, por lo que una recarga
  vuelve a la misma carpeta y periodo; parámetros inválidos ofrecen volver al
  Base para gestión.
- Se puede marcar una fila o el bloque completo de un motivo. La acción abre
  un diálogo para enviar todo a un asesor o repartir equilibradamente entre
  varios.
- Por defecto se evita devolver un lead al asesor que lo descartó. Si no hay
  otro destino válido para alguno de los seleccionados, el servidor rechaza el
  lote entero antes de cambiar nada.

## Reactivación segura

`crm.rescatar_descartes` bloquea y valida todo el lote antes de actualizarlo:

1. confirma que todos los episodios siguen siendo descartes vigentes del
   ámbito del usuario;
2. rechaza casos marcados como **No insistir** y los que fueron descartados por
   datos inválidos;
3. valida que cada asesor destino siga activo y pertenezca al equipo;
4. pasa el lead a `nuevo` y lo distribuye en ronda.

Los triggers existentes cierran el episodio descartado y abren el nuevo ciclo
de asignación. Así, el historial conserva quién descartó, cuándo y por qué,
sin confundir ese hecho con la nueva gestión.

## Producción

- La migración `20260820181756_crm_base_gestion_descartes.sql` se aplicó el
  2026-08-20 y Supabase la registró como `20260821002017`. Su SHA-256 es
  `0e3dbad3ed575e1c03ac8fb6233dc8286ea1007eb5e5f474fb9a644857abf071`.
- El postflight ejecutó las lecturas con una sesión real autorizada y confirmó
  las tres RPC, sus dos índices parciales y las ACL: `public` y `anon` sin
  ejecución; `authenticated` con ejecución. Las RPC mantienen
  `security definer` y `search_path` vacío.
- El frontend publicado es
  `crm-20260821T004017Z-7233200dc115`, ZIP SHA-256
  `38f05b0816cd1168b254635143956410550814185c0d006a424274d951c87d7d`.
  `index.html`, el bundle principal y el chunk de Base para gestión se
  comprobaron en `crm.miavance.com` con HTTP 200 e igualdad byte a byte.
- El primer paquete `crm-20260821T002429Z-2ed459dbc42b` se construyó desde un
  worktree aislado sin el `.env` ignorado por Git. El login falló cerrado con
  «El acceso con cuenta aún no está disponible aquí»; no se afectaron cuentas
  ni datos. Se reemplazó por el release anterior, se comprobó Supabase Auth con
  HTTP 200 y un navegador real confirmó `Entrar` habilitado y el aviso ausente.
  `scripts/crear-artefacto-release.mjs` ahora rechaza antes de empaquetar tanto
  una configuración ausente como un bundle que no contenga los valores públicos
  de producción.
- Validación previa: `npm run check`, 2.104 pruebas unitarias y 104 pruebas E2E
  aprobadas; 26 E2E omitidas por diseño y cero fallos.
