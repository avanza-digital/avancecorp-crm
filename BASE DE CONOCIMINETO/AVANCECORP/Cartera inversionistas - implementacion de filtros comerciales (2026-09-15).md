# Cartera inversionistas: filtros comerciales y distribución

Estado: implementado y verificado localmente; pendiente de publicación. Pedido de Miguel: «ahora vamos con los pendientes». Continúa [[Cartera inversionistas - filtros comerciales y distribucion pendiente (2026-09-15)]].

## Criterio comercial

- Mes de **cierre comercial**, conservando la decisión de la cartera anterior (`cartera-meses.ts`). Mes actual de Lima al abrir; opción Todos los meses y Sin fecha comercial. No confundir con registro, inicio, vencimiento ni imputación a un periodo sellado.
- Empresa, moneda, estado de inversión, responsable actual, contacto permitido y vencimientos próximos de 30 días. Buscar también número/referencia de inversión.
- Los clientes sin inversiones permanecen accesibles al consultar un mes sin otros filtros de inversión; opción explícita «Sin inversiones». Un cliente con inversiones fuera del mes no se convierte en un cliente sin inversiones.
- Los atributos de inversión se combinan sobre **la misma fuente**. Personas, opciones, importes y paginación salen de los núcleos F5; no filtrar páginas ni sumar capital en el navegador. Mantener empresas y monedas separadas.
- La ficha abre el historial completo, independientemente del mes del listado. Preservar [[F8 - ficha anterior recuperada para multiempresa (2026-09-15)]].

## Diseño, primera pasada

Paleta existente: navy #111e3d (texto principal), azul #2563eb (acciones/foco), blanco #ffffff (superficies), gris frío #f6f8fc (fondo), gris #64748b (texto secundario), borde #e4e9f2. Tipografía: heredar el sistema del CRM, sin nuevas fuentes; título 20 px, filas 14 px, rótulos 12 px y números tabulares.

```text
Antes: título / vencimientos / título repetido / filtros / resumen / lista
Ahora: título + acciones
       búsqueda | mes | empresa | más filtros
       resumen compacto de capital registrado por empresa y moneda
       cliente/documento | capital filtrado | cierre/responsable
       paginación                         [radar de vencimientos]
Móvil: filtros apilados y filas en dos niveles, sin desplazamiento horizontal.
```

## Segunda pasada: revisión contra el pedido

Evitar otra pantalla de tarjetas grandes. Reusar Input, Select, Button, Badge, Card y Paginación. Datos alineados a la izquierda y capital legible. El radar conserva su ámbito de empresa y sus 30 días, independiente del mes comercial. Filtros adicionales plegables, con número de filtros activos visible. No cambiar la ficha ni movimientos financieros, comisiones o sellos mensuales.

## Verificación realizada

SQL en copia local aislada: 17 grupos PASS (cruces mes/empresa/moneda, estados, sin inversiones, permisos de analista/supervisor/gerencia/directorio, paginación y coherencia de totales). Siete respuestas completas v1 idénticas tras instalar, revertir y reinstalar; propietario y permisos intactos. Seis peticiones HTTP a PostgREST real local PASS.

Frontend: 3632 tests/247 archivos PASS, cobertura de líneas 78,92 %, lint/typecheck/build/bundle/duplicación y preflights backend PASS. 26 recorridos E2E con API simulada PASS, móvil y escritorio, ficha y operaciones previas. Concurrencia limitada a cuatro workers tras timeouts de la primera corrida sin límite; no se modificaron los tests ajenos afectados. Advisors locales: cero errores/advertencias; 60 avisos INFO previos de RLS sin policy, acceso por RPC.

Claude emitió CHANGES_REQUESTED. Se corrigieron ayudas móviles, accesibilidad de filas, restauración al quitar «Por vencer», DTO explícito y un posible ciclo de reconsultas ante revocación persistente. «Sin inversiones» para Directorio se etiqueta «Sin inversiones Avance» y nunca consulta la existencia de COOPAC ocultas. Las hipótesis de cambio de owner/grants/sobrecargas quedaron descartadas mediante inventario de producción solo lectura. Dictamen y resolución en `supabase/scripts/cartera-filtros/evaluacion-claude.md`.

Evidencias, capturas, scripts reproducibles y reversa: `CRM-Avance-Corp/supabase/scripts/cartera-filtros/`. SQL candidato `20260916023055_crm_cartera_filtros_comerciales.sql`. Falta aprobar/publicar ese SQL siguiendo el ciclo de rama remota y después publicar el frontend desde `avancecorp/main`. No aplicar por arrastre otras migraciones. La apertura general F9 sigue activa; estos filtros nuevos todavía no están publicados. No se creó banco de pago ni se modificaron clientes reales.

Gate de realidad: CLI NOT RUN (sin variables de servicio; además contiene una consulta histórica a `crm.perfiles`). Equivalente SQL de lectura ejecutado: 614 fuentes reales, 11 meses comerciales, 0 fuentes sin fecha, 21 miembros comerciales activos, 1755 leads activos, 12015 actividades, 1094 tareas pendientes, 21 periodos de metas, 0 vendedores sin supervisor y 0 revisiones bajo sello. 296 clientes activos sin domicilio: probar listado/ficha con información incompleta sin exigir domicilio para leer.
