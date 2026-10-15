"""Ajustes do projeto Android gerado pelo Capacitor: permissões de localização, aviso da viagem e número da versão."""
import os
import re

run = int(os.environ.get('GITHUB_RUN_NUMBER', '1'))

manifest = 'android/app/src/main/AndroidManifest.xml'
m = open(manifest, encoding='utf-8').read()
extras = [
    '<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />',
    '<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />',
    '<uses-feature android:name="android.hardware.location.gps" android:required="false" />',
    # câmera: leitura do código de barras na dupla conferência do carregamento
    '<uses-permission android:name="android.permission.CAMERA" />',
    '<uses-feature android:name="android.hardware.camera" android:required="false" />',
]
for linha in extras:
    nome = re.search(r'android:name="([^"]+)"', linha).group(1)
    if nome not in m:
        m = m.replace('</manifest>', '    ' + linha + '\n</manifest>')
open(manifest, 'w', encoding='utf-8').write(m)

# Localização em segundo plano (viagem): nome do canal do aviso fixo que aparece na barra do celular.
strings = 'android/app/src/main/res/values/strings.xml'
if os.path.exists(strings):
    st = open(strings, encoding='utf-8').read()
    extra = {
        'capacitor_background_geolocation_notification_channel_name': 'Viagem em andamento',
        'capacitor_background_geolocation_notification_color': '#702082',
    }
    for nome, valor in extra.items():
        if nome not in st:
            st = st.replace('</resources>', '    <string name="%s">%s</string>\n</resources>' % (nome, valor))
    open(strings, 'w', encoding='utf-8').write(st)

gradle = 'android/app/build.gradle'
g = open(gradle, encoding='utf-8').read()
g = re.sub(r'versionCode\s+\d+', 'versionCode %d' % run, g)
g = re.sub(r'versionName\s+"[^"]*"', 'versionName "1.0.%d"' % run, g)
open(gradle, 'w', encoding='utf-8').write(g)
print('Android ajustado: versão 1.0.%d (código %d), permissões de localização' % (run, run))
