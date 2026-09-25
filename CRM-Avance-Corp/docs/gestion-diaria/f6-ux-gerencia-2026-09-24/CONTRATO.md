# F6 — UX/UI horizontal de gerencia

Entrega añadida por Miguel el 24/09. Candidato implementado y validado
localmente el 25/09; revisión GitHub y publicación pendientes. [Acta de resultados](ACTA.md).
Referencia: composición horizontal de supervisión, H1–H6 aprobadas, adaptada
al alcance gerencial de F5. La cola ya preparada y la observación conservan
su evidencia; no acreditan esta ampliación.

## Composición

Se conserva Plus Jakarta Sans y los tokens del CRM: fondo `#f6f8fc`, texto
`#16233f`, tarjeta `#ffffff`, primario `#111e3d`, acción `#2563eb` y borde
`#e4e9f2`. Texto operativo de 16 px, controles de al menos 44 px y foco visible.
La jerarquía procede del trabajo aprobado: cabecera compacta, indicadores,
tabla y detalle lateral; el panel pasa a diálogo cuando falta ancho útil.

En Pulso, la tabla inicial compara equipos. Elegir un equipo conserva la
jornada y muestra sus analistas como área principal; elegir una persona abre
su detalle lateral. El regreso mantiene filtros y selección del ámbito de
origen. El registro general sigue accesible desde la cabecera, con exportación.
Los ocho indicadores y sus comparaciones con ayer y referencia conservan sus
definiciones y valores del servidor. Los pendientes mantienen su fecha actual.

En Hábitos, una tabla permite comparar personas y elegir el informe detallado.
El detalle conserva contacto personal/equipo/operación, distribución, cortes,
primera llamada, huecos y sus horarios, y silencios de apertura/cierre. Siguen
disponibles las ventanas de 7/14/30 días y el acceso al registro del analista.

## Límites por rol y estado

Gerencia conserva toda la operación, equipos, autores fuera del organigrama,
registros sin autor y sus permisos de exportación. Los denominadores y las
tasas proceden de F5; filtrar la tabla no altera los totales de la operación.
Los controles propios del supervisor no amplían los permisos de gerencia.

Errores, revocación, carga, ausencia de personas y cero actividad deben seguir
siendo distinguibles. El cambio de cuenta limpia selección y datos. Abrir una
ficha o ampliar/cerrar un panel conserva la consulta del registro y su contexto.
La retirada de Seguimiento sigue condicionada a siete días reales estables.

## Verificación del alcance nuevo

- Comparación y recorrido completos con ratón y teclado; foco al abrir/cerrar.
- Fecha, filtros, selección y cursores conservados al volver de una ficha.
- Escritorio, panel ampliado, móvil y cambios de ancho sin desbordamiento.
- Hábitos de 7/14/30 días con toda la información y navegación al registro.
- Autores fuera de equipos, exportación, errores y revocación sin datos residuales.
- Gate frontend, Docker E2E y revisión independiente pertinentes al cambio.
- Evidencia visual, mismo Figma, plan y vault actualizados con resultados reales.

Este contrato mantiene los datos y capacidades de F5 y aplica la composición
aprobada, sin añadir gráficos decorativos, umbrales o métricas nuevas.
