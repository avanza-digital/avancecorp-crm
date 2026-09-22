import { ESPACIOS, OPCIONES, REGLAS, crearRevision, leerRevision, resumirRevision, LIMITE_REVISION_BYTES } from '/banco-core.mjs';

const elemento = id => document.getElementById(id);
let banco, revision, posicion = 0, hayCambios = false;
const espacio = location.pathname.slice(1);
const mensaje = texto => { elemento('estado').textContent = texto; };
const respuestas = () => new Map(revision.respuestas.map(r => [r.id, r]));

function mostrarProgreso() {
  const resumen = resumirRevision(revision);
  const revisados = resumen.clasificadas + resumen.dudas;
  elemento('progreso').textContent = `${revisados} de ${resumen.total} revisados · ${resumen.dudas} con duda`;
  elemento('avance').max = resumen.total;
  elemento('avance').value = revisados;
  return resumen;
}

function mostrar(enfocar = false) {
  const resumen = mostrarProgreso();
  const final = posicion === banco.casos.length;
  elemento('caso').hidden = final;
  elemento('resumen').hidden = !final;
  if (final) {
    elemento('resumen-texto').textContent = `${resumen.clasificadas} clasificados, ${resumen.dudas} con duda y ${resumen.sin_respuesta} sin respuesta. Las dudas quedan para conversar; no cuentan como acuerdo.`;
    if (enfocar) elemento('titulo-resumen').focus();
    return;
  }
  const caso = banco.casos[posicion];
  elemento('titulo-caso').textContent = `Caso ${posicion + 1} de ${banco.casos.length}`;
  elemento('resultado').textContent = caso.resultado;
  elemento('nota').textContent = caso.nota || '(Sin nota)';
  const elegida = respuestas().get(caso.id).clase;
  elemento('opciones').replaceChildren(...OPCIONES.map(opcion => {
    const label = document.createElement('label');
    label.className = `opcion${opcion.valor === 'duda' ? ' duda' : ''}`;
    const radio = document.createElement('input');
    radio.type = 'radio'; radio.name = 'clase'; radio.value = opcion.valor; radio.checked = opcion.valor === elegida;
    radio.addEventListener('change', () => {
      respuestas().get(caso.id).clase = radio.value; hayCambios = true;
      elemento('siguiente').disabled = false;
      mostrarProgreso();
      mensaje('');
    });
    const texto = document.createElement('span'), titulo = document.createElement('strong'), detalle = document.createElement('span');
    titulo.textContent = opcion.titulo; detalle.textContent = opcion.detalle;
    texto.append(titulo, detalle); label.append(radio, texto); return label;
  }));
  elemento('anterior').disabled = posicion === 0;
  elemento('siguiente').disabled = elegida === null;
  elemento('siguiente').textContent = posicion === banco.casos.length - 1 ? 'Ver resumen' : 'Continuar';
  if (enfocar) elemento('titulo-caso').focus();
}

elemento('formulario').addEventListener('submit', evento => {
  evento.preventDefault();
  if (!revision || !banco.casos[posicion] || respuestas().get(banco.casos[posicion].id).clase === null) return;
  posicion += 1; mostrar(true);
});
elemento('anterior').addEventListener('click', () => { if (posicion > 0) { posicion -= 1; mostrar(true); } });
elemento('volver').addEventListener('click', () => { posicion = 0; mostrar(true); });
elemento('descargar').addEventListener('click', () => {
  if (!revision) return;
  const salida = crearRevision(banco, espacio, revision.respuestas);
  const url = URL.createObjectURL(new Blob([JSON.stringify(salida, null, 2)], { type: 'application/json' }));
  const enlace = document.createElement('a');
  enlace.href = url; enlace.download = `revision-sintetica-${espacio}-${salida.emitido_en.replace(/[:.]/g, '-')}.json`;
  document.body.append(enlace); enlace.click(); enlace.remove();
  setTimeout(() => URL.revokeObjectURL(url), 30_000);
  // No quitamos el aviso al salir: solicitar una descarga no prueba que se guardó.
  mensaje('Descarga solicitada. Comprueba que el JSON quedó guardado antes de cerrar la pestaña.');
});
elemento('archivo').addEventListener('change', async evento => {
  const archivo = evento.target.files?.[0];
  if (!archivo || !revision) return;
  try {
    if (archivo.size > LIMITE_REVISION_BYTES) throw new Error('archivo_grande');
    const importada = leerRevision(await archivo.text(), banco, espacio);
    if (hayCambios && !window.confirm('¿Sustituir el avance de esta pestaña por el archivo? Descarga primero si quieres conservarlo.')) return;
    revision = importada;
    posicion = banco.casos.findIndex(caso => respuestas().get(caso.id).clase === null);
    if (posicion < 0) posicion = banco.casos.length;
    hayCambios = false; mostrar(true);
    mensaje('Respuestas recuperadas. El archivo no verifica la identidad del supervisor.');
  } catch {
    mensaje('Archivo rechazado. Debe ser un JSON de este equipo y de la versión vigente, sin campos extra. Tu avance no cambió.');
  } finally { evento.target.value = ''; }
});
window.addEventListener('beforeunload', evento => {
  if (hayCambios) { evento.preventDefault(); evento.returnValue = ''; }
});

try {
  const respuesta = await fetch('/casos.json', { cache: 'no-store', credentials: 'omit' });
  if (!respuesta.ok) throw new Error('banco_no_disponible');
  banco = await respuesta.json();
  if (!ESPACIOS.includes(espacio)) elemento('eleccion').hidden = false;
  else {
    revision = crearRevision(banco, espacio);
    elemento('equipo').textContent = espacio === 'equipo-a' ? 'Revisión · Equipo A' : 'Revisión · Equipo B';
    for (const regla of REGLAS) { const li = document.createElement('li'); li.textContent = regla; elemento('reglas').append(li); }
    elemento('ejercicio').hidden = false;
    mostrar();
  }
  mensaje('');
} catch { mensaje('No se pudo cargar el banco local. Recarga la página o comprueba que el servidor sigue abierto.'); }
