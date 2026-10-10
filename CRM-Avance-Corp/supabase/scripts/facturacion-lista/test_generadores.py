#!/usr/bin/env python3
"""Pruebas offline de integridad y modo de solo lectura de los generadores 3B."""
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

CARPETA = Path(__file__).resolve().parent
MIGRACION = '20261009234500_crm_facturacion_lista_operaciones.sql'


class IntegridadGeneradores(unittest.TestCase):
    def setUp(self):
        # Todo dentro del worktree, sin conexiones ni credenciales y sin tocar originales.
        self.temporal = tempfile.TemporaryDirectory(prefix='.prueba-', dir=CARPETA)
        raiz = Path(self.temporal.name)
        self.carpeta = raiz / 'supabase/scripts/facturacion-lista'
        self.carpeta.mkdir(parents=True)
        for archivo in CARPETA.iterdir():
            if archivo.is_file() and archivo.suffix in ('.sql', '.py'):
                shutil.copy2(archivo, self.carpeta / archivo.name)
        shutil.copytree(CARPETA / 'vivo', self.carpeta / 'vivo')
        self.migracion = raiz / 'supabase/migrations' / MIGRACION
        self.migracion.parent.mkdir()
        shutil.copy2(CARPETA.parents[1] / 'migrations' / MIGRACION, self.migracion)
        self.addCleanup(self.temporal.cleanup)

    def ejecutar(self, generador, verificar=False):
        return subprocess.run([sys.executable, str(self.carpeta / generador), *(['--verificar'] if verificar else [])],
                              capture_output=True, text=True, env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'})

    def foto(self):
        return {str(p.relative_to(self.carpeta)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in self.carpeta.rglob('*') if p.is_file()}

    def test_verificar_no_escribe(self):
        antes = self.foto()
        for nombre in ('generar-cuerpos.py', 'generar-registrar.py'):
            r = self.ejecutar(nombre, True)
            self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(antes, self.foto())

    def test_copia_alterada_se_rechaza_y_se_repara(self):
        p = self.carpeta / 'ensayo-produccion.sql'
        p.write_text(p.read_text().replace('v_inicio timestamptz := clock_timestamp();',
                                           'v_inicio timestamptz := now();', 1))
        antes = self.foto()
        self.assertNotEqual(self.ejecutar('generar-cuerpos.py', True).returncode, 0)
        self.assertEqual(antes, self.foto())
        self.assertEqual(self.ejecutar('generar-cuerpos.py').returncode, 0)
        self.assertEqual(self.ejecutar('generar-cuerpos.py', True).returncode, 0)

    def test_registro_exige_texto_exacto(self):
        self.migracion.write_text('-- Cambio de texto incluso sin cambiar SQL\n' + self.migracion.read_text())
        antes = self.foto()
        self.assertNotEqual(self.ejecutar('generar-registrar.py', True).returncode, 0)
        self.assertEqual(antes, self.foto())
        self.assertEqual(self.ejecutar('generar-registrar.py').returncode, 0)
        self.assertEqual(self.ejecutar('generar-registrar.py', True).returncode, 0)
        registro = (self.carpeta / 'registrar.sql').read_text()
        self.assertIn(self.migracion.read_text(), registro)
        self.assertIn(hashlib.md5(self.migracion.read_bytes()).hexdigest(), registro)

    def test_vivo_alterado_falla_antes_de_escribir(self):
        p = self.carpeta / 'vivo/private.facturacion_operaciones.sql'
        p.write_text(p.read_text() + '-- alterado\n')
        antes = self.foto()
        self.assertNotEqual(self.ejecutar('generar-cuerpos.py').returncode, 0)
        self.assertEqual(antes, self.foto())

    def test_marcador_duplicado_no_admite_sincronizacion_ambigua(self):
        p = self.carpeta / 'medir.sql'
        p.write_text(p.read_text() + '-- INICIO MIGRACION\n')
        antes = self.foto()
        self.assertNotEqual(self.ejecutar('generar-cuerpos.py').returncode, 0)
        self.assertEqual(antes, self.foto())

    def test_marcadores_invertidos_no_escriben(self):
        p = self.carpeta / 'medir.sql'
        p.write_text(p.read_text().replace('-- INICIO MIGRACION', '-- CAMBIO MIGRACION')
                     .replace('-- FIN MIGRACION', '-- INICIO MIGRACION')
                     .replace('-- CAMBIO MIGRACION', '-- FIN MIGRACION'))
        antes = self.foto()
        self.assertNotEqual(self.ejecutar('generar-cuerpos.py').returncode, 0)
        self.assertEqual(antes, self.foto())

    def test_registrador_rechaza_huellas_ambiguas_sin_escribir(self):
        self.migracion.write_text(self.migracion.read_text() + '-- INICIO HUELLAS\n')
        antes = self.foto()
        self.assertNotEqual(self.ejecutar('generar-registrar.py').returncode, 0)
        self.assertEqual(antes, self.foto())

    def test_canonica_viva_alterada_no_escribe(self):
        p = self.carpeta / 'vivo/private.inversionista_canonica.sql'
        p.write_text(p.read_text().replace('c.n < 16', 'c.n < 1'))
        antes = self.foto()
        self.assertNotEqual(self.ejecutar('generar-cuerpos.py').returncode, 0)
        self.assertEqual(antes, self.foto())

    def test_firma_anterior_rechazada_por_registrador(self):
        original = self.migracion.read_text()
        for firma_anterior in (
            'date,date,uuid[],boolean,uuid,boolean,text[],text,integer,integer',
            'date,date,uuid[],uuid,boolean,text[],text,integer,integer',
        ):
            with self.subTest(firma=firma_anterior):
                self.migracion.write_text(original.replace(
                    'date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer', firma_anterior))
                antes = self.foto()
                self.assertNotEqual(self.ejecutar('generar-registrar.py').returncode, 0)
                self.assertEqual(antes, self.foto())

    def test_dias_fuera_de_posicion_rechazado_por_registrador(self):
        self.migracion.write_text(self.migracion.read_text().replace(
            'date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer',
            'date,date,uuid[],date[],boolean,uuid,boolean,text[],text,integer,integer'))
        antes = self.foto()
        self.assertNotEqual(self.ejecutar('generar-registrar.py').returncode, 0)
        self.assertEqual(antes, self.foto())

    def test_medicion_propagada_desde_unica_fuente(self):
        # Una nueva medición solo se escribe en HUELLAS: ambas copias y el registro deben seguirla.
        texto = self.migracion.read_text()
        inicio, resto = texto.split('-- INICIO HUELLAS\n')
        bloque, fin = resto.split('-- FIN HUELLAS\n')
        bloque = re.sub(r"(?<=', ')[0-9a-f]{32}|PENDIENTE_MEDIR_EN_BANCO", 'a' * 32, bloque)
        self.migracion.write_text(inicio + '-- INICIO HUELLAS\n' + bloque + '-- FIN HUELLAS\n' + fin)
        for generador in ('generar-cuerpos.py', 'generar-registrar.py'):
            self.assertEqual(self.ejecutar(generador).returncode, 0)
            self.assertEqual(self.ejecutar(generador, True).returncode, 0)
        for nombre in ('reversa.sql', 'ensayo-sintetico.sql', 'ensayo-produccion.sql', 'medir.sql', 'registrar.sql'):
            self.assertIn(bloque, (self.carpeta / nombre).read_text())

    def test_los_trece_mutantes_se_construyen_sobre_el_cuerpo_actual(self):
        # Evita entregar reemplazos obsoletos tras cambiar la implementación.
        migracion = self.migracion.read_text()
        nucleo = migracion.split('CREATE OR REPLACE FUNCTION private.facturacion_lista(')[1].split('$function$\n$def$;')[0]
        ensayo = (self.carpeta / 'ensayo-sintetico.sql').read_text()
        tabla = ensayo.split('for v_mutante in select * from (values')[1].split(') m(nombre, actor, estado, antes, despues)')[0]
        literal = r"'((?:[^']|'')*)'"
        mutantes = re.findall(r'\(' + r'\s*,\s*'.join([literal] * 5) + r'\)', tabla)
        self.assertEqual(len(mutantes), 13)
        self.assertEqual({m[2] for m in mutantes}, {f'P3B{i:02d}' for i in range(1, 14)})
        comparador = migracion.split('-- INICIO COMPARADOR\n')[1].split('-- FIN COMPARADOR\n')[0]
        for nombre, _, estado, antes, despues in mutantes:
            antes, despues = antes.replace("''", "'"), despues.replace("''", "'")
            self.assertEqual(nucleo.count(antes), 1, nombre)
            self.assertNotEqual(nucleo.replace(antes, despues), nucleo, nombre)
            self.assertIn("'" + estado + "'", comparador)


if __name__ == '__main__':
    unittest.main()
