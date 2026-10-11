"""Ajustes do projeto Android gerado pelo Capacitor: permissões de localização e número da versão."""
import os
import re

run = int(os.environ.get('GITHUB_RUN_NUMBER', '1'))

manifest = 'android/app/src/main/AndroidManifest.xml'
m = open(manifest, encoding='utf-8').read()
extras = [
    '<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />',
    '<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />',
    '<uses-feature android:name="android.hardware.location.gps" android:required="false" />',
]
for linha in extras:
    nome = re.search(r'android:name="([^"]+)"', linha).group(1)
    if nome not in m:
        m = m.replace('</manifest>', '    ' + linha + '\n</manifest>')
open(manifest, 'w', encoding='utf-8').write(m)

gradle = 'android/app/build.gradle'
g = open(gradle, encoding='utf-8').read()
g = re.sub(r'versionCode\s+\d+', 'versionCode %d' % run, g)
g = re.sub(r'versionName\s+"[^"]*"', 'versionName "1.0.%d"' % run, g)
open(gradle, 'w', encoding='utf-8').write(g)
print('Android ajustado: versão 1.0.%d (código %d), permissões de localização' % (run, run))
