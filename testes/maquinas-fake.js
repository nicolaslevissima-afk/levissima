/* LEVÍSSIMA · testes: as funções dos tablets das máquinas (migração 0054) simuladas sobre o banco de teste.
 * Mesmas regras principais: a máquina vem do acesso; operador da sessão; OP pela linha do tempo do PCP; trechos na
 * troca de OP; idempotência pelo id; duplicidade; etapa final vira entrada estimada no estoque depois de ligar
 * o apontamento pelas máquinas; paradas sem sobreposição; conferência e correção com histórico.
 */
'use strict';
function ligar(amb) {
  const b = amb.banco.b, sessoes = [];
  const iso = (ms) => new Date(ms).toISOString();
  const erro = (m) => ({ data: null, erro: m }); // mesmo formato do banco de teste
  const docs = (col) => Array.from(b.docs.values()).filter((r) => r.colecao === col);
  const gravar = (col, id, data) => { b.docs.set(col + '/' + id, { colecao: col, id, data }); return data; };
  function quem(token) { try { return (JSON.parse(Buffer.from(String(token).split('.')[1].replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8')).app_metadata) || {}; } catch (e) { return {}; } }
  function minha(eu) {
    if (eu.papel !== 'setor') return null;
    const cfg = (b.docs.get('mp-config/linhas-producao') || {}).data || {};
    for (const l of cfg.linhas || []) for (const m of l.maquinas || []) if (m.acesso && m.acesso === eu.ref) { const ll = Object.assign({}, l); delete ll.maquinas; return { linha: ll, maquina: m }; }
    return null;
  }
  function opEm(lid, t) {
    const ult = {};
    docs('producao-eventos').forEach((r) => { const e = r.data; if (e.linha !== lid || !['iniciar', 'retomar', 'pausar'].includes(e.tipo) || !e.opId) return; const em = Date.parse(e.em); if (em > t) return; if (!ult[e.opId] || em > ult[e.opId].em) ult[e.opId] = { em, tipo: e.tipo }; });
    let best = null;
    Object.keys(ult).forEach((id) => { const x = ult[id]; if (x.tipo === 'pausar') return; const o = b.docs.get('producao-ordens/' + id); if (!o) return; if (o.data.status === 'concluida' && Date.parse(o.data.concluidoEm || 0) <= t) return; if (!best || x.em > best.em) best = { em: x.em, id }; });
    return best ? best.id : null;
  }
  function opInfo(id) {
    const o = b.docs.get('producao-ordens/' + id); if (!o) return null;
    return { id, numero: o.data.numero, status: o.data.status, obs: o.data.obs || '', itens: (o.data.itens || []).filter((it) => Number(it.quantidade) > 0).map((it) => { const p = (b.docs.get('produtos/' + it.produtoId) || {}).data || {}; return { produtoId: it.produtoId, nome: p.nome || it.produtoNome || '', unidade: it.unidade || p.unidade || 'unidades', quantidade: Number(it.quantidade), unidadesPorPalete: p.unidadesPorPalete || null }; }) };
  }
  const regs = (mid) => docs('producao-maq').filter((r) => r.data.maquinaId === mid).map((r) => Object.assign({ id: r.id }, r.data));
  const RPC = {
    maq_contexto(p, eu) {
      const v = minha(eu); if (!v) return { data: { maquina: null } };
      const s = sessoes.filter((x) => x.acesso === eu.ref && !x.ate).pop();
      const op = opEm(v.linha.id, Date.now()), r = regs(v.maquina.id);
      const parada = r.filter((x) => x.tipo === 'parada' && !x.fim && x.estado !== 'anulado').sort((a, c) => String(c.ini).localeCompare(a.ini))[0] || null;
      const ultimos = r.slice().sort((a, c) => String(c.enviadoEm).localeCompare(a.enviadoEm)).slice(0, 15);
      const cont = r.filter((x) => x.tipo === 'producao' && x.estado !== 'anulado' && typeof x.contador === 'number').sort((a, c) => String(c.fim).localeCompare(a.fim))[0];
      const pend = [], base = Math.floor(Date.now() / 3600000) * 3600000;
      for (let h = 1; h <= 12; h++) {
        const a = base - h * 3600000, f = a + 3600000;
        if (!opEm(v.linha.id, a + 1800000)) continue;
        if (r.some((x) => x.tipo === 'producao' && x.estado !== 'anulado' && Date.parse(x.ini) < f && Date.parse(x.fim) > a)) continue;
        if (r.some((x) => x.tipo === 'parada' && x.estado !== 'anulado' && Date.parse(x.ini) <= a && (!x.fim || Date.parse(x.fim) >= f))) continue;
        pend.push({ ini: iso(a), fim: iso(f) });
      }
      return { data: { maquina: v.maquina, linha: v.linha, operador: s ? { membro: s.membro, nome: s.nome, desde: iso(s.desde) } : null, op: op ? opInfo(op) : null, parada, ultimos, ultimoContador: cont ? { contador: cont.contador, fim: cont.fim } : null, pendentes: pend, agora: iso(Date.now()) } };
    },
    maq_operador_entrar(p, eu) {
      if (!minha(eu)) return erro('maquina');
      if (p.p_pin !== '1234') return { data: { ok: false, restam: 3 } };
      sessoes.forEach((x) => { if (x.acesso === eu.ref && !x.ate) x.ate = Date.now(); });
      sessoes.push({ acesso: eu.ref, membro: 'm-carlos', nome: 'Carlos Operador', desde: Date.now() });
      return { data: { ok: true, membro: 'm-carlos', nome: 'Carlos Operador' } };
    },
    maq_operador_sair(p, eu) { sessoes.forEach((x) => { if (x.acesso === eu.ref && !x.ate) x.ate = Date.now(); }); return { data: { ok: true } }; },
    maq_segmentos(p, eu) {
      const v = minha(eu); if (!v) return erro('maquina');
      const ini = Date.parse(p.p_ini), fim = Date.parse(p.p_fim), pts = [ini];
      docs('producao-eventos').map((r) => Date.parse(r.data.em)).filter((t, i, arr) => arr.indexOf(t) === i).sort((a, c) => a - c)
        .forEach((t) => { if (t > ini && t < fim && t - pts[pts.length - 1] >= 60000 && fim - t >= 60000) pts.push(t); });
      pts.push(fim);
      const out = []; let ult;
      for (let i = 0; i < pts.length - 1; i++) { const op = opEm(v.linha.id, (pts[i] + pts[i + 1]) / 2); if (out.length && (op || '') === (ult || '')) out[out.length - 1].fim = iso(pts[i + 1]); else out.push({ ini: iso(pts[i]), fim: iso(pts[i + 1]), op: op ? opInfo(op) : null }); ult = op; }
      return { data: out };
    },
    maq_registrar(p0, eu) {
      const v = minha(eu); if (!v) return erro('maquina');
      const p = p0.p || {}, id = 'mq-' + String(p.id || '').replace(/[^A-Za-z0-9_-]/g, '');
      if (id.length < 11) return erro('dados');
      const ja = b.docs.get('producao-maq/' + id); if (ja) return { data: { ok: true, id, repetido: true, doc: Object.assign({ id }, ja.data) } };
      const s = sessoes.filter((x) => x.acesso === eu.ref && !x.ate).pop(); if (!s) return erro('operador');
      const m = v.maquina, l = v.linha, oper = { membro: s.membro, nome: s.nome }, agora = Date.now();
      if (p.tipo === 'producao') {
        const ini = Date.parse(p.ini), fim = Date.parse(p.fim);
        if (!(fim > ini) || fim - ini > 4 * 3600000) return erro('intervalo');
        if (fim > agora + 300000) return erro('futuro');
        if (docs('producao-eventos').some((r) => r.data.linha === l.id && Date.parse(r.data.em) > ini + 60000 && Date.parse(r.data.em) < fim - 60000)) return erro('segmentar');
        const op = opEm(l.id, (ini + fim) / 2), info = op ? opInfo(op) : null, item = info ? (info.itens.find((it) => it.produtoId === p.produtoId) || info.itens[0]) : null;
        let q = null, ant = null, reinicio = false, prim = false;
        if (m.modo === 'contador') { const c = Number(p.contador); ant = p.contadorIni != null ? Number(p.contadorIni) : null; if (ant == null) { const u = regs(m.id).filter((x) => x.tipo === 'producao' && typeof x.contador === 'number' && Date.parse(x.fim) <= ini + 60000).sort((a, c2) => Date.parse(c2.fim) - Date.parse(a.fim))[0]; ant = u ? u.contador : null; } if (ant == null) prim = true; else if (c >= ant) q = c - ant; else { q = c; reinicio = true; } }
        else { q = Number(p.quantidade); if (!(q >= 0)) return erro('quantidade'); }
        const dup = regs(m.id).some((x) => x.tipo === 'producao' && x.estado !== 'anulado' && Date.parse(x.ini) < fim - 60000 && Date.parse(x.fim) > ini + 60000);
        const doc = { tipo: 'producao', maquinaId: m.id, maquina: m.nome, linha: l.id, acesso: eu.ref, operador: oper, ini: iso(ini), fim: iso(fim), dia: p.dia || '', turno: p.turno || '',
          horaIni: new Date(ini).toISOString().slice(11, 16), horaFim: new Date(fim).toISOString().slice(11, 16), quantidade: q, unidade: m.unidade || '', modo: m.modo || 'intervalo', contador: m.modo === 'contador' ? Number(p.contador) : null, contadorAnterior: ant, reinicio, primeiraLeitura: prim,
          opId: op, opNumero: info ? info.numero : null, produtoId: item ? item.produtoId : null, produtoNome: item ? item.nome : null, marca: p.marca || null, final: !!m.producao, duplicado: dup, retro: agora - fim > 90 * 60000,
          estado: 'apontado', obs: '', criadoEm: p.criadoEm, enviadoEm: iso(agora) };
        gravar('producao-maq', id, doc);
        const desde = l.apontaMaquinas && l.apontaMaquinas.desde ? Date.parse(l.apontaMaquinas.desde) : null;
        if (m.producao && op && q > 0 && !dup && desde && ini >= desde && item && item.unidade === m.unidade) {
          const est = 'mqe-' + id.slice(3);
          gravar('estoque', est, { tipo: 'entrada', porHora: true, pendente: true, origem: 'maquina', maquina: m.nome, maquinaId: m.id, maqReg: id, opId: op, produtoId: item.produtoId, produtoNome: item.nome, unidade: item.unidade, marca: p.marca || null, quantidade: Math.round(q), data: p.dia, hora: doc.horaIni, horaFim: doc.horaFim, linha: l.id, turno: p.turno || '', maquinas: {}, paradas: [], minutosParados: 0, obs: '', lider: { nome: oper.nome, ref: 'membro:' + oper.membro }, em: iso(agora), criadoEm: iso(agora) });
          doc.estoqueId = est; gravar('producao-maq', id, doc);
        }
        return { data: { ok: true, id, doc: Object.assign({ id }, doc) } };
      }
      if (p.tipo === 'parada') {
        const ini = p.ini ? Date.parse(p.ini) : agora, fim = p.fim ? Date.parse(p.fim) : null;
        if (!p.motivo) return erro('motivo');
        if (regs(m.id).some((x) => x.tipo === 'parada' && x.estado !== 'anulado' && Date.parse(x.ini) < (fim || Infinity) && (x.fim ? Date.parse(x.fim) : Infinity) > ini)) return erro('parada_sobreposta');
        const doc = { tipo: 'parada', maquinaId: m.id, maquina: m.nome, linha: l.id, acesso: eu.ref, operador: oper, ini: iso(ini), fim: fim ? iso(fim) : '', dia: p.dia || '', turno: p.turno || '', motivo: p.motivo, escopo: p.escopo === 'linha' ? 'linha' : 'maquina', estado: 'apontado', obs: p.obs || '', criadoEm: p.criadoEm, enviadoEm: iso(agora) };
        gravar('producao-maq', id, doc); return { data: { ok: true, id, doc: Object.assign({ id }, doc) } };
      }
      if (p.tipo === 'retomada') {
        const par = regs(m.id).filter((x) => x.tipo === 'parada' && !x.fim && x.estado !== 'anulado' && (!p.paradaId || x.id === p.paradaId)).sort((a, c) => String(c.ini).localeCompare(a.ini))[0];
        if (!par) return erro('sem_parada');
        const fim = p.fim ? Date.parse(p.fim) : agora;
        const pd = Object.assign({}, b.docs.get('producao-maq/' + par.id).data, { fim: iso(fim), retomadaPor: oper }); gravar('producao-maq', par.id, pd);
        const doc = { tipo: 'retomada', maquinaId: m.id, maquina: m.nome, linha: l.id, paradaId: par.id, operador: oper, ini: par.ini, fim: iso(fim), motivo: par.motivo, dia: p.dia || '', estado: 'apontado', criadoEm: p.criadoEm, enviadoEm: iso(agora) };
        gravar('producao-maq', id, doc); return { data: { ok: true, id, doc: Object.assign({ id }, doc) } };
      }
      return erro('tipo');
    },
    maq_painel(p, eu) {
      if (!['mestre', 'equipe'].includes(eu.papel)) return erro('permissao');
      const todos = docs('producao-maq').map((r) => Object.assign({ id: r.id }, r.data));
      const registros = todos.filter((r) => (r.dia >= p.p_de && r.dia <= p.p_ate) || (r.tipo === 'parada' && !r.fim && r.estado !== 'anulado')).sort((a, c) => String(a.ini).localeCompare(c.ini));
      const ultimos = {}; todos.slice().sort((a, c) => String(c.enviadoEm).localeCompare(a.enviadoEm)).forEach((r) => { if (r.maquinaId && !ultimos[r.maquinaId]) ultimos[r.maquinaId] = { id: r.id, tipo: r.tipo, ini: r.ini, fim: r.fim, quantidade: r.quantidade, unidade: r.unidade, enviadoEm: r.enviadoEm }; });
      const operadores = {}; sessoes.filter((x) => !x.ate).forEach((x) => { operadores[x.acesso] = { nome: x.nome, desde: iso(x.desde) }; });
      return { data: { registros, ultimos, operadores, podeCorrigir: eu.papel === 'mestre', agora: iso(Date.now()) } };
    },
    maq_corrigir(p, eu) {
      if (eu.papel !== 'mestre') return erro('permissao');
      if (!String(p.p_motivo || '').trim()) return erro('motivo');
      const r = b.docs.get('producao-maq/' + p.p_id); if (!r) return erro('nao_encontrado');
      const set = Object.assign({}, p.p_patch);
      if ('opId' in set) { const info = set.opId ? opInfo(set.opId) : null; set.opNumero = info ? info.numero : null; if (info) { set.produtoId = info.itens[0].produtoId; set.produtoNome = info.itens[0].nome; } }
      const de = {}; Object.keys(set).forEach((k) => { de[k] = r.data[k] === undefined ? null : r.data[k]; });
      const novo = Object.assign({}, r.data, set, { estado: set.estado || (r.data.estado === 'validado' ? 'apontado' : r.data.estado), historico: (r.data.historico || []).concat([{ em: iso(Date.now()), por: { nome: eu.nome, ref: eu.ref }, motivo: p.p_motivo, de, para: set }]) });
      if (novo.estoqueId) { const e = b.docs.get('estoque/' + novo.estoqueId); if (e && !e.data.pendente) return erro('confirmado'); if (e) { if (novo.estado === 'anulado' || !novo.opId) { b.docs.delete('estoque/' + novo.estoqueId); delete novo.estoqueId; } else gravar('estoque', novo.estoqueId, Object.assign({}, e.data, { quantidade: Math.round(novo.quantidade), opId: novo.opId })); } }
      gravar('producao-maq', p.p_id, novo);
      return { data: { ok: true, doc: Object.assign({ id: p.p_id }, novo) } };
    },
    maq_validar(p, eu) {
      if (eu.papel !== 'mestre') return erro('permissao');
      let n = 0; (p.p_ids || []).forEach((id) => { const r = b.docs.get('producao-maq/' + id); if (r && r.data.estado !== 'anulado') { gravar('producao-maq', id, Object.assign({}, r.data, { estado: 'validado', validadoPor: { nome: eu.nome } })); n++; } });
      return { data: { ok: true, validados: n } };
    }
  };
  const ctl = { sessoes, semRede: false };
  const orig = amb.banco.handle;
  amb.banco.handle = function(source, op, args) {
    if (op === 'rpc' && args && RPC[args.nome]) {
      if (source && source.page) b.paginas.add(source.page);
      if (ctl.semRede) return { data: null, erro: 'TypeError: Failed to fetch' }; // sem internet no tablet
      return RPC[args.nome](args.params || {}, quem(args.token));
    }
    return orig(source, op, args);
  };
  return ctl;
}
module.exports = { ligar };
