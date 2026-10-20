/* LEVÍSSIMA · testes: Supabase de mentira (no lugar do supabase-js do CDN).
 *
 * Só para os testes automáticos (testes/*.js, com o Playwright). Tudo o que o app pede ao Supabase vai para
 * window.__fakeDb(op, args), uma função ligada pelo teste ao "banco" em memória do Node (testes/banco-fake.js), que é
 * o mesmo para todas as páginas e navegadores do teste. As mudanças voltam pelo window.__fakeEvento (o "tempo real").
 * O login fica no localStorage, na mesma chave do supabase-js de verdade (levissima-login).
 */
(function () {
  'use strict';
  function b64uJson(t) {
    try {
      var p = String(t || '').split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
      while (p.length % 4) p += '=';
      return JSON.parse(decodeURIComponent(escape(atob(p))));
    } catch (e) { return {}; }
  }
  var canais = []; // { table, cb }
  var chaveLogin = 'levissima-login';
  function minhaRef() {
    try { var s = JSON.parse(localStorage.getItem(chaveLogin) || 'null'); return s ? ((b64uJson(s.access_token).app_metadata || {}).ref || '') : ''; } catch (e) { return ''; }
  }
  // "tempo real": o banco do teste avisa cada página; aqui valem as mesmas regras de leitura do banco (RLS)
  window.__fakeEvento = function (table, tipo, novo, velho) {
    var eu = minhaRef(), row = novo || velho || {};
    if (table === 'chat_msgs' && !(row.de === eu || row.para === eu)) return;
    if (table === 'compromissos' && !(row.dono === eu || (row.participantes || []).indexOf(eu) >= 0)) return;
    canais.slice().forEach(function (c) { if (c.table === table) { try { c.cb({ eventType: tipo, new: novo || {}, old: velho || {} }); } catch (e) { console.error(e); } } });
  };
  function chamar(op, args) {
    if (typeof window.__fakeDb !== 'function') return Promise.reject(new Error('sem banco de teste'));
    return window.__fakeDb(op, args);
  }
  function createClient(url, key, opts) {
    chaveLogin = (opts && opts.auth && opts.auth.storageKey) || chaveLogin;
    var sk = chaveLogin, ouvintes = [];
    function lerSessao() { try { return JSON.parse(localStorage.getItem(sk) || 'null'); } catch (e) { return null; } }
    function token() { var s = lerSessao(); return s ? s.access_token : null; }
    function avisar(ev, s) { setTimeout(function () { ouvintes.slice().forEach(function (cb) { try { cb(ev, s); } catch (e) { console.error(e); } }); }, 0); }
    // outra aba saiu: como o supabase-js, avisa SIGNED_OUT
    window.addEventListener('storage', function (e) { if (e.key === sk && !e.newValue) avisar('SIGNED_OUT', null); });
    var auth = {
      getSession: function () { return Promise.resolve({ data: { session: lerSessao() }, error: null }); },
      setSession: function (t) {
        var c = b64uJson(t.access_token);
        var s = { access_token: t.access_token, refresh_token: t.refresh_token, user: { id: c.sub, app_metadata: c.app_metadata || {} } };
        localStorage.setItem(sk, JSON.stringify(s));
        avisar('SIGNED_IN', s);
        return Promise.resolve({ data: { session: s, user: s.user }, error: null });
      },
      signOut: function (o) {
        var tinha = !!lerSessao();
        chamar('log', { evento: 'signOut', escopo: (o && o.scope) || 'global', tinha: tinha }).catch(function () {});
        localStorage.removeItem(sk);
        if (tinha) avisar('SIGNED_OUT', null);
        return Promise.resolve({ error: null });
      },
      onAuthStateChange: function (cb) {
        ouvintes.push(cb);
        return { data: { subscription: { unsubscribe: function () { ouvintes = ouvintes.filter(function (x) { return x !== cb; }); } } } };
      }
    };
    function from(table) {
      var q = { table: table, op: 'select', filtros: [], ordem: null, faixa: null, single: false };
      var b = {
        select: function () { return b; },
        eq: function (c, v) { q.filtros.push([c, v]); return b; },
        order: function (c, o) { q.ordem = [c, !(o && o.ascending === false)]; return b; },
        range: function (a, z) { q.faixa = [a, z]; return b; },
        limit: function (n) { q.faixa = [0, n - 1]; return b; },
        maybeSingle: function () { q.single = true; return b; },
        single: function () { q.single = true; return b; },
        delete: function () { q.op = 'delete'; return b; },
        then: function (ok, falha) { return chamar('from', { q: q, token: token() }).then(ok, falha); }
      };
      return b;
    }
    function erroDe(r) { return r && r.erro ? { message: r.erro, code: r.codigo || 'P0001' } : null; }
    return {
      auth: auth,
      from: from,
      rpc: function (nome, params) {
        return chamar('rpc', { nome: nome, params: params || {}, token: token() }).then(function (r) {
          return { data: r ? r.data : null, error: erroDe(r) };
        });
      },
      functions: {
        invoke: function (nome, o) {
          return chamar('fn', { nome: nome, body: (o && o.body) || {}, token: token() }).then(function (r) {
            if (r && r.erro) { var j = { erro: r.erro }; return { data: null, error: { message: r.erro, context: { json: function () { return Promise.resolve(j); } } } }; }
            return { data: r ? r.data : null, error: null };
          });
        }
      },
      channel: function (nome) {
        var c = { nome: nome, subs: [] };
        c.on = function (tipo, filtro, cb) { var x = { table: filtro && filtro.table, cb: cb }; canais.push(x); c.subs.push(x); return c; };
        c.subscribe = function (cb) { if (cb) setTimeout(function () { cb('SUBSCRIBED'); }, 5); return c; };
        c.unsubscribe = function () { canais = canais.filter(function (x) { return c.subs.indexOf(x) < 0; }); return Promise.resolve('ok'); };
        return c;
      },
      removeChannel: function (c) { if (c && c.unsubscribe) c.unsubscribe(); return Promise.resolve('ok'); },
      realtime: { setAuth: function () {} },
      storage: {
        from: function () {
          var nada = function () { return Promise.resolve({ data: null, error: { message: 'sem storage no teste' } }); };
          return { upload: nada, createSignedUrl: nada, download: nada, remove: function () { return Promise.resolve({ data: [], error: null }); },
            createSignedUrls: function () { return Promise.resolve({ data: [], error: null }); }, list: function () { return Promise.resolve({ data: [], error: null }); },
            getPublicUrl: function () { return { data: { publicUrl: '' } }; } };
        }
      }
    };
  }
  window.supabase = { createClient: createClient };
})();
