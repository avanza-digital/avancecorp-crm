import assert from 'node:assert/strict';
import test from 'node:test';
import { validarBancarios, validarSeccionBancaria } from './bancarios.mjs';

/** Sección PEN válida mínima, para variar un solo campo por caso. */
function seccionValida(extra = {}) {
  return {
    banco: 'BCP',
    numero_cuenta: '1912345678901',
    tipo_cuenta: 'ahorros',
    cci: '00219100234567890112',
    titular_distinto: false,
    ...extra,
  };
}

// ── La regla que motiva todo el módulo ───────────────────────────────────────

test('sin ninguna cuenta NO se puede crear el cliente', () => {
  const r = validarBancarios({ pen: {}, usd: {} });
  assert.equal(r.ok, false);
  assert.match(r.error, /al menos una cuenta bancaria/i);
});

test('body sin el bloque bancarios se rechaza (fail-closed, no crea a medias)', () => {
  for (const entrada of [undefined, null, {}, 'x', 42]) {
    const r = validarBancarios(entrada);
    assert.equal(r.ok, false, `debería rechazar: ${JSON.stringify(entrada)}`);
    assert.match(r.error, /al menos una cuenta bancaria/i);
  }
});

test('basta la cuenta en SOLES', () => {
  const r = validarBancarios({ pen: seccionValida(), usd: {} });
  assert.equal(r.ok, true);
  assert.equal(r.cuentas.length, 1);
  assert.equal(r.cuentas[0].moneda, 'PEN');
  assert.equal(r.cuentas[0].banco, 'BCP');
});

test('basta la cuenta en DÓLARES', () => {
  const r = validarBancarios({ pen: {}, usd: seccionValida({ banco: 'Interbank' }) });
  assert.equal(r.ok, true);
  assert.equal(r.cuentas.length, 1);
  assert.equal(r.cuentas[0].moneda, 'USD');
  assert.equal(r.cuentas[0].banco, 'Interbank');
});

test('las dos monedas van a filas separadas del ledger', () => {
  const r = validarBancarios({
    pen: seccionValida({ banco: 'BCP', numero_cuenta: 'PEN-1' }),
    usd: seccionValida({ banco: 'BBVA', numero_cuenta: 'USD-1' }),
  });
  assert.equal(r.ok, true);
  assert.deepEqual(r.cuentas.map((c) => [c.moneda, c.numero_cuenta]), [
    ['PEN', 'PEN-1'], ['USD', 'USD-1'],
  ]);
});

test('devuelve solo las claves de una cuenta del ledger', () => {
  const r = validarBancarios({ pen: seccionValida(), usd: {} });
  assert.equal(r.ok, true);
  assert.deepEqual(Object.keys(r.cuentas[0]).sort(), [
    'banco', 'beneficiario_dni', 'beneficiario_nombre', 'cci',
    'moneda', 'numero_cuenta', 'tipo_cuenta', 'titular_distinto',
  ]);
});

// ── Set completo cuando la sección se empezó a llenar ────────────────────────

test('una sección a medias no pasa: exige el set completo', () => {
  const casos = [
    [{ banco: '' }, /Selecciona el banco/],
    [{ numero_cuenta: '' }, /N° de cuenta.*obligatorio/],
    [{ tipo_cuenta: '' }, /Selecciona el tipo de cuenta/],
    [{ cci: '' }, /CCI.*obligatorio/],
  ];
  for (const [parche, patron] of casos) {
    const r = validarBancarios({ pen: seccionValida(parche), usd: {} });
    assert.equal(r.ok, false, `debería rechazar ${JSON.stringify(parche)}`);
    assert.match(r.error, patron);
  }
});

test('el CCI debe tener exactamente 20 dígitos', () => {
  for (const cci of ['1234567890123456789', '123456789012345678901', '0021910023456789011a']) {
    const r = validarBancarios({ pen: seccionValida({ cci }), usd: {} });
    assert.equal(r.ok, false, `debería rechazar CCI ${cci}`);
    assert.match(r.error, /20 dígitos/);
  }
});

test('tipo de cuenta fuera del catálogo se rechaza', () => {
  const r = validarBancarios({ pen: seccionValida({ tipo_cuenta: 'plazo_fijo' }), usd: {} });
  assert.equal(r.ok, false);
  assert.match(r.error, /Tipo de cuenta.*inválido/);
});

test('la caja municipal con letras en el número de cuenta SÍ pasa', () => {
  const r = validarBancarios({ pen: seccionValida({ banco: 'Caja Cusco', numero_cuenta: '106-01-AB1234' }), usd: {} });
  assert.equal(r.ok, true);
  assert.equal(r.cuentas[0].numero_cuenta, '106-01-AB1234');
});

test('un número de cuenta con espacios se rechaza', () => {
  const r = validarBancarios({ pen: seccionValida({ numero_cuenta: '191 2345 678' }), usd: {} });
  assert.equal(r.ok, false);
  assert.match(r.error, /letras, números y guiones/);
});

// ── Beneficiario (la cuenta es de un tercero) ────────────────────────────────

test('con titular distinto se exigen nombre y documento del beneficiario', () => {
  const sinNombre = validarBancarios({
    pen: seccionValida({ titular_distinto: true, beneficiario_dni: '09876543' }),
    usd: {},
  });
  assert.equal(sinNombre.ok, false);
  assert.match(sinNombre.error, /nombre completo del beneficiario/);

  const sinDoc = validarBancarios({
    pen: seccionValida({ titular_distinto: true, beneficiario_nombre: 'Ana Ruiz' }),
    usd: {},
  });
  assert.equal(sinDoc.ok, false);
  assert.match(sinDoc.error, /DNI del beneficiario.*obligatorio/);
});

test('el documento del beneficiario sigue la regla genérica 8–12 dígitos', () => {
  const corto = validarBancarios({
    pen: seccionValida({ titular_distinto: true, beneficiario_nombre: 'Ana Ruiz', beneficiario_dni: '1234567' }),
    usd: {},
  });
  assert.equal(corto.ok, false);
  assert.match(corto.error, /entre 8 y 12 dígitos/);

  const ok = validarBancarios({
    pen: seccionValida({ titular_distinto: true, beneficiario_nombre: 'Ana Ruiz', beneficiario_dni: '098765432' }),
    usd: {},
  });
  assert.equal(ok.ok, true);
});

test('el nombre del beneficiario se normaliza a MAYÚSCULA sin espacios dobles', () => {
  const r = validarBancarios({
    pen: seccionValida({ titular_distinto: true, beneficiario_nombre: '  ana   maría ruiz  ', beneficiario_dni: '09876543' }),
    usd: {},
  });
  assert.equal(r.ok, true);
  assert.equal(r.cuentas[0].beneficiario_nombre, 'ANA MARÍA RUIZ');
});

test('sin titular distinto los campos del beneficiario quedan en null', () => {
  const r = validarBancarios({
    pen: seccionValida({ beneficiario_nombre: 'se ignora', beneficiario_dni: '09876543' }),
    usd: {},
  });
  assert.equal(r.ok, true);
  assert.equal(r.cuentas[0].beneficiario_nombre, null);
  assert.equal(r.cuentas[0].beneficiario_dni, null);
  assert.equal(r.cuentas[0].titular_distinto, false);
});

test('rechaza límites que también aplica la base antes de crear Auth', () => {
  for (const parche of [
    { banco: 'B'.repeat(101) },
    { numero_cuenta: '1'.repeat(31) },
    { titular_distinto: true, beneficiario_nombre: 'A'.repeat(201), beneficiario_dni: '12345678' },
  ]) {
    assert.equal(validarBancarios({ pen: seccionValida(parche), usd: {} }).ok, false);
  }
});

test('marcar SOLO el check de titular distinto no cuenta como sección vacía', () => {
  // Si contara como vacía, un cliente podría entrar sin ninguna cuenta real.
  const r = validarBancarios({ pen: { titular_distinto: true }, usd: {} });
  assert.equal(r.ok, false);
  assert.match(r.error, /Selecciona el banco/);
});

// ── Higiene de entrada ───────────────────────────────────────────────────────

test('los espacios de los extremos no cuelan una sección vacía', () => {
  const r = validarBancarios({ pen: { banco: '   ', numero_cuenta: '  ', tipo_cuenta: ' ', cci: '  ' }, usd: {} });
  assert.equal(r.ok, false);
  assert.match(r.error, /al menos una cuenta bancaria/i);
});

test('titular_distinto solo es cierto con el booleano true (nunca por truthy)', () => {
  // Un 'false' de un <input> mal serializado no debe activar el bloque de beneficiario.
  const r = validarSeccionBancaria({ ...seccionValida(), titular_distinto: 'false' }, 'Soles');
  assert.equal(r.ok, true);
  assert.equal(r.datos.titular_distinto, false);
});

test('el mensaje dice de qué moneda es el problema', () => {
  const pen = validarBancarios({ pen: seccionValida({ cci: '1' }), usd: {} });
  assert.match(pen.error, /\(Soles\)/);
  const usd = validarBancarios({ pen: {}, usd: seccionValida({ cci: '1' }) });
  assert.match(usd.error, /\(Dólares\)/);
});
