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
# Leitor de código de barras do Google (23/11/2026): conferência do carregamento pelo Google Play Services.
LEITOR_DEP = "implementation 'com.google.android.gms:play-services-code-scanner:16.1.0'"
if 'play-services-code-scanner' not in g:
    g, n = re.subn(r'(\ndependencies\s*\{)', r'\1\n    ' + LEITOR_DEP, g, count=1)
    if not n:
        g += '\ndependencies {\n    ' + LEITOR_DEP + '\n}\n'
open(gradle, 'w', encoding='utf-8').write(g)
# o módulo do leitor já vem baixado com o app (não espera o primeiro uso)
m = open(manifest, encoding='utf-8').read()
if 'com.google.mlkit.vision.DEPENDENCIES' not in m:
    m = m.replace('</application>', '    <meta-data android:name="com.google.mlkit.vision.DEPENDENCIES" android:value="barcode_ui" />\n    </application>', 1)
    open(manifest, 'w', encoding='utf-8').write(m)
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
    # Leitor (23/11/2026): abre o leitor de código de barras do Google (tela cheia) e devolve o código lido.
    open(os.path.join(pasta_java, 'LeitorPlugin.java'), 'w', encoding='utf-8').write('''package br.com.levissima.app;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.google.mlkit.vision.barcode.common.Barcode;
import com.google.mlkit.vision.codescanner.GmsBarcodeScanner;
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions;
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning;

@CapacitorPlugin(name = "Leitor")
public class LeitorPlugin extends Plugin {

    @PluginMethod
    public void ler(final PluginCall call) {
        try {
            GmsBarcodeScannerOptions opcoes = new GmsBarcodeScannerOptions.Builder()
                .setBarcodeFormats(Barcode.FORMAT_ITF, Barcode.FORMAT_EAN_13, Barcode.FORMAT_EAN_8,
                    Barcode.FORMAT_UPC_A, Barcode.FORMAT_UPC_E, Barcode.FORMAT_CODE_128)
                .enableAutoZoom()
                .build();
            GmsBarcodeScanner leitor = GmsBarcodeScanning.getClient(getActivity(), opcoes);
            leitor.startScan()
                .addOnSuccessListener(codigo -> {
                    JSObject r = new JSObject();
                    r.put("valor", codigo.getRawValue());
                    r.put("formato", codigo.getFormat());
                    call.resolve(r);
                })
                .addOnCanceledListener(() -> call.reject("Leitura cancelada.", "CANCELADO"))
                .addOnFailureListener(e -> call.reject(e.getMessage() == null ? "O leitor não abriu." : e.getMessage(), "FALHA"));
        } catch (Exception e) {
            call.reject("O leitor não abriu.", "FALHA");
        }
    }
}
''')
    # Tela (23/11/2026): tela cheia dos módulos — esconde as barras do celular; o Voltar sai da tela cheia (evento "saiu").
    open(os.path.join(pasta_java, 'TelaPlugin.java'), 'w', encoding='utf-8').write('''package br.com.levissima.app;

import android.view.Window;

import androidx.activity.OnBackPressedCallback;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.core.view.WindowInsetsControllerCompat;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

@CapacitorPlugin(name = "Tela")
public class TelaPlugin extends Plugin {
    private OnBackPressedCallback voltar;

    private void barras(boolean esconder) {
        Window w = getActivity().getWindow();
        WindowInsetsControllerCompat c = WindowCompat.getInsetsController(w, w.getDecorView());
        if (esconder) {
            c.setSystemBarsBehavior(WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
            c.hide(WindowInsetsCompat.Type.systemBars());
        } else {
            c.show(WindowInsetsCompat.Type.systemBars());
        }
    }

    private void saiuPeloVoltar() {
        barras(false);
        if (voltar != null) {
            voltar.remove();
            voltar = null;
        }
        notifyListeners("saiu", new JSObject());
    }

    @PluginMethod
    public void cheia(final PluginCall call) {
        final boolean ativa = Boolean.TRUE.equals(call.getBoolean("ativa", Boolean.TRUE));
        getActivity().runOnUiThread(new Runnable() {
            @Override
            public void run() {
                try {
                    barras(ativa);
                    if (ativa && voltar == null) {
                        voltar = new OnBackPressedCallback(true) {
                            @Override
                            public void handleOnBackPressed() {
                                saiuPeloVoltar();
                            }
                        };
                        getActivity().getOnBackPressedDispatcher().addCallback(getActivity(), voltar);
                    } else if (!ativa && voltar != null) {
                        voltar.remove();
                        voltar = null;
                    }
                    call.resolve();
                } catch (Exception e) {
                    call.reject("Não foi possível mudar a tela.");
                }
            }
        });
    }
}
''')
    # Os plugins do próprio app são registrados na MainActivity (gerada de novo a cada versão).
    PLUGINS = ['ImpressoraPlugin', 'LeitorPlugin', 'TelaPlugin']
    main = os.path.join(pasta_java, 'MainActivity.java')
    if os.path.exists(main):
        ma = open(main, encoding='utf-8').read()
        faltam = [x for x in PLUGINS if x + '.class' not in ma]
        if faltam:
            regs = ''.join('        registerPlugin(%s.class);\n' % x for x in faltam)
            if 'public void onCreate' in ma:
                ma = re.sub(r'(public void onCreate\([^)]*\)\s*\{\n)', lambda mm: mm.group(1) + regs, ma, count=1)
            else:
                ma = re.sub(r'(public class MainActivity extends BridgeActivity\s*\{)',
                            lambda mm: mm.group(1) + '\n    @Override\n    public void onCreate(android.os.Bundle savedInstanceState) {\n' + regs + '        super.onCreate(savedInstanceState);\n    }\n', ma, count=1)
            open(main, 'w', encoding='utf-8').write(ma)
    print('Android: impressão direta (Impressora), leitor de código de barras (Leitor) e tela cheia (Tela) registrados')
