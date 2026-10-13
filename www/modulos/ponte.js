/* LEVÍSSIMA · ponte dos módulos
 *
 * Liga os programas da fábrica (Manutenção, Checklist de empilhadeiras, Uniformes e EPI, Estoque de garrafões)
 * ao login e ao banco do LEVÍSSIMA (Supabase). Cada programa continua usando o mesmo jeito de guardar dados
 * que já usava (window.claude.use('db' | 'user' | 'downloads')); aqui esse pedido é atendido pelo Supabase:
 *   - só entra quem fez login no LEVÍSSIMA com uma senha que tem este módulo (ou a senha mestre);
 *   - os dados ficam na tabela modulo_docs, separados por módulo e protegidos pelas regras do banco;
 *   - as telas se atualizam sozinhas quando outra pessoa grava (tempo real).
 *
 * Uso na página do módulo, antes de qualquer outro script:
 *   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.js"></script>
 *   <script src="ponte.js" data-modulo="manutencao"></script>
 */
(function () {
  'use strict';

  var CONFIG = { url: "https://lzsvtwwpthjncrhznfez.supabase.co", anonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx6c3Z0d3dwdGhqbmNyaHpuZmV6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE3NTQ5MjgsImV4cCI6MjEwNzMzMDkyOH0.W446lxCtvIVPn45yQqgr8Gj77s_n-t5E1Q-YYeWFN2E" };
  var NOMES = {
    manutencao: 'Manutenção',
    empilhadeiras: 'Checklist de empilhadeiras',
    uniformes: 'Uniformes e EPI',
    garrafoes: 'Estoque de garrafões'
  };
  var script = document.currentScript;
  var MODULO = (script && script.getAttribute('data-modulo')) || '';
  var RAIZ = (script && script.getAttribute('data-raiz')) || '../';
  var NOME_MODULO = NOMES[MODULO] || 'Módulo';

  function irParaLogin() { location.replace(RAIZ + 'index.html#ir=' + encodeURIComponent(MODULO)); }
  function voltarAoInicio() { location.href = RAIZ + 'index.html'; }

  // ---------- quem está logado (vem do token do login) ----------
  function lerToken(t) {
    try {
      var p = String(t || '').split('.')[1] || '';
      p = p.replace(/-/g, '+').replace(/_/g, '/');
      while (p.length % 4) p += '=';
      var txt = decodeURIComponent(Array.prototype.map.call(atob(p), function (c) {
        return '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2);
      }).join(''));
      return JSON.parse(txt) || {};
    } catch (e) { return {}; }
  }
  // 'gerir' | 'usar' | '' (sem acesso)
  function nivelNoModulo(meta, m) {
    meta = meta || {};
    if (meta.papel === 'mestre') return 'gerir';
    if (meta.papel !== 'equipe' && meta.papel !== 'setor') return '';
    var l = Array.isArray(meta.modulos) ? meta.modulos : [];
    if (l.indexOf(m + ':gerir') >= 0) return 'gerir';
    if (l.indexOf(m) >= 0) return 'usar';
    return '';
  }

  var sb = null;
  var ident = null; // { uid, nome, papel, nivel }
  var prontoResolver, prontoRejeitar;
  var pronto = new Promise(function (ok, falha) { prontoResolver = ok; prontoRejeitar = falha; });
  pronto.catch(function () {});

  function iniciar() {
    if (!window.supabase || typeof window.supabase.createClient !== 'function') {
      mostrarAviso('Não foi possível carregar o LEVÍSSIMA. Verifique a internet e tente de novo.', true);
      prontoRejeitar({ code: 'unavailable', message: 'sem supabase' });
      return;
    }
    sb = window.supabase.createClient(CONFIG.url, CONFIG.anonKey, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false, storageKey: 'levissima-login' }
    });
    sb.auth.onAuthStateChange(function (ev, s) {
      if (ev === 'SIGNED_OUT') { irParaLogin(); return; }
      if (s && s.access_token && sb.realtime && sb.realtime.setAuth) sb.realtime.setAuth(s.access_token);
    });
    sb.auth.getSession().then(function (r) {
      var s = r && r.data && r.data.session;
      if (!s || !s.access_token) { irParaLogin(); return; }
      var claims = lerToken(s.access_token);
      var meta = claims.app_metadata || (s.user && s.user.app_metadata) || {};
      var nivel = nivelNoModulo(meta, MODULO);
      ident = { uid: claims.sub || (s.user && s.user.id) || '', nome: meta.nome || '', papel: meta.papel || '', nivel: nivel };
      montarBarra();
      if (!nivel) {
        mostrarAviso('A sua senha não abre o módulo ' + NOME_MODULO + '. Peça à diretoria para liberar este módulo para você.', true);
        prontoRejeitar({ code: 'not_granted', message: 'sem acesso ao módulo' });
        return;
      }
      if (sb.realtime && sb.realtime.setAuth) sb.realtime.setAuth(s.access_token);
      prontoResolver(true);
    }).catch(function (e) {
      console.error('login', e);
      mostrarAviso('Não foi possível conferir o seu login agora. Verifique a internet e tente de novo.', true);
      prontoRejeitar({ code: 'unavailable', message: 'login' });
    });
  }

  // ---------- barra do LEVÍSSIMA no alto da página ----------
  var CSS = '' +
    '#lev-barra{--lb-bg:#ffffff;--lb-ink:#122657;--lb-muted:#5b6b80;--lb-line:#dde3ea;--lb-hover:#eef3f9;' +
    'position:relative;z-index:50;display:flex;align-items:center;gap:10px;min-height:46px;padding:6px 14px;' +
    'background:var(--lb-bg);color:var(--lb-ink);border-bottom:1px solid var(--lb-line);' +
    'font:500 14px/1.2 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;box-sizing:border-box}' +
    '#lev-barra *{box-sizing:border-box}' +
    '#lev-barra a,#lev-barra button{font:inherit;color:inherit;text-decoration:none;background:none;border:0;cursor:pointer;' +
    'display:inline-flex;align-items:center;gap:8px;padding:6px 8px;border-radius:8px;min-height:36px}' +
    '#lev-barra a:hover,#lev-barra button:hover{background:var(--lb-hover)}' +
    '#lev-barra a:focus-visible,#lev-barra button:focus-visible{outline:2px solid #125A9E;outline-offset:1px}' +
    '#lev-barra .lb-logo{height:24px;width:auto;display:block}' +
    '#lev-barra .lb-logo-esc{display:none}' +
    '#lev-barra .lb-seta{font-size:20px;line-height:1;margin-right:-2px}' +
    '#lev-barra .lb-mod{font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;min-width:0}' +
    '#lev-barra .lb-sep{width:1px;align-self:stretch;margin:6px 2px;background:var(--lb-line)}' +
    '#lev-barra .lb-esp{flex:1}' +
    '#lev-barra .lb-quem{color:var(--lb-muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:30vw}' +
    '#lev-barra .lb-sair{color:var(--lb-muted);font-weight:600}' +
    '@media (max-width:560px){#lev-barra .lb-quem{display:none}#lev-barra .lb-logo{height:20px}}' +
    '@media (prefers-color-scheme:dark){#lev-barra{--lb-bg:#0f1720;--lb-ink:#e3ebf5;--lb-muted:#93a4b8;--lb-line:#23303d;--lb-hover:#1a2531}' +
    '#lev-barra .lb-logo-cla{display:none}#lev-barra .lb-logo-esc{display:block}}' +
    '#lev-aviso{max-width:560px;margin:48px auto;padding:24px;border:1px solid #dde3ea;border-radius:14px;background:#fff;color:#122657;' +
    'font:16px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;text-align:center}' +
    '#lev-aviso a{display:inline-block;margin-top:14px;padding:10px 18px;border-radius:10px;background:#125A9E;color:#fff;text-decoration:none;font-weight:600}' +
    '@media (prefers-color-scheme:dark){#lev-aviso{background:#0f1720;color:#e3ebf5;border-color:#23303d}}';

  function quandoPronto(fn) {
    if (document.body) fn(); else document.addEventListener('DOMContentLoaded', fn);
  }
  function montarBarra() {
    quandoPronto(function () {
      if (document.getElementById('lev-barra')) return;
      var st = document.createElement('style');
      st.textContent = CSS;
      document.head.appendChild(st);
      var b = document.createElement('div');
      b.id = 'lev-barra';
      b.setAttribute('role', 'navigation');
      b.setAttribute('aria-label', 'LEVÍSSIMA');
      var a = document.createElement('a');
      a.href = RAIZ + 'index.html';
      a.title = 'Voltar ao início do LEVÍSSIMA';
      a.innerHTML = '<span class="lb-seta" aria-hidden="true">‹</span>' +
        '<img class="lb-logo lb-logo-cla" src="' + RAIZ + 'marca/levissima-horizontal.svg" alt="LEVÍSSIMA">' +
        '<img class="lb-logo lb-logo-esc" src="' + RAIZ + 'marca/levissima-horizontal-escuro.svg" alt="LEVÍSSIMA">';
      var sep = document.createElement('span'); sep.className = 'lb-sep';
      var mod = document.createElement('span'); mod.className = 'lb-mod'; mod.textContent = NOME_MODULO;
      var esp = document.createElement('span'); esp.className = 'lb-esp';
      var quem = document.createElement('span'); quem.className = 'lb-quem';
      quem.textContent = ident && ident.nome ? ident.nome : '';
      var sair = document.createElement('button'); sair.type = 'button'; sair.className = 'lb-sair'; sair.textContent = 'Sair';
      sair.addEventListener('click', function () {
        sair.disabled = true;
        var fim = function () { location.replace(RAIZ + 'index.html'); };
        try { sb.auth.signOut({ scope: 'local' }).then(fim, fim); } catch (e) { fim(); }
      });
      b.appendChild(a); b.appendChild(sep); b.appendChild(mod); b.appendChild(esp); b.appendChild(quem); b.appendChild(sair);
      document.body.insertBefore(b, document.body.firstChild);
    });
  }
  function mostrarAviso(texto, esconderApp) {
    quandoPronto(function () {
      if (!document.getElementById('lev-barra')) {
        var st = document.createElement('style'); st.textContent = CSS; document.head.appendChild(st);
      }
      if (esconderApp) {
        Array.prototype.forEach.call(document.body.children, function (el) {
          if (el.id !== 'lev-barra' && el.tagName !== 'SCRIPT' && el.tagName !== 'STYLE') el.style.display = 'none';
        });
      }
      var av = document.getElementById('lev-aviso');
      if (!av) {
        av = document.createElement('div');
        av.id = 'lev-aviso';
        av.setAttribute('role', 'alert');
        document.body.appendChild(av);
      }
      av.innerHTML = '';
      var p = document.createElement('p'); p.style.margin = '0'; p.textContent = texto;
      var a = document.createElement('a'); a.href = RAIZ + 'index.html'; a.textContent = 'Voltar ao LEVÍSSIMA';
      av.appendChild(p); av.appendChild(a);
      av.style.display = '';
    });
  }

  // ---------- erros no formato que os programas já entendem ----------
  function erroDe(e, contexto) {
    if (e && e.code && typeof e.code === 'string' && /^(unavailable|not_found|not_granted|invalid_argument|internal)$/.test(e.code)) return e;
    var msg = String((e && (e.message || e.msg || e.error_description)) || e || '');
    var code = e && e.code ? String(e.code) : '';
    var st = e && (e.status || e.statusCode);
    var r;
    if (code === 'P0002') r = { code: 'not_found', message: 'Registro não encontrado.' };
    else if (code === '42501' || st === 401 || st === 403 || /row-level security|permission denied|JWT/i.test(msg)) r = { code: 'not_granted', message: 'Sem permissão para gravar neste módulo.' };
    else if (st === 413 || /too large|payload/i.test(msg) || code === '54000') r = { code: 'invalid_argument', message: 'O registro ficou grande demais para gravar.' };
    else if (/fetch|network|Load failed|timeout|ECONN|Failed/i.test(msg) || st === 0 || st >= 500 || !navigator.onLine) r = { code: 'unavailable', message: 'Sem conexão com o banco agora.' };
    else r = { code: 'internal', message: msg || 'Erro ao gravar.' };
    if (contexto) console.warn('LEVÍSSIMA · ' + contexto, e);
    return r;
  }

  // ---------- banco do módulo (mesmo jeito do banco que os programas já usavam) ----------
  function copia(v) { return v == null ? v : JSON.parse(JSON.stringify(v)); }
  function novoId() {
    var c = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789', out = '';
    var r = crypto.getRandomValues(new Uint8Array(20));
    for (var i = 0; i < 20; i++) out += c[r[i] % c.length];
    return out;
  }
  function campo(obj, caminho) {
    var partes = String(caminho).split('.'), v = obj;
    for (var i = 0; i < partes.length; i++) { if (v == null) return undefined; v = v[partes[i]]; }
    return v;
  }
  function compara(a, b) {
    if (a === b) return 0;
    if (a === undefined || a === null) return -1;
    if (b === undefined || b === null) return 1;
    if (typeof a === 'number' && typeof b === 'number') return a - b;
    return String(a) < String(b) ? -1 : 1;
  }
  function confere(d, f) {
    var v = campo(d, f.campo), x = f.valor;
    switch (f.op) {
      case '==': case 'eq': return JSON.stringify(v) === JSON.stringify(x);
      case '!=': case 'ne': return JSON.stringify(v) !== JSON.stringify(x);
      case '<': case 'lt': return v != null && compara(v, x) < 0;
      case '<=': case 'lte': return v != null && compara(v, x) <= 0;
      case '>': case 'gt': return v != null && compara(v, x) > 0;
      case '>=': case 'gte': return v != null && compara(v, x) >= 0;
      case 'in': return Array.isArray(x) && x.some(function (y) { return JSON.stringify(y) === JSON.stringify(v); });
      case 'not-in': return Array.isArray(x) && !x.some(function (y) { return JSON.stringify(y) === JSON.stringify(v); });
      case 'array-contains': return Array.isArray(v) && v.some(function (y) { return JSON.stringify(y) === JSON.stringify(x); });
      default: return false;
    }
  }
  function dividir(caminho) {
    var p = String(caminho || '').replace(/^\/+|\/+$/g, '').split('/').filter(Boolean);
    return p;
  }

  function criarBanco() {
    var cache = {};      // caminho -> { id -> dados }
    var carregando = {}; // caminho -> Promise
    var pendentes = {};  // caminho -> mudanças que chegaram durante a primeira leitura
    var ouvintes = [];   // { caminho, consulta, cb, pronto } ou { caminho, id, cb, pronto }
    var canal = null, jaConectou = false;

    function snapDoc(caminho, id, dados) {
      var d = dados !== undefined ? dados : (cache[caminho] ? cache[caminho][id] : undefined);
      var existe = d !== undefined && d !== null;
      return {
        id: id, exists: existe, ref: docRef(caminho, id), metadata: { fromCache: false, hasPendingWrites: false },
        data: function () { return existe ? copia(d) : undefined; },
        get: function (f) { return existe ? copia(campo(d, f)) : undefined; }
      };
    }
    function snapConsulta(caminho, q) {
      var mapa = cache[caminho] || {};
      var ids = Object.keys(mapa).filter(function (id) {
        return (q.filtros || []).every(function (f) { return confere(mapa[id], f); });
      });
      if (q.ordem && q.ordem.length) {
        ids.sort(function (a, b) {
          for (var i = 0; i < q.ordem.length; i++) {
            var o = q.ordem[i];
            var c = compara(campo(mapa[a], o.campo), campo(mapa[b], o.campo));
            if (c) return o.dir === 'desc' ? -c : c;
          }
          return a < b ? -1 : a > b ? 1 : 0;
        });
      }
      if (q.limite != null) ids = ids.slice(0, q.limite);
      var docs = ids.map(function (id) { return snapDoc(caminho, id); });
      return {
        docs: docs, size: docs.length, empty: !docs.length, metadata: { fromCache: false, hasPendingWrites: false },
        forEach: function (fn) { docs.forEach(fn); }
      };
    }
    function avisar(caminho, id) {
      ouvintes.slice().forEach(function (o) {
        if (o.caminho !== caminho || !o.pronto) return;
        try {
          if (o.id !== undefined) { if (id == null || o.id === id) o.cb(snapDoc(caminho, o.id)); }
          else o.cb(snapConsulta(caminho, o.consulta));
        } catch (e) { console.error(e); }
      });
    }
    function aplicar(caminho, id, dados) { // dados null = apagado
      if (!cache[caminho]) return;
      if (dados == null) delete cache[caminho][id]; else cache[caminho][id] = dados;
      avisar(caminho, id);
    }
    function lerTudo(caminho) {
      var out = [], passo = 1000;
      function pagina(de) {
        return sb.from('modulo_docs').select('id,dados').eq('modulo', MODULO).eq('caminho', caminho)
          .order('id').range(de, de + passo - 1).then(function (r) {
            if (r.error) throw r.error;
            out = out.concat(r.data || []);
            return (r.data || []).length === passo ? pagina(de + passo) : out;
          });
      }
      return pagina(0);
    }
    function recarregar(caminho) {
      return lerTudo(caminho).then(function (rows) {
        cache[caminho] = {};
        rows.forEach(function (r) { cache[caminho][r.id] = r.dados || {}; });
        avisar(caminho, null);
      }).catch(function (e) { console.warn('LEVÍSSIMA · releitura', e); });
    }
    function buscarUm(caminho, id) {
      return sb.from('modulo_docs').select('dados').eq('modulo', MODULO).eq('caminho', caminho).eq('id', id).maybeSingle()
        .then(function (r) {
          if (r.error) throw r.error;
          return r.data ? (r.data.dados || {}) : null;
        });
    }
    function mudou(p) {
      var row = p.eventType === 'DELETE' ? p.old : p['new'];
      if (!row || row.modulo !== MODULO || !row.caminho || !row.id) return;
      var caminho = row.caminho, id = row.id;
      if (!cache[caminho] && !pendentes[caminho]) return; // ninguém está olhando esta coleção
      if (p.eventType === 'DELETE') {
        if (pendentes[caminho]) pendentes[caminho].push([id, null]); else aplicar(caminho, id, null);
        return;
      }
      if (row.dados && typeof row.dados === 'object') {
        if (pendentes[caminho]) pendentes[caminho].push([id, row.dados]); else aplicar(caminho, id, row.dados);
        return;
      }
      buscarUm(caminho, id).then(function (d) { // registro grande: o aviso veio sem os dados
        if (pendentes[caminho]) pendentes[caminho].push([id, d]); else aplicar(caminho, id, d);
      }).catch(function () {});
    }
    function ligarTempoReal() {
      if (canal) return;
      canal = sb.channel('lev-modulo-' + MODULO + '-' + novoId().slice(0, 6))
        .on('postgres_changes', { event: '*', schema: 'public', table: 'modulo_docs', filter: 'modulo=eq.' + MODULO }, mudou)
        .on('postgres_changes', { event: 'DELETE', schema: 'public', table: 'modulo_docs' }, mudou)
        .subscribe(function (status) {
          if (status === 'SUBSCRIBED') { if (jaConectou) Object.keys(cache).forEach(recarregar); jaConectou = true; }
        });
    }
    var escondidoEm = 0;
    document.addEventListener('visibilitychange', function () {
      if (document.visibilityState === 'hidden') { escondidoEm = Date.now(); return; }
      if (escondidoEm && Date.now() - escondidoEm > 60000) Object.keys(cache).forEach(recarregar);
    });
    window.addEventListener('online', function () { Object.keys(cache).forEach(recarregar); });

    function carregar(caminho) {
      if (!carregando[caminho]) {
        ligarTempoReal();
        pendentes[caminho] = [];
        carregando[caminho] = lerTudo(caminho).then(function (rows) {
          cache[caminho] = {};
          rows.forEach(function (r) { cache[caminho][r.id] = r.dados || {}; });
          var fila = pendentes[caminho] || [];
          delete pendentes[caminho];
          fila.forEach(function (m) { if (m[1] == null) delete cache[caminho][m[0]]; else cache[caminho][m[0]] = m[1]; });
        }).catch(function (e) { delete carregando[caminho]; delete pendentes[caminho]; throw erroDe(e, 'leitura de ' + caminho); });
      }
      return carregando[caminho];
    }
    function rpc(nome, params) {
      return sb.rpc(nome, params).then(function (r) { if (r.error) throw r.error; return r.data; });
    }
    function limpo(dados) {
      if (dados == null || typeof dados !== 'object' || Array.isArray(dados)) throw { code: 'invalid_argument', message: 'Os dados precisam ser um objeto.' };
      return JSON.parse(JSON.stringify(dados));
    }
    function assinar(o, carregarP, err) {
      ouvintes.push(o);
      carregarP.then(function () {
        if (ouvintes.indexOf(o) < 0) return;
        o.pronto = true;
        try { o.cb(o.id !== undefined ? snapDoc(o.caminho, o.id) : snapConsulta(o.caminho, o.consulta)); } catch (e) { console.error(e); }
      }).catch(function (e) { if (err) { try { err(erroDe(e)); } catch (x) { console.error(x); } } });
      return function () { var i = ouvintes.indexOf(o); if (i >= 0) ouvintes.splice(i, 1); };
    }
    function semPronto() { return pronto; }

    function docRef(caminho, id) {
      id = id || novoId();
      return {
        id: id, path: caminho + '/' + id,
        parent: { id: dividir(caminho).slice(-1)[0], path: caminho },
        collection: function (sub) { return colRef(caminho + '/' + id + '/' + sub); },
        get: function () {
          return semPronto().then(function () { return buscarUm(caminho, id); })
            .then(function (d) { return snapDoc(caminho, id, d); }, function (e) { throw erroDe(e, 'leitura'); });
        },
        set: function (dados, opts) {
          var corpo;
          try { corpo = limpo(dados); } catch (e) { return Promise.reject(e); }
          return semPronto().then(function () {
            return rpc('modulo_gravar', { p_modulo: MODULO, p_caminho: caminho, p_id: id, p_dados: corpo, p_mesclar: !!(opts && opts.merge) });
          }).then(function (novo) { aplicar(caminho, id, novo || {}); }, function (e) { throw erroDe(e, 'gravação'); });
        },
        update: function (patch) {
          var corpo;
          try { corpo = limpo(patch); } catch (e) { return Promise.reject(e); }
          return semPronto().then(function () {
            return rpc('modulo_atualizar', { p_modulo: MODULO, p_caminho: caminho, p_id: id, p_dados: corpo });
          }).then(function (novo) { aplicar(caminho, id, novo || {}); }, function (e) { throw erroDe(e, 'alteração'); });
        },
        'delete': function () {
          return semPronto().then(function () {
            return sb.from('modulo_docs').delete().eq('modulo', MODULO).eq('caminho', caminho).eq('id', id);
          }).then(function (r) {
            if (r && r.error) throw r.error;
            aplicar(caminho, id, null);
          }).catch(function (e) { throw erroDe(e, 'exclusão'); });
        },
        onSnapshot: function (cb, err) {
          if (typeof cb === 'object' && cb && cb.next) { err = cb.error; cb = cb.next; }
          return assinar({ caminho: caminho, id: id, cb: cb, pronto: false }, semPronto().then(function () { return carregar(caminho); }), err);
        },
        // trava curta: só uma pessoa por vez mexe neste registro (numeração, saldo de estoque)
        acquire: function (o) {
          o = o || {};
          return semPronto().then(function () {
            return rpc('modulo_travar', { p_modulo: MODULO, p_chave: caminho + '/' + id, p_dono: String(o.holder || 'pagina'), p_ms: Math.round(o.ttlMs || 3000) });
          }).then(function (r) {
            return { acquired: !!(r && r.acquired), expiresAt: r && r.expiresAt ? new Date(r.expiresAt).toISOString() : null };
          }, function (e) { throw erroDe(e, 'trava'); });
        },
        release: function (o) {
          o = o || {};
          return semPronto().then(function () {
            return rpc('modulo_soltar', { p_modulo: MODULO, p_chave: caminho + '/' + id, p_dono: String(o.holder || 'pagina') });
          }).then(function (r) { return { released: !!r }; }, function (e) { throw erroDe(e, 'trava'); });
        }
      };
    }
    function consulta(caminho, q) {
      function com(mud) {
        return consulta(caminho, {
          filtros: (q.filtros || []).concat(mud.filtros || []),
          ordem: (q.ordem || []).concat(mud.ordem || []),
          limite: mud.limite != null ? mud.limite : q.limite
        });
      }
      return {
        where: function (c, op, v) { return com({ filtros: [{ campo: c, op: op, valor: v }] }); },
        orderBy: function (c, dir) { return com({ ordem: [{ campo: c, dir: dir === 'desc' ? 'desc' : 'asc' }] }); },
        limit: function (n) { return com({ limite: Math.max(0, n | 0) }); },
        get: function () {
          return semPronto().then(function () { return carregar(caminho); })
            .then(function () { return snapConsulta(caminho, q); }, function (e) { throw erroDe(e); });
        },
        onSnapshot: function (cb, err) {
          if (typeof cb === 'object' && cb && cb.next) { err = cb.error; cb = cb.next; }
          return assinar({ caminho: caminho, consulta: q, cb: cb, pronto: false }, semPronto().then(function () { return carregar(caminho); }), err);
        }
      };
    }
    function colRef(caminho) {
      var p = dividir(caminho).join('/');
      var q = consulta(p, { filtros: [], ordem: [], limite: null });
      q.id = dividir(p).slice(-1)[0];
      q.path = p;
      q.doc = function (id) { return docRef(p, id); };
      q.add = function (dados) { var ref = docRef(p); return ref.set(dados).then(function () { return ref; }); };
      return q;
    }
    return Object.freeze({
      collection: function (caminho) { return colRef(caminho); },
      doc: function (caminho) {
        var p = dividir(caminho);
        if (p.length < 2) throw { code: 'invalid_argument', message: 'Caminho de documento inválido: ' + caminho };
        return docRef(p.slice(0, -1).join('/'), p[p.length - 1]);
      },
      // funções do banco usadas pelos módulos novos (ex.: checklist que abre chamado na Manutenção)
      rpc: function (nome, params) {
        return semPronto().then(function () { return rpc(nome, params || {}); }).catch(function (e) { throw erroDe(e, nome); });
      }
    });
  }

  // ---------- quem está usando ----------
  function criarUsuario() {
    return Object.freeze({
      id: function () { return pronto.then(function () { return ident.uid; }); },
      me: function () { return pronto.then(function () { return { id: ident.uid, name: ident.nome || '', guest: false }; }); },
      can: function (nome) { return pronto.then(function () { return nome === 'data.write' ? true : null; }); },
      canEdit: function () { return pronto.then(function () { return ident.nivel === 'gerir'; }); },
      isOwner: function () { return pronto.then(function () { return ident.papel === 'mestre'; }); },
      profiles: function () { return Promise.resolve({}); },
      search: function () { return Promise.resolve([]); },
      // extras do LEVÍSSIMA (os módulos novos usam)
      nivel: function () { return pronto.then(function () { return ident.nivel; }); },
      nome: function () { return pronto.then(function () { return ident.nome || ''; }); },
      papel: function () { return pronto.then(function () { return ident.papel; }); }
    });
  }

  // ---------- arquivos (planilhas, PDF): baixa no navegador; no app do celular, salva e abre o "compartilhar" ----------
  function appNativo() { return !!(window.Capacitor && window.Capacitor.isNativePlatform && window.Capacitor.isNativePlatform()); }
  function pluginNativo(nome) { return appNativo() && window.Capacitor.Plugins ? window.Capacitor.Plugins[nome] : null; }
  function paraBlob(dados, nome) {
    if (dados instanceof Blob) return dados;
    var tipo = /\.csv$/i.test(nome) ? 'text/csv;charset=utf-8' : /\.json$/i.test(nome) ? 'application/json'
      : /\.pdf$/i.test(nome) ? 'application/pdf' : /\.xlsx$/i.test(nome) ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      : /\.(txt|md)$/i.test(nome) ? 'text/plain;charset=utf-8' : 'application/octet-stream';
    return new Blob([dados], { type: tipo });
  }
  function blobBase64(blob) {
    return new Promise(function (ok, falha) {
      var fr = new FileReader();
      fr.onload = function () { ok(String(fr.result).split(',')[1] || ''); };
      fr.onerror = falha;
      fr.readAsDataURL(blob);
    });
  }
  function criarDownloads() {
    return Object.freeze({
      save: function (o) {
        o = o || {};
        var nome = String(o.filename || 'arquivo').replace(/[\\/:*?"<>|]+/g, '-');
        var blob;
        try { blob = paraBlob(o.data, nome); } catch (e) { return Promise.reject({ code: 'invalid_argument', message: 'arquivo inválido' }); }
        var Fs = pluginNativo('Filesystem'), Sh = pluginNativo('Share');
        if (Fs && Sh) {
          return blobBase64(blob).then(function (b64) {
            return Fs.writeFile({ path: nome, data: b64, directory: 'CACHE' });
          }).then(function (res) {
            return Sh.share({ title: nome, url: res.uri, dialogTitle: 'Salvar ou enviar' });
          }).then(function () { return { saved: true }; }, function (e) {
            if (e && /cancel/i.test(String(e.message || e))) throw { code: 'declined', message: 'cancelado' };
            throw { code: 'unavailable', message: 'não foi possível salvar o arquivo' };
          });
        }
        var url = URL.createObjectURL(blob);
        var a = document.createElement('a');
        a.href = url; a.download = nome; a.style.display = 'none';
        document.body.appendChild(a); a.click(); document.body.removeChild(a);
        setTimeout(function () { URL.revokeObjectURL(url); }, 4000);
        return Promise.resolve({ saved: true });
      }
    });
  }

  var banco = null, usuario = null, downloads = null;
  window.claude = Object.freeze({
    use: function (nome) {
      if (nome === 'db') return pronto.then(function () { return banco || (banco = criarBanco()); });
      if (nome === 'user') return pronto.then(function () { return usuario || (usuario = criarUsuario()); });
      if (nome === 'downloads') return Promise.resolve(downloads || (downloads = criarDownloads()));
      return Promise.resolve(null);
    }
  });
  window.LEVISSIMA = Object.freeze({ modulo: MODULO, nomeModulo: NOME_MODULO, raiz: RAIZ, voltar: voltarAoInicio });

  iniciar();
})();
