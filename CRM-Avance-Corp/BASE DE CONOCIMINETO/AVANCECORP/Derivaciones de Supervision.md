# Derivaciones de Supervisión

Relacionado con [[Historial de derivaciones de Coordinacion]], [[Reparto de Leads]]
y [[Centro de rescate de descartes 2026-08-20]].

## Propósito

**Derivar leads** es el módulo operativo exclusivo del Supervisor para comparar
la carga de sus asesores directos, preparar el reparto de los leads que están en
su bandeja y devolver una derivación de hoy mientras el asesor aún no haya
registrado gestión.

Las reglas de datos viven en las RPC `crm.reporte_derivaciones_equipo_fn`,
`crm.derivar_leads_equipo_fn` y `crm.revertir_derivacion_equipo_fn`. La interfaz
no sustituye sus validaciones ni modifica permisos.

## Decisión de experiencia — 2026-08-20

La asignación debe continuar siendo **lead por lead**. No se incorporan
checkboxes, selección masiva ni un destino común para varios leads. El
Supervisor conserva la decisión explícita sobre cada persona antes de guardar
el lote preparado.

La pantalla aplica cuatro mejoras basadas en principios Gestalt:

1. **Continuidad:** una ruta visible ordena la tarea en Comparar carga, Preparar
   reparto y Confirmar.
2. **Semejanza y conexión:** cada asesor recibe un color estable, usado en su
   tarjeta, el lead elegido y el resumen final. El color no representa
   rendimiento y siempre aparece acompañado por nombre y texto.
3. **Figura y fondo:** la bandeja se busca por nombre, origen, distrito o asesor,
   se pagina de 20 en 20 y conserva una barra de borrador fija con la acción de
   guardado. Las elecciones sobreviven al cambio de página o búsqueda.
4. **Cierre:** después de guardar aparece un comprobante inmediato agrupado por
   asesor. **Guardadas hoy** se organiza como carpetas desplegables por asesor y
   pagina cada carpeta de 5 en 5, evitando otra lista interminable.

La experiencia mantiene los estados degradados: si el reporte comparativo no
está disponible, los selectores y el guardado permanecen bloqueados. El
borrador no cambia ningún dueño hasta que la RPC confirma el lote.

Estado: implementado y validado localmente; pendiente de publicación.
