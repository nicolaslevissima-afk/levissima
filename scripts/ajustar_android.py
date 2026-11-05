"""Ajustes do projeto Android gerado pelo Capacitor: permissões (localização, câmera, microfone), aviso da viagem e número da versão."""
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
    # microfone: gravar áudio nas Solicitações (24/10/2026)
    '<uses-permission android:name="android.permission.RECORD_AUDIO" />',
    '<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />',
    '<uses-feature android:name="android.hardware.microphone" android:required="false" />',
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

# Impressão direta (04/11/2026): o app manda o PDF para a impressão do Android (PrintManager), sem baixar o arquivo.
# A função "Impressora" fica no próprio app (não é um pacote de fora) e é registrada na MainActivity.
pasta_java = 'android/app/src/main/java/br/com/levissima/app'
if os.path.isdir(pasta_java):
    open(os.path.join(pasta_java, 'ImpressoraPlugin.java'), 'w', encoding='utf-8').write('''package br.com.levissima.app;

import android.content.Context;
import android.os.Bundle;
import android.os.CancellationSignal;
import android.os.ParcelFileDescriptor;
import android.print.PageRange;
import android.print.PrintAttributes;
import android.print.PrintDocumentAdapter;
import android.print.PrintDocumentInfo;
import android.print.PrintManager;
import android.util.Base64;

import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import java.io.FileOutputStream;
import java.io.IOException;

@CapacitorPlugin(name = "Impressora")
public class ImpressoraPlugin extends Plugin {

    @PluginMethod
    public void imprimirPdf(final PluginCall call) {
        String dados = call.getString("dados");
        String nomeRecebido = call.getString("nome", "documento");
        if (dados == null || dados.isEmpty()) {
            call.reject("Sem documento para imprimir.");
            return;
        }
        final byte[] pdf;
        try {
            pdf = Base64.decode(dados, Base64.DEFAULT);
        } catch (IllegalArgumentException e) {
            call.reject("Documento inválido.");
            return;
        }
        final String nome = (nomeRecebido == null || nomeRecebido.isEmpty()) ? "documento" : nomeRecebido.replaceAll("[^A-Za-z0-9._-]", "-");
        getActivity().runOnUiThread(new Runnable() {
            @Override
            public void run() {
                try {
                    PrintManager pm = (PrintManager) getActivity().getSystemService(Context.PRINT_SERVICE);
                    if (pm == null) {
                        call.reject("Impressão indisponível neste aparelho.");
                        return;
                    }
                    PrintDocumentAdapter adapter = new PrintDocumentAdapter() {
                        @Override
                        public void onLayout(PrintAttributes antes, PrintAttributes depois, CancellationSignal cancelar, LayoutResultCallback retorno, Bundle extras) {
                            if (cancelar.isCanceled()) {
                                retorno.onLayoutCancelled();
                                return;
                            }
                            PrintDocumentInfo info = new PrintDocumentInfo.Builder(nome + ".pdf")
                                .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
                                .build();
                            retorno.onLayoutFinished(info, true);
                        }

                        @Override
                        public void onWrite(PageRange[] paginas, ParcelFileDescriptor destino, CancellationSignal cancelar, WriteResultCallback retorno) {
                            FileOutputStream saida = null;
                            try {
                                saida = new FileOutputStream(destino.getFileDescriptor());
                                saida.write(pdf);
                                retorno.onWriteFinished(new PageRange[] { PageRange.ALL_PAGES });
                            } catch (IOException e) {
                                retorno.onWriteFailed(e.getMessage());
                            } finally {
                                if (saida != null) {
                                    try { saida.close(); } catch (IOException ignorado) { }
                                }
                            }
                        }
                    };
                    PrintAttributes atributos = new PrintAttributes.Builder().setMediaSize(PrintAttributes.MediaSize.ISO_A4).build();
                    pm.print(nome, adapter, atributos);
                    call.resolve();
                } catch (Exception e) {
                    call.reject("Não foi possível abrir a impressão.");
                }
            }
        });
    }
}
''')
    main = os.path.join(pasta_java, 'MainActivity.java')
    if os.path.exists(main):
        ma = open(main, encoding='utf-8').read()
        if 'ImpressoraPlugin' not in ma:
            ma = re.sub(r'public class MainActivity extends BridgeActivity\s*\{\s*\}',
                        'public class MainActivity extends BridgeActivity {\n'
                        '    @Override\n'
                        '    public void onCreate(android.os.Bundle savedInstanceState) {\n'
                        '        registerPlugin(ImpressoraPlugin.class);\n'
                        '        super.onCreate(savedInstanceState);\n'
                        '    }\n'
                        '}', ma)
            if 'ImpressoraPlugin' not in ma:
                ma = re.sub(r'(public class MainActivity extends BridgeActivity\s*\{)',
                            r'\1\n    @Override\n    public void onCreate(android.os.Bundle savedInstanceState) {\n        registerPlugin(ImpressoraPlugin.class);\n        super.onCreate(savedInstanceState);\n    }\n', ma, count=1)
            open(main, 'w', encoding='utf-8').write(ma)
    print('Android: impressão direta (Impressora) registrada')
