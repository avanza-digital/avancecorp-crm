'use strict';

// Datos sintéticos para comparar dos composiciones. No hay peticiones al CRM.
const equipo = [
  { nombre: 'Camila Torres', iniciales: 'CT', capital: 420000, meta: 400000, operaciones: 8, conversion: 12.4, llamadas: 42, utiles: 40, contestadas: 22, citas: 4, realizadas: 3, pendientes: 1, noAsistio: 0, vencidas: 2, primeras: 0, oportunidades: 4, potencial: 180000 },
  { nombre: 'Bruno Salas', iniciales: 'BS', capital: 330000, meta: 350000, operaciones: 6, conversion: 10.8, llamadas: 38, utiles: 35, contestadas: 18, citas: 3, realizadas: 2, pendientes: 1, noAsistio: 0, vencidas: 3, primeras: 1, oportunidades: 4, potencial: 150000 },
  { nombre: 'Lucía Paredes', iniciales: 'LP', capital: 270000, meta: 350000, operaciones: 5, conversion: 8.3, llamadas: 36, utiles: 34, contestadas: 14, citas: 2, realizadas: 1, pendientes: 1, noAsistio: 0, vencidas: 2, primeras: 0, oportunidades: 3, potencial: 110000 },
  { nombre: 'Diego Ríos', iniciales: 'DR', capital: 210000, meta: 300000, operaciones: 4, conversion: 7.1, llamadas: 30, utiles: 28, contestadas: 12, citas: 2, realizadas: 1, pendientes: 0, noAsistio: 1, vencidas: 5, primeras: 2, oportunidades: 2, potencial: 80000 },
  { nombre: 'Valeria León', iniciales: 'VL', capital: 90000, meta: 300000, operaciones: 2, conversion: 4.6, llamadas: 24, utiles: 23, contestadas: 5, citas: 1, realizadas: 0, pendientes: 1, noAsistio: 0, vencidas: 8, primeras: 3, oportunidades: 2, potencial: 55000 },
  { nombre: 'Mateo Cruz', iniciales: 'MC', capital: 40000, meta: 300000, operaciones: 1, conversion: 2.1, llamadas: 10, utiles: 10, contestadas: 3, citas: 1, realizadas: 0, pendientes: 0, noAsistio: 1, vencidas: 4, primeras: 1, oportunidades: 1, potencial: 45000 },
];
const numero = n => new Intl.NumberFormat('fr-FR').format(n).replaceAll('\u202f', ' ');
const dinero = n => `S/ ${numero(n)}`;
const decimal = n => n.toLocaleString('es-PE', { maximumFractionDigits: 1 }).replace('.', ',');
const persona = p => `<button type="button" class="persona" data-persona="${equipo.indexOf(p)}"><span class="avatar">${p.iniciales}</span><span><b>${p.nombre}</b><small>Ver detalle →</small></span></button>`;
const avance = p => `<div class="mini-meta"><b>${decimal(p.capital / p.meta * 100)}%</b><span>${dinero(p.meta / 1000)} mil</span></div><div class="mini-barra"><i style="width:${Math.min(100, p.capital / p.meta * 100)}%"></i></div>`;
const filaMes = p => `<tr><td>${persona(p)}</td><td><strong>${dinero(p.capital)}</strong></td><td>${avance(p)}</td><td>${decimal(p.conversion)}%</td><td>${p.llamadas}</td><td><span class="indicador-vencidas">${p.vencidas}</span></td><td><button type="button" class="flecha" data-persona="${equipo.indexOf(p)}" aria-label="Ver detalle de ${p.nombre}">↗</button></td></tr>`;
function pintarA() {
  const orden = document.querySelector('#orden-a').value;
  const filas = [...equipo].sort((a, b) => orden === 'nombre' ? a.nombre.localeCompare(b.nombre, 'es') : orden === 'brecha' ? (b.meta - b.capital) - (a.meta - a.capital) : b.capital - a.capital);
  document.querySelector('#tabla-a').innerHTML = filas.map(filaMes).join('');
}
function pintarB(tipo) {
  document.querySelectorAll('[data-tabla]').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.tabla === tipo)));
  const mes = tipo === 'mes';
  document.querySelector('#subtabla-b').textContent = mes ? 'Capital, operaciones y conversión oficial de octubre' : 'Llamadas de hoy · Vencimientos acumulados al corte';
  document.querySelector('#cabecera-b').innerHTML = mes
    ? '<tr><th scope="col">Analista</th><th scope="col">Capital confirmado</th><th scope="col">Avance de meta</th><th scope="col">Operaciones</th><th scope="col">Conversión oficial</th><th scope="col">Brecha de capital</th></tr>'
    : '<tr><th scope="col">Analista</th><th scope="col">Llamadas hoy</th><th scope="col">Contacto hoy<br><small>contestadas / útiles</small></th><th scope="col">Citas de hoy<br><small>realizadas / previstas</small></th><th scope="col">Primeras gestiones<br><small>fuera de plazo · al corte</small></th><th scope="col">Tareas vencidas<br><small>al corte</small></th></tr>';
  const filas = mes ? equipo : [...equipo].sort((a, b) => b.vencidas - a.vencidas);
  document.querySelector('#tabla-b').innerHTML = filas.map(p => mes
    ? `<tr><td>${persona(p)}</td><td><strong>${dinero(p.capital)}</strong></td><td>${avance(p)}</td><td>${p.operaciones}</td><td>${decimal(p.conversion)}%</td><td>${p.capital >= p.meta ? '<span class="etiqueta azul">Meta alcanzada</span>' : dinero(p.meta - p.capital)}</td></tr>`
    : `<tr><td>${persona(p)}</td><td><strong>${p.llamadas}</strong></td><td><strong>${decimal(p.contestadas / p.utiles * 100)}%</strong> <span style="color:var(--muted)">· ${p.contestadas}/${p.utiles}</span></td><td>${p.realizadas} / ${p.citas}</td><td>${p.primeras}</td><td><span class="indicador-vencidas">${p.vencidas}</span></td></tr>`).join('');
}
function vista(id) {
  const b = id === 'b';
  document.querySelector('#vista-a').hidden = b;
  document.querySelector('#vista-b').hidden = !b;
  document.querySelectorAll('[data-vista]').forEach(btn => btn.setAttribute('aria-pressed', String(btn.dataset.vista === id)));
  document.querySelector('#titulo').textContent = b ? 'Dirección de la jornada' : 'Resultados del equipo';
  document.querySelector('#bajada').textContent = b ? 'Contacto, citas y oportunidades: dónde intervenir para impulsar el resultado.' : 'El resultado del mes, el aporte de cada analista y las decisiones de hoy.';
  history.replaceState(null, '', `#${id}`);
}
const lista = (filas, valor) => `<dl>${filas.map(p => `<dt>${p.nombre}</dt><dd>${valor(p)}</dd>`).join('')}</dl>`;
const detalles = {
  hoy: ['Capital confirmado · hoy', '<p>En el ejemplo: <b>S/ 85 000 en 2 operaciones</b>.</p><dl><dt>Camila Torres · 1 operación</dt><dd>S/ 50 000</dd><dt>Diego Ríos · 1 operación</dt><dd>S/ 35 000</dd></dl><p>Estas operaciones ya están incluidas en el capital del mes. La fecha es el cierre comercial del 16 de octubre; no se suman de nuevo al total mensual.</p>'],
  estados: ['Cuando falta información', '<p>Ejemplos de presentación; no alteran los totales ficticios de las propuestas.</p><dl><dt>Meta no publicada</dt><dd>Sin meta fijada</dd><dt>Tasa con pocas llamadas útiles</dt><dd>Muestra insuficiente</dd><dt>Falló la consulta de capital</dt><dd>No disponible · Reintentar</dd><dt>Conversión con cobertura parcial</dt><dd>Provisional</dd><dt>Cero llamadas confirmado</dt><dd>0 llamadas</dd></dl><p>Un analista sin meta conserva su producción visible; no recibe 0% ni posición en el ranking de cumplimiento. El mínimo de muestra y la calificación vienen del CRM.</p>'],
  capital: ['Capital confirmado · octubre', '<p><b>S/ 1 360 000</b> de una meta de <b>S/ 2 000 000</b>. Cumplimiento: 68%. Faltan S/ 640 000.</p><dl><dt>Nueva inversión</dt><dd>S/ 900 000</dd><dt>Adicionales</dt><dd>S/ 260 000</dd><dt>Renovaciones</dt><dd>S/ 180 000</dd><dt>Cooperativas</dt><dd>S/ 20 000</dd></dl><p>El total incluye renovaciones. No debe llamarse «dinero nuevo». En este ejemplo, la meta corresponde a las cuatro categorías; por eso es comparable con el total. La conexión real conservará el alcance de la meta publicada y su valoración oficial.</p><p class="detalle-callout">En el CRM conectado, esta cifra abriría las operaciones autorizadas del mismo mes, tipo y equipo en Facturación.</p>'],
  operaciones: ['26 operaciones confirmadas · octubre', lista(equipo, p => `${p.operaciones} operaciones`) + '<p>Hoy se confirmaron 2 de estas operaciones: S/ 50 000 de Camila y S/ 35 000 de Diego, ya incluidos en el mes.</p><p>Una persona puede tener más de una operación. Operaciones, clientes únicos y cierres que aportan a conversión son indicadores diferentes.</p>'],
  conversion: ['Conversión oficial · octubre', '<p><b>8,2%</b> en este ejemplo. Meta: 12%. Brecha: 3,8 puntos porcentuales.</p><p>La cifra del equipo viene del cálculo oficial del CRM. No se obtiene promediando las tasas individuales ni dividiendo las 26 operaciones por los leads abiertos.</p><p>Las ponderaciones, el origen, las reasignaciones, la cartera y los ajustes del cierre mensual deben conservarse. Estos porcentajes sintéticos sirven para mostrar la ubicación del dato.</p><p class="detalle-callout">El detalle del supervisor debe mostrar solo los aportes de su equipo que su permiso permita consultar. El detalle completo requiere validar su disponibilidad antes de integrarlo.</p>'],
  llamadas: ['Llamadas registradas · hoy', lista(equipo, p => `${p.llamadas} llamadas`) + '<p>Total: 180 llamadas. Se usa el registro comercial; no se cuentan llamadas personales. La actividad registrada no acredita presencia ni explica una ausencia.</p>'],
  contacto: ['Contacto en llamadas útiles · hoy', '<p><b>74 contestadas / 170 útiles = 43,5%</b>.</p><p>De 180 llamadas registradas, 10 quedan fuera de la tasa por su clasificación. Se conserva la definición vigente del CRM: no cuentan número errado ni otra persona.</p>' + lista(equipo, p => `${p.contestadas}/${p.utiles} · ${decimal(p.contestadas / p.utiles * 100)}%`) + '<p>Es una tasa sobre llamadas, no sobre personas únicas. Una muestra insuficiente se rotulará «Muestra insuficiente», sin calificar al analista.</p>'],
  citas: ['Citas previstas para hoy', lista(equipo, p => `${p.realizadas} realizadas · ${p.pendientes} pendientes · ${p.noAsistio} no asistió`) + '<p>Total: 13 previstas = 7 realizadas + 4 pendientes + 2 no asistieron + 0 anuladas en este ejemplo. Los estados se conocen de forma explícita; no se deducen restando realizadas a previstas. «Citas creadas hoy» será un dato separado: pueden estar agendadas para otro día.</p><p class="detalle-callout">Antes de conectar esta tarjeta hay que confirmar un agregado de resultados por fecha prevista. El resumen de Gestión Diaria no entrega por sí solo este desglose completo.</p>'],
  vencidas: ['Tareas vencidas · al corte', lista([...equipo].sort((a,b) => b.vencidas-a.vencidas), p => `${p.vencidas} tareas`) + '<p>Total: 24 tareas. Son pendientes acumulados, no necesariamente nacidos hoy. En la integración, se abre el listado autorizado de tareas, con responsable y vencimiento.</p>'],
  primeras: ['Primera gestión fuera de plazo', lista(equipo.filter(p => p.primeras), p => `${p.primeras} pendientes`) + '<p>Total: 7. El vencimiento lo decide el control vigente del CRM. Esta señal no equivale a todos los leads sin contactar.</p>'],
  oportunidades: ['Entrevistas realizadas · abiertas al corte', lista(equipo, p => `${p.oportunidades} · ${dinero(p.potencial)}`) + '<p>Total: 16 oportunidades, S/ 620 000 de potencial declarado, 16 con monto. Se abriría la lista con responsable, última gestión y próxima acción.</p><p>No es un pronóstico de venta ni tiene probabilidad asignada. Antes de implementarlo, confirmar que el agregado y el listado usan exactamente la misma etapa comercial y el equipo autorizado.</p>'],
  brecha: ['Dónde se concentra la brecha', lista(equipo.slice(4), p => `${dinero(p.meta - p.capital)} por completar`) + '<p>Valeria y Mateo suman S/ 470 000 de brecha individual y S/ 130 000 confirmados. En este ejemplo las metas individuales suman la del equipo. La brecha neta del equipo es S/ 640 000; incluye la compensación de Camila, que supera su meta en S/ 20 000.</p><p>No se declara incumplimiento antes del cierre. Es una señal para revisar cartera, apoyo y próximos pasos. El ritmo esperado requiere un calendario y criterio comercial acordados.</p>'],
  criterios: ['Las cifras deben contar la misma historia', '<ul><li><b>Mes:</b> capital confirmado, meta, operaciones y conversión oficial de octubre.</li><li><b>Hoy:</b> llamadas y contacto del 16 de octubre, hora de Lima.</li><li><b>Al corte:</b> cartera abierta y vencimientos acumulados a las 16:00.</li><li><b>Capital:</b> este ejemplo usa solo soles. En producción se respetan las monedas y la valoración oficial por venta; si falta valoración, se muestra la cobertura.</li><li><b>Sin datos:</b> «No disponible» o «Sin meta», nunca un cero inventado.</li><li><b>Equipo:</b> resultados mensuales con su atribución oficial; operación diaria con el equipo actual. Un traslado puede explicar diferencias entre ambos.</li><li><b>Cada cifra:</b> debe abrir el detalle del mismo período, alcance y definición.</li></ul>'],
};
const dialogo = document.querySelector('#detalle');
let origenFoco;
function abrir(titulo, cuerpo) {
  origenFoco = document.activeElement;
  document.querySelector('#detalle-titulo').textContent = titulo;
  document.querySelector('#detalle-cuerpo').innerHTML = cuerpo;
  dialogo.showModal();
  document.querySelector('#cerrar').focus();
}
document.addEventListener('click', event => {
  const boton = event.target.closest('button');
  if (!boton) return;
  if (boton.dataset.vista) vista(boton.dataset.vista);
  if (boton.dataset.tabla) pintarB(boton.dataset.tabla);
  if (boton.dataset.detalle) abrir(...detalles[boton.dataset.detalle]);
  if (boton.dataset.persona !== undefined) {
    const p = equipo[Number(boton.dataset.persona)];
    abrir(p.nombre, `<p>Analista ficticio · Octubre 2026 / Jornada del 16 de octubre</p><dl><dt>Capital confirmado del mes</dt><dd>${dinero(p.capital)}</dd><dt>Meta del mes</dt><dd>${dinero(p.meta)}</dd><dt>Cumplimiento</dt><dd>${decimal(p.capital/p.meta*100)}%</dd><dt>Conversión oficial del mes</dt><dd>${decimal(p.conversion)}%</dd><dt>Operaciones del mes</dt><dd>${p.operaciones}</dd><dt>Llamadas de hoy</dt><dd>${p.llamadas}</dd><dt>Contacto en llamadas útiles</dt><dd>${p.contestadas}/${p.utiles} · ${decimal(p.contestadas/p.utiles*100)}%</dd><dt>Citas realizadas / previstas hoy</dt><dd>${p.realizadas} / ${p.citas}</dd><dt>Tareas vencidas al corte</dt><dd>${p.vencidas}</dd><dt>Entrevistas realizadas abiertas</dt><dd>${p.oportunidades}</dd><dt>Potencial de esas oportunidades</dt><dd>${dinero(p.potencial)}</dd></dl><p class="detalle-callout">En el módulo conectado, desde aquí se abrirían sus operaciones, gestiones, citas y casos pendientes conservando el filtro de persona y fecha.</p>`);
  }
});
document.querySelector('#cerrar').addEventListener('click', () => dialogo.close());
document.querySelector('#volver').addEventListener('click', () => dialogo.close());
dialogo.addEventListener('close', () => origenFoco?.focus());
document.querySelector('#orden-a').addEventListener('change', pintarA);
pintarA();
pintarB('dia');
vista(location.hash === '#b' ? 'b' : 'a');
